--upoa_ksk_reports.ksk_report_register_header
--upoa_ksk_reports.ksk_report_create_report
--upoa_ksk_reports.ksk_report_create_all_reports
--upoa_ksk_reports.ksk_estimate_report_duration
--upoa_ksk_reports.ksk_estimate_report_duration_by_id

SELECT *
FROM upoa_ksk_reports.ksk_report_header
order by id desc;

SELECT *
FROM upoa_ksk_reports.ksk_report_totals_data
order by id desc;

SELECT *
FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data
order by id desc;

SELECT *
FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data
order by id desc;


SELECT *
FROM upoa_ksk_reports.part_ksk_result_2025_11_07;

DELETE FROM upoa_ksk_reports.part_ksk_result_default;
SELECT upoa_ksk_reports.ksk_create_partitions_for_all_tables('2025-11-08', 30);
SELECT upoa_ksk_reports.ksk_create_partitions_for_all_tables('2025-12-08', 30);
SELECT upoa_ksk_reports.ksk_create_partitions_for_all_tables('2026-01-08', 30);
SELECT upoa_ksk_reports.ksk_create_partitions_for_all_tables('2026-02-08', 30);


SELECT upoa_ksk_reports.ksk_estimate_report_duration('totals');
SELECT upoa_ksk_reports.ksk_estimate_report_duration('totals_by_payment_type');
SELECT upoa_ksk_reports.ksk_estimate_report_duration('list_totals');
SELECT upoa_ksk_reports.ksk_estimate_report_duration('list_totals_by_payment_type');
SELECT upoa_ksk_reports.ksk_estimate_report_duration('figurants');


SELECT upoa_ksk_reports.ksk_estimate_report_duration_by_id(389);
SELECT upoa_ksk_reports.ksk_estimate_report_duration_by_id(388);
SELECT upoa_ksk_reports.ksk_estimate_report_duration_by_id(387);

    SELECT MAX(finished_datetime - created_datetime) AS max_duration
    FROM upoa_ksk_reports.ksk_report_header
    WHERE orchestrator_id = 2
      AND status = 'done'
      AND (end_date - start_date) + 1 = 11;

        SELECT MAX(finished_datetime - created_datetime) AS max_duration
        FROM upoa_ksk_reports.ksk_report_header
        WHERE orchestrator_id = 2
          AND status = 'done'
          AND (end_date - start_date) + 1 = 1;


        
select upoa_ksk_reports.ksk_regenerate_report(392);

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

        


select (CURRENT_DATE - 1)::date;

select upoa_ksk_reports.ksk_run_report(
                    'totals', 
                    'system',
                    null,
                    (CURRENT_DATE - 1)::date
                );

p_report_code character varying, 
p_initiator character varying, 
p_user_login character varying DEFAULT NULL::character varying, 
p_start_date date DEFAULT CURRENT_DATE, 
p_end_date date DEFAULT NULL::date, p_parameters jsonb DEFAULT NULL::jsonb)


-- Тестовое создание отчета
DO $$
DECLARE
    v_header_id INTEGER;
    v_result INTEGER;
BEGIN
    -- Регистрация заголовка отчета
    v_header_id := upoa_ksk_reports.ksk_report_register_header(
        p_report_code => 'totals',
        p_initiator => 'user',
        p_user_login => 'VTB70184234',
        p_start_date => '2025-10-28',
        p_end_date => '2025-11-07'
    );

    RAISE NOTICE 'Зарегистрирован заголовок отчета с ID: %', v_header_id;

    -- Создание отчета
    v_result := upoa_ksk_reports.ksk_report_create_report(v_header_id);

    IF v_result > 0 THEN
        RAISE NOTICE 'Отчет успешно создан с ID: %', v_result;
    ELSE
        RAISE NOTICE 'Ошибка при создании отчета. ID ошибки: %', v_result;
    END IF;
END $$;

-- Тестовое создание всех отчетов со статусом in_progress
DO $$
DECLARE
    v_success_ids INTEGER[];
    v_error_ids INTEGER[];
BEGIN
    -- Регистрация заголовков отчетов
    PERFORM upoa_ksk_reports.ksk_report_register_header(
        p_report_code => 'list_totals',
        p_initiator => 'user',
        p_user_login => 'VTB70184234',
        p_start_date => '2025-10-28',
        p_end_date => '2025-11-07',
        p_parameters => '{"param1": "value1"}'::jsonb
    );

    PERFORM upoa_ksk_reports.ksk_report_register_header(
        p_report_code => 'totals_by_payment_type',
        p_initiator => 'user',
        p_user_login => 'VTB70184234',
        p_start_date => '2025-10-28',
        p_end_date => '2025-11-07',
        p_parameters => '{"param1": "value1"}'::jsonb
    );

    -- Установка статуса in_progress для тестовых заголовков
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'in_progress'
    WHERE user_login = 'VTB70184234';

    -- Создание всех отчетов
    SELECT * INTO v_success_ids, v_error_ids
    FROM upoa_ksk_reports.ksk_report_create_all_reports();

    RAISE NOTICE 'Успешно созданные отчеты: %', array_to_string(v_success_ids, ', ');
    RAISE NOTICE 'Отчеты с ошибками: %', array_to_string(v_error_ids, ', ');
END $$;

-- Тестовое оценка времени формирования отчета по report_code
DO $$
DECLARE
    v_duration INTERVAL;
BEGIN
    v_duration := upoa_ksk_reports.ksk_estimate_report_duration('totals');

    RAISE NOTICE 'Приблизительное время формирования отчета totals: %', v_duration;
END $$;

-- Тестовое оценка времени формирования отчета по ID
DO $$
DECLARE
    v_header_id INTEGER;
    v_duration INTERVAL;
BEGIN
    -- Регистрация заголовка отчета
    v_header_id := upoa_ksk_reports.ksk_report_register_header(
        p_report_code => 'list_totals',
        p_initiator => 'user',
        p_user_login => 'VTB70184234',
        p_start_date => '2025-11-03',
        p_end_date => '2025-11-07',
        p_parameters => '{"param1": "value1"}'
    );

    RAISE NOTICE 'Зарегистрирован заголовок отчета с ID: %', v_header_id;

    -- Создание отчета
    PERFORM upoa_ksk_reports.ksk_report_create_report(v_header_id);

    -- Оценка времени формирования отчета по ID
    v_duration := upoa_ksk_reports.ksk_estimate_report_duration_by_id(v_header_id);

    RAISE NOTICE 'Приблизительное время формирования отчета с ID %: %', v_header_id, v_duration;
END $$;