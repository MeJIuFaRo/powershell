function Convert-PFX {
  <#
  .SYNOPSIS
    Разбирает PFX на .crt + .key или собирает PFX из .crt + .key (через openssl).
  .DESCRIPTION
    Направление определяется по расширению входного файла:
      .pfx / .p12                -> создаются <имя>.crt (сертификаты) и <имя>.key (ключ без пароля);
      .crt / .cer / .pem         -> создаётся <имя>.pfx из сертификата и ключа <имя>.key
                                    (или -KeyPath). Сертификат может быть в PEM или DER.
    Пароль передаётся в openssl через переменную окружения, а не в командной строке.
    Если пароль не указан, он запрашивается скрыто (при сборке — дважды).
    Пустой пароль: PFX без пароля.
    Старые PFX (RC2) при разборе автоматически читаются с -legacy.
    При любой ошибке частично созданные файлы удаляются.
  .PARAMETER PathPfx
    Входной файл: PFX/P12 для разбора или CRT/CER/PEM для сборки.
  .PARAMETER Passwd
    Пароль PFX: SecureString или строка. Если не указан, будет запрошен.
  .PARAMETER KeyPath
    Сборка: путь к закрытому ключу. По умолчанию <имя сертификата>.key рядом с сертификатом.
  .PARAMETER KeyPasswd
    Сборка: пароль зашифрованного ключа, если он отличается от пароля PFX.
  .PARAMETER ChainPath
    Сборка: файл с промежуточными сертификатами, которые нужно добавить в PFX.
  .PARAMETER FriendlyName
    Сборка: понятное имя сертификата в PFX (видно в оснастке сертификатов Windows).
    По умолчанию имя файла.
  .PARAMETER Compat
    Сборка: PFX с шифрованием 3DES/SHA1 для старых систем (Windows Server 2016 и старше, старые Java).
    По умолчанию AES-256/SHA256.
  .PARAMETER OutDir
    Папка для результата. По умолчанию папка входного файла.
  .PARAMETER Traditional
    Разбор: ключ в старом формате (BEGIN RSA PRIVATE KEY / BEGIN EC PRIVATE KEY) вместо PKCS#8.
  .PARAMETER LeafOnly
    Разбор: в .crt только сертификат сервера, без цепочки.
  .PARAMETER Force
    Перезаписать существующие выходные файлы.
  .EXAMPLE
    Convert-PFX .\site.pfx
    Разобрать site.pfx на site.crt и site.key.
  .EXAMPLE
    Convert-PFX .\site.crt
    Собрать site.pfx из site.crt и site.key.
  .EXAMPLE
    Convert-PFX .\fullchain.pem $pw -KeyPath .\privkey.pem -FriendlyName 'site.ru 2026' -Compat
  #>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName', 'Path')]
    [string]$PathPfx,

    [Parameter(Position = 1)]
    [object]$Passwd,

    [string]$KeyPath,
    [object]$KeyPasswd,
    [string]$ChainPath,
    [string]$FriendlyName,
    [switch]$Compat,

    [string]$OutDir,
    [switch]$Traditional,
    [switch]$LeafOnly,
    [switch]$Force
  )

  begin {
    $openssl = Get-Command openssl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $openssl) { throw 'openssl не найден в PATH.' }

    function ConvertTo-Plain($v) {
      if ($null -eq $v) { return $null }
      if ($v -is [securestring]) { return [System.Net.NetworkCredential]::new('', $v).Password }
      return [string]$v
    }

    # Запуск openssl: возвращает stdout, бросает исключение с текстом stderr при ненулевом коде.
    function Invoke-OpenSsl([string[]]$OsslArgs) {
      $all = & openssl @OsslArgs 2>&1
      $out = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
      $err = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
      if ($LASTEXITCODE -ne 0) { throw (($err + $out) -join "`n") }
      return $out
    }

    # Аргумент пароля: через переменную окружения, пустой пароль — напрямую.
    function Get-PassArg([string]$Switch, [string]$EnvName, [string]$Value) {
      if ($Value) {
        Set-Item -LiteralPath "env:$EnvName" -Value $Value
        return @($Switch, "env:$EnvName")
      }
      return @($Switch, 'pass:')
    }

    $plain = ConvertTo-Plain $Passwd
    $keyPlain = ConvertTo-Plain $KeyPasswd
  }

  process {
    $src = (Resolve-Path -LiteralPath $PathPfx -ErrorAction Stop).ProviderPath
    $ext = [IO.Path]::GetExtension($src).ToLowerInvariant()
    $mode = switch ($ext) {
      { $_ -in '.pfx', '.p12' } { 'split'; break }
      { $_ -in '.crt', '.cer', '.pem' } { 'build'; break }
      default { $null }
    }
    if (-not $mode) { Write-Error "Неизвестное расширение '$ext': ожидается .pfx/.p12 (разбор) или .crt/.cer/.pem (сборка)."; return }

    $dir = if ($OutDir) { (Resolve-Path -LiteralPath $OutDir -ErrorAction Stop).ProviderPath } else { Split-Path $src -Parent }
    $base = [IO.Path]::GetFileNameWithoutExtension($src)

    # Пароль запрашивается один раз, когда стало известно направление.
    if ($null -eq $plain) {
      if ($mode -eq 'split') {
        $plain = ConvertTo-Plain (Read-Host -AsSecureString 'Пароль PFX (Enter, если без пароля)')
      } else {
        $p1 = ConvertTo-Plain (Read-Host -AsSecureString 'Пароль для нового PFX (Enter — без пароля)')
        $p2 = ConvertTo-Plain (Read-Host -AsSecureString 'Повторите пароль')
        if ($p1 -cne $p2) { Write-Error 'Пароли не совпадают.'; return }
        $plain = $p1
      }
    }

    [string[]]$outputs = if ($mode -eq 'split') { @((Join-Path $dir "$base.crt"), (Join-Path $dir "$base.key")) } else { @(Join-Path $dir "$base.pfx") }
    foreach ($out in $outputs) {
      if ($out -eq $src) { Write-Error "Выходной файл совпадает с исходным: $out"; return }
      if ((Test-Path -LiteralPath $out) -and -not $Force) {
        Write-Error "Файл уже существует: $out. Используйте -Force для перезаписи."; return
      }
    }

    $envPfx = "CONVERT_PFX_PASS_$PID"
    $envKey = "CONVERT_PFX_KEYPASS_$PID"
    $created = [System.Collections.Generic.List[string]]::new()
    $temps = [System.Collections.Generic.List[string]]::new()
    $modulesSet = $false
    try {
      if ($mode -eq 'split') {
        # ---------- Разбор PFX ----------
        $crt, $key = $outputs
        $tmp = Join-Path $dir "$base.key.tmp-$PID"
        $pass = Get-PassArg '-passin' $envPfx $plain
        $legacy = @()
        try {
          Invoke-OpenSsl (@('pkcs12', '-in', $src, '-noout') + $pass) | Out-Null
        } catch {
          if ("$_" -match 'Mac verify error|invalid password') { throw "Неверный пароль PFX: $src" }
          if ("$_" -notmatch 'unsupported|RC2|legacy|Algorithm') { throw }
          Write-Verbose 'Старый формат PFX, повтор с -legacy'
          $legacy = @('-legacy')
          # Установщик OpenSSL-Win64 кладёт legacy.dll в bin, а openssl ищет его в lib\ossl-modules.
          $binDir = Split-Path $openssl.Source
          if (-not $env:OPENSSL_MODULES -and (Test-Path (Join-Path $binDir 'legacy.dll'))) {
            $env:OPENSSL_MODULES = $binDir; $modulesSet = $true
          }
          try { Invoke-OpenSsl (@('pkcs12', '-in', $src, '-noout') + $pass + $legacy) | Out-Null }
          catch { if ("$_" -match 'Mac verify error|invalid password') { throw "Неверный пароль PFX: $src" }; throw }
        }

        $certArgs = @('pkcs12', '-in', $src, '-nokeys', '-out', $crt) + $pass + $legacy
        if ($LeafOnly) { $certArgs += '-clcerts' }
        $created.Add($crt); Invoke-OpenSsl $certArgs | Out-Null

        $temps.Add($tmp); Invoke-OpenSsl (@('pkcs12', '-in', $src, '-nocerts', '-nodes', '-out', $tmp) + $pass + $legacy) | Out-Null
        $pkeyArgs = @('pkey', '-in', $tmp, '-out', $key)
        if ($Traditional) { $pkeyArgs += '-traditional' }
        $created.Add($key); Invoke-OpenSsl $pkeyArgs | Out-Null

        [pscustomobject]@{
          Mode        = 'Split'
          Pfx         = $src
          Certificate = $crt
          Key         = $key
          CertCount   = @(Select-String -LiteralPath $crt -Pattern 'BEGIN CERTIFICATE').Count
          Legacy      = [bool]$legacy
        }
        Write-Warning "Закрытый ключ сохранён без пароля: $key"
      } else {
        # ---------- Сборка PFX ----------
        $pfx = $outputs[0]
        $keyIn = if ($KeyPath) { (Resolve-Path -LiteralPath $KeyPath -ErrorAction Stop).ProviderPath } else { Join-Path (Split-Path $src -Parent) "$base.key" }
        if (-not (Test-Path -LiteralPath $keyIn)) { throw "Не найден закрытый ключ: $keyIn. Укажите -KeyPath." }
        $chainIn = if ($ChainPath) { (Resolve-Path -LiteralPath $ChainPath -ErrorAction Stop).ProviderPath }

        # Сертификаты в DER (.cer из Windows) переводим в PEM во временный файл.
        $toPem = {
          param($file, $label)
          if (Select-String -LiteralPath $file -Pattern '-----BEGIN CERTIFICATE-----' -SimpleMatch -Quiet) { return $file }
          $t = Join-Path $dir "$base.$label.tmp-$PID.pem"
          $temps.Add($t)
          try { Invoke-OpenSsl @('x509', '-inform', 'DER', '-in', $file, '-out', $t) | Out-Null }
          catch { throw "Не удалось прочитать сертификат ни как PEM, ни как DER: $file" }
          return $t
        }
        $certIn = & $toPem $src 'cert'
        if ($chainIn) { $chainIn = & $toPem $chainIn 'chain' }

        $keyPass = Get-PassArg '-passin' $envKey $(if ($null -ne $keyPlain) { $keyPlain } else { $plain })

        # Проверяем, что ключ подходит к сертификату.
        try { $keyPub = Invoke-OpenSsl (@('pkey', '-in', $keyIn, '-pubout') + $keyPass) }
        catch {
          if ("$_" -match 'bad decrypt|unable to load|maybe wrong password|Could not read|could not decode') { throw "Не удалось прочитать ключ $keyIn (зашифрован другим паролем? укажите -KeyPasswd): $_" }
          throw
        }
        $certPub = Invoke-OpenSsl @('x509', '-in', $certIn, '-noout', '-pubkey')
        if (($keyPub -join '') -ne ($certPub -join '')) { throw "Ключ $keyIn не подходит к сертификату $src." }

        $name = if ($FriendlyName) { $FriendlyName } else { $base }
        $exportArgs = @('pkcs12', '-export', '-in', $certIn, '-inkey', $keyIn, '-out', $pfx, '-name', $name) + $keyPass + (Get-PassArg '-passout' $envPfx $plain)
        if ($chainIn) { $exportArgs += @('-certfile', $chainIn) }
        if ($Compat) { $exportArgs += @('-certpbe', 'PBE-SHA1-3DES', '-keypbe', 'PBE-SHA1-3DES', '-macalg', 'sha1') }
        $created.Add($pfx); Invoke-OpenSsl $exportArgs | Out-Null

        # Контрольное чтение собранного PFX.
        $check = Invoke-OpenSsl (@('pkcs12', '-in', $pfx, '-nokeys') + (Get-PassArg '-passin' $envPfx $plain))
        [pscustomobject]@{
          Mode         = 'Build'
          Pfx          = $pfx
          Certificate  = $src
          Key          = $keyIn
          Chain        = $ChainPath
          CertCount    = @($check | Where-Object { $_ -eq '-----BEGIN CERTIFICATE-----' }).Count
          FriendlyName = $name
          Compat       = [bool]$Compat
        }
        if (-not $plain) { Write-Warning "PFX создан без пароля: $pfx" }
      }
    } catch {
      foreach ($f in $created) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
      Write-Error "Convert-PFX: $_"
    } finally {
      foreach ($f in $temps) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
      Remove-Item -LiteralPath "env:$envPfx", "env:$envKey" -ErrorAction SilentlyContinue
      if ($modulesSet) { Remove-Item env:OPENSSL_MODULES -ErrorAction SilentlyContinue }
    }
  }

  end { $plain = $null; $keyPlain = $null }
}

Export-ModuleMember -Function Convert-PFX
