function Remove-SSHKey {
  <#
  .SYNOPSIS
    Удаляет ключ хоста из known_hosts через ssh-keygen -R.
  .DESCRIPTION
    Remove-SSHKey <host> выполняет ssh-keygen.exe -R <host>.
    Remove-SSHKey <N> берёт имя хоста из строки N файла known_hosts и удаляет его.
    Если в строке несколько имён через запятую, удаляется каждое.
  .EXAMPLE
    Remove-SSHKey 10.196.16.42
  .EXAMPLE
    Remove-SSHKey 197
  #>
  param(
    [Parameter(Mandatory, Position = 0)][string]$HostName,
    [string]$KnownHosts = "$HOME\.ssh\known_hosts"
  )
  if ($HostName -notmatch '^\d+$') {
    ssh-keygen.exe -R $HostName -f $KnownHosts
    return
  }
  $n = [int]$HostName
  $lines = @(Get-Content -LiteralPath $KnownHosts)
  if ($n -lt 1 -or $n -gt $lines.Count) { Write-Error "Строки $n нет: в $KnownHosts $($lines.Count) строк."; return }
  $fields = @($lines[$n - 1].Trim() -split '\s+')
  if ($fields[0] -like '@*') { $fields = @($fields | Select-Object -Skip 1) }
  if ($fields.Count -lt 3 -or $fields[0] -match '^(#|AAAA)') { Write-Error "Строка ${n}: нет имени хоста: $($lines[$n - 1])"; return }
  if ($fields[0] -like '|1|*') { Write-Error "Строка ${n}: имя хоста захешировано, по номеру строки его не узнать."; return }
  foreach ($h in $fields[0] -split ',') {
    Write-Host "Строка ${n}: $h" -ForegroundColor Cyan
    ssh-keygen.exe -R $h -f $KnownHosts
  }
}

Export-ModuleMember -Function Remove-SSHKey
