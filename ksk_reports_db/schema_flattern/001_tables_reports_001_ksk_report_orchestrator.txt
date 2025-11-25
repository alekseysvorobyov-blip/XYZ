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
    ('figurants', 'ksk_report_figurants_data', 'ksk_report_figurants', 'Отчёт по фигурантам', 30, 7)
ON CONFLICT (report_code) DO NOTHING;

SELECT '[ksk_report_orchestrator] ✅ Оркестратор инициализирован (5 типов отчётов)' AS status;

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
