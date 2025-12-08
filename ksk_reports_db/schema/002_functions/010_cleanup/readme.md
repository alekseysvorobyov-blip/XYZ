# ФУНКЦИИ ОЧИСТКИ KSK

## Обзор функций

### 1. ksk_cleanup_empty_records()
**Назначение:** Удаление пустых записей (resolution='empty')

**Параметры:**
- `days_old` (INTEGER, по умолчанию: 14) - возраст записей для удаления

**Возвращает:**
- `deleted_count` - количество удалённых записей
- `dropped_partitions` - массив удалённых партиций
- `execution_time` - время выполнения

### 2. ksk_cleanup_with_logging()
**Назначение:** Очистка пустых записей с логированием

**Параметры:**
- `days_old` (INTEGER, по умолчанию: 14) - возраст записей для удаления

**Возвращает:**
- `log_id` - ID записи в системном логе
- `empty_records_deleted` - количество удалённых записей
- `partitions_dropped` - массив удалённых партиций
- `total_time` - общее время выполнения

### 3. ksk_cleanup_empty_partitions()
**Назначение:** Удаление полностью пустых партиций

**Параметры:**
- `table_name` (TEXT, по умолчанию: 'ksk_result') - имя таблицы или 'all'
- `days_old` (INTEGER, по умолчанию: 7) - возраст партиций для проверки

**Возвращает:**
- `TEXT[]` - массив имён удалённых партиций

---

## Рекомендации по применению

### Ежедневная очистка (рекомендуется)

**Шаг 1: Очистка пустых записей с логированием**
-- Запуск очистки
SELECT * FROM ksk_cleanup_with_logging(14);

**Шаг 2: VACUUM ANALYZE (ОБЯЗАТЕЛЬНО!)**

⚠️ **ВАЖНО:** VACUUM нельзя запустить внутри транзакции или функции.  
Необходимо выполнить **отдельным запросом** после очистки.
-- VACUUM для основных таблиц
VACUUM ANALYZE ksk_result;
VACUUM ANALYZE ksk_figurant;
VACUUM ANALYZE ksk_figurant_match;

-- Опционально: VACUUM для конкретных партиций (если известны)
VACUUM ANALYZE part_ksk_result_2025_10_20;
VACUUM ANALYZE part_ksk_result_2025_10_21;


---

### Еженедельная очистка пустых партиций
-- Проверка и удаление пустых партиций для всех таблиц
SELECT ksk_cleanup_empty_partitions('all', 7);


### Проверка освобождённого места
-- До очистки
SELECT pg_size_pretty(pg_total_relation_size('ksk_result')) AS table_size;
-- После очистки и VACUUM
SELECT pg_size_pretty(pg_total_relation_size('ksk_result')) AS table_size_after;









