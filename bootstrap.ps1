#Ensure our script is elevated to Admin permissions
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
$arguments = "-noexit & '" + $myinvocation.mycommand.definition + "'"
Start-Process powershell -Verb runAs -ArgumentList $arguments
Break
}

function getExisitingIISBindings($name){
    return Get-WebBinding -Name $name
}

#Bindings need to be organised before they are added
function ensureSSL($config){
    # # Assign certificates to https bindings
    foreach ($binding in $config.siteBindings){
        #create a https binding       
        New-WebBinding -Name $config.siteName -Protocol "https" -Port 443 -IPAddress * -HostHeader $binding -SslFlags 0          
    }
}

function assignUmbracoFolderPermissions($dir, $iisAppPoolName){    
    Write-Host $dir
    $Acl = Get-Acl $dir
    $Ar = New-Object  system.security.accesscontrol.filesystemaccessrule("IUSR","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl -Path $dir -AclObject $Acl

    $Ar = New-Object  system.security.accesscontrol.filesystemaccessrule("IIS_IUSRS","Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl -Path $dir -AclObject $Acl

    $iisAppPoolName = "IIS apppool\$iisAppPoolName"
    $Ar = New-Object  system.security.accesscontrol.filesystemaccessrule($iisAppPoolName,"Modify", "ContainerInherit, ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($Ar)
    Set-Acl -Path $dir -AclObject $Acl
}

function newSite($config){
    Write-Host Assign http bindings
    $i = 0
    foreach ($binding in $config.siteBindings){
        if($i -eq 0){
            New-Website -Name $config.siteName -PhysicalPath $config.dir -ApplicationPool $config.appPoolName -HostHeader $binding
        }
        else {
            New-WebBinding -Name $config.siteName -IPAddress "*" -Port 80 -HostHeader $binding
        }
        $i++
    }
}

function newAppPool($name, $runtimeVersion){
    #create the app pool
    $appPool = New-WebAppPool $name
    $appPool | Set-ItemProperty -Name "managedRuntimeVersion" -Value $runtimeVersion
}

function appPoolExist($name){
    #check if the app pool exists
    return (Test-Path IIS:\AppPools\$name -pathType container)
}

function siteExist($name){
    $exist = $false
    if(Get-Website -Name "$name"){
        $exist = $true
    }
    return $exist
}

function checkSiteConfigStatus($config){
    $exist = siteExist($config.siteName)
    if($exist){
        $status = [pscustomobject]@{
            siteExist = $exist
            appPoolExist = appPoolExist($config.appPoolName)
        }
    }
    else {
        $status = [pscustomobject]@{
            siteExist = $exist
            appPoolExist = appPoolExist($config.appPoolName)
            bindings = $false
        }
    }
    
    return $status
}

# ============== Start Script
Import-Module WebAdministration
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
Write-Host Starting
Write-Host Load JSON
$iisconfig = Get-Content  "$dir\website-config.json" | Out-String | ConvertFrom-Json

$config = [pscustomobject]@{
    siteName = $iisconfig."IIS-Site-Name"
    appPoolName = $iisconfig."App-Pool-Name"
    siteBindings = $iisconfig."bindings"	
    dir = $dir
    dotNetVersion = $iisconfig."IIS-APP-POOL-VERSION"
    }
Write-Host "Loaded in JSON"
Write-Host Obtain current status of site
$status = checkSiteConfigStatus($config)
$status

Write-Host "Create App pool if it doesn't exist"
if(!$status.appPoolExist){
    newAppPool $config.appPoolName $config.dotNetVersion
}
Write-Host "Ensured App Pool"
#Easier to remove the IIS site and re create it than editing the bindings
if($status.siteExists){
    Remove-WebSite -Name $config.siteName
    Write-Host "Site already exists - Removing..."
}

#Create our IIS site with http schema
Write-Host "Creating IIS Site"
newSite $config
Write-Host "Assigning folder permissions on Web Root"
assignUmbracoFolderPermissions $config.dir $config.appPoolName
Write-Host "Ensuring SSL"
ensureSSL $config

Get-WebBinding -Protocol http -Name $config.siteName | Remove-WebBinding

Write-Host "Done !"