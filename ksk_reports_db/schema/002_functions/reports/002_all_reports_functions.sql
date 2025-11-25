-- ============================================================================
-- ФУНКЦИИ ГЕНЕРАЦИИ ОТЧЁТОВ
-- ============================================================================

-- ============================================================================
-- СЛУЖЕБНАЯ ФУНКЦИЯ: ksk_cleanup_old_reports
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет устаревшие отчёты на основе remove_date
--   Рекомендуется запускать ежедневно в cron
--
-- ПАРАМЕТРЫ:
--   Нет
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - Количество удалённых отчётов
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_cleanup_old_reports();
--
-- ЗАМЕТКИ:
--   - Удаляет заголовки отчётов с remove_date < CURRENT_DATE
--   - Данные отчётов удаляются автоматически (CASCADE)
--   - Записывает результат в системный лог
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_reports()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
    v_start_time    TIMESTAMP := CLOCK_TIMESTAMP();
    v_status        VARCHAR := 'success';
    v_info          TEXT;
BEGIN
    DELETE FROM upoa_ksk_reports.ksk_report_header
    WHERE remove_date < CURRENT_DATE;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    v_info := FORMAT(
        'Удалено устаревших отчётов: %s',
        v_deleted_count
    );

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'cleanup_old_reports',
        'Очистка устаревших отчётов',
        v_start_time,
        v_status,
        v_info,
        NULL
    );

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_old_reports() IS 
    'Удаляет устаревшие отчёты на основе remove_date с логированием';

-- ============================================================================
-- КОНЕЦ ФАЙЛА
-- ============================================================================
