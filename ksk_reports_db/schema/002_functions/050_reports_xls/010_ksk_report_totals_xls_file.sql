-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта totals
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА:
--   Строка 1: Заголовки на русском (Всего транзакций, ...)
--   Строка 2: Имена полей на английском (total, totalWithoutResult, ...)
--   Строка 3: Данные
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals_xls_file(
    p_report_header_id INTEGER
)
RETURNS INTEGER AS $$
DECLARE
    v_file_id INTEGER;
    v_xml_content XML;
    v_file_name VARCHAR(500);
    v_row_count INTEGER;
    v_data RECORD;
BEGIN
    -- Получаем данные отчёта
    SELECT
        total,
        total_without_result,
        total_with_result,
        total_allow,
        total_review,
        total_deny,
        total_bypass
    INTO v_data
    FROM upoa_ksk_reports.ksk_report_totals_data
    WHERE report_header_id = p_report_header_id
    ORDER BY id DESC
    LIMIT 1;

    -- Проверяем наличие данных
    IF v_data IS NULL THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'totals__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

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
                xmlattributes('Totals' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Total allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Total review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Не совпало с алгоритмами ДОПБ')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'total')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass'))
                    ),
                    -- Строка 3: Данные
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_without_result)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_with_result)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_allow)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_review)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_deny)),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), v_data.total_bypass))
                    )
                )
            )
        ),
        version '1.0',
        standalone yes
    );

    -- Количество строк данных (без заголовков)
    v_row_count := 1;

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

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта totals и сохраняет в ksk_report_files';
