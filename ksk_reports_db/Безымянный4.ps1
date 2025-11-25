# ============================================================================
# Скрипт выполнения миграции PostgreSQL для системы отчётов КСК
# ВЕРСИЯ ДЛЯ WINDOWS (PowerShell)
# ============================================================================
# Описание:
#   - Устанавливает переменные окружения для PostgreSQL
#   - Выполняет SQL миграцию из файла
#   - Очищает переменные окружения после выполнения
#
# Использование:
#   .\run_migration_windows.ps1
#   или
#   powershell -ExecutionPolicy Bypass -File .\run_migration_windows.ps1
#
# Требования:
#   - PowerShell 5.1+ (встроен в Windows 10/11)
#   - PostgreSQL установлен на Windows
#
# Автор: AI Assistant
# Дата: 30.10.2025
# ============================================================================

# Остановка при ошибке
$ErrorActionPreference = "Stop"

# Функции для цветного вывода
function Write-Header { param($text) Write-Host $text -ForegroundColor Cyan }
function Write-Success { param($text) Write-Host "✓ $text" -ForegroundColor Green }
function Write-Error-Custom { param($text) Write-Host "✗ $text" -ForegroundColor Red }
function Write-Warning-Custom { param($text) Write-Host "→ $text" -ForegroundColor Yellow }
function Write-Info { param($text) Write-Host "  $text" -ForegroundColor Gray }

Write-Header "============================================"
Write-Header "  Миграция PostgreSQL - Система КСК"
Write-Header "  (Windows PowerShell)"
Write-Header "============================================"
Write-Host ""

# ============================================================================
# ШАГ 1: УСТАНОВКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ
# ============================================================================
Write-Warning-Custom "[ШАГ 1/3] Установка переменных окружения..."

# --- НАСТРОЙКИ БАЗЫ ДАННЫХ (ИЗМЕНИТЕ НА СВОИ) ---
$env:PGHOST = "localhost"           # Хост БД
$env:PGPORT = "5432"                # Порт БД
$env:PGDATABASE = "postgres"          # Имя базы данных
$env:PGUSER = "postgres"            # Пользователь БД
$env:PGPASSWORD = "sloaer"   # Пароль (или используйте .pgpass)

# --- ПУТЬ К PSQL (WINDOWS) ---
# ВАРИАНТ 1: Автоматический поиск PostgreSQL (рекомендуется)
$PostgreSQLVersions = @("16", "15", "14", "13")
$PsqlPath = $null

foreach ($version in $PostgreSQLVersions) {
    $testPath = "C:\Program Files\pgAdmin 4\runtime\psql.exe"
    if (Test-Path $testPath) {
        $PsqlPath = $testPath
        break
    }
}

# ВАРИАНТ 2: Явное указание версии
# $PsqlPath = "C:\Program Files\PostgreSQL\16\bin\psql.exe"

# ВАРИАНТ 3: Если PostgreSQL в PATH
# $PsqlPath = "psql"

if (-not $PsqlPath) {
    Write-Error-Custom "ОШИБКА: psql.exe не найден!"
    Write-Info "Проверьте установку PostgreSQL:"
    Write-Info "  - Стандартный путь: C:\Program Files\PostgreSQL\<версия>\bin\psql.exe"
    Write-Info "  - Или добавьте PostgreSQL в PATH"
    exit 1
}

# --- ПУТЬ К ФАЙЛУ МИГРАЦИИ (WINDOWS) ---
# ВАРИАНТ 1: Абсолютный путь
$MigrationFile = "D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\deepseek\ksk_reports_db\migrations\ksk_full_migration-20251029-003.sql"

# ВАРИАНТ 2: Относительный путь (если скрипт в той же папке)
# $MigrationFile = ".\ksk_full_migration-20251029-001.txt"

# ВАРИАНТ 3: Путь относительно скрипта
# $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# $MigrationFile = Join-Path $ScriptDir "ksk_full_migration-20251029-001.txt"

# Проверка существования файла миграции
if (-not (Test-Path $MigrationFile)) {
    Write-Error-Custom "ОШИБКА: Файл миграции не найден!"
    Write-Info "Путь: $MigrationFile"
    Write-Host ""
    Write-Info "Подсказки:"
    Write-Info "  - Проверьте правильность пути к файлу"
    Write-Info "  - Убедитесь что файл существует"
    Write-Info "  - Проверьте права доступа к файлу"
    exit 1
}

