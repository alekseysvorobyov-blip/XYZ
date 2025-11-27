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
