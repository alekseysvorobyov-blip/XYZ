# ============================================================================
# СКРИПТ: Merge-SqlFiles.ps1
# ============================================================================
# ОПИСАНИЕ:
#   Склеивает все .sql файлы из указанного каталога в один файл
#   Сортирует файлы по имени для предсказуемого порядка
#   Добавляет разделители между файлами для читаемости
#
# ИСПОЛЬЗОВАНИЕ:
#   .\Merge-SqlFiles.ps1
#   .\Merge-SqlFiles.ps1 -SourcePath "C:\sql" -OutputFile "merged.sql"
#
# ПАРАМЕТРЫ:
#   -SourcePath  : Путь к каталогу с SQL файлами (по умолчанию: текущий)
#   -OutputFile  : Имя выходного файла (по умолчанию: merged_<timestamp>.sql)
#   -Recursive   : Искать в подкаталогах (по умолчанию: false)
# ============================================================================


$SourcePath = "D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\ksk_reports_db\XYZ\ksk_reports_db\schema"
$OutputFile = "D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\ksk_reports_db\XYZ\ksk_reports_db\migrations\ksk_full_migration-20251208-001.sql"
$Recursive = $true


# Устанавливаем кодировку UTF-8 без BOM
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

# Если имя выходного файла не указано, генерируем его в текущем каталоге
if ([string]::IsNullOrEmpty($OutputFile)) {
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputFile = Join-Path (Get-Location) "merged_$timestamp.sql"
} else {
    # Проверяем, указан ли полный путь
    if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
        # Если относительный путь, делаем абсолютным относительно текущего каталога
        $OutputFile = Join-Path (Get-Location) $OutputFile
    }
    
    # Создаём родительский каталог, если его нет
    $parentDir = Split-Path -Parent $OutputFile
    if (-not (Test-Path $parentDir)) {
        Write-Host "Создаём каталог: $parentDir" -ForegroundColor Yellow
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }
}

# Получаем абсолютный путь
$OutputFilePath = [System.IO.Path]::GetFullPath($OutputFile)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  СКЛЕЙКА SQL ФАЙЛОВ" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Исходный каталог : $SourcePath" -ForegroundColor Yellow
Write-Host "Выходной файл    : $OutputFilePath" -ForegroundColor Yellow
Write-Host "Рекурсивный поиск: $Recursive" -ForegroundColor Yellow
Write-Host ""

# Получаем список SQL файлов
if ($Recursive) {
    $sqlFiles = Get-ChildItem -Path $SourcePath -Filter "*.sql" -Recurse | Sort-Object FullName
} else {
    $sqlFiles = Get-ChildItem -Path $SourcePath -Filter "*.sql" | Sort-Object Name
}

if ($sqlFiles.Count -eq 0) {
    Write-Host "ОШИБКА: SQL файлы не найдены в каталоге $SourcePath" -ForegroundColor Red
    exit 1
}

Write-Host "Найдено файлов: $($sqlFiles.Count)" -ForegroundColor Green
Write-Host ""

# Создаем/очищаем выходной файл
$null = New-Item -Path $OutputFilePath -ItemType File -Force

# Создаем StreamWriter для записи
$writer = [System.IO.StreamWriter]::new($OutputFilePath, $false, $Utf8NoBom)

try {
    # Записываем заголовок
    $header = @"
-- ============================================================================
-- ОБЪЕДИНЕННЫЙ SQL СКРИПТ
-- ============================================================================
-- Дата создания: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
-- Исходный каталог: $SourcePath
-- Количество файлов: $($sqlFiles.Count)
-- ============================================================================

"@
    $writer.WriteLine($header)

    # Обрабатываем каждый файл
    $fileNumber = 0
    foreach ($file in $sqlFiles) {
        $fileNumber++
        
        Write-Host "[$fileNumber/$($sqlFiles.Count)] $($file.Name)" -NoNewline
        
        # Разделитель между файлами
        $separator = @"

-- ============================================================================
-- ФАЙЛ: $($file.Name)
-- Путь: $($file.FullName)
-- Размер: $([math]::Round($file.Length / 1KB, 2)) KB
-- ============================================================================

"@
        $writer.WriteLine($separator)
        
        # Читаем содержимое файла
        try {
            $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
            $writer.WriteLine($content)
            
            Write-Host " [OK]" -ForegroundColor Green
        }
        catch {
            Write-Host " [ОШИБКА]" -ForegroundColor Red
            Write-Host "  Причина: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Записываем футер
    $footer = @"

-- ============================================================================
-- КОНЕЦ ОБЪЕДИНЕННОГО СКРИПТА
-- ============================================================================
-- Всего файлов обработано: $fileNumber
-- Дата завершения: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
-- ============================================================================
"@
    $writer.WriteLine($footer)
    
}
finally {
    # Закрываем writer
    $writer.Close()
}

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "  ГОТОВО!" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host ""
$NewPath = $OutputFilePath -replace '\.sql$', '.txt'
Copy-Item $OutputFilePath $NewPath
(Get-Content $NewPath) | Where-Object { $_ -notmatch '^\s*--' } | Set-Content $NewPath
$NewPath = $OutputFilePath -replace '\.sql$', '.txt2'
Copy-Item $OutputFilePath $NewPath
(Get-Content $NewPath) | Where-Object { $_ -notmatch '^\s*--' } | Set-Content $NewPath
Write-Host "Выходной файл: $OutputFilePath" -ForegroundColor Yellow
Write-Host "Размер: $([math]::Round((Get-Item $OutputFilePath).Length / 1KB, 2)) KB" -ForegroundColor Yellow
Write-Host ""

