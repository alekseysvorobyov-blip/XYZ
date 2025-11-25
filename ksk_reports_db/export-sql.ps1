# Скрипт для копирования SQL файлов в TXT с префиксом 'sql_' и иерархией в имени
# Использование: .\sql_to_txt.ps1 -SourceFolder "C:\schema" -DestFolder "C:\output"

# param(
#     [Parameter(Mandatory=$true)]
#     [string]$SourceFolder,
#     
#     [Parameter(Mandatory=$true)]
#     [string]$DestFolder
# )

$SourceFolder = "D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\deepseek\ksk_reports_db"
$DestFolder = "D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\deepseek\sql-only"

# Проверка существования папок
if (-not (Test-Path $SourceFolder)) {
    Write-Error "Папка источника не существует: $SourceFolder"
    exit 1
}

if (-not (Test-Path $DestFolder)) {
    Write-Host "Создаю папку назначения: $DestFolder"
    New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null
}

# Получаем все SQL файлы рекурсивно
$sqlFiles = Get-ChildItem -Path $SourceFolder -Filter "*.sql" -Recurse

if ($sqlFiles.Count -eq 0) {
    Write-Host "SQL файлы не найдены в $SourceFolder"
    exit 0
}

Write-Host "Найдено $($sqlFiles.Count) SQL файлов. Начинаю обработку..."
Write-Host ""

foreach ($file in $sqlFiles) {
    # Получаем относительный путь от исходной папки
    $relativePath = $file.FullName.Substring($SourceFolder.Length + 1)
    
    # Заменяем расширение .sql на пустую строку (для дальнейшей обработки)
    $pathWithoutExtension = $relativePath -replace '\.sql$', ''
    
    # Заменяем обратные слеши на подчеркивания
    $hierarchyPath = $pathWithoutExtension -replace '\\', '_'
    
    # Формируем новое имя с префиксом 'sql_' и расширением '.txt'
    $newFileName = "sql_$hierarchyPath.txt"
    
    # Путь к файлу назначения (в плоской структуре)
    $destPath = Join-Path $DestFolder $newFileName
    
    # Копируем файл
    Copy-Item -Path $file.FullName -Destination $destPath -Force
    
    Write-Host "✓ $relativePath"
    Write-Host "  → $newFileName"
    Write-Host ""
}

Write-Host "=========================================="
Write-Host "Готово! Все файлы скопированы в:"
Write-Host "$DestFolder"
Write-Host "=========================================="
