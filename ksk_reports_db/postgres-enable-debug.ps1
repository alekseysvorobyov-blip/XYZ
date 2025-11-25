# Определите путь к data каталогу
$PGVER = "16"
$PGDATA = "C:\Program Files\PostgreSQL\$PGVER\data\postgresql.conf"

# Откройте конфиг в Блокноте
#notepad $PGDATA

Get-Service | Where-Object {$_.Name -like "postgresql*"} | Select-Object Name, Status, DisplayName

#postgresql-16     Running postgresql-16    
#postgresql-x64-16 Stopped postgresql-x64-16
#postgresql-x64-18 Running postgresql-x64-18

Test-Path "C:\Program Files\PostgreSQL\16\lib\plugin_debugger.dll"
Test-Path "C:\Program Files\PostgreSQL\16\share\extension\pldbgapi.control"

#Get-Content "C:\Program Files\PostgreSQL\16\data\pg_log\*.log" -Tail 200 -
#Get-Content "C:\Program Files\PostgreSQL\16\data\log\*.log" -Tail 200 -Wait

Restart-Service postgresql-x64-16 -Force

