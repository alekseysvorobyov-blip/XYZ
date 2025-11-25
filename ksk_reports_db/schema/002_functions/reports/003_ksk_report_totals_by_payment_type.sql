-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals_by_payment_type
-- ============================================================================
-- ОПИСАНИЕ:
-- Генерирует отчёт по статистике с разбивкой по типам платежей
-- Создаёт агрегации для каждого из 5 типов платежей (русские названия)
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
-- - Создаёт одну запись со всеми типами платежей
-- - Типы платежей (русские названия):
--   • i_ - Входящий
--   • o_ - Исходящий
--   • t_ - Транзитный
--   • m_ - Межфилиальный
--   • v_ - Внутрифилиальный
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
-- 2025-10-25 - Исправлено использование русских названий типов платежей
-- 2025-11-26 - FIX: total_bypass теперь по resolution='bypass', не has_bypass
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type(
    p_header_id   INTEGER,
    p_start_date  DATE,
    p_end_date    DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_totals_by_payment_type_data (
        report_header_id,
        total, total_without_result, total_with_result,
        total_allow, total_review, total_deny, total_bypass,
        i_total, i_total_without_result, i_total_with_result,
        i_total_allow, i_total_review, i_total_deny, i_total_bypass,
        o_total, o_total_without_result, o_total_with_result,
        o_total_allow, o_total_review, o_total_deny, o_total_bypass,
        t_total, t_total_without_result, t_total_with_result,
        t_total_allow, t_total_review, t_total_deny, t_total_bypass,
        m_total, m_total_without_result, m_total_with_result,
        m_total_allow, m_total_review, m_total_deny, m_total_bypass,
        v_total, v_total_without_result, v_total_with_result,
        v_total_allow, v_total_review, v_total_deny, v_total_bypass
    )
    SELECT
        p_header_id,
        -- Общие счётчики
        COUNT(*),
        COUNT(*) FILTER (WHERE resolution = 'empty'),
        COUNT(*) FILTER (WHERE resolution != 'empty'),                          -- FIX: != вместо вычитания
        COUNT(*) FILTER (WHERE resolution = 'allow'),
        COUNT(*) FILTER (WHERE resolution = 'review'),
        COUNT(*) FILTER (WHERE resolution = 'deny'),
        COUNT(*) FILTER (WHERE resolution = 'bypass'),                          -- FIX!
        -- Входящий
        COUNT(*) FILTER (WHERE payment_type = 'Входящий'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'bypass'),  -- FIX!
        -- Исходящий
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'bypass'),  -- FIX!
        -- Транзитный
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'bypass'),  -- FIX!
        -- Межфилиальный
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'bypass'),  -- FIX!
        -- Внутрифилиальный
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'bypass')  -- FIX!
    FROM upoa_ksk_reports.ksk_result
    WHERE output_timestamp >= p_start_date
      AND output_timestamp < (p_end_date + INTERVAL '1 day');
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type(INTEGER, DATE, DATE, JSONB) IS
'Генерирует отчёт по статистике с разбивкой по типам платежей. v2: bypass как resolution';
