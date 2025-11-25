-- ============================================================================
-- Генерация всех типов отчётов за период: 2021-11-01 - 2021-11-12
-- ============================================================================
--
-- НАЗНАЧЕНИЕ:
-- Создать системные отчёты всех 5 типов за каждый день в периоде
--
-- ТИПЫ ОТЧЁТОВ (5):
-- 1. totals                        → ksk_report_totals_data
-- 2. totals_by_payment_type        → ksk_report_totals_by_payment_type_data  
-- 3. list_totals                   → ksk_report_list_totals_data
-- 4. list_totals_by_payment_type   → ksk_report_list_totals_by_payment_type_data
-- 5. figurants                     → ksk_report_figurants_data
--
-- ПРИМЕЧАНИЕ: review - это функция (не таблица), генерируется по запросу
--
-- ОСНОВАНО НА:
-- - ksk_run_report() из 002_all_reports_functions.sql
-- - Примеры из 001_cron.sql
--
-- ============================================================================

-- ============================================================================
-- ГЛАВНАЯ ФУНКЦИЯ: Генерирует все отчёты за период
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.generate_all_reports_for_period(
    p_start_date DATE DEFAULT '2021-11-01',
    p_end_date DATE DEFAULT '2021-11-12'
) 
RETURNS TABLE(
    operation_date DATE,
    report_type VARCHAR,
    header_id INTEGER,
    status VARCHAR,
    message TEXT
)
LANGUAGE plpgsql
AS $$
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
                    p_start_date := v_current_date,
                    p_end_date := NULL,
                    p_parameters := NULL
                );
                
                -- Получаем финальный статус отчёта из ksk_report_header
                SELECT status INTO v_header_status
                FROM upoa_ksk_reports.ksk_report_header
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

END $$;

COMMENT ON FUNCTION upoa_ksk_reports.generate_all_reports_for_period(DATE, DATE) IS
'Генерирует все типы отчётов за период. Использует реальную функцию ksk_run_report()';

-- ============================================================================
-- ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ: Проверка статуса генерированных отчётов
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.check_generated_reports_status(
    p_start_date DATE DEFAULT '2021-11-01',
    p_end_date DATE DEFAULT '2021-11-12'
)
RETURNS TABLE(
    report_date DATE,
    report_code VARCHAR,
    header_id INTEGER,
    status VARCHAR,
    created_datetime TIMESTAMP,
    finished_datetime TIMESTAMP,
    rows_count BIGINT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        DATE(rh.created_datetime) AS report_date,
        ro.report_code,
        rh.id AS header_id,
        rh.status,
        rh.created_datetime,
        rh.finished_datetime,
        CASE 
            WHEN ro.report_code = 'totals' THEN 
                (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_data WHERE report_header_id = rh.id)
            WHEN ro.report_code = 'totals_by_payment_type' THEN 
                (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data WHERE report_header_id = rh.id)
            WHEN ro.report_code = 'list_totals' THEN 
                (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_data WHERE report_header_id = rh.id)
            WHEN ro.report_code = 'list_totals_by_payment_type' THEN 
                (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data WHERE report_header_id = rh.id)
            WHEN ro.report_code = 'figurants' THEN 
                (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_figurants_data WHERE report_header_id = rh.id)
            ELSE 0
        END AS rows_count
    FROM upoa_ksk_reports.ksk_report_header rh
    JOIN upoa_ksk_reports.ksk_report_orchestrator ro ON rh.orchestrator_id = ro.id
    WHERE DATE(rh.created_datetime) >= p_start_date
        AND DATE(rh.created_datetime) <= p_end_date
        AND rh.initiator = 'system'
    ORDER BY rh.created_datetime DESC, ro.report_code;
END $$;

COMMENT ON FUNCTION upoa_ksk_reports.check_generated_reports_status(DATE, DATE) IS
'Проверяет статус всех сгенерированных отчётов за период';

-- ============================================================================
-- СТАТИСТИКА ПО ГЕНЕРИРОВАННЫМ ОТЧЁТАМ
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.get_report_generation_stats(
    p_start_date DATE DEFAULT '2021-11-01',
    p_end_date DATE DEFAULT '2021-11-12'
)
RETURNS TABLE(
    report_code VARCHAR,
    total_count BIGINT,
    done_count BIGINT,
    error_count BIGINT,
    in_progress_count BIGINT,
    avg_duration_seconds NUMERIC,
    min_row_count BIGINT,
    max_row_count BIGINT,
    avg_row_count NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        ro.report_code,
        COUNT(*) AS total_count,
        COUNT(*) FILTER (WHERE rh.status = 'done') AS done_count,
        COUNT(*) FILTER (WHERE rh.status = 'error') AS error_count,
        COUNT(*) FILTER (WHERE rh.status = 'in_progress') AS in_progress_count,
        ROUND(
            AVG(EXTRACT(EPOCH FROM (COALESCE(rh.finished_datetime, NOW()) - rh.created_datetime)))::NUMERIC,
            2
        ) AS avg_duration_seconds,
        MIN(
            CASE 
                WHEN ro.report_code = 'totals' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'totals_by_payment_type' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'list_totals' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'list_totals_by_payment_type' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'figurants' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_figurants_data WHERE report_header_id = rh.id)
                ELSE 0
            END
        ) AS min_row_count,
        MAX(
            CASE 
                WHEN ro.report_code = 'totals' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'totals_by_payment_type' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'list_totals' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'list_totals_by_payment_type' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data WHERE report_header_id = rh.id)
                WHEN ro.report_code = 'figurants' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_figurants_data WHERE report_header_id = rh.id)
                ELSE 0
            END
        ) AS max_row_count,
        ROUND(
            AVG(
                CASE 
                    WHEN ro.report_code = 'totals' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_data WHERE report_header_id = rh.id)
                    WHEN ro.report_code = 'totals_by_payment_type' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data WHERE report_header_id = rh.id)
                    WHEN ro.report_code = 'list_totals' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_data WHERE report_header_id = rh.id)
                    WHEN ro.report_code = 'list_totals_by_payment_type' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data WHERE report_header_id = rh.id)
                    WHEN ro.report_code = 'figurants' THEN (SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_figurants_data WHERE report_header_id = rh.id)
                    ELSE 0
                END
            )::NUMERIC,
            2
        ) AS avg_row_count
    FROM upoa_ksk_reports.ksk_report_header rh
    JOIN upoa_ksk_reports.ksk_report_orchestrator ro ON rh.orchestrator_id = ro.id
    WHERE DATE(rh.created_datetime) >= p_start_date
        AND DATE(rh.created_datetime) <= p_end_date
        AND rh.initiator = 'system'
    GROUP BY ro.report_code
    ORDER BY ro.report_code;
