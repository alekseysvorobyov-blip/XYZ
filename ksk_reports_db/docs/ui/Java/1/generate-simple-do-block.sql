-- ============================================================================
-- ПРОСТОЙ БЛОК: Генерация всех типов отчётов за период 2021-11-01 - 2021-11-12
-- ============================================================================
-- Без создания функций, просто DO...END блок
-- ============================================================================

DO $$
DECLARE
    v_current_date DATE;
    v_end_date DATE;
    v_report_types TEXT[];
    v_report_type TEXT;
    v_header_id INTEGER;
    v_count INTEGER := 0;
BEGIN
    -- Инициализация
    v_current_date := '2021-11-01'::DATE;
    v_end_date := '2021-11-12'::DATE;
    v_report_types := ARRAY['totals', 'totals_by_payment_type', 'list_totals', 'list_totals_by_payment_type', 'figurants'];
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Генерация отчётов за период % - %', v_current_date, v_end_date;
    RAISE NOTICE '========================================';
    
    -- ОСНОВНОЙ ЦИКЛ: По каждому дню
    WHILE v_current_date <= v_end_date LOOP
        
        -- ВНУТРЕННИЙ ЦИКЛ: По каждому типу отчёта
        FOREACH v_report_type IN ARRAY v_report_types LOOP
            BEGIN
                -- Создаём отчёт
                v_header_id := upoa_ksk_reports.ksk_run_report(
                    p_report_code := v_report_type,
                    p_initiator := 'system',
                    p_user_login := NULL,
                    p_start_date := v_current_date,
                    p_end_date := NULL,
                    p_parameters := NULL
                );
                
                v_count := v_count + 1;
                
                RAISE NOTICE '[%] % для % → header_id=%', v_count, v_report_type, v_current_date, v_header_id;
                
            EXCEPTION WHEN OTHERS THEN
                RAISE WARNING 'Ошибка при создании % для %: %', v_report_type, v_current_date, SQLERRM;
            END;
        END LOOP;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Завершено! Создано % отчётов', v_count;
    RAISE NOTICE '========================================';
    
END $$;

-- ============================================================================
-- ПРОВЕРКА: Просмотр созданных отчётов
-- ============================================================================

SELECT 
    DATE(rh.created_datetime) AS report_date,
    ro.report_code,
    rh.status,
    rh.id AS header_id
FROM upoa_ksk_reports.ksk_report_header rh
JOIN upoa_ksk_reports.ksk_report_orchestrator ro ON rh.orchestrator_id = ro.id
WHERE DATE(rh.created_datetime) >= '2021-11-01'
    AND DATE(rh.created_datetime) <= '2021-11-12'
    AND rh.initiator = 'system'
ORDER BY rh.created_datetime DESC, ro.report_code;

-- ============================================================================
-- СТАТИСТИКА: Итого созданных
-- ============================================================================

SELECT 
    COUNT(*) AS total_reports,
    COUNT(*) FILTER (WHERE rh.status = 'done') AS done,
    COUNT(*) FILTER (WHERE rh.status = 'error') AS errors,
    COUNT(DISTINCT DATE(rh.created_datetime)) AS days
FROM upoa_ksk_reports.ksk_report_header rh
WHERE DATE(rh.created_datetime) >= '2021-11-01'
    AND DATE(rh.created_datetime) <= '2021-11-12'
    AND rh.initiator = 'system';
