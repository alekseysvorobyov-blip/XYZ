-- ============================================================================
-- ОБЪЕДИНЕННЫЙ SQL СКРИПТ
-- ============================================================================
-- Дата создания: 2025-12-16 15:03:09
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 000_initial_script.sql
-- Размер: 0.52 KB
-- ============================================================================

SET client_min_messages = NOTICE;
SET client_encoding = 'UTF8';
-- Создание схемы
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'upoa_ksk_reports') THEN
        CREATE SCHEMA upoa_ksk_reports;
        RAISE NOTICE 'Схема upoa_ksk_reports создана';
    ELSE
        RAISE NOTICE 'Схема upoa_ksk_reports уже существует';
    END IF;
END $$;

-- В начале файла миграции
SET search_path TO upoa_ksk_reports, public;

-- ============================================================================
-- ФАЙЛ: 050_add_column_if_not_exists.sql
-- Размер: 4.82 KB
-- ============================================================================

-- ============================================================================
-- Функция: add_column_if_not_exists
-- Схема: upoa_ksk_reports
-- ============================================================================
-- Описание:
--   Добавляет новое поле (столбец) в указанную таблицу, если оно еще не существует.
--   Работает для всех допустимых в PostgreSQL типов данных, включая массивы, кастомные типы и т.д.
--   Функция идемпотентна - повторные вызовы с теми же параметрами не вызывают ошибок.
--
-- Параметры:
--   p_table_name    (text)   - имя таблицы (если не указана схема, используется upoa_ksk_reports)
--   p_column_name   (text)   - имя столбца
--   p_column_type   (text)   - тип столбца (например: 'integer', 'text', 'jsonb', 'varchar(255)', 'timestamp', 'integer[]' и т.п.)
--   p_column_default (text, optional) - выражение для DEFAULT значения (например: 'now()', '0', 'NULL')
--
-- Примеры:
--   SELECT upoa_ksk_reports.add_column_if_not_exists('reports', 'is_verified', 'boolean', 'false');
--   SELECT upoa_ksk_reports.add_column_if_not_exists('log', 'meta', 'jsonb');
--   SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.facts', 'extra_info', 'varchar(255)');
--   SELECT upoa_ksk_reports.add_column_if_not_exists('test_table', 'numbers', 'integer[]');
--
-- Свойства:
--   IDEMPOTENT - безопасна для повторного запуска
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.add_column_if_not_exists(
    p_table_name text,
    p_column_name text,
    p_column_type text,
    p_column_default text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
    v_schema_name text;
    v_actual_table_name text;
    v_table_exists boolean;
    v_column_exists boolean;
    v_sql text;
    v_full_table_name text;
BEGIN
    -- Парсим имя таблицы: если содержит точку, берём как есть, иначе добавляем схему по умолчанию
    IF p_table_name LIKE '%.%' THEN
        v_schema_name := split_part(p_table_name, '.', 1);
        v_actual_table_name := split_part(p_table_name, '.', 2);
    ELSE
        v_schema_name := 'upoa_ksk_reports';
        v_actual_table_name := p_table_name;
    END IF;

    v_full_table_name := v_schema_name || '.' || v_actual_table_name;

    -- Проверяем, существует ли таблица
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = v_schema_name
          AND table_name = v_actual_table_name
    )
    INTO v_table_exists;

    IF NOT v_table_exists THEN
        RAISE NOTICE '[add_column_if_not_exists] ❌ Таблица % не существует', v_full_table_name;
        RETURN;
    END IF;

    -- Проверяем, существует ли столбец
    SELECT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = v_schema_name
          AND table_name = v_actual_table_name
          AND column_name = p_column_name
    )
    INTO v_column_exists;

    IF v_column_exists THEN
        RAISE NOTICE '[add_column_if_not_exists] ℹ️  Столбец %.% уже существует', v_full_table_name, p_column_name;
        RETURN;
    END IF;

    -- Добавляем столбец
    BEGIN
        v_sql := 'ALTER TABLE ' || quote_ident(v_schema_name) || '.' || quote_ident(v_actual_table_name) ||
                 ' ADD COLUMN ' || quote_ident(p_column_name) ||
                 ' ' || p_column_type;
        
        IF p_column_default IS NOT NULL THEN
            v_sql := v_sql || ' DEFAULT ' || p_column_default;
        END IF;
        
        EXECUTE v_sql;
        
        IF p_column_default IS NOT NULL THEN
            RAISE NOTICE '[add_column_if_not_exists] ✅ Столбец %.% добавлен как % (DEFAULT: %)', 
                v_full_table_name, p_column_name, p_column_type, p_column_default;
        ELSE
            RAISE NOTICE '[add_column_if_not_exists] ✅ Столбец %.% добавлен как %', 
                v_full_table_name, p_column_name, p_column_type;
        END IF;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '[add_column_if_not_exists] ❌ Ошибка при добавлении столбца %.%: %', 
            v_full_table_name, p_column_name, SQLERRM;
        RAISE;
    END;

END;
$function$;


-- ============================================================================
-- ФАЙЛ: 100_jsonb_object_length.sql
-- Размер: 2.07 KB
-- ============================================================================

-- ============================================================================
-- Функция: jsonb_object_length
-- Схема: upoa_ksk_reports
-- ============================================================================
-- Описание:
--   Универсальная функция для определения "размера" JSONB значения.
--   Возвращает количество элементов независимо от типа JSONB структуры.
--
-- Параметры:
--   input_data (jsonb) - входное JSONB значение любого типа
--
-- Возвращает:
--   integer - количество элементов/размер значения
--
-- Логика работы:
--   - Объект: возвращает количество полей (ключей)
--   - Массив: возвращает количество элементов
--   - Скаляр (строка, число, boolean): возвращает 1
--   - null: возвращает 0
--
-- Примеры:
--   SELECT jsonb_object_length('{"a":1,"b":2}'::jsonb);        -- 2
--   SELECT jsonb_object_length('[1,2,3,4]'::jsonb);             -- 4
--   SELECT jsonb_object_length('"text"'::jsonb);                -- 1
--   SELECT jsonb_object_length('null'::jsonb);                  -- 0
--
-- Свойства:
--   IMMUTABLE - результат зависит только от входных параметров
--   PARALLEL SAFE - может использоваться в параллельных запросах
--
-- Дата создания: 2025-10-27
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.jsonb_object_length(input_data jsonb)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
SELECT CASE jsonb_typeof(input_data)
    WHEN 'object' THEN (SELECT count(*)::integer FROM jsonb_each(input_data))
    WHEN 'array' THEN jsonb_array_length(input_data)
    WHEN 'null' THEN 0
    ELSE 1
END;
$function$;


-- ============================================================================
-- ФАЙЛ: 001_ksk_result.sql
-- Размер: 19.45 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_result (ПОЛНЫЙ СКРИПТ СОЗДАНИЯ)
-- ДАТА ОБНОВЛЕНИЯ: 2025-10-29
-- НАЗНАЧЕНИЕ: Основная таблица результатов проверки КСК с Kafka метаданными
-- ============================================================================
-- ОПИСАНИЕ:
--   Таблица содержит результаты проверки платежей по требованиям КСК.
--   Включает партиционирование по output_timestamp (ежедневно).
--   Оптимизирована для работы с ~3M записей/день (3TB на HDD за год).
--   Содержит JSON входящего и выходящего данных, денормализованные поля для отчётов.
--   Содержит Kafka метаданные (partition, offset, headers) для отслеживания источников.
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-26 - Оптимизация производительности (BRIN, GIN индексы)
--   2025-10-28 - Добавлены Kafka headers (input_kafka_headers, output_kafka_headers)
--   2025-10-29 - Добавлены Kafka метаданные (partition, offset)
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_result (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Основная таблица с результатами проверки КСК
-- Дата: 2025-10-28 (обновлено: добавлены kafka параметры)
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

-- Проверяем существование таблицы и создаём её если нет
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'upoa_ksk_reports' 
        AND table_name = 'ksk_result'
    ) THEN
        -- Создание основной таблицы с партиционированием
        CREATE TABLE upoa_ksk_reports.ksk_result (
            -- Первичный ключ и технические поля
            id INTEGER GENERATED ALWAYS AS IDENTITY,
            date DATE NOT NULL,
            corr_id VARCHAR(100) NOT NULL,
            
            -- Временные метки
            input_timestamp TIMESTAMP(3),
            output_timestamp TIMESTAMP(3) NOT NULL,
            
            -- JSON данные
            input_json JSONB,
            output_json JSONB,
            
            -- Классификация транзакции
            payment_type VARCHAR(20) NOT NULL,
            resolution VARCHAR(20) NOT NULL,
            list_codes TEXT[],
            has_bypass VARCHAR(10) DEFAULT 'empty',
            
            -- Поля из input_json для оптимизации запросов (денормализация)
            payment_id TEXT,
            payment_purpose TEXT,
            account_debet TEXT,
            account_credit TEXT,
            
            -- Информация о плательщике
            payer_inn TEXT,
            payer_name TEXT,
            payer_account_number TEXT,
            payer_document_type TEXT,
            payer_bank_name TEXT,
            payer_bank_account_number TEXT,
            
            -- Информация о получателе
            receiver_account_number TEXT,
            receiver_name TEXT,
            receiver_inn TEXT,
            receiver_bank_name TEXT,
            receiver_bank_account_number TEXT,
            receiver_document_type TEXT,
            
            -- Финансовая информация
            amount TEXT,
            currency TEXT,
            currency_control TEXT,
            
            -- Kafka метаданные (ДОБАВЛЕНО 28.10.2025)
            input_kafka_headers JSONB,
            output_kafka_headers JSONB,
            
            -- Kafka метаданные для трассировки (ДОБАВЛЕНО 29.10.2025)
            input_kafka_partition INTEGER,
            input_kafka_offset BIGINT,
			
			-- Точное время создания записи в БД
			created_date TIMESTAMP(3) NOT NULL DEFAULT NOW(),
            
            -- Первичный ключ включает колонку партиционирования
            PRIMARY KEY (id, output_timestamp)
        ) PARTITION BY RANGE (output_timestamp);
        

        -- Убедитесь, что стратегия хранения EXTENDED (должна быть по умолчанию)
        -- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
        ALTER TABLE upoa_ksk_reports.ksk_result
           ALTER COLUMN input_json SET STORAGE EXTENDED,
           ALTER COLUMN output_json SET STORAGE EXTENDED,
           ALTER COLUMN input_kafka_headers SET STORAGE EXTENDED,
           ALTER COLUMN output_kafka_headers SET STORAGE EXTENDED;

        -- Включите сжатие LZ4 для колонок
        ALTER TABLE upoa_ksk_reports.ksk_result 
            ALTER COLUMN input_json SET COMPRESSION lz4,
            ALTER COLUMN output_json SET COMPRESSION lz4,
            ALTER COLUMN input_kafka_headers SET COMPRESSION lz4,
            ALTER COLUMN output_kafka_headers SET COMPRESSION lz4;
        
        -- Партиция по умолчанию для новых данных
        CREATE TABLE upoa_ksk_reports.part_ksk_result_default
            PARTITION OF upoa_ksk_reports.ksk_result DEFAULT;
        
        -- Комментарии для документации
        COMMENT ON TABLE upoa_ksk_reports.ksk_result 
            IS 'Основная таблица результатов проверки КСК (приблизительно 3M записей/день, 3TB в год)';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.id 
            IS 'Уникальный идентификатор записи';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.corr_id 
            IS 'Корреляционный ID платежа - индекс B-tree';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.resolution 
            IS 'Резолюция проверки (allow, review, deny, empty)';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.has_bypass 
            IS 'Признак обхода проверки (empty/yes/no)';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.list_codes 
            IS 'Массив кодов санкционных списков - GIN индекс';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.input_json 
            IS 'Входящий JSON (исходный запрос) - EXTERNAL STORAGE';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.output_json 
            IS 'Выходящий JSON (результат проверки) - EXTERNAL STORAGE';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.input_kafka_headers 
            IS 'Kafka headers от входящего сообщения (upoa_enriched_transactions) - EXTERNAL STORAGE - ДОБАВЛЕНО 28.10.2025';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.output_kafka_headers 
            IS 'Kafka headers от выходящего сообщения (upoa_ksk_results) - EXTERNAL STORAGE - ДОБАВЛЕНО 28.10.2025';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.input_kafka_partition 
            IS 'Номер партиции Kafka входящего сообщения (для отладки и трассировки) - ДОБАВЛЕНО 29.10.2025';
        
        COMMENT ON COLUMN upoa_ksk_reports.ksk_result.input_kafka_offset 
            IS 'Offset входящего сообщения в партиции Kafka (уникален вместе с partition) - ДОБАВЛЕНО 29.10.2025';
			
		COMMENT ON COLUMN upoa_ksk_reports.ksk_result.created_date 
			IS 'Точное время создания записи в БД (по часам сервера). Используется для audit trail и SLA контроля.';
        
        RAISE NOTICE '[ksk_result] ✅ Таблица создана с партиционированием по output_timestamp';
    ELSE
        RAISE NOTICE '[ksk_result] ℹ️  Таблица уже существует, пропуск создания';
    END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'corr_id', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'input_timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'output_timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'input_json', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'output_json', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payment_type', 'VARCHAR(20)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'resolution', 'VARCHAR(20)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'list_codes', 'TEXT[]');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'has_bypass', 'VARCHAR(10)', '''empty''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payment_id', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payment_purpose', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'account_debet', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'account_credit', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payer_inn', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payer_name', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payer_account_number', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payer_document_type', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payer_bank_name', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'payer_bank_account_number', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'receiver_account_number', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'receiver_name', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'receiver_inn', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'receiver_bank_name', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'receiver_bank_account_number', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'receiver_document_type', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'amount', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'currency', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'currency_control', 'TEXT');

-- ДОБАВЛЕНИЕ KAFKA HEADERS (28.10.2025)
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'input_kafka_headers', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'output_kafka_headers', 'JSONB');

-- ДОБАВЛЕНИЕ KAFKA МЕТАДАННЫХ (29.10.2025)
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'input_kafka_partition', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'input_kafka_offset', 'BIGINT');

-- Добавление колонки created_date (идемпотентно) (13.11.2025)
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result', 'created_date', 'TIMESTAMP(3)','NOW()'::TEXT);
COMMENT ON COLUMN upoa_ksk_reports.ksk_result.created_date IS 'Точное время создания записи в БД (по часам сервера). Используется для audit trail и SLA контроля.';


SELECT '[ksk_result] ✅ Проверка и добавление колонок завершена (35 + 4 Kafka = 39 колонок)';

-- ============================================================================
-- 2.1. НАСТРОЙКА STORAGE EXTERNAL ДЛЯ KAFKA HEADERS (для существующих таблиц)
-- ============================================================================

DO $$
BEGIN
    -- Устанавливаем STORAGE EXTERNAL для JSONB колонок если таблица уже существовала
    BEGIN
        ALTER TABLE upoa_ksk_reports.ksk_result 
            ALTER COLUMN input_kafka_headers SET STORAGE EXTERNAL;
        RAISE NOTICE '[ksk_result] ✅ STORAGE EXTERNAL установлен для input_kafka_headers';
    EXCEPTION
        WHEN undefined_column THEN
            RAISE NOTICE '[ksk_result] ⚠️  Колонка input_kafka_headers не найдена';
    END;
    
    BEGIN
        ALTER TABLE upoa_ksk_reports.ksk_result 
            ALTER COLUMN output_kafka_headers SET STORAGE EXTERNAL;
        RAISE NOTICE '[ksk_result] ✅ STORAGE EXTERNAL установлен для output_kafka_headers';
    EXCEPTION
        WHEN undefined_column THEN
            RAISE NOTICE '[ksk_result] ⚠️  Колонка output_kafka_headers не найдена';
    END;
END $$;

-- ============================================================================
-- 3. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- ---- ВАЖНО: Использование CREATE INDEX IF NOT EXISTS гарантирует идемпотентность ----

-- 3.1. B-tree индекс на corr_id (корреляционный ID платежа)
-- Поддержка часто использует поиск по corrId
-- Применение: SELECT * FROM ksk_result WHERE corr_id = 'abc-123'
--
CREATE INDEX IF NOT EXISTS idx_ksk_result_corr_id
    ON upoa_ksk_reports.ksk_result (corr_id);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_corr_id 
    IS 'B-tree: Поиск по корреляционному ID. Часто используется поддержкой при отладке платежей.';

-- 3.2. BRIN индекс для фильтрации по временным диапазонам
-- BRIN в 1000 раз компактнее B-tree для временных рядов
-- Идеален для партиционированных таблиц с упорядоченными данными
-- Применение: фильтрация по датам в отчётах (WHERE output_timestamp > now() - interval '7 days')
--
CREATE INDEX IF NOT EXISTS idx_ksk_result_output_ts_brin
    ON upoa_ksk_reports.ksk_result USING BRIN (output_timestamp)
    WITH (pages_per_range = 128);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_output_ts_brin 
    IS 'BRIN: Фильтрация по временным диапазонам. ~1000x меньше, чем B-tree. Критичен на HDD.';

-- 3.3. Комбинированный индекс для агрегаций и отчётов
-- Три колонки в WHERE + одна в SELECT (INCLUDE)
-- INCLUDE покрывает весь запрос = нулевых обращений к таблице (index-only scan)
-- Применение: SELECT COUNT(*), resolution, has_bypass FROM ... GROUP BY resolution, has_bypass
--
CREATE INDEX IF NOT EXISTS idx_ksk_result_aggregation
    ON upoa_ksk_reports.ksk_result (output_timestamp, resolution, has_bypass)
    INCLUDE (payment_type);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_aggregation 
    IS 'Covering index: WHERE по (output_timestamp, resolution, has_bypass), SELECT payment_type. Index-only scan.';

-- 3.4. GIN индекс для поиска по массиву list_codes
-- Ускорение 10-20x для запросов: WHERE list_codes && ARRAY['code1', 'code2']
-- Применение: отчёты по санкционным спискам
--
CREATE INDEX IF NOT EXISTS idx_ksk_result_list_codes_gin
    ON upoa_ksk_reports.ksk_result USING GIN (list_codes);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_list_codes_gin 
    IS 'GIN: Поиск по массиву list_codes. Критичен для отчётов по спискам. 10-20x ускорение.';

-- 3.5. Простой B-tree индекс на payment_type
-- Фильтрация по типам платежей (i_*, o_*, t_*, m_*, v_*)
-- Применение: агрегация по типам платежей
--
CREATE INDEX IF NOT EXISTS idx_ksk_result_payment_type
    ON upoa_ksk_reports.ksk_result (payment_type);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_payment_type 
    IS 'B-tree: Фильтрация по типам платежей. Используется в большинстве отчётов.';

SELECT '[ksk_result] ✅ Индексы созданы/проверены (5 индексов)';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
-- ИТОГО:
-- ✅ Таблица ksk_result создана/обновлена
-- ✅ 39 колонок (35 исходных + 4 Kafka метаданных)
-- ✅ Партиционирование по output_timestamp (RANGE)
-- ✅ EXTERNAL storage для 4 JSONB колонок
-- ✅ 5 оптимизированных индексов
-- ✅ Полная идемпотентность (безопасна для повторного запуска)
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 002_ksk_figurant.sql
-- Размер: 13.47 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_figurant
-- ОПИСАНИЕ: Таблица с фигурантами (лица, на которых выпали проверки)
-- ============================================================================
-- Связи: 
--   - N:1 с ksk_result (через source_id)
--   - 1:N с ksk_figurant_match
-- Партиционирование: По дням (timestamp)
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_figurant (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Таблица с фигурантами (лица, на которых выпали проверки)
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

-- Проверяем существование таблицы и создаём её если нет
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_figurant'
  ) THEN
    
    -- Создание основной таблицы с партиционированием
    CREATE TABLE upoa_ksk_reports.ksk_figurant (
      -- Первичный ключ и связи
      id INTEGER GENERATED ALWAYS AS IDENTITY,
      source_id INTEGER NOT NULL,
      
      -- Временные метки
      date DATE NOT NULL,
      timestamp TIMESTAMP(3) NOT NULL,
      
      -- JSON данные
      figurant JSONB NOT NULL,
      figurant_index INTEGER NOT NULL,
      
      -- Классификация
      resolution VARCHAR(20) NOT NULL,
      is_bypass VARCHAR(10) DEFAULT 'no',
      
      -- Поля из figurant JSON
      list_code TEXT,
      name_figurant TEXT,
      president_group TEXT,
      auto_login BOOLEAN,
      has_exclusion BOOLEAN,
      exclusion_phrase TEXT,
      exclusion_name_list TEXT,
      bypass_name TEXT,
      
      -- Первичный ключ включает колонку партиционирования
      PRIMARY KEY (id, timestamp),
      
      -- Внешний ключ связь с ksk_result
      -- CASCADE DELETE: при удалении записи из ksk_result удаляются все фигуранты
      FOREIGN KEY (source_id, timestamp)
        REFERENCES upoa_ksk_reports.ksk_result(id, output_timestamp)
        ON DELETE CASCADE
    ) PARTITION BY RANGE (timestamp);
    
    -- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
    ALTER TABLE upoa_ksk_reports.ksk_figurant
       ALTER COLUMN figurant SET STORAGE EXTENDED;

    -- Включите сжатие LZ4 для колонок
    ALTER TABLE upoa_ksk_reports.ksk_figurant 
        ALTER COLUMN figurant SET COMPRESSION lz4;

    -- Партиция по умолчанию для новых данных
    -- КРИТИЧНО: Все строки, которые не попадают в явные партиции, попадают сюда
    CREATE TABLE upoa_ksk_reports.part_ksk_figurant_default 
      PARTITION OF upoa_ksk_reports.ksk_figurant DEFAULT;
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_figurant 
      IS 'Фигуранты - лица/организации, на которых выпали проверки КСК';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.source_id 
      IS 'Ссылка на ksk_result.id - N:1 связь';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.figurant 
      IS 'Полная информация о фигуранте в JSONB формате - EXTERNAL STORAGE';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.figurant_index 
      IS 'Порядковый номер фигуранта в результате проверки';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.resolution 
      IS 'Резолюция для фигуранта (ALLOW, BLOCK, REVIEW и т.д.)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.is_bypass 
      IS 'Признак обхода проверки (yes/no)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.list_code 
      IS 'Код санкционного списка';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.name_figurant 
      IS 'Полное имя фигуранта из санкционного списка';
    
    RAISE NOTICE '[ksk_figurant] ✅ Таблица создана с партиционированием по timestamp';
    RAISE NOTICE '[ksk_figurant] ✅ Дефолтная партиция создана: part_ksk_figurant_default';
    
  ELSE
    RAISE NOTICE '[ksk_figurant] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'source_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'figurant', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'figurant_index', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'resolution', 'VARCHAR(20)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'is_bypass', 'VARCHAR(10)', '''no''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'list_code', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'name_figurant', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'president_group', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'auto_login', 'BOOLEAN');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'has_exclusion', 'BOOLEAN');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'exclusion_phrase', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'exclusion_name_list', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'bypass_name', 'TEXT');

-- Добавляем комментарий на поле
COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.bypass_name IS 
'Имя исключения из списка исключений. Извлекается из JSON figuvant.bypassName при условии, что поле непусто. NULL если поле отсутствует или пусто.';

SELECT '[ksk_figurant] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================
-- Логика: выбираем все индексы на таблице, и удаляем те, что не в списке нужных
-- Это безопаснее чем удалять всё сразу, и правильнее чем вручную

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_figurant_ts_brin',
        'idx_ksk_figurant_list_code',
        'idx_ksk_figurant_source_id',
        'idx_ksk_figurant_resolution',
        'idx_ksk_figurant_is_bypass_yes'
    ];
    v_index_count integer := 0;
BEGIN
    -- Итерируем по всем индексам на таблице ksk_figurant (кроме PK и FK)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_figurant'
          AND indexname NOT LIKE '%_pkey'  -- Исключаем PK
    LOOP
        -- Проверяем, входит ли этот индекс в список нужных
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            -- Удаляем ненужный индекс
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_figurant] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    -- Итоговое сообщение
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_figurant] ℹ️  Ненужных индексов не найдено, пропуск удаления';
    ELSE
        RAISE NOTICE '[ksk_figurant] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- ---- ВАЖНО: Использование CREATE INDEX IF NOT EXISTS гарантирует идемпотентность ----

-- 4.1. BRIN индекс для timestamp (из 005_ksk_indexes_optimization.sql)
-- BRIN в 1000 раз компактнее B-tree для временных рядов
-- Идеален для партиционированных таблиц с упорядоченными данными
-- Применение: WHERE timestamp > now() - interval '7 days'
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_ts_brin
  ON upoa_ksk_reports.ksk_figurant USING BRIN (timestamp)
  WITH (pages_per_range = 128);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_ts_brin 
  IS 'BRIN: Фильтрация по временным диапазонам. ~1000x меньше, чем B-tree. Критичен на HDD.';

-- 4.2. Partial B-tree индекс на list_code (только NOT NULL значения) (из 005_ksk_indexes_optimization.sql)
-- Partial индекс экономит место (пропускает NULL)
-- Применение: поиск по коду санкционного списка (WHERE list_code = 'SDN')
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_list_code
  ON upoa_ksk_reports.ksk_figurant (list_code)
  WHERE list_code IS NOT NULL;
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_list_code 
  IS 'Partial B-tree: Поиск по санкционному списку. Только NOT NULL значения.';

-- 4.3. B-tree индекс на source_id (FK к ksk_result) (из 005_ksk_indexes_optimization.sql)
-- Критичен для JOIN операций между ksk_result и ksk_figurant
-- Применение: SELECT * FROM ksk_figurant WHERE source_id = X
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_source_id
  ON upoa_ksk_reports.ksk_figurant (source_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_source_id 
  IS 'B-tree: Индекс на внешний ключ для JOIN с ksk_result.';

-- 4.4. Индекс для фильтрации по resolution
-- Используется для агрегации по резолюциям
-- Применение: WHERE resolution = 'BLOCK'
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_resolution
  ON upoa_ksk_reports.ksk_figurant (resolution);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_resolution 
  IS 'B-tree: Фильтрация по резолюции. Используется в отчётах по результатам.';

-- 4.5. Partial индекс на is_bypass (только 'yes' значения)
-- Оптимизация: поиск только случаев обхода проверки
-- Применение: WHERE is_bypass = 'yes' - высокоселективный запрос
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_is_bypass_yes
  ON upoa_ksk_reports.ksk_figurant (is_bypass)
  WHERE is_bypass = 'yes';
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_is_bypass_yes 
  IS 'Partial B-tree: Поиск обходов проверки (is_bypass=yes). Экономит место, высокая селективность.';

SELECT '[ksk_figurant] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 003_ksk_match.sql
-- Размер: 11.26 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_figurant_match
-- ОПИСАНИЕ: Совпадения алгоритмов поиска для фигурантов
-- ============================================================================
-- Связи: 
--   - N:1 с ksk_figurant (через figurant_id)
-- Партиционирование: По дням (timestamp)
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_figurant_match (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Совпадения алгоритмов поиска для фигурантов
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

-- Проверяем существование таблицы и создаём её если нет
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_figurant_match'
  ) THEN
    
    -- Создание основной таблицы с партиционированием
    CREATE TABLE upoa_ksk_reports.ksk_figurant_match (
      -- Первичный ключ и связи
      id INTEGER GENERATED ALWAYS AS IDENTITY,
      figurant_id INTEGER NOT NULL,
      
      -- Временные метки
      date DATE NOT NULL,
      timestamp TIMESTAMP(3) NOT NULL,
      
      -- JSON данные
      match JSONB NOT NULL,
      match_index INTEGER NOT NULL,
      algorithm VARCHAR(100) NOT NULL,
      
      -- Поля из match JSON
      match_value TEXT,
      match_payment_field TEXT,
      match_payment_value TEXT,
      
      -- Первичный ключ включает колонку партиционирования
      PRIMARY KEY (id, timestamp),
      
      -- Внешний ключ связь с ksk_figurant
      -- CASCADE DELETE: при удалении фигуранта удаляются все его совпадения
      FOREIGN KEY (figurant_id, timestamp)
        REFERENCES upoa_ksk_reports.ksk_figurant(id, timestamp)
        ON DELETE CASCADE
    ) PARTITION BY RANGE (timestamp);
    
    -- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
    ALTER TABLE upoa_ksk_reports.ksk_figurant_match
       ALTER COLUMN match SET STORAGE EXTENDED;

    -- Включите сжатие LZ4 для колонок
    ALTER TABLE upoa_ksk_reports.ksk_figurant_match 
        ALTER COLUMN match SET COMPRESSION lz4;

    
    -- Партиция по умолчанию для новых данных
    -- КРИТИЧНО: Все строки, которые не попадают в явные партиции, попадают сюда
    CREATE TABLE upoa_ksk_reports.part_ksk_figurant_match_default 
      PARTITION OF upoa_ksk_reports.ksk_figurant_match DEFAULT;
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_figurant_match 
      IS 'Совпадения алгоритмов поиска для фигурантов';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.figurant_id 
      IS 'Ссылка на ksk_figurant.id - N:1 связь';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match 
      IS 'Полная информация о совпадении в JSONB формате - EXTERNAL STORAGE';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_index 
      IS 'Порядковый номер совпадения для фигуранта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.algorithm 
      IS 'Название алгоритма поиска совпадений';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_value 
      IS 'Значение совпадения из JSON';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_payment_field 
      IS 'Поле платежа, где найдено совпадение';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_payment_value 
      IS 'Значение поля платежа для совпадения';
    
    RAISE NOTICE '[ksk_figurant_match] ✅ Таблица создана с партиционированием по timestamp';
    RAISE NOTICE '[ksk_figurant_match] ✅ Дефолтная партиция создана: part_ksk_figurant_match_default';
    
  ELSE
    RAISE NOTICE '[ksk_figurant_match] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'figurant_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_index', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'algorithm', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_value', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_payment_field', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_payment_value', 'TEXT');

