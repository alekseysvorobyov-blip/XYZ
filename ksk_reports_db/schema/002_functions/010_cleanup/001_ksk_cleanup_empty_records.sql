-- ============================================================================
-- ФУНКЦИЯ: ksk_cleanup_empty_records
-- ============================================================================
-- ОПИСАНИЕ:
--   Быстрое удаление пустых записей из партиций ksk_result
--   2/3 записей имеют resolution='empty' (нет срабатываний КСК)
--   Храним их 14 дней для статистики, затем удаляем для экономии места
--
-- ПАРАМЕТРЫ:
--   @days_old - Возраст записей для удаления (по умолчанию: 14 дней)
--
-- ВОЗВРАЩАЕТ:
--   TABLE:
--     - deleted_count       BIGINT - Количество удалённых записей
--     - dropped_partitions  TEXT[] - Массив удалённых партиций
--     - execution_time      INTERVAL - Общее время выполнения
--
-- ЛОГИКА РАБОТЫ:
--   1. Если ВСЕ записи в партиции пустые → удаляет партицию целиком
--   2. Если есть НЕпустые записи → удаляет только пустые записи
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_cleanup_empty_records(14);
--   SELECT * FROM ksk_cleanup_empty_records(7);
--
-- ЗАМЕТКИ:
--   - Обрабатывает только партиции старше cutoff_date
--   - После удаления рекомендуется выполнить VACUUM ANALYZE
--     (см. документацию в README_cleanup_functions.md)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из cleanup_empty_ksk_records_fast
--   2025-10-25 - Удалён параметр perform_vacuum
--   2025-10-25 - Исправлено определение пустой партиции
-- ============================================================================
CREATE OR REPLACE FUNCTION ksk_cleanup_empty_records(
    days_old INTEGER DEFAULT 14
)
RETURNS TABLE(
    deleted_count       BIGINT,
    dropped_partitions  TEXT[],
    execution_time      INTERVAL
) AS $$
DECLARE
    start_time              TIMESTAMP := CLOCK_TIMESTAMP();
    total_deleted           BIGINT := 0;
    dropped_partitions_list TEXT[] := '{}';
    cutoff_date             DATE;
    partition_record        RECORD;
    deleted_count_var       BIGINT;
    all_empty               BOOLEAN;
BEGIN
    cutoff_date := CURRENT_DATE - (days_old || ' days')::INTERVAL;
    
    RAISE NOTICE 'Быстрое удаление пустых записей старше % дней (до %)', 
        days_old, cutoff_date;

    -- ========================================================================
    -- ОБРАБОТКА ПАРТИЦИЙ СТАРШЕ cutoff_date
    -- ========================================================================
    FOR partition_record IN
        SELECT child.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class parent ON parent.oid = i.inhparent
        JOIN pg_class child  ON child.oid  = i.inhrelid
        WHERE parent.relname = 'ksk_result'
          AND child.relname < 'part_ksk_result_' || TO_CHAR(cutoff_date, 'YYYY_MM_DD')
        ORDER BY child.relname
    LOOP
        -- ════════════════════════════════════════════════════════════════════
        -- ОПТИМИЗАЦИЯ: Проверяем, все ли записи пустые
        -- БЫЛО: SELECT COUNT(*) = 0 FROM table WHERE resolution != 'empty'
        -- СТАЛО: NOT EXISTS (SELECT 1 ... LIMIT 1)
        -- ════════════════════════════════════════════════════════════════════
        EXECUTE FORMAT(
            'SELECT NOT EXISTS (SELECT 1 FROM %I WHERE resolution != ''empty'' LIMIT 1)',
            partition_record.partition_name
        ) INTO all_empty;

        IF all_empty THEN
            -- Если все записи пустые, удаляем всю партицию
            EXECUTE FORMAT('DROP TABLE %I', partition_record.partition_name);
            dropped_partitions_list := ARRAY_APPEND(dropped_partitions_list, partition_record.partition_name);
            RAISE NOTICE '  ✓ Удалена партиция % (все записи пустые)', 
                partition_record.partition_name;
        ELSE
            -- Иначе удаляем только пустые записи
            EXECUTE FORMAT(
                'DELETE FROM %I WHERE resolution = ''empty''',
                partition_record.partition_name
            );
            GET DIAGNOSTICS deleted_count_var = ROW_COUNT;
            total_deleted := total_deleted + deleted_count_var;
            
            IF deleted_count_var > 0 THEN
                RAISE NOTICE '  ✓ Удалено % пустых записей из партиции %',
                    deleted_count_var, partition_record.partition_name;
            END IF;
        END IF;
    END LOOP;

    -- Итоговое сообщение
    RAISE NOTICE 'Удалено записей: %, удалено партиций: %',
        total_deleted, COALESCE(ARRAY_LENGTH(dropped_partitions_list, 1), 0);
    RAISE NOTICE '⚠️  РЕКОМЕНДАЦИЯ: Выполните VACUUM ANALYZE для освобождения места';

    -- Возвращаем результаты
    RETURN QUERY SELECT
        total_deleted,
        dropped_partitions_list,
        (CLOCK_TIMESTAMP() - start_time)::INTERVAL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_empty_records(INTEGER) IS 
    'Быстрое удаление пустых записей (resolution=empty) из старых партиций. После выполнения требуется VACUUM ANALYZE';
