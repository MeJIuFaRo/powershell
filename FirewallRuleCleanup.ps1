# Generate transcript
Start-Transcript -Path ".\FirewallRuleCleanup.log" -Append

# Collect who is currently logged in, we don't want to modify their firewall rules...
Write-Output ("{0} - Gathering current user information" -f (Get-Date -Format g))
$LoggedIn = (Get-WmiObject -Class Win32_ComputerSystem).UserName
If ($LoggedIn -like "msc\*") {
    $LoggedInUsername = $LoggedIn.Replace("DOMAIN\","")

}ElseIf ($LoggedIn -like "$env:COMPUTERNAME\*"){
    $LoggedInUsername = $LoggedIn.Replace("$env:COMPUTERNAME\","")
}

# Find SID of current user to exclude their firewall rules from deletion
If ($null -ne $LoggedInUsername) {
    Write-Output ("{0} - Finding $LoggedInUsername's SID" -f (Get-Date -Format g))
    $UserProfiles = Get-WmiObject -Class Win32_UserProfile
    $SID = ($UserProfiles | Where-Object {$_.LocalPath -eq "C:\Users\$LoggedInUsername"}).SID
    Write-Output ("{0} - $LoggedInUsername - $SID" -f (Get-Date -Format g))
} Else {
    # Nobody is currently logged in via console
    Write-Output ("{0} - Machine is not in use" -f (Get-Date -Format g))
}

# Gather Firewall Rules
Write-Output ("{0} - Gathering FireWall Rules" -f (Get-Date -Format g))
$FirewallRules = Get-NetFirewallRule | Where-Object {($_.Owner -ne $null) -and ($_.Owner -notlike "*-500") -and ($_.Owner -like "S-1-5-21-*") -and ($_.Owner -ne $SID)}
Write-Output ("{0} - Finished gathering Rules" -f (Get-Date -Format g))
Write-Output ("{0} - Total number of Firewall Rules: {1}" -f (Get-Date -Format g),$FirewallRules.count)

# Delete Firewall Rules
Write-Output ("{0} - Deleting Firewall Rules" -f (Get-Date -Format g))
$FirewallRules | Remove-NetFirewallRule
Write-Output ("{0} - Complete!" -f (Get-Date -Format g))
Stop-Transcript