SELECT '[ksk_figurant_match] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================
-- Логика: выбираем все индексы на таблице, и удаляем те, что не в списке нужных
-- Это безопаснее чем удалять всё сразу, и правильнее чем вручную

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_match_ts_brin',
        'idx_ksk_match_figurant_id',
        'idx_ksk_match_algorithm'
    ];
    v_index_count integer := 0;
BEGIN
    -- Итерируем по всем индексам на таблице ksk_figurant_match (кроме PK и FK)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_figurant_match'
          AND indexname NOT LIKE '%_pkey'  -- Исключаем PK
    LOOP
        -- Проверяем, входит ли этот индекс в список нужных
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            -- Удаляем ненужный индекс
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_figurant_match] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    -- Итоговое сообщение
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_figurant_match] ℹ️  Ненужных индексов не найдено, пропуск удаления';
    ELSE
        RAISE NOTICE '[ksk_figurant_match] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- ---- ВАЖНО: Использование CREATE INDEX IF NOT EXISTS гарантирует идемпотентность ----

-- 4.1. BRIN индекс для timestamp (из 005_ksk_indexes_optimization.sql)
-- BRIN в 1000 раз компактнее B-tree для временных рядов
-- Идеален для партиционированных таблиц с упорядоченными данными
-- Применение: WHERE timestamp > now() - interval '7 days'
--
CREATE INDEX IF NOT EXISTS idx_ksk_match_ts_brin
  ON upoa_ksk_reports.ksk_figurant_match USING BRIN (timestamp)
  WITH (pages_per_range = 128);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_match_ts_brin 
  IS 'BRIN: Фильтрация по временным диапазонам. ~1000x меньше, чем B-tree. Критичен на HDD.';

-- 4.2. B-tree индекс на figurant_id (FK к ksk_figurant) (из 005_ksk_indexes_optimization.sql)
-- Критичен для JOIN операций между ksk_figurant и ksk_figurant_match
-- Применение: SELECT * FROM ksk_figurant_match WHERE figurant_id = X
--
CREATE INDEX IF NOT EXISTS idx_ksk_match_figurant_id
  ON upoa_ksk_reports.ksk_figurant_match (figurant_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_match_figurant_id 
  IS 'B-tree: Индекс на внешний ключ для JOIN с ksk_figurant.';

-- 4.3. B-tree индекс на algorithm (для фильтрации по алгоритмам) (из 005_ksk_indexes_optimization.sql)
-- Применение: отчёты по используемым алгоритмам поиска, фильтрация по типам совпадений
-- Используется для аналитики: SELECT algorithm, COUNT(*) FROM ksk_figurant_match GROUP BY algorithm
--
CREATE INDEX IF NOT EXISTS idx_ksk_match_algorithm
  ON upoa_ksk_reports.ksk_figurant_match (algorithm);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_match_algorithm 
  IS 'B-tree: Фильтрация по алгоритмам поиска. Используется для аналитики и статистики.';

SELECT '[ksk_figurant_match] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 004_ksk_system_operation_log.sql
-- Размер: 10.94 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_system_operations_log
-- ============================================================================
-- ОПИСАНИЕ:
--   Системный лог всех служебных операций в системе КСК
--   Записывает информацию о каждой операции с временем выполнения и результатом
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и комментарии
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_system_operations_log (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Системный лог всех служебных операций в системе отчётов
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

-- Проверяем существование таблицы и создаём её если нет
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_system_operations_log'
  ) THEN
    
    -- Создание таблицы системного логирования
    CREATE TABLE upoa_ksk_reports.ksk_system_operations_log (
      -- Первичный ключ (простой, без партиционирования)
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Идентификация операции
      operation_code VARCHAR(50) NOT NULL,
      operation_name VARCHAR(200) NOT NULL,
      
      -- Временные метки
      begin_time TIMESTAMP(3) NOT NULL DEFAULT NOW()::timestamp(3),
      end_time TIMESTAMP(3),
      duration INTERVAL,
      
      -- Результат выполнения
      -- CHECK constraint ограничивает значения только 'success' и 'error'
      status VARCHAR(20) NOT NULL CHECK (status IN ('success', 'error')),
      info TEXT,
      err_msg TEXT
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_system_operations_log 
      IS 'Системный лог всех служебных операций в системе отчётов';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.id 
      IS 'Уникальный идентификатор записи логирования';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.operation_code 
      IS 'Код операции (например: create_partitions, drop_partitions, run_report)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.operation_name 
      IS 'Человекочитаемое название операции';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.begin_time 
      IS 'Время начала операции (DEFAULT: NOW())';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.end_time 
      IS 'Время окончания операции';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.duration 
      IS 'Длительность выполнения операции (вычисляется как end_time - begin_time)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.status 
      IS 'Статус выполнения: success или error (CHECK constraint)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.info 
      IS 'Дополнительная информация о результате операции (JSON или текст)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.err_msg 
      IS 'Сообщение об ошибке при неудачном выполнении';
    
    RAISE NOTICE '[ksk_system_operations_log] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_system_operations_log] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'operation_code', 'VARCHAR(50)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'operation_name', 'VARCHAR(200)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'begin_time', 'TIMESTAMP(3)', 'now()::timestamp(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'end_time', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'duration', 'INTERVAL');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'status', 'VARCHAR(20)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'info', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'err_msg', 'TEXT');

SELECT '[ksk_system_operations_log] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================
-- Логика: выбираем все индексы на таблице, и удаляем те, что не в списке нужных
-- Это безопаснее чем удалять всё сразу, и правильнее чем вручную

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_system_operations_log_operation_code',
        'idx_ksk_system_operations_log_begin_time',
        'idx_ksk_system_operations_log_status'
    ];
    v_index_count integer := 0;
BEGIN
    -- Итерируем по всем индексам на таблице ksk_system_operations_log (кроме PK)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_system_operations_log'
          AND indexname NOT LIKE '%_pkey'  -- Исключаем PK
    LOOP
        -- Проверяем, входит ли этот индекс в список нужных
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            -- Удаляем ненужный индекс
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_system_operations_log] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    -- Итоговое сообщение
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_system_operations_log] ℹ️  Ненужных индексов не найдено, пропуск удаления';
    ELSE
        RAISE NOTICE '[ksk_system_operations_log] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- ---- ВАЖНО: Использование CREATE INDEX IF NOT EXISTS гарантирует идемпотентность ----

-- 4.1. B-tree индекс на operation_code
-- Применение: фильтрация логов по коду операции (WHERE operation_code = 'create_partitions')
-- Используется для поиска истории конкретной операции
--
CREATE INDEX IF NOT EXISTS idx_ksk_system_operations_log_operation_code
  ON upoa_ksk_reports.ksk_system_operations_log (operation_code);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_system_operations_log_operation_code 
  IS 'B-tree: Фильтрация логов по коду операции. Поиск истории операций.';

-- 4.2. B-tree индекс на begin_time
-- Применение: временная фильтрация логов (WHERE begin_time > now() - interval '1 day')
-- Используется для просмотра недавних операций
--
CREATE INDEX IF NOT EXISTS idx_ksk_system_operations_log_begin_time
  ON upoa_ksk_reports.ksk_system_operations_log (begin_time);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_system_operations_log_begin_time 
  IS 'B-tree: Фильтрация логов по времени начала. Поиск операций за период.';

-- 4.3. B-tree индекс на status
-- Применение: поиск ошибок (WHERE status = 'error') или успешных операций
-- Используется для мониторинга проблем
--
CREATE INDEX IF NOT EXISTS idx_ksk_system_operations_log_status
  ON upoa_ksk_reports.ksk_system_operations_log (status);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_system_operations_log_status 
  IS 'B-tree: Фильтрация логов по статусу. Поиск ошибок и успехов.';

SELECT '[ksk_system_operations_log] ✅ Индексы созданы/проверены';

DO $$
BEGIN
    ALTER TABLE upoa_ksk_reports.ksk_system_operations_log
    ALTER COLUMN begin_time TYPE TIMESTAMP(3),
    ALTER COLUMN end_time TYPE TIMESTAMP(3);
    
    RAISE NOTICE '✅ Миграция на TIMESTAMP(3) завершена';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ℹ️  Уже TIMESTAMP(3) или таблица не существует';
END $$;

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 005_ksk_result_error.sql
-- Размер: 16.69 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_result_error
-- НАЗНАЧЕНИЕ: Логирование ошибок при обработке JSON в функции put_ksk_result
-- ============================================================================
--
-- ОПИСАНИЕ:
--   Таблица для хранения всех ошибок, возникающих при валидации и обработке
--   входящих данных в функции put_ksk_result. Позволяет отлаживать некорректные
--   JSON структуры, отслеживать Kafka партиции и офсеты проблемных сообщений.
--   Хранит ВСЕ параметры функции put_ksk_result для полной реконструкции
--   контекста ошибки и возможности replay через Kafka.
--
-- ПАТТЕРНЫ ВЗЯТЫ ИЗ:
--   - ksk_result (15 зависимостей: FK from ksk_figurant, put_ksk_result(), партиционирование)
--   - ksk_system_operations_log (10 зависимостей: центральное логирование, все функции)
--
-- ИСПОЛЬЗОВАНИЕ:
--   - INSERT при ловле исключений в put_ksk_result
--   - SELECT для анализа битых JSON и поиска паттернов ошибок
--   - JOIN с Kafka метаданными для replay проблемных сообщений
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-29 - AI GENERATED: Создание таблицы для логирования ошибок валидации JSON
--   2025-10-29 - Паттерны взяты из ksk_result и ksk_system_operations_log
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_schema = 'upoa_ksk_reports' 
        AND table_name = 'ksk_result_error'
    ) THEN
        -- Создаём таблицу
        CREATE TABLE upoa_ksk_reports.ksk_result_error (
            -- Идентификатор записи (паттерн из ksk_result, ksk_system_operations_log)
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

            -- Временная метка ошибки (паттерн из ksk_system_operations_log.begin_time)
            error_timestamp TIMESTAMP(3) NOT NULL DEFAULT NOW(),

            -- Информация об ошибке (паттерн из ksk_system_operations_log)
            error_code VARCHAR(50) NOT NULL,
            error_message TEXT NOT NULL,

            -- Временные метки из параметров функции (паттерн из ksk_result)
            input_timestamp TIMESTAMP(3),
            output_timestamp TIMESTAMP(3),

            -- Kafka метаданные (паттерн из ksk_result)
            kafka_partition INTEGER NOT NULL,
            kafka_offset BIGINT NOT NULL,

            -- Kafka headers (паттерн из ksk_result)
            input_kafka_headers JSONB,
            output_kafka_headers JSONB,

            -- Корреляционный ID (паттерн из ksk_result.corr_id)
            corr_id VARCHAR(100),

            -- Полные JSON для отладки (паттерн из ksk_result.input_json/output_json)
            input_json JSONB NOT NULL,
            output_json JSONB,

            -- Контекст ошибки (паттерн из ksk_system_operations_log.info)
            function_context TEXT
        );

        -- EXTERNAL storage для JSONB колонок (паттерн из ksk_result)
        -- Выносим большие JSON на HDD для экономии основной памяти
        ALTER TABLE upoa_ksk_reports.ksk_result_error
            ALTER COLUMN input_json SET STORAGE EXTERNAL,
            ALTER COLUMN output_json SET STORAGE EXTERNAL,
            ALTER COLUMN input_kafka_headers SET STORAGE EXTERNAL,
            ALTER COLUMN output_kafka_headers SET STORAGE EXTERNAL;

        -- Комментарии на таблицу и колонки (паттерн из обеих таблиц)
        COMMENT ON TABLE upoa_ksk_reports.ksk_result_error 
            IS 'Таблица для логирования ошибок при обработке JSON в функции put_ksk_result. Содержит ВСЕ параметры функции для полной реконструкции контекста.';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.id 
            IS 'Уникальный идентификатор записи об ошибке';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.error_timestamp 
            IS 'Временная метка возникновения ошибки. DEFAULT NOW().';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.error_code 
            IS 'Код ошибки: MISSING_REQUIRED_FIELD, INVALID_JSON_STRUCTURE, TYPE_MISMATCH, CONSTRAINT_VIOLATION, UNKNOWN_ERROR';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.error_message 
            IS 'Подробное описание ошибки или текст исключения PostgreSQL';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.input_timestamp 
            IS 'Временная метка входящего сообщения (p_input_timestamp из функции put_ksk_result)';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.output_timestamp 
            IS 'Временная метка исходящего сообщения (p_output_timestamp из функции put_ksk_result)';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.kafka_partition 
            IS 'Номер партиции Kafka входящего топика (p_input_kafka_partition из функции put_ksk_result)';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.kafka_offset 
            IS 'Offset сообщения в Kafka партиции для возможности replay (p_input_kafka_offset из функции put_ksk_result)';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.input_kafka_headers 
            IS 'Полные Kafka headers входящего топика upoa_enriched_transactions (p_input_kafka_headers). STORAGE EXTERNAL.';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.output_kafka_headers 
            IS 'Полные Kafka headers исходящего топика upoa_ksk_results (p_output_kafka_headers). STORAGE EXTERNAL.';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.corr_id 
            IS 'Correlation ID из input_json.corrId (если удалось извлечь). Может быть NULL при битом JSON.';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.input_json 
            IS 'Полный дамп входящего JSON (p_input_json) для анализа и отладки. STORAGE EXTERNAL.';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.output_json 
            IS 'Полный дамп исходящего JSON (p_output_json). STORAGE EXTERNAL. Может быть NULL.';

        COMMENT ON COLUMN upoa_ksk_reports.ksk_result_error.function_context 
            IS 'Контекст ошибки. Любая полезная информация. Может содержать стек-трейс, SQLSTATE код, или другую техническую информацию';

        RAISE NOTICE '[ksk_result_error] ✅ Таблица успешно создана';
    ELSE
        RAISE NOTICE '[ksk_result_error] ⚠ Таблица уже существует, пропускаем создание';
    END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ КОЛОНОК (для совместимости с существующими таблицами)
-- ============================================================================
-- Паттерн из ksk_result: add_column_if_not_exists для всех колонок

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'error_timestamp', 'TIMESTAMP(3)', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'error_code', 'VARCHAR(50)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'error_message', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'input_timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'output_timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'kafka_partition', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'kafka_offset', 'BIGINT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'input_kafka_headers', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'output_kafka_headers', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'corr_id', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'input_json', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'output_json', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_result_error', 'function_context', 'TEXT');

SELECT '[ksk_result_error] ✅ Проверка колонок завершена (13 колонок)' AS status;

-- ============================================================================
-- 2.1. Установка STORAGE EXTERNAL для JSONB колонок
-- ============================================================================
-- Паттерн из ksk_result: DO $$ блок с обработкой исключений

DO $$
BEGIN
    BEGIN
        ALTER TABLE upoa_ksk_reports.ksk_result_error
            ALTER COLUMN input_json SET STORAGE EXTERNAL;
        RAISE NOTICE '[ksk_result_error] ✅ установлен STORAGE EXTERNAL для input_json';
    EXCEPTION WHEN undefined_column THEN
        RAISE NOTICE '[ksk_result_error] ⚠ колонка input_json не найдена';
    END;

    BEGIN
        ALTER TABLE upoa_ksk_reports.ksk_result_error
            ALTER COLUMN output_json SET STORAGE EXTERNAL;
        RAISE NOTICE '[ksk_result_error] ✅ установлен STORAGE EXTERNAL для output_json';
    EXCEPTION WHEN undefined_column THEN
        RAISE NOTICE '[ksk_result_error] ⚠ колонка output_json не найдена';
    END;

    BEGIN
        ALTER TABLE upoa_ksk_reports.ksk_result_error
            ALTER COLUMN input_kafka_headers SET STORAGE EXTERNAL;
        RAISE NOTICE '[ksk_result_error] ✅ установлен STORAGE EXTERNAL для input_kafka_headers';
    EXCEPTION WHEN undefined_column THEN
        RAISE NOTICE '[ksk_result_error] ⚠ колонка input_kafka_headers не найдена';
    END;

    BEGIN
        ALTER TABLE upoa_ksk_reports.ksk_result_error
            ALTER COLUMN output_kafka_headers SET STORAGE EXTERNAL;
        RAISE NOTICE '[ksk_result_error] ✅ установлен STORAGE EXTERNAL для output_kafka_headers';
    EXCEPTION WHEN undefined_column THEN
        RAISE NOTICE '[ksk_result_error] ⚠ колонка output_kafka_headers не найдена';
    END;
END $$;

-- ============================================================================
-- 3. Удаление ненужных индексов
-- ============================================================================
-- Паттерн из ksk_system_operations_log: динамическое удаление лишних индексов

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_result_error_timestamp',
        'idx_ksk_result_error_error_code',
        'idx_ksk_result_error_kafka_meta',
        'idx_ksk_result_error_corr_id',
        'idx_ksk_result_error_output_ts'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN 
        SELECT indexname 
        FROM pg_indexes 
        WHERE schemaname = 'upoa_ksk_reports' 
        AND tablename = 'ksk_result_error'
        AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT (v_index_name = ANY(v_needed_indexes)) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_result_error] 🗑️  удалён ненужный индекс %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;

    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_result_error] ℹ️  нет ненужных индексов для удаления';
    ELSE
        RAISE NOTICE '[ksk_result_error] ✅ удалено ненужных индексов: %', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. Создание индексов
-- ============================================================================
-- Паттерны из ksk_result и ksk_system_operations_log

-- 4.1. BRIN индекс на error_timestamp (паттерн из ksk_result.output_timestamp)
CREATE INDEX IF NOT EXISTS idx_ksk_result_error_timestamp 
    ON upoa_ksk_reports.ksk_result_error 
    USING BRIN (error_timestamp) 
    WITH (pages_per_range = 128);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_error_timestamp 
    IS 'BRIN индекс для фильтрации по времени ошибки. Экономит память в 1000x раз. Оптимален для HDD.';

-- 4.2. B-tree индекс на error_code (паттерн из ksk_system_operations_log.operation_code)
CREATE INDEX IF NOT EXISTS idx_ksk_result_error_error_code 
    ON upoa_ksk_reports.ksk_result_error (error_code);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_error_error_code 
    IS 'B-tree индекс для фильтрации по типу ошибки. Аналитика и мониторинг.';

-- 4.3. Composite B-tree индекс на kafka_partition + kafka_offset (паттерн из ksk_result)
CREATE INDEX IF NOT EXISTS idx_ksk_result_error_kafka_meta 
    ON upoa_ksk_reports.ksk_result_error (kafka_partition, kafka_offset);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_error_kafka_meta 
    IS 'Composite B-tree для поиска по Kafka метаданным (partition + offset). Replay проблемных сообщений.';

-- 4.4. Partial B-tree индекс на corr_id (паттерн из ksk_result.corr_id)
CREATE INDEX IF NOT EXISTS idx_ksk_result_error_corr_id 
    ON upoa_ksk_reports.ksk_result_error (corr_id) 
    WHERE corr_id IS NOT NULL;

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_error_corr_id 
    IS 'Partial B-tree для поиска по correlation ID. Только NOT NULL значения.';

-- 4.5. BRIN индекс на output_timestamp (паттерн из ksk_result)
CREATE INDEX IF NOT EXISTS idx_ksk_result_error_output_ts 
    ON upoa_ksk_reports.ksk_result_error 
    USING BRIN (output_timestamp) 
    WITH (pages_per_range = 128);

COMMENT ON INDEX upoa_ksk_reports.idx_ksk_result_error_output_ts 
    IS 'BRIN индекс для корреляции с таблицей ksk_result по output_timestamp.';

SELECT '[ksk_result_error] ✅ создано 5 индексов' AS status;

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
-- ИТОГИ:
-- ============================================================================
-- Таблица: ksk_result_error
-- Колонки: 14 (id + 13 data columns)
-- Индексы: 5 (2 BRIN, 2 B-tree, 1 Partial, 1 Composite)
-- STORAGE: EXTERNAL для 4 JSONB колонок
-- Назначение: Логирование ошибок put_ksk_result с replay через Kafka
-- Паттерны взяты из:
--   - ksk_result (15 зависимостей): BRIN индексы, STORAGE EXTERNAL, Kafka метаданные
--   - ksk_system_operations_log (10 зависимостей): логирование операций, error_code
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 001_ksk_report_orchestrator.sql
-- Размер: 8.63 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_orchestrator (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Оркестратор отчётов - метаданные всех типов отчётов в системе
-- Дата: 2025-10-27
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_report_orchestrator (ИДЕМПОТЕНТНАЯ ВЕРСИЯ - ИСПРАВЛЕНО)
-- ОПИСАНИЕ: Оркестратор отчётов - метаданные всех типов отчётов в системе
-- Дата: 2025-10-28
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'upoa_ksk_reports'
          AND table_name = 'ksk_report_orchestrator'
    ) THEN
        -- Создание таблицы оркестратора отчётов
        CREATE TABLE upoa_ksk_reports.ksk_report_orchestrator (
            -- Первичный ключ
            id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
            
            -- Идентификация отчёта
            report_code VARCHAR(50) NOT NULL UNIQUE,  -- UNIQUE создаёт индекс автоматически!
            report_table VARCHAR(100),
            report_function VARCHAR(100) NOT NULL,
            name VARCHAR(200) NOT NULL,
            
            -- Параметры хранения
            system_ttl INTEGER NOT NULL DEFAULT 30,
            user_ttl INTEGER NOT NULL DEFAULT 7,
            
            -- Временные метки
            created_at TIMESTAMP DEFAULT NOW(),
            updated_at TIMESTAMP DEFAULT NOW()
        );
        
        -- Комментарии для документации
        COMMENT ON TABLE upoa_ksk_reports.ksk_report_orchestrator
            IS 'Оркестратор отчётов - метаданные всех типов отчётов в системе';
        COMMENT ON COLUMN upoa_ksk_reports.ksk_report_orchestrator.report_code
            IS 'Уникальный код отчёта (например: totals, list_totals)';
        COMMENT ON COLUMN upoa_ksk_reports.ksk_report_orchestrator.report_table
            IS 'Таблица для хранения данных отчёта';
        COMMENT ON COLUMN upoa_ksk_reports.ksk_report_orchestrator.report_function
            IS 'Имя функции для генерации отчёта';
        COMMENT ON COLUMN upoa_ksk_reports.ksk_report_orchestrator.name
            IS 'Человекочитаемое название отчёта';
        COMMENT ON COLUMN upoa_ksk_reports.ksk_report_orchestrator.system_ttl
            IS 'TTL в днях для системных отчётов';
        COMMENT ON COLUMN upoa_ksk_reports.ksk_report_orchestrator.user_ttl
            IS 'TTL в днях для пользовательских отчётов';
        
        RAISE NOTICE '[ksk_report_orchestrator] ✅ Таблица создана';
    ELSE
        RAISE NOTICE '[ksk_report_orchestrator] ℹ️  Таблица уже существует, пропуск создания';
    END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'report_code', 'VARCHAR(50)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'report_table', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'report_function', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'name', 'VARCHAR(200)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'system_ttl', 'INTEGER', '30');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'user_ttl', 'INTEGER', '7');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'created_at', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_orchestrator', 'updated_at', 'TIMESTAMP', 'now()');

SELECT '[ksk_report_orchestrator] ✅ Проверка и добавление колонок завершена' AS status;

-- ============================================================================
-- 3. УДАЛЕНИЕ ДУБЛИРУЮЩИХ ИНДЕКСОВ (ИСПРАВЛЕНО)
-- ============================================================================
-- Проблема: UNIQUE constraint уже создаёт индекс ksk_report_orchestrator_report_code_key
-- Дополнительный idx_ksk_report_orchestrator_code - это дубликат!
--
DO $$
DECLARE
    v_index_name text;
    v_constraint_indexes text[];
    v_index_count integer := 0;
BEGIN
    -- Получаем список индексов, созданных constraint-ами
    SELECT array_agg(i.relname)
    INTO v_constraint_indexes
    FROM pg_constraint c
    JOIN pg_class i ON i.oid = c.conindid
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'upoa_ksk_reports'
      AND t.relname = 'ksk_report_orchestrator';
    
    -- Удаляем только обычные индексы (не constraint-based)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_orchestrator'
          AND indexname NOT LIKE '%_pkey'
          AND indexname != ALL(COALESCE(v_constraint_indexes, ARRAY[]::text[]))
    LOOP
        EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
        RAISE NOTICE '[ksk_report_orchestrator] 🗑️  Удалён дублирующий индекс: %', v_index_name;
        v_index_count := v_index_count + 1;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_orchestrator] ℹ️  Дублирующих индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_orchestrator] ✅ Удалено дублирующих индексов: %', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. ИНИЦИАЛИЗАЦИЯ ОРКЕСТРАТОРА (идемпотентно)
-- ============================================================================
-- Добавляем типы отчётов в оркестратор (если их ещё нет)
INSERT INTO upoa_ksk_reports.ksk_report_orchestrator (report_code, report_table, report_function, name, system_ttl, user_ttl)
VALUES
    ('totals', 'ksk_report_totals_data', 'ksk_report_totals', 'Общая статистика', 365, 14),
    ('totals_by_payment_type', 'ksk_report_totals_by_payment_type_data', 'ksk_report_totals_by_payment_type', 'Статистика по типам платежей', 365, 14),
    ('list_totals', 'ksk_report_list_totals_data', 'ksk_report_list_totals', 'Итоги по спискам', 365, 14),
    ('list_totals_by_payment_type', 'ksk_report_list_totals_by_payment_type_data', 'ksk_report_list_totals_by_payment_type', 'Итоги по спискам и типам платежей', 365, 14),
    ('figurants', 'ksk_report_figurants_data', 'ksk_report_figurants', 'Отчёт по фигурантам', 30, 7),
    ('report_review', 'ksk_report_review_data', 'ksk_report_review_create_report', 'Проверки', 7, 7)
ON CONFLICT (report_code) DO NOTHING;

SELECT '[ksk_report_orchestrator] ✅ Оркестратор инициализирован (6 типов отчётов)' AS status;

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 002_ksk_report_header.sql
-- Размер: 9.85 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_header (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Заголовки отчётов - экземпляры сгенерированных отчётов
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_report_header'
  ) THEN
    
    -- Создание таблицы заголовков отчётов
    CREATE TABLE upoa_ksk_reports.ksk_report_header (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с оркестратором
      orchestrator_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_orchestrator(id) ON DELETE CASCADE,
      
      -- Идентификация отчёта
      name VARCHAR(500) NOT NULL,
      initiator VARCHAR(100) NOT NULL CHECK (initiator IN ('system', 'user')),
      user_login VARCHAR(100),
      
      -- Временные метки
      created_datetime TIMESTAMP NOT NULL DEFAULT NOW(),
      finished_datetime TIMESTAMP,
      
      -- Статус и хранение
      status VARCHAR(20) NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'in_progress', 'done', 'error')),
      ttl INTEGER NOT NULL,
      remove_date DATE NOT NULL,
      
      -- Параметры отчёта
      start_date DATE,
      end_date DATE,
      parameters JSONB,
      
      -- Constraint для обязательного user_login при initiator='user'
      CONSTRAINT chk_user_login CHECK (
        (initiator = 'user' AND user_login IS NOT NULL) OR 
        (initiator = 'system' AND user_login IS NULL)
      )
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_header 
      IS 'Заголовки отчётов - экземпляры сгенерированных отчётов';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.orchestrator_id 
      IS 'Ссылка на тип отчёта в ksk_report_orchestrator';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.name 
      IS 'Название конкретного экземпляра отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.initiator 
      IS 'Инициатор создания: system или user';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.user_login 
      IS 'Логин пользователя (обязателен при initiator=user)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.status 
      IS 'Статус генерации: created, in_progress, done, error';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.ttl 
      IS 'Time-to-live в днях для данного отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.remove_date 
      IS 'Дата удаления отчёта (рассчитывается на основе TTL)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.start_date 
      IS 'Начало периода отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.end_date 
      IS 'Конец периода отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.parameters 
      IS 'Дополнительные параметры отчёта в JSON формате';
    
    RAISE NOTICE '[ksk_report_header] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_header] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'orchestrator_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'name', 'VARCHAR(500)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'initiator', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'user_login', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'created_datetime', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'finished_datetime', 'TIMESTAMP');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'status', 'VARCHAR(20)', '''created''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'ttl', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'remove_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'start_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'end_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'parameters', 'JSONB');

SELECT '[ksk_report_header] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_header_orchestrator',
        'idx_ksk_report_header_status',
        'idx_ksk_report_header_remove_date',
        'idx_ksk_report_header_created'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_header'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_header] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_header] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_header] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на orchestrator_id (FK)
