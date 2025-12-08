-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта Review
--   ОПТИМИЗИРОВАНО для больших объёмов данных (до 500 000 строк)
--   Использует потоковую генерацию XML через string_agg вместо xmlagg
--
-- ПАРАМЕТРЫ:
--   @p_report_date - Дата отчёта
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_review_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (35 колонок A-AI):
--   Строка 1: Заголовки
--   Строка 2: Имена полей
--   Строки 3+: Данные
--
-- ОПТИМИЗАЦИИ:
--   1. Использует string_agg вместо xmlagg (меньше потребление памяти)
--   2. Экранирование XML делается через replace (быстрее xmlelement)
--   3. Генерация XML как TEXT, конвертация в XML только при сохранении
--   4. INSERT ON CONFLICT для атомарной замены отчёта за дату
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции с оптимизацией для больших объёмов
--   2025-12-08 - FIX: escape_xml теперь удаляет недопустимые XML control characters
-- ============================================================================

-- Вспомогательная функция для экранирования XML
-- Удаляет недопустимые XML символы (control characters) и экранирует спецсимволы
CREATE OR REPLACE FUNCTION upoa_ksk_reports.escape_xml(p_text TEXT)
RETURNS TEXT AS $$
DECLARE
    v_text TEXT;
BEGIN
    IF p_text IS NULL THEN
        RETURN '';
    END IF;

    -- Удаляем недопустимые XML символы (control characters 0x00-0x1F кроме tab, lf, cr)
    v_text := regexp_replace(p_text, E'[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]', '', 'g');

    -- Экранируем XML спецсимволы
    RETURN replace(
        replace(
            replace(
                replace(
                    replace(v_text, '&', '&amp;'),
                    '<', '&lt;'
                ),
                '>', '&gt;'
            ),
            '"', '&quot;'
        ),
        '''', '&apos;'
    );
END;
$$ LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE;

-- Основная функция генерации отчёта
CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_xls_file(
    p_report_date DATE
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_text TEXT;
    v_data_rows TEXT;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_file_size INTEGER;
BEGIN
    -- Формируем имя файла
    v_file_name := 'review__' || TO_CHAR(p_report_date, 'YYYYMMDD') || TO_CHAR(NOW(), 'HH24MI') || '.xls';

    -- Генерируем строки данных через string_agg (оптимизировано для больших объёмов)
    SELECT
        string_agg(
            '<Row>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(corr_id) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(message_timestamp::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(algorithm) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_value) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_payment_field) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(match_payment_value) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(list_code) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(name_figurant) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(president_group) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(auto_login::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(has_exclusion::TEXT) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(exclusion_phrase) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(exclusion_name_list) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(is_bypass) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(transaction_resolution) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(figurant_resolition) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payment_id) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payment_purpose) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(account_debet) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(account_credit) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_inn) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_document_type) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_bank_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(payer_bank_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_inn) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_bank_name) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_bank_account_number) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(receiver_document_type) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(amount) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(currency) || '</Data></Cell>' ||
            '<Cell><Data ss:Type="String">' || upoa_ksk_reports.escape_xml(currency_control) || '</Data></Cell>' ||
            '</Row>',
            E'\n'
        ),
        COUNT(*)
    INTO v_data_rows, v_row_count
    FROM upoa_ksk_reports.ksk_report_review(p_report_date)
    WHERE rn = 1;  -- Убираем дубликаты

    -- Если нет данных, создаём пустой отчёт
    IF v_row_count = 0 THEN
        v_data_rows := '';
    END IF;

    -- Собираем полный XML документ
    v_xml_text := '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles>
<Style ss:ID="s1"><Font ss:Bold="1"/></Style>
</Styles>
<Worksheet ss:Name="Review">
<Table>
<Row>
<Cell ss:StyleID="s1"><Data ss:Type="String">corr_id</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Время обработки платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Алгоритм</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Значение для поиска на фигуранте</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Поле платежа с совпадением</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Значение поля платежа с совпадением</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Код списка</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Наименование фигуранта</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">presidentGroup</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">autoLogin</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Наличие исключения</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Фраза исключения</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Название списка исключений</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Исключено из контроля</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Решение по транзакции</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Решение по фигуранту</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ID платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Назначение платежа</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.accountDebit.name</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Счёт кредита</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ИНН плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Имя плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Тип документа плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Банк плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта банка плательщика</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Имя получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">ИНН получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.receiverBankName.name</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Номер счёта банка получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Тип документа получателя</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Сумма</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">Валюта</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">system.reports.REVIEW.table.column.currencyControl.name</Data></Cell>
</Row>
<Row>
<Cell ss:StyleID="s1"><Data ss:Type="String">corrId</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">messageTimestamp</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">algorithm</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchValue</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchPaymentField</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">matchPaymentValue</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">listCode</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">nameFigurant</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">presidentGroup</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">autoLogin</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">hasExclusion</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">exclusionPhrase</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">exclusionNameList</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">isBypass</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">transactionResolution</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">figurantResolition</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">paymentId</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">paymentPurpose</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">accountDebit</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">accountCredit</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerInn</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerDocumentType</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerBankName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">payerBankAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverInn</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverBankName</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverBankAccountNumber</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">receiverDocumentType</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">amount</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">currency</Data></Cell>
<Cell ss:StyleID="s1"><Data ss:Type="String">currencyControl</Data></Cell>
</Row>
' || COALESCE(v_data_rows, '') || '
</Table>
</Worksheet>
</Workbook>';

    -- Вычисляем размер файла
    v_file_size := LENGTH(v_xml_text);

    -- Сохраняем файл в таблицу (INSERT ON CONFLICT для атомарной замены)
    INSERT INTO upoa_ksk_reports.ksk_report_review_files (
        report_date,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_date,
        v_file_name,
        'excel_xml',
        v_xml_text::XML,
        v_file_size,
        1,
        v_row_count
    )
    ON CONFLICT (report_date) DO UPDATE SET
        file_name = EXCLUDED.file_name,
        file_format = EXCLUDED.file_format,
        file_content = EXCLUDED.file_content,
        file_size_bytes = EXCLUDED.file_size_bytes,
        sheet_count = EXCLUDED.sheet_count,
        row_count = EXCLUDED.row_count,
        created_datetime = NOW()
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_xls_file(DATE) IS
    'Генерирует Excel XML файл для отчёта Review. Оптимизировано для больших объёмов (до 500k строк). Сохраняет в ksk_report_review_files с уникальностью по дате.';

COMMENT ON FUNCTION upoa_ksk_reports.escape_xml(TEXT) IS
    'Вспомогательная функция для экранирования специальных символов XML: & < > " ''';
