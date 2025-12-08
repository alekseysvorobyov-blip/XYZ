-- ============================================================================
-- ТАБЛИЦА: ksk_figurant
-- ОПИСАНИЕ: Таблица с фигурантами (лица, на которых выпали проверки)
-- ============================================================================
-- Связи: 
--   - N:1 с ksk_result (через source_id)
--   - 1:N с ksk_figurant_match
-- Партиционирование: По дням (timestamp)
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_figurant (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Таблица с фигурантами (лица, на которых выпали проверки)
-- Дата: 2025-10-27
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
    AND table_name = 'ksk_figurant'
  ) THEN
    
    -- Создание основной таблицы с партиционированием
    CREATE TABLE upoa_ksk_reports.ksk_figurant (
      -- Первичный ключ и связи
      id INTEGER GENERATED ALWAYS AS IDENTITY,
      source_id INTEGER NOT NULL,
      
      -- Временные метки
      date DATE NOT NULL,
      timestamp TIMESTAMP(3) NOT NULL,
      
      -- JSON данные
      figurant JSONB NOT NULL,
      figurant_index INTEGER NOT NULL,
      
      -- Классификация
      resolution VARCHAR(20) NOT NULL,
      is_bypass VARCHAR(10) DEFAULT 'no',
      
      -- Поля из figurant JSON
      list_code TEXT,
      name_figurant TEXT,
      president_group TEXT,
      auto_login BOOLEAN,
      has_exclusion BOOLEAN,
      exclusion_phrase TEXT,
      exclusion_name_list TEXT,
      bypass_name TEXT,
      
      -- Первичный ключ включает колонку партиционирования
      PRIMARY KEY (id, timestamp),
      
      -- Внешний ключ связь с ksk_result
      -- CASCADE DELETE: при удалении записи из ksk_result удаляются все фигуранты
      FOREIGN KEY (source_id, timestamp)
        REFERENCES upoa_ksk_reports.ksk_result(id, output_timestamp)
        ON DELETE CASCADE
    ) PARTITION BY RANGE (timestamp);
    
    -- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
    ALTER TABLE upoa_ksk_reports.ksk_figurant
       ALTER COLUMN figurant SET STORAGE EXTENDED;

    -- Включите сжатие LZ4 для колонок
    ALTER TABLE upoa_ksk_reports.ksk_figurant 
        ALTER COLUMN figurant SET COMPRESSION lz4;

    -- Партиция по умолчанию для новых данных
    -- КРИТИЧНО: Все строки, которые не попадают в явные партиции, попадают сюда
    CREATE TABLE upoa_ksk_reports.part_ksk_figurant_default 
      PARTITION OF upoa_ksk_reports.ksk_figurant DEFAULT;
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_figurant 
      IS 'Фигуранты - лица/организации, на которых выпали проверки КСК';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.source_id 
      IS 'Ссылка на ksk_result.id - N:1 связь';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.figurant 
      IS 'Полная информация о фигуранте в JSONB формате - EXTERNAL STORAGE';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.figurant_index 
      IS 'Порядковый номер фигуранта в результате проверки';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.resolution 
      IS 'Резолюция для фигуранта (ALLOW, BLOCK, REVIEW и т.д.)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.is_bypass 
      IS 'Признак обхода проверки (yes/no)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.list_code 
      IS 'Код санкционного списка';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.name_figurant 
      IS 'Полное имя фигуранта из санкционного списка';
    
    RAISE NOTICE '[ksk_figurant] ✅ Таблица создана с партиционированием по timestamp';
    RAISE NOTICE '[ksk_figurant] ✅ Дефолтная партиция создана: part_ksk_figurant_default';
    
  ELSE
    RAISE NOTICE '[ksk_figurant] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'source_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'figurant', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'figurant_index', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'resolution', 'VARCHAR(20)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'is_bypass', 'VARCHAR(10)', '''no''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'list_code', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'name_figurant', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'president_group', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'auto_login', 'BOOLEAN');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'has_exclusion', 'BOOLEAN');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'exclusion_phrase', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'exclusion_name_list', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant', 'bypass_name', 'TEXT');

