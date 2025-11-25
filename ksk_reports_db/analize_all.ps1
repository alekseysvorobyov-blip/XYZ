<#
.\Analyze-KSK-Tables.ps1 `
    -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
    -PasswordFile "C:\secure\db_password.txt" `
    -DbHost "192.168.1.100" `
    -DbPort 5432 `
    -DbName "ksk_db" `
    -DbUser "ksk_user"

.\Analyze-KSK-Tables.ps1 `
    -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
    -PasswordFile "C:\secure\db_password.txt" `
    -DbName "ksk_db" `
    -DbUser "postgres"


.SYNOPSIS
    Выполняет ANALYZE на всех таблицах и партициях КСК
.DESCRIPTION
    Скрипт подключается к PostgreSQL через psql и выполняет ANALYZE 
    на всех таблицах схемы upoa_ksk_reports
.PARAMETER PsqlPath
    Путь к исполняемому файлу psql.exe
.PARAMETER PasswordFile
    Путь к текстовому файлу с паролем (одна строка)
.PARAMETER DbHost
    Хост PostgreSQL (по умолчанию: localhost)
.PARAMETER DbPort
    Порт PostgreSQL (по умолчанию: 5432)
.PARAMETER DbName
    Имя базы данных
.PARAMETER DbUser
    Пользователь PostgreSQL
