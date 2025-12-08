-- ============================================================================
-- ФУНКЦИЯ: ksk_list_partitions
-- ============================================================================
-- ОПИСАНИЕ:
--   Возвращает информацию о всех партициях таблиц КСК
--   Включает размер, диапазон и примерное количество записей
--
-- ПАРАМЕТРЫ:
--   Нет
--
-- ВОЗВРАЩАЕТ:
--   TABLE:
--     - table_name         TEXT   - Имя родительской таблицы
--     - partition_name     TEXT   - Имя партиции
--     - partition_range    TEXT   - Диапазон значений партиции
--     - total_size         TEXT   - Размер партиции (человекочитаемый)
--     - estimated_records  BIGINT - Примерное количество записей
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_list_partitions();
--   SELECT * FROM ksk_list_partitions() WHERE table_name = 'ksk_result';
--   SELECT * FROM ksk_list_partitions() ORDER BY total_size DESC LIMIT 10;
--
-- ЗАМЕТКИ:
--   - estimated_records - это грубая оценка (размер / 1000 байт)
--   - Отсортировано по имени таблицы и партиции
--   - Используется для мониторинга роста БД
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из list_all_ksk_partitions
--   2025-10-25 - Изменён возвращаемый тип с DATE на TEXT для совместимости с REGEXP_MATCH
-- ============================================================================
CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_list_partitions(
    p_table_name TEXT DEFAULT 'ksk_result'
)
RETURNS TABLE (
    partition_name      TEXT,
    partition_date      TEXT,
    partition_date_next TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        child.relname::TEXT AS partition_name,
        (REGEXP_MATCH(child.relname, '\d{4}_\d{2}_\d{2}'))[1]::TEXT AS partition_date,
        ((REGEXP_MATCH(child.relname, '\d{4}_\d{2}_\d{2}'))[1]::DATE + INTERVAL '1 day')::TEXT AS partition_date_next
    FROM pg_inherits i
    JOIN pg_class parent ON parent.oid = i.inhparent
    JOIN pg_class child ON child.oid = i.inhrelid
    JOIN pg_namespace n ON n.oid = parent.relnamespace
    WHERE n.nspname = 'upoa_ksk_reports'
      AND parent.relname = p_table_name
    ORDER BY child.relname;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_list_partitions(TEXT) IS 
    'Возвращает список партиций для указанной таблицы с датами начала и конца';