-- Добавляем комментарий на поле
COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant.bypass_name IS 
'Имя исключения из списка исключений. Извлекается из JSON figuvant.bypassName при условии, что поле непусто. NULL если поле отсутствует или пусто.';

SELECT '[ksk_figurant] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================
-- Логика: выбираем все индексы на таблице, и удаляем те, что не в списке нужных
-- Это безопаснее чем удалять всё сразу, и правильнее чем вручную

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_figurant_ts_brin',
        'idx_ksk_figurant_list_code',
        'idx_ksk_figurant_source_id',
        'idx_ksk_figurant_resolution',
        'idx_ksk_figurant_is_bypass_yes'
    ];
    v_index_count integer := 0;
BEGIN
    -- Итерируем по всем индексам на таблице ksk_figurant (кроме PK и FK)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_figurant'
          AND indexname NOT LIKE '%_pkey'  -- Исключаем PK
    LOOP
        -- Проверяем, входит ли этот индекс в список нужных
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            -- Удаляем ненужный индекс
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_figurant] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    -- Итоговое сообщение
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_figurant] ℹ️  Ненужных индексов не найдено, пропуск удаления';
    ELSE
        RAISE NOTICE '[ksk_figurant] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- ---- ВАЖНО: Использование CREATE INDEX IF NOT EXISTS гарантирует идемпотентность ----

-- 4.1. BRIN индекс для timestamp (из 005_ksk_indexes_optimization.sql)
-- BRIN в 1000 раз компактнее B-tree для временных рядов
-- Идеален для партиционированных таблиц с упорядоченными данными
-- Применение: WHERE timestamp > now() - interval '7 days'
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_ts_brin
  ON upoa_ksk_reports.ksk_figurant USING BRIN (timestamp)
  WITH (pages_per_range = 128);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_ts_brin 
  IS 'BRIN: Фильтрация по временным диапазонам. ~1000x меньше, чем B-tree. Критичен на HDD.';

-- 4.2. Partial B-tree индекс на list_code (только NOT NULL значения) (из 005_ksk_indexes_optimization.sql)
-- Partial индекс экономит место (пропускает NULL)
-- Применение: поиск по коду санкционного списка (WHERE list_code = 'SDN')
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_list_code
  ON upoa_ksk_reports.ksk_figurant (list_code)
  WHERE list_code IS NOT NULL;
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_list_code 
  IS 'Partial B-tree: Поиск по санкционному списку. Только NOT NULL значения.';

-- 4.3. B-tree индекс на source_id (FK к ksk_result) (из 005_ksk_indexes_optimization.sql)
-- Критичен для JOIN операций между ksk_result и ksk_figurant
-- Применение: SELECT * FROM ksk_figurant WHERE source_id = X
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_source_id
  ON upoa_ksk_reports.ksk_figurant (source_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_source_id 
  IS 'B-tree: Индекс на внешний ключ для JOIN с ksk_result.';

-- 4.4. Индекс для фильтрации по resolution
-- Используется для агрегации по резолюциям
-- Применение: WHERE resolution = 'BLOCK'
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_resolution
  ON upoa_ksk_reports.ksk_figurant (resolution);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_resolution 
  IS 'B-tree: Фильтрация по резолюции. Используется в отчётах по результатам.';

-- 4.5. Partial индекс на is_bypass (только 'yes' значения)
-- Оптимизация: поиск только случаев обхода проверки
-- Применение: WHERE is_bypass = 'yes' - высокоселективный запрос
--
CREATE INDEX IF NOT EXISTS idx_ksk_figurant_is_bypass_yes
  ON upoa_ksk_reports.ksk_figurant (is_bypass)
  WHERE is_bypass = 'yes';
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_figurant_is_bypass_yes 
  IS 'Partial B-tree: Поиск обходов проверки (is_bypass=yes). Экономит место, высокая селективность.';

SELECT '[ksk_figurant] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
