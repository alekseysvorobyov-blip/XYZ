-- ============================================================================
-- ФАЙЛ: ksk_test_performance_ai_generated_20251031_002.sql
-- ============================================================================
-- ИСПРАВЛЕНИЕ: Правильные имена полей для put_ksk_result_batch v3.0
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_test_put_ksk_result_batch_performance_test(
    p_test_duration interval DEFAULT '00:00:30'::interval, 
    p_batch_size integer DEFAULT 100
)
RETURNS TABLE(metric text, value text)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_test_start_time TIMESTAMP(3);
    v_test_end_time TIMESTAMP(3);
    v_actual_duration INTERVAL;
    v_actual_duration_sec NUMERIC;

    v_deadline TIMESTAMP(3);
    v_iteration INTEGER := 0;

    v_batch JSONB;
    v_result RECORD;

    v_total_batches INTEGER := 0;
    v_total_records INTEGER := 0;
    v_total_success INTEGER := 0;
    v_total_errors INTEGER := 0;

    v_batch_start_time TIMESTAMP(3);
    v_batch_end_time TIMESTAMP(3);
    v_batch_duration_ms NUMERIC;

    v_min_batch_duration_ms NUMERIC;
    v_max_batch_duration_ms NUMERIC;
    v_avg_batch_duration_ms NUMERIC;
    v_sum_batch_duration_ms NUMERIC := 0;

    v_throughput_records_per_sec NUMERIC;
    v_throughput_batches_per_sec NUMERIC;

    v_count_ksk_result INTEGER;
    v_count_ksk_figurant INTEGER;
    v_count_ksk_match INTEGER;

    v_base_timestamp TIMESTAMP(3);
    v_test_corr_id TEXT;
