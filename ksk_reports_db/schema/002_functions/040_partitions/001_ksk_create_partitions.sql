-- ============================================================================
-- ФУНКЦИЯ: ksk_create_partitions
-- ============================================================================
-- ОПИСАНИЕ:
--   Создаёт дневные партиции для указанной таблицы КСК
--   Проверяет существование партиций перед созданием (идемпотентность)
--
-- ПАРАМЕТРЫ:
--   @table_name   - Имя таблицы (ksk_result | ksk_figurant | ksk_figurant_match)
--   @base_date    - Начальная дата для создания партиций (по умолчанию: текущая дата)
--   @days_ahead   - Количество дней вперёд (1-30, по умолчанию: 7)
--
-- ВОЗВРАЩАЕТ:
--   TEXT[] - Массив имён созданных партиций
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_create_partitions('ksk_result', CURRENT_DATE, 7);
--   SELECT ksk_create_partitions('ksk_figurant', CURRENT_DATE + 1, 14);
--
-- ЗАМЕТКИ:
--   - Если партиция уже существует, создание пропускается
--   - Формат имени партиции: part_{table_name}_YYYY_MM_DD
--   - Диапазон партиции: [DATE, DATE + 1 day)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из create_ksk_partitions
-- ============================================================================

CREATE OR REPLACE FUNCTION ksk_create_partitions(
    table_name   TEXT,
    base_date    DATE    DEFAULT CURRENT_DATE,
    days_ahead   INTEGER DEFAULT 7
)
RETURNS TEXT[] AS $$
DECLARE
    created_partitions  TEXT[]    := '{}';
    partition_date      DATE;
    full_partition_name TEXT;
    start_timestamp     TIMESTAMP;
    end_timestamp       TIMESTAMP;
    i                   INTEGER;
BEGIN
    -- Валидация параметров
    IF table_name NOT IN ('ksk_result', 'ksk_figurant_match', 'ksk_figurant') THEN
        RAISE EXCEPTION 
            'Неподдерживаемая таблица "%" для ksk_create_partitions. Допустимые: ksk_result, ksk_figurant_match, ksk_figurant', 
            table_name;
    END IF;

    IF days_ahead < 1 OR days_ahead > 30 THEN
        RAISE EXCEPTION 
            'Параметр days_ahead должен быть в диапазоне 1-30 (получено: %)', 
            days_ahead;
    END IF;

    RAISE NOTICE 'Создание партиций для таблицы % от % на % дней вперёд', 
        table_name, base_date, days_ahead;

    -- Цикл создания партиций
    FOR i IN 0..(days_ahead - 1) LOOP
        partition_date := base_date + i;
        full_partition_name := 'part_' || table_name || '_' || TO_CHAR(partition_date, 'YYYY_MM_DD');
        start_timestamp := partition_date;
        end_timestamp := partition_date + INTERVAL '1 day';

        -- Проверка существования партиции
        IF NOT EXISTS (
            SELECT 1 
            FROM pg_class
            WHERE relname = full_partition_name 
              AND relkind = 'r'
        ) THEN
            -- Создание партиции
            EXECUTE FORMAT(
                'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
                full_partition_name, table_name, start_timestamp, end_timestamp
            );
            
            created_partitions := ARRAY_APPEND(created_partitions, full_partition_name);
            RAISE NOTICE '  ✓ Создана партиция: %', full_partition_name;
        ELSE
            RAISE NOTICE '  ⊙ Партиция % уже существует (пропущено)', full_partition_name;
        END IF;
    END LOOP;

    -- Итоговое сообщение
    IF ARRAY_LENGTH(created_partitions, 1) IS NULL THEN
        RAISE NOTICE 'Все партиции уже существуют для таблицы %', table_name;
    ELSE
        RAISE NOTICE 'Для таблицы % создано партиций: %', 
            table_name, ARRAY_LENGTH(created_partitions, 1);
    END IF;

    RETURN created_partitions;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_create_partitions(TEXT, DATE, INTEGER) IS 
    'Создаёт дневные партиции для таблицы КСК (идемпотентная операция)';