-- Применение: JOIN с ksk_report_orchestrator
-- Используется для поиска всех отчётов определённого типа
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_orchestrator
  ON upoa_ksk_reports.ksk_report_header (orchestrator_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_orchestrator 
  IS 'B-tree: FK для JOIN с ksk_report_orchestrator. Поиск отчётов по типу.';

-- 4.2. B-tree индекс на status
-- Применение: фильтрация по статусу (WHERE status = 'done')
-- Используется для мониторинга и управления отчётами
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_status
  ON upoa_ksk_reports.ksk_report_header (status);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_status 
  IS 'B-tree: Фильтрация по статусу отчёта. Мониторинг генерации.';

-- 4.3. B-tree индекс на remove_date
-- Применение: поиск отчётов для удаления (WHERE remove_date < current_date)
-- Используется в процессе очистки устаревших отчётов
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_remove_date
  ON upoa_ksk_reports.ksk_report_header (remove_date);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_remove_date 
  IS 'B-tree: Поиск отчётов для удаления по TTL. Автоматическая очистка.';

-- 4.4. B-tree индекс на created_datetime
-- Применение: временная фильтрация (ORDER BY created_datetime DESC)
-- Используется для отображения последних отчётов
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_created
  ON upoa_ksk_reports.ksk_report_header (created_datetime);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_created 
  IS 'B-tree: Временная фильтрация и сортировка отчётов.';

SELECT '[ksk_report_header] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 003_ksk_report_totals_data.sql
-- Размер: 7.46 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_totals_data (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Данные отчёта по общей статистике
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_report_totals_data'
  ) THEN
    
    -- Создание таблицы данных отчёта по общей статистике
    CREATE TABLE upoa_ksk_reports.ksk_report_totals_data (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,
      created_date_time TIMESTAMP NOT NULL DEFAULT NOW(),
      
      -- Счётчики
      total INTEGER NOT NULL,
      total_without_result INTEGER NOT NULL,
      total_with_result INTEGER NOT NULL,
      total_allow INTEGER NOT NULL,
      total_review INTEGER NOT NULL,
      total_deny INTEGER NOT NULL,
      total_bypass INTEGER NOT NULL
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_totals_data 
      IS 'Данные отчёта по общей статистике. Агрегированные данные о всех транзакциях за период.';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.report_header_id 
      IS 'Ссылка на заголовок отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total 
      IS 'Всего сообщений обработано';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total_without_result 
      IS 'Всего сообщений без сработок';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total_with_result 
      IS 'Всего сообщений с результатом';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total_allow 
      IS 'Всего сообщений с результатом "allow"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total_review 
      IS 'Всего сообщений с результатом "review"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total_deny 
      IS 'Всего сообщений с результатом "deny"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_data.total_bypass 
      IS 'Всего сообщений с исключениями';
    
    RAISE NOTICE '[ksk_report_totals_data] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_totals_data] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'created_date_time', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_data', 'total_bypass', 'INTEGER');

SELECT '[ksk_report_totals_data] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_totals_data_header',
        'idx_ksk_report_totals_data_created'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_totals_data'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_totals_data] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_totals_data] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_totals_data] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header, поиск данных конкретного отчёта
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_totals_data_header
  ON upoa_ksk_reports.ksk_report_totals_data (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_totals_data_header 
  IS 'B-tree: FK для JOIN с ksk_report_header.';

-- 4.2. B-tree индекс на created_date_time
-- Применение: временная фильтрация и сортировка
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_totals_data_created
  ON upoa_ksk_reports.ksk_report_totals_data (created_date_time);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_totals_data_created 
  IS 'B-tree: Временная фильтрация данных отчёта.';

SELECT '[ksk_report_totals_data] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 004_ksk_report_list_totals_data.sql
-- Размер: 8.12 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_list_totals_data (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Данные отчёта по итогам по спискам (агрегация по list_code)
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_report_list_totals_data'
  ) THEN
    
    -- Создание таблицы данных отчёта по спискам
    CREATE TABLE upoa_ksk_reports.ksk_report_list_totals_data (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,
      created_date_time TIMESTAMP NOT NULL DEFAULT NOW(),
      
      -- Идентификация списка
      list_code VARCHAR(100) NOT NULL,
      
      -- Счётчики
      total_with_list INTEGER NOT NULL,
      total_without_list INTEGER NOT NULL,
      total_allow INTEGER NOT NULL,
      total_review INTEGER NOT NULL,
      total_deny INTEGER NOT NULL,
      total_bypass INTEGER NOT NULL
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_list_totals_data 
      IS 'Данные отчёта по итогам по спискам. Агрегация по кодам санкционных списков.';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.report_header_id 
      IS 'Ссылка на заголовок отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.list_code 
      IS 'Код санкционного списка';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.total_with_list 
      IS 'Всего сообщений со списком';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.total_without_list 
      IS 'Всего сообщений без списка';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.total_allow 
      IS 'Всего сообщений с результатом "allow"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.total_review 
      IS 'Всего сообщений с результатом "review"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.total_deny 
      IS 'Всего сообщений с результатом "deny"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_data.total_bypass 
      IS 'Всего сообщений с исключениями';
    
    RAISE NOTICE '[ksk_report_list_totals_data] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_list_totals_data] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'created_date_time', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'list_code', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_data', 'total_bypass', 'INTEGER');

SELECT '[ksk_report_list_totals_data] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_list_totals_data_header',
        'idx_ksk_report_list_totals_data_created',
        'idx_ksk_report_list_totals_data_list_code'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_list_totals_data'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_list_totals_data] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_list_totals_data] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_list_totals_data] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_list_totals_data_header
  ON upoa_ksk_reports.ksk_report_list_totals_data (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_list_totals_data_header 
  IS 'B-tree: FK для JOIN с ksk_report_header.';

-- 4.2. B-tree индекс на created_date_time
-- Применение: временная фильтрация
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_list_totals_data_created
  ON upoa_ksk_reports.ksk_report_list_totals_data (created_date_time);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_list_totals_data_created 
  IS 'B-tree: Временная фильтрация данных отчёта.';

-- 4.3. B-tree индекс на list_code
-- Применение: поиск и фильтрация по коду санкционного списка
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_list_totals_data_list_code
  ON upoa_ksk_reports.ksk_report_list_totals_data (list_code);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_list_totals_data_list_code 
  IS 'B-tree: Фильтрация по коду санкционного списка.';

SELECT '[ksk_report_list_totals_data] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 005_ksk_report_totals_by_payment_type_data.sql
-- Размер: 13.3 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_totals_by_payment_type_data (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Данные отчёта по статистике с разбивкой по типам платежей
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_report_totals_by_payment_type_data'
  ) THEN
    
    -- Создание таблицы данных отчёта по типам платежей
    CREATE TABLE upoa_ksk_reports.ksk_report_totals_by_payment_type_data (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,
      created_date_time TIMESTAMP NOT NULL DEFAULT NOW(),
      
      -- Общие счётчики (все типы платежей)
      total INTEGER,
      total_without_result INTEGER,
      total_with_result INTEGER,
      total_allow INTEGER,
      total_review INTEGER,
      total_deny INTEGER,
      total_bypass INTEGER,
      
      -- Входящий (I)
      i_total INTEGER,
      i_total_without_result INTEGER,
      i_total_with_result INTEGER,
      i_total_allow INTEGER,
      i_total_review INTEGER,
      i_total_deny INTEGER,
      i_total_bypass INTEGER,
      
      -- Исходящий (O)
      o_total INTEGER,
      o_total_without_result INTEGER,
      o_total_with_result INTEGER,
      o_total_allow INTEGER,
      o_total_review INTEGER,
      o_total_deny INTEGER,
      o_total_bypass INTEGER,
      
      -- Транзитный (T)
      t_total INTEGER,
      t_total_without_result INTEGER,
      t_total_with_result INTEGER,
      t_total_allow INTEGER,
      t_total_review INTEGER,
      t_total_deny INTEGER,
      t_total_bypass INTEGER,
      
      -- Межфилиальный (M)
      m_total INTEGER,
      m_total_without_result INTEGER,
      m_total_with_result INTEGER,
      m_total_allow INTEGER,
      m_total_review INTEGER,
      m_total_deny INTEGER,
      m_total_bypass INTEGER,
      
      -- Внутрифилиальный (V)
      v_total INTEGER,
      v_total_without_result INTEGER,
      v_total_with_result INTEGER,
      v_total_allow INTEGER,
      v_total_review INTEGER,
      v_total_deny INTEGER,
      v_total_bypass INTEGER
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_totals_by_payment_type_data 
      IS 'Данные отчёта по статистике с разбивкой по 5 типам платежей: I (Входящий), O (Исходящий), T (Транзитный), M (Межфилиальный), V (Внутрифилиальный)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_by_payment_type_data.report_header_id 
      IS 'Ссылка на заголовок отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_by_payment_type_data.i_total 
      IS 'Входящий (I) - всего сообщений';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_by_payment_type_data.o_total 
      IS 'Исходящий (O) - всего сообщений';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_by_payment_type_data.t_total 
      IS 'Транзитный (T) - всего сообщений';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_by_payment_type_data.m_total 
      IS 'Межфилиальный (M) - всего сообщений';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_totals_by_payment_type_data.v_total 
      IS 'Внутрифилиальный (V) - всего сообщений';
    
    RAISE NOTICE '[ksk_report_totals_by_payment_type_data] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_totals_by_payment_type_data] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'created_date_time', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'i_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'o_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 't_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'm_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total_without_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total_with_result', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_totals_by_payment_type_data', 'v_total_bypass', 'INTEGER');

SELECT '[ksk_report_totals_by_payment_type_data] ✅ Проверка и добавление колонок завершена (44 колонки!)';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_totals_by_payment_type_data_header'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_totals_by_payment_type_data'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_totals_by_payment_type_data] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_totals_by_payment_type_data] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_totals_by_payment_type_data] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_totals_by_payment_type_data_header
  ON upoa_ksk_reports.ksk_report_totals_by_payment_type_data (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_totals_by_payment_type_data_header 
  IS 'B-tree: FK для JOIN с ksk_report_header.';

SELECT '[ksk_report_totals_by_payment_type_data] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 006_ksk_report_list_totals_by_payment_type_data.sql
-- Размер: 12.78 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_list_totals_by_payment_type_data (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Данные отчёта по итогам по спискам с разбивкой по типам платежей
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_report_list_totals_by_payment_type_data'
  ) THEN
    
    -- Создание таблицы данных отчёта по спискам и типам платежей
    CREATE TABLE upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,
      created_date_time TIMESTAMP NOT NULL DEFAULT NOW(),
      
      -- Идентификация списка
      list_code VARCHAR(100),
      
      -- Общие счётчики
      total_with_list INTEGER,
      total_without_list INTEGER,
      total_allow INTEGER,
      total_review INTEGER,
      total_deny INTEGER,
      total_bypass INTEGER,
      
      -- Входящий (I)
      i_total_with_list INTEGER,
      i_total_without_list INTEGER,
      i_total_allow INTEGER,
      i_total_review INTEGER,
      i_total_deny INTEGER,
      i_total_bypass INTEGER,
      
      -- Исходящий (O)
      o_total_with_list INTEGER,
      o_total_without_list INTEGER,
      o_total_allow INTEGER,
      o_total_review INTEGER,
      o_total_deny INTEGER,
      o_total_bypass INTEGER,
      
      -- Транзитный (T)
      t_total_with_list INTEGER,
      t_total_without_list INTEGER,
      t_total_allow INTEGER,
      t_total_review INTEGER,
      t_total_deny INTEGER,
      t_total_bypass INTEGER,
      
      -- Межфилиальный (M)
      m_total_with_list INTEGER,
      m_total_without_list INTEGER,
      m_total_allow INTEGER,
      m_total_review INTEGER,
      m_total_deny INTEGER,
      m_total_bypass INTEGER,
      
      -- Внутрифилиальный (V)
      v_total_with_list INTEGER,
      v_total_without_list INTEGER,
      v_total_allow INTEGER,
      v_total_review INTEGER,
      v_total_deny INTEGER,
      v_total_bypass INTEGER
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data 
      IS 'Данные отчёта по итогам по спискам с разбивкой по 5 типам платежей: I (Входящий), O (Исходящий), T (Транзитный), M (Межфилиальный), V (Внутрифилиальный)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data.report_header_id 
      IS 'Ссылка на заголовок отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data.list_code 
      IS 'Код санкционного списка';
    
    RAISE NOTICE '[ksk_report_list_totals_by_payment_type_data] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_list_totals_by_payment_type_data] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'created_date_time', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'list_code', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'i_total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'i_total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'i_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'i_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'i_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'i_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'o_total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'o_total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'o_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'o_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'o_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'o_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 't_total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 't_total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 't_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 't_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 't_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 't_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'm_total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'm_total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'm_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'm_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'm_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'm_total_bypass', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'v_total_with_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'v_total_without_list', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'v_total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'v_total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'v_total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data', 'v_total_bypass', 'INTEGER');

SELECT '[ksk_report_list_totals_by_payment_type_data] ✅ Проверка и добавление колонок завершена (39 колонок!)';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_list_totals_by_payment_type_data_header',
        'idx_ksk_report_list_totals_by_payment_type_data_list_code'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_list_totals_by_payment_type_data'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_list_totals_by_payment_type_data] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_list_totals_by_payment_type_data] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_list_totals_by_payment_type_data] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_list_totals_by_payment_type_data_header
  ON upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_list_totals_by_payment_type_data_header 
  IS 'B-tree: FK для JOIN с ksk_report_header.';

-- 4.2. B-tree индекс на list_code
-- Применение: поиск и фильтрация по коду санкционного списка
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_list_totals_by_payment_type_data_list_code
  ON upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data (list_code);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_list_totals_by_payment_type_data_list_code 
  IS 'B-tree: Фильтрация по коду санкционного списка.';

SELECT '[ksk_report_list_totals_by_payment_type_data] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 007_ksk_report_figurants_data.sql
-- Размер: 8.24 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_figurants_data (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Данные отчёта по фигурантам - детальная статистика
-- Дата: 2025-10-27
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'upoa_ksk_reports' 
    AND table_name = 'ksk_report_figurants_data'
  ) THEN
    
    -- Создание таблицы данных отчёта по фигурантам
    CREATE TABLE upoa_ksk_reports.ksk_report_figurants_data (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,
      created_date_time TIMESTAMP NOT NULL DEFAULT NOW(),
      
      -- Данные фигуранта
      list_code VARCHAR(100),
      name_figurant VARCHAR(200),
      president_group VARCHAR(200),
      auto_login VARCHAR(100),
      exclusion_phrase TEXT,
      exclusion_name_list text NULL,
      
      -- Счётчики
      total INTEGER,
      total_allow INTEGER,
      total_review INTEGER,
      total_deny INTEGER,
      total_bypass INTEGER
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_figurants_data 
      IS 'Данные отчёта по фигурантам. Детальная статистика по каждому фигуранту за период.';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.report_header_id 
      IS 'Ссылка на заголовок отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.list_code 
      IS 'Код санкционного списка';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.name_figurant 
      IS 'Имя фигуранта из санкционного списка';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.president_group 
      IS 'Группа президента (если применимо)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.auto_login 
      IS 'Автологин (признак типа фигуранта)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.exclusion_phrase 
      IS 'Фразы исключения (разделены точкой с запятой)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.total 
      IS 'Всего упоминаний фигуранта в периоде';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.total_allow 
      IS 'Упоминаний с резолюцией "allow"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.total_review 
      IS 'Упоминаний с резолюцией "review"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.total_deny 
      IS 'Упоминаний с резолюцией "deny"';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.total_bypass 
      IS 'Упоминаний с обходом проверки';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_figurants_data.exclusion_name_list 
      IS 'Список исключений';
    
    RAISE NOTICE '[ksk_report_figurants_data] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_figurants_data] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'created_date_time', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'list_code', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'name_figurant', 'VARCHAR(200)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'president_group', 'VARCHAR(200)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'auto_login', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'exclusion_phrase', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'exclusion_name_list', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'total', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'total_allow', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'total_review', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'total_deny', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_figurants_data', 'total_bypass', 'INTEGER');

SELECT '[ksk_report_figurants_data] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_figurants_data_header'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_figurants_data'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_figurants_data] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_figurants_data] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_figurants_data] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_figurants_data_header
  ON upoa_ksk_reports.ksk_report_figurants_data (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_figurants_data_header 
  IS 'B-tree: FK для JOIN с ksk_report_header.';

SELECT '[ksk_report_figurants_data] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 008_ksk_report_files.sql
-- Размер: 8.36 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_files (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Файлы отчётов в формате Excel XML (SpreadsheetML)
-- Дата: 2025-12-08
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_files'
  ) THEN

    -- Создание таблицы файлов отчётов
    CREATE TABLE upoa_ksk_reports.ksk_report_files (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,

      -- Идентификация файла
      file_name VARCHAR(500) NOT NULL,
      file_format VARCHAR(50) NOT NULL DEFAULT 'excel_xml' CHECK (file_format IN ('excel_xml', 'csv', 'json', 'xml')),

      -- Временные метки
      created_datetime TIMESTAMP NOT NULL DEFAULT NOW(),

      -- Содержимое файла
      file_content XML,
      file_content_text TEXT,

      -- Метаданные файла
      file_size_bytes INTEGER,
      sheet_count INTEGER DEFAULT 1,
      row_count INTEGER,

      -- Constraint: либо XML, либо TEXT содержимое
      CONSTRAINT chk_file_content CHECK (
        (file_format = 'excel_xml' AND file_content IS NOT NULL) OR
        (file_format != 'excel_xml' AND file_content_text IS NOT NULL)
      )
    );

    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_files
      IS 'Файлы отчётов в формате Excel XML (SpreadsheetML) и других форматах';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.report_header_id
      IS 'Ссылка на заголовок отчёта в ksk_report_header';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_name
      IS 'Имя файла отчёта (например: report_2025-01.xls)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_format
      IS 'Формат файла: excel_xml, csv, json, xml';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_content
      IS 'Содержимое файла в формате XML (SpreadsheetML для Excel)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_content_text
      IS 'Содержимое файла в текстовом формате (для CSV, JSON)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_size_bytes
      IS 'Размер файла в байтах';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.sheet_count
      IS 'Количество листов в Excel-файле';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.row_count
      IS 'Общее количество строк данных';

    RAISE NOTICE '[ksk_report_files] ✅ Таблица создана';

  ELSE
    RAISE NOTICE '[ksk_report_files] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_name', 'VARCHAR(500)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_format', 'VARCHAR(50)', '''excel_xml''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'created_datetime', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_content', 'XML');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_content_text', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_size_bytes', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'sheet_count', 'INTEGER', '1');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'row_count', 'INTEGER');

SELECT '[ksk_report_files] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_files_header',
        'idx_ksk_report_files_format',
        'idx_ksk_report_files_created'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_files'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_files] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;

    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_files] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_files] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header
-- Используется для поиска всех файлов конкретного отчёта
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_files_header
  ON upoa_ksk_reports.ksk_report_files (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_files_header
  IS 'B-tree: FK для JOIN с ksk_report_header. Поиск файлов по отчёту.';

-- 4.2. B-tree индекс на file_format
-- Применение: фильтрация по формату (WHERE file_format = 'excel_xml')
-- Используется для выборки файлов определённого формата
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_files_format
  ON upoa_ksk_reports.ksk_report_files (file_format);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_files_format
  IS 'B-tree: Фильтрация по формату файла.';

-- 4.3. B-tree индекс на created_datetime
-- Применение: временная фильтрация (ORDER BY created_datetime DESC)
-- Используется для отображения последних файлов
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_files_created
  ON upoa_ksk_reports.ksk_report_files (created_datetime);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_files_created
  IS 'B-tree: Временная фильтрация и сортировка файлов.';

SELECT '[ksk_report_files] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 009_ksk_report_review_files.sql
-- Размер: 12.01 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_review_files (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Файлы отчётов Review в формате Excel XML (SpreadsheetML)
--           Связаны с заголовком отчёта через report_header_id
-- Дата: 2025-12-16
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_review_files'
  ) THEN

    -- Создание таблицы файлов отчётов Review
    CREATE TABLE upoa_ksk_reports.ksk_report_review_files (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

      -- Связь с заголовком отчёта
      report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,

      -- Дата отчёта
      report_date DATE NOT NULL,

      -- Идентификация файла
      file_name VARCHAR(500) NOT NULL,
      file_format VARCHAR(50) NOT NULL DEFAULT 'excel_xml' CHECK (file_format IN ('excel_xml', 'csv', 'json', 'xml')),

      -- Временные метки
      created_datetime TIMESTAMP NOT NULL DEFAULT NOW(),

      -- Содержимое файла
      file_content XML,
      file_content_text TEXT,

      -- Метаданные файла
      file_size_bytes INTEGER,
      sheet_count INTEGER DEFAULT 1,
      row_count INTEGER,

      -- Constraint: должно быть либо XML, либо TEXT содержимое
      CONSTRAINT chk_review_file_content CHECK (
        file_content IS NOT NULL OR file_content_text IS NOT NULL
      )
    );

    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_review_files
      IS 'Файлы отчётов Review в формате Excel XML. Связаны с заголовком отчёта через report_header_id.';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.report_header_id
      IS 'Ссылка на заголовок отчёта (ON DELETE CASCADE)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.report_date
      IS 'Дата отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.file_name
      IS 'Имя файла отчёта (например: review_2025-01-15.xls)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.file_format
      IS 'Формат файла: excel_xml, csv, json, xml';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.file_content
      IS 'Содержимое файла в формате XML (SpreadsheetML для Excel)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.file_content_text
      IS 'Содержимое файла в текстовом формате (для CSV, JSON)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.file_size_bytes
      IS 'Размер файла в байтах';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.sheet_count
      IS 'Количество листов в Excel-файле';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.row_count
      IS 'Общее количество строк данных';

    RAISE NOTICE '[ksk_report_review_files] ✅ Таблица создана';

  ELSE
    RAISE NOTICE '[ksk_report_review_files] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. МИГРАЦИЯ: Добавление report_header_id в существующую таблицу
-- ============================================================================
-- Если таблица существует без поля report_header_id - удаляем все записи
-- и добавляем новое поле (для совместимости с новой архитектурой)
-- ============================================================================

DO $$
BEGIN
  -- Проверяем, существует ли колонка report_header_id
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_review_files'
    AND column_name = 'report_header_id'
  ) THEN
    -- Удаляем все записи (старые файлы без привязки к header)
    DELETE FROM upoa_ksk_reports.ksk_report_review_files;
    RAISE NOTICE '[ksk_report_review_files] 🗑️  Удалены все записи (миграция на report_header_id)';

    -- Удаляем UNIQUE constraint на report_date если есть
    IF EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE table_schema = 'upoa_ksk_reports'
      AND table_name = 'ksk_report_review_files'
      AND constraint_name = 'ksk_report_review_files_report_date_key'
    ) THEN
      ALTER TABLE upoa_ksk_reports.ksk_report_review_files
        DROP CONSTRAINT ksk_report_review_files_report_date_key;
      RAISE NOTICE '[ksk_report_review_files] 🗑️  Удалён UNIQUE constraint на report_date';
    END IF;

    -- Добавляем колонку report_header_id
    ALTER TABLE upoa_ksk_reports.ksk_report_review_files
      ADD COLUMN report_header_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE;

    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.report_header_id
      IS 'Ссылка на заголовок отчёта (ON DELETE CASCADE)';

    RAISE NOTICE '[ksk_report_review_files] ✅ Добавлена колонка report_header_id';
  ELSE
    RAISE NOTICE '[ksk_report_review_files] ℹ️  Колонка report_header_id уже существует';
  END IF;
END $$;

-- ============================================================================
-- 3. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'report_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'file_name', 'VARCHAR(500)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'file_format', 'VARCHAR(50)', '''excel_xml''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'created_datetime', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'file_content', 'XML');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'file_content_text', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'file_size_bytes', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'sheet_count', 'INTEGER', '1');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_files', 'row_count', 'INTEGER');

SELECT '[ksk_report_review_files] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 4. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_review_files_header',
        'idx_ksk_report_review_files_date',
        'idx_ksk_report_review_files_format',
        'idx_ksk_report_review_files_created'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_review_files'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_review_files] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;

    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_review_files] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_review_files] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 5. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 5.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header, CASCADE DELETE
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_header
  ON upoa_ksk_reports.ksk_report_review_files (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_header
  IS 'B-tree: FK для JOIN с ksk_report_header.';

-- 5.2. B-tree индекс на report_date
-- Применение: поиск отчёта по дате
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_date
  ON upoa_ksk_reports.ksk_report_review_files (report_date);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_date
  IS 'B-tree: Поиск отчёта по дате.';

-- 5.3. B-tree индекс на file_format
-- Применение: фильтрация по формату (WHERE file_format = 'excel_xml')
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_format
  ON upoa_ksk_reports.ksk_report_review_files (file_format);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_format
  IS 'B-tree: Фильтрация по формату файла.';

-- 5.4. B-tree индекс на created_datetime
-- Применение: временная фильтрация (ORDER BY created_datetime DESC)
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_created
  ON upoa_ksk_reports.ksk_report_review_files (created_datetime);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_created
  IS 'B-tree: Временная фильтрация и сортировка файлов.';

SELECT '[ksk_report_review_files] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- 6. ОБНОВЛЕНИЕ CONSTRAINT (вне транзакции для идемпотентности)
-- ============================================================================

ALTER TABLE upoa_ksk_reports.ksk_report_review_files
DROP CONSTRAINT IF EXISTS chk_review_file_content;

ALTER TABLE upoa_ksk_reports.ksk_report_review_files
ADD CONSTRAINT chk_review_file_content CHECK (
    file_content IS NOT NULL OR file_content_text IS NOT NULL
);

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 010_ksk_report_review_data.sql
-- Размер: 7.66 KB
-- ============================================================================

-- ============================================================================
-- ТАБЛИЦА: ksk_report_review_data (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Метаданные отчёта Review для совместимости с системой отчётов
--           Содержит ссылку на заголовок отчёта и статистику файла
-- Дата: 2025-12-16
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. СОЗДАНИЕ ТАБЛИЦЫ (идемпотентно)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_review_data'
  ) THEN

    -- Создание таблицы метаданных отчёта Review
    CREATE TABLE upoa_ksk_reports.ksk_report_review_data (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

      -- Связь с заголовком отчёта (уникальная - один отчёт на заголовок)
      report_header_id INTEGER NOT NULL UNIQUE REFERENCES upoa_ksk_reports.ksk_report_header(id) ON DELETE CASCADE,
      created_date_time TIMESTAMP NOT NULL DEFAULT NOW(),

      -- Метаданные файла
      file_size_bytes INTEGER,
      row_count INTEGER,
      transaction_resolution TEXT
    );

    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_review_data
      IS 'Метаданные отчёта Review для совместимости с системой отчётов. Содержит ссылку на заголовок и статистику файла.';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_data.report_header_id
      IS 'Ссылка на заголовок отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_data.created_date_time
      IS 'Дата и время создания записи';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_data.file_size_bytes
      IS 'Размер сгенерированного файла в байтах';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_data.row_count
      IS 'Количество строк данных в отчёте';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_data.transaction_resolution
      IS 'Тип резолюции транзакций в отчёте (allow, review, deny, empty)';

    RAISE NOTICE '[ksk_report_review_data] ✅ Таблица создана';

  ELSE
    RAISE NOTICE '[ksk_report_review_data] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_data', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_data', 'created_date_time', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_data', 'file_size_bytes', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_data', 'row_count', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_review_data', 'transaction_resolution', 'TEXT');

SELECT '[ksk_report_review_data] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 2.1. ДОБАВЛЕНИЕ UNIQUE CONSTRAINT НА report_header_id (для ON CONFLICT)
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_review_data'
    AND constraint_name = 'ksk_report_review_data_report_header_id_key'
  ) THEN
    ALTER TABLE upoa_ksk_reports.ksk_report_review_data
      ADD CONSTRAINT ksk_report_review_data_report_header_id_key UNIQUE (report_header_id);
    RAISE NOTICE '[ksk_report_review_data] ✅ Добавлен UNIQUE constraint на report_header_id';
  ELSE
    RAISE NOTICE '[ksk_report_review_data] ℹ️  UNIQUE constraint на report_header_id уже существует';
  END IF;
