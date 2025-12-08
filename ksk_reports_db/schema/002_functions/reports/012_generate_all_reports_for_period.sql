CREATE OR REPLACE FUNCTION upoa_ksk_reports.generate_all_reports_for_period(p_start_date date DEFAULT '2021-11-01'::date, p_end_date date DEFAULT '2021-11-12'::date)
 RETURNS TABLE(operation_date date, report_type character varying, header_id integer, status character varying, message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_date DATE;
    v_report_types TEXT[] := ARRAY['totals', 'totals_by_payment_type', 'list_totals', 'list_totals_by_payment_type', 'figurants'];
    v_report_type TEXT;
    v_header_id INTEGER;
    v_header_status VARCHAR;
    v_message TEXT;
    v_start_time TIMESTAMP(3);
    v_error_msg TEXT;
BEGIN
    v_start_time := NOW()::TIMESTAMP(3);
    
    -- ОСНОВНОЙ ЦИКЛ: По каждому дню в периоде
    v_current_date := p_start_date;
    
    WHILE v_current_date <= p_end_date LOOP
        
        -- ВНУТРЕННИЙ ЦИКЛ: По каждому типу отчёта
        FOREACH v_report_type IN ARRAY v_report_types LOOP
            BEGIN
                -- Создаём отчёт вызовом ksk_run_report()
                -- Параметры:
                -- p_report_code := код отчёта
                -- p_initiator := 'system' (встроенный, а не пользовательский)
                -- p_user_login := NULL (нет пользователя)
                -- p_start_date := дата дня
                -- p_end_date := NULL (будет автоматически установлена в p_start_date)
                -- p_parameters := NULL (нет доп. параметров)
                
                v_header_id := upoa_ksk_reports.ksk_run_report(
                    p_report_code := v_report_type,
                    p_initiator := 'system',
                    p_user_login := NULL,
                    p_start_date := v_current_date::date,
                    p_end_date := NULL,
                    p_parameters := NULL
                );
                
                -- Получаем финальный статус отчёта из ksk_report_header
                SELECT t.status INTO v_header_status
                FROM upoa_ksk_reports.ksk_report_header t
                WHERE id = v_header_id;
                
                v_message := FORMAT(
                    'Report %s for %s created successfully (header_id=%s, status=%s)',
                    v_report_type, v_current_date, v_header_id, v_header_status
                );
                
                -- Возвращаем успешный результат
                RETURN QUERY SELECT 
                    v_current_date,
                    v_report_type::VARCHAR,
                    v_header_id,
                    v_header_status,
                    v_message;
                    
            EXCEPTION WHEN OTHERS THEN
                v_error_msg := SQLERRM;
                v_message := FORMAT(
                    'ERROR: Failed to generate %s for %s: %s',
                    v_report_type, v_current_date, v_error_msg
                );
                
                -- Возвращаем ошибку
                RETURN QUERY SELECT 
                    v_current_date,
                    v_report_type::VARCHAR,
                    NULL::INTEGER,
                    'error'::VARCHAR,
                    v_message;
                    
                RAISE WARNING '%', v_message;
            END;
            
        END LOOP; -- Конец цикла по типам отчётов
        
        v_current_date := v_current_date + INTERVAL '1 day';
        
    END LOOP; -- Конец цикла по датам

END $function$
;
