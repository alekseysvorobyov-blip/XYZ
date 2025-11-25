-- ============================================================================
-- ФУНКЦИЯ 1: ksk_run_report
-- ============================================================================
-- ОПИСАНИЕ:
--   Универсальная функция для запуска генерации отчёта
--   Создаёт заголовок отчёта, вызывает функцию генерации и обновляет статус
--
-- ПАРАМЕТРЫ:
--   @p_report_code - Код отчёта из оркестратора
--   @p_initiator   - Инициатор ('system' или 'user')
--   @p_user_login  - Логин пользователя (NULL для system)
--   @p_start_date  - Начальная дата периода (включительно)
--   @p_end_date    - Конечная дата периода (ИСКЛЮЧАЯ, NULL = p_start_date + 1 day)
--   @p_parameters  - Дополнительные параметры в формате JSON
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданного заголовка отчёта
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--   При NULL end_date: отчёт за 1 день [start_date ... start_date+1day)
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   -- Системный отчёт за день (22 октября)
--   SELECT ksk_run_report('totals', 'system', NULL, '2025-10-22', NULL, NULL);
--   -- Результат: p_end_date = '2025-10-23', интервал [2025-10-22 ... 2025-10-23)
--
--   -- Пользовательский отчёт с фильтром по спискам
--   SELECT ksk_run_report('figurants', 'user', 'ivanov', '2025-10-20', '2025-10-23',
--                         '{"list_codes": ["4200", "4204"]}'::JSONB);
--
-- ЗАВИСИМОСТИ:
--   - ksk_report_orchestrator
--   - ksk_report_header
--   - Функции генерации отчётов (ksk_report_*)
--   - ksk_log_operation (для логирования)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование через ksk_log_operation
--   2025-11-26 - FIX: p_end_date исключающий, NULL = start_date + 1 day
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_run_report(
    p_report_code VARCHAR,
    p_initiator   VARCHAR,
    p_user_login  VARCHAR DEFAULT NULL,
    p_start_date  DATE DEFAULT CURRENT_DATE,
    p_end_date    DATE DEFAULT NULL,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_report_function VARCHAR;
    v_report_name VARCHAR;
    v_ttl INTEGER;
    v_header_id INTEGER;
    v_start_time TIMESTAMP := CLOCK_TIMESTAMP();
    v_status VARCHAR := 'success';
    v_error_msg TEXT := NULL;
    v_info TEXT;
BEGIN
    -- Валидация: end_date не может быть меньше start_date
    IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
        RAISE EXCEPTION 'end_date (%) не может быть меньше start_date (%)', p_end_date, p_start_date;
    END IF;

    -- Установка end_date по умолчанию (исключающий интервал [start_date ... start_date+1day))
    IF p_end_date IS NULL THEN
        p_end_date := (p_start_date + INTERVAL '1 day')::DATE;
    END IF;

    -- Получение метаданных из оркестратора
    SELECT
        id,
        report_function,
        name,
        CASE
            WHEN p_initiator = 'system' THEN system_ttl
            WHEN p_initiator = 'user' THEN user_ttl
        END
    INTO v_orchestrator_id, v_report_function, v_report_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE report_code = p_report_code;

    IF v_orchestrator_id IS NULL THEN
        RAISE EXCEPTION 'Отчёт с кодом % не найден', p_report_code;
    END IF;

    -- Создание заголовка отчёта
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
        v_report_name || ' (' || p_start_date || ' - ' || p_end_date || ')',
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

    -- Вызов функции генерации отчёта
    BEGIN
        EXECUTE FORMAT('SELECT %I($1, $2, $3, $4)', v_report_function)
        USING v_header_id, p_start_date, p_end_date, p_parameters;

        -- Обновление статуса на 'done'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'done',
            finished_datetime = NOW()
        WHERE id = v_header_id;

        v_info := FORMAT(
            'Отчёт %s создан успешно. Header ID: %s. Период: %s - %s',
            p_report_code, v_header_id, p_start_date, p_end_date
        );

    EXCEPTION WHEN OTHERS THEN
        v_status := 'error';
        v_error_msg := SQLERRM;

        -- Обновление статуса на 'error'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = v_header_id;

        v_info := FORMAT(
            'Ошибка создания отчёта %s. Header ID: %s. Период: %s - %s',
            p_report_code, v_header_id, p_start_date, p_end_date
        );

        RAISE WARNING 'Ошибка при генерации отчёта %: %', p_report_code, SQLERRM;
    END;

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'run_report_' || p_report_code,
        'Генерация отчёта: ' || v_report_name,
        v_start_time,
        v_status,
        v_info,
        v_error_msg
    );

    RETURN v_header_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_run_report(VARCHAR, VARCHAR, VARCHAR, DATE, DATE, JSONB) IS
    'Универсальная функция для запуска генерации отчёта. Фильтр [start_date..end_date). При NULL end_date = start_date + 1 day';