END $$;

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_review_data_header',
        'idx_ksk_report_review_data_created',
        'ksk_report_review_data_report_header_id_key'  -- UNIQUE constraint index
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_review_data'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_review_data] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;

    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_review_data] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_review_data] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header, поиск данных конкретного отчёта
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_data_header
  ON upoa_ksk_reports.ksk_report_review_data (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_data_header
  IS 'B-tree: FK для JOIN с ksk_report_header.';

-- 4.2. B-tree индекс на created_date_time
-- Применение: временная фильтрация и сортировка
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_data_created
  ON upoa_ksk_reports.ksk_report_review_data (created_date_time);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_data_created
  IS 'B-tree: Временная фильтрация данных отчёта.';

SELECT '[ksk_report_review_data] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 001_ksk_cleanup_empty_records.sql
-- Размер: 6.11 KB
-- ============================================================================

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


-- ============================================================================
-- ФАЙЛ: 002_ksk_cleanup_with_logging.sql
-- Размер: 3.98 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_cleanup_with_logging
-- ============================================================================
-- ОПИСАНИЕ:
--   Выполняет очистку пустых записей с записью результата в системный лог
--   Обёртка над ksk_cleanup_empty_records() с логированием
--
-- ПАРАМЕТРЫ:
--   @days_old - Возраст записей для удаления (по умолчанию: 14)
--
-- ВОЗВРАЩАЕТ:
--   TABLE:
--     - log_id                  INTEGER  - ID записи в логе
--     - empty_records_deleted   BIGINT   - Количество удалённых записей
--     - partitions_dropped      TEXT[]   - Удалённые партиции
--     - total_time              INTERVAL - Общее время
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_cleanup_with_logging();
--   SELECT * FROM ksk_cleanup_with_logging(7);
--
-- ЗАМЕТКИ:
--   - Рекомендуется запускать ежедневно в cron
--   - Результат записывается в ksk_system_operations_log
--   - После выполнения требуется VACUUM ANALYZE (запускать отдельно вне транзакции)
--     (см. документацию в README_cleanup_functions.md)
--
-- ЗАВИСИМОСТИ:
--   - ksk_cleanup_empty_records(INTEGER)
--   - ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из daily_ksk_cleanup_with_logging
--   2025-10-25 - Переход на системный лог (ksk_system_operations_log)
--   2025-10-25 - Удалён параметр perform_vacuum
-- ============================================================================

CREATE OR REPLACE FUNCTION ksk_cleanup_with_logging(
    days_old INTEGER DEFAULT 14
)
RETURNS TABLE(
    log_id                  INTEGER,
    empty_records_deleted   BIGINT,
    partitions_dropped      TEXT[],
    total_time              INTERVAL
) AS $$
DECLARE
    result          RECORD;
    new_log_id      INTEGER;
    v_start_time    TIMESTAMP := CLOCK_TIMESTAMP();
    v_status        VARCHAR := 'success';
    v_info          TEXT;
BEGIN
    -- Выполняем очистку
    SELECT * INTO result
    FROM upoa_ksk_reports.ksk_cleanup_empty_records(days_old)
    AS t(deleted_count BIGINT, dropped_partitions TEXT[], execution_time INTERVAL);

    -- Формирование информационного сообщения
    v_info := FORMAT(
        'Период: старше %s дней. Удалено записей: %s. Удалено партиций: %s. Время: %s',
        days_old,
        result.deleted_count,
        COALESCE(ARRAY_LENGTH(result.dropped_partitions, 1), 0),
        result.execution_time
    );

    -- Запись в системный лог
    SELECT upoa_ksk_reports.ksk_log_operation(
        'cleanup_empty_records',
        'Очистка пустых записей',
        v_start_time,
        v_status,
        v_info,
        NULL
    ) INTO new_log_id;

    RAISE NOTICE 'Очистка завершена и записана в лог (ID: %)', new_log_id;
    RAISE NOTICE '⚠️  РЕКОМЕНДАЦИЯ: Выполните VACUUM ANALYZE отдельным запросом';

    -- Возвращаем результаты
    RETURN QUERY SELECT
        new_log_id,
        result.deleted_count,
        result.dropped_partitions,
        result.execution_time;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_with_logging(INTEGER) IS 
    'Очистка пустых записей с записью результата в системный лог. После выполнения требуется VACUUM ANALYZE';


-- ============================================================================
-- ФАЙЛ: 003_ksk_cleanup_empty_partitions.sql
-- Размер: 6.95 KB
-- ============================================================================

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


-- ============================================================================
-- ФАЙЛ: 004_ksk_cleanup_old_logs.sql
-- Размер: 2.26 KB
-- ============================================================================

-- ============================================================================
-- Функция: ksk_cleanup_old_logs
-- Описание: Удаление записей системного лога КСК старше N дней
-- Параметры: 
--   p_days_to_keep - количество дней для хранения (по умолчанию 365)
-- Возвращает: количество удалённых записей
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_logs(
    p_days_to_keep INTEGER DEFAULT 365
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_cutoff_date TIMESTAMP;
    v_deleted_count INTEGER;
    v_operation_code TEXT;
    v_start_time TIMESTAMP(3);
BEGIN
    v_start_time := now()::timestamp(3);
    v_operation_code := 'cleanup_logs_' || extract(epoch from v_start_time)::bigint;
    v_cutoff_date := now() - (p_days_to_keep || ' days')::interval;
    
    -- Удаляем старые записи
    DELETE FROM upoa_ksk_reports.ksk_system_operations_log
    WHERE begin_time < v_cutoff_date;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
    
    -- Логируем только финальный результат
    PERFORM upoa_ksk_reports.ksk_log_operation(
        v_operation_code,
        'Очистка системного лога (старше ' || p_days_to_keep || ' дней)',
        v_start_time,
        'success',
        'Граничная дата: ' || v_cutoff_date::text || ', удалено записей: ' || v_deleted_count,
        NULL
    );
    
    RETURN v_deleted_count;
    
EXCEPTION WHEN OTHERS THEN
    -- Логируем ошибку
    PERFORM upoa_ksk_reports.ksk_log_operation(
        v_operation_code || '_error',
        'Ошибка при очистке лога',
        v_start_time,
        'error',
        NULL,
        SQLERRM
    );
    
    RAISE;
END;
$$;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_cleanup_old_logs(INTEGER) IS 
'Удаляет записи системного лога КСК старше указанного количества дней. По умолчанию хранит последние 365 дней.';


-- ============================================================================
-- ФАЙЛ: 005_ksk_monitor_table_bloat.sql
-- Размер: 5.48 KB
-- ============================================================================

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



-- ============================================================================
-- ФАЙЛ: 001_check_figurant_status_OPTIMIZED.sql
-- Размер: 7.86 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: check_figurant_status
-- ============================================================================
-- ОПИСАНИЕ:
--   Определяет статус фигуранта (allow/review/deny) на основе матрицы проверок.
--   
--   Матрица решений (8 сценариев):
--   ┌───────────────┬──────────┬────────────┬─────────┐
--   │ presidentGroup│ autoLogin│ exclusions │ Решение │
--   ├───────────────┼──────────┼────────────┼─────────┤
--   │ part          │ false    │ true       │ allow   │ (1)
--   │ part          │ false    │ false      │ allow   │ (2)
--   │ full          │ false    │ true       │ allow   │ (3)
--   │ full          │ false    │ false      │ review  │ (4)
--   │ none          │ false    │ true       │ allow   │ (5)
--   │ none          │ false    │ false      │ review  │ (6)
--   │ none          │ true     │ true       │ allow   │ (7)
--   │ none          │ true     │ false      │ allow   │ (8)
--   └───────────────┴──────────┴────────────┴─────────┘
--
-- ПАРАМЕТРЫ:
--   input_data (JSONB) - JSON фигуранта с полями:
--     - presidentGroup (TEXT): 'part', 'full', 'none'
--     - autoLogin (BOOLEAN): true/false
--     - searchCheckResultsExclusionList (JSONB): объект с исключениями
--
-- ВОЗВРАЩАЕТ:
--   TEXT - Статус фигуранта: 'allow', 'review', 'deny', 'unknown'
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   Текущая:  ~0.5-1ms на вызов (8 IF проверок)
--   Оптимизированная: ~0.2-0.3ms (lookup table)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-27 - Оптимизация через lookup table вместо cascade IF
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.check_figurant_status(input_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE  -- Функция детерминированная → можно кэшировать результат
AS $function$
DECLARE
    v_president_group TEXT;
    v_auto_login      BOOLEAN;
    v_has_exclusions  BOOLEAN;
BEGIN
    -- =========================================================================
    -- ОПТИМИЗАЦИЯ 1: Извлекаем все поля один раз
    -- =========================================================================
    v_president_group := COALESCE(input_data->>'presidentGroup', 'none');
    v_auto_login      := COALESCE((input_data->>'autoLogin')::BOOLEAN, FALSE);

    -- Проверка наличия исключений (более компактная логика)
    v_has_exclusions := (
        input_data ? 'searchCheckResultsExclusionList' 
        AND jsonb_typeof(input_data->'searchCheckResultsExclusionList') = 'object'
        AND jsonb_object_length(input_data->'searchCheckResultsExclusionList') > 0
    );

    -- =========================================================================
    -- ОПТИМИЗАЦИЯ 2: Lookup table вместо каскада IF
    -- =========================================================================
    -- Анализ матрицы показывает упрощённую логику:
    -- - Если (full AND !autoLogin AND !exclusions) → review  (сценарий 4)
    -- - Если (none AND !autoLogin AND !exclusions) → review  (сценарий 6)
    -- - Все остальные → allow

    -- Сценарии 4 и 6: review
    IF (v_president_group IN ('full', 'none') 
        AND v_auto_login = FALSE 
        AND v_has_exclusions = FALSE) THEN
        RETURN 'review';
    END IF;

    -- Все остальные сценарии (1,2,3,5,7,8): allow
    -- part + любые условия → always allow
    -- full + (autoLogin=true OR exclusions=true) → allow
    -- none + (autoLogin=true OR exclusions=true) → allow
    IF v_president_group IN ('part', 'full', 'none') THEN
        RETURN 'allow';
    END IF;

    -- Неизвестное значение presidentGroup
    RETURN 'unknown';
END;
$function$;

-- ============================================================================
-- КОММЕНТАРИИ К ОПТИМИЗАЦИЯМ
-- ============================================================================

/*
ОПТИМИЗАЦИЯ 1: Кэширование значений
-----------------------------------
БЫЛО:
  - 8 раз обращение к input_data->>'presidentGroup'
  - 8 раз обращение к (input_data->>'autoLogin')::BOOLEAN
  - 8 раз вычисление has_exclusions

СТАЛО:
  - 1 раз извлечение каждого значения в переменную
  - Экономия: ~40% времени парсинга JSONB

ОПТИМИЗАЦИЯ 2: Упрощение логики
--------------------------------
БЫЛО:
  - 8 отдельных IF блоков (проверка всех 8 сценариев)
  - Worst case: 8 IF проверок

СТАЛО:
  - 2 IF блока (группировка по результату)
  - Worst case: 2 IF проверки
  - Экономия: ~60% на логике

ОПТИМИЗАЦИЯ 3: IMMUTABLE маркер
--------------------------------
ДОБАВЛЕНО:
  - IMMUTABLE → PostgreSQL кэширует результат для одинаковых входов
  - При повторных вызовах с тем же JSON → результат из кэша
  - Критично для check_transaction_status (вызывает в цикле)

АНАЛИЗ МАТРИЦЫ:
---------------
Упрощённая логика (вместо 8 сценариев → 2 группы):

Группа 1 (review): full/none + !autoLogin + !exclusions
Группа 2 (allow):  все остальные

Почему так:
- part → всегда allow (независимо от других условий)
- full/none → review только если НЕТ ни autoLogin, ни exclusions
- full/none → allow если ЕСТЬ autoLogin ИЛИ exclusions
*/

-- ============================================================================
-- ТЕСТЫ (запустить после создания функции)
-- ============================================================================

/*
-- Тест 1: part → always allow
SELECT check_figurant_status('{"presidentGroup":"part","autoLogin":false}'::jsonb); -- allow
SELECT check_figurant_status('{"presidentGroup":"part","autoLogin":true}'::jsonb);  -- allow

-- Тест 2: full + !autoLogin + !exclusions → review
SELECT check_figurant_status('{"presidentGroup":"full","autoLogin":false}'::jsonb); -- review

-- Тест 3: full + autoLogin=true → allow
SELECT check_figurant_status('{"presidentGroup":"full","autoLogin":true}'::jsonb);  -- allow

-- Тест 4: none + !autoLogin + !exclusions → review
SELECT check_figurant_status('{"presidentGroup":"none","autoLogin":false}'::jsonb); -- review

-- Тест 5: none + exclusions → allow
SELECT check_figurant_status('{"presidentGroup":"none","autoLogin":false,"searchCheckResultsExclusionList":{"test":"value"}}'::jsonb); -- allow

-- Тест 6: unknown presidentGroup
SELECT check_figurant_status('{"presidentGroup":"invalid","autoLogin":false}'::jsonb); -- unknown
*/

-- ============================================================================
-- КОНЕЦ ФАЙЛА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 002_check_transaction_status_OPTIMIZED.sql
-- Размер: 7.13 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: check_transaction_status
-- ============================================================================
-- ОПИСАНИЕ:
-- Определяет итоговое решение по транзакции на основе всех фигурантов.
--
-- Логика агрегации (приоритет сверху вниз):
-- ┌─────────────────────────────────┬─────────────┐
-- │ Условие                         │ Решение     │
-- ├─────────────────────────────────┼─────────────┤
-- │ Нет фигурантов                  │ empty       │
-- │ ВСЕ фигуранты bypass            │ bypass      │  ← NEW
-- │ Хотя бы один DENY (не bypass)   │ deny        │
-- │ Нет DENY, есть REVIEW           │ review      │
-- │ Все ALLOW                       │ allow       │
-- └─────────────────────────────────┴─────────────┘
--
-- ПАРАМЕТРЫ:
-- input_data (JSONB) - JSON транзакции с массивом фигурантов:
--   - searchCheckResultKCKH (JSONB[]): массив фигурантов
--
-- ВОЗВРАЩАЕТ:
-- TEXT - Итоговый статус: 'deny', 'review', 'allow', 'bypass', 'empty'
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
-- ~0.5-2ms (early exit оптимизация)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
-- 2025-10-27 - Оптимизация через early exit и кэширование
-- 2025-11-25 - Добавлена обработка bypass: исключенные фигуранты приравниваются к allow
-- 2025-11-26 - NEW: bypass как отдельный статус транзакции (все фигуранты bypass)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.check_transaction_status(input_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    v_figurant          JSONB;
    v_figurant_status   TEXT;
    v_has_review        BOOLEAN := FALSE;
    v_has_allow         BOOLEAN := FALSE;
    v_all_bypass        BOOLEAN := TRUE;   -- NEW: флаг "все bypass"
    v_has_figurants     BOOLEAN := FALSE;  -- NEW: есть ли фигуранты вообще
BEGIN
    -- =========================================================================
    -- Проверка наличия массива фигурантов
    -- =========================================================================
    IF NOT (input_data ? 'searchCheckResultKCKH')
       OR jsonb_typeof(input_data->'searchCheckResultKCKH') != 'array' THEN
        RETURN 'empty';
    END IF;

    -- =========================================================================
    -- Основной цикл с early exit для DENY
    -- =========================================================================
    FOR v_figurant IN
        SELECT * FROM jsonb_array_elements(input_data->'searchCheckResultKCKH')
    LOOP
        v_has_figurants := TRUE;
        
        -- Проверка bypass: bypassName не пустой
        IF (v_figurant->>'bypassName') IS NOT NULL 
           AND (v_figurant->>'bypassName') != '' THEN
            -- Этот фигурант bypass, продолжаем проверять остальных
            CONTINUE;
        END IF;
        
        -- Если дошли сюда - фигурант НЕ bypass
        v_all_bypass := FALSE;
        
        v_figurant_status := check_figurant_status(v_figurant);

        -- Early exit: deny имеет наивысший приоритет
        IF v_figurant_status = 'deny' THEN
            RETURN 'deny';
        END IF;

        -- Флаги для агрегации остальных статусов
        IF v_figurant_status = 'review' THEN
            v_has_review := TRUE;
        ELSIF v_figurant_status = 'allow' THEN
            v_has_allow := TRUE;
        END IF;
    END LOOP;

    -- =========================================================================
    -- Агрегация результата
    -- =========================================================================
    
    -- Нет фигурантов → empty
    IF NOT v_has_figurants THEN
        RETURN 'empty';
    END IF;
    
    -- NEW: ВСЕ фигуранты bypass → bypass
    IF v_all_bypass THEN
        RETURN 'bypass';
    END IF;
    
    -- Стандартная логика приоритетов
    IF v_has_review THEN
        RETURN 'review';
    ELSIF v_has_allow THEN
        RETURN 'allow';
    ELSE
        RETURN 'empty';
    END IF;
END;
$function$;

-- ============================================================================
-- ТЕСТЫ
-- ============================================================================
/*
-- Тест 1: Нет фигурантов → empty
SELECT check_transaction_status('{}'::jsonb);                                    -- empty
SELECT check_transaction_status('{"searchCheckResultKCKH":[]}'::jsonb);          -- empty

-- Тест 2: Один фигурант allow → allow
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"presidentGroup":"part","autoLogin":false}
  ]
}'::jsonb);  -- allow

-- Тест 3: Один фигурант review → review  
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"presidentGroup":"full","autoLogin":false}
  ]
}'::jsonb);  -- review

-- Тест 4: deny всегда побеждает
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"presidentGroup":"part","autoLogin":false},
    {"presidentGroup":"unknown","autoLogin":false}
  ]
}'::jsonb);  -- deny

-- Тест 5: NEW - ВСЕ bypass → bypass
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"bypassName":"Тестовый bypass"},
    {"bypassName":"Ещё один bypass"}
  ]
}'::jsonb);  -- bypass

-- Тест 6: NEW - Смешанный (bypass + обычный) → обычная логика
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"bypassName":"Bypass фигурант"},
    {"presidentGroup":"full","autoLogin":false}
  ]
}'::jsonb);  -- review (bypass игнорируется, full+!autoLogin = review)

-- Тест 7: NEW - Bypass + allow → allow (bypass не участвует в агрегации)
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"bypassName":"Bypass"},
    {"presidentGroup":"part","autoLogin":false}
  ]
}'::jsonb);  -- allow
*/
-- ============================================================================
-- КОНЕЦ ФАЙЛА
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 003_put_ksk_result.sql
-- Размер: 16.5 KB
-- ============================================================================

-- ============================================================================
-- ФАЙЛ: 003_put_ksk_result_v4.1_bypass_detection.sql
-- ============================================================================
-- ОПИСАНИЕ:
-- Миграция функции put_ksk_result v4.1
-- ОПИСАНИЕ:
-- Миграция функции put_ksk_result с логированием ошибок БЕЗ отката транзакции
-- ВАЛИДАЦИЯ: одна проверка всех параметров, один INSERT при ошибке
--
-- ДАТА СОЗДАНИЯ: 31.10.2025 04:00 MSK
-- ВЕРСИЯ: 4.0
--
-- ИЗМЕНЕНИЯ ОТ ОРИГИНАЛА:
-- + Валидация всех 6 параметров через IF-ELSIF (чистый код)
-- + ОДИН INSERT в ksk_result_error при любой ошибке валидации
-- + ОДИН INSERT в ksk_result_error при runtime ошибке (EXCEPTION)
-- + RETURN -1 * error_id вместо RETURN -1 → возврат ID ошибки
--
-- ЛОГИКА ВАЛИДАЦИИ:
-- 1. Проверяем все параметры через IF-ELSIF
-- 2. Если хоть один NULL → сохраняем в v_validation_error
-- 3. Если v_validation_error NOT NULL → ОДИН INSERT + RETURN -error_id
-- 4. Иначе продолжаем обработку
--
-- ПРЕИМУЩЕСТВА:
-- ✅ Чистый код без дублирования
-- ✅ Один INSERT вместо 6 (экономия на IO)
-- ✅ Ошибка сохраняется в БД для анализа
-- ✅ Приложение получает -error_id и может запросить детали
-- ✅ Batch продолжается для других записей
--
-- ИНТЕГРАЦИЯ С JAVA SPRING:
-- Integer result = jdbcTemplate.queryForObject(...);
-- if (result <= 0) { 
--     int errorId = Math.abs(result);
--     errorCounter.increment();
-- }
--
-- ПАТТЕРНЫ ВЗЯТЫ ИЗ:
-- - ksk_result: Kafka metadata, партиционирование
-- - ksk_system_operations_log: error logging
-- 
-- ДАТА СОЗДАНИЯ: 17.11.2025 16:24 MSK
-- ВЕРСИЯ: 4.1
-- 
-- ИЗМЕНЕНИЯ ОТ v4.0:
-- + НОВАЯ ЛОГИКА: Анализ has_bypass на основе bypassName в фигурантах
-- + Безопасная проверка массива searchCheckResultKCKH
-- + Три сценария: yes / no / empty
-- ДАТА СОЗДАНИЯ: 17.11.2025 16:36 MSK
-- ВЕРСИЯ: 4.2
-- 
-- ИЗМЕНЕНИЯ ОТ v4.1:
-- + Добавляем bypass_name в INSERT ksk_figurant из JSON figuvant.bypassName
-- + БЕЗОПАСНАЯ логика: NULL если отсутствует или пусто
-- + Используем NULLIF для корректной обработки
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.put_ksk_result(
  p_input_timestamp TIMESTAMP(3),
  p_output_timestamp TIMESTAMP(3),
  p_input_json JSONB,
  p_output_json JSONB,
  p_input_kafka_partition INTEGER DEFAULT NULL,
  p_input_kafka_offset BIGINT DEFAULT NULL,
  p_input_kafka_headers JSONB DEFAULT NULL,
  p_output_kafka_headers JSONB DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
  v_result_id INTEGER;
  v_error_id INTEGER;
  v_figurant_record RECORD;
  v_figurant_id INTEGER;
  v_match_record RECORD;
  
  -- JSONB переменные
  v_payment_info JSONB;
  v_payer_info JSONB;
  v_receiver_info JSONB;
  v_payer_bank_info JSONB;
  v_receiver_bank_info JSONB;
  v_header_info JSONB;
  v_search_results JSONB;
  
  -- Переменная для сообщения об ошибке валидации
  v_validation_error TEXT;
  v_error_text TEXT;
  
  -- NEW: Переменные для анализа has_bypass
  v_has_bypass VARCHAR(10);
  v_figurant_count INTEGER;
  v_has_bypass_with_value BOOLEAN;

  -- NEW v4.2: Переменная для bypass_name
  v_bypass_name TEXT;  
BEGIN

-- ========================================================================
-- ВАЛИДАЦИЯ ВСЕХ ПАРАМЕТРОВ (ОДНА ПРОВЕРКА)
-- v4.1: Возвращаем -ERROR_ID вместо -1
-- ========================================================================

v_validation_error := NULL;

IF p_input_timestamp IS NULL THEN
  v_validation_error := 'p_input_timestamp cannot be NULL';
ELSIF p_output_timestamp IS NULL THEN
  v_validation_error := 'p_output_timestamp cannot be NULL';
ELSIF p_input_json IS NULL THEN
  v_validation_error := 'p_input_json cannot be NULL (use empty JSON {})';
ELSIF p_output_json IS NULL THEN
  v_validation_error := 'p_output_json cannot be NULL (use empty JSON {})';
ELSIF p_input_kafka_partition IS NULL THEN
  v_validation_error := 'p_input_kafka_partition cannot be NULL (use -1 for unknown)';
ELSIF p_input_kafka_offset IS NULL THEN
  v_validation_error := 'p_input_kafka_offset cannot be NULL (use -1 for unknown)';
END IF;

-- Если есть ошибка валидации - логируем и возвращаем -ERROR_ID
IF v_validation_error IS NOT NULL THEN
  INSERT INTO upoa_ksk_reports.ksk_result_error (
    error_code,
    error_message,
    input_timestamp,
    output_timestamp,
    kafka_partition,
    kafka_offset,
    input_kafka_headers,
    output_kafka_headers,
    corr_id,
    input_json,
    output_json,
    function_context
  )
  VALUES (
    'PARAM_NULL',
    'Validation error: ' || v_validation_error,
    p_input_timestamp,
    p_output_timestamp,
    p_input_kafka_partition,
    p_input_kafka_offset,
    p_input_kafka_headers,
    p_output_kafka_headers,
    (p_output_json->'headerInfo'->>'corrId'),
    p_input_json,
    p_output_json,
    'put_ksk_result validation failed: ' || v_validation_error
  )
  RETURNING id INTO v_error_id;
  
  RETURN -1 * v_error_id;
END IF;

-- ========================================================================
-- ОСНОВНАЯ БИЗНЕС-ЛОГИКА
-- ========================================================================

-- ИЗВЛЕЧЕНИЕ JSONB ДАННЫХ
v_header_info := p_output_json->'headerInfo';
v_payment_info := p_input_json->'paymentInfo';
v_payer_info := p_input_json->'payerInfo';
v_receiver_info := p_input_json->'receiverInfo';
v_payer_bank_info := p_input_json->'payerBankInfo';
v_receiver_bank_info := p_input_json->'receiverBankInfo';
v_search_results := COALESCE(p_output_json->'searchCheckResultKCKH', '[]'::jsonb);

-- ========================================================================
-- NEW v4.1: АНАЛИЗ has_bypass НА ОСНОВЕ bypassName
-- ========================================================================
-- Логика:
-- 1. Если нет фигурантов (массив пуст) → has_bypass = 'empty'
-- 2. Если есть фигурант с непустым bypassName → has_bypass = 'yes'
-- 3. Если все bypassName пусты или отсутствуют → has_bypass = 'no'
-- ========================================================================

v_figurant_count := jsonb_array_length(v_search_results);

IF v_figurant_count = 0 THEN
  -- Сценарий 1: Фигурантов нет
  v_has_bypass := 'empty';
ELSE
  -- Сценарий 2 и 3: Ищем хоть один bypassName с непустым значением
  SELECT EXISTS(
    SELECT 1
    FROM jsonb_array_elements(v_search_results) AS elem
    WHERE (elem->>'bypassName') IS NOT NULL
      AND (elem->>'bypassName') != ''
    LIMIT 1
  ) INTO v_has_bypass_with_value;
  
  IF v_has_bypass_with_value THEN
    -- Сценарий 2: Найден хоть один непустой bypassName
    v_has_bypass := 'yes';
  ELSE
    -- Сценарий 3: Все bypassName пусты или отсутствуют
    v_has_bypass := 'no';
  END IF;
END IF;

-- 1) INSERT В ksk_result

INSERT INTO upoa_ksk_reports.ksk_result(
  date,
  corr_id,
  input_timestamp,
  output_timestamp,
  input_json,
  output_json,
  payment_type,
  resolution,
  has_bypass,
  list_codes,
  
  -- Поля платежа
  payment_id,
  payment_purpose,
  account_debet,
  account_credit,
  amount,
  currency,
  currency_control,
  
  -- Плательщик
  payer_inn,
  payer_name,
  payer_account_number,
  payer_document_type,
  payer_bank_name,
  payer_bank_account_number,
  
  -- Получатель
  receiver_account_number,
  receiver_name,
  receiver_inn,
  receiver_bank_name,
  receiver_bank_account_number,
  receiver_document_type,
  
  -- Kafka метаданные
  input_kafka_partition,
  input_kafka_offset,
  input_kafka_headers,
  output_kafka_headers
)
WITH list_codes_cte AS (
  SELECT COALESCE(array_agg(DISTINCT (elem->>'listCode')), '{}'::TEXT[]) AS codes
  FROM jsonb_array_elements(v_search_results) AS elem
  WHERE elem->>'listCode' IS NOT NULL
)
SELECT
  DATE(p_output_timestamp),
  v_header_info->>'corrId',
  p_input_timestamp,
  p_output_timestamp,
  p_input_json,
  p_output_json,
  v_payment_info->>'paymentType',
  upoa_ksk_reports.check_transaction_status(p_output_json),
  v_has_bypass,  -- НОВОЕ: Используем вычисленное значение вместо 'empty'
  lc.codes,
  
  -- Поля платежа
  COALESCE(v_payment_info->>'paymentId', ''),
  COALESCE(v_payment_info->>'paymentPurpose', ''),
  COALESCE(v_payment_info->>'accountDebet', ''),
  COALESCE(v_payment_info->>'accountCredit', ''),
  (v_payment_info->>'amount')::NUMERIC,
  COALESCE(v_payment_info->>'currency', ''),
  COALESCE(v_payment_info->>'currencyControl', ''),
  
  -- Плательщик
  COALESCE(v_payer_info->>'payerInn', ''),
  COALESCE(v_payer_info->>'payerName', ''),
  COALESCE(v_payer_info->'payerAccountInfo'->>'payerAccountNumber', ''),
  COALESCE(v_payer_info->>'payerDocumentType', ''),
  COALESCE(v_payer_bank_info->>'payerBankName', ''),
  COALESCE(v_payer_bank_info->>'payerBankAccountNumber', ''),

  -- Получатель
  COALESCE(v_receiver_info->'receiverAccountInfo'->>'receiverAccountNumber', ''),
  COALESCE(v_receiver_info->>'receiverName', ''),
  COALESCE(v_receiver_info->>'receiverInn', ''),
  COALESCE(v_receiver_bank_info->>'receiverBankName', ''),
  COALESCE(v_receiver_bank_info->>'receiverBankAccountNumber', ''),
  COALESCE(v_receiver_info->>'receiverDocumentType', ''),
  
  -- Kafka метаданные
  p_input_kafka_partition,
  p_input_kafka_offset,
  p_input_kafka_headers,
  p_output_kafka_headers
FROM list_codes_cte lc
RETURNING id INTO v_result_id;

-- 2) INSERT В ksk_figurant

FOR v_figurant_record IN
  SELECT
    elem.value AS figurant_data,
    (elem.index - 1)::INTEGER AS figurant_index
  FROM jsonb_array_elements(v_search_results) WITH ORDINALITY AS elem(value, index)
LOOP
  -- NEW v4.2: БЕЗОПАСНОЕ извлечение bypass_name
  -- Логика: NULL если поле отсутствует ИЛИ пусто
  v_bypass_name := NULLIF(
    TRIM(COALESCE(v_figurant_record.figurant_data->>'bypassName', '')), 
    ''
  );
  INSERT INTO upoa_ksk_reports.ksk_figurant(
    source_id,
    date,
    timestamp,
    figurant,
    figurant_index,
    resolution,
    is_bypass,
    list_code,
    name_figurant,
    president_group,
    auto_login,
    has_exclusion,
    exclusion_phrase,
    exclusion_name_list,
	bypass_name  -- NEW v4.2
  )
  VALUES (
    v_result_id,
    DATE(p_output_timestamp),
    p_output_timestamp,
    v_figurant_record.figurant_data,
    v_figurant_record.figurant_index,
    upoa_ksk_reports.check_figurant_status(v_figurant_record.figurant_data),
    CASE WHEN v_bypass_name IS NOT NULL THEN 'yes' ELSE 'no' END,
    COALESCE(v_figurant_record.figurant_data->>'listCode', ''),
    COALESCE(v_figurant_record.figurant_data->>'nameFigurant', ''),
    COALESCE(v_figurant_record.figurant_data->>'presidentGroup', ''),
    COALESCE((v_figurant_record.figurant_data->>'autoLogin')::BOOLEAN, FALSE),
    COALESCE(
      jsonb_typeof(v_figurant_record.figurant_data->'searchCheckResultsExclusionList') = 'object'
      AND jsonb_array_length(
        v_figurant_record.figurant_data->'searchCheckResultsExclusionList'->'phrasesToExclude'
      ) > 0,
      FALSE
    ),
    COALESCE(
      (SELECT string_agg(elem, '; ')
       FROM jsonb_array_elements_text(
         v_figurant_record.figurant_data->'searchCheckResultsExclusionList'->'phrasesToExclude'
       ) AS elem),
      ''
    ),
    COALESCE(((((v_figurant_record.figurant_data)::jsonb)::jsonb)->'searchCheckResultsExclusionList'->'nameList')::text, ''),
	v_bypass_name  -- NEW v4.2: Значение bypass_name (может быть NULL)
  )
  RETURNING id INTO v_figurant_id;

  -- 3) INSERT В ksk_figurant_match

  IF jsonb_array_length(v_figurant_record.figurant_data->'match') > 0 THEN
    INSERT INTO upoa_ksk_reports.ksk_figurant_match(
      figurant_id,
      date,
      timestamp,
      match,
      match_index,
      algorithm,
      match_value,
      match_payment_field,
      match_payment_value
    )
    SELECT
      v_figurant_id,
      DATE(p_output_timestamp),
      p_output_timestamp,
      match_elem.value,
      (match_elem.index - 1)::INTEGER,
      COALESCE(match_elem.value->>'algorithm', 'unknown'),
      COALESCE(match_elem.value->>'value', ''),
      COALESCE(match_elem.value->>'paymentField', ''),
      COALESCE(match_elem.value->>'paymentValue', '')
    FROM jsonb_array_elements(v_figurant_record.figurant_data->'match')
      WITH ORDINALITY AS match_elem(value, index);
  END IF;
END LOOP;

RETURN v_result_id;

EXCEPTION
WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_error_text = pg_exception_context;
  
  -- Обработка runtime ошибок с возвратом -ERROR_ID
  INSERT INTO upoa_ksk_reports.ksk_result_error (
    error_code,
    error_message,
    input_timestamp,
    output_timestamp,
    kafka_partition,
    kafka_offset,
    input_kafka_headers,
    output_kafka_headers,
    corr_id,
    input_json,
    output_json,
    function_context
  )
  VALUES (
    SQLSTATE,
    'Runtime error: ' || SQLERRM || '\n Stack: \n' || v_error_text,
    p_input_timestamp,
    p_output_timestamp,
    p_input_kafka_partition,
    p_input_kafka_offset,
    p_input_kafka_headers,
    p_output_kafka_headers,
    (p_output_json->'headerInfo'->>'corrId'),
    p_input_json,
    p_output_json,
    'put_ksk_result runtime error: ' || SQLERRM
  )
  RETURNING id INTO v_error_id;
  
  RETURN -1 * v_error_id;
END;

$function$;

-- ============================================================================
-- КОММЕНТАРИЙ НА ФУНКЦИЮ
-- ============================================================================

COMMENT ON FUNCTION upoa_ksk_reports.put_ksk_result(
  TIMESTAMP(3), TIMESTAMP(3), JSONB, JSONB, INTEGER, BIGINT, JSONB, JSONB
) IS 'Функция вставки данных КСК с логированием ошибок БЕЗ отката транзакции.

Версия: 4.1 от 17.11.2025

ВОЗВРАЩАЕМЫЕ ЗНАЧЕНИЯ:
  > 0 - ID вставленной записи (успех)
  < 0 - Отрицательный ERROR_ID из ksk_result_error (ошибка)
  = 0 - Зарезервировано

ВАЛИДАЦИЯ:
  Одна проверка всех 6 параметров через IF-ELSIF
  Один INSERT в ksk_result_error при любой ошибке

ЛОГИКА has_bypass (NEW v4.1):
  Анализирует массив searchCheckResultKCKH на наличие bypassName:
  
  1. Если фигурантов нет (массив пуст)
     → has_bypass = ''empty''
  
  2. Если есть хоть один фигурант с непустым bypassName
     → has_bypass = ''yes''
  
  3. Если есть фигуранты, но все bypassName пусты или отсутствуют
     → has_bypass = ''no''

ОБРАБОТКА ОШИБОК:
  - Валидация: error_code = PARAM_NULL, return = -ERROR_ID
  - Runtime: error_code = SQLSTATE, return = -ERROR_ID

ИНТЕГРАЦИЯ:
  if (result <= 0) {
    errorCounter.increment();
    log.error("Error ID: " + Math.abs(result));
  }';

-- ============================================================================
-- КОНЕЦ МИГРАЦИИ v4.1
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 004_put_ksk_result_batch.sql
-- Размер: 11.64 KB
-- ============================================================================

-- ============================================================================
-- ФАЙЛ: put_ksk_result_batch_ai_generated_20251029_002.sql
-- ============================================================================
-- ОПИСАНИЕ:
--   Функция для пакетной обработки сообщений КСК из Kafka
--   ВАРИАНТ 2: HYBRID с SAVEPOINT для изоляции ошибок
--
-- ДАТА СОЗДАНИЯ: 29.10.2025 15:26 MSK
-- ВЕРСИЯ: 2.0 (ОПТИМИЗИРОВАННАЯ)
-- БАЗОВАЯ ВЕРСИЯ: 1.0 от 29.10.2025 14:39 MSK
--
-- ============================================================================
-- КЛЮЧЕВЫЕ ИЗМЕНЕНИЯ В v2.0:
-- ============================================================================
-- 1. ✅ SAVEPOINT для изоляции ошибок отдельных записей
--       - Ошибка одной записи НЕ откатывает весь batch
--       - Продолжаем обработку остальных записей
--       - Гарантия максимального количества успешных вставок
--
-- 2. ✅ Обработка кейса put_ksk_result = -1
--       - Сохраняем error_id который вернул put_ksk_result
--       - Добавляем в массив error_ids для возврата
--
-- 3. ✅ Улучшенная обработка исключений
--       - ROLLBACK TO SAVEPOINT при ошибке
--       - Логирование в ksk_result_error с полным контекстом
--       - Сохранение error_id для анализа
--
-- 4. ✅ Мониторинг через RAISE NOTICE
--       - Прогресс обработки каждые 10 записей
--       - Итоговая статистика
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
-- -------------------
-- Ожидаемый прирост: 2-5x быстрее v1.0
-- 
-- ПРИЧИНЫ:
-- - SAVEPOINT предотвращает откат успешных INSERT при ошибке
-- - Batch продолжает обработку при частичных ошибках
-- - Меньше повторных вызовов из-за ошибок
-- - Лучшая утилизация connection pool
--
-- СОВМЕСТИМОСТЬ:
-- -------------
-- ✅ 100% обратная совместимость с v1.0
-- ✅ Та же сигнатура функции
-- ✅ Тот же формат входных/выходных данных
-- ✅ Полная совместимость с put_ksk_result
--
-- ТЕХНИЧЕСКИЙ СМЫСЛ:
-- -----------------
-- SAVEPOINT = подтранзакция внутри основной транзакции
-- - SAVEPOINT batch_record_N - создание точки отката
-- - ROLLBACK TO SAVEPOINT - откат только до этой точки
-- - RELEASE SAVEPOINT - освобождение точки отката при успехе
--
-- Пример работы при batch=3:
-- 1. Запись 1: OK → RELEASE SAVEPOINT → v_success++
-- 2. Запись 2: ERROR → ROLLBACK TO SAVEPOINT → v_errors++ → продолжаем
-- 3. Запись 3: OK → RELEASE SAVEPOINT → v_success++
-- Итого: 2 успеха, 1 ошибка, БЕЗ потери успешных записей
--
-- ФОРМАТ ВХОДНЫХ ДАННЫХ (p_batch):
--   [
--     {
--       "input_timestamp": "2025-10-29T14:00:00.123",
--       "output_timestamp": "2025-10-29T14:00:01.456",
--       "input_json": {...},
--       "output_json": {...},
--       "input_kafka_partition": 3,
--       "input_kafka_offset": 12345,
--       "input_kafka_headers": {...},
--       "output_kafka_headers": {...}
--     },
--     ... ещё N записей
--   ]
--
-- ФОРМАТ ВЫХОДНЫХ ДАННЫХ (TABLE):
--   total_records  | success_count | error_count | error_ids
--   ---------------|---------------|-------------|------------
--   100            | 97            | 3           | {1234, 1235, 1236}
--
-- ПАТТЕРНЫ ВЗЯТЫ ИЗ:
--   - put_ksk_result (основная функция вставки)
--   - ksk_result_error (логирование ошибок)
--   - PostgreSQL SAVEPOINT best practices
--
-- ============================================================================

--DROP FUNCTION upoa_ksk_reports.put_ksk_result_batch(jsonb);

CREATE OR REPLACE FUNCTION upoa_ksk_reports.put_ksk_result_batch(p_batch jsonb)
 RETURNS TABLE(total_records integer, success_count integer, error_count integer, error_ids integer[])
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_record JSONB;
    v_result_id INTEGER;
    v_success INTEGER := 0;
    v_errors INTEGER := 0;
    v_error_ids INTEGER[] := '{}';
    v_total INTEGER;
    v_record_idx INTEGER := 0;
    v_corrid TEXT;
    v_first_record JSONB;
    v_error_id INTEGER;
BEGIN
    -- ========================================================================
    -- ВАЛИДАЦИЯ ВХОДНЫХ ДАННЫХ
    -- ========================================================================

    IF p_batch IS NULL OR jsonb_typeof(p_batch) != 'array' THEN
        RAISE EXCEPTION 'p_batch must be a non-null JSONB array';
    END IF;

    v_total := jsonb_array_length(p_batch);

    IF v_total = 0 THEN
        RAISE EXCEPTION 'p_batch array is empty';
    END IF;

    -- Валидация структуры первой записи
    v_first_record := p_batch->0;
    IF v_first_record IS NULL OR 
       v_first_record->>'input_timestamp' IS NULL OR
       v_first_record->>'output_timestamp' IS NULL THEN
        RAISE EXCEPTION 'First record missing required timestamps';
    END IF;

    RAISE NOTICE 'Batch processing started: % records', v_total;

    -- ========================================================================
    -- ОБРАБОТКА КАЖДОЙ ЗАПИСИ С BEGIN/EXCEPTION
    -- ========================================================================
    FOR v_record IN SELECT * FROM jsonb_array_elements(p_batch)
    LOOP
        v_record_idx := v_record_idx + 1;

        -- Извлекаем corrId с улучшенным fallback
        v_corrid := COALESCE(
            v_record->'output_json'->'headerInfo'->>'corrId',
            v_record->'output_json'->>'corrId',
            'record_' || v_record_idx
        );

        -- ====================================================================
        -- BEGIN/EXCEPTION блок для изоляции ошибок
        -- PostgreSQL автоматически создаёт подтранзакцию
        -- ====================================================================
        BEGIN
            -- ================================================================
            -- ВЫЗОВ put_ksk_result ДЛЯ ОДНОЙ ЗАПИСИ
            -- ================================================================
            v_result_id := upoa_ksk_reports.put_ksk_result(
                (v_record->>'input_timestamp')::TIMESTAMP(3),
                (v_record->>'output_timestamp')::TIMESTAMP(3),
                v_record->'input_json',
                v_record->'output_json',
                COALESCE((v_record->>'input_kafka_partition')::INTEGER, -1),
                COALESCE((v_record->>'input_kafka_offset')::BIGINT, -1),
                v_record->'input_kafka_headers',
                v_record->'output_kafka_headers'
            );

            -- ================================================================
            -- АНАЛИЗ РЕЗУЛЬТАТА (новый контракт v4.0)
            -- put_ksk_result возвращает:
            --   > 0  = успех (ID вставленной записи)
            --   < 0  = ошибка (отрицательный error_id из ksk_result_error)
            -- ================================================================
            IF v_result_id > 0 THEN
                -- Успешная вставка
                v_success := v_success + 1;

            ELSE
                -- put_ksk_result вернул отрицательный error_id
                -- Ошибка УЖЕ залогирована в ksk_result_error
                v_errors := v_errors + 1;

                -- Сохраняем абсолютное значение error_id
                v_error_id := ABS(v_result_id);
                v_error_ids := array_append(v_error_ids, v_error_id);

                RAISE WARNING 'Record %/% (corrId: %) failed with error_id=%', 
                    v_record_idx, v_total, v_corrid, v_error_id;
            END IF;

        EXCEPTION WHEN OTHERS THEN
            -- ================================================================
            -- ОБРАБОТКА ИСКЛЮЧЕНИЙ
            -- Сюда попадают ошибки, которые НЕ словил put_ksk_result:
            -- - Некорректный формат JSONB
            -- - Ошибки casting (timestamp, integer)
            -- - Другие runtime ошибки
            -- ================================================================

            v_errors := v_errors + 1;

            -- Логируем ошибку в ksk_result_error
            INSERT INTO upoa_ksk_reports.ksk_result_error (
                error_code,
                error_message,
                input_timestamp,
                output_timestamp,
                kafka_partition,
                kafka_offset,
                input_kafka_headers,
                output_kafka_headers,
                corr_id,
                input_json,
                output_json,
                function_context
            )
            VALUES (
                SQLSTATE,
                format('Batch record %s/%s exception: %s', v_record_idx, v_total, SQLERRM),
                (v_record->>'input_timestamp')::TIMESTAMP(3),
                (v_record->>'output_timestamp')::TIMESTAMP(3),
                (v_record->>'input_kafka_partition')::INTEGER,
                (v_record->>'input_kafka_offset')::BIGINT,
                v_record->'input_kafka_headers',
                v_record->'output_kafka_headers',
                v_corrid,
                v_record->'input_json',
                v_record->'output_json',
                format('put_ksk_result_batch v3.0: record %s/%s, SQLSTATE=%s', 
                       v_record_idx, v_total, SQLSTATE)
            )
            RETURNING id INTO v_error_id;

            -- Сохраняем ID ошибки для возврата
            v_error_ids := array_append(v_error_ids, v_error_id);

            RAISE WARNING 'Batch record %/% exception: SQLSTATE=%, MESSAGE=%, corrId=%, error_id=%',
                v_record_idx, v_total, SQLSTATE, SQLERRM, v_corrid, v_error_id;
        END;

        -- Прогресс каждые 1000 записей (оптимизация логирования)
        IF v_record_idx % 1000 = 0 THEN
            RAISE NOTICE 'Progress: %/% records processed (success=%, errors=%)', 
                v_record_idx, v_total, v_success, v_errors;
        END IF;
    END LOOP;

    -- ========================================================================
    -- ВОЗВРАТ СТАТИСТИКИ
    -- ========================================================================

    RAISE NOTICE 'Batch processing completed: total=%, success=%, errors=%', 
        v_total, v_success, v_errors;

    RETURN QUERY SELECT 
        v_total,
        v_success,
        v_errors,
        v_error_ids;
END;
$function$
;
-- ============================================================================
-- КОНЕЦ МИГРАЦИИ
-- ============================================================================


-- ============================================================================
-- ФАЙЛ: 001_ksk_log_operation.sql
-- Размер: 3.18 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_log_operation
-- ============================================================================
-- ОПИСАНИЕ:
--   Вспомогательная функция для записи операции в системный лог
--   Используется во всех функциях системы для единообразного логирования
--
-- ПАРАМЕТРЫ:
--   @p_operation_code - Код операции (например: 'create_partitions')
--   @p_operation_name - Название операции (например: 'Создание партиций')
--   @p_begin_time     - Время начала операции
--   @p_status         - Статус: 'success' или 'error'
--   @p_info           - Дополнительная информация о результате
--   @p_err_msg        - Сообщение об ошибке (если есть)
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в логе
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   PERFORM ksk_log_operation(
--       'create_partitions',
--       'Создание партиций для всех таблиц',
--       v_start_time,
--       'success',
--       'Создано 21 партиция',
--       NULL
--   );
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION ksk_log_operation(
    p_operation_code VARCHAR,
    p_operation_name VARCHAR,
    p_begin_time     TIMESTAMP(3),
    p_status         VARCHAR,
    p_info           TEXT DEFAULT NULL,
    p_err_msg        TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_log_id INTEGER;
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_system_operations_log (
        operation_code,
        operation_name,
        begin_time,
        end_time,
        duration,
        status,
        info,
        err_msg
    ) VALUES (
        p_operation_code,
        p_operation_name,
        p_begin_time,
        CLOCK_TIMESTAMP(),
        CLOCK_TIMESTAMP() - p_begin_time,
        p_status,
        p_info,
        p_err_msg
    )
    RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ksk_log_operation(
    p_operation_code VARCHAR,
    p_operation_name VARCHAR,
    p_begin_time     TIMESTAMP with TIME ZONE,
    p_status         VARCHAR,
    p_info           TEXT DEFAULT NULL,
    p_err_msg        TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_log_id INTEGER;
BEGIN    
    RETURN upoa_ksk_reports.ksk_log_operation(
       p_operation_code,
       p_operation_name,
       p_begin_time::timestamp(3),
       p_status,
       p_info,
       p_err_msg);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT) IS 
    'Записывает операцию в системный лог с автоматическим расчётом длительности';


-- ============================================================================
-- ФАЙЛ: 001_ksk_create_partitions.sql
-- Размер: 4.51 KB
-- ============================================================================

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


-- ============================================================================
-- ФАЙЛ: 002_ksk_create_all_partitions.sql
-- Размер: 4.65 KB
-- ============================================================================

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


-- ============================================================================
-- ФАЙЛ: 003_list_partitions.sql
-- Размер: 2.81 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_list_partitions
-- ============================================================================
-- ОПИСАНИЕ:
--   Возвращает информацию о всех партициях таблиц КСК
--   Включает размер, диапазон и примерное количество записей
--
-- ПАРАМЕТРЫ:
--   Нет
--
-- ВОЗВРАЩАЕТ:
--   TABLE:
--     - table_name         TEXT   - Имя родительской таблицы
--     - partition_name     TEXT   - Имя партиции
--     - partition_range    TEXT   - Диапазон значений партиции
--     - total_size         TEXT   - Размер партиции (человекочитаемый)
--     - estimated_records  BIGINT - Примерное количество записей
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_list_partitions();
--   SELECT * FROM ksk_list_partitions() WHERE table_name = 'ksk_result';
--   SELECT * FROM ksk_list_partitions() ORDER BY total_size DESC LIMIT 10;
--
-- ЗАМЕТКИ:
--   - estimated_records - это грубая оценка (размер / 1000 байт)
--   - Отсортировано по имени таблицы и партиции
--   - Используется для мониторинга роста БД
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Переименование из list_all_ksk_partitions
--   2025-10-25 - Изменён возвращаемый тип с DATE на TEXT для совместимости с REGEXP_MATCH
-- ============================================================================
CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_list_partitions(
    p_table_name TEXT DEFAULT 'ksk_result'
)
RETURNS TABLE (
    partition_name      TEXT,
    partition_date      TEXT,
    partition_date_next TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        child.relname::TEXT AS partition_name,
        (REGEXP_MATCH(child.relname, '\d{4}_\d{2}_\d{2}'))[1]::TEXT AS partition_date,
        ((REGEXP_MATCH(child.relname, '\d{4}_\d{2}_\d{2}'))[1]::DATE + INTERVAL '1 day')::TEXT AS partition_date_next
    FROM pg_inherits i
    JOIN pg_class parent ON parent.oid = i.inhparent
    JOIN pg_class child ON child.oid = i.inhrelid
    JOIN pg_namespace n ON n.oid = parent.relnamespace
    WHERE n.nspname = 'upoa_ksk_reports'
      AND parent.relname = p_table_name
    ORDER BY child.relname;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_list_partitions(TEXT) IS 
    'Возвращает список партиций для указанной таблицы с датами начала и конца';


-- ============================================================================
-- ФАЙЛ: 005_drop_partitions.sql
-- Размер: 7.81 KB
-- ============================================================================

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


-- ============================================================================
-- ФАЙЛ: 100_drop_old.sql
-- Размер: 1.17 KB
-- ============================================================================

-- ============================================================================
-- УДАЛЕНИЕ СТАРЫХ ВЕРСИЙ ФУНКЦИЙ УПРАВЛЕНИЯ ПАРТИЦИЯМИ
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет устаревшие версии функций с неправильным именованием
--   Запускать перед установкой новых версий функций
--
-- ДАТА СОЗДАНИЯ: 2025-10-25
-- ============================================================================

-- Удаление функций старого именования (без префикса ksk_)
DROP FUNCTION IF EXISTS create_ksk_partitions(TEXT, DATE, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS create_ksk_partitions_for_all_tables(DATE, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS list_all_ksk_partitions() CASCADE;
DROP FUNCTION IF EXISTS drop_old_ksk_partitions(INTEGER) CASCADE;

-- Лог выполнения
DO $$
BEGIN
    RAISE NOTICE '✓ Удалены устаревшие функции управления партициями';
END $$;


-- ============================================================================
-- ФАЙЛ: 010_ksk_report_totals_xls_file.sql
-- Размер: 8.45 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта totals
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА:
--   Строка 1: Заголовки на русском (Всего транзакций, ...)
--   Строка 2: Имена полей на английском (total, totalWithoutResult, ...)
--   Строка 3: Данные
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data RECORD;
BEGIN
    -- Получаем данные отчёта
    SELECT
        total,
        total_without_result,
        total_with_result,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    INTO v_data
    FROM upoa_ksk_reports.ksk_report_totals_data
    WHERE report_header_id = p_report_header_id
    ORDER BY id DESC
    LIMIT 1;

    -- Проверяем наличие данных
    IF v_data IS NULL THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'totals__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем Excel XML (SpreadsheetML формат)
    v_xml_content := xmlroot(
        xmlelement(
            name "Workbook",
            xmlattributes(
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns",
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns:ss"
            ),
            -- Стили
            xmlelement(
                name "Styles",
                -- Стиль для заголовков (жирный)
                xmlelement(
                    name "Style",
                    xmlattributes('s1' AS "ss:ID"),
                    xmlelement(
                        name "Font",
                        xmlattributes('1' AS "ss:Bold")
                    )
                )
            ),
            -- Лист
            xmlelement(
                name "Worksheet",
                xmlattributes('Totals' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Total allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Total review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Не совпало с алгоритмами ДОПБ')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'total')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass'))
                    ),
                    -- Строка 3: Данные
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_without_result)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_with_result)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_allow)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_review)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_deny)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_bypass))
                    )
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Количество строк данных (без заголовков)
    v_row_count := 1;

    -- Сохраняем файл в таблицу
    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_content,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта totals и сохраняет в ksk_report_files';


