function Get-ServerFarm {
    param ([string]$webFarmName)

    $assembly = [System.Reflection.Assembly]::LoadFrom("$env:systemroot\system32\inetsrv\Microsoft.Web.Administration.dll")
    $mgr = new-object Microsoft.Web.Administration.ServerManager "$env:systemroot\system32\inetsrv\config\applicationhost.config"
    $conf = $mgr.GetApplicationHostConfiguration()
    $section = $conf.GetSection("webFarms")
    $webFarms = $section.GetCollection()
    $webFarm = $webFarms | Where {
        $_.GetAttributeValue("name") -eq $webFarmName
    }

    $webFarm
}

$siteBlue = "http://alwaysup-blue:8001"
$siteGreen = "http://alwaysup-green:8002"
$pathBlue = "C:\Projects\alwaysup\alwaysup-blue"
$pathGreen = "C:\Projects\alwaysup\alwaysup-green"
$pathBlueContent = (Get-Content $pathBlue\up.html)
$serverFarmName = "alwaysup"
$webFarm = Get-ServerFarm $serverFarmName
$webFarmArr = $webFarm.GetChildElement("applicationRequestRouting")
$webFarmHeathCheck = $webFarmArr.GetChildElement("healthCheck")
$healthCheckTimeoutS = $webFarmHeathCheck.GetAttributeValue("interval").TotalSeconds

$siteToWarm = $siteBlue
$pathToBringDown = $pathGreen
$pathToBringUp = $pathBlue

if ($pathBlueContent -contains 'up')
{
    $siteToWarm = $siteGreen
    $pathToBringUp = $pathGreen
    $pathToBringDown = $pathBlue
}

Write-Host "Warming up $($siteToWarm)"
Do {
    $time = Measure-Command {
        $res = Invoke-WebRequest $siteToWarm
    }
    $ms = $time.TotalMilliSeconds
    If ($ms -ge 400) {
        Write-Host "$($res.StatusCode) from   $($siteToWarm) in $($ms)ms" -foreground "yellow"
    }
} While ($ms -ge 400)
Write-Host "$($res.StatusCode) from $($siteToWarm) in $($ms)ms" -foreground "cyan"

if ($res.StatusCode -eq 200) {
    Write-Host "Bringing $($pathToBringUp) up" -foreground "cyan"
    (Get-Content $pathToBringUp\up.html).replace('down', 'up') | Set-Content $pathToBringUp\up.html

    Write-Host "Waiting for health check to pass in $($healthCheckTimeoutS) seconds..."
    Start-Sleep -s $healthCheckTimeoutS

    Write-Host "Bringing $($pathToBringDown) down"
    (Get-Content $pathToBringDown\up.html).replace('up', 'down') | Set-Content $pathToBringDown\up.html
} else {
    Write-Host "Cannot warm up $($siteToWarm)" -foreground "red"
}