BEGIN
    -- Генерация уникального идентификатора теста
    v_test_corr_id := 'PERF-TEST-' || extract(epoch from now())::BIGINT || '-' || 
                      EXTRACT(EPOCH FROM p_test_duration)::INTEGER || 's-' || p_batch_size;
    v_base_timestamp := now();

    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ (THROUGHPUT): put_ksk_result_batch';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Test ID: %', v_test_corr_id;
    RAISE NOTICE 'Test duration: %', p_test_duration;
    RAISE NOTICE 'Batch size: %', p_batch_size;
    RAISE NOTICE 'Deadline: %', v_base_timestamp + p_test_duration;
    RAISE NOTICE '-----------------------------------------------------------------';

    -- Инициализация
    v_test_start_time := clock_timestamp();
    v_deadline := v_test_start_time + p_test_duration;
    v_min_batch_duration_ms := 999999999;
    v_max_batch_duration_ms := 0;

    -- ========================================
    -- ЦИКЛ ТЕСТИРОВАНИЯ
    -- ========================================
    RAISE NOTICE 'Запуск непрерывной вставки batch...';

    WHILE clock_timestamp() < v_deadline LOOP
        v_iteration := v_iteration + 1;

        -- ШАГ 1: Генерация batch с правильными именами полей (snake_case)
        WITH generated_data AS (
            SELECT 
                i AS idx,
                upoa_ksk_reports.ksk_test_generate_data_messages() AS gen
            FROM generate_series(1, p_batch_size) AS i
        ),
        parsed_data AS (
            SELECT 
                idx,
                (gen).input_json,
                (gen).output_json
            FROM generated_data
        ),
        batch_records AS (
            SELECT 
                jsonb_build_object(
                    'input_timestamp', (v_base_timestamp + (v_iteration * p_batch_size + idx || ' seconds')::INTERVAL)::TEXT,
                    'output_timestamp', (v_base_timestamp + (v_iteration * p_batch_size + idx + 1 || ' seconds')::INTERVAL)::TEXT,
                    'input_json', input_json,
                    'output_json', output_json,
                    'input_kafka_partition', (idx % 10),
                    'input_kafka_offset', (v_iteration * p_batch_size + idx)::BIGINT,
                    'input_kafka_headers', '{}'::JSONB,
                    'output_kafka_headers', '{}'::JSONB
                ) AS record
            FROM parsed_data
        )
        SELECT jsonb_agg(record)
        INTO v_batch
        FROM batch_records;

        -- ШАГ 2: Вызов put_ksk_result_batch
        v_batch_start_time := clock_timestamp();

        SELECT * INTO v_result
        FROM upoa_ksk_reports.put_ksk_result_batch(v_batch);

        v_batch_end_time := clock_timestamp();
        v_batch_duration_ms := EXTRACT(EPOCH FROM (v_batch_end_time - v_batch_start_time)) * 1000;

        -- ШАГ 3: Накопление статистики (правильные имена полей из v3.0)
        v_total_batches := v_total_batches + 1;
        v_total_records := v_total_records + v_result.total_records;
        v_total_success := v_total_success + v_result.success_count;
        v_total_errors := v_total_errors + v_result.error_count;

        v_sum_batch_duration_ms := v_sum_batch_duration_ms + v_batch_duration_ms;

        IF v_batch_duration_ms < v_min_batch_duration_ms THEN
            v_min_batch_duration_ms := v_batch_duration_ms;
        END IF;

        IF v_batch_duration_ms > v_max_batch_duration_ms THEN
            v_max_batch_duration_ms := v_batch_duration_ms;
        END IF;

        -- Вывод прогресса каждые 10 итераций
        IF v_iteration % 10 = 0 THEN
            RAISE NOTICE 'Iteration %: % batches processed, % records, % ms/batch', 
                v_iteration, v_total_batches, v_total_records, round(v_batch_duration_ms, 2);
        END IF;

        -- Проверка deadline
        IF clock_timestamp() >= v_deadline THEN
            EXIT;
        END IF;
    END LOOP;

    v_test_end_time := clock_timestamp();
    v_actual_duration := v_test_end_time - v_test_start_time;
    v_actual_duration_sec := EXTRACT(EPOCH FROM v_actual_duration);

    RAISE NOTICE '-----------------------------------------------------------------';
    RAISE NOTICE 'Тест завершён! Обработано % batches за %.2f сек', v_total_batches, v_actual_duration_sec;

    -- ========================================
    -- ПОДСЧЁТ ВСТАВЛЕННЫХ ЗАПИСЕЙ
    -- ========================================
    SELECT COUNT(*) INTO v_count_ksk_result
    FROM upoa_ksk_reports.ksk_result
    WHERE output_timestamp >= v_base_timestamp
      AND output_timestamp <= v_test_end_time;

    SELECT COUNT(*) INTO v_count_ksk_figurant
    FROM upoa_ksk_reports.ksk_figurant f
    WHERE f.timestamp >= v_base_timestamp
      AND f.timestamp <= v_test_end_time;

    SELECT COUNT(*) INTO v_count_ksk_match
    FROM upoa_ksk_reports.ksk_figurant_match m
    WHERE m.timestamp >= v_base_timestamp
      AND m.timestamp <= v_test_end_time;

    -- ========================================
    -- РАСЧЁТ МЕТРИК
    -- ========================================
    v_avg_batch_duration_ms := CASE 
        WHEN v_total_batches > 0 THEN v_sum_batch_duration_ms / v_total_batches
        ELSE 0 
    END;

    v_throughput_records_per_sec := CASE 
        WHEN v_actual_duration_sec > 0 THEN v_total_success / v_actual_duration_sec
        ELSE 0 
    END;

    v_throughput_batches_per_sec := CASE 
        WHEN v_actual_duration_sec > 0 THEN v_total_batches / v_actual_duration_sec
        ELSE 0 
    END;

    -- ========================================
    -- ВЫВОД РЕЗУЛЬТАТОВ
    -- ========================================
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'РЕЗУЛЬТАТЫ ТЕСТА';
    RAISE NOTICE '=================================================================';

    RETURN QUERY
    SELECT 'TEST_ID'::TEXT, v_test_corr_id
    UNION ALL
    SELECT 'TEST_TYPE', 'THROUGHPUT / PERFORMANCE TEST'
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'TARGET_DURATION', p_test_duration::TEXT
    UNION ALL
    SELECT 'ACTUAL_DURATION', v_actual_duration::TEXT
    UNION ALL
    SELECT 'ACTUAL_DURATION_SEC', round(v_actual_duration_sec, 2)::TEXT
    UNION ALL
    SELECT 'BATCH_SIZE', p_batch_size::TEXT
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'TOTAL_BATCHES', v_total_batches::TEXT
    UNION ALL
    SELECT 'TOTAL_RECORDS', v_total_records::TEXT
    UNION ALL
    SELECT 'TOTAL_SUCCESS', v_total_success::TEXT
    UNION ALL
    SELECT 'TOTAL_ERRORS', v_total_errors::TEXT
    UNION ALL
    SELECT 'ERROR_RATE_%', CASE 
        WHEN v_total_records > 0 THEN round((v_total_errors::NUMERIC / v_total_records) * 100, 2)::TEXT
        ELSE '0' 
    END
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'THROUGHPUT_RECORDS/SEC', round(v_throughput_records_per_sec, 2)::TEXT
    UNION ALL
    SELECT 'THROUGHPUT_BATCHES/SEC', round(v_throughput_batches_per_sec, 4)::TEXT
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'MIN_BATCH_DURATION_MS', round(v_min_batch_duration_ms, 2)::TEXT
    UNION ALL
    SELECT 'MAX_BATCH_DURATION_MS', round(v_max_batch_duration_ms, 2)::TEXT
    UNION ALL
    SELECT 'AVG_BATCH_DURATION_MS', round(v_avg_batch_duration_ms, 2)::TEXT
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'INSERTED_KSK_RESULT', v_count_ksk_result::TEXT
    UNION ALL
    SELECT 'INSERTED_KSK_FIGURANT', v_count_ksk_figurant::TEXT
    UNION ALL
    SELECT 'INSERTED_KSK_MATCH', v_count_ksk_match::TEXT
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'VERDICT', CASE 
        WHEN v_total_errors = 0 THEN '✅ PASS (no errors)'
        WHEN v_total_errors < v_total_success * 0.01 THEN '✅ PASS (< 1% error rate)'
        WHEN v_total_errors < v_total_success * 0.05 THEN '⚠️ WARNING (< 5% error rate)'
        ELSE '❌ FAIL (≥ 5% error rate)'
    END;

    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Тест завершён!';
    RAISE NOTICE 'Throughput: %.2f records/sec, %.4f batches/sec', 
        v_throughput_records_per_sec, v_throughput_batches_per_sec;
    RAISE NOTICE '=================================================================';

END;
$function$;

-- ============================================================================
-- КОММЕНТАРИЙ НА ФУНКЦИЮ
-- ============================================================================

COMMENT ON FUNCTION upoa_ksk_reports.ksk_test_put_ksk_result_batch_performance_test(interval, integer) IS 
'Тест производительности для put_ksk_result_batch v3.0.

ИСПРАВЛЕНО: 
- Использование snake_case вместо CamelCase в JSON полях
- Правильные имена полей из RETURNS TABLE функции put_ksk_result_batch v3.0

ПАРАМЕТРЫ:
  p_test_duration - Длительность теста (default 30 секунд)
  p_batch_size - Размер batch (default 100 записей)

ВОЗВРАЩАЕТ:
  Таблицу с метриками производительности

ИСПОЛЬЗОВАНИЕ:
  SELECT * FROM upoa_ksk_reports.ksk_test_put_ksk_result_batch_performance_test();
  SELECT * FROM upoa_ksk_reports.ksk_test_put_ksk_result_batch_performance_test(''00:01:00'', 200);';

-- ============================================================================
-- КОНЕЦ МИГРАЦИИ
-- ============================================================================