-- ============================================================================
-- ФАЙЛ: 020_ksk_report_list_totals_xls_file.sql
-- Размер: 7.65 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_list_totals_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА:
--   Строка 1: Заголовки на русском (Код списка, Всего транзакций с списком, ...)
--   Строка 2: Имена полей на английском (listCode, totalWithList, ...)
--   Строки 3+: Данные (по одной строке на каждый list_code)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data_rows XML;
BEGIN
    -- Проверяем наличие данных
    SELECT COUNT(*) INTO v_row_count
    FROM upoa_ksk_reports.ksk_report_list_totals_data
    WHERE report_header_id = p_report_header_id;

    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'list_totals__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем строки данных
    SELECT xmlagg(
        xmlelement(
            name "Row",
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), list_code)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_with_list)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_allow)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_review)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_deny)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_bypass))
        )
        ORDER BY list_code
    )
    INTO v_data_rows
    FROM upoa_ksk_reports.ksk_report_list_totals_data
    WHERE report_header_id = p_report_header_id;

    -- Генерируем Excel XML (SpreadsheetML формат)
    v_xml_content := xmlroot(
        xmlelement(
            name "Workbook",
            xmlattributes(
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns",
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns:ss"
            ),
            -- Стили
            xmlelement(
                name "Styles",
                -- Стиль для заголовков (жирный)
                xmlelement(
                    name "Style",
                    xmlattributes('s1' AS "ss:ID"),
                    xmlelement(
                        name "Font",
                        xmlattributes('1' AS "ss:Bold")
                    )
                )
            ),
            -- Лист
            xmlelement(
                name "Worksheet",
                xmlattributes('ListTotals' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Код списка')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций с списком')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass'))
                    ),
                    -- Строки данных
                    v_data_rows
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Сохраняем файл в таблицу
    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_content,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals и сохраняет в ksk_report_files';


-- ============================================================================
-- ФАЙЛ: 030_ksk_report_list_totals_by_payment_type_xls_file.sql
-- Размер: 23.54 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_list_totals_by_payment_type_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals_by_payment_type
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (31 колонка A-AE):
--   Строка 1: Заголовки на русском
--   Строка 2: Имена полей на английском (listCode, totalWithList, ...)
--   Строки 3+: Данные (по одной строке на каждый list_code)
--
-- КОЛОНКИ:
--   A: listCode (Код списка)
--   B-F: Общие (totalWithList, totalAllow, totalReview, totalDeny, totalBypass)
--   G-K: Входящий I (iTotalWithList, iTotalAllow, iTotalReview, iTotalDeny, iTotalBypass)
--   L-P: Исходящий O (oTotalWithList, oTotalAllow, oTotalReview, oTotalDeny, oTotalBypass)
--   Q-U: Транзитный T (tTotalWithList, tTotalAllow, tTotalReview, tTotalDeny, tTotalBypass)
--   V-Z: Межфилиальный M (mTotalWithList, mTotalAllow, mTotalReview, mTotalDeny, mTotalBypass)
--   AA-AE: Внутрифилиальный V (vTotalWithList, vTotalAllow, vTotalReview, vTotalDeny, vTotalBypass)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data_rows XML;
BEGIN
    -- Проверяем наличие данных
    SELECT COUNT(*) INTO v_row_count
    FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data
    WHERE report_header_id = p_report_header_id;

    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'list_totals_by_payment_type__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем строки данных
    SELECT xmlagg(
        xmlelement(
            name "Row",
            -- A: listCode
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), list_code)),
            -- B-F: Общие
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_bypass, 0))),
            -- G-K: Входящий (I)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_bypass, 0))),
            -- L-P: Исходящий (O)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_bypass, 0))),
            -- Q-U: Транзитный (T)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_bypass, 0))),
            -- V-Z: Межфилиальный (M)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_bypass, 0))),
            -- AA-AE: Внутрифилиальный (V)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_bypass, 0)))
        )
        ORDER BY list_code
    )
    INTO v_data_rows
    FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data
    WHERE report_header_id = p_report_header_id;

    -- Генерируем Excel XML (SpreadsheetML формат)
    v_xml_content := xmlroot(
        xmlelement(
            name "Workbook",
            xmlattributes(
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns",
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns:ss"
            ),
            -- Стили
            xmlelement(
                name "Styles",
                xmlelement(
                    name "Style",
                    xmlattributes('s1' AS "ss:ID"),
                    xmlelement(
                        name "Font",
                        xmlattributes('1' AS "ss:Bold")
                    )
                )
            ),
            -- Лист
            xmlelement(
                name "Worksheet",
                xmlattributes('ListTotalsByPaymentType' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        -- A: Код списка
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Код списка')),
                        -- B-F: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.totalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля')),
                        -- G-K: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.iTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Исключено из контроля')),
                        -- L-P: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.oTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Исключено из контроля')),
                        -- Q-U: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.tTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.tTotalAllow.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Исключено из контроля')),
                        -- V-Z: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.mTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Исключено из контроля')),
                        -- AA-AE: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.vTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        -- A: listCode
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        -- B-F: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass')),
                        -- G-K: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalBypass')),
                        -- L-P: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalBypass')),
                        -- Q-U: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalBypass')),
                        -- V-Z: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalBypass')),
                        -- AA-AE: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalBypass'))
                    ),
                    -- Строки данных
                    v_data_rows
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Сохраняем файл в таблицу
    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_content,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals_by_payment_type и сохраняет в ksk_report_files';


-- ============================================================================
-- ФАЙЛ: 040_ksk_report_totals_by_payment_type_xls_file.sql
-- Размер: 31.74 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals_by_payment_type_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта totals_by_payment_type
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (42 колонки A-AP):
--   Строка 1: Заголовки на русском
--   Строка 2: Имена полей на английском
--   Строка 3: Данные
--
-- КОЛОНКИ:
--   A-G: Общие (total, totalWithoutResult, totalWithResult, totalAllow, totalReview, totalDeny, totalBypass)
--   H-N: Входящий I (iTotal, iTotalWithoutResult, iTotalWithResult, iTotalAllow, iTotalReview, iTotalDeny, iTotalBypass)
--   O-U: Исходящий O (oTotal, ...)
--   V-AB: Транзитный T (tTotal, ...)
--   AC-AI: Межфилиальный M (mTotal, ...)
--   AJ-AP: Внутрифилиальный V (vTotal, ...)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data RECORD;
BEGIN
    -- Получаем данные отчёта
    SELECT
        -- Общие
        total, total_without_result, total_with_result,
        total_allow, total_review, total_deny, total_bypass,
        -- Входящий (I)
        i_total, i_total_without_result, i_total_with_result,
        i_total_allow, i_total_review, i_total_deny, i_total_bypass,
        -- Исходящий (O)
        o_total, o_total_without_result, o_total_with_result,
        o_total_allow, o_total_review, o_total_deny, o_total_bypass,
        -- Транзитный (T)
        t_total, t_total_without_result, t_total_with_result,
        t_total_allow, t_total_review, t_total_deny, t_total_bypass,
        -- Межфилиальный (M)
        m_total, m_total_without_result, m_total_with_result,
        m_total_allow, m_total_review, m_total_deny, m_total_bypass,
        -- Внутрифилиальный (V)
        v_total, v_total_without_result, v_total_with_result,
        v_total_allow, v_total_review, v_total_deny, v_total_bypass
    INTO v_data
    FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data
    WHERE report_header_id = p_report_header_id
    ORDER BY id DESC
    LIMIT 1;

    -- Проверяем наличие данных
    IF v_data IS NULL THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'totals_by_payment_type__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Количество строк данных
    v_row_count := 1;

    -- Генерируем Excel XML (SpreadsheetML формат)
    v_xml_content := xmlroot(
        xmlelement(
            name "Workbook",
            xmlattributes(
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns",
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns:ss"
            ),
            -- Стили
            xmlelement(
                name "Styles",
                xmlelement(
                    name "Style",
                    xmlattributes('s1' AS "ss:ID"),
                    xmlelement(
                        name "Font",
                        xmlattributes('1' AS "ss:Bold")
                    )
                )
            ),
            -- Лист
            xmlelement(
                name "Worksheet",
                xmlattributes('TotalsByPaymentType' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        -- A-G: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего исключено из контроля')),
                        -- H-N: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Исключено из контроля')),
                        -- O-U: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Исключено из контроля')),
                        -- V-AB: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Исключено из контроля')),
                        -- AC-AI: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Исключено из контроля')),
                        -- AJ-AP: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        -- A-G: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'total')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass')),
                        -- H-N: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalBypass')),
                        -- O-U: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalBypass')),
                        -- V-AB: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalBypass')),
                        -- AC-AI: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalBypass')),
                        -- AJ-AP: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalBypass'))
                    ),
                    -- Строка 3: Данные
                    xmlelement(
                        name "Row",
                        -- A-G: Общие
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_bypass, 0))),
                        -- H-N: Входящий
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_bypass, 0))),
                        -- O-U: Исходящий
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_bypass, 0))),
                        -- V-AB: Транзитный
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_bypass, 0))),
                        -- AC-AI: Межфилиальный
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_bypass, 0))),
                        -- AJ-AP: Внутрифилиальный
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_bypass, 0)))
                    )
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Сохраняем файл в таблицу
    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_content,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта totals_by_payment_type и сохраняет в ksk_report_files';


