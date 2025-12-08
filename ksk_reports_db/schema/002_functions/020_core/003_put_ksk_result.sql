-- ============================================================================
-- ФАЙЛ: 003_put_ksk_result_v4.1_bypass_detection.sql
-- ============================================================================
-- ОПИСАНИЕ:
-- Миграция функции put_ksk_result v4.1
-- ОПИСАНИЕ:
-- Миграция функции put_ksk_result с логированием ошибок БЕЗ отката транзакции
-- ВАЛИДАЦИЯ: одна проверка всех параметров, один INSERT при ошибке
--
-- ДАТА СОЗДАНИЯ: 31.10.2025 04:00 MSK
-- ВЕРСИЯ: 4.0
--
-- ИЗМЕНЕНИЯ ОТ ОРИГИНАЛА:
-- + Валидация всех 6 параметров через IF-ELSIF (чистый код)
-- + ОДИН INSERT в ksk_result_error при любой ошибке валидации
-- + ОДИН INSERT в ksk_result_error при runtime ошибке (EXCEPTION)
-- + RETURN -1 * error_id вместо RETURN -1 → возврат ID ошибки
--
-- ЛОГИКА ВАЛИДАЦИИ:
-- 1. Проверяем все параметры через IF-ELSIF
-- 2. Если хоть один NULL → сохраняем в v_validation_error
-- 3. Если v_validation_error NOT NULL → ОДИН INSERT + RETURN -error_id
-- 4. Иначе продолжаем обработку
--
-- ПРЕИМУЩЕСТВА:
-- ✅ Чистый код без дублирования
-- ✅ Один INSERT вместо 6 (экономия на IO)
-- ✅ Ошибка сохраняется в БД для анализа
-- ✅ Приложение получает -error_id и может запросить детали
-- ✅ Batch продолжается для других записей
--
-- ИНТЕГРАЦИЯ С JAVA SPRING:
-- Integer result = jdbcTemplate.queryForObject(...);
-- if (result <= 0) { 
--     int errorId = Math.abs(result);
--     errorCounter.increment();
-- }
--
-- ПАТТЕРНЫ ВЗЯТЫ ИЗ:
-- - ksk_result: Kafka metadata, партиционирование
-- - ksk_system_operations_log: error logging
-- 
-- ДАТА СОЗДАНИЯ: 17.11.2025 16:24 MSK
-- ВЕРСИЯ: 4.1
-- 
-- ИЗМЕНЕНИЯ ОТ v4.0:
-- + НОВАЯ ЛОГИКА: Анализ has_bypass на основе bypassName в фигурантах
-- + Безопасная проверка массива searchCheckResultKCKH
-- + Три сценария: yes / no / empty
-- ДАТА СОЗДАНИЯ: 17.11.2025 16:36 MSK
-- ВЕРСИЯ: 4.2
-- 
-- ИЗМЕНЕНИЯ ОТ v4.1:
-- + Добавляем bypass_name в INSERT ksk_figurant из JSON figuvant.bypassName
-- + БЕЗОПАСНАЯ логика: NULL если отсутствует или пусто
-- + Используем NULLIF для корректной обработки
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.put_ksk_result(
  p_input_timestamp TIMESTAMP(3),
  p_output_timestamp TIMESTAMP(3),
  p_input_json JSONB,
  p_output_json JSONB,
  p_input_kafka_partition INTEGER DEFAULT NULL,
  p_input_kafka_offset BIGINT DEFAULT NULL,
  p_input_kafka_headers JSONB DEFAULT NULL,
  p_output_kafka_headers JSONB DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $function$
DECLARE
  v_result_id INTEGER;
  v_error_id INTEGER;
  v_figurant_record RECORD;
  v_figurant_id INTEGER;
  v_match_record RECORD;
  
  -- JSONB переменные
  v_payment_info JSONB;
  v_payer_info JSONB;
  v_receiver_info JSONB;
  v_payer_bank_info JSONB;
  v_receiver_bank_info JSONB;
  v_header_info JSONB;
  v_search_results JSONB;
  
  -- Переменная для сообщения об ошибке валидации
  v_validation_error TEXT;
  v_error_text TEXT;
  
  -- NEW: Переменные для анализа has_bypass
  v_has_bypass VARCHAR(10);
  v_figurant_count INTEGER;
  v_has_bypass_with_value BOOLEAN;

  -- NEW v4.2: Переменная для bypass_name
  v_bypass_name TEXT;  
BEGIN

-- ========================================================================
-- ВАЛИДАЦИЯ ВСЕХ ПАРАМЕТРОВ (ОДНА ПРОВЕРКА)
-- v4.1: Возвращаем -ERROR_ID вместо -1
-- ========================================================================

v_validation_error := NULL;

IF p_input_timestamp IS NULL THEN
  v_validation_error := 'p_input_timestamp cannot be NULL';
ELSIF p_output_timestamp IS NULL THEN
  v_validation_error := 'p_output_timestamp cannot be NULL';
ELSIF p_input_json IS NULL THEN
  v_validation_error := 'p_input_json cannot be NULL (use empty JSON {})';
ELSIF p_output_json IS NULL THEN
  v_validation_error := 'p_output_json cannot be NULL (use empty JSON {})';
ELSIF p_input_kafka_partition IS NULL THEN
  v_validation_error := 'p_input_kafka_partition cannot be NULL (use -1 for unknown)';
ELSIF p_input_kafka_offset IS NULL THEN
  v_validation_error := 'p_input_kafka_offset cannot be NULL (use -1 for unknown)';
END IF;

-- Если есть ошибка валидации - логируем и возвращаем -ERROR_ID
IF v_validation_error IS NOT NULL THEN
  INSERT INTO upoa_ksk_reports.ksk_result_error (
    error_code,
    error_message,
    input_timestamp,
    output_timestamp,
    kafka_partition,
    kafka_offset,
    input_kafka_headers,
    output_kafka_headers,
    corr_id,
    input_json,
    output_json,
    function_context
  )
  VALUES (
    'PARAM_NULL',
    'Validation error: ' || v_validation_error,
    p_input_timestamp,
    p_output_timestamp,
    p_input_kafka_partition,
    p_input_kafka_offset,
    p_input_kafka_headers,
    p_output_kafka_headers,
    (p_output_json->'headerInfo'->>'corrId'),
    p_input_json,
    p_output_json,
    'put_ksk_result validation failed: ' || v_validation_error
  )
  RETURNING id INTO v_error_id;
  
  RETURN -1 * v_error_id;
END IF;

-- ========================================================================
-- ОСНОВНАЯ БИЗНЕС-ЛОГИКА
-- ========================================================================

-- ИЗВЛЕЧЕНИЕ JSONB ДАННЫХ
v_header_info := p_output_json->'headerInfo';
v_payment_info := p_input_json->'paymentInfo';
v_payer_info := p_input_json->'payerInfo';
v_receiver_info := p_input_json->'receiverInfo';
v_payer_bank_info := p_input_json->'payerBankInfo';
v_receiver_bank_info := p_input_json->'receiverBankInfo';
v_search_results := COALESCE(p_output_json->'searchCheckResultKCKH', '[]'::jsonb);

-- ========================================================================
-- NEW v4.1: АНАЛИЗ has_bypass НА ОСНОВЕ bypassName
-- ========================================================================
-- Логика:
-- 1. Если нет фигурантов (массив пуст) → has_bypass = 'empty'
-- 2. Если есть фигурант с непустым bypassName → has_bypass = 'yes'
-- 3. Если все bypassName пусты или отсутствуют → has_bypass = 'no'
-- ========================================================================

v_figurant_count := jsonb_array_length(v_search_results);

IF v_figurant_count = 0 THEN
  -- Сценарий 1: Фигурантов нет
  v_has_bypass := 'empty';
ELSE
  -- Сценарий 2 и 3: Ищем хоть один bypassName с непустым значением
  SELECT EXISTS(
    SELECT 1
    FROM jsonb_array_elements(v_search_results) AS elem
    WHERE (elem->>'bypassName') IS NOT NULL
      AND (elem->>'bypassName') != ''
    LIMIT 1
  ) INTO v_has_bypass_with_value;
  
  IF v_has_bypass_with_value THEN
    -- Сценарий 2: Найден хоть один непустой bypassName
    v_has_bypass := 'yes';
  ELSE
    -- Сценарий 3: Все bypassName пусты или отсутствуют
    v_has_bypass := 'no';
  END IF;
END IF;

-- 1) INSERT В ksk_result

