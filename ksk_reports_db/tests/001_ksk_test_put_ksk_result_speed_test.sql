-- DROP FUNCTION upoa_ksk_reports.ksk_test_put_ksk_result_speed_test(int4);

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_test_put_ksk_result_speed_test(p_count integer DEFAULT 1000)
 RETURNS TABLE(total_count bigint, elapsed_seconds numeric, records_per_second numeric, figurants_inserted bigint, matches_inserted bigint)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_start_time TIMESTAMP(3) := clock_timestamp();
    v_last_report_time TIMESTAMP(3) := clock_timestamp();
    v_current_time TIMESTAMP(3);
    v_elapsed NUMERIC;
    v_total_elapsed NUMERIC;
    
    v_processed_count INTEGER := 0;
    v_last_processed_count INTEGER := 0;
    
    v_kafka_offset BIGINT := floor(random() * 1000000)::BIGINT;
    v_kafka_partition INTEGER := floor(random() * 10)::INTEGER;
    v_rec RECORD;
    
    v_total_figurants BIGINT := 0;
    v_total_matches BIGINT := 0;
    v_figurants_in_message INTEGER;
    v_matches_in_figurant INTEGER;
    
    v_input_headers JSONB;
    v_output_headers JSONB;
    v_current_timestamp TIMESTAMP(3);
    v_current_epoch BIGINT;
    
BEGIN
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'ТЕСТ СКОРОСТИ: put_ksk_result';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'Количество транзакций: %', p_count;
    RAISE NOTICE 'Старт: %', v_start_time;
    RAISE NOTICE '───────────────────────────────────────────────────────────────';
    
    -- Цикл вставки
    FOR i IN 1..p_count LOOP
        v_current_timestamp := clock_timestamp();
        v_current_epoch := (EXTRACT(EPOCH FROM v_current_timestamp) * 1000)::BIGINT;
        
        -- Генерируем тестовое сообщение
        SELECT * INTO v_rec FROM upoa_ksk_reports.ksk_test_generate_data_messages();
        
        -- Формируем headers для входящего сообщения
        v_input_headers := jsonb_build_array(
            jsonb_build_object('key', 'ksk_report_consumer.service-name', 'value', 'ksk-report-consumer-test'),
            jsonb_build_object('key', 'ksk_report_consumer.service-version', 'value', '1.0.0'),
            jsonb_build_object('key', 'ksk_report_consumer.topic-name', 'value', 'ksk.input.topic'),
            jsonb_build_object('key', 'ksk_report_consumer.topic-partition', 'value', v_kafka_partition::TEXT),
            jsonb_build_object('key', 'ksk_report_consumer.topic-offset', 'value', v_kafka_offset::TEXT),
            jsonb_build_object('key', 'ksk_report_consumer.topic-timestamp', 'value', v_current_epoch::TEXT),
            jsonb_build_object('key', 'ksk_report_consumer.topic-timestamp-string', 'value', to_char(v_current_timestamp, 'YYYY-MM-DD HH24:MI:SS.MS'))
        );
        
        -- Формируем headers для выходящего сообщения
        v_output_headers := jsonb_build_array(
            jsonb_build_object('key', 'ksk_report_consumer.service-name', 'value', 'ksk-report-consumer-test'),
            jsonb_build_object('key', 'ksk_report_consumer.service-version', 'value', '1.0.0'),
            jsonb_build_object('key', 'ksk_report_consumer.topic-name', 'value', 'ksk.output.topic'),
            jsonb_build_object('key', 'ksk_report_consumer.topic-partition', 'value', v_kafka_partition::TEXT),
            jsonb_build_object('key', 'ksk_report_consumer.topic-offset', 'value', v_kafka_offset::TEXT),
            jsonb_build_object('key', 'ksk_report_consumer.topic-timestamp', 'value', v_current_epoch::TEXT),
            jsonb_build_object('key', 'ksk_report_consumer.topic-timestamp-string', 'value', to_char(v_current_timestamp, 'YYYY-MM-DD HH24:MI:SS.MS'))
        );
        
        -- ✅ ИСПРАВЛЕНО: правильный порядок и названия параметров
        PERFORM upoa_ksk_reports.put_ksk_result(
            p_input_timestamp := v_current_timestamp - interval '100 milliseconds',
            p_output_timestamp := v_current_timestamp,
            p_input_json := v_rec.input_json,
            p_output_json := v_rec.output_json,
            p_input_kafka_partition := v_kafka_partition,
            p_input_kafka_offset := v_kafka_offset,
            p_input_kafka_headers := v_input_headers,
            p_output_kafka_headers := v_output_headers
        );
        
        v_kafka_offset := v_kafka_offset + 1;
        v_processed_count := v_processed_count + 1;
        
        -- Подсчёт фигурантов и совпадений
        v_figurants_in_message := jsonb_array_length(v_rec.output_json->'searchCheckResultKCKH');
        IF v_figurants_in_message > 0 THEN
            v_total_figurants := v_total_figurants + v_figurants_in_message;
            
            FOR j IN 0..(v_figurants_in_message - 1) LOOP
                v_matches_in_figurant := jsonb_array_length(
                    v_rec.output_json->'searchCheckResultKCKH'->j->'match'
                );
                v_total_matches := v_total_matches + v_matches_in_figurant;
            END LOOP;
        END IF;
        
        -- Промежуточный отчёт каждые 10 секунд
        v_current_time := clock_timestamp();
        v_elapsed := EXTRACT(EPOCH FROM (v_current_time - v_last_report_time));
        
        IF v_elapsed >= 10 THEN
            v_total_elapsed := EXTRACT(EPOCH FROM (v_current_time - v_start_time));
            
            RAISE NOTICE '⏱  %.1f сек | Обработано: % / % (%.1f%%) | Скорость: %.1f rec/sec | Фигуранты: % | Совпадения: %',
                v_total_elapsed,
                v_processed_count,
                p_count,
                (v_processed_count::NUMERIC / p_count * 100),
                ((v_processed_count - v_last_processed_count)::NUMERIC / v_elapsed),
                v_total_figurants,
                v_total_matches;
            
            v_last_report_time := v_current_time;
            v_last_processed_count := v_processed_count;
        END IF;
    END LOOP;
    
    -- Итоговая статистика
    v_current_time := clock_timestamp();
    v_total_elapsed := EXTRACT(EPOCH FROM (v_current_time - v_start_time));
    
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE '✅ ТЕСТ ЗАВЕРШЁН';
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    RAISE NOTICE 'Всего вставлено:      % транзакций', v_processed_count;
    RAISE NOTICE 'Фигурантов:           %', v_total_figurants;
    RAISE NOTICE 'Совпадений:           %', v_total_matches;
    RAISE NOTICE 'Время выполнения:     %.2f сек', v_total_elapsed;
    RAISE NOTICE 'Средняя скорость:     %.2f rec/sec', (v_processed_count::NUMERIC / v_total_elapsed);
    RAISE NOTICE '═══════════════════════════════════════════════════════════════';
    
    RETURN QUERY SELECT
        v_processed_count::BIGINT,
        ROUND(v_total_elapsed, 2),
        ROUND(v_processed_count::NUMERIC / v_total_elapsed, 2),
        v_total_figurants,
        v_total_matches;
END;
$function$
;