Write-Success "Переменные окружения установлены"
Write-Info "Хост: $env:PGHOST"
Write-Info "Порт: $env:PGPORT"
Write-Info "База: $env:PGDATABASE"
Write-Info "Пользователь: $env:PGUSER"
Write-Info "PSQL: $PsqlPath"
Write-Info "Файл миграции: $MigrationFile"
Write-Host ""

# ============================================================================
# ШАГ 2: ВЫПОЛНЕНИЕ МИГРАЦИИ
# ============================================================================
Write-Warning-Custom "[ШАГ 2/3] Запуск миграции..."
Write-Host ""

# Проверка существования psql
if (-not (Test-Path $PsqlPath)) {
    Write-Error-Custom "ОШИБКА: psql.exe не найден по пути: $PsqlPath"
    exit 1
}

# Проверка подключения к БД
Write-Warning-Custom "Проверка подключения к БД..."
try {
    $versionCheck = & $PsqlPath -c "SELECT version();" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Не удалось подключиться"
    }
    Write-Success "Подключение успешно"
} catch {
    Write-Error-Custom "ОШИБКА: Не удалось подключиться к базе данных!"
    Write-Info "Проверьте настройки подключения."
    Write-Host ""
    Write-Info "Возможные причины:"
    Write-Info "  - PostgreSQL сервис не запущен (запустите: services.msc → postgresql)"
    Write-Info "  - Неверный хост/порт/пользователь/пароль"
    Write-Info "  - Firewall блокирует подключение"
    Write-Info "  - База данных '$env:PGDATABASE' не существует"
    exit 1
}
Write-Host ""

# Выполнение миграции
Write-Warning-Custom "Выполнение SQL миграции..."
Write-Info "(это может занять несколько минут)"
Write-Host ""

# Создание имени лог-файла
$LogFile = "migration_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Запуск миграции с логированием
try {
    $startTime = Get-Date
    
    # Выполнение psql с перенаправлением вывода
    & $PsqlPath `
        -v ON_ERROR_STOP=1 `
        --echo-errors `
        -f $MigrationFile `
        *>&1 | Tee-Object -FilePath $LogFile
    
    if ($LASTEXITCODE -ne 0) {
        throw "Миграция завершилась с ошибкой (код: $LASTEXITCODE)"
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    
    Write-Host ""
    Write-Success "Миграция выполнена успешно!"
    Write-Info "Время выполнения: $($duration.ToString('hh\:mm\:ss'))"
    Write-Info "Лог сохранён: $LogFile"
    
} catch {
    Write-Host ""
    Write-Error-Custom "ОШИБКА: Миграция завершилась с ошибкой!"
    Write-Info "Проверьте лог: $LogFile"
    Write-Info "Ошибка: $_"
    exit 1
}

Write-Host ""

# ============================================================================
# ШАГ 3: ОЧИСТКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ
# ============================================================================
Write-Warning-Custom "[ШАГ 3/3] Очистка переменных окружения..."

Remove-Item Env:\PGHOST -ErrorAction SilentlyContinue
Remove-Item Env:\PGPORT -ErrorAction SilentlyContinue
Remove-Item Env:\PGDATABASE -ErrorAction SilentlyContinue
Remove-Item Env:\PGUSER -ErrorAction SilentlyContinue
Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue

Write-Success "Переменные окружения очищены"
Write-Host ""

# ============================================================================
# ЗАВЕРШЕНИЕ
# ============================================================================
Write-Header "============================================"
Write-Success "  ✓ Миграция завершена успешно!"
Write-Header "============================================"
Write-Host ""
Write-Info "Следующие шаги:"
Write-Info "  1. Проверьте структуру БД: \d+ ksk_result"
Write-Info "  2. Проверьте функции: \df upoa_ksk_reports.*"
Write-Info "  3. Проверьте отчёты: SELECT * FROM ksk_report_orchestrator;"
Write-Host ""
Write-Info "Запустить psql:"
Write-Info "  $PsqlPath"
Write-Host ""
