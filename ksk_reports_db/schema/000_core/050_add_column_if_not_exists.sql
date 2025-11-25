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
