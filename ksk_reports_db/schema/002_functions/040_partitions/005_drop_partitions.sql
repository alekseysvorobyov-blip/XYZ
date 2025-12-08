-- ============================================================================
-- ФУНКЦИЯ: ksk_drop_old_partitions
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет партиции старше указанного количества дней
--   Соблюдает правильный порядок удаления (от зависимых к независимым)
--   Записывает результат выполнения в системный лог
--
-- ПАРАМЕТРЫ:
--   @cutoff_days - Количество дней для хранения (по умолчанию: 365)
--
-- ВОЗВРАЩАЕТ:
--   TEXT[] - Массив имён удалённых партиций
--
-- ПОРЯДОК УДАЛЕНИЯ:
--   1. ksk_figurant_match (самая зависимая)
--   2. ksk_figurant (зависит от ksk_result)
--   3. ksk_result (наименее зависимая)
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_drop_old_partitions();           -- Удалить старше 365 дней
--   SELECT ksk_drop_old_partitions(180);        -- Удалить старше 180 дней
--
-- ЗАМЕТКИ:
--   - Рекомендуется запускать раз в месяц
--   - Использует CASCADE для удаления зависимостей
--   - Обрабатывает ошибки для каждой партиции независимо
--   - Результат записывается в ksk_system_operations_log
--
-- ВНИМАНИЕ:
--   ⚠️  ОПЕРАЦИЯ НЕОБРАТИМА! Убедитесь в наличии бэкапов.
--   ⚠️  Протестируйте на тестовом окружении перед применением.
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование операций
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_drop_old_partitions(
    cutoff_days INTEGER DEFAULT 365
)
RETURNS TEXT[] AS $$
DECLARE
    dropped_partitions TEXT[] := '{}';
    partition_record   RECORD;
    cutoff_date        DATE;
    v_start_time       TIMESTAMP := CLOCK_TIMESTAMP();
    v_status           VARCHAR := 'success';
    v_error_msg        TEXT := NULL;
    v_info             TEXT;
    v_error_count      INTEGER := 0;
BEGIN
    -- Расчёт даты отсечения
    cutoff_date := CURRENT_DATE - (cutoff_days || ' days')::INTERVAL;
    
    RAISE NOTICE 'Удаление партиций старше % дней (до %)', cutoff_days, cutoff_date;

    -- ========================================================================
    -- ШАГ 1: Удаление ksk_figurant_match (самая зависимая таблица)
    -- ========================================================================
    RAISE NOTICE 'Удаление партиций ksk_figurant_match...';
    
    FOR partition_record IN
        SELECT tablename
        FROM pg_tables
        WHERE tablename LIKE 'part_ksk_figurant_match_%'
          AND tablename < 'part_ksk_figurant_match_' || TO_CHAR(cutoff_date, 'YYYY_MM_DD')
        ORDER BY tablename
    LOOP
        BEGIN
            EXECUTE 'DROP TABLE ' || QUOTE_IDENT(partition_record.tablename) || ' CASCADE';
            dropped_partitions := ARRAY_APPEND(dropped_partitions, partition_record.tablename);
            RAISE NOTICE '  ✓ Удалена: %', partition_record.tablename;
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            v_error_msg := COALESCE(v_error_msg || E'\n', '') || 
                          partition_record.tablename || ': ' || SQLERRM;
            RAISE WARNING '  ✗ Ошибка удаления %: %', partition_record.tablename, SQLERRM;
        END;
    END LOOP;

    -- ========================================================================
    -- ШАГ 2: Удаление ksk_figurant
    -- ========================================================================
    RAISE NOTICE 'Удаление партиций ksk_figurant...';
    
    FOR partition_record IN
        SELECT tablename
        FROM pg_tables
        WHERE tablename LIKE 'part_ksk_figurant_%'
          AND tablename NOT LIKE 'part_ksk_figurant_match_%'
          AND tablename < 'part_ksk_figurant_' || TO_CHAR(cutoff_date, 'YYYY_MM_DD')
        ORDER BY tablename
    LOOP
        BEGIN
            EXECUTE 'DROP TABLE ' || QUOTE_IDENT(partition_record.tablename) || ' CASCADE';
            dropped_partitions := ARRAY_APPEND(dropped_partitions, partition_record.tablename);
            RAISE NOTICE '  ✓ Удалена: %', partition_record.tablename;
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            v_error_msg := COALESCE(v_error_msg || E'\n', '') || 
                          partition_record.tablename || ': ' || SQLERRM;
            RAISE WARNING '  ✗ Ошибка удаления %: %', partition_record.tablename, SQLERRM;
        END;
    END LOOP;

    -- ========================================================================
    -- ШАГ 3: Удаление ksk_result (наименее зависимая)
    -- ========================================================================
    RAISE NOTICE 'Удаление партиций ksk_result...';
    
    FOR partition_record IN
        SELECT tablename
        FROM pg_tables
        WHERE tablename LIKE 'part_ksk_result_%'
          AND tablename < 'part_ksk_result_' || TO_CHAR(cutoff_date, 'YYYY_MM_DD')
        ORDER BY tablename
    LOOP
        BEGIN
            EXECUTE 'DROP TABLE ' || QUOTE_IDENT(partition_record.tablename) || ' CASCADE';
            dropped_partitions := ARRAY_APPEND(dropped_partitions, partition_record.tablename);
            RAISE NOTICE '  ✓ Удалена: %', partition_record.tablename;
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            v_error_msg := COALESCE(v_error_msg || E'\n', '') || 
                          partition_record.tablename || ': ' || SQLERRM;
            RAISE WARNING '  ✗ Ошибка удаления %: %', partition_record.tablename, SQLERRM;
        END;
    END LOOP;

    -- Определение статуса операции
    IF v_error_count > 0 THEN
        v_status := 'error';
    END IF;

    -- Формирование информационного сообщения
    v_info := FORMAT(
        'Дата отсечения: %s (старше %s дней). Удалено партиций: %s. Ошибок: %s',
        cutoff_date,
        cutoff_days,
        COALESCE(ARRAY_LENGTH(dropped_partitions, 1), 0),
        v_error_count
    );

    -- Итоговое сообщение
    IF ARRAY_LENGTH(dropped_partitions, 1) IS NULL THEN
        RAISE NOTICE 'Нет партиций для удаления';
    ELSE
        RAISE NOTICE 'Всего удалено партиций: %', ARRAY_LENGTH(dropped_partitions, 1);
    END IF;

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'drop_old_partitions',
        'Удаление старых партиций',
        v_start_time,
        v_status,
        v_info,
        v_error_msg
    );
    
    RETURN dropped_partitions;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_drop_old_partitions(INTEGER) IS 
    'Удаляет партиции старше указанного количества дней с логированием (по умолчанию 365)';
