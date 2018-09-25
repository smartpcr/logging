param(
    [string]$imageToRemove = "",
    [string]$containersToRemove = ""
)

Write-Host "Checking existing docker containers..."
$containers = Invoke-Expression "docker ps -q"
if ($containersToRemove -and $containersToRemove.Length -gt 0) {
    $containers = Invoke-Expression "docker ps -q --filter `"$containersToRemove`""
}
if ($containers) {
    $containers | ForEach-Object {
        $containerId = $_ 
        Invoke-Expression "docker kill $containerId"
        Invoke-Expression "docker rm $containerId"
    }
}
    
Write-Host "Checking existing images..."
$images = Invoke-Expression "docker images -q"
if ($imageToRemove -and $imageToRemove.Length -gt 0) {
    $images = Invoke-Expression "docker images $imageToRemove -q"
}
if ($images) {
    $images | ForEach-Object {
        $imageId = $_ 
        Invoke-Expression "docker rmi -f $imageId"
    }
}


$danglingImages = Invoke-Expression "docker images -qf dangling=true"
if ($danglingImages) {
    Write-Host "remove all dangling images..."
    Invoke-Expression "docker rmi -f $(docker images -qf dangling=true)"
}

# remove volume
docker volume rm $(docker volume ls -qf dangling=true)
docker volume ls -qf dangling=true | xargs -r docker volume rm

# remove network
docker network rm $(docker network ls | grep "bridge" | awk '/ / { print $1 }')