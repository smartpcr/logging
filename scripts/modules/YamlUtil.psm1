

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

Import-Module "$scriptFolder\Modules\powershell-yaml\powershell-yaml.psm1" -Force

function Get-EnvironmentSettings {
    param(
        [string] $EnvName = "dev",
        [string] $SpaceName = "xd",
        [string] $EnvRootFolder
    )
    
    $valuesOverride = Get-Content (Join-Path $EnvRootFolder "values.yaml") -Raw | ConvertFrom-Yaml2
    if ($EnvName) {
        $envFolder = Join-Path $EnvRootFolder $EnvName
        $envValueYamlFile = Join-Path $envFolder "values.yaml"
        if (Test-Path $envValueYamlFile) {
            $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml2
            Copy-YamlObject -fromObj $envValues -toObj $valuesOverride
        }

        if ($SpaceName) {
            $spaceFolder = Join-Path $envFolder $SpaceName 
            $spaceValueYamlFile = Join-Path $spaceFolder "values.yaml"
            if (Test-Path $spaceValueYamlFile) {
                $spaceValues = Get-Content $spaceValueYamlFile -Raw | ConvertFrom-Yaml2
                Copy-YamlObject -fromObj $spaceValues -toObj $valuesOverride
            }
        }
    }

    $bootstrapTemplate = Get-Content "$EnvRootFolder\env.yaml" -Raw
    $bootstrapTemplate = Set-YamlValues -valueTemplate $bootstrapTemplate -settings $valuesOverride
    $bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml2

    $propertiesOverride = GetProperties -subject $valuesOverride
    $targetProperties = GetProperties -subject $bootstrapValues
    $propertiesOverride | ForEach-Object {
        $propOverride = $_ 
        $targetPropFound = $targetProperties | Where-Object { $_ -eq $propOverride }
        if ($targetPropFound) {
            $newValue = GetPropertyValue -subject $valuesOverride -propertyPath $targetPropFound
            $existingValue = GetPropertyValue -subject $bootstrapValues -propertyPath $targetPropFound
            if ($null -ne $newValue -and $existingValue -ne $newValue) {
                SetPropertyValue -targetObject $bootstrapValues -propertyPath $targetPropFound -propertyValue $newValue
            }
        }
    }

    return $bootstrapValues
}


function Copy-YamlObject {
    param (
        [object] $fromObj,
        [object] $toObj
    )
    
    # handles array assignment
    if ($fromObj.GetType().IsGenericType -and $toObj.GetType().IsGenericType) {
        $toObj = $fromObj
        return 
    }

    $fromObj.Keys | ForEach-Object {
        $name = $_ 
        $value = $fromObj.Item($name)
    
        if ($value) {
            $tgtName = $toObj.Keys | Where-Object { $_ -eq $name }
            if (!$tgtName) {
                $toObj.Add($name, $value) | Out-Null
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

function Set-YamlValues {
    param (
        [string] $valueTemplate,
        [object] $settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.([a-zA-Z\.0-9_]+)\s*\}\}")
    $replacements = New-Object System.Collections.ArrayList
    $match = $regex.Match($valueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value

        $found = GetPropertyValue -subject $settings -propertyPath $searchKey
        if ($found) {
            if ($found -is [string] -or $found -is [int] -or $found -is [bool]) {
                $replaceValue = $found.ToString()
                $replacements.Add(@{
                        oldValue = $toBeReplaced
                        newValue = $replaceValue
                    }) | Out-Null
            }
            else {
                Write-Warning "Invalid value for path '$searchKey': $found"
            }
        }
        else {
            Write-Warning "Unable to find value with path '$searchKey'"
        }
        
        $match = $match.NextMatch()
    }
    
    $replacements | ForEach-Object {
        $oldValue = $_.oldValue 
        $newValue = $_.newValue 
        $valueTemplate = $valueTemplate.Replace($oldValue, $newValue)
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
    
    $buffer.ToString() | Out-File $YamlFile -Encoding ascii
}

function GetPropertyValue {
    param(
        [object]$subject,
        [string]$propertyPath
    )

    $propNames = $propertyPath.Split(".")
    $currentObject = $subject
    $propnames | ForEach-Object {
        $propName = $_ 
        if ($currentObject.ContainsKey($propName)) {
            $currentObject = $currentObject[$propName]
        }
        else {
            return $null 
        }
    }

    return $currentObject
}

function GetProperties {
    param(
        [object] $subject,
        [string] $parentPropName
    )

    $props = New-Object System.Collections.ArrayList
    $subject.Keys | ForEach-Object {
        $currentPropName = $_ 
        $value = $subject[$currentPropName]

        if ($value) {
            $propName = $currentPropName
            if ($null -ne $parentPropName -and $parentPropName.Length -gt 0) {
                $propName = $parentPropName + "." + $currentPropName
            }
            
            if (IsPrimitiveValue -inputValue $value) {
                $props.Add($propName) | Out-Null
            }
            else {
                $nestedProps = GetProperties -subject $value -parentPropName $propName
                if ($nestedProps -and $nestedProps.Count -gt 0) {
                    $nestedProps | ForEach-Object {
                        $props.Add($_) | Out-Null
                    }
                }
            }
        }
    }

    return $props 
}

function IsPrimitiveValue {
    param([object] $inputValue) 

    if ($null -eq $inputValue) {
        return $true
    }

    $type = $inputValue.GetType()
    if ($type.IsPrimitive -or $type.IsEnum -or $type.Name -ieq "string") {
        return $true
    }

    return $false;
}

function SetPropertyValue {
    param(
        [object] $targetObject,
        [string] $propertyPath,
        [object] $propertyValue 
    )
    
    if ($null -eq $targetObject) {
        return
    }

    $propNames = $propertyPath.Split(".")
    $currentValue = $targetObject 
    $index = 0
    while ($index -lt $propNames.Count) {
        $propName = $propNames[$index]

        if ($index -eq $propNames.Count - 1) {
            $oldValue = $currentValue[$propName]
            $currentValue[$propName] = $propertyValue
            Write-Host "`tChange value for property '$propertyPath' from '$oldValue' to '$propertyValue'" -ForegroundColor White
            return 
        }
        else {
            $currentValue = $currentValue[$propName]
            if ($null -eq $currentValue) {
                Write-Warning "Unable to find property with path '$propertyPath'"
                return
            }
        }

        $index++
    }
}