INSERT INTO upoa_ksk_reports.ksk_result(
  date,
  corr_id,
  input_timestamp,
  output_timestamp,
  input_json,
  output_json,
  payment_type,
  resolution,
  has_bypass,
  list_codes,
  
  -- Поля платежа
  payment_id,
  payment_purpose,
  account_debet,
  account_credit,
  amount,
  currency,
  currency_control,
  
  -- Плательщик
  payer_inn,
  payer_name,
  payer_account_number,
  payer_document_type,
  payer_bank_name,
  payer_bank_account_number,
  
  -- Получатель
  receiver_account_number,
  receiver_name,
  receiver_inn,
  receiver_bank_name,
  receiver_bank_account_number,
  receiver_document_type,
  
  -- Kafka метаданные
  input_kafka_partition,
  input_kafka_offset,
  input_kafka_headers,
  output_kafka_headers
)
WITH list_codes_cte AS (
  SELECT COALESCE(array_agg(DISTINCT (elem->>'listCode')), '{}'::TEXT[]) AS codes
  FROM jsonb_array_elements(v_search_results) AS elem
  WHERE elem->>'listCode' IS NOT NULL
)
SELECT
  DATE(p_output_timestamp),
  v_header_info->>'corrId',
  p_input_timestamp,
  p_output_timestamp,
  p_input_json,
  p_output_json,
  v_payment_info->>'paymentType',
  upoa_ksk_reports.check_transaction_status(p_output_json),
  v_has_bypass,  -- НОВОЕ: Используем вычисленное значение вместо 'empty'
  lc.codes,
  
  -- Поля платежа
  COALESCE(v_payment_info->>'paymentId', ''),
  COALESCE(v_payment_info->>'paymentPurpose', ''),
  COALESCE(v_payment_info->>'accountDebet', ''),
  COALESCE(v_payment_info->>'accountCredit', ''),
  (v_payment_info->>'amount')::NUMERIC,
  COALESCE(v_payment_info->>'currency', ''),
  COALESCE(v_payment_info->>'currencyControl', ''),
  
  -- Плательщик
  COALESCE(v_payer_info->>'inn', ''),
  COALESCE(v_payer_info->>'name', ''),
  COALESCE(v_payer_info->>'accountNumber', ''),
  COALESCE(v_payer_info->>'documentType', ''),
  COALESCE(v_payer_bank_info->>'bankName', ''),
  COALESCE(v_payer_bank_info->>'accountNumber', ''),
  
  -- Получатель
  COALESCE(v_receiver_info->>'accountNumber', ''),
  COALESCE(v_receiver_info->>'name', ''),
  COALESCE(v_receiver_info->>'inn', ''),
  COALESCE(v_receiver_bank_info->>'bankName', ''),
  COALESCE(v_receiver_bank_info->>'accountNumber', ''),
  COALESCE(v_receiver_info->>'documentType', ''),
  
  -- Kafka метаданные
  p_input_kafka_partition,
  p_input_kafka_offset,
  p_input_kafka_headers,
  p_output_kafka_headers
