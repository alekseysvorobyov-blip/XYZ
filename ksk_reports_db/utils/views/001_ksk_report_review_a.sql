-- ============================================================================
-- ЗАПРОС: Большой отчёт review (вариант с извлечением из JSON)
-- ============================================================================
-- ОПИСАНИЕ:
--   Детальный отчёт по транзакциям review с извлечением данных из JSON-полей
--   Используется для ad-hoc анализа или когда структурированные поля недоступны
--
-- ПАРАМЕТРЫ:
--   Замените '2025-10-21' и '2025-10-22' на нужные даты
--
-- ВОЗВРАЩАЕТ:
--   Детализированный набор данных по каждой транзакции:
--   - Идентификация и временные метки
--   - Информация о совпадениях и фигурантах
--   - Полная информация о платеже (извлечение из input_json)
--   - Данные плательщика и получателя
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   ⚠️ ВНИМАНИЕ: Извлечение из JSON медленнее структурированных полей
--   Рекомендуется для разовых запросов, не для регулярных отчётов
--
-- ЗАМЕТКИ:
--   - Закомментированы поля input_json, output_json, figurant, match для экономии памяти
--   - Для получения полных JSON раскомментируйте последние строки SELECT
-- ============================================================================

-- Фильтрация данных по периоду
WITH ksk_figurant_match_filtered AS (
    SELECT *
    FROM ksk_figurant_match kfm
    WHERE kfm."timestamp" >= '2025-10-21'::DATE 
      AND kfm."timestamp" < '2025-10-22'::DATE
),
ksk_figurant_filtered AS (
    SELECT *
    FROM ksk_figurant kf
    WHERE kf."timestamp" >= '2025-10-21'::DATE 
      AND kf."timestamp" < '2025-10-22'::DATE
),
ksk_result_filtered AS (
    SELECT *
    FROM ksk_result kr
    WHERE kr.output_timestamp >= '2025-10-21'::DATE 
      AND kr.output_timestamp < '2025-10-22'::DATE
)

-- Основной запрос с извлечением из JSON
SELECT
    -- Идентификация транзакции
    rf.corr_id,
    rf.output_timestamp,
    
    -- Информация о совпадении (из JSON в ksk_figurant_match)
    mf.algorithm,
    COALESCE(mf.match->>'value', '') AS match_value,
    COALESCE(mf.match->>'paymentField', '') AS match_payment_field,
    COALESCE(mf.match->>'paymentValue', '') AS match_payment_value,
    
    -- Информация о фигуранте (из JSON в ksk_figurant)
    COALESCE(ff.figurant->>'listCode', '') AS list_code,
    COALESCE(ff.figurant->>'nameFigurant', '') AS name_figurant,
    COALESCE(ff.figurant->>'presidentGroup', '') AS president_group,
    COALESCE(ff.figurant->>'autoLogin', '') AS auto_login,
    
    -- Информация об исключениях
    LENGTH(
        COALESCE(
            (SELECT STRING_AGG(elem, ';') 
             FROM JSONB_ARRAY_ELEMENTS_TEXT(ff.figurant->'searchCheckResultsExclusionList'->'phrasesToExclude') AS elem),
            ''
        )
    ) > 0 AS has_exclusion,
    COALESCE(
        (SELECT STRING_AGG(elem, ';') 
         FROM JSONB_ARRAY_ELEMENTS_TEXT(ff.figurant->'searchCheckResultsExclusionList'->'phrasesToExclude') AS elem),
        ''
    ) AS exclusion_phrase,
    COALESCE(ff.figurant->'searchCheckResultsExclusionList'->>'nameList', '') AS exclusion_name_list,
    
    -- Резолюции и bypass
    ff.is_bypass,
    rf.resolution AS transaction_resolution,
    ff.resolution AS figurant_resolition,
    
    -- ========================================================================
    -- ПЛАТЁЖНЫЕ ДАННЫЕ (извлечение из input_json)
    -- ========================================================================
    
    -- Основная информация о платеже
    COALESCE(rf.input_json->'paymentInfo'->>'paymentId', '') AS payment_id,
    COALESCE(rf.input_json->'paymentInfo'->>'paymentPurpose', '') AS payment_purpose,
    COALESCE(rf.input_json->'paymentInfo'->>'accountDebet', '') AS account_debet,
    COALESCE(rf.input_json->'paymentInfo'->>'accountCredit', '') AS account_сredit,
    
    -- Информация о плательщике
    COALESCE(rf.input_json->'payerInfo'->>'payerInn', '') AS payer_inn,
    COALESCE(rf.input_json->'payerInfo'->>'payerName', '') AS payer_name,
    COALESCE(rf.input_json->'payerInfo'->'payerAccountInfo'->>'payerAccountNumber', '') AS payer_account_number,
    COALESCE(
        (SELECT STRING_AGG(elem->>'documentType', ';') 
         FROM JSONB_ARRAY_ELEMENTS(rf.input_json->'payerInfo'->'documents') AS elem),
        ''
    ) AS payer_document_type,
    COALESCE(rf.input_json->'payerBankInfo'->>'payerBankName', '') AS payer_bank_name,
    COALESCE(rf.input_json->'payerBankInfo'->>'payerBankAccountNumber', '') AS payer_bank_account_number,
    
    -- Информация о получателе
    COALESCE(rf.input_json->'receiverInfo'->'receiverAccountInfo'->>'receiverAccountNumber', '') AS receiver_account_number,
    COALESCE(rf.input_json->'receiverInfo'->>'receiverName', '') AS receiver_name,
    COALESCE(rf.input_json->'receiverInfo'->>'receiverInn', '') AS receiver_inn,
    COALESCE(rf.input_json->'receiverBankInfo'->>'receiverBankName', '') AS receiver_bank_name,
    COALESCE(rf.input_json->'receiverBankInfo'->>'receiverBankAccountNumber', '') AS receiver_bank_account_number,
    COALESCE(
        (SELECT STRING_AGG(elem->>'documentType', ';') 
         FROM JSONB_ARRAY_ELEMENTS(rf.input_json->'receiverInfo'->'documents') AS elem),
        ''
    ) AS receiver_document_type,
    
    -- Финансовые данные
    COALESCE(rf.input_json->'paymentInfo'->>'amount', '') AS amount,
    COALESCE(rf.input_json->'paymentInfo'->>'currency', '') AS currency,
    COALESCE(rf.input_json->'paymentInfo'->>'currencyControl', '') AS currency_control
    
    -- ========================================================================
    -- ОПЦИОНАЛЬНО: Полные JSON (раскомментировать при необходимости)
    -- ========================================================================
    /*
    ,rf.input_json,
    rf.output_json,
    ff.figurant,
    mf.match
    */

FROM ksk_figurant_match_filtered mf
JOIN ksk_figurant_filtered ff 
    ON mf.figurant_id = ff.id
JOIN ksk_result_filtered rf 
    ON ff.source_id = rf.id
    
WHERE 1 = 1
    -- Дополнительные фильтры (опционально)
    -- AND rf.resolution = 'review'
    -- AND ff.list_code IN ('4200', '4204')

ORDER BY rf.id DESC;