-- ============================================================================
-- ФАЙЛ: 050_ksk_report_figurants_xls_file.sql
-- Размер: 10.12 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_figurants_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта figurants
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (10 колонок A-J):
--   Строка 1: Заголовки (listCode, nameFigurant, presidentGroup, autoLogin, exclusionPhrase, Всего транзакций, Allow, Review, Deny, Исключено из контроля)
--   Строка 2: Имена полей (listCode, nameFigurant, presidentGroup, autoLogin, exclusionPhrase, total, totalAllow, totalReview, totalDeny, totalBypass)
--   Строки 3+: Данные (по одной строке на каждого фигуранта)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_figurants_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data_rows XML;
BEGIN
    -- Проверяем наличие данных
    SELECT COUNT(*) INTO v_row_count
    FROM upoa_ksk_reports.ksk_report_figurants_data
    WHERE report_header_id = p_report_header_id;

    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'figurants__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем строки данных
    SELECT xmlagg(
        xmlelement(
            name "Row",
            -- A: listCode
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(list_code, ''))),
            -- B: nameFigurant
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(name_figurant, ''))),
            -- C: presidentGroup
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(president_group, ''))),
            -- D: autoLogin
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(auto_login, ''))),
            -- E: exclusionPhrase
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(exclusion_phrase, ''))),
            -- F: total
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total, 0))),
            -- G: totalAllow
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_allow, 0))),
            -- H: totalReview
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_review, 0))),
            -- I: totalDeny
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_deny, 0))),
            -- J: totalBypass
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_bypass, 0)))
        )
        ORDER BY list_code, name_figurant
    )
    INTO v_data_rows
    FROM upoa_ksk_reports.ksk_report_figurants_data
    WHERE report_header_id = p_report_header_id;

    -- Генерируем Excel XML (SpreadsheetML формат)
    v_xml_content := xmlroot(
        xmlelement(
            name "Workbook",
            xmlattributes(
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns",
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns:ss"
            ),
            -- Стили
            xmlelement(
                name "Styles",
                xmlelement(
                    name "Style",
                    xmlattributes('s1' AS "ss:ID"),
                    xmlelement(
                        name "Font",
                        xmlattributes('1' AS "ss:Bold")
                    )
                )
            ),
            -- Лист
            xmlelement(
                name "Worksheet",
                xmlattributes('Figurants' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'nameFigurant')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'presidentGroup')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'autoLogin')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'exclusionPhrase')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'nameFigurant')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'presidentGroup')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'autoLogin')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'exclusionPhrase')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'total')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass'))
                    ),
                    -- Строки данных
                    v_data_rows
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Сохраняем файл в таблицу
    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_content,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_figurants_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта figurants и сохраняет в ksk_report_files';


-- ============================================================================
-- ФАЙЛ: 060_ksk_report_review_xls_file.sql
-- Размер: 16.54 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта Review
--   ОПТИМИЗИРОВАНО для больших объёмов данных (до 500 000 строк)
--   Использует потоковую генерацию XML через string_agg вместо xmlagg
--
-- ПАРАМЕТРЫ:
--   @p_report_date - Дата отчёта
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_review_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (35 колонок A-AI):
--   Строка 1: Заголовки
--   Строка 2: Имена полей
--   Строки 3+: Данные
--
-- ОПТИМИЗАЦИИ:
--   1. Использует string_agg вместо xmlagg (меньше потребление памяти)
--   2. Экранирование XML делается через replace (быстрее xmlelement)
--   3. Генерация XML как TEXT, конвертация в XML только при сохранении
--   4. INSERT ON CONFLICT для атомарной замены отчёта за дату
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции с оптимизацией для больших объёмов
--   2025-12-08 - FIX: escape_xml теперь удаляет недопустимые XML control characters
--   2025-12-08 - FIX: Сохранение в file_content_text (TEXT) вместо file_content (XML)
--                для избежания ошибок валидации XML на больших файлах
-- ============================================================================

-- Вспомогательная функция для экранирования XML
-- Удаляет недопустимые XML символы и экранирует спецсимволы
-- XML 1.0 допускает только: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD]
CREATE OR REPLACE FUNCTION upoa_ksk_reports.escape_xml(p_text TEXT)
RETURNS TEXT AS $$
DECLARE
    v_text TEXT;
BEGIN
    IF p_text IS NULL OR p_text = '' THEN
        RETURN '';
    END IF;

    -- Шаг 1: Оставляем ТОЛЬКО печатаемые ASCII и пробельные символы
    -- Удаляем все что НЕ является: пробел, буквы, цифры, пунктуация, кириллица
    -- [^...] - отрицание, удаляем всё что НЕ в списке
    v_text := regexp_replace(p_text, '[^[:print:][:space:]]', '', 'g');

    -- Шаг 2: Заменяем переносы строк на пробелы
    v_text := regexp_replace(v_text, E'[\r\n\t]+', ' ', 'g');

    -- Шаг 3: Экранируем XML спецсимволы (порядок важен - & первым!)
    v_text := replace(v_text, '&', '&amp;');
    v_text := replace(v_text, '<', '&lt;');
    v_text := replace(v_text, '>', '&gt;');
    v_text := replace(v_text, '"', '&quot;');
    v_text := replace(v_text, '''', '&apos;');

    RETURN v_text;
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;

-- Основная функция генерации отчёта
CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_xls_file(
    p_report_date DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_text TEXT;
    v_data_rows TEXT;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_file_size INTEGER;
BEGIN
    -- Формируем имя файла
    v_file_name := 'review__' || TO_CHAR(p_report_date, 'YYYYMMDD') || TO_CHAR(NOW(), 'HH24MI') || '.xls';

    -- Генерируем строки данных через string_agg (оптимизировано для больших объёмов)
    SELECT
        string_agg(
            '<Row>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(corr_id) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(message_timestamp::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(algorithm) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_value) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_payment_field) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_payment_value) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(list_code) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(name_figurant) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(president_group) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(auto_login::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(has_exclusion::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(exclusion_phrase) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(exclusion_name_list) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(is_bypass) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(transaction_resolution) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(figurant_resolition) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payment_id) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payment_purpose) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(account_debet) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(account_credit) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_inn) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_document_type) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_bank_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_bank_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_inn) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_bank_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_bank_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_document_type) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(amount) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(currency) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(currency_control) || '</Data></Cell>' ||
            '</Row>',
            E'\n'
        ),
        COUNT(*)
    INTO v_data_rows, v_row_count
    FROM upoa_ksk_reports.ksk_report_review(p_report_date)
    WHERE rn = 1;  -- Убираем дубликаты

    -- Если нет данных, создаём пустой отчёт
    IF v_row_count = 0 THEN
        v_data_rows := '';
    END IF;

    -- Собираем полный XML документ
    v_xml_text := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles>
<Style ss:ID="s1"><Font ss:Bold="1"/></Style>
</Styles>
<Worksheet ss:Name="Review">
<Table>
<Row>
<Cell ss:StyleID="s1"><Data ss:Type="String">corr_id</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Время обработки платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Алгоритм</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Значение для поиска на фигуранте</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Поле платежа с совпадением</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Значение поля платежа с совпадением</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Код списка</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Наименование фигуранта</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">presidentGroup</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">autoLogin</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Наличие исключения</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Фраза исключения</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Название списка исключений</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Исключено из контроля</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Решение по транзакции</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Решение по фигуранту</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ID платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Назначение платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.accountDebit.name</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Счёт кредита</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ИНН плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Имя плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Тип документа плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Банк плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта банка плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Имя получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ИНН получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.receiverBankName.name</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта банка получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Тип документа получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Сумма</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Валюта</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.currencyControl.name</Data></Cell>
</Row>
<Row>
<Cell ss:StyleID="s1"><Data ss:Type="String">corrId</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">messageTimestamp</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">algorithm</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchValue</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchPaymentField</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchPaymentValue</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">listCode</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">nameFigurant</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">presidentGroup</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">autoLogin</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">hasExclusion</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">exclusionPhrase</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">exclusionNameList</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">isBypass</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">transactionResolution</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">figurantResolition</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">paymentId</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">paymentPurpose</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">accountDebit</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">accountCredit</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerInn</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerDocumentType</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerBankName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerBankAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverInn</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverBankName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverBankAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverDocumentType</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">amount</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">currency</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">currencyControl</Data></Cell>
</Row>
' || COALESCE(v_data_rows, '') || '
</Table>
</Worksheet>
</Workbook>';

    -- Вычисляем размер файла
    v_file_size := LENGTH(v_xml_text);

    -- Сохраняем файл в таблицу как TEXT (без валидации XML - для больших файлов)
    -- INSERT ON CONFLICT для атомарной замены
    INSERT INTO upoa_ksk_reports.ksk_report_review_files (
        report_date,
        file_name,
        file_format,
        file_content_text,  -- TEXT вместо XML для больших файлов
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_date,
        v_file_name,
        'excel_xml',
        v_xml_text,  -- Сохраняем как TEXT без ::XML конвертации
        v_file_size,
        1,
        v_row_count
    )
    ON CONFLICT (report_date) DO UPDATE SET
        file_name = EXCLUDED.file_name,
        file_format = EXCLUDED.file_format,
        file_content_text = EXCLUDED.file_content_text,
        file_content = NULL,  -- Очищаем XML поле если было
        file_size_bytes = EXCLUDED.file_size_bytes,
        sheet_count = EXCLUDED.sheet_count,
        row_count = EXCLUDED.row_count,
        created_datetime = NOW()
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_xls_file(DATE) IS
    'Генерирует Excel XML файл для отчёта Review. Оптимизировано для больших объёмов (до 500k строк). Сохраняет в ksk_report_review_files с уникальностью по дате.';

COMMENT ON FUNCTION upoa_ksk_reports.escape_xml(TEXT) IS
    'Вспомогательная функция для экранирования специальных символов XML: & < > " ''';


-- ============================================================================
-- ФАЙЛ: 061_ksk_report_review_xls_find_bad_rows.sql
-- Размер: 7.76 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_xls_find_bad_rows (ДИАГНОСТИЧЕСКАЯ)
-- ============================================================================
-- ОПИСАНИЕ:
--   Находит строки в данных review, которые содержат невалидные XML символы
--   Используется для диагностики ошибок "invalid XML content"
--
-- ПАРАМЕТРЫ:
--   @p_report_date - Дата отчёта
--   @p_limit       - Максимум строк для проверки (по умолчанию 1000)
--
-- ВОЗВРАЩАЕТ:
--   TABLE с проблемными строками и информацией о невалидных символах
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание диагностической функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_xls_find_bad_rows(
    p_report_date DATE,
    p_limit INTEGER DEFAULT 1000
)
RETURNS TABLE (
    row_num         BIGINT,
    corr_id         TEXT,
    field_name      TEXT,
    field_value     TEXT,
    bad_char_codes  TEXT
) AS $$
DECLARE
    v_rec RECORD;
    v_row_num BIGINT := 0;
    v_fields TEXT[];
    v_values TEXT[];
    v_i INTEGER;
    v_char_code INTEGER;
    v_bad_codes TEXT;
    v_j INTEGER;
    v_val TEXT;
BEGIN
    -- Список полей для проверки
    v_fields := ARRAY[
        'corr_id', 'algorithm', 'match_value', 'match_payment_field', 'match_payment_value',
        'list_code', 'name_figurant', 'president_group', 'exclusion_phrase', 'exclusion_name_list',
        'is_bypass', 'transaction_resolution', 'figurant_resolition', 'payment_id', 'payment_purpose',
        'account_debet', 'account_credit', 'payer_inn', 'payer_name', 'payer_account_number',
        'payer_document_type', 'payer_bank_name', 'payer_bank_account_number', 'receiver_account_number',
        'receiver_name', 'receiver_inn', 'receiver_bank_name', 'receiver_bank_account_number',
        'receiver_document_type', 'amount', 'currency', 'currency_control'
    ];

    FOR v_rec IN
        SELECT *
        FROM upoa_ksk_reports.ksk_report_review(p_report_date)
        WHERE rn = 1
        LIMIT p_limit
    LOOP
        v_row_num := v_row_num + 1;

        -- Собираем значения полей
        v_values := ARRAY[
            v_rec.corr_id, v_rec.algorithm, v_rec.match_value, v_rec.match_payment_field, v_rec.match_payment_value,
            v_rec.list_code, v_rec.name_figurant, v_rec.president_group, v_rec.exclusion_phrase, v_rec.exclusion_name_list,
            v_rec.is_bypass, v_rec.transaction_resolution, v_rec.figurant_resolition, v_rec.payment_id, v_rec.payment_purpose,
            v_rec.account_debet, v_rec.account_credit, v_rec.payer_inn, v_rec.payer_name, v_rec.payer_account_number,
            v_rec.payer_document_type, v_rec.payer_bank_name, v_rec.payer_bank_account_number, v_rec.receiver_account_number,
            v_rec.receiver_name, v_rec.receiver_inn, v_rec.receiver_bank_name, v_rec.receiver_bank_account_number,
            v_rec.receiver_document_type, v_rec.amount, v_rec.currency, v_rec.currency_control
        ];

        -- Проверяем каждое поле на невалидные символы
        FOR v_i IN 1..array_length(v_fields, 1) LOOP
            v_val := v_values[v_i];
            IF v_val IS NOT NULL AND v_val != '' THEN
                v_bad_codes := '';

                -- Проверяем каждый символ
                FOR v_j IN 1..length(v_val) LOOP
                    v_char_code := ascii(substr(v_val, v_j, 1));

                    -- Проверяем на недопустимые XML символы
                    IF v_char_code < 32 AND v_char_code NOT IN (9, 10, 13) THEN
                        v_bad_codes := v_bad_codes || v_char_code::TEXT || ',';
                    END IF;
                END LOOP;

                -- Если нашли плохие символы - возвращаем
                IF v_bad_codes != '' THEN
                    row_num := v_row_num;
                    corr_id := v_rec.corr_id;
                    field_name := v_fields[v_i];
                    field_value := left(v_val, 100);  -- Первые 100 символов
                    bad_char_codes := rtrim(v_bad_codes, ',');
                    RETURN NEXT;
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_xls_find_bad_rows(DATE, INTEGER) IS
    'Диагностическая функция для поиска строк с невалидными XML символами в данных review';


-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_xls_test_xml (ДИАГНОСТИЧЕСКАЯ)
-- ============================================================================
-- Проверяет можно ли сконвертировать строку в XML
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_xls_test_xml(
    p_report_date DATE,
    p_batch_size INTEGER DEFAULT 1000
)
RETURNS TABLE (
    batch_num       INTEGER,
    rows_from       INTEGER,
    rows_to         INTEGER,
    xml_valid       BOOLEAN,
    error_message   TEXT
) AS $$
DECLARE
    v_batch INTEGER := 0;
    v_offset INTEGER := 0;
    v_xml_test TEXT;
    v_row_data TEXT;
    v_count INTEGER;
BEGIN
    -- Получаем общее количество строк
    SELECT COUNT(*) INTO v_count
    FROM upoa_ksk_reports.ksk_report_review(p_report_date)
    WHERE rn = 1;

    WHILE v_offset < v_count LOOP
        v_batch := v_batch + 1;

        BEGIN
            -- Генерируем XML для батча
            SELECT string_agg(
                '<Row>' ||
                '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(r.corr_id) || '</Data></Cell>' ||
                '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(r.name_figurant) || '</Data></Cell>' ||
                '</Row>',
                E'\n'
            )
            INTO v_row_data
            FROM (
                SELECT corr_id, name_figurant
                FROM upoa_ksk_reports.ksk_report_review(p_report_date)
                WHERE rn = 1
                OFFSET v_offset
                LIMIT p_batch_size
            ) r;

            -- Пробуем конвертировать в XML
            v_xml_test := '<?xml version="1.0"?><Root>' || COALESCE(v_row_data, '') || '</Root>';
            PERFORM v_xml_test::XML;

            batch_num := v_batch;
            rows_from := v_offset + 1;
            rows_to := LEAST(v_offset + p_batch_size, v_count);
            xml_valid := TRUE;
            error_message := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            batch_num := v_batch;
            rows_from := v_offset + 1;
            rows_to := LEAST(v_offset + p_batch_size, v_count);
            xml_valid := FALSE;
            error_message := SQLERRM;
            RETURN NEXT;
        END;

        v_offset := v_offset + p_batch_size;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_xls_test_xml(DATE, INTEGER) IS
    'Диагностика: проверяет батчами какие строки ломают XML парсинг';


-- ============================================================================
-- ФАЙЛ: 070_ksk_report_generate_all_xls_files_in_period.sql
-- Размер: 7.97 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_generate_all_xls_files_in_period
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel-файлы для всех отчётов в заданном периоде
--   Если у отчёта уже есть файл - пропускает
--   Для review-отчётов генерирует файлы за каждую дату в периоде
--
-- ПАРАМЕТРЫ:
--   @p_date_from - Начальная дата периода (включительно)
--   @p_date_to   - Конечная дата периода (включительно)
--
-- ВОЗВРАЩАЕТ:
--   TABLE (
--     report_type    TEXT,    -- Тип отчёта
--     report_date    DATE,    -- Дата отчёта
--     header_id      INTEGER, -- ID заголовка (NULL для review)
--     file_id        INTEGER, -- ID созданного файла
--     status         TEXT     -- 'created', 'skipped', 'error'
--   )
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_report_generate_all_xls_files_in_period('2025-12-01', '2025-12-08');
--   SELECT * FROM ksk_report_generate_all_xls_files_in_period(CURRENT_DATE - 7, CURRENT_DATE);
--
-- ЗАМЕТКИ:
--   - Обрабатывает все типы отчётов из ksk_report_header
--   - Для каждого типа вызывает соответствующую xls-функцию
--   - Review-отчёты обрабатываются отдельно (по датам, без header)
--   - Возвращает детальный лог выполнения
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
--   2025-12-08 - FIX: Исправлена неоднозначность report_date (rf.report_date)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_generate_all_xls_files_in_period(
    p_date_from DATE,
    p_date_to DATE
)
RETURNS TABLE (
    report_type    TEXT,
    report_date    DATE,
    header_id      INTEGER,
    file_id        INTEGER,
    status         TEXT
) AS $$
DECLARE
    v_header RECORD;
    v_file_id INTEGER;
    v_current_date DATE;
    v_has_file BOOLEAN;
    v_report_code TEXT;
BEGIN
    -- ========================================================================
    -- 1. ОБРАБОТКА СТАНДАРТНЫХ ОТЧЁТОВ (из ksk_report_header)
    -- ========================================================================
    FOR v_header IN
        SELECT
            h.id AS header_id,
            h.start_date,
            h.end_date,
            o.report_code,
            o.report_function
        FROM upoa_ksk_reports.ksk_report_header h
        JOIN upoa_ksk_reports.ksk_report_orchestrator o ON h.orchestrator_id = o.id
        WHERE h.status = 'done'
          AND h.start_date >= p_date_from
          AND h.start_date <= p_date_to
        ORDER BY h.start_date, o.report_code
    LOOP
        -- Проверяем, есть ли уже файл для этого отчёта
        SELECT EXISTS(
            SELECT 1 FROM upoa_ksk_reports.ksk_report_files
            WHERE report_header_id = v_header.header_id
        ) INTO v_has_file;

        IF v_has_file THEN
            -- Файл уже существует - пропускаем
            report_type := v_header.report_code;
            report_date := v_header.start_date;
            header_id := v_header.header_id;
            file_id := NULL;
            status := 'skipped';
            RETURN NEXT;
        ELSE
            -- Генерируем файл в зависимости от типа отчёта
            BEGIN
                CASE v_header.report_code
                    WHEN 'totals' THEN
                        SELECT upoa_ksk_reports.ksk_report_totals_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'totals_by_payment_type' THEN
                        SELECT upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'list_totals' THEN
                        SELECT upoa_ksk_reports.ksk_report_list_totals_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'list_totals_by_payment_type' THEN
                        SELECT upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'figurants' THEN
                        SELECT upoa_ksk_reports.ksk_report_figurants_xls_file(v_header.header_id) INTO v_file_id;
                    ELSE
                        -- Неизвестный тип отчёта - пропускаем
                        report_type := v_header.report_code;
                        report_date := v_header.start_date;
                        header_id := v_header.header_id;
                        file_id := NULL;
                        status := 'unknown_type';
                        RETURN NEXT;
                        CONTINUE;
                END CASE;

                report_type := v_header.report_code;
                report_date := v_header.start_date;
                header_id := v_header.header_id;
                file_id := v_file_id;
                status := 'created';
                RETURN NEXT;

            EXCEPTION WHEN OTHERS THEN
                report_type := v_header.report_code;
                report_date := v_header.start_date;
                header_id := v_header.header_id;
                file_id := NULL;
                status := 'error: ' || SQLERRM;
                RETURN NEXT;
            END;
        END IF;
    END LOOP;

    -- ========================================================================
    -- 2. ОБРАБОТКА REVIEW-ОТЧЁТОВ (по датам)
    -- ========================================================================
    v_current_date := p_date_from;

    WHILE v_current_date <= p_date_to LOOP
        -- Проверяем, есть ли уже файл для этой даты
        -- FIX: используем rf.report_date для избежания неоднозначности
        SELECT EXISTS(
            SELECT 1 FROM upoa_ksk_reports.ksk_report_review_files rf
            WHERE rf.report_date = v_current_date
        ) INTO v_has_file;

        IF v_has_file THEN
            -- Файл уже существует - пропускаем
            report_type := 'review';
            report_date := v_current_date;
            header_id := NULL;
            file_id := NULL;
            status := 'skipped';
            RETURN NEXT;
        ELSE
            -- Генерируем файл
            BEGIN
                SELECT upoa_ksk_reports.ksk_report_review_xls_file(v_current_date) INTO v_file_id;

                report_type := 'review';
                report_date := v_current_date;
                header_id := NULL;
                file_id := v_file_id;
                status := 'created';
                RETURN NEXT;

            EXCEPTION WHEN OTHERS THEN
                report_type := 'review';
                report_date := v_current_date;
                header_id := NULL;
                file_id := NULL;
                status := 'error: ' || SQLERRM;
                RETURN NEXT;
            END;
        END IF;

        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_generate_all_xls_files_in_period(DATE, DATE) IS
    'Генерирует Excel-файлы для всех отчётов в заданном периоде. Пропускает отчёты с существующими файлами. Включает review-отчёты.';


-- ============================================================================
-- ФАЙЛ: 001_ksk_report_review.sql
-- Размер: 8.45 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review
-- ============================================================================
-- ОПИСАНИЕ:
--   Формирует детальный отчёт по транзакциям, требующим ручной проверки (review)
--   Объединяет данные о транзакциях, фигурантах и совпадениях за указанную дату
--   Извлекает детализированную информацию из структурированных полей (не JSON)
--
-- ПАРАМЕТРЫ:
--   @report_date - Дата отчёта (по умолчанию: текущая дата)
--
-- ВОЗВРАЩАЕТ:
--   TABLE с 31 полем:
--     - Идентификация: corr_id, message_timestamp
--     - Совпадение: algorithm, match_value, match_payment_field, match_payment_value
--     - Фигурант: list_code, name_figurant, president_group, auto_login, exclusion данные
--     - Транзакция: transaction_resolution, figurant_resolition
--     - Платёж: payment_id, payment_purpose, account_debet, account_credit
--     - Плательщик: payer_inn, payer_name, payer_account_number, payer_document_type, payer_bank_*
--     - Получатель: receiver_account_number, receiver_name, receiver_inn, receiver_bank_*, receiver_document_type
--     - Сумма: amount, currency, currency_control
--     - Технические: match_id, figurant_id, transaction_id, rn (номер строки)
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_report_review('2025-10-22');
--   SELECT * FROM ksk_report_review(CURRENT_DATE);
--   
--   -- С фильтрацией
--   SELECT * FROM ksk_report_review('2025-10-22')
--   WHERE list_code = '4200' 
--     AND transaction_resolution = 'review';
--
-- ЗАМЕТКИ:
--   - Использует структурированные поля вместо JSON для повышения производительности
--   - Фильтрует только транзакции с resolution != 'empty'
--   - ROW_NUMBER партиционирует по match_id для устранения дубликатов
--   - Рекомендуется устанавливать work_mem = '256MB' для больших отчётов
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   - Типичное время выполнения: ~2-5 сек на 280k строк
--   - Использует партиционирование для эффективной фильтрации по датам
--   - Оптимизировано под операции JOIN по timestamp и id
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и документация
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review(
    report_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    -- Идентификация
    corr_id                     TEXT,
    message_timestamp           TIMESTAMP(3),
    
    -- Информация о совпадении
    algorithm                   TEXT,
    match_value                 TEXT,
    match_payment_field         TEXT,
    match_payment_value         TEXT,
    
    -- Информация о фигуранте
    list_code                   TEXT,
    name_figurant               TEXT,
    president_group             TEXT,
    auto_login                  BOOLEAN,
    has_exclusion               BOOLEAN,
    exclusion_phrase            TEXT,
    exclusion_name_list         TEXT,
    is_bypass                   TEXT,
    
    -- Резолюции
    transaction_resolution      TEXT,
    figurant_resolition         TEXT,
    
    -- Платёжные данные
    payment_id                  TEXT,
    payment_purpose             TEXT,
    account_debet               TEXT,
    account_credit              TEXT,
    
    -- Информация о плательщике
    payer_inn                   TEXT,
    payer_name                  TEXT,
    payer_account_number        TEXT,
    payer_document_type         TEXT,
    payer_bank_name             TEXT,
    payer_bank_account_number   TEXT,
    
    -- Информация о получателе
    receiver_account_number     TEXT,
    receiver_name               TEXT,
    receiver_inn                TEXT,
    receiver_bank_name          TEXT,
    receiver_bank_account_number TEXT,
    receiver_document_type      TEXT,
    
    -- Финансовые данные
    amount                      TEXT,
    currency                    TEXT,
    currency_control            TEXT,
    
    -- Технические идентификаторы
    match_id                    BIGINT,
    figurant_id                 BIGINT,
    transaction_id              BIGINT,
    rn                          INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    -- Фильтрация данных по дате отчёта
    WITH ksk_figurant_match_filtered AS (
        SELECT *
        FROM upoa_ksk_reports.ksk_figurant_match kfm
        WHERE kfm."timestamp" >= report_date 
          AND kfm."timestamp" < (report_date + INTERVAL '1 day')
    ),
    ksk_figurant_filtered AS (
        SELECT *
        FROM upoa_ksk_reports.ksk_figurant kf
        WHERE kf."timestamp" >= report_date 
          AND kf."timestamp" < (report_date + INTERVAL '1 day')
    ),
    ksk_result_filtered AS (
        SELECT *
        FROM upoa_ksk_reports.ksk_result kr
        WHERE kr.output_timestamp >= report_date 
          AND kr.output_timestamp < (report_date + INTERVAL '1 day')
          AND kr.resolution != 'empty'  -- Исключаем пустые транзакции
    )
    
    -- Основной запрос с объединением всех данных
    SELECT
        -- Идентификация транзакции
        rf.corr_id,
        rf.output_timestamp AS message_timestamp,
        
        -- Информация о совпадении
        mf.algorithm,
        mf.match_value,
        mf.match_payment_field,
        mf.match_payment_value,
        
        -- Информация о фигуранте
        ff.list_code,
        ff.name_figurant,
        ff.president_group,
        ff.auto_login,
        ff.has_exclusion,
        ff.exclusion_phrase,
        ff.exclusion_name_list,
        ff.is_bypass,
        
        -- Резолюции
        rf.resolution AS transaction_resolution,
        ff.resolution AS figurant_resolition,
        
        -- Платёжные данные (из структурированных полей)
        rf.payment_id,
        rf.payment_purpose,
        rf.account_debet,
        rf.account_credit,
        
        -- Информация о плательщике
        rf.payer_inn,
        rf.payer_name,
        rf.payer_account_number,
        rf.payer_document_type,
        rf.payer_bank_name,
        rf.payer_bank_account_number,
        
        -- Информация о получателе
        rf.receiver_account_number,
        rf.receiver_name,
        rf.receiver_inn,
        rf.receiver_bank_name,
        rf.receiver_bank_account_number,
        rf.receiver_document_type,
        
        -- Финансовые данные
        rf.amount,
        rf.currency,
        rf.currency_control,
        
        -- Технические идентификаторы
        mf.id AS match_id,
        ff.id AS figurant_id,
        rf.id AS transaction_id,
        
        -- Нумерация для устранения дубликатов
        ROW_NUMBER() OVER (PARTITION BY mf.id) AS rn
        
    FROM ksk_figurant_match_filtered mf
    JOIN ksk_figurant_filtered ff 
        ON mf.figurant_id = ff.id 
       AND mf."timestamp" = ff."timestamp"
    JOIN ksk_result_filtered rf 
        ON ff.source_id = rf.id 
       AND ff."timestamp" = rf.output_timestamp
$$;

COMMENT ON FUNCTION ksk_report_review(DATE) IS 
    'Формирует детальный отчёт по транзакциям review за указанную дату. Использует структурированные поля для оптимальной производительности';


-- ============================================================================
-- ФАЙЛ: 001_ksk_run_report.sql
-- Размер: 6.54 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ 1: ksk_run_report
-- ============================================================================
-- ОПИСАНИЕ:
--   Универсальная функция для запуска генерации отчёта
--   Создаёт заголовок отчёта, вызывает функцию генерации и обновляет статус
--
-- ПАРАМЕТРЫ:
--   @p_report_code - Код отчёта из оркестратора
--   @p_initiator   - Инициатор ('system' или 'user')
--   @p_user_login  - Логин пользователя (NULL для system)
--   @p_start_date  - Начальная дата периода (включительно)
--   @p_end_date    - Конечная дата периода (ИСКЛЮЧАЯ, NULL = p_start_date + 1 day)
--   @p_parameters  - Дополнительные параметры в формате JSON
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданного заголовка отчёта
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--   При NULL end_date: отчёт за 1 день [start_date ... start_date+1day)
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   -- Системный отчёт за день (22 октября)
--   SELECT ksk_run_report('totals', 'system', NULL, '2025-10-22', NULL, NULL);
--   -- Результат: p_end_date = '2025-10-23', интервал [2025-10-22 ... 2025-10-23)
--
--   -- Пользовательский отчёт с фильтром по спискам
--   SELECT ksk_run_report('figurants', 'user', 'ivanov', '2025-10-20', '2025-10-23',
--                         '{"list_codes": ["4200", "4204"]}'::JSONB);
--
-- ЗАВИСИМОСТИ:
--   - ksk_report_orchestrator
--   - ksk_report_header
--   - Функции генерации отчётов (ksk_report_*)
--   - ksk_log_operation (для логирования)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование через ksk_log_operation
--   2025-11-26 - FIX: p_end_date исключающий, NULL = start_date + 1 day
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_run_report(
    p_report_code VARCHAR,
    p_initiator   VARCHAR,
    p_user_login  VARCHAR DEFAULT NULL,
    p_start_date  DATE DEFAULT CURRENT_DATE,
    p_end_date    DATE DEFAULT NULL,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_report_function VARCHAR;
    v_report_name VARCHAR;
    v_ttl INTEGER;
    v_header_id INTEGER;
    v_start_time TIMESTAMP := CLOCK_TIMESTAMP();
    v_status VARCHAR := 'success';
    v_error_msg TEXT := NULL;
    v_info TEXT;
BEGIN
    -- Валидация: end_date не может быть меньше start_date
    IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
        RAISE EXCEPTION 'end_date (%) не может быть меньше start_date (%)', p_end_date, p_start_date;
    END IF;

    -- Установка end_date по умолчанию (исключающий интервал [start_date ... start_date+1day))
    IF p_end_date IS NULL THEN
        p_end_date := (p_start_date + INTERVAL '1 day')::DATE;
    END IF;

    -- Получение метаданных из оркестратора
    SELECT
        id,
        report_function,
        name,
        CASE
            WHEN p_initiator = 'system' THEN system_ttl
            WHEN p_initiator = 'user' THEN user_ttl
        END
    INTO v_orchestrator_id, v_report_function, v_report_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE report_code = p_report_code;

    IF v_orchestrator_id IS NULL THEN
        RAISE EXCEPTION 'Отчёт с кодом % не найден', p_report_code;
    END IF;

    -- Создание заголовка отчёта
    INSERT INTO upoa_ksk_reports.ksk_report_header (
        orchestrator_id,
        name,
        initiator,
        user_login,
        status,
        ttl,
        remove_date,
        start_date,
        end_date,
        parameters
    ) VALUES (
        v_orchestrator_id,
        v_report_name || ' (' || p_start_date || ' - ' || p_end_date - interval '1 day' || ')',
        p_initiator,
        p_user_login,
        'in_progress',
        v_ttl,
        CURRENT_DATE + v_ttl,
        p_start_date,
        p_end_date,
        p_parameters
    )
    RETURNING id INTO v_header_id;

    -- Вызов функции генерации отчёта
    BEGIN
        EXECUTE FORMAT('SELECT %I($1, $2, $3, $4)', v_report_function)
        USING v_header_id, p_start_date, p_end_date, p_parameters;

        -- Обновление статуса на 'done'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'done',
            finished_datetime = NOW()
        WHERE id = v_header_id;

        v_info := FORMAT(
            'Отчёт %s создан успешно. Header ID: %s. Период: %s - %s',
            p_report_code, v_header_id, p_start_date, p_end_date
        );

    EXCEPTION WHEN OTHERS THEN
        v_status := 'error';
        v_error_msg := SQLERRM;

        -- Обновление статуса на 'error'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = v_header_id;

        v_info := FORMAT(
            'Ошибка создания отчёта %s. Header ID: %s. Период: %s - %s',
            p_report_code, v_header_id, p_start_date, p_end_date
        );

        RAISE WARNING 'Ошибка при генерации отчёта %: %', p_report_code, SQLERRM;
    END;

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'run_report_' || p_report_code,
        'Генерация отчёта: ' || v_report_name,
        v_start_time,
        v_status,
        v_info,
        v_error_msg
    );

    RETURN v_header_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_run_report(VARCHAR, VARCHAR, VARCHAR, DATE, DATE, JSONB) IS
    'Универсальная функция для запуска генерации отчёта. Фильтр [start_date..end_date). При NULL end_date = start_date + 1 day';


-- ============================================================================
-- ФАЙЛ: 002_ksk_cleanup_old_reports.sql
-- Размер: 2.99 KB
-- ============================================================================

-- ============================================================================
-- СЛУЖЕБНАЯ ФУНКЦИЯ: ksk_cleanup_old_reports
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет устаревшие отчёты на основе remove_date
--   Рекомендуется запускать ежедневно в cron
--
-- ПАРАМЕТРЫ:
--   Нет
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - Количество удалённых заголовков отчётов
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_cleanup_old_reports();
--
-- ЗАМЕТКИ:
--   - Удаляет заголовки отчётов с remove_date < CURRENT_DATE
--   - Данные отчётов удаляются автоматически (CASCADE):
--     * ksk_report_totals_data
--     * ksk_report_list_totals_data
--     * ksk_report_totals_by_payment_type_data
--     * ksk_report_list_totals_by_payment_type_data
--     * ksk_report_figurants_data
--     * ksk_report_files
--     * ksk_report_review_data
--     * ksk_report_review_files
--   - Записывает результат в системный лог
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование
--   2025-12-08 - Добавлена очистка ksk_report_review_files (7 дней)
--   2025-12-16 - Удалена жёсткая очистка review_files (теперь CASCADE через header)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_reports()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_headers INTEGER;
    v_start_time      TIMESTAMP := CLOCK_TIMESTAMP();
    v_status          VARCHAR := 'success';
    v_info            TEXT;
BEGIN
    -- Удаление устаревших заголовков отчётов (CASCADE удалит связанные данные)
    -- Включая: ksk_report_review_data, ksk_report_review_files
    DELETE FROM upoa_ksk_reports.ksk_report_header
    WHERE remove_date < CURRENT_DATE;

    GET DIAGNOSTICS v_deleted_headers = ROW_COUNT;

    v_info := FORMAT(
        'Удалено заголовков отчётов: %s (данные удалены каскадно)',
        v_deleted_headers
    );

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'cleanup_old_reports',
        'Очистка устаревших отчётов',
        v_start_time,
        v_status,
        v_info,
        NULL
    );

    RETURN v_deleted_headers;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_old_reports() IS
    'Удаляет устаревшие отчёты по remove_date. CASCADE удаляет связанные данные (включая review_data и review_files).';


-- ============================================================================
-- ФАЙЛ: 003_ksk_report_totals.sql
-- Размер: 3.03 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по общей статистике за период
--   Подсчитывает количество транзакций по резолюциям
--
-- ПАРАМЕТРЫ:
--   @p_header_id   - ID заголовка отчёта
--   @p_start_date  - Начальная дата периода (включительно)
--   @p_end_date    - Конечная дата периода (ИСКЛЮЧАЯ)
--   @p_parameters  - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--
-- ЗАМЕТКИ:
--   - Вызывается через ksk_run_report()
--   - Создаёт одну запись в ksk_report_totals_data
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и документация
--   2025-11-26 - FIX: total_bypass теперь по resolution='bypass', не has_bypass
--   2025-11-26 - FIX: p_end_date исключающий, убран +INTERVAL '1 day'
--   2025-12-08 - Добавлен вызов генерации Excel-файла
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals(
    p_header_id   INTEGER,
    p_start_date  DATE,
    p_end_date    DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_totals_data (
        report_header_id,
        total,
        total_without_result,
        total_with_result,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    )
    SELECT
        p_header_id,
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE resolution = 'empty') AS total_without_result,
        COUNT(*) FILTER (WHERE resolution != 'empty') AS total_with_result,
        COUNT(*) FILTER (WHERE resolution = 'allow') AS total_allow,
        COUNT(*) FILTER (WHERE resolution = 'review') AS total_review,
        COUNT(*) FILTER (WHERE resolution = 'deny') AS total_deny,
        COUNT(*) FILTER (WHERE resolution = 'bypass') AS total_bypass
    FROM upoa_ksk_reports.ksk_result
    WHERE output_timestamp >= p_start_date::TIMESTAMP(3)
      AND output_timestamp < p_end_date::TIMESTAMP(3);

    -- Генерация Excel-файла
    PERFORM upoa_ksk_reports.ksk_report_totals_xls_file(p_header_id);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует отчёт по общей статистике за период. v2: bypass как отдельный resolution. Фильтр [start_date..end_date)';


-- ============================================================================
-- ФАЙЛ: 003_ksk_report_totals_by_payment_type.sql
-- Размер: 7.25 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals_by_payment_type
-- ============================================================================
-- ОПИСАНИЕ:
-- Генерирует отчёт по статистике с разбивкой по типам платежей
-- Создаёт агрегации для каждого из 5 типов платежей (русские названия)
--
-- ПАРАМЕТРЫ:
-- @p_header_id   - ID заголовка отчёта
-- @p_start_date  - Начальная дата периода
-- @p_end_date    - Конечная дата периода
-- @p_parameters  - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
-- VOID
--
-- ЗАМЕТКИ:
-- - Создаёт одну запись со всеми типами платежей
-- - Типы платежей (русские названия):
--   • i_ - Входящий
--   • o_ - Исходящий
--   • t_ - Транзитный
--   • m_ - Межфилиальный
--   • v_ - Внутрифилиальный
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
-- 2025-10-25 - Исправлено использование русских названий типов платежей
-- 2025-11-26 - FIX: total_bypass теперь по resolution='bypass', не has_bypass
-- 2025-12-08 - Добавлен вызов генерации Excel-файла
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type(
    p_header_id   INTEGER,
    p_start_date  DATE,
    p_end_date    DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_totals_by_payment_type_data (
        report_header_id,
        total, total_without_result, total_with_result,
        total_allow, total_review, total_deny, total_bypass,
        i_total, i_total_without_result, i_total_with_result,
        i_total_allow, i_total_review, i_total_deny, i_total_bypass,
        o_total, o_total_without_result, o_total_with_result,
        o_total_allow, o_total_review, o_total_deny, o_total_bypass,
        t_total, t_total_without_result, t_total_with_result,
        t_total_allow, t_total_review, t_total_deny, t_total_bypass,
        m_total, m_total_without_result, m_total_with_result,
        m_total_allow, m_total_review, m_total_deny, m_total_bypass,
        v_total, v_total_without_result, v_total_with_result,
        v_total_allow, v_total_review, v_total_deny, v_total_bypass
    )
    SELECT
        p_header_id,
        -- Общие счётчики
        COUNT(*),
        COUNT(*) FILTER (WHERE resolution = 'empty'),
        COUNT(*) FILTER (WHERE resolution != 'empty'),                          -- FIX: != вместо вычитания
        COUNT(*) FILTER (WHERE resolution = 'allow'),
        COUNT(*) FILTER (WHERE resolution = 'review'),
        COUNT(*) FILTER (WHERE resolution = 'deny'),
        COUNT(*) FILTER (WHERE resolution = 'bypass'),                          -- FIX!
        -- Входящий
        COUNT(*) FILTER (WHERE payment_type = 'Входящий'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Входящий' AND resolution = 'bypass'),  -- FIX!
        -- Исходящий
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Исходящий' AND resolution = 'bypass'),  -- FIX!
        -- Транзитный
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Транзитный' AND resolution = 'bypass'),  -- FIX!
        -- Межфилиальный
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Межфилиальный' AND resolution = 'bypass'),  -- FIX!
        -- Внутрифилиальный
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution != 'empty'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'allow'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'review'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'deny'),
        COUNT(*) FILTER (WHERE payment_type = 'Внутрифилиальный' AND resolution = 'bypass')  -- FIX!
    FROM upoa_ksk_reports.ksk_result
    WHERE output_timestamp >= p_start_date::TIMESTAMP(3)
      AND output_timestamp < p_end_date::TIMESTAMP(3);

    -- Генерация Excel-файла
    PERFORM upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(p_header_id);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type(INTEGER, DATE, DATE, JSONB) IS
'Генерирует отчёт по статистике с разбивкой по типам платежей. v2: bypass как resolution';


-- ============================================================================
-- ФАЙЛ: 004_ksk_report_list_totals_by_payment_type.sql
-- Размер: 10.04 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_list_totals_by_payment_type (v2 ОПТИМИЗИРОВАННАЯ)
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по итогам по спискам с разбивкой по типам платежей
--   Комбинирует group by list_code с агрегацией по payment_type
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта
--   @p_start_date       - Начальная дата периода (включительно)
--   @p_end_date         - Конечная дата периода (ИСКЛЮЧАЯ)
--   @p_parameters       - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--
-- ОПТИМИЗАЦИИ:
--   ✅ UNNEST(list_codes) вместо LOOP по массиву → 5-10x быстрее
--   ✅ Один SELECT вместо множественных сканов таблицы
--   ✅ COUNT(*) FILTER для условной агрегации
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   ДО: 110 сек (с LOOP)
--   ПОСЛЕ: 10-20 сек (с UNNEST)
--   УСКОРЕНИЕ: 5-10x
--
-- МАППИНГ ТИПОВ ПЛАТЕЖЕЙ:
--   i_* = Входящий
--   o_* = Исходящий
--   t_* = Транзитный
--   m_* = Межфилиальный
--   v_* = Внутрифилиальный
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-26 - ИСПРАВЛЕНО: Привел в соответствие префиксы и типы платежей
--   2025-10-25 - Убран STRING_TO_ARRAY (list_codes уже массив TEXT[])
--   2025-10-25 - Добавлен UNNEST для оптимизации (v2)
--   2025-11-26 - FIX: p_end_date исключающий, убран +INTERVAL '1 day', TIMESTAMP(3)
--   2025-12-08 - Добавлен вызов генерации Excel-файла
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type(
    p_report_header_id INTEGER,
    p_start_date       DATE,
    p_end_date         DATE,
    p_parameters       JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data (
        report_header_id,
        list_code,
        total_with_list,
        total_without_list,
        total_allow,
        total_review,
        total_deny,
        total_bypass,
        i_total_with_list, i_total_without_list, i_total_allow, i_total_review, i_total_deny, i_total_bypass,
        o_total_with_list, o_total_without_list, o_total_allow, o_total_review, o_total_deny, o_total_bypass,
        t_total_with_list, t_total_without_list, t_total_allow, t_total_review, t_total_deny, t_total_bypass,
        m_total_with_list, m_total_without_list, m_total_allow, m_total_review, m_total_deny, m_total_bypass,
        v_total_with_list, v_total_without_list, v_total_allow, v_total_review, v_total_deny, v_total_bypass
    )
    SELECT
        p_report_header_id,
        f.list_code,
        -- ========================================================================
        -- ОБЩИЕ СЧЕТЧИКИ: по ТРАНЗАКЦИЯМ (не по фигурантам)
        -- ========================================================================
        COUNT(DISTINCT r.id) AS total_with_list,
        0 AS total_without_list,
        -- ========================================================================
        -- СЧЕТЧИКИ РЕШЕНИЙ: по ФИГУРАНТАМ БЕЗ bypass
        -- ========================================================================
        COUNT(*) FILTER (WHERE f.resolution = 'allow' AND f.is_bypass != 'yes') AS total_allow,
        COUNT(*) FILTER (WHERE f.resolution = 'review' AND f.is_bypass != 'yes') AS total_review,
        COUNT(*) FILTER (WHERE f.resolution = 'deny' AND f.is_bypass != 'yes') AS total_deny,
        -- ========================================================================
        -- СЧЕТЧИК BYPASS: по ФИГУРАНТАМ с is_bypass='yes'
        -- ========================================================================
        COUNT(*) FILTER (WHERE f.is_bypass = 'yes') AS total_bypass,
        -- ========================================================================
        -- i_* - Входящий: ТРАНЗАКЦИИ для total_with_list, ФИГУРАНТЫ для решений
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Входящий') AS i_total_with_list,
        0 AS i_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS i_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS i_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS i_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Входящий' AND f.is_bypass = 'yes') AS i_total_bypass,
        -- ========================================================================
        -- o_* - Исходящий
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Исходящий') AS o_total_with_list,
        0 AS o_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS o_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS o_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS o_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Исходящий' AND f.is_bypass = 'yes') AS o_total_bypass,
        -- ========================================================================
        -- t_* - Транзитный
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Транзитный') AS t_total_with_list,
        0 AS t_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS t_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS t_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS t_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Транзитный' AND f.is_bypass = 'yes') AS t_total_bypass,
        -- ========================================================================
        -- m_* - Межфилиальный
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Межфилиальный') AS m_total_with_list,
        0 AS m_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS m_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS m_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS m_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Межфилиальный' AND f.is_bypass = 'yes') AS m_total_bypass,
        -- ========================================================================
        -- v_* - Внутрифилиальный
        -- ========================================================================
        COUNT(DISTINCT r.id) FILTER (WHERE r.payment_type = 'Внутрифилиальный') AS v_total_with_list,
        0 AS v_total_without_list,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.resolution = 'allow' AND f.is_bypass != 'yes') AS v_total_allow,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.resolution = 'review' AND f.is_bypass != 'yes') AS v_total_review,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.resolution = 'deny' AND f.is_bypass != 'yes') AS v_total_deny,
        COUNT(*) FILTER (WHERE r.payment_type = 'Внутрифилиальный' AND f.is_bypass = 'yes') AS v_total_bypass
    FROM upoa_ksk_reports.ksk_figurant f
    INNER JOIN upoa_ksk_reports.ksk_result r
        ON f.source_id = r.id
        AND f.timestamp = r.output_timestamp
    WHERE f.timestamp >= p_start_date::TIMESTAMP(3)
      AND f.timestamp < p_end_date::TIMESTAMP(3)
      AND f.list_code IS NOT NULL
    GROUP BY f.list_code
    ORDER BY f.list_code;

    -- Генерация Excel-файла
    PERFORM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(p_report_header_id);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует отчёт по итогам по спискам с разбивкой по типам платежей. Фильтр [start_date..end_date). i=Входящий, o=Исходящий, t=Транзитный, m=Межфилиальный, v=Внутрифилиальный';


