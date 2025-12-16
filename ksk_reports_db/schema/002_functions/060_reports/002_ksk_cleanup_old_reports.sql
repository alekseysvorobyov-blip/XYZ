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
--   INTEGER - Количество удалённых заголовков отчётов
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_cleanup_old_reports();
--
-- ЗАМЕТКИ:
--   - Удаляет заголовки отчётов с remove_date < CURRENT_DATE
--   - Данные отчётов удаляются автоматически (CASCADE):
--     * ksk_report_totals_data
--     * ksk_report_list_totals_data
--     * ksk_report_totals_by_payment_type_data
--     * ksk_report_list_totals_by_payment_type_data
--     * ksk_report_figurants_data
--     * ksk_report_files
--     * ksk_report_review_data
--     * ksk_report_review_files
--   - Записывает результат в системный лог
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование
--   2025-12-08 - Добавлена очистка ksk_report_review_files (7 дней)
--   2025-12-16 - Удалена жёсткая очистка review_files (теперь CASCADE через header)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_reports()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_headers INTEGER;
    v_start_time      TIMESTAMP := CLOCK_TIMESTAMP();
    v_status          VARCHAR := 'success';
    v_info            TEXT;
BEGIN
    -- Удаление устаревших заголовков отчётов (CASCADE удалит связанные данные)
    -- Включая: ksk_report_review_data, ksk_report_review_files
    DELETE FROM upoa_ksk_reports.ksk_report_header
    WHERE remove_date < CURRENT_DATE;

    GET DIAGNOSTICS v_deleted_headers = ROW_COUNT;

    v_info := FORMAT(
        'Удалено заголовков отчётов: %s (данные удалены каскадно)',
        v_deleted_headers
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

    RETURN v_deleted_headers;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_old_reports() IS
    'Удаляет устаревшие отчёты по remove_date. CASCADE удаляет связанные данные (включая review_data и review_files).';
