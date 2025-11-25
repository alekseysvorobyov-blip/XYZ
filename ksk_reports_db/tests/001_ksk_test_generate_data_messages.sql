-- ============================================================================
-- Функция генерации тестовых пар JSON (input + output) для системы КСК v3
-- ============================================================================
-- ИСПРАВЛЕНИЯ v3:
--   1. У ВСЕХ фигурантов ВСЕГДА есть совпадения (99% → 1, 1% → 2-4)
--   2. Исправлены тестовые запросы (VOLATILE для множественных вызовов)
-- Создано на основе: input.json, output.json, output_2figurants.json
-- Справочник: KSK-Schema-Reference-v2.md v2.0
-- PostgreSQL: 16
-- Дата: 2025-10-30
-- Версия: 3 (финальная, правильная логика)
-- 
-- СТАТИСТИКА СИСТЕМЫ (3М транзакций/день):
-- • 100% транзакций на вход
-- • 30% с результатами проверки (900К/день)
-- • 20% с 1 фигурантом (600К/день)
-- • 10% с 2-4 фигурантами (300К/день)
-- • У ВСЕХ фигурантов есть совпадения: 99% → 1 совпадение, 1% → 2-4 совпадения
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_test_generate_data_messages()
RETURNS TABLE(
    input_json JSONB,
    output_json JSONB
)
LANGUAGE plpgsql
VOLATILE  -- ВАЖНО: позволяет вызывать функцию множество раз с разными результатами
AS $$
DECLARE
    v_corr_id TEXT := gen_random_uuid()::TEXT;
    v_payment_id TEXT := gen_random_uuid()::TEXT;
    v_msg_datetime TEXT := (NOW() + (random() * interval '1 hour'))::TIMESTAMP(3)::TEXT;
    v_trans_datetime TEXT := (NOW() - (random() * interval '24 hours'))::TIMESTAMP(3)::TEXT;
    v_payment_date TEXT := (CURRENT_DATE - (random() * 30)::INTEGER)::TEXT;
    
    -- Случайные реалистичные данные
    v_client_id TEXT := (1000000000000 + (random() * 999999999999)::BIGINT)::TEXT;
    v_receiver_id TEXT := (9990000000000 + (random() * 9999999999)::BIGINT)::TEXT;
    v_amount TEXT := (10 + random() * 99990)::NUMERIC(10,2)::TEXT;
    v_inn_payer TEXT := (7700000000 + (random() * 299999999)::BIGINT)::TEXT;
    v_inn_receiver TEXT := (7700000000 + (random() * 299999999)::BIGINT)::TEXT;
    v_account_debet TEXT := '4082881' || lpad((random() * 9999999999999)::BIGINT::TEXT, 13, '0');
    v_account_credit TEXT := '4082881' || lpad((random() * 9999999999999)::BIGINT::TEXT, 13, '0');
    v_bic_payer TEXT := '04452' || lpad((random() * 9999)::INTEGER::TEXT, 4, '0');
    v_bic_receiver TEXT := '04452' || lpad((random() * 9999)::INTEGER::TEXT, 4, '0');
    
    -- Массивы реалистичных названий
    v_payer_names TEXT[] := ARRAY[
        'ПАО БАНК ВТБ', 'ПАО СБЕРБАНК', 'АО АЛЬФА-БАНК', 'АО РАЙФФАЙЗЕНБАНК',
        'ПАО МОСКОВСКИЙ КРЕДИТНЫЙ БАНК', 'АО РОСБАНК', 'ПАО БАНК УРАЛСИБ',
        'Т-БАНК', 'ПАО ПРОМСВЯЗЬБАНК', 'АО ЮНИКРЕДИТ БАНК'
    ];
    v_receiver_names TEXT[] := ARRAY[
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ ТЕХНО-ТЕМП',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ СТРОЙ-КОМПЛЕКС',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ АЛЬФА-ТРАНС',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ МЕГА-ТОРГ',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ БИЗНЕС-СЕРВИС',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ ИНВЕСТ-ХОЛДИНГ',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ ПРОГРЕСС-АВТО',
        'ОБЩЕСТВО С ОГРАНИЧЕННОЙ ОТВЕТСТВЕННОСТЬЮ ЭКСПЕРТ-ГРУПП'
    ];
    v_purposes TEXT[] := ARRAY[
        'оплата по договору', 'вознаграждение', 'аренда помещения',
        'поставка товара', 'оказание услуг', 'пополнение счета',
        'возврат займа', 'консультационные услуги', 'транспортные услуги'
    ];
    v_payment_types TEXT[] := ARRAY['Входящий', 'Исходящий', 'Транзитный', 'Межфилиальный', 'Внутрифилиальный'];
    
    v_payer_name TEXT := v_payer_names[1 + floor(random() * array_length(v_payer_names, 1))];
    v_receiver_name TEXT := v_receiver_names[1 + floor(random() * array_length(v_receiver_names, 1))];
    v_purpose TEXT := v_purposes[1 + floor(random() * array_length(v_purposes, 1))];
    v_payment_type TEXT := v_payment_types[1 + floor(random() * array_length(v_payment_types, 1))];
    
    -- Определяем будет ли результат (30% вероятность)
    v_has_result BOOLEAN := random() < 0.3;
    v_figurants_count INTEGER := 0;
    v_output JSONB;
    v_figurants JSONB[] := ARRAY[]::JSONB[];
    
    -- Фигуранты и совпадения
    v_figurant_names TEXT[] := ARRAY[
        'Суда', 'КУБА', 'Текущий счет резидентов физических лиц',
        'ИРАН', 'СЕВЕРНАЯ КОРЕЯ', 'Военная техника', 'Оружие',
        'Наркотические вещества', 'Территории', 'Банки из списка'
    ];
    v_list_codes TEXT[] := ARRAY['4200', '4201', '4204', '2002', '2003'];
    v_algorithms TEXT[] := ARRAY['SEARCH_WORDS_DOPB', 'CROSSBORDER_TRANSFERS', 'COMMISSION_DECISION', 'ACCOUNT_MATCH'];
    v_payment_fields TEXT[] := ARRAY['paymentPurpose', 'payerAccountNumber', 'receiverName', 'accountDebet'];
    
