#!/bin/bash

# ============================================================================
# Скрипт выполнения миграции PostgreSQL для системы отчётов КСК
# ВЕРСИЯ ДЛЯ WINDOWS (Git Bash)
# ============================================================================
# Описание:
#   - Устанавливает переменные окружения для PostgreSQL
#   - Выполняет SQL миграцию из файла
#   - Очищает переменные окружения после выполнения
#
# Использование:
#   ./run_migration_windows.sh
#   или
#   bash run_migration_windows.sh
#
# Требования:
#   - Git Bash (входит в Git for Windows)
#   - PostgreSQL установлен на Windows
#
# Автор: AI Assistant
# Дата: 27.10.2025
# ============================================================================

set -e  # Остановка при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "${BLUE}============================================${NC}"
echo "${BLUE}  Миграция PostgreSQL - Система КСК${NC}"
echo "${BLUE}  (Windows Git Bash)${NC}"
echo "${BLUE}============================================${NC}"
echo ""

# ============================================================================
# ШАГ 1: УСТАНОВКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ
# ============================================================================
echo "${YELLOW}[ШАГ 1/3]${NC} Установка переменных окружения..."

# --- НАСТРОЙКИ БАЗЫ ДАННЫХ (ИЗМЕНИТЕ НА СВОИ) ---
export PGHOST="localhost"           # Хост БД
export PGPORT="5432"                # Порт БД
export PGDATABASE="postgres"          # Имя базы данных
export PGUSER="postgres"            # Пользователь БД
export PGPASSWORD="sloart"   # Пароль (или используйте .pgpass)

# --- ПУТЬ К PSQL (WINDOWS) ---
# ВАРИАНТ 1: Стандартная установка PostgreSQL 15
PSQL_PATH="C:/Program Files/pgAdmin 4/runtime/psql.exe"

# ВАРИАНТ 2: PostgreSQL 14
# PSQL_PATH="C:/Program Files/PostgreSQL/14/bin/psql.exe"

# ВАРИАНТ 3: Если PostgreSQL в PATH (можно просто psql)
# PSQL_PATH="psql"

# --- ПУТЬ К ФАЙЛУ МИГРАЦИИ (WINDOWS) ---
# ВАЖНО: Используйте прямые слеши / вместо обратных \
# Git Bash понимает оба варианта, но / предпочтительнее

# Пример с абсолютным путём:
MIGRATION_FILE="D:\Yandex.Drive\Disk\YandexDisk\Документы\КСК\upoa_ksk_reports\ksk_reports_db\XYZ\ksk_reports_db\migrations\ksk_full_migration-20251127-003.sql"

# Пример с относительным путём (если скрипт в той же папке):
# MIGRATION_FILE="./ksk_full_migration-20251027-001.sql"

# Пример с сетевым диском:
# MIGRATION_FILE="//server/share/ksk/migrations/ksk_full_migration-20251027-001.sql"

# Проверка существования файла миграции
if [ ! -f "$MIGRATION_FILE" ]; then
    echo "${RED}✗ ОШИБКА: Файл миграции не найден!${NC}"
    echo "${RED}  Путь: $MIGRATION_FILE${NC}"
    echo ""
    echo "Подсказки для Windows:"
    echo "  - Используйте прямые слеши: C:/path/to/file.sql"
    echo "  - Проверьте права доступа к файлу"
    echo "  - Убедитесь что путь не содержит кириллицы"
    exit 1
fi

echo "${GREEN}✓ Переменные окружения установлены${NC}"
echo "  - Хост: $PGHOST"
echo "  - Порт: $PGPORT"
echo "  - База: $PGDATABASE"
echo "  - Пользователь: $PGUSER"
echo "  - PSQL: $PSQL_PATH"
echo "  - Файл миграции: $MIGRATION_FILE"
echo ""

# ============================================================================
# ШАГ 2: ВЫПОЛНЕНИЕ МИГРАЦИИ
# ============================================================================
echo "${YELLOW}[ШАГ 2/3]${NC} Запуск миграции..."
echo ""

# Проверка существования psql
if [ ! -f "$PSQL_PATH" ]; then
    echo "${RED}✗ ОШИБКА: psql.exe не найден!${NC}"
    echo "${RED}  Путь: $PSQL_PATH${NC}"
    echo ""
    echo "Подсказки:"
    echo "  - Проверьте версию PostgreSQL (14, 15, 16?)"
    echo "  - Стандартный путь: C:/Program Files/PostgreSQL/15/bin/psql.exe"
    echo "  - Или добавьте PostgreSQL в PATH"
    exit 1
fi

# Проверка подключения к БД
echo "${BLUE}→ Проверка подключения к БД...${NC}"
if ! "$PSQL_PATH" -c "SELECT version();" > /dev/null 2>&1; then
    echo "${RED}✗ ОШИБКА: Не удалось подключиться к базе данных!${NC}"
    echo "${RED}  Проверьте настройки подключения.${NC}"
    echo ""
    echo "Возможные причины:"
    echo "  - PostgreSQL сервис не запущен"
    echo "  - Неверный хост/порт/пользователь/пароль"
    echo "  - Firewall блокирует подключение"
    exit 1
fi
echo "${GREEN}✓ Подключение успешно${NC}"
echo ""

# Выполнение миграции
echo "${BLUE}→ Выполнение SQL миграции...${NC}"
echo "${BLUE}  (это может занять несколько минут)${NC}"
echo ""

# Запуск с логированием
LOG_FILE="migration_$(date +%Y%m%d_%H%M%S).log"

if "$PSQL_PATH" \
    -v ON_ERROR_STOP=1 \
    --echo-errors \
    -f "$MIGRATION_FILE" \
    2>&1 | tee "$LOG_FILE"; then

    echo ""
    echo "${GREEN}✓ Миграция выполнена успешно!${NC}"
    echo "${GREEN}  Лог сохранён: $LOG_FILE${NC}"
else
    echo ""
    echo "${RED}✗ ОШИБКА: Миграция завершилась с ошибкой!${NC}"
    echo "${RED}  Проверьте лог: $LOG_FILE${NC}"
    exit 1
fi

echo ""

# ============================================================================
# ШАГ 3: ОЧИСТКА ПЕРЕМЕННЫХ ОКРУЖЕНИЯ
# ============================================================================
echo "${YELLOW}[ШАГ 3/3]${NC} Очистка переменных окружения..."

unset PGHOST
unset PGPORT
unset PGDATABASE
unset PGUSER
unset PGPASSWORD

echo "${GREEN}✓ Переменные окружения очищены${NC}"
echo ""

# ============================================================================
# ЗАВЕРШЕНИЕ
# ============================================================================
echo "${GREEN}============================================${NC}"
echo "${GREEN}  ✓ Миграция завершена успешно!${NC}"
echo "${GREEN}============================================${NC}"
echo ""
echo "Следующие шаги:"
echo "  1. Проверьте структуру БД: \d+ ksk_report_header"
echo "  2. Проверьте функции: \df ksk_*"
echo "  3. Протестируйте отчёты"
echo ""
echo "Запустить psql:"
echo "  "$PSQL_PATH""
echo ""
