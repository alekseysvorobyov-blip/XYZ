-- ============================================================================
-- ФУНКЦИЯ: ksk_report_totals_by_payment_type_xls_file
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel XML (SpreadsheetML) файл для отчёта totals_by_payment_type
--   Формат совместим с Excel 2003 XML и открывается в современных версиях Excel
--
-- ПАРАМЕТРЫ:
--   @p_report_header_id - ID заголовка отчёта из ksk_report_header
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в ksk_report_files
--
-- СТРУКТУРА EXCEL ФАЙЛА (42 колонки A-AP):
--   Строка 1: Заголовки на русском
--   Строка 2: Имена полей на английском
--   Строка 3: Данные
--
-- КОЛОНКИ:
--   A-G: Общие (total, totalWithoutResult, totalWithResult, totalAllow, totalReview, totalDeny, totalBypass)
--   H-N: Входящий I (iTotal, iTotalWithoutResult, iTotalWithResult, iTotalAllow, iTotalReview, iTotalDeny, iTotalBypass)
--   O-U: Исходящий O (oTotal, ...)
--   V-AB: Транзитный T (tTotal, ...)
--   AC-AI: Межфилиальный M (mTotal, ...)
--   AJ-AP: Внутрифилиальный V (vTotal, ...)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(
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
        -- Общие
        total, total_without_result, total_with_result,
        total_allow, total_review, total_deny, total_bypass,
        -- Входящий (I)
        i_total, i_total_without_result, i_total_with_result,
        i_total_allow, i_total_review, i_total_deny, i_total_bypass,
        -- Исходящий (O)
        o_total, o_total_without_result, o_total_with_result,
        o_total_allow, o_total_review, o_total_deny, o_total_bypass,
        -- Транзитный (T)
        t_total, t_total_without_result, t_total_with_result,
        t_total_allow, t_total_review, t_total_deny, t_total_bypass,
        -- Межфилиальный (M)
        m_total, m_total_without_result, m_total_with_result,
        m_total_allow, m_total_review, m_total_deny, m_total_bypass,
        -- Внутрифилиальный (V)
        v_total, v_total_without_result, v_total_with_result,
        v_total_allow, v_total_review, v_total_deny, v_total_bypass
    INTO v_data
    FROM upoa_ksk_reports.ksk_report_totals_by_payment_type_data
    WHERE report_header_id = p_report_header_id
    ORDER BY id DESC
    LIMIT 1;

    -- Проверяем наличие данных
    IF v_data IS NULL THEN
        RAISE EXCEPTION 'Данные отчёта не найдены для report_header_id = %', p_report_header_id;
    END IF;

    -- Формируем имя файла
    v_file_name := 'totals_by_payment_type__' || TO_CHAR(NOW(), 'YYYYMMDDHH24MI') || '.xls';

    -- Количество строк данных
    v_row_count := 1;

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
                xmlattributes('TotalsByPaymentType' AS "ss:Name"),
                xmlelement(
                    name "Table",
                    -- Строка 1: Заголовки на русском
                    xmlelement(
                        name "Row",
                        -- A-G: Общие
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Всего исключено из контроля')),
                        -- H-N: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Входящий Исключено из контроля')),
                        -- O-U: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Исходящий Исключено из контроля')),
                        -- V-AB: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Транзитный Исключено из контроля')),
                        -- AC-AI: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего транзакций с результатом')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего allow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего review')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Всего deny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Межфилиальный Исключено из контроля')),
                        -- AJ-AP: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего транзакций')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего транзакций без результата')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'Внутрифилиальный Всего транзакций с результатом')),
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
                        -- A-G: Общие
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
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'totalBypass')),
                        -- H-N: Входящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'iTotalBypass')),
                        -- O-U: Исходящий
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'oTotalBypass')),
                        -- V-AB: Транзитный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'tTotalBypass')),
                        -- AC-AI: Межфилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'mTotalBypass')),
                        -- AJ-AP: Внутрифилиальный
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotal')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalWithoutResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalWithResult')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalAllow')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalReview')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalDeny')),
                        xmlelement(name "Cell", xmlattributes('s1' AS "ss:StyleID"),
                            xmlelement(name "Data", xmlattributes('String' AS "ss:Type"), 'vTotalBypass'))
                    ),
                    -- Строка 3: Данные
                    xmlelement(
                        name "Row",
                        -- A-G: Общие
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.total_bypass, 0))),
                        -- H-N: Входящий
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.i_total_bypass, 0))),
                        -- O-U: Исходящий
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.o_total_bypass, 0))),
                        -- V-AB: Транзитный
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.t_total_bypass, 0))),
                        -- AC-AI: Межфилиальный
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.m_total_bypass, 0))),
                        -- AJ-AP: Внутрифилиальный
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_without_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_with_result, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_allow, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_review, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_deny, 0))),
                        xmlelement(name "Cell",
                            xmlelement(name "Data", xmlattributes('Number' AS "ss:Type"), COALESCE(v_data.v_total_bypass, 0)))
                    )
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

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(INTEGER) IS
    'Генерирует Excel XML (SpreadsheetML) файл для отчёта totals_by_payment_type и сохраняет в ksk_report_files';
