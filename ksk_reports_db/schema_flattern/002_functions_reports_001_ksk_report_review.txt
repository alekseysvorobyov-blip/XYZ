-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review
-- ============================================================================
-- ОПИСАНИЕ:
--   Формирует детальный отчёт по транзакциям, требующим ручной проверки (review)
--   Объединяет данные о транзакциях, фигурантах и совпадениях за указанную дату
--   Извлекает детализированную информацию из структурированных полей (не JSON)
--
-- ПАРАМЕТРЫ:
--   @report_date - Дата отчёта (по умолчанию: текущая дата)
--
-- ВОЗВРАЩАЕТ:
--   TABLE с 31 полем:
--     - Идентификация: corr_id, message_timestamp
--     - Совпадение: algorithm, match_value, match_payment_field, match_payment_value
--     - Фигурант: list_code, name_figurant, president_group, auto_login, exclusion данные
--     - Транзакция: transaction_resolution, figurant_resolition
--     - Платёж: payment_id, payment_purpose, account_debet, account_credit
--     - Плательщик: payer_inn, payer_name, payer_account_number, payer_document_type, payer_bank_*
--     - Получатель: receiver_account_number, receiver_name, receiver_inn, receiver_bank_*, receiver_document_type
--     - Сумма: amount, currency, currency_control
--     - Технические: match_id, figurant_id, transaction_id, rn (номер строки)
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_report_review('2025-10-22');
--   SELECT * FROM ksk_report_review(CURRENT_DATE);
--   
--   -- С фильтрацией
--   SELECT * FROM ksk_report_review('2025-10-22')
--   WHERE list_code = '4200' 
--     AND transaction_resolution = 'review';
--
-- ЗАМЕТКИ:
--   - Использует структурированные поля вместо JSON для повышения производительности
--   - Фильтрует только транзакции с resolution != 'empty'
--   - ROW_NUMBER партиционирует по match_id для устранения дубликатов
--   - Рекомендуется устанавливать work_mem = '256MB' для больших отчётов
--
-- ПРОИЗВОДИТЕЛЬНОСТЬ:
--   - Типичное время выполнения: ~2-5 сек на 280k строк
--   - Использует партиционирование для эффективной фильтрации по датам
--   - Оптимизировано под операции JOIN по timestamp и id
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Форматирование и документация
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review(
    report_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE (
    -- Идентификация
    corr_id                     TEXT,
    message_timestamp           TIMESTAMP(3),
    
    -- Информация о совпадении
    algorithm                   TEXT,
    match_value                 TEXT,
    match_payment_field         TEXT,
    match_payment_value         TEXT,
    
    -- Информация о фигуранте
    list_code                   TEXT,
    name_figurant               TEXT,
    president_group             TEXT,
    auto_login                  BOOLEAN,
    has_exclusion               BOOLEAN,
    exclusion_phrase            TEXT,
    exclusion_name_list         TEXT,
    is_bypass                   TEXT,
    
    -- Резолюции
    transaction_resolution      TEXT,
    figurant_resolition         TEXT,
    
    -- Платёжные данные
    payment_id                  TEXT,
    payment_purpose             TEXT,
    account_debet               TEXT,
    account_credit              TEXT,
    
    -- Информация о плательщике
    payer_inn                   TEXT,
    payer_name                  TEXT,
    payer_account_number        TEXT,
    payer_document_type         TEXT,
    payer_bank_name             TEXT,
    payer_bank_account_number   TEXT,
    
    -- Информация о получателе
    receiver_account_number     TEXT,
    receiver_name               TEXT,
    receiver_inn                TEXT,
    receiver_bank_name          TEXT,
    receiver_bank_account_number TEXT,
    receiver_document_type      TEXT,
    
    -- Финансовые данные
    amount                      TEXT,
    currency                    TEXT,
    currency_control            TEXT,
    
    -- Технические идентификаторы
    match_id                    BIGINT,
    figurant_id                 BIGINT,
    transaction_id              BIGINT,
    rn                          INTEGER
)
LANGUAGE SQL
STABLE
AS $$
    -- Фильтрация данных по дате отчёта
    WITH ksk_figurant_match_filtered AS (
        SELECT *
        FROM upoa_ksk_reports.ksk_figurant_match kfm
        WHERE kfm."timestamp" >= report_date 
          AND kfm."timestamp" < (report_date + INTERVAL '1 day')
    ),
    ksk_figurant_filtered AS (
        SELECT *
        FROM upoa_ksk_reports.ksk_figurant kf
        WHERE kf."timestamp" >= report_date 
          AND kf."timestamp" < (report_date + INTERVAL '1 day')
    ),
    ksk_result_filtered AS (
        SELECT *
        FROM upoa_ksk_reports.ksk_result kr
        WHERE kr.output_timestamp >= report_date 
          AND kr.output_timestamp < (report_date + INTERVAL '1 day')
          AND kr.resolution != 'empty'  -- Исключаем пустые транзакции
    )
    
    -- Основной запрос с объединением всех данных
    SELECT
        -- Идентификация транзакции
        rf.corr_id,
        rf.output_timestamp AS message_timestamp,
        
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
        
        -- Платёжные данные (из структурированных полей)
        rf.payment_id,
        rf.payment_purpose,
        rf.account_debet,
        rf.account_credit,
        
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
        rf.id AS transaction_id,
        
        -- Нумерация для устранения дубликатов
        ROW_NUMBER() OVER (PARTITION BY mf.id) AS rn
        
    FROM ksk_figurant_match_filtered mf
    JOIN ksk_figurant_filtered ff 
        ON mf.figurant_id = ff.id 
       AND mf."timestamp" = ff."timestamp"
    JOIN ksk_result_filtered rf 
        ON ff.source_id = rf.id 
       AND ff."timestamp" = rf.output_timestamp
$$;

COMMENT ON FUNCTION ksk_report_review(DATE) IS 
    'Формирует детальный отчёт по транзакциям review за указанную дату. Использует структурированные поля для оптимальной производительности';
