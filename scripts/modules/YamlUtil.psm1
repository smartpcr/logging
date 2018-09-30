
Install-Module powershell-yaml
    

function Get-EnvironmentSettings {
    param(
        [string] $EnvName = "dev",
        [string] $EnvRootFolder
    )
    
    $values = Get-Content (Join-Path $EnvRootFolder "values.yaml") -Raw | ConvertFrom-Yaml
    if ($EnvName) {
        $envFolder = Join-Path $EnvRootFolder $EnvName
        $envValueYamlFile =  Join-Path $envFolder "values.yaml"
        if (Test-Path $envValueYamlFile) {
            $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml
            Copy-YamlObject -fromObj $envValues -toObj $values
        }
    }

    $bootstrapTemplate = Get-Content "$EnvRootFolder\bootstrap.yaml" -Raw
    $bootstrapTemplate = Set-Values -valueTemplate $bootstrapTemplate -settings $values
    $bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml

    return $bootstrapValues
}


function Copy-YamlObject {
    param (
        [object] $fromObj,
        [object] $toObj
    )
    
    $fromObj.Keys | ForEach-Object {
        $name = $_ 
        $value = $fromObj.Item($name)
    
        if ($value) {
            $tgtName = $toObj.Keys | Where-Object { $_ -eq $name }
            if (!$tgtName) {
                $toObj.Add($name, $value)
            }
            else {
                $tgtValue = $toObj.Item($tgtName)
                if ($value -is [string] -or $value -is [int] -or $value -is [bool]) {
                    if ($value -ne $tgtValue) {
                        $toObj[$tgtName] = $value
                    }
                }
                else {
                    Copy-YamlObject -fromObj $value -toObj $tgtValue
                }
            }
        }
    }
}

function Set-Values {
    param (
        [object] $valueTemplate,
        [object] $settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.(\w+)\s*\}\}")
    $match = $regex.Match($valueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value
        $found = $settings.Keys | Where-Object { $_ -eq $searchKey }
        if ($found) {
            $replaceValue = $settings.Item($found)
            $valueTemplate = ([string]$valueTemplate).Replace($toBeReplaced, $replaceValue)
            $match = $regex.Match($valueTemplate)
        }
        else {
            $match = $match.NextMatch()
        }
    }

    return $valueTemplate
}

function ReplaceValuesInYamlFile {
    param(
        [string] $YamlFile,
        [string] $PlaceHolder,
        [string] $Value 
    )

    $content = ""
    if (Test-Path $YamlFile) {
        $content = Get-Content $YamlFile 
    }

    $pattern = "{{ .Values.$PlaceHolder }}"
    $buffer = New-Object System.Text.StringBuilder
    $content | ForEach-Object {
        $line = $_ 
        if ($line) {
            $line = $line.Replace($pattern, $Value)
            $buffer.AppendLine($line) | Out-Null
        }
    }
    $buffer.AppendLine($replaceValue) | Out-Null
    $buffer.ToString() | Out-File $YamlFile -Encoding ascii
}