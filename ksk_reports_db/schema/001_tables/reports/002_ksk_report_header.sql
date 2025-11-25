-- ============================================================================
-- ТАБЛИЦА: ksk_report_header (ИДЕМПОТЕНТНАЯ ВЕРСИЯ)
-- ОПИСАНИЕ: Заголовки отчётов - экземпляры сгенерированных отчётов
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
    AND table_name = 'ksk_report_header'
  ) THEN
    
    -- Создание таблицы заголовков отчётов
    CREATE TABLE upoa_ksk_reports.ksk_report_header (
      -- Первичный ключ
      id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      
      -- Связь с оркестратором
      orchestrator_id INTEGER NOT NULL REFERENCES upoa_ksk_reports.ksk_report_orchestrator(id) ON DELETE CASCADE,
      
      -- Идентификация отчёта
      name VARCHAR(500) NOT NULL,
      initiator VARCHAR(100) NOT NULL CHECK (initiator IN ('system', 'user')),
      user_login VARCHAR(100),
      
      -- Временные метки
      created_datetime TIMESTAMP NOT NULL DEFAULT NOW(),
      finished_datetime TIMESTAMP,
      
      -- Статус и хранение
      status VARCHAR(20) NOT NULL DEFAULT 'created' CHECK (status IN ('created', 'in_progress', 'done', 'error')),
      ttl INTEGER NOT NULL,
      remove_date DATE NOT NULL,
      
      -- Параметры отчёта
      start_date DATE,
      end_date DATE,
      parameters JSONB,
      
      -- Constraint для обязательного user_login при initiator='user'
      CONSTRAINT chk_user_login CHECK (
        (initiator = 'user' AND user_login IS NOT NULL) OR 
        (initiator = 'system' AND user_login IS NULL)
      )
    );
    
    -- Комментарии для документации
    COMMENT ON TABLE upoa_ksk_reports.ksk_report_header 
      IS 'Заголовки отчётов - экземпляры сгенерированных отчётов';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.orchestrator_id 
      IS 'Ссылка на тип отчёта в ksk_report_orchestrator';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.name 
      IS 'Название конкретного экземпляра отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.initiator 
      IS 'Инициатор создания: system или user';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.user_login 
      IS 'Логин пользователя (обязателен при initiator=user)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.status 
      IS 'Статус генерации: created, in_progress, done, error';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.ttl 
      IS 'Time-to-live в днях для данного отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.remove_date 
      IS 'Дата удаления отчёта (рассчитывается на основе TTL)';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.start_date 
      IS 'Начало периода отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.end_date 
      IS 'Конец периода отчёта';
    COMMENT ON COLUMN upoa_ksk_reports.ksk_report_header.parameters 
      IS 'Дополнительные параметры отчёта в JSON формате';
    
    RAISE NOTICE '[ksk_report_header] ✅ Таблица создана';
    
  ELSE
    RAISE NOTICE '[ksk_report_header] ℹ️  Таблица уже существует, пропуск создания';
  END IF;
END $$;

-- ============================================================================
-- 2. ДОБАВЛЕНИЕ НЕДОСТАЮЩИХ КОЛОНОК (для существующих таблиц)
-- ============================================================================

SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'orchestrator_id', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'name', 'VARCHAR(500)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'initiator', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'user_login', 'VARCHAR(100)');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'created_datetime', 'TIMESTAMP', 'now()');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'finished_datetime', 'TIMESTAMP');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'status', 'VARCHAR(20)', '''created''');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'ttl', 'INTEGER');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'remove_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'start_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'end_date', 'DATE');
SELECT upoa_ksk_reports.add_column_if_not_exists('upoa_ksk_reports.ksk_report_header', 'parameters', 'JSONB');

SELECT '[ksk_report_header] ✅ Проверка и добавление колонок завершена';

-- ============================================================================
-- 3. УДАЛЕНИЕ СТАРЫХ/НЕЭФФЕКТИВНЫХ ИНДЕКСОВ (ДИНАМИЧЕСКОЕ)
-- ============================================================================

DO $$
DECLARE
    v_index_name text;
    v_needed_indexes text[] := ARRAY[
        'idx_ksk_report_header_orchestrator',
        'idx_ksk_report_header_status',
        'idx_ksk_report_header_remove_date',
        'idx_ksk_report_header_created'
    ];
    v_index_count integer := 0;
BEGIN
    FOR v_index_name IN
        SELECT indexname
        FROM pg_indexes
        WHERE schemaname = 'upoa_ksk_reports'
          AND tablename = 'ksk_report_header'
          AND indexname NOT LIKE '%_pkey'
    LOOP
        IF NOT v_index_name = ANY(v_needed_indexes) THEN
            EXECUTE 'DROP INDEX IF EXISTS upoa_ksk_reports.' || quote_ident(v_index_name);
            RAISE NOTICE '[ksk_report_header] 🗑️  Удалён ненужный индекс: %', v_index_name;
            v_index_count := v_index_count + 1;
        END IF;
    END LOOP;
    
    IF v_index_count = 0 THEN
        RAISE NOTICE '[ksk_report_header] ℹ️  Ненужных индексов не найдено';
    ELSE
        RAISE NOTICE '[ksk_report_header] ✅ Удалено % ненужных индексов', v_index_count;
    END IF;
END $$;

-- ============================================================================
-- 4. СОЗДАНИЕ ОПТИМИЗИРОВАННЫХ ИНДЕКСОВ (идемпотентно)
-- ============================================================================

-- 4.1. B-tree индекс на orchestrator_id (FK)
-- Применение: JOIN с ksk_report_orchestrator
-- Используется для поиска всех отчётов определённого типа
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_orchestrator
  ON upoa_ksk_reports.ksk_report_header (orchestrator_id);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_orchestrator 
  IS 'B-tree: FK для JOIN с ksk_report_orchestrator. Поиск отчётов по типу.';

-- 4.2. B-tree индекс на status
-- Применение: фильтрация по статусу (WHERE status = 'done')
-- Используется для мониторинга и управления отчётами
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_status
  ON upoa_ksk_reports.ksk_report_header (status);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_status 
  IS 'B-tree: Фильтрация по статусу отчёта. Мониторинг генерации.';

-- 4.3. B-tree индекс на remove_date
-- Применение: поиск отчётов для удаления (WHERE remove_date < current_date)
-- Используется в процессе очистки устаревших отчётов
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_remove_date
  ON upoa_ksk_reports.ksk_report_header (remove_date);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_remove_date 
  IS 'B-tree: Поиск отчётов для удаления по TTL. Автоматическая очистка.';

-- 4.4. B-tree индекс на created_datetime
-- Применение: временная фильтрация (ORDER BY created_datetime DESC)
-- Используется для отображения последних отчётов
--
CREATE INDEX IF NOT EXISTS idx_ksk_report_header_created
  ON upoa_ksk_reports.ksk_report_header (created_datetime);
COMMENT ON INDEX upoa_ksk_reports.idx_ksk_report_header_created 
  IS 'B-tree: Временная фильтрация и сортировка отчётов.';

SELECT '[ksk_report_header] ✅ Индексы созданы/проверены';

COMMIT;

-- ============================================================================
-- КОНЕЦ СКРИПТА
-- ============================================================================