.EXAMPLE
    .\Analyze-KSK-Tables.ps1 `
        -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
        -PasswordFile "C:\secure\db_password.txt" `
        -DbName "ksk_db" `
        -DbUser "postgres"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PsqlPath,
    
    [Parameter(Mandatory=$true)]
    [string]$PasswordFile,
    
    [Parameter(Mandatory=$false)]
    [string]$DbHost = "localhost",
    
    [Parameter(Mandatory=$false)]
    [int]$DbPort = 5432,
    
    [Parameter(Mandatory=$true)]
    [string]$DbName,
    
    [Parameter(Mandatory=$true)]
    [string]$DbUser
)

# Проверка существования psql
if (-not (Test-Path $PsqlPath)) {
    Write-Error "psql не найден по пути: $PsqlPath"
    exit 1
}

# Проверка существования файла с паролем
if (-not (Test-Path $PasswordFile)) {
    Write-Error "Файл с паролем не найден: $PasswordFile"
    exit 1
}

# Чтение пароля из файла
try {
    $password = Get-Content -Path $PasswordFile -Raw -ErrorAction Stop
    $password = $password.Trim()
    
    if ([string]::IsNullOrWhiteSpace($password)) {
        Write-Error "Файл с паролем пуст: $PasswordFile"
        exit 1
    }
}
catch {
    Write-Error "Ошибка чтения файла с паролем: $_"
    exit 1
}

Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "ANALYZE таблиц КСК" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

# SQL-скрипт для ANALYZE
$sqlScript = @"
-- ============================================================================
-- ANALYZE всех таблиц КСК в схеме upoa_ksk_reports
-- ============================================================================

\timing on

\echo ''
\echo '============================================================================'
\echo 'Начало ANALYZE таблиц КСК'
\echo '============================================================================'
\echo ''

-- Основные таблицы (родительские)
\echo '--- Основные таблицы ---'

\echo 'ANALYZE ksk_result...'
ANALYZE upoa_ksk_reports.ksk_result;

\echo 'ANALYZE ksk_figurant...'
ANALYZE upoa_ksk_reports.ksk_figurant;

\echo 'ANALYZE ksk_figurant_match...'
ANALYZE upoa_ksk_reports.ksk_figurant_match;

-- Служебные таблицы
\echo ''
\echo '--- Служебные таблицы ---'

\echo 'ANALYZE ksk_system_operations_log...'
ANALYZE upoa_ksk_reports.ksk_system_operations_log;

-- Таблицы отчётов
\echo ''
\echo '--- Таблицы отчётов ---'

\echo 'ANALYZE ksk_report_orchestrator...'
ANALYZE upoa_ksk_reports.ksk_report_orchestrator;

\echo 'ANALYZE ksk_report_header...'
ANALYZE upoa_ksk_reports.ksk_report_header;

\echo 'ANALYZE ksk_report_totals_data...'
ANALYZE upoa_ksk_reports.ksk_report_totals_data;

\echo 'ANALYZE ksk_report_list_totals_data...'
ANALYZE upoa_ksk_reports.ksk_report_list_totals_data;

\echo 'ANALYZE ksk_report_totals_by_payment_type_data...'
ANALYZE upoa_ksk_reports.ksk_report_totals_by_payment_type_data;

\echo 'ANALYZE ksk_report_list_totals_by_payment_type_data...'
ANALYZE upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data;

\echo 'ANALYZE ksk_report_figurants_data...'
ANALYZE upoa_ksk_reports.ksk_report_figurants_data;

-- Партиции (все автоматически)
\echo ''
\echo '--- Партиции ---'

DO `$`$
DECLARE
    partition_record RECORD;
    partition_count INTEGER := 0;
BEGIN
    -- Партиции ksk_result
    FOR partition_record IN
        SELECT child.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class parent ON parent.oid = i.inhparent
        JOIN pg_class child ON child.oid = i.inhrelid
        JOIN pg_namespace n ON n.oid = parent.relnamespace
        WHERE n.nspname = 'upoa_ksk_reports'
          AND parent.relname = 'ksk_result'
        ORDER BY child.relname
    LOOP
        EXECUTE FORMAT('ANALYZE upoa_ksk_reports.%I', partition_record.partition_name);
        partition_count := partition_count + 1;
    END LOOP;
    
    -- Партиции ksk_figurant
    FOR partition_record IN
        SELECT child.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class parent ON parent.oid = i.inhparent
        JOIN pg_class child ON child.oid = i.inhrelid
        JOIN pg_namespace n ON n.oid = parent.relnamespace
        WHERE n.nspname = 'upoa_ksk_reports'
          AND parent.relname = 'ksk_figurant'
        ORDER BY child.relname
    LOOP
        EXECUTE FORMAT('ANALYZE upoa_ksk_reports.%I', partition_record.partition_name);
        partition_count := partition_count + 1;
    END LOOP;
    
    -- Партиции ksk_figurant_match
    FOR partition_record IN
        SELECT child.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class parent ON parent.oid = i.inhparent
        JOIN pg_class child ON child.oid = i.inhrelid
        JOIN pg_namespace n ON n.oid = parent.relnamespace
        WHERE n.nspname = 'upoa_ksk_reports'
          AND parent.relname = 'ksk_figurant_match'
        ORDER BY child.relname
    LOOP
        EXECUTE FORMAT('ANALYZE upoa_ksk_reports.%I', partition_record.partition_name);
        partition_count := partition_count + 1;
    END LOOP;
    
    RAISE NOTICE 'ANALYZE выполнен для % партиций', partition_count;
END `$`$;

\echo ''
\echo '============================================================================'
\echo 'ANALYZE завершён успешно'
\echo '============================================================================'
\echo ''
"@

# Создание временного файла со скриптом
$tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"
$sqlScript | Out-File -FilePath $tempSqlFile -Encoding UTF8

try {
    Write-Host "Подключение к БД: $DbHost`:$DbPort/$DbName" -ForegroundColor Yellow
    Write-Host "Пользователь: $DbUser" -ForegroundColor Yellow
    Write-Host "Файл с паролем: $PasswordFile" -ForegroundColor Yellow
    Write-Host ""
    
    # Установка пароля в переменную окружения
    $env:PGPASSWORD = $password
    
    # Выполнение скрипта через psql
    & $PsqlPath -h $DbHost -p $DbPort -U $DbUser -d $DbName -f $tempSqlFile
    
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Host ""
        Write-Host "============================================================================" -ForegroundColor Green
        Write-Host "ANALYZE выполнен успешно!" -ForegroundColor Green
        Write-Host "============================================================================" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "============================================================================" -ForegroundColor Red
        Write-Host "ОШИБКА при выполнении ANALYZE (код выхода: $exitCode)" -ForegroundColor Red
        Write-Host "============================================================================" -ForegroundColor Red
        exit $exitCode
    }
}
finally {
    # Удаление временного файла
    if (Test-Path $tempSqlFile) {
        Remove-Item $tempSqlFile -Force
    }
    
    # Очистка пароля из переменной окружения
    $env:PGPASSWORD = $null
}
