-- ============================================================================
-- Функция: ksk_cleanup_old_logs
-- Описание: Удаление записей системного лога КСК старше N дней
-- Параметры: 
--   p_days_to_keep - количество дней для хранения (по умолчанию 365)
-- Возвращает: количество удалённых записей
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_logs(
    p_days_to_keep INTEGER DEFAULT 365
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_cutoff_date TIMESTAMP;
    v_deleted_count INTEGER;
    v_operation_code TEXT;
    v_start_time TIMESTAMP(3);
BEGIN
    v_start_time := now()::timestamp(3);
    v_operation_code := 'cleanup_logs_' || extract(epoch from v_start_time)::bigint;
    v_cutoff_date := now() - (p_days_to_keep || ' days')::interval;
    
    -- Удаляем старые записи
    DELETE FROM upoa_ksk_reports.ksk_system_operations_log
    WHERE begin_time < v_cutoff_date;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    -- Логируем только финальный результат
    PERFORM upoa_ksk_reports.ksk_log_operation(
        v_operation_code,
        'Очистка системного лога (старше ' || p_days_to_keep || ' дней)',
        v_start_time,
        'success',
        'Граничная дата: ' || v_cutoff_date::text || ', удалено записей: ' || v_deleted_count,
        NULL
    );
    
    RETURN v_deleted_count;
    
EXCEPTION WHEN OTHERS THEN
    -- Логируем ошибку
    PERFORM upoa_ksk_reports.ksk_log_operation(
        v_operation_code || '_error',
        'Ошибка при очистке лога',
        v_start_time,
        'error',
        NULL,
        SQLERRM
    );
    
    RAISE;
END;
$$;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_cleanup_old_logs(INTEGER) IS 
'Удаляет записи системного лога КСК старше указанного количества дней. По умолчанию хранит последние 365 дней.';