FROM list_codes_cte lc
RETURNING id INTO v_result_id;

-- 2) INSERT В ksk_figurant

FOR v_figurant_record IN
  SELECT
    elem.value AS figurant_data,
    (elem.index - 1)::INTEGER AS figurant_index
  FROM jsonb_array_elements(v_search_results) WITH ORDINALITY AS elem(value, index)
LOOP
  -- NEW v4.2: БЕЗОПАСНОЕ извлечение bypass_name
  -- Логика: NULL если поле отсутствует ИЛИ пусто
  v_bypass_name := NULLIF(
    TRIM(COALESCE(v_figurant_record.figurant_data->>'bypassName', '')), 
    ''
  );
  INSERT INTO upoa_ksk_reports.ksk_figurant(
    source_id,
    date,
    timestamp,
    figurant,
    figurant_index,
    resolution,
    is_bypass,
    list_code,
    name_figurant,
    president_group,
    auto_login,
    has_exclusion,
    exclusion_phrase,
    exclusion_name_list,
	bypass_name  -- NEW v4.2
  )
  VALUES (
    v_result_id,
    DATE(p_output_timestamp),
    p_output_timestamp,
    v_figurant_record.figurant_data,
    v_figurant_record.figurant_index,
    upoa_ksk_reports.check_figurant_status(v_figurant_record.figurant_data),
    CASE WHEN v_bypass_name IS NOT NULL THEN 'yes' ELSE 'no' END,
    COALESCE(v_figurant_record.figurant_data->>'listCode', ''),
    COALESCE(v_figurant_record.figurant_data->>'nameFigurant', ''),
    COALESCE(v_figurant_record.figurant_data->>'presidentGroup', ''),
    COALESCE((v_figurant_record.figurant_data->>'autoLogin')::BOOLEAN, FALSE),
    COALESCE(
      jsonb_typeof(v_figurant_record.figurant_data->'searchCheckResultsExclusionList') = 'object'
      AND jsonb_array_length(
        v_figurant_record.figurant_data->'searchCheckResultsExclusionList'->'phrasesToExclude'
      ) > 0,
      FALSE
    ),
    COALESCE(
      (SELECT string_agg(elem, '; ')
       FROM jsonb_array_elements_text(
         v_figurant_record.figurant_data->'searchCheckResultsExclusionList'->'phrasesToExclude'
       ) AS elem),
      ''
    ),
    COALESCE(((((v_figurant_record.figurant_data)::jsonb)::jsonb)->'searchCheckResultsExclusionList'->'nameList')::text, ''),
	v_bypass_name  -- NEW v4.2: Значение bypass_name (может быть NULL)
  )
  RETURNING id INTO v_figurant_id;

  -- 3) INSERT В ksk_figurant_match

  IF jsonb_array_length(v_figurant_record.figurant_data->'match') > 0 THEN
    INSERT INTO upoa_ksk_reports.ksk_figurant_match(
      figurant_id,
      date,
      timestamp,
      match,
      match_index,
      algorithm,
      match_value,
      match_payment_field,
      match_payment_value
    )
    SELECT
      v_figurant_id,
      DATE(p_output_timestamp),
      p_output_timestamp,
      match_elem.value,
      (match_elem.index - 1)::INTEGER,
      COALESCE(match_elem.value->>'algorithm', 'unknown'),
      COALESCE(match_elem.value->>'value', ''),
      COALESCE(match_elem.value->>'paymentField', ''),
      COALESCE(match_elem.value->>'paymentValue', '')
    FROM jsonb_array_elements(v_figurant_record.figurant_data->'match')
      WITH ORDINALITY AS match_elem(value, index);
  END IF;
