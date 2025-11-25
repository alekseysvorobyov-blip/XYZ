-- ============================================================================
-- ВСПОМОГАТЕЛЬНЫЕ СКРИПТЫ И ТЕСТОВЫЕ ЗАПРОСЫ
-- ============================================================================
-- ОПИСАНИЕ:
--   Коллекция полезных запросов для работы с системой КСК
--   Включает тестирование, диагностику, статистику и оптимизацию
-- ============================================================================

-- ============================================================================
-- РАЗДЕЛ 1: ТЕСТОВЫЕ ЗАПРОСЫ ДЛЯ ПРОВЕРКИ ДАННЫХ
-- ============================================================================

-- Просмотр данных конкретной партиции
SELECT *
FROM part_ksk_result_2025_10_21
-- WHERE NOT resolution IN ('allow', 'empty')
;

-- Проверка уникальных типов платежей
SELECT DISTINCT payment_type
FROM part_ksk_result_2025_10_21
-- WHERE NOT resolution IN ('allow', 'empty')
;

-- Статистика по резолюциям за день
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE resolution = 'empty') AS total_without_results,
    COUNT(*) - (COUNT(*) FILTER (WHERE resolution = 'empty')) AS total_with_results,
    COUNT(*) FILTER (WHERE resolution = 'allow') AS total_allow,
    COUNT(*) FILTER (WHERE resolution = 'review') AS total_review,
    COUNT(*) FILTER (WHERE resolution = 'deny') AS total_deny,
    COUNT(*) FILTER (WHERE has_bypass = 'yes') AS total_bypass
FROM part_ksk_result_2025_10_22
-- GROUP BY resolution
;

-- ============================================================================
-- РАЗДЕЛ 2: СТАТИСТИКА ПО ФИГУРАНТАМ
-- ============================================================================

/*
ЦЕЛЬ ОТЧЁТА:
Статистика по фигурантам с возможностью фильтрации по listCode
(например, только списки 4200 и 4204)

КОЛОНКИ:
- listCode: код списка
- nameFigurant: имя фигуранта
- presidentGroup: президентская группа
- autoLogin: автоматический логин
- exclusionPhrase: фразы исключения
- Всего: общее количество
- Review/Allow: количество по резолюциям
*/

SELECT
    figurant->>'listCode' AS list_code,
    figurant->>'nameFigurant' AS name_figurant,
    figurant->>'presidentGroup' AS president_group,
    figurant->>'autoLogin' AS auto_login,
    COALESCE(
        (SELECT STRING_AGG(elem, ';')
         FROM JSONB_ARRAY_ELEMENTS_TEXT(figurant->'searchCheckResultsExclusionList'->'phrasesToExclude') AS elem),
        ''
    ) AS exclusion_phrase,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE resolution = 'allow') AS total_allow,
    COUNT(*) FILTER (WHERE resolution = 'review') AS total_review,
    COUNT(*) FILTER (WHERE resolution = 'deny') AS total_deny,
    COUNT(*) FILTER (WHERE is_bypass = 'yes') AS total_bypass
FROM ksk_figurant t
WHERE 1 = 1
  AND t."timestamp" >= '2025-10-21'::DATE 
  AND t."timestamp" < '2025-10-22'::DATE
  -- AND figurant->>'listCode' IN ('4200', '4204')  -- Фильтр по спискам
GROUP BY
    list_code,
    name_figurant,
    president_group,
    auto_login,
    exclusion_phrase
ORDER BY total DESC;

-- ============================================================================
-- РАЗДЕЛ 3: АНАЛИЗ И ОПТИМИЗАЦИЯ
-- ============================================================================

-- ANALYZE для обновления статистики (запускать после загрузки данных)
ANALYZE part_ksk_result_2025_10_21;
ANALYZE part_ksk_result_2025_10_22;
ANALYZE ksk_result;
ANALYZE part_ksk_figurant_2025_10_21;
ANALYZE part_ksk_figurant_2025_10_22;
ANALYZE ksk_figurant;
ANALYZE part_ksk_figurant_match_2025_10_21;
ANALYZE part_ksk_figurant_match_2025_10_22;
ANALYZE ksk_figurant_match;

-- Проверка настроек оптимизатора
SHOW constraint_exclusion;  -- Должно быть 'partition'
SHOW work_mem;              -- Рекомендуется 256MB для больших отчётов
SHOW enable_hashjoin;       -- Обычно 'on'

-- ============================================================================
-- РАЗДЕЛ 4: НАСТРОЙКИ ДЛЯ БОЛЬШИХ ОТЧЁТОВ
-- ============================================================================

-- Увеличить память для сортировки и хэширования
SET work_mem = '256MB';

-- Отключить hash join (если нужно использовать merge join)
-- SET enable_hashjoin = OFF;

-- Вернуть настройки по умолчанию
-- SET enable_hashjoin = ON;

-- ============================================================================
-- РАЗДЕЛ 5: ТЕСТИРОВАНИЕ ФУНКЦИИ ksk_report_review
-- ============================================================================

-- Подсчёт количества записей в отчёте
SELECT COUNT(*)
FROM ksk_report_review('2025-10-22'::DATE);

-- Проверка дубликатов (rn != 1)
SELECT COUNT(*)
FROM ksk_report_review('2025-10-22'::DATE)
WHERE rn != 1;

-- Полный отчёт с фильтрами
SELECT *
FROM ksk_report_review('2025-10-22'::DATE)
WHERE 1 = 1
  -- AND receiver_account_number LIKE '4070281080%'
  -- AND message_timestamp > '2025-10-22 00:00:18'
  -- AND match_value = 'займ'
  -- AND receiver_name = 'ООО "ГК "ПРОФ ИНЖИНИРИНГ"'
ORDER BY figurant_id DESC
-- LIMIT 100 OFFSET 0
;

-- ============================================================================
-- РАЗДЕЛ 6: МЕТАДАННЫЕ И ДИАГНОСТИКА
-- ============================================================================

-- Список индексов на таблицах ksk_result
SELECT
    tablename,
    indexname
FROM pg_catalog.pg_indexes
WHERE tablename LIKE 'ksk_result%'
ORDER BY tablename, indexname;

-- Список CHECK-ограничений (для проверки partition exclusion)
SELECT
    tc.table_name,
    tc.constraint_name,
    cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
    ON tc.constraint_name = cc.constraint_name
WHERE tc.table_name LIKE 'ksk_result%'
  AND tc.constraint_type = 'CHECK'
ORDER BY tc.table_name, tc.constraint_name;

-- Подсчёт записей по партициям
SELECT COUNT(*) FROM part_ksk_result_2025_10_21
UNION ALL
SELECT COUNT(*) FROM part_ksk_result_2025_10_22;

-- Проверка версии PostgreSQL
SELECT version();

-- ============================================================================
-- РАЗДЕЛ 7: ОБНОВЛЕНИЕ ДАННЫХ (СЛУЖЕБНОЕ)
-- ============================================================================

-- Обновление resolution на основе output_json
UPDATE part_ksk_result_2025_10_22
SET resolution = check_transaction_status(output_json);

-- ============================================================================
-- КОНЕЦ ФАЙЛА
-- ============================================================================
