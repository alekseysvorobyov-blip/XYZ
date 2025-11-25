CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_register_header(
    p_report_code VARCHAR,
    p_initiator   VARCHAR,
    p_user_login  VARCHAR DEFAULT NULL,
    p_start_date  DATE DEFAULT CURRENT_DATE,
    p_end_date    DATE DEFAULT CURRENT_DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_name VARCHAR;
    v_ttl INTEGER;
    v_header_id INTEGER;
BEGIN
 -- Валидация: end_date не может быть меньше start_date
    IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
        RAISE EXCEPTION 'end_date (%) не может быть меньше start_date (%)', p_end_date, p_start_date;
    END IF;
    -- Установка end_date: исключающий интервал [start_date ... end_date)
    -- Если NULL или равны start_date → отчёт за 1 день
    IF p_end_date IS NULL OR p_end_date = p_start_date THEN
        p_end_date := (p_start_date + INTERVAL '1 day')::DATE;
    END IF;

    -- Получение метаданных из оркестратора
    SELECT
        id,
        name,
        CASE
            WHEN p_initiator = 'system' THEN system_ttl
            WHEN p_initiator = 'user' THEN user_ttl
        END
    INTO v_orchestrator_id, v_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE report_code = p_report_code;

    IF v_orchestrator_id IS NULL THEN
        RAISE EXCEPTION 'Отчёт с кодом % не найден', p_report_code;
    END IF;

    -- Вставка записи в ksk_report_header
    INSERT INTO upoa_ksk_reports.ksk_report_header (
        orchestrator_id,
        name,
        initiator,
        user_login,
        status,
        ttl,
        remove_date,
        start_date,
        end_date,
        parameters
    ) VALUES (
        v_orchestrator_id,
        v_name || ' (' || p_start_date || ' - ' || p_end_date || ')',
        p_initiator,
        p_user_login,
        'in_progress',
        v_ttl,
        CURRENT_DATE + v_ttl,
        p_start_date,
        p_end_date,
        p_parameters
    )
    RETURNING id INTO v_header_id;

    RETURN v_header_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_register_header(VARCHAR, VARCHAR, VARCHAR, DATE, DATE, JSONB) IS
    'Регистрирует заголовок отчёта. Фильтр [start_date..end_date). При равных датах = start_date + 1 day';