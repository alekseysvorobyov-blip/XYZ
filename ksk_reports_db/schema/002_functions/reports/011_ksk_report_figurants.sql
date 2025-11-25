-- ============================================================================
-- ФУНКЦИЯ: ksk_report_figurants
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по фигурантам за период
--   ОПТИМИЗИРОВАНО: Использует структурированные поля вместо JSON
--   Поддерживает фильтрацию по кодам списков через параметры
--
-- ПАРАМЕТРЫ:
--   @p_header_id   - ID заголовка отчёта
--   @p_start_date  - Начальная дата периода
--   @p_end_date    - Конечная дата периода
--   @p_parameters  - JSON с опциональным полем "list_codes": ["4200", "4204"]
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- СТРУКТУРИРОВАННЫЕ ПОЛЯ ksk_figurant:
--   - list_code           TEXT
--   - name_figurant       TEXT
--   - president_group     TEXT
--   - auto_login          BOOLEAN
--   - has_exclusion       BOOLEAN
--   - exclusion_phrase    TEXT
--   - exclusion_name_list TEXT
--   - is_bypass           VARCHAR(10)
--   - resolution          VARCHAR(20)
--
-- ЗАМЕТКИ:
--   - Bypass-фигуранты исключены из расчёта total_allow, total_review, total_deny
--   - total = total_allow + total_review + total_deny + total_bypass
--
-- ПРИМЕР ПАРАМЕТРОВ:
--   NULL                                    -- Все списки
--   '{"list_codes": ["4200", "4204"]}'::JSONB  -- Фильтр по спискам
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Оптимизация: переход на структурированные поля
--   2025-11-20 - Добавлено поле exclusion_name_list - список исключений
--   2025-01-XX - Bypass-фигуранты исключены из расчёта разрешений
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_figurants(
    p_header_id   INTEGER,
    p_start_date  DATE,
    p_end_date    DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_list_codes TEXT[];
BEGIN
    -- Извлечение фильтра по спискам из параметров
    IF p_parameters IS NOT NULL AND p_parameters ? 'list_codes' THEN
        SELECT ARRAY_AGG(value::TEXT)
        INTO v_list_codes
        FROM JSONB_ARRAY_ELEMENTS_TEXT(p_parameters->'list_codes');
    END IF;

    INSERT INTO upoa_ksk_reports.ksk_report_figurants_data (
        report_header_id,
        list_code,
        name_figurant,
        president_group,
        auto_login,
        exclusion_phrase,
        exclusion_name_list,
        total,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    )
    SELECT
        p_header_id,        
        -- Структурированные поля (прямой доступ без извлечения из JSON)
        list_code,
        name_figurant,
        president_group,
        auto_login::TEXT AS auto_login,
        exclusion_phrase,
        exclusion_name_list,        
        -- Агрегированные счётчики
        COUNT(*) AS total,
        -- Bypass-фигуранты исключены из расчёта разрешений
        COUNT(*) FILTER (WHERE resolution = 'allow' AND is_bypass != 'yes') AS total_allow,
        COUNT(*) FILTER (WHERE resolution = 'review' AND is_bypass != 'yes') AS total_review,
        COUNT(*) FILTER (WHERE resolution = 'deny' AND is_bypass != 'yes') AS total_deny,
        COUNT(*) FILTER (WHERE is_bypass = 'yes') AS total_bypass        
    FROM upoa_ksk_reports.ksk_figurant
    WHERE "timestamp" >= p_start_date 
      AND "timestamp" < p_end_date  -- Исправлено: убрано + INTERVAL '1 day'
      -- Фильтр по list_codes (если указан)
      AND (v_list_codes IS NULL OR list_code = ANY(v_list_codes))
    GROUP BY
        list_code,
        name_figurant,
        president_group,
        auto_login,
        exclusion_phrase,
        exclusion_name_list
    ORDER BY total DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_figurants(INTEGER, DATE, DATE, JSONB) IS 
    'Генерирует отчёт по фигурантам с опциональной фильтрацией. Использует структурированные поля для максимальной производительности';