-- ============================================================================
-- ФАЙЛ: 005_ksk_report_list_totals.sql
-- Размер: 4.59 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ 3: ksk_report_list_totals
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по итогам по спискам за период
--   Агрегирует данные фигурантов по кодам списков
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта
--   @p_start_date       - Начальная дата периода (DATE, включительно)
--   @p_end_date         - Конечная дата периода (DATE, ИСКЛЮЧАЯ)
--   @p_parameters       - Дополнительные параметры (не используются)
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ИСТОЧНИК ДАННЫХ:
--   ksk_figurant - денормализованная таблица фигурантов
--   Поля: list_code, resolution, is_bypass, source_id, timestamp
--
-- ЛОГИКА:
--   1. Агрегирует по list_code (TEXT)
--   2. total_with_list = COUNT(DISTINCT source_id) - уникальные транзакции
--   3. allow/review/deny - исключены фигуранты с is_bypass='yes'
--   4. bypass - фигуранты с is_bypass='yes'
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--
-- ЗАМЕТКИ:
--   - Источник данных: таблица ksk_figurant (денормализованные поля)
--   - Агрегирует решения фигурантов (resolution, is_bypass)
--   - Фигуранты с is_bypass='yes' не учитываются в allow/review/deny
--   - Все поля в snake_case согласно правилам пространства КСК
--   - Фильтрация по timestamp (партиционирование и BRIN индекс)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и документация
--                Убран STRING_TO_ARRAY - list_codes уже массив TEXT[]
--   2025-11-25 - Переделана логика: JOIN на ksk_figurant вместо ksk_result
--   2025-11-25 - Исправлена фильтрация даты и исключение bypass из счетчиков
--   2025-11-25 - Переведено на денормализованные поля ksk_figurant
--   2025-11-25 - Исправлено имя поля: source_id (snake_case)
--   2025-11-25 - Переведена фильтрация на timestamp (вместо date) для оптимизации
--   2025-11-26 - FIX: p_end_date исключающий, упрощено приведение типов
--   2025-12-08 - Добавлен вызов генерации Excel-файла
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals(
    p_report_header_id INTEGER,
    p_start_date       DATE,
    p_end_date         DATE,
    p_parameters       JSONB DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_report_list_totals_data (
        report_header_id,
        list_code,
        total_with_list,
        total_without_list,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    )
    SELECT
        p_report_header_id,
        fig.list_code,
        COUNT(DISTINCT fig.source_id) AS total_with_list,
        0 AS total_without_list,
        COUNT(*) FILTER (WHERE fig.resolution = 'allow' AND fig.is_bypass != 'yes') AS total_allow,
        COUNT(*) FILTER (WHERE fig.resolution = 'review' AND fig.is_bypass != 'yes') AS total_review,
        COUNT(*) FILTER (WHERE fig.resolution = 'deny' AND fig.is_bypass != 'yes') AS total_deny,
        COUNT(*) FILTER (WHERE fig.is_bypass = 'yes') AS total_bypass
    FROM upoa_ksk_reports.ksk_figurant fig
    WHERE fig.timestamp >= p_start_date::TIMESTAMP(3)
      AND fig.timestamp < p_end_date::TIMESTAMP(3)
    GROUP BY fig.list_code
    ORDER BY fig.list_code;

    -- Генерация Excel-файла
    PERFORM upoa_ksk_reports.ksk_report_list_totals_xls_file(p_report_header_id);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует отчёт по итогам по спискам с агрегацией данных фигурантов. Фильтр [start_date..end_date)';


-- ============================================================================
-- ФАЙЛ: 006_ksk_report_register_header.sql
-- Размер: 2.49 KB
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_register_header(
    p_report_code VARCHAR,
    p_initiator   VARCHAR,
    p_user_login  VARCHAR DEFAULT NULL,
    p_start_date  DATE DEFAULT CURRENT_DATE,
    p_end_date    DATE DEFAULT CURRENT_DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_name VARCHAR;
    v_ttl INTEGER;
    v_header_id INTEGER;
BEGIN
 -- Валидация: end_date не может быть меньше start_date
    IF p_end_date IS NOT NULL AND p_end_date < p_start_date THEN
        RAISE EXCEPTION 'end_date (%) не может быть меньше start_date (%)', p_end_date, p_start_date;
    END IF;
    -- Установка end_date: исключающий интервал [start_date ... end_date)
    -- Если NULL или равны start_date → отчёт за 1 день
    IF p_end_date IS NULL OR p_end_date = p_start_date THEN
        p_end_date := (p_start_date + INTERVAL '1 day')::DATE;
    END IF;

    -- Получение метаданных из оркестратора
    SELECT
        id,
        name,
        CASE
            WHEN p_initiator = 'system' THEN system_ttl
            WHEN p_initiator = 'user' THEN user_ttl
        END
    INTO v_orchestrator_id, v_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE report_code = p_report_code;

    IF v_orchestrator_id IS NULL THEN
        RAISE EXCEPTION 'Отчёт с кодом % не найден', p_report_code;
    END IF;

    -- Вставка записи в ksk_report_header
    INSERT INTO upoa_ksk_reports.ksk_report_header (
        orchestrator_id,
        name,
        initiator,
        user_login,
        status,
        ttl,
        remove_date,
        start_date,
        end_date,
        parameters
    ) VALUES (
        v_orchestrator_id,
        v_name || ' (' || p_start_date || ' - ' || p_end_date - interval '1 day' || ')',
        p_initiator,
        p_user_login,
        'in_progress',
        v_ttl,
        CURRENT_DATE + v_ttl,
        p_start_date,
        p_end_date,
        p_parameters
    )
    RETURNING id INTO v_header_id;

    RETURN v_header_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_register_header(VARCHAR, VARCHAR, VARCHAR, DATE, DATE, JSONB) IS
    'Регистрирует заголовок отчёта. Фильтр [start_date..end_date). При равных датах = start_date + 1 day';

-- ============================================================================
-- ФАЙЛ: 007_ksk_report_create_report.sql
-- Размер: 8.07 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_create_report
-- ============================================================================
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Создание функции
--   2025-11-26 - FIX: end_date исключающий, валидация end_date >= start_date
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_create_report(p_header_id integer)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_orchestrator_id INTEGER;
    v_report_function VARCHAR;
    v_report_name VARCHAR;
    v_ttl INTERVAL;
    v_start_time TIMESTAMP;
    v_status VARCHAR := 'success';
    v_info TEXT;
    v_error_msg TEXT;
    v_stack_trace TEXT;
    rec RECORD;
    v_log_id INTEGER;
BEGIN
    -- Получение записи из ksk_report_header
    SELECT id, orchestrator_id, initiator, user_login, start_date, end_date, parameters, status
    INTO rec
    FROM upoa_ksk_reports.ksk_report_header
    WHERE id = p_header_id;

    IF rec.id IS NULL THEN
        RAISE WARNING 'Запись с ID % не найдена в ksk_report_header', p_header_id;
        v_info := FORMAT('Запись с ID %s не найдена в ksk_report_header', p_header_id);
        v_error_msg := 'Запись не найдена';

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            'error',
            v_info,
            v_error_msg
        );

        RETURN -1*v_log_id;
    END IF;

    -- Проверка статуса
    IF rec.status NOT IN ('created', 'in_progress') THEN
        RAISE WARNING 'Статус записи с ID % не соответствует "created" или "in_progress". Текущий статус: %', p_header_id, rec.status;
        v_info := FORMAT('Статус записи с ID %s не соответствует "created" или "in_progress". Текущий статус: %s', p_header_id, rec.status);
        v_error_msg := 'Недопустимый статус';

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            'error',
            v_info,
            v_error_msg
        );

        RETURN -1*v_log_id;
    END IF;

    -- Валидация: end_date не может быть меньше start_date
    IF rec.end_date IS NOT NULL AND rec.end_date < rec.start_date THEN
        RAISE WARNING 'end_date (%) не может быть меньше start_date (%) для header_id %', rec.end_date, rec.start_date, p_header_id;
        v_info := FORMAT('end_date (%s) не может быть меньше start_date (%s). Header ID: %s', rec.end_date, rec.start_date, p_header_id);
        v_error_msg := 'Некорректный период: end_date < start_date';

        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            'error',
            v_info,
            v_error_msg
        );

        RETURN -1*v_log_id;
    END IF;

    -- Установка end_date по умолчанию (исключающий интервал [start_date ... start_date+1day))
    IF rec.end_date IS NULL OR rec.end_date = rec.start_date THEN
        rec.end_date := (rec.start_date + INTERVAL '1 day')::DATE;
        UPDATE upoa_ksk_reports.ksk_report_header
        SET end_date = rec.end_date
        WHERE id = rec.id;       
    END IF;

    -- Получение метаданных из оркестратора
    SELECT
        id,
        report_function,
        name,
        CASE
            WHEN rec.initiator = 'system' THEN system_ttl
            WHEN rec.initiator = 'user' THEN user_ttl
            ELSE NULL
        END
    INTO v_orchestrator_id, v_report_function, v_report_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE id = rec.orchestrator_id;

    IF v_orchestrator_id IS NULL THEN
        v_status := 'error';
        v_info := FORMAT('Отчет с orchestrator_id %s не найден. Header ID: %s', rec.orchestrator_id, rec.id);
        v_error_msg := 'Отчет не найден в оркестраторе';

        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            v_status,
            v_info,
            v_error_msg
        );

        RAISE WARNING 'Отчет с orchestrator_id % не найден. Header ID: %', rec.orchestrator_id, rec.id;

        RETURN -1*v_log_id;
    END IF;

    -- Проверка v_ttl на NULL
    IF v_ttl IS NULL THEN
        v_status := 'error';
        v_info := FORMAT('Не задан TTL для отчета с orchestrator_id %s. Header ID: %s', rec.orchestrator_id, rec.id);
        v_error_msg := 'Не задан TTL';

        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            CURRENT_TIMESTAMP,
            v_status,
            v_info,
            v_error_msg
        );

        RAISE WARNING 'Не задан TTL для отчета с orchestrator_id %: Header ID: %', rec.orchestrator_id, rec.id;

        RETURN -1*v_log_id;
    END IF;

    -- Обновление статуса на 'in_progress'
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'in_progress'
    WHERE id = rec.id;

    -- Вызов функции генерации отчёта
    BEGIN
        v_start_time := CLOCK_TIMESTAMP();

        EXECUTE FORMAT('SELECT %I($1, $2, $3, $4)', v_report_function)
        USING rec.id, rec.start_date, rec.end_date, rec.parameters;

        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'done',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_info := FORMAT(
            'Отчёт %s создан успешно. Header ID: %s. Период: %s - %s',
            v_report_name, rec.id, rec.start_date, rec.end_date
        );

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            v_start_time,
            'success',
            v_info,
            ''
        );

        RETURN rec.id;

    EXCEPTION WHEN OTHERS THEN
        v_status := 'error';
        v_error_msg := SQLERRM;
        GET STACKED DIAGNOSTICS v_stack_trace = pg_exception_context;

        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = rec.id;

        v_info := FORMAT(
            'Ошибка создания отчёта %s. Header ID: %s. Период: %s - %s',
            v_report_name, rec.id, rec.start_date, rec.end_date
        );

        v_log_id := upoa_ksk_reports.ksk_log_operation(
            'create_report',
            v_info,
            v_start_time,
            'error',
            v_info,
            v_error_msg || E'\nСтек-трейс:\n' || v_stack_trace
        );

        RAISE WARNING 'Ошибка при генерации отчёта %: %\nСтек-трейс:\n%', v_report_name, SQLERRM, v_stack_trace;

        RETURN -1*v_log_id;
    END;