END LOOP;

RETURN v_result_id;

EXCEPTION
WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v_error_text = pg_exception_context;
  
  -- Обработка runtime ошибок с возвратом -ERROR_ID
  INSERT INTO upoa_ksk_reports.ksk_result_error (
    error_code,
    error_message,
    input_timestamp,
    output_timestamp,
    kafka_partition,
    kafka_offset,
    input_kafka_headers,
    output_kafka_headers,
    corr_id,
    input_json,
    output_json,
    function_context
  )
  VALUES (
    SQLSTATE,
    'Runtime error: ' || SQLERRM || '\n Stack: \n' || v_error_text,
    p_input_timestamp,
    p_output_timestamp,
    p_input_kafka_partition,
    p_input_kafka_offset,
    p_input_kafka_headers,
    p_output_kafka_headers,
    (p_output_json->'headerInfo'->>'corrId'),
    p_input_json,
    p_output_json,
    'put_ksk_result runtime error: ' || SQLERRM
  )
  RETURNING id INTO v_error_id;
  
  RETURN -1 * v_error_id;
END;

$function$;

-- ============================================================================
-- КОММЕНТАРИЙ НА ФУНКЦИЮ
-- ============================================================================

COMMENT ON FUNCTION upoa_ksk_reports.put_ksk_result(
  TIMESTAMP(3), TIMESTAMP(3), JSONB, JSONB, INTEGER, BIGINT, JSONB, JSONB
) IS 'Функция вставки данных КСК с логированием ошибок БЕЗ отката транзакции.

Версия: 4.1 от 17.11.2025

ВОЗВРАЩАЕМЫЕ ЗНАЧЕНИЯ:
  > 0 - ID вставленной записи (успех)
  < 0 - Отрицательный ERROR_ID из ksk_result_error (ошибка)
  = 0 - Зарезервировано

ВАЛИДАЦИЯ:
  Одна проверка всех 6 параметров через IF-ELSIF
  Один INSERT в ksk_result_error при любой ошибке

ЛОГИКА has_bypass (NEW v4.1):
  Анализирует массив searchCheckResultKCKH на наличие bypassName:
  
  1. Если фигурантов нет (массив пуст)
     → has_bypass = ''empty''
  
  2. Если есть хоть один фигурант с непустым bypassName
     → has_bypass = ''yes''
  
  3. Если есть фигуранты, но все bypassName пусты или отсутствуют
     → has_bypass = ''no''

ОБРАБОТКА ОШИБОК:
  - Валидация: error_code = PARAM_NULL, return = -ERROR_ID
  - Runtime: error_code = SQLSTATE, return = -ERROR_ID

ИНТЕГРАЦИЯ:
  if (result <= 0) {
    errorCounter.increment();
    log.error("Error ID: " + Math.abs(result));
  }';

-- ============================================================================
-- КОНЕЦ МИГРАЦИИ v4.1
-- ============================================================================
