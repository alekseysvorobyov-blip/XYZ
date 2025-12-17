-- ============================================================================
-- ФУНКЦИЯ: ksk_report_list_totals_by_payment_type_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals_by_payment_type
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (31 колонка A-AE):
--   Строка 1: Заголовки на русском
--   Строка 2: Имена полей на английском (listCode, totalWithList, ...)
--   Строки 3+: Данные (по одной строке на каждый list_code)
--
-- КОЛОНКИ:
--   A: listCode (Код списка)
--   B-F: Общие (totalWithList, totalAllow, totalReview, totalDeny, totalBypass)
--   G-K: Входящий I (iTotalWithList, iTotalAllow, iTotalReview, iTotalDeny, iTotalBypass)
--   L-P: Исходящий O (oTotalWithList, oTotalAllow, oTotalReview, oTotalDeny, oTotalBypass)
--   Q-U: Транзитный T (tTotalWithList, tTotalAllow, tTotalReview, tTotalDeny, tTotalBypass)
--   V-Z: Межфилиальный M (mTotalWithList, mTotalAllow, mTotalReview, mTotalDeny, mTotalBypass)
--   AA-AE: Внутрифилиальный V (vTotalWithList, vTotalAllow, vTotalReview, vTotalDeny, vTotalBypass)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data_rows XML;
BEGIN
    -- Проверяем наличие данных
    SELECT COUNT(*) INTO v_row_count
    FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data
    WHERE report_header_id = p_report_header_id;

    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'list_totals_by_payment_type__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем строки данных
    SELECT xmlagg(
        xmlelement(
            name "Row",
            -- A: listCode
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), list_code)),
            -- B-F: Общие
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_bypass, 0))),
            -- G-K: Входящий (I)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(i_total_bypass, 0))),
            -- L-P: Исходящий (O)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(o_total_bypass, 0))),
            -- Q-U: Транзитный (T)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(t_total_bypass, 0))),
            -- V-Z: Межфилиальный (M)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(m_total_bypass, 0))),
            -- AA-AE: Внутрифилиальный (V)
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_with_list, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_allow, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_review, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_deny, 0))),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_total_bypass, 0)))
        )
        ORDER BY list_code
    )
    INTO v_data_rows
    FROM upoa_ksk_reports.ksk_report_list_totals_by_payment_type_data
    WHERE report_header_id = p_report_header_id;

    -- Генерируем Excel XML (SpreadsheetML формат)
    v_xml_content := xmlroot(
        xmlelement(
            name "Workbook",
            xmlattributes(
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns",
                'urn:schemas-microsoft-com:office:spreadsheet' AS "xmlns:ss"
            ),
            -- Стили
            xmlelement(
                name "Styles",
                xmlelement(
                    name "Style",
                    xmlattributes('s1' AS "ss:ID"),
                    xmlelement(
                        name "Font",
                        xmlattributes('1' AS "ss:Bold")
                    )
                )
            ),
            -- Лист
            xmlelement(
                name "Worksheet",
                xmlattributes('ListTotalsByPaymentType' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        -- A: Код списка
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Код списка')),
                        -- B-F: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.totalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля')),
                        -- G-K: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.iTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Исключено из контроля')),
                        -- L-P: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.oTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Исключено из контроля')),
                        -- Q-U: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.tTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.tTotalAllow.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Исключено из контроля')),
                        -- V-Z: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.mTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Исключено из контроля')),
                        -- AA-AE: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'system.reports.LIST_TOTALS_BY_PAYMENT_TYPE.table.column.vTotalWithList.name')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        -- A: listCode
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        -- B-F: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass')),
                        -- G-K: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalBypass')),
                        -- L-P: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalBypass')),
                        -- Q-U: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalBypass')),
                        -- V-Z: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalBypass')),
                        -- AA-AE: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalBypass'))
                    ),
                    -- Строки данных
                    v_data_rows
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Сохраняем файл в таблицу (унифицировано в TEXT)
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
        v_xml_content::TEXT,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals_by_payment_type и сохраняет в ksk_report_files';