BEGIN
    -- Определяем количество фигурантов если есть результат
    IF v_has_result THEN
        IF random() < 0.667 THEN  -- 20/30 = 66.7% случаев с результатом имеют 1 фигуранта
            v_figurants_count := 1;
        ELSE  -- 10/30 = 33.3% случаев имеют 2-4 фигуранта
            v_figurants_count := 2 + floor(random() * 3)::INTEGER;
        END IF;
        
        -- Генерируем фигурантов
        FOR i IN 1..v_figurants_count LOOP
            DECLARE
                -- У ВСЕХ фигурантов ЕСТЬ совпадения
                v_matches_count INTEGER := CASE WHEN random() < 0.99 THEN 1 ELSE 2 + floor(random() * 3)::INTEGER END;
                v_matches JSONB[] := ARRAY[]::JSONB[];
                v_figurant_name TEXT := v_figurant_names[1 + floor(random() * array_length(v_figurant_names, 1))];
            BEGIN
                -- Генерируем совпадения (ВСЕГДА, для каждого фигуранта)
                FOR j IN 1..v_matches_count LOOP
                    v_matches := array_append(v_matches, jsonb_build_object(
                        'algorithm', v_algorithms[1 + floor(random() * array_length(v_algorithms, 1))],
                        'paymentField', v_payment_fields[1 + floor(random() * array_length(v_payment_fields, 1))],
                        'paymentValue', v_purpose,
                        'value', lower(split_part(v_purpose, ' ', 1))
                    ));
                END LOOP;
                
                -- Добавляем фигуранта (ВСЕГДА с совпадениями)
                v_figurants := array_append(v_figurants, jsonb_build_object(
                    'objectType', (1 + floor(random() * 6)::INTEGER)::TEXT,
                    'nameFigurant', v_figurant_name,
                    'currency', '',
                    'thresholdAmount', '',
                    'idRecord', (1 + floor(random() * 10)::INTEGER)::TEXT,
                    'recType', CASE WHEN random() < 0.5 THEN '' ELSE 'ЮЛ' END,
                    'searchValuePhrase', '',
                    'taxNumber', '',
                    'bic', '',
                    'account', CASE WHEN random() < 0.3 THEN '40817' ELSE '' END,
                    'altChannel', 'да',
                    'birthYear', '',
                    'birthDate', '',
                    'citizenship', '',
                    'birthPlace', '',
                    'addrReg', '',
                    'regDate', '',
                    'location', '',
                    'docSerOkpo', '',
                    'docNumOgrn', '',
                    'docDetails', '',
                    'addInfo', '',
                    'dateIn', '',
                    'dateOut', '',
                    'swift', '',
                    'extraParam1', '',
                    'extraParam2', '',
                    'hashSum', md5(random()::TEXT),
                    'presidentGroup', CASE 
                        WHEN random() < 0.9 THEN 'none'
                        WHEN random() < 0.5 THEN 'part'
                        ELSE 'full'
                    END,
                    'match', to_jsonb(v_matches),  -- ВСЕГДА заполнен (минимум 1 элемент)
                    'autoLogin', random() < 0.1,
                    'listCode', v_list_codes[1 + floor(random() * array_length(v_list_codes, 1))]
                ));
            END;
        END LOOP;
    END IF;
    
    -- Формируем INPUT JSON
    input_json := jsonb_build_object(
        'headerInfo', jsonb_build_object(
            'corrId', v_corr_id,
            'source', '1388_ALPP',
            'version', '1.0',
            'msgDateTime', v_msg_datetime
        ),
        'paymentInfo', jsonb_build_object(
            'operationKind', '1388.0006.0001',
            'channel', 'TP',
            'paymentId', v_payment_id,
            'transactionDateTime', v_trans_datetime,
            'paymentType', v_payment_type,
            'documentCode', '01',
            'paymentNumber', (1000000000 + (random() * 999999999)::BIGINT)::TEXT,
            'paymentDate', v_payment_date,
            'amount', v_amount,
            'currency', 'RUB',
            'operationType', '01',
            'paymentPurpose', v_purpose,
            'paymentPriority', '5',
            'accountDebet', v_account_debet,
            'accountCredit', v_account_credit
        ),
        'payerInfo', jsonb_build_object(
            'clientId', v_client_id,
            'mdmSystemCode', '1498',
            'clientType', (3 + floor(random() * 2)::INTEGER)::TEXT,
            'payerName', v_payer_name,
            'payerInn', v_inn_payer,
            'payerAccountInfo', jsonb_build_object(
                'purpose', 'счет требований 47423',
                'payerAccountNumber', v_account_debet
            )
        ),
        'receiverInfo', jsonb_build_object(
            'clientId', v_receiver_id,
            'mdmSystemCode', '1498',
            'clientType', '3',
            'receiverMessageInfo', 'receiverMessageInfo',
            'receiverName', v_receiver_name,
            'receiverInn', v_inn_receiver,
            'receiverAccountInfo', jsonb_build_object(
                'purpose', 'счет требований 47423',
                'receiverAccountNumber', v_account_credit
            ),
            'documents', '[]'::JSONB
        ),
        'payerBankInfo', jsonb_build_object(
            'payerBankName', v_payer_name,
            'payerBankBic', v_bic_payer,
            'payerBankAccountNumber', '3010281' || lpad((random() * 9999999999999)::BIGINT::TEXT, 13, '0')
        ),
        'receiverBankInfo', jsonb_build_object(
            'receiverBankInfo', 'receiverBankInfo',
            'receiverBankName', 'ФИЛИАЛ ЮЖНЫЙ ПАО БАНК УРАЛСИБ',
            'receiverBankBic', v_bic_receiver,
            'receiverBankAccountNumber', '3010281' || lpad((random() * 9999999999999)::BIGINT::TEXT, 13, '0')
        ),
        'mediatorBankInfo', jsonb_build_object(
            'mediatorBankInfo', 'mediatorBankInfo',
            'mediatorBankName', 'FILIAL',
            'mediatorBankBic', '044555555',
            'mediatorBankAccountNumber', '30102810145250000411'
        )
    );
    
    -- Формируем OUTPUT JSON
    output_json := jsonb_build_object(
        'errors', '[]'::JSONB,
        'headerInfo', jsonb_build_object(
            'requestId', NULL,
            'corrId', v_corr_id,  -- КОНСИСТЕНТНОСТЬ: тот же corrId что в input
            'requestMsgDateTime', v_msg_datetime
        ),
        'searchCheckResultKCKH', to_jsonb(v_figurants),
        'presidentGroupsKCKH', '[]'::JSONB
    );
    
    RETURN NEXT;
