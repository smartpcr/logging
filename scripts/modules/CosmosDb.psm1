# helper functions for using the DocumentDB REST API.

function GetCosmosDbAccountKey() {
    param(
        [string]$AccountName,
        [string]$ResourceGroupName
    )

    $dbAcctKeys = az cosmosdb list-keys --name $AccountName --resource-group $ResourceGroupName | ConvertFrom-Json
    return $dbAcctKeys.primaryMasterKey
}

function EnsureCosmosDbAccount() {
    param(
        [string]$AccountName,
        [ValidateSet("SQL", "Gremlin", "Mongo", "Cassandra", "Table")]
        [string]$API,
        [string]$ResourceGroupName,
        [string]$Location
    )

    $dbAcct = az cosmosdb list --query "[?name=='$AccountName']" | ConvertFrom-Json
    if (!$dbAcct) {
        if ($API -eq "Gremlin") {
            Write-Host "Creating cosmosDB account $AccountName with gremlin api..."
            az cosmosdb create `
                --resource-group $ResourceGroupName `
                --name $AccountName `
                --capabilities EnableGremlin `
                --locations $Location=0 `
                --default-consistency-level "Session" 
        }
        elseif ($API -eq "Mongo") {
            Write-Host "Creating cosmosDB account $AccountName with mongodb api..."
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --default-consistency-level ConsistentPrefix --kind MongoDB --locations $Location=0 | Out-Null
        }
        elseif ($API -eq "Cassandra") {
            Write-Host "Creating cosmosDB account $AccountName with cassandra api..."
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --kind MongoDB --locations $Location=0 --capabilities EnableCassandra | Out-Null
        }
        elseif ($API -eq "Table") {
            Write-Host "Creating cosmosDB account $AccountName with table api..."
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --kind MongoDB --locations $Location=0 --capabilities EnableTable | Out-Null
        }
        else {
            Write-Host "Creating cosmosDB account $AccountName with sql api..."
            az cosmosdb create --name $AccountName --resource-group $ResourceGroupName --default-consistency-level Session --kind GlobalDocumentDB --locations $Location=0 | Out-Null
        }
    }
    else {
        Write-Host "CosmosDB account $AccountName is already created."
    }
}

function EnsureCollectionExists() {
    param(
        [string]$AccountName,
        [string]$ResourceGroupName,
        [string]$DbName,
        [string]$CollectionName,
        [string]$CosmosDbKey,
        [int]$Throughput = 1000
    )

    $found = az cosmosdb collection show --collection-name $CollectionName --db-name $DbName --resource-group $ResourceGroupName --url-connection "https://$AccountName.documents.azure.com:443/" --key $CosmosDbKey
    if (!$found) {
        az cosmosdb collection create --collection-name $CollectionName --db-name $DbName --resource-group $ResourceGroupName --name $AccountName --throughput $Throughput | Out-Null
    }
}

function EnsureDatabaseExists($Endpoint, $MasterKey, $DatabaseName) {
    $uri = CombineUris $Endpoint "/dbs"
    $headers = BuildHeaders -verb POST -resType dbs -masterkey $MasterKey
    try {
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body (@{id = $DatabaseName} | ConvertTo-Json)
    }
    catch {
        if ($_.Exception.Response.StatusCode -ne 409) {
            throw
        }
        # else already created
    }
}

function CreateCollection($Endpoint, $MasterKey, $DatabaseName, $CollectionName, $PartitionKey, $Throughput = 1000) {
    $uri = CombineUris $Endpoint "/dbs/$DatabaseName/colls"
    $headers = BuildHeaders -verb POST -resType colls -resourceId "dbs/$DatabaseName" -masterkey $MasterKey -throughput $Throughput

    $collectionJson = BuildDefaultCollection -CollectionName $CollectionName -PartitionKey $PartitionKey
    Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $collectionJson
}

function RemoveCollection($Endpoint, $MasterKey, $DatabaseName, $CollectionName) {
    $uri = CombineUris $Endpoint "/dbs/$DatabaseName/colls/$CollectionName"
    $headers = BuildHeaders -verb DELETE -resType colls -resourceId "dbs/$DatabaseName/colls/$CollectionName" -masterkey $MasterKey
    
    try {
        Invoke-RestMethod -Uri $uri -Method Delete -Headers $headers
    }
    catch {
        if ($_.Exception.Response.StatusCode -ne 404) {
            Write-Warning "Unable to delete collection $CollectionName"
            throw
        }
    }
}

function EnsureDocumentExists($Endpoint, $MasterKey, $DatabaseName, $CollectionName, $Document) {
    $uri = CombineUris $Endpoint "/dbs/$DatabaseName/colls/$CollectionName/docs"
    $resourceId = "dbs/$DatabaseName/colls/$CollectionName"
    $headers = BuildHeaders -verb POST -resType docs -resourceId $resourceId -masterkey $MasterKey
    $headers.Add("x-ms-documentdb-is-upsert", "true")
    $response = Invoke-RestMethod $uri -Method Post -Body $Document -ContentType "application/json" -Headers $headers
    return $response
}

function GetKey($Verb, $ResourceId, $ResourceType, $Date, $masterKey) {
    $keyBytes = [System.Convert]::FromBase64String($masterKey) 
    $text = "$($Verb.ToLowerInvariant())`n$($ResourceType.ToLowerInvariant())`n$($ResourceId)`n$($Date.ToLowerInvariant())`n`n"
    $body = [Text.Encoding]::UTF8.GetBytes($text)
    $hmacsha = new-object -TypeName System.Security.Cryptography.HMACSHA256 -ArgumentList (, $keyBytes) 
    $hash = $hmacsha.ComputeHash($body)
    $signature = [System.Convert]::ToBase64String($hash)
    [System.Web.HttpUtility]::UrlEncode("type=master&ver=1.0&sig=$signature")
}

function BuildHeaders($verb = "get", $resType, $resourceId, $masterKey, $throughput) {
    $apiDate = GetUTCDate
    $authz = GetKey -Verb $verb -ResourceType $resType -ResourceId $resourceId -Date $apiDate -masterKey $masterKey

    if ($throughput -and $throughput -ge 400 -and $throughput -le 250000) {
        return @{
            Authorization           = $authz;
            "x-ms-version"          = "2015-12-16";
            "x-ms-date"             = $apiDate;
            "x-ms-offer-throughput" = $throughput
        };
    }
    return @{
        Authorization  = $authz;
        "x-ms-version" = "2015-12-16";
        "x-ms-date"    = $apiDate
    }
}

function GetUTCDate() {
    $date = [System.DateTime]::UtcNow
    return $date.ToString("r", [System.Globalization.CultureInfo]::InvariantCulture);
}

function CombineUris($base, $relative) {
    return New-Object System.Uri -ArgumentList (New-Object System.Uri -ArgumentList $base), $relative
}

function BuildDefaultCollection($CollectionName, $PartitionKey) {
    if ($PartitionKey) {
        $collectionJson = @"
        {  
            "id": "$($CollectionName)",  
            "indexingPolicy": {  
              "indexingMode": "consistent",  
              "automatic": true,  
              "includedPaths": [  
                {  
                  "path": "/*",  
                  "indexes": [  
                    {  
                      "kind": "Hash",  
                      "dataType": "String",  
                      "precision": 3  
                    },  
                    {  
                      "kind": "Range",  
                      "dataType": "Number",  
                      "precision": -1  
                    }  
                  ]  
                }  
              ],  
              "excludedPaths": []  
            },  
            "partitionKey": {  
              "paths": [  
                "/$($PartitionKey)"  
              ],  
              "kind": "Hash"  
            }
          }  
"@
        return $collectionJson
    }
    else {
        return (@{id = $CollectionName} | ConvertTo-Json)
    }
}