END $$;

COMMENT ON FUNCTION upoa_ksk_reports.get_report_generation_stats(DATE, DATE) IS
'Получает статистику по типам генерированных отчётов';

-- ============================================================================
-- ЗАПУСК: Генерация всех отчётов
-- ============================================================================

-- Основной запрос: генерирует все отчёты за период
-- ПРИМЕЧАНИЕ: Это создаст 60 отчётов (12 дней × 5 типов)
-- Время выполнения зависит от объёма данных в ksk_result и ksk_figurant

SELECT * FROM upoa_ksk_reports.generate_all_reports_for_period(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-12'
);

-- ============================================================================
-- ПРОВЕРКА: Просмотр созданных отчётов
-- ============================================================================

-- Статус всех созданных отчётов
SELECT * FROM upoa_ksk_reports.check_generated_reports_status(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-12'
)
ORDER BY report_date DESC, report_code;

-- ============================================================================
-- СТАТИСТИКА: Сводная статистика по типам отчётов
-- ============================================================================

-- Статистика по каждому типу отчёта
SELECT * FROM upoa_ksk_reports.get_report_generation_stats(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-12'
)
ORDER BY report_code;

-- ============================================================================
-- ПРИМЕРЫ ДОПОЛНИТЕЛЬНЫХ ЗАПРОСОВ
-- ============================================================================

-- Пример 1: Только ошибки
SELECT * FROM upoa_ksk_reports.check_generated_reports_status(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-12'
)
WHERE status = 'error'
ORDER BY report_date DESC;

-- Пример 2: Только успешные отчёты
SELECT * FROM upoa_ksk_reports.check_generated_reports_status(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-12'
)
WHERE status = 'done'
ORDER BY report_date DESC, report_code;

-- Пример 3: Отчёты за конкретный день
SELECT * FROM upoa_ksk_reports.check_generated_reports_status(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-01'
)
ORDER BY report_code;

-- Пример 4: Итого созданных отчётов
SELECT 
    COUNT(*) AS total_reports,
    COUNT(*) FILTER (WHERE status = 'done') AS done,
    COUNT(*) FILTER (WHERE status = 'error') AS errors,
    COUNT(DISTINCT DATE(created_datetime)) AS days_with_reports
FROM upoa_ksk_reports.check_generated_reports_status(
    p_start_date := '2021-11-01',
    p_end_date := '2021-11-12'
);

-- ============================================================================
-- ИТОГИ
-- ============================================================================
-- Период: 2021-11-01 до 2021-11-12 (12 дней)
-- Типов отчётов: 5 (из ksk_report_orchestrator)
-- Всего отчётов: 12 * 5 = 60 отчётов
--
-- Распределение:
-- - totals:                        12 отчётов (по 1 на каждый день)
-- - totals_by_payment_type:        12 отчётов (по 1 на каждый день)
-- - list_totals:                   12 отчётов (по 1 на каждый день)
-- - list_totals_by_payment_type:   12 отчётов (по 1 на каждый день)
-- - figurants:                     12 отчётов (по 1 на каждый день)
--
-- Примечание:
-- ✓ review НЕ включен т.к. это функция (не таблица), генерируется по запросу
-- ✓ Каждый отчёт создаёт запись в ksk_report_header с initiator='system'
-- ✓ Данные каждого отчёта хранятся в соответствующей таблице данных
-- ✓ TTL для системных отчётов: 365 дней
-- ✓ Использует реальную функцию ksk_run_report() из системы
-- ✓ Каждый отчёт логируется через ksk_log_operation()
-- ============================================================================
