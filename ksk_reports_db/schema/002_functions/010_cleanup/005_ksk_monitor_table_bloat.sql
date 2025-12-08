-- ============================================================================
-- Функция: ksk_monitor_table_bloat
-- Описание: Мониторинг раздутия (bloat) таблиц с логированием результатов
-- 
-- Возвращает: JSON с отчётом по таблицам где bloat >5%
-- 
-- Логирует в ksk_system_operations_log:
--   - status = 'success' если все таблицы здоровы (bloat <15%)
--   - status = 'error' если есть таблицы с критичным bloat (>30%)
--   - info содержит список таблиц с высоким bloat
--
-- Примеры логов:
--   Успех:
--     status: 'success'
--     info: 'Bloat monitoring: All tables healthy (<15% bloat)'
--
--   Предупреждение:
--     status: 'success'
--     info: 'Bloat monitoring: WARNING (15-30%): ksk_match'
--
--   Критично:
--     status: 'error'
--     info: 'Bloat monitoring: CRITICAL (>30%): ksk_result, ksk_figurant; WARNING (15-30%): ksk_match'
--     errmsg: 'Critical bloat detected'
--
-- Использование:
--   SELECT upoa_ksk_reports.ksk_monitor_table_bloat();
--
-- Просмотр логов:
--   SELECT begin_time, status, info 
--   FROM upoa_ksk_reports.ksk_system_operations_log 
--   WHERE operation_name LIKE '%bloat%' 
--   ORDER BY begin_time DESC;
-- ============================================================================
CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_monitor_table_bloat()
RETURNS JSON
LANGUAGE plpgsql
AS $$
DECLARE
    v_operation_code TEXT;
    v_start_time TIMESTAMP(3);
    v_bloat_report JSON;
    v_critical_tables TEXT := '';
    v_warning_tables TEXT := '';
    v_info TEXT;
    v_status TEXT := 'success';
BEGIN
    v_start_time := now()::timestamp(3);
    v_operation_code := 'monitor_bloat_' || extract(epoch from v_start_time)::bigint;
    
    -- Собираем статистику раздутия
    WITH bloat_stats AS (
        SELECT
            schemaname,
            relname AS tablename,  -- ✅ ИСПРАВЛЕНО: relname AS tablename
            pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS size,  -- ✅ ИСПРАВЛЕНО
            n_dead_tup,
            n_live_tup,
            ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct
        FROM pg_stat_user_tables
        WHERE schemaname = 'upoa_ksk_reports'
          AND n_live_tup > 0
        ORDER BY dead_pct DESC NULLS LAST
    )
    SELECT json_agg(row_to_json(bloat_stats))
    INTO v_bloat_report
    FROM bloat_stats
    WHERE dead_pct > 5; -- только таблицы с >5% мёртвых строк
    
    -- Формируем список критичных таблиц (>30% bloat)
    SELECT string_agg(relname, ', ')  -- ✅ ИСПРАВЛЕНО: relname вместо tablename
    INTO v_critical_tables
    FROM (
        SELECT relname  -- ✅ ИСПРАВЛЕНО: relname вместо tablename
        FROM pg_stat_user_tables
        WHERE schemaname = 'upoa_ksk_reports'
          AND n_live_tup > 0
          AND ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) > 30
    ) t;
    
    -- Формируем список таблиц с предупреждением (15-30% bloat)
    SELECT string_agg(relname, ', ')  -- ✅ ИСПРАВЛЕНО: relname вместо tablename
    INTO v_warning_tables
    FROM (
        SELECT relname  -- ✅ ИСПРАВЛЕНО: relname вместо tablename
        FROM pg_stat_user_tables
        WHERE schemaname = 'upoa_ksk_reports'
          AND n_live_tup > 0
          AND ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) BETWEEN 15 AND 30
    ) t;
    
    -- Формируем итоговое сообщение
    v_info := 'Bloat monitoring: ';
    
    IF v_critical_tables IS NOT NULL AND v_critical_tables != '' THEN
        v_info := v_info || 'CRITICAL (>30%): ' || v_critical_tables || '; ';
        v_status := 'error';
    END IF;
    
    IF v_warning_tables IS NOT NULL AND v_warning_tables != '' THEN
        v_info := v_info || 'WARNING (15-30%): ' || v_warning_tables || '; ';
    END IF;
    
    IF (v_critical_tables IS NULL OR v_critical_tables = '') 
       AND (v_warning_tables IS NULL OR v_warning_tables = '') THEN
        v_info := v_info || 'All tables healthy (<15% bloat)';
    END IF;
    
    -- Логируем результат
    PERFORM upoa_ksk_reports.ksk_log_operation(
        v_operation_code,
        'Мониторинг раздутия таблиц (bloat monitoring)',
        v_start_time,
        v_status,
        v_info,
        CASE WHEN v_status = 'error' THEN 'Critical bloat detected' ELSE NULL END
    );
    
    RETURN v_bloat_report;
    
EXCEPTION WHEN OTHERS THEN
    -- Логируем ошибку
    PERFORM upoa_ksk_reports.ksk_log_operation(
        v_operation_code || '_error',
        'Ошибка при мониторинге bloat',
        v_start_time,
        'error',
        NULL,
        SQLERRM
    );
    RAISE;
END;
$$;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_monitor_table_bloat() IS
'Еженедельный мониторинг раздутия (bloat) таблиц. Логирует результаты в ksk_system_operations_log. Возвращает JSON с таблицами где bloat >5%. Статус "error" если bloat >30%.';

