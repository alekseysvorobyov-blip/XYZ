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
