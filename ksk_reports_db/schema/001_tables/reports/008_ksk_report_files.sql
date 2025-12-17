-- ============================================================================
-- ТАБЛИЦА: ksk_report_files (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Файлы отчётов в формате Excel XML (SpreadsheetML) и других форматах
--           Универсальное хранилище для всех типов отчётов
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

      -- Содержимое файла (унифицировано в TEXT)
      file_content_text TEXT NOT NULL,

      -- Метаданные файла
      file_size_bytes INTEGER,
      sheet_count INTEGER DEFAULT 1,
      row_count INTEGER
    );

    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_files
      IS 'Универсальное хранилище файлов отчётов всех типов (Excel XML, CSV, JSON)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.report_header_id
      IS 'Ссылка на заголовок отчёта в ksk_report_header (CASCADE DELETE)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_name
      IS 'Имя файла отчёта (например: report_2025-01.xls)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_format
      IS 'Формат файла: excel_xml, csv, json, xml';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_files.file_content_text
      IS 'Содержимое файла в текстовом формате (XML хранится как TEXT для производительности)';
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
-- 2. МИГРАЦИЯ: Перенос данных из file_content в file_content_text
-- ============================================================================

DO $$
BEGIN
  -- Проверяем, существует ли старая колонка file_content (XML)
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_files'
    AND column_name = 'file_content'
  ) THEN
    -- Переносим данные из file_content в file_content_text (если file_content_text пустой)
    UPDATE upoa_ksk_reports.ksk_report_files
    SET file_content_text = file_content::TEXT
    WHERE file_content IS NOT NULL
      AND (file_content_text IS NULL OR file_content_text = '');

    RAISE NOTICE '[ksk_report_files] ✅ Данные перенесены из file_content в file_content_text';

    -- Удаляем старую колонку file_content
    ALTER TABLE upoa_ksk_reports.ksk_report_files DROP COLUMN file_content;

    RAISE NOTICE '[ksk_report_files] ✅ Колонка file_content (XML) удалена';
  ELSE
    RAISE NOTICE '[ksk_report_files] ℹ️  Колонка file_content уже удалена';
  END IF;
END $$;

-- ============================================================================
-- 3. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'report_header_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_name', 'VARCHAR(500)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_format', 'VARCHAR(50)', '''excel_xml''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'created_datetime', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_content_text', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'file_size_bytes', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'sheet_count', 'INTEGER', '1');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_files', 'row_count', 'INTEGER');

SELECT '[ksk_report_files] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 4. УДАЛЕНИЕ СТАРЫХ CONSTRAINT-ов
-- ============================================================================

DO $$
BEGIN
  -- Удаляем старый constraint если есть
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_schema = 'upoa_ksk_reports'
    AND table_name = 'ksk_report_files'
    AND constraint_name = 'chk_file_content'
  ) THEN
    ALTER TABLE upoa_ksk_reports.ksk_report_files DROP CONSTRAINT chk_file_content;
    RAISE NOTICE '[ksk_report_files] ✅ Удалён старый constraint chk_file_content';
  END IF;
END $$;

-- ============================================================================
-- 5. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
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
-- 6. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 6.1. B-tree индекс на report_header_id (FK)
-- Применение: JOIN с ksk_report_header, CASCADE DELETE
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_files_header
  ON upoa_ksk_reports.ksk_report_files (report_header_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_files_header
  IS 'B-tree: FK для JOIN с ksk_report_header. Поиск файлов по отчёту.';

-- 6.2. B-tree индекс на file_format
-- Применение: фильтрация по формату (WHERE file_format = 'excel_xml')
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_files_format
  ON upoa_ksk_reports.ksk_report_files (file_format);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_files_format
  IS 'B-tree: Фильтрация по формату файла.';

-- 6.3. B-tree индекс на created_datetime
-- Применение: временная фильтрация (ORDER BY created_datetime DESC)
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
