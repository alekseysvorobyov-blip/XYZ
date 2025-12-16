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
