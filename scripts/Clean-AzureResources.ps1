param(
    [switch] $IncludeResourceGroups,
    [switch] $includeAadApps
)

if ($IncludeResourceGroups) {
    $rgs = az.cmd group list | ConvertFrom-Json
    $rgs | ForEach-Object {
        $rgName = $_ 
        az group delete $rgName
    }
}

if ($includeAadApps) {
    $spns = az ad app list | ConvertFrom-Json
}