-- ============================================================================
-- ФУНКЦИЯ: ksk_cleanup_with_logging
-- ============================================================================
-- ОПИСАНИЕ:
--   Выполняет очистку пустых записей с записью результата в системный лог
--   Обёртка над ksk_cleanup_empty_records() с логированием
--
-- ПАРАМЕТРЫ:
--   @days_old - Возраст записей для удаления (по умолчанию: 14)
--
-- ВОЗВРАЩАЕТ:
--   TABLE:
--     - log_id                  INTEGER  - ID записи в логе
--     - empty_records_deleted   BIGINT   - Количество удалённых записей
--     - partitions_dropped      TEXT[]   - Удалённые партиции
--     - total_time              INTERVAL - Общее время
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_cleanup_with_logging();
--   SELECT * FROM ksk_cleanup_with_logging(7);
--
-- ЗАМЕТКИ:
--   - Рекомендуется запускать ежедневно в cron
--   - Результат записывается в ksk_system_operations_log
--   - После выполнения требуется VACUUM ANALYZE (запускать отдельно вне транзакции)
--     (см. документацию в README_cleanup_functions.md)
--
-- ЗАВИСИМОСТИ:
--   - ksk_cleanup_empty_records(INTEGER)
--   - ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из daily_ksk_cleanup_with_logging
--   2025-10-25 - Переход на системный лог (ksk_system_operations_log)
--   2025-10-25 - Удалён параметр perform_vacuum
-- ============================================================================

CREATE OR REPLACE FUNCTION ksk_cleanup_with_logging(
    days_old INTEGER DEFAULT 14
)
RETURNS TABLE(
    log_id                  INTEGER,
    empty_records_deleted   BIGINT,
    partitions_dropped      TEXT[],
    total_time              INTERVAL
) AS $$
DECLARE
    result          RECORD;
    new_log_id      INTEGER;
    v_start_time    TIMESTAMP := CLOCK_TIMESTAMP();
    v_status        VARCHAR := 'success';
    v_info          TEXT;
BEGIN
    -- Выполняем очистку
    SELECT * INTO result
    FROM upoa_ksk_reports.ksk_cleanup_empty_records(days_old)
    AS t(deleted_count BIGINT, dropped_partitions TEXT[], execution_time INTERVAL);

    -- Формирование информационного сообщения
    v_info := FORMAT(
        'Период: старше %s дней. Удалено записей: %s. Удалено партиций: %s. Время: %s',
        days_old,
        result.deleted_count,
        COALESCE(ARRAY_LENGTH(result.dropped_partitions, 1), 0),
        result.execution_time
    );

    -- Запись в системный лог
    SELECT upoa_ksk_reports.ksk_log_operation(
        'cleanup_empty_records',
        'Очистка пустых записей',
        v_start_time,
        v_status,
        v_info,
        NULL
    ) INTO new_log_id;

    RAISE NOTICE 'Очистка завершена и записана в лог (ID: %)', new_log_id;
    RAISE NOTICE '⚠️  РЕКОМЕНДАЦИЯ: Выполните VACUUM ANALYZE отдельным запросом';

    -- Возвращаем результаты
    RETURN QUERY SELECT
        new_log_id,
        result.deleted_count,
        result.dropped_partitions,
        result.execution_time;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_with_logging(INTEGER) IS 
    'Очистка пустых записей с записью результата в системный лог. После выполнения требуется VACUUM ANALYZE';
