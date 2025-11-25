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
