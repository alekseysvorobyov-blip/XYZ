-- ============================================================================
-- ФУНКЦИЯ 3: ksk_report_list_totals
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по итогам по спискам за период
--   Разворачивает массив list_codes и агрегирует по каждому коду
--
-- ПАРАМЕТРЫ:
--   @p_header_id   - ID заголовка отчёта
--   @p_start_date  - Начальная дата периода
--   @p_end_date    - Конечная дата периода
--   @p_parameters  - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ЗАМЕТКИ:
--   - Использует UNNEST для развёртывания массива list_codes
--   - Создаёт одну запись на каждый уникальный list_code
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и документация
--   Убран STRING_TO_ARRAY - list_codes уже массив TEXT[]
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals(
    p_report_header_id INTEGER,
    p_start_date DATE,
    p_end_date DATE,
    p_parameters JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_list_totals_data (
        report_header_id,
        list_code,
        total_with_list,
        total_without_list,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    )
    SELECT 
        p_report_header_id,
        list_code,
        COUNT(*) AS total_with_list,
        0 AS total_without_list,
        COUNT(*) FILTER (WHERE resolution = 'allow') AS total_allow,
        COUNT(*) FILTER (WHERE resolution = 'review') AS total_review,
        COUNT(*) FILTER (WHERE resolution = 'deny') AS total_deny,
        COUNT(*) FILTER (WHERE has_bypass = 'yes') AS total_bypass
    FROM upoa_ksk_reports.ksk_result,
         UNNEST(list_codes) AS list_code  -- БЕЗ STRING_TO_ARRAY!
    WHERE output_timestamp >= p_start_date::TIMESTAMP
      AND output_timestamp < (p_end_date + INTERVAL '1 day')::TIMESTAMP
    GROUP BY list_code
    ORDER BY list_code;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals(INTEGER, DATE, DATE, JSONB) IS 
    'Генерирует отчёт по итогам по спискам с разворачиванием массива list_codes';
