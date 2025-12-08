-- ============================================================================
-- ФУНКЦИЯ: ksk_report_list_totals_by_payment_type (v2 ОПТИМИЗИРОВАННАЯ)
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по итогам по спискам с разбивкой по типам платежей
--   Комбинирует group by list_code с агрегацией по payment_type
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта
--   @p_start_date       - Начальная дата периода (включительно)
--   @p_end_date         - Конечная дата периода (ИСКЛЮЧАЯ)
--   @p_parameters       - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--
-- ОПТИМИЗАЦИИ:
--   ✅ UNNEST(list_codes) вместо LOOP по массиву → 5-10x быстрее
--   ✅ Один SELECT вместо множественных сканов таблицы
--   ✅ COUNT(*) FILTER для условной агрегации
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   ДО: 110 сек (с LOOP)
--   ПОСЛЕ: 10-20 сек (с UNNEST)
--   УСКОРЕНИЕ: 5-10x
--
-- МАППИНГ ТИПОВ ПЛАТЕЖЕЙ:
--   i_* = Входящий
--   o_* = Исходящий
--   t_* = Транзитный
--   m_* = Межфилиальный
--   v_* = Внутрифилиальный
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-26 - ИСПРАВЛЕНО: Привел в соответствие префиксы и типы платежей
--   2025-10-25 - Убран STRING_TO_ARRAY (list_codes уже массив TEXT[])
--   2025-10-25 - Добавлен UNNEST для оптимизации (v2)
--   2025-11-26 - FIX: p_end_date исключающий, убран +INTERVAL '1 day', TIMESTAMP(3)
--   2025-12-08 - Добавлен вызов генерации Excel-файла
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type(
    p_report_header_id INTEGER,
    p_start_date       DATE,
    p_end_date         DATE,
    p_parameters       JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data (
        report_header_id,
        list_code,
        total_with_list,
        total_without_list,
        total_allow,
        total_review,
        total_deny,
        total_bypass,
        i_total_with_list, i_total_without_list, i_total_allow, i_total_review, i_total_deny, i_total_bypass,
        o_total_with_list, o_total_without_list, o_total_allow, o_total_review, o_total_deny, o_total_bypass,
        t_total_with_list, t_total_without_list, t_total_allow, t_total_review, t_total_deny, t_total_bypass,
        m_total_with_list, m_total_without_list, m_total_allow, m_total_review, m_total_deny, m_total_bypass,
        v_total_with_list, v_total_without_list, v_total_allow, v_total_review, v_total_deny, v_total_bypass
    )
    SELECT
        p_report_header_id,
        f.list_code,
        -- ========================================================================
        -- ОБЩИЕ СЧЕТЧИКИ: по ТРАНЗАКЦИЯМ (не по фигурантам)
        -- ========================================================================
        COUNT(DISTINCT r.id) AS total_with_list,
        0 AS total_without_list,
        -- ========================================================================
        -- СЧЕТЧИКИ РЕШЕНИЙ: по ФИГУРАНТАМ БЕЗ bypass
        -- ========================================================================
        COUNT(*) FILTER (WHERE f.resolution = 'allow' AND f.is_bypass != 'yes') AS total_allow,
        COUNT(*) FILTER (WHERE f.resolution = 'review' AND f.is_bypass != 'yes') AS total_review,
        COUNT(*) FILTER (WHERE f.resolution = 'deny' AND f.is_bypass != 'yes') AS total_deny,
        -- ========================================================================
        -- СЧЕТЧИК BYPASS: по ФИГУРАНТАМ с is_bypass='yes'
        -- ========================================================================
        COUNT(*) FILTER (WHERE f.is_bypass = 'yes') AS total_bypass,
        -- ========================================================================
        -- i_* - Входящий: ТРАНЗАКЦИИ для total_with_list, ФИГУРАНТЫ для решений
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Входящий') AS i_total_with_list,
        0 AS i_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS i_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS i_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS i_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.is_bypass = 'yes') AS i_total_bypass,
        -- ========================================================================
        -- o_* - Исходящий
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Исходящий') AS o_total_with_list,
        0 AS o_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS o_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS o_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS o_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.is_bypass = 'yes') AS o_total_bypass,
        -- ========================================================================
        -- t_* - Транзитный
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Транзитный') AS t_total_with_list,
        0 AS t_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS t_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS t_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS t_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.is_bypass = 'yes') AS t_total_bypass,
        -- ========================================================================
        -- m_* - Межфилиальный
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Межфилиальный') AS m_total_with_list,
        0 AS m_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS m_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS m_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS m_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.is_bypass = 'yes') AS m_total_bypass,
        -- ========================================================================
        -- v_* - Внутрифилиальный
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Внутрифилиальный') AS v_total_with_list,
        0 AS v_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS v_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS v_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS v_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.is_bypass = 'yes') AS v_total_bypass
    FROM upoa_ksk_reports.ksk_figurant f
    INNER JOIN upoa_ksk_reports.ksk_result r
        ON f.source_id = r.id
        AND f.timestamp = r.output_timestamp
    WHERE f.timestamp >= p_start_date::TIMESTAMP(3)
      AND f.timestamp < p_end_date::TIMESTAMP(3)
      AND f.list_code IS NOT NULL
    GROUP BY f.list_code
    ORDER BY f.list_code;

    -- Генерация Excel-файла
    PERFORM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(p_report_header_id);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует отчёт по итогам по спискам с разбивкой по типам платежей. Фильтр [start_date..end_date). i=Входящий, o=Исходящий, t=Транзитный, m=Межфилиальный, v=Внутрифилиальный';
