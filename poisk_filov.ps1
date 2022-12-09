$ComputerList = Get-Content "C:\Users\ayupetrov-adm\Desktop\List.txt"
Foreach ($Computer in $ComputerList) {
    if (Test-Connection -ComputerName $Computer) {
        $LogicalDisks = Get-WmiObject -ComputerName $Computer -Query "Select * From Win32_LogicalDisk where DriveType = 3"
        Foreach ($LogicalDisk in $LogicalDisks) {
            $Path = "\\$Computer\" + ($LogicalDisk.DeviceID -replace ":", "$")
            Get-ChildItem -LiteralPath $Path -Recurse | ? {$_.Extension -match "(\.mkv|\.torrent)"} | Select-Object -Property FullName | Out-File -Append -LiteralPath "C:\Users\ayupetrov-adm\Desktop\log.txt"
        }
    }
}