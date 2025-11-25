CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_create_report(p_header_id INTEGER)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_report_function VARCHAR;
    v_report_name VARCHAR;
    v_ttl INTERVAL;
    v_start_time TIMESTAMP;
    v_status VARCHAR := 'success';
    v_info TEXT;
    v_error_msg TEXT;
    v_stack_trace TEXT;
    rec RECORD;
    v_log_id INTEGER;
BEGIN
    -- Получение записи из ksk_report_header
    SELECT id, orchestrator_id, initiator, user_login, start_date, end_date, parameters, status
    INTO rec
    FROM upoa_ksk_reports.ksk_report_header
    WHERE id = p_header_id;

    IF rec.id IS NULL THEN
        RAISE WARNING 'Запись с ID % не найдена в ksk_report_header', p_header_id;
        v_info := FORMAT('Запись с ID %s не найдена в ksk_report_header', p_header_id);
        v_error_msg := 'Запись не найдена';

        -- Логирование в системный лог
        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            'error',
            v_info,
            v_error_msg
        );

        RETURN -1*v_log_id;
    END IF;

    -- Проверка статуса
    IF rec.status NOT IN ('created', 'in_progress') THEN
        RAISE WARNING 'Статус записи с ID % не соответствует "created" или "in_progress". Текущий статус: %', p_header_id, rec.status;
        v_info := FORMAT('Статус записи с ID %s не соответствует "created" или "in_progress". Текущий статус: %s', p_header_id, rec.status);
        v_error_msg := 'Недопустимый статус';

        -- Логирование в системный лог
        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            'error',
            v_info,
            v_error_msg
        );

        RETURN -1*v_log_id;
    END IF;

    -- Установка end_date по умолчанию
    IF rec.end_date IS NULL THEN
        rec.end_date := rec.start_date;
    END IF;

    -- Получение метаданных из оркестратора
    SELECT 
        id,
        report_function,
        name,
        CASE 
            WHEN rec.initiator = 'system' THEN system_ttl
            WHEN rec.initiator = 'user' THEN user_ttl
            ELSE NULL
        END
    INTO v_orchestrator_id, v_report_function, v_report_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE id = rec.orchestrator_id;

    IF v_orchestrator_id IS NULL THEN
        v_status := 'error';
        v_info := FORMAT('Отчет с orchestrator_id %s не найден. Header ID: %s', rec.orchestrator_id, rec.id);
        v_error_msg := 'Отчет не найден в оркестраторе';

        -- Обновление статуса на 'error'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        -- Логирование в системный лог
        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            v_status,
            v_info,
            v_error_msg
        );

        RAISE WARNING 'Отчет с orchestrator_id % не найден. Header ID: %', rec.orchestrator_id, rec.id;

        RETURN -1*v_log_id;
    END IF;

    -- Проверка v_ttl на NULL
    IF v_ttl IS NULL THEN
        v_status := 'error';
        v_info := FORMAT('Не задан TTL для отчета с orchestrator_id %s. Header ID: %s', rec.orchestrator_id, rec.id);
        v_error_msg := 'Не задан TTL';

        -- Обновление статуса на 'error'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        -- Логирование в системный лог
        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            v_status,
            v_info,
            v_error_msg
        );

        RAISE WARNING 'Не задан TTL для отчета с orchestrator_id %: Header ID: %', rec.orchestrator_id, rec.id;

        RETURN -1*v_log_id;
    END IF;

    -- Обновление статуса на 'in_progress'
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'in_progress'
    WHERE id = rec.id;

    -- Вызов функции генерации отчёта
    BEGIN
        v_start_time := CLOCK_TIMESTAMP();

        EXECUTE FORMAT('SELECT %I($1, $2, $3, $4)', v_report_function)
        USING rec.id, rec.start_date, rec.end_date, rec.parameters;

        -- Обновление статуса на 'done'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'done',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_info := FORMAT(
            'Отчёт %s создан успешно. Header ID: %s. Период: %s - %s',
            v_report_name, rec.id, rec.start_date, rec.end_date
        );

        -- Логирование в системный лог
        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            v_start_time,
            'success',
            v_info,
            ''
        );

        RETURN rec.id;

    EXCEPTION WHEN OTHERS THEN
        v_status := 'error';
        v_error_msg := SQLERRM;
        GET STACKED DIAGNOSTICS v_stack_trace = pg_exception_context;

        -- Обновление статуса на 'error'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_info := FORMAT(
            'Ошибка создания отчёта %s. Header ID: %s. Период: %s - %s',
            v_report_name, rec.id, rec.start_date, rec.end_date
        );

        -- Логирование в системный лог
        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            v_start_time,
            'error',
            v_info,
            v_error_msg || E'\nСтек-трейс:\n' || v_stack_trace
        );

        RAISE WARNING 'Ошибка при генерации отчёта %: %\nСтек-трейс:\n%', v_report_name, SQLERRM, v_stack_trace;

        RETURN -1*v_log_id;
    END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_create_report(INTEGER) IS 
    'Функция для создания отчета по указанному header_id';