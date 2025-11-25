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
