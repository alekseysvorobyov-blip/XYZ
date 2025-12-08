CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_create_all_reports()
RETURNS TABLE(success_ids INTEGER[], error_ids INTEGER[]) AS $$
DECLARE
    rec RECORD;
    v_result INTEGER;
    v_success_ids INTEGER[] := '{}';
    v_error_ids INTEGER[] := '{}';
BEGIN
    -- Обход всех записей в ksk_report_header со статусом 'in_progress'
    FOR rec IN 
        SELECT id
        FROM upoa_ksk_reports.ksk_report_header
        WHERE status = 'in_progress'
    LOOP
        -- Вызов функции для создания отчета
        v_result := upoa_ksk_reports.ksk_report_create_report(rec.id);

        -- Проверка результата
        IF v_result > 0 THEN
            v_success_ids := array_append(v_success_ids, v_result);
        ELSE
            v_error_ids := array_append(v_error_ids, v_result);
            RAISE WARNING 'Ошибка при создании отчета с Header ID: %', rec.id;
        END IF;
    END LOOP;

    RETURN QUERY
    SELECT v_success_ids, v_error_ids;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_create_all_reports() IS 
    'Функция для создания всех отчетов со статусом in_progress и возврата списков ID успешно созданных отчетов и ошибок';