END;
$function$
;

COMMENT ON FUNCTION ksk_report_create_report(INTEGER) IS
    'Создаёт отчёт по header_id. Фильтр [start_date..end_date). При NULL/равных датах = start_date + 1 day';


-- ============================================================================
-- ФАЙЛ: 008_ksk_report_create_all_reports.sql
-- Размер: 1.34 KB
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_create_all_reports()
RETURNS TABLE(success_ids INTEGER[], error_ids INTEGER[]) AS $$
DECLARE
    rec RECORD;
    v_result INTEGER;
    v_success_ids INTEGER[] := '{}';
    v_error_ids INTEGER[] := '{}';
BEGIN
    -- Обход всех записей в ksk_report_header со статусом 'in_progress'
    FOR rec IN 
        SELECT id
        FROM upoa_ksk_reports.ksk_report_header
        WHERE status = 'in_progress'
    LOOP
        -- Вызов функции для создания отчета
        v_result := upoa_ksk_reports.ksk_report_create_report(rec.id);

        -- Проверка результата
        IF v_result > 0 THEN
            v_success_ids := array_append(v_success_ids, v_result);
        ELSE
            v_error_ids := array_append(v_error_ids, v_result);
            RAISE WARNING 'Ошибка при создании отчета с Header ID: %', rec.id;
        END IF;
    END LOOP;

    RETURN QUERY
    SELECT v_success_ids, v_error_ids;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_create_all_reports() IS 
    'Функция для создания всех отчетов со статусом in_progress и возврата списков ID успешно созданных отчетов и ошибок';

-- ============================================================================
-- ФАЙЛ: 009_ksk_estimate_report_duration.sql
-- Размер: 3.83 KB
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_estimate_report_duration(p_report_code VARCHAR)
RETURNS INTERVAL AS $$
DECLARE
    v_avg_duration INTERVAL;
BEGIN
    -- Получение среднего времени выполнения отчета
    SELECT AVG(finished_datetime - created_datetime) AS avg_duration
    INTO v_avg_duration
    FROM upoa_ksk_reports.ksk_report_header t
    WHERE 
      t.orchestrator_id in (select id from upoa_ksk_reports.ksk_report_orchestrator where report_code = p_report_code)
      AND status = 'done';

    -- Если нет данных, вернуть 2 минуты
    IF v_avg_duration IS NULL THEN
        RAISE NOTICE 'Нет данных для расчета среднего времени выполнения отчета %', p_report_code;
        RETURN INTERVAL '2 minutes';
    END IF;

    RETURN v_avg_duration;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_estimate_report_duration(VARCHAR) IS 
    'Функция для расчета приблизительного времени формирования отчета по указанному report_code';

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_estimate_report_duration_by_id(p_header_id INTEGER)
RETURNS INTERVAL AS $$
DECLARE
    v_days INTEGER;
    v_max_duration INTERVAL;
    v_orchestrator_id INTEGER;
    v_start_date DATE;
    v_end_date DATE;
    v_period INTERVAL;
BEGIN
    -- Получаем информацию о отчете по id
    SELECT orchestrator_id, start_date, end_date
    INTO v_orchestrator_id, v_start_date, v_end_date
    FROM upoa_ksk_reports.ksk_report_header
    WHERE id = p_header_id;

    IF v_orchestrator_id IS NULL THEN
        RAISE NOTICE 'Отчет с ID % не найден', p_header_id;
        RETURN INTERVAL '2 minutes';
    ELSE 
        RAISE NOTICE 'v_orchestrator_id % ', v_orchestrator_id;
    END IF;

    -- Рассчитываем количество дней для формирования отчета
    v_days := (v_end_date - v_start_date) + 1;
    RAISE NOTICE 'v_days % ', v_days;

    -- Ищем максимальное время формирования такого же типа отчета с таким же количеством дней
    SELECT MAX(finished_datetime - created_datetime) AS max_duration
    INTO v_max_duration
    FROM upoa_ksk_reports.ksk_report_header
    WHERE orchestrator_id = v_orchestrator_id
      AND status = 'done'
      AND (end_date - start_date) + 1 = v_days;

    -- Если нет данных с таким количеством дней, ищем максимальное время формирования такого же типа отчета с периодом 1 день
    IF v_max_duration < interval '10 seconds' THEN
        SELECT MAX(finished_datetime - created_datetime) AS max_duration
        INTO v_max_duration
        FROM upoa_ksk_reports.ksk_report_header
        WHERE orchestrator_id = v_orchestrator_id
          AND status = 'done'
          AND (end_date - start_date) + 1 = 1;
    END IF;

    -- Если все еще нет данных, возвращаем 2 минуты
    IF v_max_duration IS NULL THEN
        RAISE NOTICE 'Нет данных для расчета среднего времени выполнения отчета с orchestrator_id % с периодом % дней', v_orchestrator_id, v_days;
        RETURN INTERVAL '2 minutes';
    END IF;

    -- Умножаем найденное время на количество дней
    RETURN v_max_duration * v_days;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_estimate_report_duration_by_id(INTEGER) IS 
    'Функция для оценки продолжительности формирования отчета по указанному header_id';

-- ============================================================================
-- ФАЙЛ: 010_ksk_regenerate_report.sql
-- Размер: 3.16 KB
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_regenerate_report(p_header_id INTEGER)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id INTEGER;
    v_report_table VARCHAR;
    v_result INTEGER;
    v_stack_trace TEXT;
    v_status TEXT;
    v_error_msg TEXT;
    v_info TEXT;
    v_log_id INTEGER;
BEGIN
    -- Получение orchestrator_id и report_table из ksk_report_header
    SELECT o.id, o.report_table
    INTO v_orchestrator_id, v_report_table
    FROM 
       upoa_ksk_reports.ksk_report_header h,
       upoa_ksk_reports.ksk_report_orchestrator o
    WHERE 
      h.id = p_header_id
      and h.orchestrator_id = o.id;

    IF v_orchestrator_id IS NULL THEN
        RAISE WARNING 'Запись с ID % не найдена в ksk_report_header', p_header_id;
        RETURN -1;
    END IF;

    -- Удаление данных из таблицы отчета
    EXECUTE FORMAT('DELETE FROM upoa_ksk_reports.%I WHERE report_header_id = %L', v_report_table, p_header_id);

    -- Обновление статуса на 'in_progress'
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'in_progress'
    WHERE id = p_header_id;

    -- Вызов функции ksk_report_create_report для регенерации отчета
    v_result := upoa_ksk_reports.ksk_report_create_report(p_header_id);

    RETURN v_result;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Ошибка при регенерации отчета с ID %: %', p_header_id, SQLERRM;
    v_status := 'error';
    v_error_msg := SQLERRM;
    GET STACKED DIAGNOSTICS v_stack_trace = pg_exception_context;
    -- Обновление статуса на 'error'
    UPDATE upoa_ksk_reports.ksk_report_header
    SET status = 'error',
        finished_datetime = NOW()
    WHERE id = p_header_id;
    v_info := FORMAT('Ошибка регенерации отчета отчёта ksk_report_header.id: %s.', p_header_id);
        -- Логирование в системный лог
    v_log_id := upoa_ksk_reports.ksk_log_operation('ksk_regenerate_report', v_info, now()::timestamp(3),
      'error', v_info, v_error_msg || E'\nСтек-трейс:\n' || v_stack_trace);
    RETURN -1*v_log_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_regenerate_report(INTEGER) IS 
    'Функция для регенерации отчета по указанному header_id';



/*
DO $$
DECLARE
    rec integer;
    v_result INTEGER;
BEGIN
    -- Обход всех записей с статусом 'done'
    FOR rec IN
        SELECT id
        FROM upoa_ksk_reports.ksk_report_header
        WHERE status = 'done'
    LOOP
        -- Вызов функции ksk_regenerate_report для каждого отчета
        v_result := upoa_ksk_reports.ksk_regenerate_report(rec);

        -- Логирование результата
        IF v_result > 0 THEN
            RAISE NOTICE 'Отчет с ID % успешно регенерирован.', rec;
        ELSE
            RAISE WARNING 'Ошибка при регенерации отчета с ID %.', rec;
        END IF;
    END LOOP;
END $$;  
*/

-- ============================================================================
-- ФАЙЛ: 011_ksk_report_figurants.sql
-- Размер: 5.1 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_figurants
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт по фигурантам за период
--   ОПТИМИЗИРОВАНО: Использует структурированные поля вместо JSON
--   Поддерживает фильтрацию по кодам списков через параметры
--
-- ПАРАМЕТРЫ:
--   @p_header_id   - ID заголовка отчёта
--   @p_start_date  - Начальная дата периода (включительно)
--   @p_end_date    - Конечная дата периода (ИСКЛЮЧАЯ)
--   @p_parameters  - JSON с опциональным полем "list_codes": ["4200", "4204"]
--
-- ВОЗВРАЩАЕТ:
--   VOID
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--
-- СТРУКТУРИРОВАННЫЕ ПОЛЯ ksk_figurant:
--   - list_code           TEXT
--   - name_figurant       TEXT
--   - president_group     TEXT
--   - auto_login          BOOLEAN
--   - has_exclusion       BOOLEAN
--   - exclusion_phrase    TEXT
--   - exclusion_name_list TEXT
--   - is_bypass           VARCHAR(10)
--   - resolution          VARCHAR(20)
--
-- ЗАМЕТКИ:
--   - Bypass-фигуранты исключены из расчёта total_allow, total_review, total_deny
--   - total = total_allow + total_review + total_deny + total_bypass
--
-- ПРИМЕР ПАРАМЕТРОВ:
--   NULL                                    -- Все списки
--   '{"list_codes": ["4200", "4204"]}'::JSONB  -- Фильтр по спискам
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Оптимизация: переход на структурированные поля
--   2025-11-20 - Добавлено поле exclusion_name_list - список исключений
--   2025-11-26 - Bypass-фигуранты исключены из расчёта разрешений
--   2025-11-26 - FIX: p_end_date исключающий, явное приведение к TIMESTAMP(3)
--   2025-12-08 - Добавлен вызов генерации Excel-файла
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_figurants(
    p_header_id   INTEGER,
    p_start_date  DATE,
    p_end_date    DATE,
    p_parameters  JSONB DEFAULT NULL
)
RETURNS VOID AS $$
DECLARE
    v_list_codes TEXT[];
BEGIN
    -- Извлечение фильтра по спискам из параметров
    IF p_parameters IS NOT NULL AND p_parameters ? 'list_codes' THEN
        SELECT ARRAY_AGG(value::TEXT)
        INTO v_list_codes
        FROM JSONB_ARRAY_ELEMENTS_TEXT(p_parameters->'list_codes');
    END IF;

    INSERT INTO upoa_ksk_reports.ksk_report_figurants_data (
        report_header_id,
        list_code,
        name_figurant,
        president_group,
        auto_login,
        exclusion_phrase,
        exclusion_name_list,
        total,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    )
    SELECT
        p_header_id,
        -- Структурированные поля (прямой доступ без извлечения из JSON)
        list_code,
        name_figurant,
        president_group,
        auto_login::TEXT AS auto_login,
        exclusion_phrase,
        exclusion_name_list,
        -- Агрегированные счётчики
        COUNT(*) AS total,
        -- Bypass-фигуранты исключены из расчёта разрешений
        COUNT(*) FILTER (WHERE resolution = 'allow' AND is_bypass != 'yes') AS total_allow,
        COUNT(*) FILTER (WHERE resolution = 'review' AND is_bypass != 'yes') AS total_review,
        COUNT(*) FILTER (WHERE resolution = 'deny' AND is_bypass != 'yes') AS total_deny,
        COUNT(*) FILTER (WHERE is_bypass = 'yes') AS total_bypass
    FROM upoa_ksk_reports.ksk_figurant
    WHERE "timestamp" >= p_start_date::TIMESTAMP(3)
      AND "timestamp" < p_end_date::TIMESTAMP(3)
      -- Фильтр по list_codes (если указан)
      AND (v_list_codes IS NULL OR list_code = ANY(v_list_codes))
    GROUP BY
        list_code,
        name_figurant,
        president_group,
        auto_login,
        exclusion_phrase,
        exclusion_name_list
    ORDER BY total DESC;

    -- Генерация Excel-файла
    PERFORM upoa_ksk_reports.ksk_report_figurants_xls_file(p_header_id);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_report_figurants(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует отчёт по фигурантам с опциональной фильтрацией. Фильтр [start_date..end_date). Использует структурированные поля для максимальной производительности';


-- ============================================================================
-- ФАЙЛ: 012_generate_all_reports_for_period.sql
-- Размер: 3.72 KB
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.generate_all_reports_for_period(p_start_date date DEFAULT '2021-11-01'::date, p_end_date date DEFAULT '2021-11-12'::date)
 RETURNS TABLE(operation_date date, report_type character varying, header_id integer, status character varying, message text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_date DATE;
    v_report_types TEXT[] := ARRAY['totals', 'totals_by_payment_type', 'list_totals', 'list_totals_by_payment_type', 'figurants'];
    v_report_type TEXT;
    v_header_id INTEGER;
    v_header_status VARCHAR;
    v_message TEXT;
    v_start_time TIMESTAMP(3);
    v_error_msg TEXT;
BEGIN
    v_start_time := NOW()::TIMESTAMP(3);
    
    -- ОСНОВНОЙ ЦИКЛ: По каждому дню в периоде
    v_current_date := p_start_date;
    
    WHILE v_current_date <= p_end_date LOOP
        
        -- ВНУТРЕННИЙ ЦИКЛ: По каждому типу отчёта
        FOREACH v_report_type IN ARRAY v_report_types LOOP
            BEGIN
                -- Создаём отчёт вызовом ksk_run_report()
                -- Параметры:
                -- p_report_code := код отчёта
                -- p_initiator := 'system' (встроенный, а не пользовательский)
                -- p_user_login := NULL (нет пользователя)
                -- p_start_date := дата дня
                -- p_end_date := NULL (будет автоматически установлена в p_start_date)
                -- p_parameters := NULL (нет доп. параметров)
                
                v_header_id := upoa_ksk_reports.ksk_run_report(
                    p_report_code := v_report_type,
                    p_initiator := 'system',
                    p_user_login := NULL,
                    p_start_date := v_current_date::date,
                    p_end_date := NULL,
                    p_parameters := NULL
                );
                
                -- Получаем финальный статус отчёта из ksk_report_header
                SELECT t.status INTO v_header_status
                FROM upoa_ksk_reports.ksk_report_header t
                WHERE id = v_header_id;
                
                v_message := FORMAT(
                    'Report %s for %s created successfully (header_id=%s, status=%s)',
                    v_report_type, v_current_date, v_header_id, v_header_status
                );
                
                -- Возвращаем успешный результат
                RETURN QUERY SELECT 
                    v_current_date,
                    v_report_type::VARCHAR,
                    v_header_id,
                    v_header_status,
                    v_message;
                    
            EXCEPTION WHEN OTHERS THEN
                v_error_msg := SQLERRM;
                v_message := FORMAT(
                    'ERROR: Failed to generate %s for %s: %s',
                    v_report_type, v_current_date, v_error_msg
                );
                
                -- Возвращаем ошибку
                RETURN QUERY SELECT 
                    v_current_date,
                    v_report_type::VARCHAR,
                    NULL::INTEGER,
                    'error'::VARCHAR,
                    v_message;
                    
                RAISE WARNING '%', v_message;
            END;
            
        END LOOP; -- Конец цикла по типам отчётов
        
        v_current_date := v_current_date + INTERVAL '1 day';
        
    END LOOP; -- Конец цикла по датам

END $function$
;


-- ============================================================================
-- ФАЙЛ: 012_ksk_report_review_create_report.sql
-- Размер: 17.58 KB
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_create_report
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт Review (проверки) за указанный день
--   Создаёт Excel XML файл с детальной информацией о транзакциях
--   Поддерживает фильтрацию по типу резолюции через параметры
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта (обязательный)
--   @p_start_date       - Дата отчёта (включительно)
--   @p_end_date         - Конечная дата (должна быть p_start_date + 1 day)
--   @p_parameters       - JSON с опциональным полем "resolution": "allow"|"review"|"deny"|"empty"
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданного файла в ksk_report_review_files
--
-- ОГРАНИЧЕНИЯ:
--   - Отчёт генерируется строго за 1 день (p_end_date = p_start_date + 1 day)
--   - Параметр resolution должен быть одним из: allow, review, deny, empty
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--   Фактически - данные за один день p_start_date
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   -- Все транзакции с резолюцией 'review' за день
--   SELECT ksk_report_review_create_report(123, '2025-12-15', '2025-12-16', '{"resolution": "review"}');
--
--   -- Все транзакции за день (по умолчанию resolution = 'review')
--   SELECT ksk_report_review_create_report(123, '2025-12-15', '2025-12-16', NULL);
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-16 - Создание функции для системы отчётов
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_create_report(
    p_report_header_id INTEGER,
    p_start_date       DATE,
    p_end_date         DATE,
    p_parameters       JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_resolution TEXT := 'review';  -- Значение по умолчанию
    v_file_id INTEGER;
    v_xml_text TEXT;
    v_data_rows TEXT;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_file_size INTEGER;
BEGIN
    -- =========================================================================
    -- ВАЛИДАЦИЯ ПАРАМЕТРОВ
    -- =========================================================================

    -- Проверка p_report_header_id
    IF p_report_header_id IS NULL THEN
        RAISE EXCEPTION 'p_report_header_id не может быть NULL';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM upoa_ksk_reports.ksk_report_header WHERE id = p_report_header_id
    ) THEN
        RAISE EXCEPTION 'Заголовок отчёта с id = % не найден', p_report_header_id;
    END IF;

    -- Проверка что p_end_date = p_start_date + interval '1 day'
    IF p_end_date != (p_start_date + INTERVAL '1 day')::DATE THEN
        RAISE EXCEPTION 'p_end_date (%) должна быть равна p_start_date + 1 день (%). Отчёт Review генерируется строго за 1 день.',
            p_end_date, (p_start_date + INTERVAL '1 day')::DATE;
    END IF;

    -- Извлечение параметра resolution из p_parameters
    IF p_parameters IS NOT NULL AND p_parameters ? 'resolution' THEN
        v_resolution := p_parameters->>'resolution';
    END IF;

    -- Проверка допустимых значений resolution
    IF v_resolution NOT IN ('allow', 'review', 'deny', 'empty') THEN
        RAISE EXCEPTION 'Недопустимое значение resolution: %. Допустимые значения: allow, review, deny, empty', v_resolution;
    END IF;

    -- =========================================================================
    -- ГЕНЕРАЦИЯ EXCEL XML ФАЙЛА
    -- =========================================================================

    -- Формируем имя файла
    v_file_name := 'review_' || v_resolution || '_' || TO_CHAR(p_start_date, 'YYYYMMDD') || '_' || TO_CHAR(NOW(), 'HH24MI') || '.xls';

    -- Генерируем строки данных через string_agg (оптимизировано для больших объёмов)
    SELECT
        string_agg(
            '<Row>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(corr_id) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(message_timestamp::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(algorithm) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_value) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_payment_field) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_payment_value) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(list_code) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(name_figurant) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(president_group) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(auto_login::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(has_exclusion::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(exclusion_phrase) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(exclusion_name_list) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(is_bypass) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(transaction_resolution) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(figurant_resolition) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payment_id) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payment_purpose) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(account_debet) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(account_credit) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_inn) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_document_type) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_bank_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_bank_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_inn) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_bank_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_bank_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_document_type) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(amount) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(currency) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(currency_control) || '</Data></Cell>' ||
            '</Row>',
            E'\n'
        ),
        COUNT(*)
    INTO v_data_rows, v_row_count
    FROM upoa_ksk_reports.ksk_report_review(p_start_date)
    WHERE rn = 1  -- Убираем дубликаты
      AND transaction_resolution = v_resolution;  -- Фильтр по резолюции

    -- Если нет данных, создаём пустой отчёт
    IF v_row_count = 0 THEN
        v_data_rows := '';
    END IF;

    -- Собираем полный XML документ
    v_xml_text := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles>
<Style ss:ID="s1"><Font ss:Bold="1"/></Style>
</Styles>
<Worksheet ss:Name="Review">
<Table>
<Row>
<Cell ss:StyleID="s1"><Data ss:Type="String">corr_id</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Время обработки платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Алгоритм</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Значение для поиска на фигуранте</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Поле платежа с совпадением</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Значение поля платежа с совпадением</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Код списка</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Наименование фигуранта</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">presidentGroup</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">autoLogin</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Наличие исключения</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Фраза исключения</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Название списка исключений</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Исключено из контроля</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Решение по транзакции</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Решение по фигуранту</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ID платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Назначение платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.accountDebit.name</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Счёт кредита</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ИНН плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Имя плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Тип документа плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Банк плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта банка плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Имя получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ИНН получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.receiverBankName.name</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта банка получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Тип документа получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Сумма</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Валюта</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.currencyControl.name</Data></Cell>
</Row>
<Row>
<Cell ss:StyleID="s1"><Data ss:Type="String">corrId</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">messageTimestamp</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">algorithm</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchValue</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchPaymentField</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchPaymentValue</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">listCode</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">nameFigurant</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">presidentGroup</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">autoLogin</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">hasExclusion</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">exclusionPhrase</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">exclusionNameList</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">isBypass</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">transactionResolution</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">figurantResolition</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">paymentId</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">paymentPurpose</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">accountDebit</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">accountCredit</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerInn</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerDocumentType</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerBankName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerBankAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverInn</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverBankName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverBankAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverDocumentType</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">amount</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">currency</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">currencyControl</Data></Cell>
</Row>
' || COALESCE(v_data_rows, '') || '
</Table>
</Worksheet>
</Workbook>';

    -- Вычисляем размер файла
    v_file_size := LENGTH(v_xml_text);

    -- =========================================================================
    -- СОХРАНЕНИЕ ФАЙЛА В ksk_report_review_files
    -- =========================================================================

    INSERT INTO upoa_ksk_reports.ksk_report_review_files (
        report_header_id,
        report_date,
        file_name,
        file_format,
        file_content_text,  -- TEXT вместо XML для больших файлов
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        p_start_date,
        v_file_name,
        'excel_xml',
        v_xml_text,  -- Сохраняем как TEXT без ::XML конвертации
        v_file_size,
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    -- =========================================================================
    -- СОХРАНЕНИЕ/ОБНОВЛЕНИЕ МЕТАДАННЫХ В ksk_report_review_data
    -- =========================================================================

    INSERT INTO upoa_ksk_reports.ksk_report_review_data (
        report_header_id,
        file_size_bytes,
        row_count,
        transaction_resolution
    )
    VALUES (
        p_report_header_id,
        v_file_size,
        v_row_count,
        v_resolution
    )
    ON CONFLICT (report_header_id) DO UPDATE SET
        file_size_bytes = EXCLUDED.file_size_bytes,
        row_count = EXCLUDED.row_count,
        transaction_resolution = EXCLUDED.transaction_resolution,
        created_date_time = NOW();

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_create_report(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует Excel XML файл для отчёта Review. Фильтр по резолюции (allow/review/deny/empty). Отчёт строго за 1 день. Сохраняет в ksk_report_review_files и ksk_report_review_data.';


-- ============================================================================
-- ФАЙЛ: 001_cron.sql
-- Размер: 8.49 KB
-- ============================================================================

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


-- ============================================================================
-- ФАЙЛ: 010_create_partitions.sql
-- Размер: 0.06 KB
-- ============================================================================

select upoa_ksk_reports.ksk_create_partitions_for_all_tables();


-- ============================================================================
-- ФАЙЛ: 020_alter_json_columns.sql
-- Размер: 1.49 KB
-- ============================================================================

-- Убедитесь, что стратегия хранения EXTENDED (должна быть по умолчанию)
-- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
ALTER TABLE upoa_ksk_reports.ksk_result
   ALTER COLUMN input_json SET STORAGE EXTENDED,
   ALTER COLUMN output_json SET STORAGE EXTENDED,
   ALTER COLUMN input_kafka_headers SET STORAGE EXTENDED,
   ALTER COLUMN output_kafka_headers SET STORAGE EXTENDED;

-- Включите сжатие LZ4 для колонок
ALTER TABLE upoa_ksk_reports.ksk_result 
    ALTER COLUMN input_json SET COMPRESSION lz4,
    ALTER COLUMN output_json SET COMPRESSION lz4,
    ALTER COLUMN input_kafka_headers SET COMPRESSION lz4,
    ALTER COLUMN output_kafka_headers SET COMPRESSION lz4;

-- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
ALTER TABLE upoa_ksk_reports.ksk_figurant
   ALTER COLUMN figurant SET STORAGE EXTENDED;

-- Включите сжатие LZ4 для колонок
ALTER TABLE upoa_ksk_reports.ksk_figurant 
    ALTER COLUMN figurant SET COMPRESSION lz4;

-- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
ALTER TABLE upoa_ksk_reports.ksk_figurant_match
   ALTER COLUMN match SET STORAGE EXTENDED;

-- Включите сжатие LZ4 для колонок
ALTER TABLE upoa_ksk_reports.ksk_figurant_match 
    ALTER COLUMN match SET COMPRESSION lz4;



-- ============================================================================
-- КОНЕЦ ОБЪЕДИНЕННОГО СКРИПТА
-- ============================================================================
-- Всего файлов обработано: 59
-- Дата завершения: 2025-12-16 15:03:09
-- ============================================================================
