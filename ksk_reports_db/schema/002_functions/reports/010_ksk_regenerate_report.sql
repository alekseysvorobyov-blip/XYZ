CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_regenerate_report(p_header_id INTEGER)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_report_table VARCHAR;
    v_result INTEGER;
    v_stack_trace TEXT;
    v_status TEXT;
    v_error_msg TEXT;
    v_info TEXT;
    v_log_id INTEGER;
BEGIN
    -- Получение orchestrator_id и report_table из ksk_report_header
    SELECT o.id, o.report_table
    INTO v_orchestrator_id, v_report_table
    FROM 
       upoa_ksk_reports.ksk_report_header h,
       upoa_ksk_reports.ksk_report_orchestrator o
    WHERE 
      h.id = p_header_id
      and h.orchestrator_id = o.id;

    IF v_orchestrator_id IS NULL THEN
        RAISE WARNING 'Запись с ID % не найдена в ksk_report_header', p_header_id;
        RETURN -1;
    END IF;

    -- Удаление данных из таблицы отчета
    EXECUTE FORMAT('DELETE FROM upoa_ksk_reports.%I WHERE report_header_id = %L', v_report_table, p_header_id);

    -- Обновление статуса на 'in_progress'
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'in_progress'
    WHERE id = p_header_id;

    -- Вызов функции ksk_report_create_report для регенерации отчета
    v_result := upoa_ksk_reports.ksk_report_create_report(p_header_id);

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Ошибка при регенерации отчета с ID %: %', p_header_id, SQLERRM;
    v_status := 'error';
    v_error_msg := SQLERRM;
    GET STACKED DIAGNOSTICS v_stack_trace = pg_exception_context;
    -- Обновление статуса на 'error'
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'error',
        finished_datetime = NOW()
    WHERE id = p_header_id;
    v_info := FORMAT('Ошибка регенерации отчета отчёта ksk_report_header.id: %s.', p_header_id);
        -- Логирование в системный лог
    v_log_id := upoa_ksk_reports.ksk_log_operation('ksk_regenerate_report', v_info, now()::timestamp(3),
      'error', v_info, v_error_msg || E'\nСтек-трейс:\n' || v_stack_trace);
    RETURN -1*v_log_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_regenerate_report(INTEGER) IS 
    'Функция для регенерации отчета по указанному header_id';



/*
DO $$
DECLARE
    rec integer;
    v_result INTEGER;
BEGIN
    -- Обход всех записей с статусом 'done'
    FOR rec IN
        SELECT id
        FROM upoa_ksk_reports.ksk_report_header
        WHERE status = 'done'
    LOOP
        -- Вызов функции ksk_regenerate_report для каждого отчета
        v_result := upoa_ksk_reports.ksk_regenerate_report(rec);

        -- Логирование результата
        IF v_result > 0 THEN
            RAISE NOTICE 'Отчет с ID % успешно регенерирован.', rec;
        ELSE
            RAISE WARNING 'Ошибка при регенерации отчета с ID %.', rec;
        END IF;
    END LOOP;
END $$;  
*/