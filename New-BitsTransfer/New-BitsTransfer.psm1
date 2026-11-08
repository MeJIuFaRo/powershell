function New-BitsTransfer {
  <#
  .SYNOPSIS
    Копирует файлы через BITS с индикатором прогресса, скоростью и оставшимся временем.
  .DESCRIPTION
    Запускает асинхронную BITS-задачу и ждёт её завершения.
    Источник: HTTP/HTTPS URL, локальный путь или UNC-путь (один файл или несколько).
    Если источник недоступен дольше -RetryTimeoutSec, задача отменяется с ошибкой.
    При ошибке или Ctrl+C BITS-задача удаляется вместе с временными файлами.
  .PARAMETER Source
    Один или несколько источников.
  .PARAMETER Destination
    Файл назначения или папка (для нескольких источников — только папка).
  .PARAMETER Name
    Подпись задачи в BITS (видно в Get-BitsTransfer).
  .PARAMETER Priority
    Приоритет BITS: Foreground (по умолчанию), High, Normal, Low.
  .PARAMETER RetryTimeoutSec
    Сколько секунд ждать при временной ошибке (сервер недоступен, обрыв сети), прежде чем сдаться.
    0 — ждать бесконечно. По умолчанию 46800 (13 часов).
  .PARAMETER Credential
    Учётные данные для источника (HTTP-аутентификация или общая папка).
  .EXAMPLE
    New-BitsTransfer \\srv\share\big.iso D:\ISO\
  .EXAMPLE
    New-BitsTransfer https://example.com/file.zip .\file.zip -Priority Normal -RetryTimeoutSec 600
  .EXAMPLE
    New-BitsTransfer (Get-ChildItem \\srv\share\*.vhdx).FullName D:\VM\
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0)]
    [string[]]$Source,

    [Parameter(Mandatory, Position = 1)]
    [string]$Destination,

    [Parameter(Position = 2)]
    [string]$Name = 'New-BitsTransfer',

    [ValidateSet('Foreground', 'High', 'Normal', 'Low')]
    [string]$Priority = 'Foreground',

    [ValidateRange(0, [int]::MaxValue)]
    [int]$RetryTimeoutSec = 46800,

    [pscredential]$Credential
  )

  function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N2} ГБ' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N1} МБ' -f ($Bytes / 1MB) }
    else { '{0:N0} КБ' -f ($Bytes / 1KB) }
  }

  # Локальные и UNC-источники проверяем заранее, чтобы ошибка была понятной.
  foreach ($s in $Source) {
    if ($s -notmatch '^https?://' -and -not (Test-Path -LiteralPath $s -PathType Leaf)) {
      Write-Error "Источник не найден: $s"; return
    }
  }

  # Несколько источников: BITS нужен отдельный путь назначения на каждый файл.
  $dest = @($Destination)
  if ($Source.Count -gt 1) {
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
      Write-Error "Для нескольких источников -Destination должен быть существующей папкой: $Destination"; return
    }
    $dest = foreach ($s in $Source) {
      $leaf = if ($s -match '^https?://') { [uri]::UnescapeDataString(([uri]$s).Segments[-1]) } else { Split-Path $s -Leaf }
      Join-Path $Destination $leaf
    }
  }

  $startArgs = @{
    Source      = $Source
    Destination = [string[]]$dest
    Asynchronous = $true
    Priority    = $Priority
    DisplayName = $Name
    ErrorAction = 'Stop'
  }
  if ($Credential) { $startArgs.Credential = $Credential }

  $job = $null
  $done = $false
  $activity = "BITS: $Name"
  try {
    $job = Start-BitsTransfer @startArgs
    $started = Get-Date
    $lastBytes = 0.0; $lastTime = $started; $speed = 0.0
    $transientSince = $null

    while ($true) {
      $state = $job.JobState.ToString()
      switch ($state) {
        'Transferred' { break }
        { $_ -in 'Error', 'Cancelled' } {
          throw "BITS-задача завершилась с состоянием ${state}: $($job.ErrorDescription)".Trim()
        }
        'TransientError' {
          if (-not $transientSince) { $transientSince = Get-Date }
          $waited = ((Get-Date) - $transientSince).TotalSeconds
          if ($RetryTimeoutSec -gt 0 -and $waited -ge $RetryTimeoutSec) {
            $limit = [timespan]::FromSeconds($RetryTimeoutSec)
            $limitText = if ($limit.TotalHours -ge 1) { '{0:N1} ч' -f $limit.TotalHours } elseif ($limit.TotalMinutes -ge 1) { '{0:N0} мин' -f $limit.TotalMinutes } else { "$RetryTimeoutSec с" }
            throw "Источник недоступен дольше ${limitText}: $($job.ErrorDescription)".Trim()
          }
        }
        'Suspended' { Resume-BitsTransfer -BitsJob $job -Asynchronous | Out-Null }
        default { $transientSince = $null }
      }
      if ($state -eq 'Transferred') { break }

      # Прогресс. Пока размер неизвестен, BITS отдаёт UInt64.MaxValue.
      $now = Get-Date
      $bytes = [double]$job.BytesTransferred
      $total = [double]$job.BytesTotal
      $dt = ($now - $lastTime).TotalSeconds
      if ($dt -ge 1) {
        $speed = [math]::Max(0, ($bytes - $lastBytes) / $dt)
        $lastBytes = $bytes; $lastTime = $now
      }
      $files = "файлов $($job.FilesTransferred) из $($job.FilesTotal)"
      $speedText = if ($speed -gt 0) { "$(Format-Size $speed)/с" } else { '—' }
      if ($total -gt 0 -and $total -lt [UInt64]::MaxValue) {
        $pct = [int][math]::Floor($bytes / $total * 100)
        $eta = if ($speed -gt 0) { [int](($total - $bytes) / $speed) } else { -1 }
        $status = "$pct% — $(Format-Size $bytes) из $(Format-Size $total), $speedText, $files"
        Write-Progress -Activity $activity -Status $status -PercentComplete $pct -SecondsRemaining $eta -CurrentOperation $state
      } else {
        $status = "$(Format-Size $bytes), размер ещё неизвестен, $files"
        Write-Progress -Activity $activity -Status $status -CurrentOperation $state
      }
      Start-Sleep -Milliseconds 500
    }

    $total = [double]$job.BytesTotal
    $filesTotal = $job.FilesTotal
    Complete-BitsTransfer -BitsJob $job -ErrorAction Stop
    $done = $true
    $elapsed = (Get-Date) - $started
    $avg = if ($elapsed.TotalSeconds -gt 0) { $total / $elapsed.TotalSeconds } else { 0 }
    Write-Host "Готово: $(Format-Size $total), файлов $filesTotal, за $([int]$elapsed.TotalSeconds) с ($(Format-Size $avg)/с)" -ForegroundColor Green
    [pscustomobject]@{
      Name        = $Name
      Source      = $Source
      Destination = $Destination
      Files       = $filesTotal
      Bytes       = [UInt64]$total
      Duration    = $elapsed
      MBps        = [math]::Round($avg / 1MB, 2)
    }
  } catch {
    Write-Error $_.Exception.Message
  } finally {
    Write-Progress -Activity $activity -Completed
    # Ошибка или Ctrl+C: отменяем задачу, BITS удаляет временные файлы.
    if ($job -and -not $done) {
      Remove-BitsTransfer -BitsJob $job -ErrorAction SilentlyContinue
    }
  }
}

Export-ModuleMember -Function New-BitsTransfer
