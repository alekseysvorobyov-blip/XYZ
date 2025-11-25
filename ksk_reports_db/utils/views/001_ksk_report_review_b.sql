-- ============================================================================
-- ЗАПРОС: Большой отчёт review (вариант со структурированными полями)
-- ============================================================================
-- ОПИСАНИЕ:
--   Детальный отчёт по транзакциям review с использованием структурированных полей
--   Максимальная производительность за счёт прямого доступа к колонкам
--
-- ПАРАМЕТРЫ:
--   Замените '2025-10-21' и '2025-10-22' на нужные даты
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   ✅ РЕКОМЕНДУЕТСЯ: В 5-10 раз быстрее версии с JSON
--   Используйте этот вариант для регулярных отчётов и больших выборок
--
-- ЗАМЕТКИ:
--   - Требует наличия структурированных полей в ksk_result
--   - Оптимизировано под работу с партиционированием
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
      AND kr.resolution != 'empty'  -- Фильтруем пустые транзакции
)

-- Основной запрос со структурированными полями
SELECT
    -- Идентификация транзакции
    rf.corr_id,
    rf.output_timestamp,
    
    -- Информация о совпадении
    mf.algorithm,
    mf.match_value,
    mf.match_payment_field,
    mf.match_payment_value,
    
    -- Информация о фигуранте
    ff.list_code,
    ff.name_figurant,
    ff.president_group,
    ff.auto_login,
    ff.has_exclusion,
    ff.exclusion_phrase,
    ff.exclusion_name_list,
    ff.is_bypass,
    
    -- Резолюции
    rf.resolution AS transaction_resolution,
    ff.resolution AS figurant_resolition,
    
    -- ========================================================================
    -- ПЛАТЁЖНЫЕ ДАННЫЕ (структурированные поля)
    -- ========================================================================
    
    -- Основная информация о платеже
    rf.payment_id,
    rf.payment_purpose,
    rf.account_debet,
    rf.account_сredit,
    
    -- Информация о плательщике
    rf.payer_inn,
    rf.payer_name,
    rf.payer_account_number,
    rf.payer_document_type,
    rf.payer_bank_name,
    rf.payer_bank_account_number,
    
    -- Информация о получателе
    rf.receiver_account_number,
    rf.receiver_name,
    rf.receiver_inn,
    rf.receiver_bank_name,
    rf.receiver_bank_account_number,
    rf.receiver_document_type,
    
    -- Финансовые данные
    rf.amount,
    rf.currency,
    rf.currency_control,
    
    -- Технические идентификаторы
    mf.id AS match_id,
    ff.id AS figurant_id,
    rf.id AS transaction_id

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
