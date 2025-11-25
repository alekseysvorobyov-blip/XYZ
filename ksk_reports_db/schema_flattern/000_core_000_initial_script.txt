SET client_min_messages = NOTICE;
SET client_encoding = 'UTF8';
-- Создание схемы
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'upoa_ksk_reports') THEN
        CREATE SCHEMA upoa_ksk_reports;
        RAISE NOTICE 'Схема upoa_ksk_reports создана';
    ELSE
        RAISE NOTICE 'Схема upoa_ksk_reports уже существует';
    END IF;
END $$;

-- В начале файла миграции
SET search_path TO upoa_ksk_reports, public;