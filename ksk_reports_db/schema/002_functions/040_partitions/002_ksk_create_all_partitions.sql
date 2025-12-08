-- ============================================================================
-- ФУНКЦИЯ: ksk_create_partitions_for_all_tables
-- ============================================================================
-- ОПИСАНИЕ:
--   Создаёт партиции для всех таблиц КСК (ksk_result, ksk_figurant, ksk_figurant_match)
--   Обрабатывает ошибки для каждой таблицы независимо
--   Записывает результат выполнения в системный лог
--
-- ПАРАМЕТРЫ:
--   @base_date  - Начальная дата (по умолчанию: текущая дата)
--   @days_ahead - Количество дней вперёд (по умолчанию: 7)
--
-- ВОЗВРАЩАЕТ:
--   JSON - Объект с результатами для каждой таблицы:
--          { "ksk_result": [...], "ksk_figurant": [...], "ksk_figurant_match": [...] }
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_create_partitions_for_all_tables();
--   SELECT ksk_create_partitions_for_all_tables(CURRENT_DATE, 14);
--
-- ЗАМЕТКИ:
--   - Рекомендуется запускать ежедневно в cron
--   - При ошибке для одной таблицы другие продолжают обрабатываться
--   - Результат записывается в ksk_system_operations_log
--
-- ЗАВИСИМОСТИ:
--   - ksk_create_partitions(TEXT, DATE, INTEGER)
--   - ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование операций
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_create_partitions_for_all_tables(
    base_date   DATE    DEFAULT CURRENT_DATE,
    days_ahead  INTEGER DEFAULT 7
)
RETURNS JSON AS $$
DECLARE
    result              JSON := '{}';
    tables              TEXT[] := ARRAY['ksk_result', 'ksk_figurant', 'ksk_figurant_match'];
    table_name          TEXT;
    created_partitions  TEXT[];
    v_start_time        TIMESTAMP := CLOCK_TIMESTAMP();
    v_status            VARCHAR := 'success';
    v_error_msg         TEXT := NULL;
    v_total_created     INTEGER := 0;
    v_info              TEXT;
BEGIN
    RAISE NOTICE 'Создание партиций для всех таблиц КСК от % на % дней вперёд', 
        base_date, days_ahead;

    FOREACH table_name IN ARRAY tables LOOP
        BEGIN
            -- Создание партиций для таблицы
            created_partitions := ksk_create_partitions(table_name, base_date, days_ahead);
            
            -- Добавление результата в JSON
            result := JSONB_SET(
                result::JSONB,
                ARRAY[table_name],
                TO_JSONB(created_partitions)
            )::JSON;
            
            -- Подсчёт общего количества созданных партиций
            v_total_created := v_total_created + COALESCE(ARRAY_LENGTH(created_partitions, 1), 0);

        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'Ошибка при создании партиций для %: %', table_name, SQLERRM;
            
            v_status := 'error';
            v_error_msg := COALESCE(v_error_msg || E'\n', '') || 
                          'Таблица ' || table_name || ': ' || SQLERRM;
            
            result := JSONB_SET(
                result::JSONB,
                ARRAY[table_name],
                '"ERROR"'
            )::JSON;
        END;
    END LOOP;

    -- Формирование информационного сообщения
    v_info := FORMAT(
        'Период: %s - %s (%s дней). Всего создано партиций: %s. Детали: %s',
        base_date,
        base_date + days_ahead,
        days_ahead,
        v_total_created,
        result::TEXT
    );

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'create_partitions_all',
        'Создание партиций для всех таблиц',
        v_start_time,
        v_status,
        v_info,
        v_error_msg
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_create_partitions_for_all_tables(DATE, INTEGER) IS 
    'Создаёт партиции для всех таблиц КСК с обработкой ошибок и логированием';
