-- ============================================================================
-- ФАЙЛ: ksk_test_speed_test_ai_generated_20251031_003.sql
-- ============================================================================
-- ИСПРАВЛЕНИЕ: Правильные имена полей для put_ksk_result_batch v3.0
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_test_put_ksk_result_batch_speed_test(p_batch_size integer DEFAULT 100)
RETURNS TABLE(metric text, value text)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_start_time TIMESTAMP(3);
    v_end_time TIMESTAMP(3);
    v_duration INTERVAL;
    v_duration_ms NUMERIC;

    v_batch JSONB;
    v_result RECORD;

    v_total_records INTEGER;
    v_success_count INTEGER;
    v_error_count INTEGER;
    v_error_ids INTEGER[];

    v_records_per_sec NUMERIC;
    v_ms_per_record NUMERIC;

    v_count_ksk_result INTEGER;
    v_count_ksk_figurant INTEGER;
    v_count_ksk_match INTEGER;

    v_base_timestamp TIMESTAMP(3);
    v_test_corr_id TEXT;
BEGIN
    -- Генерация уникального идентификатора теста
    v_test_corr_id := 'SPEED-TEST-' || extract(epoch from now())::BIGINT || '-' || p_batch_size;
    v_base_timestamp := now();

    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'ТЕСТ ПРОИЗВОДИТЕЛЬНОСТИ: put_ksk_result_batch';
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Batch size: %', p_batch_size;
    RAISE NOTICE 'Test ID: %', v_test_corr_id;
    RAISE NOTICE '-----------------------------------------------------------------';

    -- ========================================
    -- ШАГ 1: ГЕНЕРАЦИЯ ТЕСТОВОГО BATCH
    -- ========================================
    RAISE NOTICE 'Генерация тестового batch используя ksk_test_generate_data_messages()...';

    -- ИСПРАВЛЕНО: snake_case вместо CamelCase в JSON полях
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
                'input_timestamp', (v_base_timestamp + (idx || ' seconds')::INTERVAL)::TEXT,
                'output_timestamp', (v_base_timestamp + (idx + 1 || ' seconds')::INTERVAL)::TEXT,
                'input_json', input_json,
                'output_json', output_json,
                'input_kafka_partition', (idx % 10),
                'input_kafka_offset', idx::BIGINT,
                'input_kafka_headers', '{}'::JSONB,
                'output_kafka_headers', '{}'::JSONB
            ) AS record
        FROM parsed_data
    )
    SELECT jsonb_agg(record)
    INTO v_batch
    FROM batch_records;

    RAISE NOTICE 'Batch сгенерирован: % записей', p_batch_size;

    -- ========================================
    -- ШАГ 2: ЗАПУСК ТЕСТА
    -- ========================================
    RAISE NOTICE '-----------------------------------------------------------------';
    RAISE NOTICE 'Запуск put_ksk_result_batch...';

    v_start_time := clock_timestamp();

    -- Вызов тестируемой функции
    SELECT * INTO v_result
    FROM upoa_ksk_reports.put_ksk_result_batch(v_batch);

    v_end_time := clock_timestamp();
    v_duration := v_end_time - v_start_time;
    v_duration_ms := EXTRACT(EPOCH FROM v_duration) * 1000;

    -- ИСПРАВЛЕНО: правильные имена полей из RETURNS TABLE
    v_total_records := v_result.total_records;
    v_success_count := v_result.success_count;
    v_error_count := v_result.error_count;
    v_error_ids := v_result.error_ids;

    RAISE NOTICE 'Обработка завершена за %.2f мс', v_duration_ms;
    RAISE NOTICE '-----------------------------------------------------------------';

    -- ========================================
    -- ШАГ 3: ПОДСЧЁТ ВСТАВЛЕННЫХ ЗАПИСЕЙ
    -- ========================================
    -- Считаем записи, созданные в период выполнения теста
    SELECT COUNT(*) INTO v_count_ksk_result
    FROM upoa_ksk_reports.ksk_result
    WHERE output_timestamp >= v_base_timestamp
      AND output_timestamp <= v_end_time;

    SELECT COUNT(*) INTO v_count_ksk_figurant
    FROM upoa_ksk_reports.ksk_figurant f
    WHERE f.timestamp >= v_base_timestamp
      AND f.timestamp <= v_end_time;

    SELECT COUNT(*) INTO v_count_ksk_match
    FROM upoa_ksk_reports.ksk_figurant_match m
    WHERE m.timestamp >= v_base_timestamp
      AND m.timestamp <= v_end_time;

    -- ========================================
    -- ШАГ 4: РАСЧЁТ МЕТРИК
    -- ========================================
    v_records_per_sec := CASE 
        WHEN v_duration_ms > 0 THEN (v_success_count * 1000.0 / v_duration_ms)
        ELSE 0 
    END;

    v_ms_per_record := CASE 
        WHEN v_success_count > 0 THEN (v_duration_ms / v_success_count)
        ELSE 0 
    END;

    -- ========================================
    -- ШАГ 5: ВЫВОД РЕЗУЛЬТАТОВ
    -- ========================================
    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'РЕЗУЛЬТАТЫ ТЕСТА';
    RAISE NOTICE '=================================================================';

    RETURN QUERY
    SELECT 'TEST_ID'::TEXT, v_test_corr_id
    UNION ALL
    SELECT 'BATCH_SIZE', p_batch_size::TEXT
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'TOTAL_RECORDS', v_total_records::TEXT
    UNION ALL
    SELECT 'SUCCESS_COUNT', v_success_count::TEXT
    UNION ALL
    SELECT 'ERROR_COUNT', v_error_count::TEXT
    UNION ALL
    SELECT 'ERROR_IDS', COALESCE(array_to_string(v_error_ids, ', '), 'none')
    UNION ALL
    SELECT '---', '---'
    UNION ALL
    SELECT 'DURATION_MS', round(v_duration_ms, 2)::TEXT
    UNION ALL
    SELECT 'DURATION_SEC', round(EXTRACT(EPOCH FROM v_duration), 3)::TEXT
    UNION ALL
    SELECT 'RECORDS_PER_SEC', round(v_records_per_sec, 2)::TEXT
    UNION ALL
    SELECT 'MS_PER_RECORD', round(v_ms_per_record, 2)::TEXT
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
        WHEN v_error_count = 0 AND v_success_count = p_batch_size THEN '✅ PASS'
        WHEN v_error_count > 0 THEN '⚠️ PARTIAL FAIL (' || v_error_count || ' errors)'
        ELSE '❌ FAIL (records mismatch)'
    END;

    RAISE NOTICE '=================================================================';
    RAISE NOTICE 'Тест завершён!';
    RAISE NOTICE '=================================================================';

END;
$function$;

-- ============================================================================
-- КОММЕНТАРИЙ НА ФУНКЦИЮ
-- ============================================================================

COMMENT ON FUNCTION upoa_ksk_reports.ksk_test_put_ksk_result_batch_speed_test(integer) IS 
'Тест скорости для put_ksk_result_batch v3.0.

ИСПРАВЛЕНО:
- Использование snake_case вместо CamelCase в JSON полях
- Правильные имена полей из RETURNS TABLE функции put_ksk_result_batch v3.0

ПАРАМЕТРЫ:
  p_batch_size - Размер batch (default 100 записей)

ВОЗВРАЩАЕТ:
  Таблицу с метриками производительности для одного batch

ИСПОЛЬЗОВАНИЕ:
  SELECT * FROM upoa_ksk_reports.ksk_test_put_ksk_result_batch_speed_test(100);
  SELECT * FROM upoa_ksk_reports.ksk_test_put_ksk_result_batch_speed_test(500);
  SELECT * FROM upoa_ksk_reports.ksk_test_put_ksk_result_batch_speed_test(1000);';

-- ============================================================================
-- КОНЕЦ МИГРАЦИИ
-- ============================================================================