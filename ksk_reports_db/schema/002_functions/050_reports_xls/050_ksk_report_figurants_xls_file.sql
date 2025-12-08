-- ============================================================================
-- ФУНКЦИЯ: ksk_report_figurants_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта figurants
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (10 колонок A-J):
--   Строка 1: Заголовки (listCode, nameFigurant, presidentGroup, autoLogin, exclusionPhrase, Всего транзакций, Allow, Review, Deny, Исключено из контроля)
--   Строка 2: Имена полей (listCode, nameFigurant, presidentGroup, autoLogin, exclusionPhrase, total, totalAllow, totalReview, totalDeny, totalBypass)
--   Строки 3+: Данные (по одной строке на каждого фигуранта)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_figurants_xls_file(
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
    FROM upoa_ksk_reports.ksk_report_figurants_data
    WHERE report_header_id = p_report_header_id;

    IF v_row_count = 0 THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'figurants__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Генерируем строки данных
    SELECT xmlagg(
        xmlelement(
            name "Row",
            -- A: listCode
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(list_code, ''))),
            -- B: nameFigurant
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(name_figurant, ''))),
            -- C: presidentGroup
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(president_group, ''))),
            -- D: autoLogin
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(auto_login, ''))),
            -- E: exclusionPhrase
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), COALESCE(exclusion_phrase, ''))),
            -- F: total
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total, 0))),
            -- G: totalAllow
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_allow, 0))),
            -- H: totalReview
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_review, 0))),
            -- I: totalDeny
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_deny, 0))),
            -- J: totalBypass
            xmlelement(name "Cell",
                xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(total_bypass, 0)))
        )
        ORDER BY list_code, name_figurant
    )
    INTO v_data_rows
    FROM upoa_ksk_reports.ksk_report_figurants_data
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
                xmlattributes('Figurants' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'nameFigurant')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'presidentGroup')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'autoLogin')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'exclusionPhrase')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исключено из контроля'))
                    ),
                    -- Строка 2: Имена полей на английском
                    xmlelement(
                        name "Row",
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'listCode')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'nameFigurant')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'presidentGroup')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'autoLogin')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'exclusionPhrase')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'total')),
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

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_figurants_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта figurants и сохраняет в ksk_report_files';