END;
$$;

-- Комментарии
COMMENT ON FUNCTION upoa_ksk_reports.ksk_test_generate_data_messages() IS 
'Генерирует пару консистентных JSON (input + output) для тестирования системы КСК.
ФИНАЛЬНАЯ ВЕРСИЯ v3:
  • У ВСЕХ фигурантов ВСЕГДА есть совпадения: 99% → 1, 1% → 2-4
  • VOLATILE для корректной работы в циклах
  • Префикс: ksk_test_generate_data_* для всех тестовых функций генерации данных
Статистика: 3М транзакций/день, 30% с результатами.
Возвращает: input_json (JSONB), output_json (JSONB) с одинаковым corrId.';

-- ============================================================================
-- ПРИМЕРЫ ИСПОЛЬЗОВАНИЯ (ИСПРАВЛЕННЫЕ!)
-- ============================================================================

-- ❌ НЕПРАВИЛЬНО (повторяет результат 100 раз):
-- SELECT * FROM generate_series(1, 100), 
--        LATERAL upoa_ksk_reports.ksk_test_generate_data_messages();

-- ✅ ПРАВИЛЬНО: Генерация одной пары
-- SELECT * FROM upoa_ksk_reports.ksk_test_generate_data_messages();

-- ✅ ПРАВИЛЬНО: Генерация 100 РАЗНЫХ пар (цикл в plpgsql)
-- DO $$
-- DECLARE
--     rec RECORD;
-- BEGIN
--     FOR i IN 1..100 LOOP
--         SELECT * INTO rec FROM upoa_ksk_reports.ksk_test_generate_data_messages();
--         -- Обработка rec.input_json и rec.output_json
--     END LOOP;
-- END $$;

