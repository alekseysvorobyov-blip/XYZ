-- ============================================================================
-- НАСТРОЙКА ЕЖЕДНЕВНЫХ ЗАДАЧ ОБСЛУЖИВАНИЯ КСК ЧЕРЕЗ pg_cron
-- ============================================================================
-- Дата: 2025-10-28
-- Описание: Автоматизация всех maintenance задач через pg_cron
-- ============================================================================

-- ============================================================================
-- ОЧИСТКА СТАРЫХ ЗАДАЧ (опционально, если перенастраиваете)
-- ============================================================================
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN SELECT jobid FROM cron.job WHERE jobname LIKE 'ksk_%'
    LOOP
        PERFORM cron.unschedule(rec.jobid);
    END LOOP;
END $$;

-- ============================================================================
-- ЗАДАЧА #1: ANALYZE вчерашних партиций (00:30)
-- ============================================================================
SELECT cron.schedule(
    'ksk_analyze_yesterday_partitions',  -- job name
    '30 0 * * *',                         -- cron schedule
    $$
    DO $job$
    DECLARE
        v_date TEXT := TO_CHAR(CURRENT_DATE - 1, 'YYYY_MM_DD');
    BEGIN
        EXECUTE 'ANALYZE upoa_ksk_reports.part_ksk_result_' || v_date;
        EXECUTE 'ANALYZE upoa_ksk_reports.part_ksk_figurant_' || v_date;
        EXECUTE 'ANALYZE upoa_ksk_reports.part_ksk_match_' || v_date;
        
        -- Логирование
        PERFORM upoa_ksk_reports.ksk_log_operation(
            'analyze_partitions',
            'system',
            now()::timestamp(3),
            'success',
            'Analyzed partitions for date: ' || v_date,
            NULL
        );
    EXCEPTION
        WHEN OTHERS THEN
            PERFORM upoa_ksk_reports.ksk_log_operation(
                'analyze_partitions',
                'system',
                 now()::timestamp(3),
                'error',
                'Failed to analyze partitions for date: ' || v_date,
                SQLERRM
            );
            RAISE;
    END $job$;
    $$
);

-- ============================================================================
-- ЗАДАЧА #2: Создание будущих партиций (01:00)
-- ============================================================================
SELECT cron.schedule(
    'ksk_create_future_partitions',
    '0 1 * * *',
    $$
    SELECT upoa_ksk_reports.ksk_create_partitions_for_all_tables(
        CURRENT_DATE,
        7
    );
    $$
);

-- ============================================================================
-- ЗАДАЧА #3: Генерация системных отчётов (01:30)
-- ============================================================================
SELECT cron.schedule(
    'ksk_generate_system_reports',
    '30 1 * * *',
    $$
    DO $job$
    DECLARE
        rec RECORD;
        v_report_id INTEGER;
    BEGIN
        DELETE FROM upoa_ksk_reports.ksk_report_review_files WHERE report_date >= (CURRENT_DATE - 1)::date;
        FOR rec IN 
            SELECT report_code 
            FROM upoa_ksk_reports.ksk_report_orchestrator
            ORDER BY report_code
        LOOP
            BEGIN
                -- Генерация отчёта
                v_report_id := upoa_ksk_reports.ksk_run_report(
                    rec.report_code, 
                    'system', null, (CURRENT_DATE - 1)::date
                );
                
                -- Логирование успеха
                PERFORM upoa_ksk_reports.ksk_log_operation(
                    'generate_report',
                    rec.report_code,
	            now()::timestamp(3),
                    'success',
                    'Report generated with ID: ' || v_report_id,
                    NULL
                );
            EXCEPTION
                WHEN OTHERS THEN
                    -- Логирование ошибки
                    PERFORM upoa_ksk_reports.ksk_log_operation(
                        'generate_report',
                        rec.report_code,
                        now()::timestamp(3),
                        'error',
                        'Failed to generate report',
                        SQLERRM
                    );
            END;
        END LOOP;
    END $job$;
    $$
);

-- ============================================================================
-- ЗАДАЧА #4: Удаление прошлогодних партиций (02:00)
-- ============================================================================
SELECT cron.schedule(
    'ksk_drop_old_partitions',
    '0 2 * * *',
    $$
    SELECT upoa_ksk_reports.ksk_drop_old_partitions(365);
    $$
);

-- ============================================================================
-- ЗАДАЧА #5: Удаление empty записей (03:00)
-- ============================================================================
SELECT cron.schedule(
    'ksk_cleanup_empty_records',
    '0 3 * * *',
    $$
    SELECT upoa_ksk_reports.ksk_cleanup_empty_records(14);
    $$
);

-- ============================================================================
-- ЗАДАЧА #6: Удаление пустых партиций (03:30)
-- ============================================================================
SELECT cron.schedule(
    'ksk_cleanup_empty_partitions',
    '30 3 * * *',
    $$
    SELECT upoa_ksk_reports.ksk_cleanup_empty_partitions('all', 14);
    $$
);

-- ============================================================================
-- ЗАДАЧА #7: Очистка старых отчётов (04:00)
-- ============================================================================
SELECT cron.schedule(
    'ksk_cleanup_old_reports',
    '0 4 * * *',
    $$
    SELECT upoa_ksk_reports.ksk_cleanup_old_reports();
    $$
);

-- ============================================================================
-- ЗАДАЧА #8: Очистка системных логов (04:30)
-- ============================================================================
SELECT cron.schedule(
    'ksk_cleanup_old_logs',
    '30 4 * * *',
    $$
    SELECT upoa_ksk_reports.ksk_cleanup_old_logs(365);
    $$
);

-- ============================================================================
-- ЗАДАЧА #9: VACUUM главных таблиц (05:00)
-- ============================================================================
/*
-- VACUUM cannot run inside a transaction block
SELECT cron.schedule(
    'ksk_vacuum_main_tables',
    '0 5 * * *',
    $$
    DO $job$
    BEGIN
        VACUUM ANALYZE upoa_ksk_reports.ksk_result;
        VACUUM ANALYZE upoa_ksk_reports.ksk_figurant;
        VACUUM ANALYZE upoa_ksk_reports.ksk_match;
        VACUUM ANALYZE upoa_ksk_reports.ksk_report_header;
        VACUUM ANALYZE upoa_ksk_reports.ksk_system_operations_log;
        
        -- Логирование
        PERFORM upoa_ksk_reports.ksk_log_operation(
            'vacuum_tables',
            'system',
            'success',
            'VACUUM ANALYZE completed for main tables',
            NULL
        );
    EXCEPTION
        WHEN OTHERS THEN
            PERFORM upoa_ksk_reports.ksk_log_operation(
                'vacuum_tables',
                'system',
                'error',
                'VACUUM ANALYZE failed',
                SQLERRM
            );
    END $job$;
    $$
);
*/

-- ============================================================================
-- ЗАДАЧА #10: Мониторинг bloat (воскресенье 04:00)
-- ============================================================================
SELECT cron.schedule(
    'ksk_monitor_bloat',
    '0 4 * * 0',  -- 0 = воскресенье
    $$
    SELECT upoa_ksk_reports.ksk_monitor_table_bloat();
    $$
);

-- ============================================================================
-- ВЕРИФИКАЦИЯ: Проверка созданных задач
-- ============================================================================
SELECT 
    jobid,
    schedule,
    command,
    nodename,
    nodeport,
    database,
    username,
    active,
    jobname
FROM cron.job
WHERE jobname LIKE 'ksk_%'
ORDER BY schedule;

--COMMENT ON EXTENSION pg_cron IS 
--'PostgreSQL job scheduler for KSK maintenance tasks';
