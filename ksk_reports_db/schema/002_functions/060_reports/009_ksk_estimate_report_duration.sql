CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_estimate_report_duration(p_report_code VARCHAR)
RETURNS INTERVAL AS $$
DECLARE
    v_avg_duration INTERVAL;
BEGIN
    -- Получение среднего времени выполнения отчета
    SELECT AVG(finished_datetime - created_datetime) AS avg_duration
    INTO v_avg_duration
    FROM upoa_ksk_reports.ksk_report_header t
    WHERE 
      t.orchestrator_id in (select id from upoa_ksk_reports.ksk_report_orchestrator where report_code = p_report_code)
      AND status = 'done';

    -- Если нет данных, вернуть 2 минуты
    IF v_avg_duration IS NULL THEN
        RAISE NOTICE 'Нет данных для расчета среднего времени выполнения отчета %', p_report_code;
        RETURN INTERVAL '2 minutes';
    END IF;

    RETURN v_avg_duration;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_estimate_report_duration(VARCHAR) IS 
    'Функция для расчета приблизительного времени формирования отчета по указанному report_code';

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_estimate_report_duration_by_id(p_header_id INTEGER)
RETURNS INTERVAL AS $$
DECLARE
    v_days INTEGER;
    v_max_duration INTERVAL;
    v_orchestrator_id INTEGER;
    v_start_date DATE;
    v_end_date DATE;
    v_period INTERVAL;
BEGIN
    -- Получаем информацию о отчете по id
    SELECT orchestrator_id, start_date, end_date
    INTO v_orchestrator_id, v_start_date, v_end_date
    FROM upoa_ksk_reports.ksk_report_header
    WHERE id = p_header_id;

    IF v_orchestrator_id IS NULL THEN
        RAISE NOTICE 'Отчет с ID % не найден', p_header_id;
        RETURN INTERVAL '2 minutes';
    ELSE 
        RAISE NOTICE 'v_orchestrator_id % ', v_orchestrator_id;
    END IF;

    -- Рассчитываем количество дней для формирования отчета
    v_days := (v_end_date - v_start_date) + 1;
    RAISE NOTICE 'v_days % ', v_days;

    -- Ищем максимальное время формирования такого же типа отчета с таким же количеством дней
    SELECT MAX(finished_datetime - created_datetime) AS max_duration
    INTO v_max_duration
    FROM upoa_ksk_reports.ksk_report_header
    WHERE orchestrator_id = v_orchestrator_id
      AND status = 'done'
      AND (end_date - start_date) + 1 = v_days;

    -- Если нет данных с таким количеством дней, ищем максимальное время формирования такого же типа отчета с периодом 1 день
    IF v_max_duration < interval '10 seconds' THEN
        SELECT MAX(finished_datetime - created_datetime) AS max_duration
        INTO v_max_duration
        FROM upoa_ksk_reports.ksk_report_header
        WHERE orchestrator_id = v_orchestrator_id
          AND status = 'done'
          AND (end_date - start_date) + 1 = 1;
    END IF;

    -- Если все еще нет данных, возвращаем 2 минуты
    IF v_max_duration IS NULL THEN
        RAISE NOTICE 'Нет данных для расчета среднего времени выполнения отчета с orchestrator_id % с периодом % дней', v_orchestrator_id, v_days;
        RETURN INTERVAL '2 minutes';
    END IF;

    -- Умножаем найденное время на количество дней
    RETURN v_max_duration * v_days;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_estimate_report_duration_by_id(INTEGER) IS 
    'Функция для оценки продолжительности формирования отчета по указанному header_id';