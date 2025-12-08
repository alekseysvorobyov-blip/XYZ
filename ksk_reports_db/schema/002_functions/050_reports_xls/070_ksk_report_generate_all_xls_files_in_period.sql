-- ============================================================================
-- ФУНКЦИЯ: ksk_report_generate_all_xls_files_in_period
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует Excel-файлы для всех отчётов в заданном периоде
--   Если у отчёта уже есть файл - пропускает
--   Для review-отчётов генерирует файлы за каждую дату в периоде
--
-- ПАРАМЕТРЫ:
--   @p_date_from - Начальная дата периода (включительно)
--   @p_date_to   - Конечная дата периода (включительно)
--
-- ВОЗВРАЩАЕТ:
--   TABLE (
--     report_type    TEXT,    -- Тип отчёта
--     report_date    DATE,    -- Дата отчёта
--     header_id      INTEGER, -- ID заголовка (NULL для review)
--     file_id        INTEGER, -- ID созданного файла
--     status         TEXT     -- 'created', 'skipped', 'error'
--   )
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM ksk_report_generate_all_xls_files_in_period('2025-12-01', '2025-12-08');
--   SELECT * FROM ksk_report_generate_all_xls_files_in_period(CURRENT_DATE - 7, CURRENT_DATE);
--
-- ЗАМЕТКИ:
--   - Обрабатывает все типы отчётов из ksk_report_header
--   - Для каждого типа вызывает соответствующую xls-функцию
--   - Review-отчёты обрабатываются отдельно (по датам, без header)
--   - Возвращает детальный лог выполнения
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-08 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_report_generate_all_xls_files_in_period(
    p_date_from DATE,
    p_date_to DATE
)
RETURNS TABLE (
    report_type    TEXT,
    report_date    DATE,
    header_id      INTEGER,
    file_id        INTEGER,
    status         TEXT
) AS $$
DECLARE
    v_header RECORD;
    v_file_id INTEGER;
    v_current_date DATE;
    v_has_file BOOLEAN;
    v_report_code TEXT;
BEGIN
    -- ========================================================================
    -- 1. ОБРАБОТКА СТАНДАРТНЫХ ОТЧЁТОВ (из ksk_report_header)
    -- ========================================================================
    FOR v_header IN
        SELECT
            h.id AS header_id,
            h.start_date,
            h.end_date,
            o.report_code,
            o.report_function
        FROM upoa_ksk_reports.ksk_report_header h
        JOIN upoa_ksk_reports.ksk_report_orchestrator o ON h.orchestrator_id = o.id
        WHERE h.status = 'done'
          AND h.start_date >= p_date_from
          AND h.start_date <= p_date_to
        ORDER BY h.start_date, o.report_code
    LOOP
        -- Проверяем, есть ли уже файл для этого отчёта
        SELECT EXISTS(
            SELECT 1 FROM upoa_ksk_reports.ksk_report_files
            WHERE report_header_id = v_header.header_id
        ) INTO v_has_file;

        IF v_has_file THEN
            -- Файл уже существует - пропускаем
            report_type := v_header.report_code;
            report_date := v_header.start_date;
            header_id := v_header.header_id;
            file_id := NULL;
            status := 'skipped';
            RETURN NEXT;
        ELSE
            -- Генерируем файл в зависимости от типа отчёта
            BEGIN
                CASE v_header.report_code
                    WHEN 'totals' THEN
                        SELECT upoa_ksk_reports.ksk_report_totals_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'totals_by_payment_type' THEN
                        SELECT upoa_ksk_reports.ksk_report_totals_by_payment_type_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'list_totals' THEN
                        SELECT upoa_ksk_reports.ksk_report_list_totals_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'list_totals_by_payment_type' THEN
                        SELECT upoa_ksk_reports.ksk_report_list_totals_by_payment_type_xls_file(v_header.header_id) INTO v_file_id;
                    WHEN 'figurants' THEN
                        SELECT upoa_ksk_reports.ksk_report_figurants_xls_file(v_header.header_id) INTO v_file_id;
                    ELSE
                        -- Неизвестный тип отчёта - пропускаем
                        report_type := v_header.report_code;
                        report_date := v_header.start_date;
                        header_id := v_header.header_id;
                        file_id := NULL;
                        status := 'unknown_type';
                        RETURN NEXT;
                        CONTINUE;
                END CASE;

                report_type := v_header.report_code;
                report_date := v_header.start_date;
                header_id := v_header.header_id;
                file_id := v_file_id;
                status := 'created';
                RETURN NEXT;

            EXCEPTION WHEN OTHERS THEN
                report_type := v_header.report_code;
                report_date := v_header.start_date;
                header_id := v_header.header_id;
                file_id := NULL;
                status := 'error: ' || SQLERRM;
                RETURN NEXT;
            END;
        END IF;
    END LOOP;

    -- ========================================================================
    -- 2. ОБРАБОТКА REVIEW-ОТЧЁТОВ (по датам)
    -- ========================================================================
    v_current_date := p_date_from;

    WHILE v_current_date <= p_date_to LOOP
        -- Проверяем, есть ли уже файл для этой даты
        SELECT EXISTS(
            SELECT 1 FROM upoa_ksk_reports.ksk_report_review_files
            WHERE report_date = v_current_date
        ) INTO v_has_file;

        IF v_has_file THEN
            -- Файл уже существует - пропускаем
            report_type := 'review';
            report_date := v_current_date;
            header_id := NULL;
            file_id := NULL;
            status := 'skipped';
            RETURN NEXT;
        ELSE
            -- Генерируем файл
            BEGIN
                SELECT upoa_ksk_reports.ksk_report_review_xls_file(v_current_date) INTO v_file_id;

                report_type := 'review';
                report_date := v_current_date;
                header_id := NULL;
                file_id := v_file_id;
                status := 'created';
                RETURN NEXT;

            EXCEPTION WHEN OTHERS THEN
                report_type := 'review';
                report_date := v_current_date;
                header_id := NULL;
                file_id := NULL;
                status := 'error: ' || SQLERRM;
                RETURN NEXT;
            END;
        END IF;

        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;

    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION upoa_ksk_reports.ksk_report_generate_all_xls_files_in_period(DATE, DATE) IS
    'Генерирует Excel-файлы для всех отчётов в заданном периоде. Пропускает отчёты с существующими файлами. Включает review-отчёты.';
