-- ============================================================================
-- ТАБЛИЦА: ksk_figurant_match
-- ОПИСАНИЕ: Совпадения алгоритмов поиска для фигурантов
-- ============================================================================
-- Связи: 
--   - N:1 с ksk_figurant (через figurant_id)
-- Партиционирование: По дням (timestamp)
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_figurant_match (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Совпадения алгоритмов поиска для фигурантов
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
    AND table_name = 'ksk_figurant_match'
  ) THEN
    
    -- Создание основной таблицы с партиционированием
    CREATE TABLE upoa_ksk_reports.ksk_figurant_match (
      -- Первичный ключ и связи
      id INTEGER GENERATED ALWAYS AS IDENTITY,
      figurant_id INTEGER NOT NULL,
      
      -- Временные метки
      date DATE NOT NULL,
      timestamp TIMESTAMP(3) NOT NULL,
      
      -- JSON данные
      match JSONB NOT NULL,
      match_index INTEGER NOT NULL,
      algorithm VARCHAR(100) NOT NULL,
      
      -- Поля из match JSON
      match_value TEXT,
      match_payment_field TEXT,
      match_payment_value TEXT,
      
      -- Первичный ключ включает колонку партиционирования
      PRIMARY KEY (id, timestamp),
      
      -- Внешний ключ связь с ksk_figurant
      -- CASCADE DELETE: при удалении фигуранта удаляются все его совпадения
      FOREIGN KEY (figurant_id, timestamp)
        REFERENCES upoa_ksk_reports.ksk_figurant(id, timestamp)
        ON DELETE CASCADE
    ) PARTITION BY RANGE (timestamp);
    
    -- Если нет, сначала выполните это (скорее всего, НЕ НАДО):
    ALTER TABLE upoa_ksk_reports.ksk_figurant_match
       ALTER COLUMN match SET STORAGE EXTENDED;

    -- Включите сжатие LZ4 для колонок
    ALTER TABLE upoa_ksk_reports.ksk_figurant_match 
        ALTER COLUMN match SET COMPRESSION lz4;

    
    -- Партиция по умолчанию для новых данных
    -- КРИТИЧНО: Все строки, которые не попадают в явные партиции, попадают сюда
    CREATE TABLE upoa_ksk_reports.part_ksk_figurant_match_default 
      PARTITION OF upoa_ksk_reports.ksk_figurant_match DEFAULT;
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_figurant_match 
      IS 'Совпадения алгоритмов поиска для фигурантов';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.figurant_id 
      IS 'Ссылка на ksk_figurant.id - N:1 связь';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match 
      IS 'Полная информация о совпадении в JSONB формате - EXTERNAL STORAGE';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_index 
      IS 'Порядковый номер совпадения для фигуранта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.algorithm 
      IS 'Название алгоритма поиска совпадений';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_value 
      IS 'Значение совпадения из JSON';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_payment_field 
      IS 'Поле платежа, где найдено совпадение';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_figurant_match.match_payment_value 
      IS 'Значение поля платежа для совпадения';
    
    RAISE NOTICE '[ksk_figurant_match] ✅ Таблица создана с партиционированием по timestamp';
    RAISE NOTICE '[ksk_figurant_match] ✅ Дефолтная партиция создана: part_ksk_figurant_match_default';
    
  ELSE
    RAISE NOTICE '[ksk_figurant_match] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'figurant_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'timestamp', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match', 'JSONB');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_index', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'algorithm', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_value', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_payment_field', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_figurant_match', 'match_payment_value', 'TEXT');

SELECT '[ksk_figurant_match] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================
-- Логика: выбираем все индексы на таблице, и удаляем те, что не в списке нужных
-- Это безопаснее чем удалять всё сразу, и правильнее чем вручную

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_match_ts_brin',
        'idx_ksk_match_figurant_id',
        'idx_ksk_match_algorithm'
    ];
    v_index_count integer := 0;
BEGIN
    -- Итерируем по всем индексам на таблице ksk_figurant_match (кроме PK и FK)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_figurant_match'
          AND indexname NOT LIKE '%_pkey'  -- Исключаем PK
    LOOP
        -- Проверяем, входит ли этот индекс в список нужных
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            -- Удаляем ненужный индекс
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_figurant_match] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    -- Итоговое сообщение
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_figurant_match] ℹ️  Ненужных индексов не найдено, пропуск удаления';
    ELSE
        RAISE NOTICE '[ksk_figurant_match] ✅ Удалено % ненужных индексов', v_index_count;
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
CREATE INDEX IF NOT EXISTS idx_ksk_match_ts_brin
  ON upoa_ksk_reports.ksk_figurant_match USING BRIN (timestamp)
  WITH (pages_per_range = 128);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_match_ts_brin 
  IS 'BRIN: Фильтрация по временным диапазонам. ~1000x меньше, чем B-tree. Критичен на HDD.';

-- 4.2. B-tree индекс на figurant_id (FK к ksk_figurant) (из 005_ksk_indexes_optimization.sql)
-- Критичен для JOIN операций между ksk_figurant и ksk_figurant_match
-- Применение: SELECT * FROM ksk_figurant_match WHERE figurant_id = X
--
CREATE INDEX IF NOT EXISTS idx_ksk_match_figurant_id
  ON upoa_ksk_reports.ksk_figurant_match (figurant_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_match_figurant_id 
  IS 'B-tree: Индекс на внешний ключ для JOIN с ksk_figurant.';

-- 4.3. B-tree индекс на algorithm (для фильтрации по алгоритмам) (из 005_ksk_indexes_optimization.sql)
-- Применение: отчёты по используемым алгоритмам поиска, фильтрация по типам совпадений
-- Используется для аналитики: SELECT algorithm, COUNT(*) FROM ksk_figurant_match GROUP BY algorithm
--
CREATE INDEX IF NOT EXISTS idx_ksk_match_algorithm
  ON upoa_ksk_reports.ksk_figurant_match (algorithm);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_match_algorithm 
  IS 'B-tree: Фильтрация по алгоритмам поиска. Используется для аналитики и статистики.';

SELECT '[ksk_figurant_match] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
