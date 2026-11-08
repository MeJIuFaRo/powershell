# New-BitsTransfer

Копирует и скачивает файлы через BITS (Background Intelligent Transfer Service) и показывает прогресс: процент, объём, скорость, оставшееся время и число файлов.

Обёртка над `Start-BitsTransfer -Asynchronous`. Не зависает на ошибках и не оставляет после себя висящих BITS-задач.

## Требования

- Windows с модулем `BitsTransfer` (входит в Windows 10/11 и Windows Server).
- PowerShell 7.x (на Windows PowerShell 5.1 не проверялся).
- Интерактивный вход пользователя: BITS выполняет задачи пользователя, только пока он вошёл в систему.

## Примеры

```powershell
# Скопировать файл с общей папки в локальную папку
New-BitsTransfer \\srv\share\big.iso D:\ISO\

# Скачать по HTTPS и сдаться через 10 минут, если сервер недоступен (по умолчанию ждёт 13 часов)
New-BitsTransfer https://example.com/file.zip .\file.zip -RetryTimeoutSec 600

# Скопировать несколько файлов в папку
New-BitsTransfer (Get-ChildItem \\srv\share\*.vhdx).FullName D:\VM\

# Подпись задачи и низкий приоритет (не мешает другому трафику)
New-BitsTransfer \\srv\share\backup.zip D:\Backup\ 'Ночной бэкап' -Priority Low

# С учётными данными для HTTP/HTTPS-сервера
New-BitsTransfer https://intranet/report.xlsx .\report.xlsx -Credential (Get-Credential)

# Общая папка под другой учётной записью: сначала подключить её, потом копировать
net use \\srv\share /user:DOMAIN\user
New-BitsTransfer \\srv\share\big.iso D:\ISO\
```

## Параметры

| Параметр | Описание |
|---|---|
| `Source` (позиция 0) | Один или несколько источников: HTTP/HTTPS URL, локальный путь или UNC-путь |
| `Destination` (позиция 1) | Файл назначения или папка. Для нескольких источников — только существующая папка |
| `Name` (позиция 2) | Подпись задачи в BITS (видно в `Get-BitsTransfer`). По умолчанию `New-BitsTransfer` |
| `Priority` | `Foreground` (по умолчанию), `High`, `Normal`, `Low` |
| `RetryTimeoutSec` | Сколько секунд ждать при временной ошибке (сервер недоступен, обрыв сети). `0` — ждать бесконечно. По умолчанию `46800` (13 часов) |
| `Credential` | Учётные данные для HTTP/HTTPS-сервера в `Source`. Для локальных и UNC-путей **не действуют** (см. ниже) |

## Результат

Функция пишет зелёную строку `Готово: …` и возвращает объект:

| Поле | Что содержит |
|---|---|
| `Name`, `Source`, `Destination` | Параметры задачи |
| `Files` | Число скопированных файлов |
| `Bytes` | Общий объём в байтах |
| `Duration` | Время копирования (`TimeSpan`) |
| `MBps` | Средняя скорость, МБ/с |

## Как работает

- **Состояние задачи проверяется** каждые полсекунды:
  - `Error` или `Cancelled` — сразу ошибка с описанием от BITS;
  - `TransientError` — ожидание до `-RetryTimeoutSec`, затем ошибка;
  - `Suspended` — задача возобновляется.
- **Пока размер неизвестен** (BITS ещё подключается), показывается только скачанный объём, без процента.
- **Локальные и UNC-источники** проверяются до запуска, поэтому ошибка «Источник не найден» понятна сразу.
- **Несколько источников:** путь назначения для каждого файла собирается из папки и имени файла.
- **При ошибке или Ctrl+C** BITS-задача отменяется, а BITS удаляет свои временные файлы `BIT*.tmp`.

## Общие папки и учётные данные

`-Credential` для UNC-путей (`\\сервер\шара`) не работает: `Start-BitsTransfer` проверяет такой путь от имени текущего пользователя ещё до запуска BITS. Если доступа нет, команда сразу выдаёт «Источник не найден», а если доступ есть, переданные учётные данные просто игнорируются. При `-Credential` с локальным или UNC-источником функция выводит предупреждение.

Доступ к общей папке под другой учётной записью задайте заранее:

```powershell
# Навсегда (пароль будет запрошен, хранится в диспетчере учётных данных Windows)
cmdkey /add:srv.domain.local /user:DOMAIN\user /pass

# Только на текущий сеанс входа
net use \\srv.domain.local\share /user:DOMAIN\user
```

После этого `New-BitsTransfer` работает с этой папкой без `-Credential`.

## Если закрыть окно терминала

Задачей управляет служба BITS, поэтому при закрытии окна копирование **продолжится**. Но готовый файл сам не появится: данные останутся во временном скрытом `BIT*.tmp`, пока задачу не завершат. Незавершённые задачи BITS удаляет сам через 90 дней бездействия.

```powershell
# Посмотреть свои задачи
Get-BitsTransfer | Select-Object DisplayName, JobState, BytesTransferred, BytesTotal

# Задача в состоянии Transferred: превратить временный файл в готовый
Get-BitsTransfer | Where-Object { $_.DisplayName -eq 'Ночной бэкап' -and $_.JobState -eq 'Transferred' } | Complete-BitsTransfer

# Отменить задачу и удалить временный файл
Get-BitsTransfer | Where-Object DisplayName -eq 'Ночной бэкап' | Remove-BitsTransfer
```
