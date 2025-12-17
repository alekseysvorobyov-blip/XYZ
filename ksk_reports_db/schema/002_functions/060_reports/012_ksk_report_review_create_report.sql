-- ============================================================================
-- ФУНКЦИЯ: ksk_report_review_create_report
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует отчёт Review (проверки) за указанный день
--   Создаёт Excel XML файл с детальной информацией о транзакциях
--   Поддерживает фильтрацию по типу резолюции через параметры
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта (обязательный)
--   @p_start_date       - Дата отчёта (включительно)
--   @p_end_date         - Конечная дата (должна быть p_start_date + 1 day)
--   @p_parameters       - JSON с опциональным полем "resolution": "allow"|"review"|"deny"|"empty"
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданного файла в ksk_report_files
--
-- ОГРАНИЧЕНИЯ:
--   - Отчёт генерируется строго за 1 день (p_end_date = p_start_date + 1 day)
--   - Параметр resolution должен быть одним из: allow, review, deny, empty
--
-- ФИЛЬТРАЦИЯ ПО ДАТЕ:
--   Интервал [p_start_date ... p_end_date) - исключающий конец
--   Фактически - данные за один день p_start_date
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   -- Все транзакции с резолюцией 'review' за день
--   SELECT ksk_report_review_create_report(123, '2025-12-15', '2025-12-16', '{"resolution": "review"}');
--
--   -- Все транзакции за день (по умолчанию resolution = 'review')
--   SELECT ksk_report_review_create_report(123, '2025-12-15', '2025-12-16', NULL);
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-16 - Создание функции для системы отчётов
--   2025-12-16 - Миграция на ksk_report_files (вместо ksk_report_review_files)
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_review_create_report(
    p_report_header_id INTEGER,
    p_start_date       DATE,
    p_end_date         DATE,
    p_parameters       JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_resolution TEXT := 'review';  -- Значение по умолчанию
    v_file_id INTEGER;
    v_xml_text TEXT;
    v_data_rows TEXT;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_file_size INTEGER;
BEGIN
    -- =========================================================================
    -- ВАЛИДАЦИЯ ПАРАМЕТРОВ
    -- =========================================================================

    -- Проверка p_report_header_id
    IF p_report_header_id IS NULL THEN
        RAISE EXCEPTION 'p_report_header_id не может быть NULL';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM upoa_ksk_reports.ksk_report_header WHERE id = p_report_header_id
    ) THEN
        RAISE EXCEPTION 'Заголовок отчёта с id = % не найден', p_report_header_id;
    END IF;

    -- Проверка что p_end_date = p_start_date + interval '1 day'
    IF p_end_date != (p_start_date + INTERVAL '1 day')::DATE THEN
        RAISE EXCEPTION 'p_end_date (%) должна быть равна p_start_date + 1 день (%). Отчёт Review генерируется строго за 1 день.',
            p_end_date, (p_start_date + INTERVAL '1 day')::DATE;
    END IF;

    -- Извлечение параметра resolution из p_parameters
    IF p_parameters IS NOT NULL AND p_parameters ? 'resolution' THEN
        v_resolution := p_parameters->>'resolution';
    END IF;

    -- Проверка допустимых значений resolution
    IF v_resolution NOT IN ('allow', 'review', 'deny', 'empty') THEN
        RAISE EXCEPTION 'Недопустимое значение resolution: %. Допустимые значения: allow, review, deny, empty', v_resolution;
    END IF;

    -- =========================================================================
    -- ГЕНЕРАЦИЯ EXCEL XML ФАЙЛА
    -- =========================================================================

    -- Формируем имя файла
    v_file_name := 'review_' || v_resolution || '_' || TO_CHAR(p_start_date, 'YYYYMMDD') || '_' || TO_CHAR(NOW(), 'HH24MI') || '.xls';

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
    FROM upoa_ksk_reports.ksk_report_review(p_start_date)
    WHERE rn = 1  -- Убираем дубликаты
      AND transaction_resolution = v_resolution;  -- Фильтр по резолюции

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

    -- =========================================================================
    -- СОХРАНЕНИЕ ФАЙЛА В ksk_report_files (унифицированное хранилище)
    -- =========================================================================

    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content_text,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_text,
        v_file_size,
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    -- =========================================================================
    -- СОХРАНЕНИЕ/ОБНОВЛЕНИЕ МЕТАДАННЫХ В ksk_report_review_data
    -- =========================================================================

    INSERT INTO upoa_ksk_reports.ksk_report_review_data (
        report_header_id,
        file_size_bytes,
        row_count,
        transaction_resolution
    )
    VALUES (
        p_report_header_id,
        v_file_size,
        v_row_count,
        v_resolution
    )
    ON CONFLICT (report_header_id) DO UPDATE SET
        file_size_bytes = EXCLUDED.file_size_bytes,
        row_count = EXCLUDED.row_count,
        transaction_resolution = EXCLUDED.transaction_resolution,
        created_date_time = NOW();

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_review_create_report(INTEGER, DATE, DATE, JSONB) IS
    'Генерирует Excel XML файл для отчёта Review. Фильтр по резолюции (allow/review/deny/empty). Отчёт строго за 1 день. Сохраняет в ksk_report_files и ksk_report_review_data.';
