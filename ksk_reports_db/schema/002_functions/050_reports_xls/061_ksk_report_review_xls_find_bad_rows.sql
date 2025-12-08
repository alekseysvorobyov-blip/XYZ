-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_xls_find_bad_rows (ДИАГНОСТИЧЕСКАЯ)
-- ============================================================================
-- ОПИСАНИЕ:
--   Находит строки в данных review, которые содержат невалидные XML символы
--   Используется для диагностики ошибок "invalid XML content"
--
-- ПАРАМЕТРЫ:
--   @p_report_date - Дата отчёта
--   @p_limit       - Максимум строк для проверки (по умолчанию 1000)
--
-- ВОЗВРАЩАЕТ:
--   TABLE с проблемными строками и информацией о невалидных символах
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание диагностической функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_xls_find_bad_rows(
    p_report_date DATE,
    p_limit INTEGER DEFAULT 1000
)
RETURNS TABLE (
    row_num         BIGINT,
    corr_id         TEXT,
    field_name      TEXT,
    field_value     TEXT,
    bad_char_codes  TEXT
) AS $$
DECLARE
    v_rec RECORD;
    v_row_num BIGINT := 0;
    v_fields TEXT[];
    v_values TEXT[];
    v_i INTEGER;
    v_char_code INTEGER;
    v_bad_codes TEXT;
    v_j INTEGER;
    v_val TEXT;
BEGIN
    -- Список полей для проверки
    v_fields := ARRAY[
        'corr_id', 'algorithm', 'match_value', 'match_payment_field', 'match_payment_value',
        'list_code', 'name_figurant', 'president_group', 'exclusion_phrase', 'exclusion_name_list',
        'is_bypass', 'transaction_resolution', 'figurant_resolition', 'payment_id', 'payment_purpose',
        'account_debet', 'account_credit', 'payer_inn', 'payer_name', 'payer_account_number',
        'payer_document_type', 'payer_bank_name', 'payer_bank_account_number', 'receiver_account_number',
        'receiver_name', 'receiver_inn', 'receiver_bank_name', 'receiver_bank_account_number',
        'receiver_document_type', 'amount', 'currency', 'currency_control'
    ];

    FOR v_rec IN
        SELECT *
        FROM upoa_ksk_reports.ksk_report_review(p_report_date)
        WHERE rn = 1
        LIMIT p_limit
    LOOP
        v_row_num := v_row_num + 1;

        -- Собираем значения полей
        v_values := ARRAY[
            v_rec.corr_id, v_rec.algorithm, v_rec.match_value, v_rec.match_payment_field, v_rec.match_payment_value,
            v_rec.list_code, v_rec.name_figurant, v_rec.president_group, v_rec.exclusion_phrase, v_rec.exclusion_name_list,
            v_rec.is_bypass, v_rec.transaction_resolution, v_rec.figurant_resolition, v_rec.payment_id, v_rec.payment_purpose,
            v_rec.account_debet, v_rec.account_credit, v_rec.payer_inn, v_rec.payer_name, v_rec.payer_account_number,
            v_rec.payer_document_type, v_rec.payer_bank_name, v_rec.payer_bank_account_number, v_rec.receiver_account_number,
            v_rec.receiver_name, v_rec.receiver_inn, v_rec.receiver_bank_name, v_rec.receiver_bank_account_number,
            v_rec.receiver_document_type, v_rec.amount, v_rec.currency, v_rec.currency_control
        ];

        -- Проверяем каждое поле на невалидные символы
        FOR v_i IN 1..array_length(v_fields, 1) LOOP
            v_val := v_values[v_i];
            IF v_val IS NOT NULL AND v_val != '' THEN
                v_bad_codes := '';

                -- Проверяем каждый символ
                FOR v_j IN 1..length(v_val) LOOP
                    v_char_code := ascii(substr(v_val, v_j, 1));

                    -- Проверяем на недопустимые XML символы
                    IF v_char_code < 32 AND v_char_code NOT IN (9, 10, 13) THEN
                        v_bad_codes := v_bad_codes || v_char_code::TEXT || ',';
                    END IF;
                END LOOP;

                -- Если нашли плохие символы - возвращаем
                IF v_bad_codes != '' THEN
                    row_num := v_row_num;
                    corr_id := v_rec.corr_id;
                    field_name := v_fields[v_i];
                    field_value := left(v_val, 100);  -- Первые 100 символов
                    bad_char_codes := rtrim(v_bad_codes, ',');
                    RETURN NEXT;
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_xls_find_bad_rows(DATE, INTEGER) IS
    'Диагностическая функция для поиска строк с невалидными XML символами в данных review';


-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_xls_test_xml (ДИАГНОСТИЧЕСКАЯ)
-- ============================================================================
-- Проверяет можно ли сконвертировать строку в XML
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_xls_test_xml(
    p_report_date DATE,
    p_batch_size INTEGER DEFAULT 1000
)
RETURNS TABLE (
    batch_num       INTEGER,
    rows_from       INTEGER,
    rows_to         INTEGER,
    xml_valid       BOOLEAN,
    error_message   TEXT
) AS $$
DECLARE
    v_batch INTEGER := 0;
    v_offset INTEGER := 0;
    v_xml_test TEXT;
    v_row_data TEXT;
    v_count INTEGER;
BEGIN
    -- Получаем общее количество строк
    SELECT COUNT(*) INTO v_count
    FROM upoa_ksk_reports.ksk_report_review(p_report_date)
    WHERE rn = 1;

    WHILE v_offset < v_count LOOP
        v_batch := v_batch + 1;

        BEGIN
            -- Генерируем XML для батча
            SELECT string_agg(
                '<Row>' ||
                '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(r.corr_id) || '</Data></Cell>' ||
                '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(r.name_figurant) || '</Data></Cell>' ||
                '</Row>',
                E'\n'
            )
            INTO v_row_data
            FROM (
                SELECT corr_id, name_figurant
                FROM upoa_ksk_reports.ksk_report_review(p_report_date)
                WHERE rn = 1
                OFFSET v_offset
                LIMIT p_batch_size
            ) r;

            -- Пробуем конвертировать в XML
            v_xml_test := '<?xml version="1.0"?><Root>' || COALESCE(v_row_data, '') || '</Root>';
            PERFORM v_xml_test::XML;

            batch_num := v_batch;
            rows_from := v_offset + 1;
            rows_to := LEAST(v_offset + p_batch_size, v_count);
            xml_valid := TRUE;
            error_message := NULL;
            RETURN NEXT;

        EXCEPTION WHEN OTHERS THEN
            batch_num := v_batch;
            rows_from := v_offset + 1;
            rows_to := LEAST(v_offset + p_batch_size, v_count);
            xml_valid := FALSE;
            error_message := SQLERRM;
            RETURN NEXT;
        END;

        v_offset := v_offset + p_batch_size;
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_xls_test_xml(DATE, INTEGER) IS
    'Диагностика: проверяет батчами какие строки ломают XML парсинг';
