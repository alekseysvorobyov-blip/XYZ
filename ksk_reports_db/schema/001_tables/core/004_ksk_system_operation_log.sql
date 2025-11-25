-- ============================================================================
-- ТАБЛИЦА: ksk_system_operations_log
-- ============================================================================
-- ОПИСАНИЕ:
--   Системный лог всех служебных операций в системе КСК
--   Записывает информацию о каждой операции с временем выполнения и результатом
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и комментарии
-- ============================================================================
-- ============================================================================
-- ТАБЛИЦА: ksk_system_operations_log (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Системный лог всех служебных операций в системе отчётов
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
    AND table_name = 'ksk_system_operations_log'
  ) THEN
    
    -- Создание таблицы системного логирования
    CREATE TABLE upoa_ksk_reports.ksk_system_operations_log (
      -- Первичный ключ (простой, без партиционирования)
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Идентификация операции
      operation_code VARCHAR(50) NOT NULL,
      operation_name VARCHAR(200) NOT NULL,
      
      -- Временные метки
      begin_time TIMESTAMP(3) NOT NULL DEFAULT NOW()::timestamp(3),
      end_time TIMESTAMP(3),
      duration INTERVAL,
      
      -- Результат выполнения
      -- CHECK constraint ограничивает значения только 'success' и 'error'
      status VARCHAR(20) NOT NULL CHECK (status IN ('success', 'error')),
      info TEXT,
      err_msg TEXT
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_system_operations_log 
      IS 'Системный лог всех служебных операций в системе отчётов';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.id 
      IS 'Уникальный идентификатор записи логирования';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.operation_code 
      IS 'Код операции (например: create_partitions, drop_partitions, run_report)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.operation_name 
      IS 'Человекочитаемое название операции';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.begin_time 
      IS 'Время начала операции (DEFAULT: NOW())';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.end_time 
      IS 'Время окончания операции';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.duration 
      IS 'Длительность выполнения операции (вычисляется как end_time - begin_time)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.status 
      IS 'Статус выполнения: success или error (CHECK constraint)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.info 
      IS 'Дополнительная информация о результате операции (JSON или текст)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_system_operations_log.err_msg 
      IS 'Сообщение об ошибке при неудачном выполнении';
    
    RAISE NOTICE '[ksk_system_operations_log] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_system_operations_log] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================
-- Используем функцию add_column_if_not_exists для идемпотентности
-- Если таблица существовала с меньшим набором колонок, добавим недостающие

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'operation_code', 'VARCHAR(50)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'operation_name', 'VARCHAR(200)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'begin_time', 'TIMESTAMP(3)', 'now()::timestamp(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'end_time', 'TIMESTAMP(3)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'duration', 'INTERVAL');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'status', 'VARCHAR(20)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'info', 'TEXT');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_system_operations_log', 'err_msg', 'TEXT');

SELECT '[ksk_system_operations_log] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================
-- Логика: выбираем все индексы на таблице, и удаляем те, что не в списке нужных
-- Это безопаснее чем удалять всё сразу, и правильнее чем вручную

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_system_operations_log_operation_code',
        'idx_ksk_system_operations_log_begin_time',
        'idx_ksk_system_operations_log_status'
    ];
    v_index_count integer := 0;
BEGIN
    -- Итерируем по всем индексам на таблице ksk_system_operations_log (кроме PK)
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_system_operations_log'
          AND indexname NOT LIKE '%_pkey'  -- Исключаем PK
    LOOP
        -- Проверяем, входит ли этот индекс в список нужных
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            -- Удаляем ненужный индекс
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_system_operations_log] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    -- Итоговое сообщение
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_system_operations_log] ℹ️  Ненужных индексов не найдено, пропуск удаления';
    ELSE
        RAISE NOTICE '[ksk_system_operations_log] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- ---- ВАЖНО: Использование CREATE INDEX IF NOT EXISTS гарантирует идемпотентность ----

-- 4.1. B-tree индекс на operation_code
-- Применение: фильтрация логов по коду операции (WHERE operation_code = 'create_partitions')
-- Используется для поиска истории конкретной операции
--
CREATE INDEX IF NOT EXISTS idx_ksk_system_operations_log_operation_code
  ON upoa_ksk_reports.ksk_system_operations_log (operation_code);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_system_operations_log_operation_code 
  IS 'B-tree: Фильтрация логов по коду операции. Поиск истории операций.';

-- 4.2. B-tree индекс на begin_time
-- Применение: временная фильтрация логов (WHERE begin_time > now() - interval '1 day')
-- Используется для просмотра недавних операций
--
CREATE INDEX IF NOT EXISTS idx_ksk_system_operations_log_begin_time
  ON upoa_ksk_reports.ksk_system_operations_log (begin_time);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_system_operations_log_begin_time 
  IS 'B-tree: Фильтрация логов по времени начала. Поиск операций за период.';

-- 4.3. B-tree индекс на status
-- Применение: поиск ошибок (WHERE status = 'error') или успешных операций
-- Используется для мониторинга проблем
--
CREATE INDEX IF NOT EXISTS idx_ksk_system_operations_log_status
  ON upoa_ksk_reports.ksk_system_operations_log (status);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_system_operations_log_status 
  IS 'B-tree: Фильтрация логов по статусу. Поиск ошибок и успехов.';

SELECT '[ksk_system_operations_log] ✅ Индексы созданы/проверены';

DO $$
BEGIN
    ALTER TABLE upoa_ksk_reports.ksk_system_operations_log
    ALTER COLUMN begin_time TYPE TIMESTAMP(3),
    ALTER COLUMN end_time TYPE TIMESTAMP(3);
    
    RAISE NOTICE '✅ Миграция на TIMESTAMP(3) завершена';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ℹ️  Уже TIMESTAMP(3) или таблица не существует';
END $$;

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
