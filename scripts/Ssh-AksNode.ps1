param(
    [string] $EnvName = "dev3",
    [string] $NodeName = "aks-nodepool1-33901137-0"
)


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | Out-Null
$kubeContextName = "$(kubectl config current-context)" 
LogStep -Step 1 -Message "You are now connected to kubenetes context: '$kubeContextName'" 


LogStep -Step 2 "Retrieve ip config selected vm"
$nodeResourceGroup = "$(az aks show --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName) --query nodeResourceGroup -o tsv)"
$vm = az vm show -g $nodeResourceGroup -n $NodeName | ConvertFrom-Json
[string]$pipId = $vm.networkProfile.networkInterfaces.id
$nicName = $pipId.Substring($pipId.LastIndexOf("/") + 1)
$ipConfig = az network nic ip-config list --nic-name $nicName -g $nodeResourceGroup | ConvertFrom-Json


LogStep -Step 3 -Message "Setup public IP for selected node"
$publicIpName = "jumpbox"
az network public-ip create -g $nodeResourceGroup -n $publicIpName | Out-Null
az network nic ip-config update -g $nodeResourceGroup --nic-name $nicName --name $ipConfig.name --public-ip-address $publicIpName | Out-Null
$pip = az network public-ip show -g $nodeResourceGroup -n $publicIpName | ConvertFrom-Json

<# in case you lose ssh key file 
$password = Read-Host "Enter user password"
az vm user update `
    --resource-group $nodeResourceGroup `
    --name $NodeName `
    --username azureuser `
    --password $password

#>
  
ssh "$($bootstrapValues.aks.adminUsername)@$($pip.ipAddress)"


<# remove pip 
az network public-ip delete -g $nodeResourceGroup -n $publicIpName
#>