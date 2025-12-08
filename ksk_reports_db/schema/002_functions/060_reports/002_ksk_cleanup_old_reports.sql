-- ============================================================================
-- СЛУЖЕБНАЯ ФУНКЦИЯ: ksk_cleanup_old_reports
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет устаревшие отчёты на основе remove_date
--   Также удаляет файлы review-отчётов старше 7 дней
--   Рекомендуется запускать ежедневно в cron
--
-- ПАРАМЕТРЫ:
--   Нет
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - Общее количество удалённых записей
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
--   - Удаляет ksk_report_review_files старше 7 дней (жёсткая очистка)
--   - Записывает результат в системный лог
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование
--   2025-12-08 - Добавлена очистка ksk_report_review_files (7 дней)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_reports()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_headers INTEGER;
    v_deleted_review_files INTEGER;
    v_total_deleted INTEGER;
    v_start_time    TIMESTAMP := CLOCK_TIMESTAMP();
    v_status        VARCHAR := 'success';
    v_info          TEXT;
BEGIN
    -- 1. Удаление устаревших заголовков отчётов (CASCADE удалит связанные данные)
    DELETE FROM upoa_ksk_reports.ksk_report_header
    WHERE remove_date < CURRENT_DATE;

    GET DIAGNOSTICS v_deleted_headers = ROW_COUNT;

    -- 2. Удаление файлов review-отчётов старше 7 дней (жёсткая очистка)
    DELETE FROM upoa_ksk_reports.ksk_report_review_files
    WHERE report_date < CURRENT_DATE - INTERVAL '7 days';

    GET DIAGNOSTICS v_deleted_review_files = ROW_COUNT;

    -- Общее количество удалённых записей
    v_total_deleted := v_deleted_headers + v_deleted_review_files;

    v_info := FORMAT(
        'Удалено: заголовков отчётов: %s, файлов review (>7 дней): %s, всего: %s',
        v_deleted_headers,
        v_deleted_review_files,
        v_total_deleted
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

    RETURN v_total_deleted;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_old_reports() IS
    'Удаляет устаревшие отчёты (по remove_date) и файлы review старше 7 дней. CASCADE удаляет связанные данные.';
