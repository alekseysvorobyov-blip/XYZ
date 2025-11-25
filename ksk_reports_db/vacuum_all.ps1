<#
.\Vacuum-KSK-Tables.ps1 `
    -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
    -PasswordFile "C:\secure\db_password.txt" `
    -DbName "ksk_db" `
    -DbUser "postgres"

.\Vacuum-KSK-Tables.ps1 `
    -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
    -PasswordFile "C:\secure\db_password.txt" `
    -DbName "ksk_db" `
    -DbUser "postgres" `
    -VacuumType "VACUUM FULL"

.\Vacuum-KSK-Tables.ps1 `
    -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
    -PasswordFile "C:\secure\db_password.txt" `
    -DbHost "192.168.1.100" `
    -DbPort 5432 `
    -DbName "ksk_db" `
    -DbUser "ksk_user"


.SYNOPSIS
    Выполняет VACUUM на всех таблицах и партициях КСК
.DESCRIPTION
    Скрипт подключается к PostgreSQL через psql и выполняет VACUUM 
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
.PARAMETER VacuumType
    Тип VACUUM: 'VACUUM' (по умолчанию) или 'VACUUM FULL'
.EXAMPLE
    .\Vacuum-KSK-Tables.ps1 `
        -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
        -PasswordFile "C:\secure\db_password.txt" `
        -DbName "ksk_db" `
        -DbUser "postgres"
.EXAMPLE
    .\Vacuum-KSK-Tables.ps1 `
        -PsqlPath "C:\Program Files\PostgreSQL\15\bin\psql.exe" `
        -PasswordFile "C:\secure\db_password.txt" `
        -DbName "ksk_db" `
        -DbUser "postgres" `
        -VacuumType "VACUUM FULL"
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
    [string]$DbUser,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("VACUUM", "VACUUM FULL")]
    [string]$VacuumType = "VACUUM"
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
Write-Host "VACUUM таблиц КСК" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Тип операции: $VacuumType" -ForegroundColor Yellow
Write-Host ""

# SQL-скрипт для VACUUM
$sqlScript = @"
-- ============================================================================
-- VACUUM всех таблиц КСК в схеме upoa_ksk_reports
-- ============================================================================

\timing on

\echo ''
\echo '============================================================================'
\echo 'Начало $VacuumType таблиц КСК'
\echo '============================================================================'
\echo ''

-- Основные таблицы (родительские)
\echo '--- Основные таблицы ---'

\echo '$VacuumType ksk_result...'
$VacuumType upoa_ksk_reports.ksk_result;

\echo '$VacuumType ksk_figurant...'
$VacuumType upoa_ksk_reports.ksk_figurant;

\echo '$VacuumType ksk_figurant_match...'
$VacuumType upoa_ksk_reports.ksk_figurant_match;

-- Служебные таблицы
\echo ''
\echo '--- Служебные таблицы ---'

\echo '$VacuumType ksk_system_operations_log...'
$VacuumType upoa_ksk_reports.ksk_system_operations_log;

-- Таблицы отчётов
\echo ''
\echo '--- Таблицы отчётов ---'

\echo '$VacuumType ksk_report_orchestrator...'
$VacuumType upoa_ksk_reports.ksk_report_orchestrator;

\echo '$VacuumType ksk_report_header...'
$VacuumType upoa_ksk_reports.ksk_report_header;

\echo '$VacuumType ksk_report_totals_data...'
$VacuumType upoa_ksk_reports.ksk_report_totals_data;

\echo '$VacuumType ksk_report_list_totals_data...'
$VacuumType upoa_ksk_reports.ksk_report_list_totals_data;

\echo '$VacuumType ksk_report_totals_by_payment_type_data...'
$VacuumType upoa_ksk_reports.ksk_report_totals_by_payment_type_data;

\echo '$VacuumType ksk_report_list_totals_by_payment_type_data...'
$VacuumType upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data;

\echo '$VacuumType ksk_report_figurants_data...'
$VacuumType upoa_ksk_reports.ksk_report_figurants_data;

-- Партиции (все автоматически)
\echo ''
\echo '--- Партиции ---'

DO `$`$
DECLARE
    partition_record RECORD;
    partition_count INTEGER := 0;
    vacuum_command TEXT := '$VacuumType';
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
        EXECUTE FORMAT('%s upoa_ksk_reports.%I', vacuum_command, partition_record.partition_name);
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
        EXECUTE FORMAT('%s upoa_ksk_reports.%I', vacuum_command, partition_record.partition_name);
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
        EXECUTE FORMAT('%s upoa_ksk_reports.%I', vacuum_command, partition_record.partition_name);
        partition_count := partition_count + 1;
    END LOOP;
    
    RAISE NOTICE '$VacuumType выполнен для % партиций', partition_count;
END `$`$;

\echo ''
\echo '============================================================================'
\echo '$VacuumType завершён успешно'
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
    
    if ($VacuumType -eq "VACUUM FULL") {
        Write-Host "ВНИМАНИЕ: VACUUM FULL блокирует таблицы на время выполнения!" -ForegroundColor Red
        Write-Host "Это может занять много времени на больших таблицах." -ForegroundColor Red
        Write-Host ""
        
        $confirmation = Read-Host "Продолжить? (yes/no)"
        if ($confirmation -ne "yes") {
            Write-Host "Операция отменена пользователем." -ForegroundColor Yellow
            exit 0
        }
    }
    
    # Установка пароля в переменную окружения
    $env:PGPASSWORD = $password
    
    # Выполнение скрипта через psql
    & $PsqlPath -h $DbHost -p $DbPort -U $DbUser -d $DbName -f $tempSqlFile
    
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Host ""
        Write-Host "============================================================================" -ForegroundColor Green
        Write-Host "$VacuumType выполнен успешно!" -ForegroundColor Green
        Write-Host "============================================================================" -ForegroundColor Green
        
        if ($VacuumType -eq "VACUUM") {
            Write-Host ""
            Write-Host "Рекомендация: Запустите ANALYZE для обновления статистики" -ForegroundColor Cyan
            Write-Host "  .\Analyze-KSK-Tables.ps1 -PsqlPath ""$PsqlPath"" -PasswordFile ""$PasswordFile"" -DbName ""$DbName"" -DbUser ""$DbUser""" -ForegroundColor Cyan
        }
    } else {
        Write-Host ""
        Write-Host "============================================================================" -ForegroundColor Red
        Write-Host "ОШИБКА при выполнении $VacuumType (код выхода: $exitCode)" -ForegroundColor Red
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
