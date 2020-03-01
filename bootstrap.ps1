Write-host Ensure our script is elevated to Administrator permissions
If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{   
$arguments = "-noexit & '" + $myinvocation.mycommand.definition + "'"
Start-Process powershell -Verb runAs -ArgumentList $arguments
Break
}


Write-host Start Script
Import-Module WebAdministration
$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
Write-Host Starting
Write-host $dir
