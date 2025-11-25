-- ============================================================================
-- ФУНКЦИЯ 3: ksk_report_list_totals
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по итогам по спискам за период
--   Агрегирует данные фигурантов по кодам списков
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта
--   @p_start_date       - Начальная дата периода (DATE)
--   @p_end_date         - Конечная дата периода (DATE)
--   @p_parameters       - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ИСТОЧНИК ДАННЫХ:
--   ksk_figurant - денормализованная таблица фигурантов
--   Поля: list_code, resolution, is_bypass, source_id, timestamp
--
-- ЛОГИКА:
--   1. Агрегирует по list_code (TEXT)
--   2. total_with_list = COUNT(DISTINCT source_id) - уникальные транзакции
--   3. allow/review/deny - исключены фигуранты с is_bypass='yes'
--   4. bypass - фигуранты с is_bypass='yes'
--
-- ЗАМЕТКИ:
--   - Источник данных: таблица ksk_figurant (денормализованные поля)
--   - Агрегирует решения фигурантов (resolution, is_bypass)
--   - Фигуранты с is_bypass='yes' не учитываются в allow/review/deny
--   - Все поля в snake_case согласно правилам пространства КСК
--   - Фильтрация по timestamp (партиционирование и BRIN индекс)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и документация
--   Убран STRING_TO_ARRAY - list_codes уже массив TEXT[]
--   2025-11-25 - Переделана логика: JOIN на ksk_figurant вместо ksk_result
--   2025-11-25 - Исправлена фильтрация даты и исключение bypass из счетчиков
--   2025-11-25 - Переведено на денормализованные поля ksk_figurant
--   2025-11-25 - Исправлено имя поля: source_id (snake_case)
--   2025-11-25 - Переведена фильтрация на timestamp (вместо date) для оптимизации
--   2025-11-25 - Убран INTERVAL '1 day' - фильтрация только до конца дня
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
        fig.list_code,
        COUNT(DISTINCT fig.source_id) AS total_with_list,
        0 AS total_without_list,
        COUNT(*) FILTER (WHERE fig.resolution = 'allow' AND fig.is_bypass != 'yes') AS total_allow,
        COUNT(*) FILTER (WHERE fig.resolution = 'review' AND fig.is_bypass != 'yes') AS total_review,
        COUNT(*) FILTER (WHERE fig.resolution = 'deny' AND fig.is_bypass != 'yes') AS total_deny,
        COUNT(*) FILTER (WHERE fig.is_bypass = 'yes') AS total_bypass
    FROM upoa_ksk_reports.ksk_figurant fig
    WHERE fig.timestamp >= (p_start_date::DATE)::TIMESTAMP
      AND fig.timestamp < (p_end_date::DATE)::TIMESTAMP
    GROUP BY fig.list_code
    ORDER BY fig.list_code;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals(INTEGER, DATE, DATE, JSONB) IS 
    'Генерирует отчёт по итогам по спискам с агрегацией данных фигурантов';
