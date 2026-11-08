# PowerShell-модули

Небольшие модули для повседневного администрирования Windows.

| Модуль | Что делает |
|---|---|
| [Convert-PFX](Convert-PFX/README.md) | Разбирает PFX на сертификат и ключ или собирает PFX из сертификата и ключа (через OpenSSL) |
| [New-BitsTransfer](New-BitsTransfer/README.md) | Копирует и скачивает файлы через BITS с прогрессом, скоростью и защитой от зависаний |
| [Remove-SSHKey](Remove-SSHKey/README.md) | Удаляет ключ хоста из `known_hosts` по имени хоста или по номеру строки |

## Установка

Скопируйте папку модуля в каталог модулей пользователя:

| PowerShell | Каталог |
|---|---|
| 7.x | `$HOME\Documents\PowerShell\Modules` |
| Windows PowerShell 5.1 | `$HOME\Documents\WindowsPowerShell\Modules` |

```powershell
git clone https://github.com/MeJIuFaRo/powershell.git
Copy-Item .\powershell\Convert-PFX, .\powershell\New-BitsTransfer, .\powershell\Remove-SSHKey "$HOME\Documents\PowerShell\Modules" -Recurse
```

После этого модуль подгрузится сам при первом вызове команды. В уже открытой сессии:

```powershell
Import-Module Convert-PFX -Force
```

Справка по каждой команде доступна через `Get-Help`:

```powershell
Get-Help Convert-PFX -Full
Get-Help New-BitsTransfer -Examples
Get-Help Remove-SSHKey -Examples
```
