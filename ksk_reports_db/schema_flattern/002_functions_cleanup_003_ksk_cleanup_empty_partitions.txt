-- ============================================================================
-- ФУНКЦИЯ: ksk_cleanup_empty_partitions
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет партиции, в которых совсем нет данных
--   Используется для очистки ошибочно созданных или полностью очищенных партиций
--   Записывает результат выполнения в системный лог
--
-- ПАРАМЕТРЫ:
--   @table_name - Имя таблицы или 'all' для всех таблиц (по умолчанию: 'ksk_result')
--   @days_old   - Возраст партиций для проверки (по умолчанию: 7 дней)
--
-- ВОЗВРАЩАЕТ:
--   TABLE:
--     - log_id              INTEGER  - ID записи в системном логе
--     - deleted_partitions  TEXT[]   - Массив имён удалённых партиций
--     - execution_time      INTERVAL - Время выполнения
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_cleanup_empty_partitions('ksk_result', 7);
--   SELECT * FROM ksk_cleanup_empty_partitions('all', 14);
--
-- ЗАМЕТКИ:
--   - Обрабатывает только партиции старше cutoff_date
--   - Использует EXISTS для эффективной проверки (не считает все строки)
--   - Удаляет только партиции с нулевым количеством записей
--   - Результат записывается в ksk_system_operations_log
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из cleanup_ksk_empty_partitions
--   2025-10-25 - Добавлено логирование операций
--   2025-10-25 - Оптимизация проверки пустоты (COUNT(*) → EXISTS)
-- ============================================================================

CREATE OR REPLACE FUNCTION ksk_cleanup_empty_partitions(
    table_name TEXT    DEFAULT 'ksk_result',
    days_old   INTEGER DEFAULT 7
)
RETURNS TABLE(
    log_id              INTEGER,
    deleted_partitions  TEXT[],
    execution_time      INTERVAL
) AS $$
DECLARE
    empty_partitions  TEXT[] := '{}';
    target_tables     TEXT[];
    current_table     TEXT;
    partition_record  RECORD;
    cutoff_date       DATE := CURRENT_DATE - (days_old || ' days')::INTERVAL;
    is_empty          BOOLEAN;
    v_start_time      TIMESTAMP := CLOCK_TIMESTAMP();
    v_status          VARCHAR := 'success';
    v_error_msg       TEXT := NULL;
    v_error_count     INTEGER := 0;
    v_info            TEXT;
    new_log_id        INTEGER;
BEGIN
    -- Определяем список таблиц для обработки
    IF table_name = 'all' THEN
        target_tables := ARRAY['ksk_result', 'ksk_figurant', 'ksk_figurant_match'];
    ELSE
        target_tables := ARRAY[table_name];
    END IF;

    RAISE NOTICE 'Проверка пустых партиций старше % дней (до %)', days_old, cutoff_date;

    -- Обработка каждой таблицы
    FOREACH current_table IN ARRAY target_tables LOOP
        RAISE NOTICE 'Обработка таблицы %...', current_table;

        FOR partition_record IN
            SELECT child.relname AS partition_name
            FROM pg_inherits i
            JOIN pg_class parent ON parent.oid = i.inhparent
            JOIN pg_class child  ON child.oid  = i.inhrelid
            WHERE parent.relname = current_table
              AND child.relname < 'part_' || current_table || '_' || TO_CHAR(cutoff_date, 'YYYY_MM_DD')
        LOOP
            BEGIN
                -- Оптимизированная проверка: партиция пуста?
                -- Использует EXISTS вместо COUNT(*) - останавливается на первой найденной строке
                EXECUTE FORMAT(
                    'SELECT NOT EXISTS (SELECT 1 FROM %I LIMIT 1)',
                    partition_record.partition_name
                ) INTO is_empty;

                IF is_empty THEN
                    -- Удаляем пустую партицию
                    EXECUTE FORMAT('DROP TABLE %I', partition_record.partition_name);
                    empty_partitions := ARRAY_APPEND(empty_partitions, partition_record.partition_name);
                    RAISE NOTICE '  ✓ Удалена пустая партиция: %', partition_record.partition_name;
                END IF;

            EXCEPTION WHEN OTHERS THEN
                v_error_count := v_error_count + 1;
                v_error_msg := COALESCE(v_error_msg || E'\n', '') || 
                              partition_record.partition_name || ': ' || SQLERRM;
                RAISE WARNING '  ✗ Ошибка при проверке партиции %: %', 
                    partition_record.partition_name, SQLERRM;
            END;
        END LOOP;
    END LOOP;

    -- Определение статуса операции
    IF v_error_count > 0 THEN
        v_status := 'error';
    END IF;

    -- Итоговое сообщение
    IF ARRAY_LENGTH(empty_partitions, 1) IS NULL THEN
        RAISE NOTICE 'Пустых партиций не найдено';
    ELSE
        RAISE NOTICE 'Всего удалено пустых партиций: %', ARRAY_LENGTH(empty_partitions, 1);
    END IF;

    -- Формирование информационного сообщения
    v_info := FORMAT(
        'Таблицы: %s. Дата отсечения: %s (старше %s дней). Удалено партиций: %s. Ошибок: %s',
        CASE WHEN table_name = 'all' THEN 'все' ELSE table_name END,
        cutoff_date,
        days_old,
        COALESCE(ARRAY_LENGTH(empty_partitions, 1), 0),
        v_error_count
    );

    -- Запись в системный лог
    SELECT upoa_ksk_reports.ksk_log_operation(
        'cleanup_empty_partitions',
        'Удаление пустых партиций',
        v_start_time,
        v_status,
        v_info,
        v_error_msg
    ) INTO new_log_id;

    RAISE NOTICE 'Операция записана в лог (ID: %)', new_log_id;

    -- Возвращаем результаты
    RETURN QUERY SELECT
        new_log_id,
        empty_partitions,
        (CLOCK_TIMESTAMP() - v_start_time)::INTERVAL;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_empty_partitions(TEXT, INTEGER) IS 
    'Удаляет партиции, в которых совсем нет данных. Использует оптимизированную проверку через EXISTS';
