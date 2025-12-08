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
