-- ============================================================================
-- ТАБЛИЦА: ksk_report_review_files (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Файлы отчётов Review в формате Excel XML (SpreadsheetML)
--           Один файл на одну дату (уникальность по report_date)
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
    AND table_name = 'ksk_report_review_files'
  ) THEN

    -- Создание таблицы файлов отчётов Review
    CREATE TABLE upoa_ksk_reports.ksk_report_review_files (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

      -- Дата отчёта (уникальная - один отчёт на дату)
      report_date DATE NOT NULL UNIQUE,

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
      IS 'Файлы отчётов Review в формате Excel XML. Один файл на одну дату (уникальность по report_date).';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_review_files.report_date
      IS 'Дата отчёта (уникальная - только один отчёт на дату)';
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
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

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
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_review_files_date',
        'idx_ksk_report_review_files_format',
        'idx_ksk_report_review_files_created',
        'ksk_report_review_files_report_date_key'
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
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на report_date (уже есть UNIQUE constraint, но добавим явно для ясности)
-- Применение: поиск отчёта по дате
-- Используется для быстрого поиска файла за конкретную дату
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_date
  ON upoa_ksk_reports.ksk_report_review_files (report_date);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_date
  IS 'B-tree: Поиск отчёта по дате. Основной индекс для быстрого доступа.';

-- 4.2. B-tree индекс на file_format
-- Применение: фильтрация по формату (WHERE file_format = 'excel_xml')
-- Используется для выборки файлов определённого формата
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_format
  ON upoa_ksk_reports.ksk_report_review_files (file_format);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_format
  IS 'B-tree: Фильтрация по формату файла.';

-- 4.3. B-tree индекс на created_datetime
-- Применение: временная фильтрация (ORDER BY created_datetime DESC)
-- Используется для отображения последних файлов
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_review_files_created
  ON upoa_ksk_reports.ksk_report_review_files (created_datetime);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_review_files_created
  IS 'B-tree: Временная фильтрация и сортировка файлов.';

SELECT '[ksk_report_review_files] ✅ Индексы созданы/проверены';

COMMIT;

-- Изменяем constraint
ALTER TABLE upoa_ksk_reports.ksk_report_review_files 
DROP CONSTRAINT IF EXISTS chk_review_file_content;

ALTER TABLE upoa_ksk_reports.ksk_report_review_files 
ADD CONSTRAINT chk_review_file_content CHECK (
    file_content IS NOT NULL OR file_content_text IS NOT NULL
);


-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
