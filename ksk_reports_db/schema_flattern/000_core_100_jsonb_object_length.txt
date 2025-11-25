-- ============================================================================
-- Функция: jsonb_object_length
-- Схема: upoa_ksk_reports
-- ============================================================================
-- Описание:
--   Универсальная функция для определения "размера" JSONB значения.
--   Возвращает количество элементов независимо от типа JSONB структуры.
--
-- Параметры:
--   input_data (jsonb) - входное JSONB значение любого типа
--
-- Возвращает:
--   integer - количество элементов/размер значения
--
-- Логика работы:
--   - Объект: возвращает количество полей (ключей)
--   - Массив: возвращает количество элементов
--   - Скаляр (строка, число, boolean): возвращает 1
--   - null: возвращает 0
--
-- Примеры:
--   SELECT jsonb_object_length('{"a":1,"b":2}'::jsonb);        -- 2
--   SELECT jsonb_object_length('[1,2,3,4]'::jsonb);             -- 4
--   SELECT jsonb_object_length('"text"'::jsonb);                -- 1
--   SELECT jsonb_object_length('null'::jsonb);                  -- 0
--
-- Свойства:
--   IMMUTABLE - результат зависит только от входных параметров
--   PARALLEL SAFE - может использоваться в параллельных запросах
--
-- Автор: -
-- Дата создания: 2025-10-27
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.jsonb_object_length(input_data jsonb)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $function$
SELECT CASE jsonb_typeof(input_data)
    WHEN 'object' THEN (SELECT count(*)::integer FROM jsonb_each(input_data))
    WHEN 'array' THEN jsonb_array_length(input_data)
    WHEN 'null' THEN 0
    ELSE 1
END;
$function$;
