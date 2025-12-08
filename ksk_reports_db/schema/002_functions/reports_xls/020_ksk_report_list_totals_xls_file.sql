-- ============================================================================
-- ФУНКЦИЯ: ksk_report_list_totals_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА:
--   Строка 1: Заголовки на русском (Код списка, Всего транзакций с списком, ...)
--   Строка 2: Имена полей на английском (listCode, totalWithList, ...)
--   Строки 3+: Данные (по одной строке на каждый list_code)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_list_totals_xls_file(
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
    FROM upoa_ksk_reports.ksk_report_list_totals_data
    WHERE report_header_id = p_report_header_id;

    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'list_totals__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем строки данных
    SELECT xmlagg(
        xmlelement(
            name "Row",
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), list_code)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_with_list)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_allow)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_review)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_deny)),
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), total_bypass))
        )
        ORDER BY list_code
    )
    INTO v_data_rows
    FROM upoa_ksk_reports.ksk_report_list_totals_data
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
                -- Стиль для заголовков (жирный)
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
                xmlattributes('ListTotals' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Код списка')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций с списком')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithList')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass'))
                    ),
                    -- Строки данных
                    v_data_rows
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Сохраняем файл в таблицу
    INSERT INTO upoa_ksk_reports.ksk_report_files (
        report_header_id,
        file_name,
        file_format,
        file_content,
        file_size_bytes,
        sheet_count,
        row_count
    )
    VALUES (
        p_report_header_id,
        v_file_name,
        'excel_xml',
        v_xml_content,
        LENGTH(v_xml_content::TEXT),
        1,
        v_row_count
    )
    RETURNING id INTO v_file_id;

    RETURN v_file_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_list_totals_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта list_totals и сохраняет в ksk_report_files';
