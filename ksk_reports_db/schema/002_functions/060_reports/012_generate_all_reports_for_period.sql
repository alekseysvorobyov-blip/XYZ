-- ============================================================================
-- ФУНКЦИЯ: generate_all_reports_for_period
-- ============================================================================
-- ОПИСАНИЕ:
--   Генерирует все типы отчётов за указанный период дат.
--   Типы отчётов берутся из таблицы ksk_report_orchestrator.
--   Если отчёт уже существует - вызывает ksk_regenerate_report (перегенерация).
--   Если отчёт не существует - вызывает ksk_run_report (создание нового).
--
-- ПАРАМЕТРЫ:
--   @p_start_date - Начальная дата периода
--   @p_end_date   - Конечная дата периода
--
-- ВОЗВРАЩАЕТ:
--   TABLE (operation_date, report_type, header_id, status, message)
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT * FROM upoa_ksk_reports.generate_all_reports_for_period('2024-01-01', '2024-01-31');
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-12-16 - Рефакторинг: типы отчётов из оркестратора, логика regenerate/run
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.generate_all_reports_for_period(
    p_start_date DATE DEFAULT '2021-11-01'::DATE,
    p_end_date DATE DEFAULT '2021-11-12'::DATE
)
RETURNS TABLE(
    operation_date DATE,
    report_type CHARACTER VARYING,
    header_id INTEGER,
    status CHARACTER VARYING,
    message TEXT
)
LANGUAGE plpgsql
AS $function$
DECLARE
    v_current_date DATE;
    v_report_rec RECORD;
    v_existing_header_id INTEGER;
    v_header_id INTEGER;
    v_header_status VARCHAR;
    v_message TEXT;
    v_action TEXT;
    v_error_msg TEXT;
BEGIN
    -- ОСНОВНОЙ ЦИКЛ: По каждому дню в периоде
    v_current_date := p_start_date;

    WHILE v_current_date <= p_end_date LOOP

        -- ВНУТРЕННИЙ ЦИКЛ: По каждому типу отчёта из оркестратора
        FOR v_report_rec IN
            SELECT report_code, report_table, report_function, name
            FROM upoa_ksk_reports.ksk_report_orchestrator
            ORDER BY id
        LOOP
            BEGIN
                -- Проверяем существует ли отчёт для этой даты и типа
                SELECT h.id INTO v_existing_header_id
                FROM upoa_ksk_reports.ksk_report_header h
                JOIN upoa_ksk_reports.ksk_report_orchestrator o ON h.orchestrator_id = o.id
                WHERE o.report_code = v_report_rec.report_code
                  AND h.start_date = v_current_date
                LIMIT 1;

                IF v_existing_header_id IS NOT NULL THEN
                    -- Отчёт существует - регенерируем
                    v_action := 'regenerate';
                    v_header_id := upoa_ksk_reports.ksk_regenerate_report(v_existing_header_id);

                    -- ksk_regenerate_report возвращает отрицательное значение при ошибке
                    IF v_header_id < 0 THEN
                        v_header_status := 'error';
                        v_message := FORMAT(
                            'ERROR: Failed to regenerate %s for %s (existing header_id=%s)',
                            v_report_rec.report_code, v_current_date, v_existing_header_id
                        );
                    ELSE
                        -- Получаем финальный статус
                        SELECT t.status INTO v_header_status
                        FROM upoa_ksk_reports.ksk_report_header t
                        WHERE id = v_existing_header_id;

                        v_header_id := v_existing_header_id;
                        v_message := FORMAT(
                            'Report %s for %s regenerated successfully (header_id=%s, status=%s)',
                            v_report_rec.report_code, v_current_date, v_header_id, v_header_status
                        );
                    END IF;
                ELSE
                    -- Отчёт не существует - создаём новый
                    v_action := 'create';
                    v_header_id := upoa_ksk_reports.ksk_run_report(
                        p_report_code := v_report_rec.report_code,
                        p_initiator := 'system',
                        p_user_login := NULL,
                        p_start_date := v_current_date::DATE,
                        p_end_date := NULL,
                        p_parameters := NULL
                    );

                    -- Получаем финальный статус отчёта из ksk_report_header
                    SELECT t.status INTO v_header_status
                    FROM upoa_ksk_reports.ksk_report_header t
                    WHERE id = v_header_id;

                    v_message := FORMAT(
                        'Report %s for %s created successfully (header_id=%s, status=%s)',
                        v_report_rec.report_code, v_current_date, v_header_id, v_header_status
                    );
                END IF;

                -- Возвращаем успешный результат
                RETURN QUERY SELECT
                    v_current_date,
                    v_report_rec.report_code::VARCHAR,
                    v_header_id,
                    v_header_status,
                    v_message;

            EXCEPTION WHEN OTHERS THEN
                v_error_msg := SQLERRM;
                v_message := FORMAT(
                    'ERROR: Failed to %s %s for %s: %s',
                    COALESCE(v_action, 'process'), v_report_rec.report_code, v_current_date, v_error_msg
                );

                -- Возвращаем ошибку
                RETURN QUERY SELECT
                    v_current_date,
                    v_report_rec.report_code::VARCHAR,
                    NULL::INTEGER,
                    'error'::VARCHAR,
                    v_message;

                RAISE WARNING '%', v_message;
            END;

        END LOOP; -- Конец цикла по типам отчётов

        v_current_date := v_current_date + INTERVAL '1 day';

    END LOOP; -- Конец цикла по датам

END $function$;

COMMENT ON FUNCTION upoa_ksk_reports.generate_all_reports_for_period(DATE, DATE) IS
    'Генерирует все типы отчётов за период. Существующие отчёты перегенерируются, новые создаются.';