-- ✅ ПРАВИЛЬНО: Генерация 100 пар в таблицу (WITH RECURSIVE)
-- WITH RECURSIVE generate AS (
--     SELECT 1 as n, t.* FROM upoa_ksk_reports.ksk_test_generate_data_messages() t
--     UNION ALL
--     SELECT n+1, t.* FROM generate, upoa_ksk_reports.ksk_test_generate_data_messages() t
--     WHERE n < 100
-- )
-- SELECT input_json, output_json FROM generate;

-- ✅ ПРАВИЛЬНО: Простейший способ - вызов в цикле приложения
-- Вызывайте функцию N раз из приложения (Go/Java/Python):
-- for i := 0; i < 100; i++ {
--     row := db.QueryRow("SELECT * FROM upoa_ksk_reports.ksk_test_generate_data_messages()")
-- }

-- ✅ ПРАВИЛЬНО: Генерация с сохранением в временную таблицу
-- CREATE TEMP TABLE test_messages (
--     id SERIAL PRIMARY KEY,
--     input_json JSONB,
--     output_json JSONB
-- );
-- 
-- DO $$
-- DECLARE
--     rec RECORD;
-- BEGIN
--     FOR i IN 1..1000 LOOP
--         SELECT * INTO rec FROM upoa_ksk_reports.ksk_test_generate_data_messages();
--         INSERT INTO test_messages (input_json, output_json) 
--         VALUES (rec.input_json, rec.output_json);
--     END LOOP;
-- END $$;

-- Проверка распределения фигурантов (ПОСЛЕ вставки в таблицу):
-- SELECT 
--     jsonb_array_length(output_json->'searchCheckResultKCKH') as figurants_count,
--     COUNT(*) as transactions_count,
--     ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) || '%' as percentage
-- FROM test_messages
-- GROUP BY figurants_count
-- ORDER BY figurants_count;
-- 
-- Ожидаемый результат:
-- figurants_count | transactions_count | percentage
-- ----------------+--------------------+------------
-- 0               | ~700               | 70.0%
-- 1               | ~200               | 20.0%
-- 2               | ~33                | 3.3%
-- 3               | ~33                | 3.3%
-- 4               | ~33                | 3.3%

-- Проверка совпадений у фигурантов (ПОСЛЕ вставки в таблицу):
-- WITH figurants AS (
--     SELECT jsonb_array_elements(output_json->'searchCheckResultKCKH') as figurant
--     FROM test_messages
--     WHERE jsonb_array_length(output_json->'searchCheckResultKCKH') > 0
-- )
-- SELECT 
--     jsonb_array_length(figurant->'match') as matches_count,
--     COUNT(*) as figurants_count,
--     ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) || '%' as percentage
-- FROM figurants
-- GROUP BY matches_count
-- ORDER BY matches_count;
--
-- Ожидаемый результат:
-- matches_count | figurants_count | percentage
-- --------------+-----------------+------------
-- 1             | ~495            | 99.0%
-- 2             | ~2              | 0.33%
-- 3             | ~2              | 0.33%
-- 4             | ~2              | 0.33%
