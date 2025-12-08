-- ============================================================================
-- УДАЛЕНИЕ СТАРЫХ ВЕРСИЙ ФУНКЦИЙ УПРАВЛЕНИЯ ПАРТИЦИЯМИ
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет устаревшие версии функций с неправильным именованием
--   Запускать перед установкой новых версий функций
--
-- ДАТА СОЗДАНИЯ: 2025-10-25
-- АВТОР: KSK Reports System
-- ============================================================================

-- Удаление функций старого именования (без префикса ksk_)
DROP FUNCTION IF EXISTS create_ksk_partitions(TEXT, DATE, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS create_ksk_partitions_for_all_tables(DATE, INTEGER) CASCADE;
DROP FUNCTION IF EXISTS list_all_ksk_partitions() CASCADE;
DROP FUNCTION IF EXISTS drop_old_ksk_partitions(INTEGER) CASCADE;

-- Лог выполнения
DO $$
BEGIN
    RAISE NOTICE '✓ Удалены устаревшие функции управления партициями';
END $$;
