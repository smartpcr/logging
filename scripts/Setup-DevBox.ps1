<#
    This script setup devbox on windows
    1) install chocolate
    2) install .net core sdk 2.1
    3) install azure cli 
    4) install docker (make sure to check "Expose daemon on tcp://localhost:2375 without TLS")
    6) install windows subsystem for linux (WSL)
    7) install kubectl (kubernetes cli)
    8) install helm and draft
    9) install minikube

    there are two options to setup minikube, one is via hyper-v, the other is via virtualbox
    9a) disable hyper-v feature
    10a) install virtualbox
    11a) start minikube

    9b) enable hyper-v feature
    10b) fix hyper-v network
    11a) start minikube
#>

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\modules\common.psm1" -Force

if (-not (Test-IsAdmin)) {
    throw "You need to run this script as administrator"
}

# install chocolatey 
if (-not (Test-ChocoInstalled)) {
    Write-Host "Installing chocolate..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; 
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

    choco install firacode -Y
}
else {
    Write-Host "Chocolate already installed"
}

# install .net core
if (-not (Test-NetCoreInstalled)) {
    Write-Host "Installing .net core..."
    $netSdkDownloadLink = "https://download.microsoft.com/download/D/0/4/D04C5489-278D-4C11-9BD3-6128472A7626/dotnet-sdk-2.1.301-win-gs-x64.exe"
    $tempFile = "C:\users\$env:username\downloads\dotnetsdk.exe"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($netSdkDownloadLink, $tempFile)
    Start-Process $tempFile -Wait 
    Remove-Item $tempFile -Force 
}
else {
    Write-Host ".net core is already installed"
}

if (-not (Test-AzureCliInstalled)) {
    Write-Host "Installing azure cli..."
    $azureCliDownloadLink = "https://aka.ms/installazurecliwindows"
    $tempFile = "C:\users\$env:username\downloads\azcli.msi"
    $webClient = New-Object System.Net.WebClient
    $webClient.DownloadFile($azureCliDownloadLink, $tempFile)
    Start-Process $tempFile -Wait 
    Remove-Item $tempFile -Force 
}
else {
    Write-Host "az cli is already installed"
}

if (-not (Test-DockerInstalled)) {
    Install-Docker 
    Restart-Computer -Force
}
else {
    Write-Host "Docker is already installed"
}

# instead of using hyper-v, use windows-linux-subsystem
Disable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All

Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
Invoke-WebRequest -Uri https://aka.ms/wsl-ubuntu-1604 -OutFile Ubuntu.appx -UseBasicParsing

# kubectl must be installed before minikube
Write-Host "Installing kubectl..."
choco install kubernetes-cli -y

# install heml
Write-Host "Installing helm..."
choco install kubernetes-helm -y

# install terraform 
Write-Host "Install terraform..."
choco install terraform -y 

# install openssl
Write-Host "Installing openssl..."
choco install openssl.light -y 

# setup java
choco install jdk8 -params 'installdir=c:\\java8' -Y
choco install maven -y  # choco upgrade maven
choco install gradle -y # choco upgrade gradle

# setup python
# brew install mysql
# brew install pip 
# pip install mysqlclient
# pip install flask
# pip install prometheus_client

# go
choco install golang -y
[System.Environment]::SetEnvironmentVariable("GOROOT", "C:\GO", [System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable("GOPATH", "E:\GO", [System.EnvironmentVariableTarget]::User)
# choco upgrade golang
go version 

# JQ
choco.exe install jq -y

Write-Host "Installing devspace..." -ForegroundColor Green
InstallDevSpace

Write-Host "Installing pulumi..." -ForegroundColor Green
InstallPulumi

# trust the gallery so that I can import yamlUtil without prompt
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
