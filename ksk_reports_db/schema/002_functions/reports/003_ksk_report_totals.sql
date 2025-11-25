-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals
-- ============================================================================
-- ОПИСАНИЕ:
-- Генерирует отчёт по общей статистике за период
-- Подсчитывает количество транзакций по резолюциям
--
-- ПАРАМЕТРЫ:
-- @p_header_id   - ID заголовка отчёта
-- @p_start_date  - Начальная дата периода
-- @p_end_date    - Конечная дата периода
-- @p_parameters  - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
-- VOID
--
-- ЗАМЕТКИ:
-- - Вызывается через ksk_run_report()
-- - Создаёт одну запись в ksk_report_totals_data
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
-- 2025-10-25 - Форматирование и документация
-- 2025-11-26 - FIX: total_bypass теперь по resolution='bypass', не has_bypass
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals(
    p_header_id   INTEGER,
    p_start_date  DATE,
    p_end_date    DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_totals_data (
        report_header_id,
        total,
        total_without_result,
        total_with_result,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    )
    SELECT
        p_header_id,
        COUNT(*)                                              AS total,
        COUNT(*) FILTER (WHERE resolution = 'empty')          AS total_without_result,
        COUNT(*) FILTER (WHERE resolution != 'empty')         AS total_with_result,
        COUNT(*) FILTER (WHERE resolution = 'allow')          AS total_allow,
        COUNT(*) FILTER (WHERE resolution = 'review')         AS total_review,
        COUNT(*) FILTER (WHERE resolution = 'deny')           AS total_deny,
        COUNT(*) FILTER (WHERE resolution = 'bypass')         AS total_bypass  -- FIX
    FROM upoa_ksk_reports.ksk_result
    WHERE output_timestamp >= p_start_date
      AND output_timestamp < (p_end_date + INTERVAL '1 day');
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals(INTEGER, DATE, DATE, JSONB) IS
'Генерирует отчёт по общей статистике за период. v2: bypass как отдельный resolution';
