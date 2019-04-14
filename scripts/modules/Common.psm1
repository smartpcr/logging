
function Test-IsAdmin {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = new-object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $isAdmin = $prp.IsInRole($adm)
    return $isAdmin
}

function Test-NetCoreInstalled () {
    try {
        $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
        $isInstalled = $false
        if ($dotnetCmd) {
            $isInstalled = Test-Path($dotnetCmd.Source)
        }
        return $isInstalled
    }
    catch {
        return $false 
    }
}

function Test-AzureCliInstalled() {
    try {
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if ($azCmd) {
            $azVersionConent = az --version
            $azVersionString = $azVersionConent[0]
            if ($azVersionString -match "\(([\.0-9]+)\)") {
                $version = $matches[1]
                $currentVersion = [System.Version]::new($version)
                $requiredVersion = [System.Version]::new("2.0.36") # aks enable-rbac is introduced in this version
                if ($currentVersion -lt $requiredVersion) {
                    return $false
                }
            }
            else {
                return $false 
            }
            return Test-Path $azCmd.Source 
        }
    }
    catch {}
    return $false 
}

function Test-ChocoInstalled() {
    try {
        $chocoVersion = Invoke-Expression "choco -v" -ErrorAction SilentlyContinue
        return ($chocoVersion -ne $null)
    }
    catch {}
    return $false 
}

function Test-DockerInstalled() {
    try {
        $dockerVer = Invoke-Expression "docker --version" -ErrorAction SilentlyContinue
        return ($dockerVer -ne $null)
    }
    catch {}
    return $false 
}

function Get-WindowsVersion {
    (Get-WmiObject win32_operatingsystem).caption
    #(Get-WmiObject -class Win32_OperatingSystem).Version
}

function Install-Docker() {
    param(
        [switch]$UseWindowsContainer
    )
    $winVer = Get-WindowsVersion
    if (($winVer -like "*Windows Server 2016*") -or ($winVer -like "*Windows Server 2019*")) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        if ($UseWindowsContainer) {
            Install-Module -Name DockerMsftProvider -Force
            Install-Package -Name docker -ProviderName DockerMsftProvider -Force
        }
        else {
            Uninstall-Package -Name docker -ProviderName  DockerMSFTProvider -Force 
            Install-Module -Name DockerProvider -Force
            Install-Package Docker -ProviderName DockerProvider -RequiredVersion preview -Force
        }
        # install docker-compose 
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $dockerComposeVersion = "1.23.2"
        $dockerComposeInstallFile = "$Env:ProgramFiles\docker\docker-compose.exe"
        Invoke-WebRequest "https://github.com/docker/compose/releases/download/$dockerComposeVersion/docker-compose-Windows-x86_64.exe" -UseBasicParsing -OutFile $dockerComposeInstallFile
    }
    else {
        Write-Host "Installing docker ce for windows.."
        $dockerForWindow = "https://download.docker.com/win/stable/Docker%20for%20Windows%20Installer.exe"
        $tempFile = "C:\users\$env:username\downloads\Docker for Windows Installer.exe"
        $webClient = New-Object System.Net.WebClient
        $webClient.DownloadFile($dockerForWindow, $tempFile)
        Start-Process $tempFile -Wait 
        Remove-Item $tempFile -Force 
    }
}


function InstallDevSpace() {
    $devSpaceCmd = Get-Command devspace -ErrorAction SilentlyContinue
    if (!$devSpaceCmd) {
        mkdir -Force "$Env:APPDATA\devspace" | Out-Null 
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]'Tls,Tls11,Tls12';
        Invoke-WebRequest -UseBasicParsing ((Invoke-WebRequest -URI "https://github.com/devspace-cloud/devspace/releases/latest" -UseBasicParsing).Content -replace "(?ms).*`"([^`"]*devspace-windows-amd64.exe)`".*", "https://github.com/`$1") -o $Env:APPDATA\devspace\devspace.exe; 
        & "$Env:APPDATA\devspace\devspace.exe" "install"; $env:Path = (Get-ItemProperty -Path HKCU:\Environment -Name Path).Path
    }
    else {
        Write-Host "devspace is already installed." -ForegroundColor Yellow 
    }
}

function InstallPulumi() {
    $pulumiCommand = Get-Command pulumi -ErrorAction SilentlyContinue
    if (!$pulumiCommand) {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://get.pulumi.com/install.ps1'))
        $PATH = [System.Environment]::GetEnvironmentVariable("PATH", "USER")
        $pulumiBinPath = "$($ENV:USERPROFILE)\.pulumi\bin"
        if (-not $PATH.Contains($pulumiBinPath)) {
            $PATH += ";$pulumiBinPath"
            [System.Environment]::SetEnvironmentVariable("PATH", $PATH, "USER")
        }
    }
    else {
        Write-Host "pulumi cli is already installed." -ForegroundColor Yellow
    }
}