-- ============================================================================
-- ФУНКЦИЯ: check_transaction_status
-- ============================================================================
-- ОПИСАНИЕ:
-- Определяет итоговое решение по транзакции на основе всех фигурантов.
--
-- Логика агрегации (приоритет сверху вниз):
-- ┌─────────────────────────────────┬─────────────┐
-- │ Условие                         │ Решение     │
-- ├─────────────────────────────────┼─────────────┤
-- │ Нет фигурантов                  │ empty       │
-- │ ВСЕ фигуранты bypass            │ bypass      │  ← NEW
-- │ Хотя бы один DENY (не bypass)   │ deny        │
-- │ Нет DENY, есть REVIEW           │ review      │
-- │ Все ALLOW                       │ allow       │
-- └─────────────────────────────────┴─────────────┘
--
-- ПАРАМЕТРЫ:
-- input_data (JSONB) - JSON транзакции с массивом фигурантов:
--   - searchCheckResultKCKH (JSONB[]): массив фигурантов
--
-- ВОЗВРАЩАЕТ:
-- TEXT - Итоговый статус: 'deny', 'review', 'allow', 'bypass', 'empty'
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
-- ~0.5-2ms (early exit оптимизация)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
-- 2025-10-27 - Оптимизация через early exit и кэширование
-- 2025-11-25 - Добавлена обработка bypass: исключенные фигуранты приравниваются к allow
-- 2025-11-26 - NEW: bypass как отдельный статус транзакции (все фигуранты bypass)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.check_transaction_status(input_data JSONB)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
    v_figurant          JSONB;
    v_figurant_status   TEXT;
    v_has_review        BOOLEAN := FALSE;
    v_has_allow         BOOLEAN := FALSE;
    v_all_bypass        BOOLEAN := TRUE;   -- NEW: флаг "все bypass"
    v_has_figurants     BOOLEAN := FALSE;  -- NEW: есть ли фигуранты вообще
BEGIN
    -- =========================================================================
    -- Проверка наличия массива фигурантов
    -- =========================================================================
    IF NOT (input_data ? 'searchCheckResultKCKH')
       OR jsonb_typeof(input_data->'searchCheckResultKCKH') != 'array' THEN
        RETURN 'empty';
    END IF;

    -- =========================================================================
    -- Основной цикл с early exit для DENY
    -- =========================================================================
    FOR v_figurant IN
        SELECT * FROM jsonb_array_elements(input_data->'searchCheckResultKCKH')
    LOOP
        v_has_figurants := TRUE;
        
        -- Проверка bypass: bypassName не пустой
        IF (v_figurant->>'bypassName') IS NOT NULL 
           AND (v_figurant->>'bypassName') != '' THEN
            -- Этот фигурант bypass, продолжаем проверять остальных
            CONTINUE;
        END IF;
        
        -- Если дошли сюда - фигурант НЕ bypass
        v_all_bypass := FALSE;
        
        v_figurant_status := check_figurant_status(v_figurant);

        -- Early exit: deny имеет наивысший приоритет
        IF v_figurant_status = 'deny' THEN
            RETURN 'deny';
        END IF;

        -- Флаги для агрегации остальных статусов
        IF v_figurant_status = 'review' THEN
            v_has_review := TRUE;
        ELSIF v_figurant_status = 'allow' THEN
            v_has_allow := TRUE;
        END IF;
    END LOOP;

    -- =========================================================================
    -- Агрегация результата
    -- =========================================================================
    
    -- Нет фигурантов → empty
    IF NOT v_has_figurants THEN
        RETURN 'empty';
    END IF;
    
    -- NEW: ВСЕ фигуранты bypass → bypass
    IF v_all_bypass THEN
        RETURN 'bypass';
    END IF;
    
    -- Стандартная логика приоритетов
    IF v_has_review THEN
        RETURN 'review';
    ELSIF v_has_allow THEN
        RETURN 'allow';
    ELSE
        RETURN 'empty';
    END IF;
END;
$function$;

-- ============================================================================
-- ТЕСТЫ
-- ============================================================================
/*
-- Тест 1: Нет фигурантов → empty
SELECT check_transaction_status('{}'::jsonb);                                    -- empty
SELECT check_transaction_status('{"searchCheckResultKCKH":[]}'::jsonb);          -- empty

-- Тест 2: Один фигурант allow → allow
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"presidentGroup":"part","autoLogin":false}
  ]
}'::jsonb);  -- allow

-- Тест 3: Один фигурант review → review  
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"presidentGroup":"full","autoLogin":false}
  ]
}'::jsonb);  -- review

-- Тест 4: deny всегда побеждает
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"presidentGroup":"part","autoLogin":false},
    {"presidentGroup":"unknown","autoLogin":false}
  ]
}'::jsonb);  -- deny

-- Тест 5: NEW - ВСЕ bypass → bypass
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"bypassName":"Тестовый bypass"},
    {"bypassName":"Ещё один bypass"}
  ]
}'::jsonb);  -- bypass

-- Тест 6: NEW - Смешанный (bypass + обычный) → обычная логика
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"bypassName":"Bypass фигурант"},
    {"presidentGroup":"full","autoLogin":false}
  ]
}'::jsonb);  -- review (bypass игнорируется, full+!autoLogin = review)

-- Тест 7: NEW - Bypass + allow → allow (bypass не участвует в агрегации)
SELECT check_transaction_status('{
  "searchCheckResultKCKH": [
    {"bypassName":"Bypass"},
    {"presidentGroup":"part","autoLogin":false}
  ]
}'::jsonb);  -- allow
*/
-- ============================================================================
-- КОНЕЦ ФАЙЛА
-- ============================================================================
