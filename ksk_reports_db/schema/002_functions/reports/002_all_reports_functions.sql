-- ============================================================================
-- ФУНКЦИИ ГЕНЕРАЦИИ ОТЧЁТОВ
-- ============================================================================

-- ============================================================================
-- ФУНКЦИЯ 1: ksk_run_report
-- ============================================================================
-- ОПИСАНИЕ:
--   Универсальная функция для запуска генерации отчёта
--   Создаёт заголовок отчёта, вызывает функцию генерации и обновляет статус
--
-- ПАРАМЕТРЫ:
--   @p_report_code   - Код отчёта из оркестратора
--   @p_initiator     - Инициатор ('system' или 'user')
--   @p_user_login    - Логин пользователя (NULL для system)
--   @p_start_date    - Начальная дата периода
--   @p_end_date      - Конечная дата периода (NULL = p_start_date)
--   @p_parameters    - Дополнительные параметры в формате JSON
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданного заголовка отчёта
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   -- Системный отчёт за день
--   SELECT ksk_run_report('totals', 'system', NULL, '2025-10-22', NULL, NULL);
--   
--   -- Пользовательский отчёт с фильтром по спискам
--   SELECT ksk_run_report('figurants', 'user', 'ivanov', '2025-10-20', '2025-10-22', 
--       '{"list_codes": ["4200", "4204"]}'::JSONB);
--
-- ЗАВИСИМОСТИ:
--   - ksk_report_orchestrator
--   - ksk_report_header
--   - Функции генерации отчётов (ksk_report_*)
--   - ksk_log_operation (для логирования)
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование через ksk_log_operation
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_run_report(
    p_report_code   VARCHAR,
    p_initiator     VARCHAR,
    p_user_login    VARCHAR DEFAULT NULL,
    p_start_date    DATE DEFAULT CURRENT_DATE,
    p_end_date      DATE DEFAULT NULL,
    p_parameters    JSONB DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_orchestrator_id   INTEGER;
    v_report_function   VARCHAR;
    v_report_name       VARCHAR;
    v_ttl               INTEGER;
    v_header_id         INTEGER;
    v_start_time        TIMESTAMP := CLOCK_TIMESTAMP();
    v_status            VARCHAR := 'success';
    v_error_msg         TEXT := NULL;
    v_info              TEXT;
BEGIN
    -- Установка end_date по умолчанию
    IF p_end_date IS NULL THEN
        p_end_date := p_start_date;
    END IF;

    -- Получение метаданных из оркестратора
    SELECT 
        id,
        report_function,
        name,
        CASE 
            WHEN p_initiator = 'system' THEN system_ttl
            WHEN p_initiator = 'user' THEN user_ttl
        END
    INTO v_orchestrator_id, v_report_function, v_report_name, v_ttl
    FROM upoa_ksk_reports.ksk_report_orchestrator
    WHERE report_code = p_report_code;

    IF v_orchestrator_id IS NULL THEN
        RAISE EXCEPTION 'Отчёт с кодом % не найден', p_report_code;
    END IF;

    -- Создание заголовка отчёта
    INSERT INTO upoa_ksk_reports.ksk_report_header (
        orchestrator_id,
        name,
        initiator,
        user_login,
        status,
        ttl,
        remove_date,
        start_date,
        end_date,
        parameters
    ) VALUES (
        v_orchestrator_id,
        v_report_name || ' (' || p_start_date || ' - ' || p_end_date || ')',
        p_initiator,
        p_user_login,
        'in_progress',
        v_ttl,
        CURRENT_DATE + v_ttl,
        p_start_date,
        p_end_date,
        p_parameters
    )
    RETURNING id INTO v_header_id;

    -- Вызов функции генерации отчёта
    BEGIN
        EXECUTE FORMAT('SELECT %I($1, $2, $3, $4)', v_report_function)
        USING v_header_id, p_start_date, p_end_date, p_parameters;

        -- Обновление статуса на 'done'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'done',
            finished_datetime = NOW()
        WHERE id = v_header_id;

        v_info := FORMAT(
            'Отчёт %s создан успешно. Header ID: %s. Период: %s - %s',
            p_report_code, v_header_id, p_start_date, p_end_date
        );

    EXCEPTION WHEN OTHERS THEN
        v_status := 'error';
        v_error_msg := SQLERRM;

        -- Обновление статуса на 'error'
        UPDATE upoa_ksk_reports.ksk_report_header
        SET status = 'error',
            finished_datetime = NOW()
        WHERE id = v_header_id;

        v_info := FORMAT(
            'Ошибка создания отчёта %s. Header ID: %s. Период: %s - %s',
            p_report_code, v_header_id, p_start_date, p_end_date
        );

        RAISE WARNING 'Ошибка при генерации отчёта %: %', p_report_code, SQLERRM;
    END;

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'run_report_' || p_report_code,
        'Генерация отчёта: ' || v_report_name,
        v_start_time,
        v_status,
        v_info,
        v_error_msg
    );

    RETURN v_header_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_run_report(VARCHAR, VARCHAR, VARCHAR, DATE, DATE, JSONB) IS 
    'Универсальная функция для запуска генерации отчёта с логированием';

-- ============================================================================
-- СЛУЖЕБНАЯ ФУНКЦИЯ: ksk_cleanup_old_reports
-- ============================================================================
-- ОПИСАНИЕ:
--   Удаляет устаревшие отчёты на основе remove_date
--   Рекомендуется запускать ежедневно в cron
--
-- ПАРАМЕТРЫ:
--   Нет
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - Количество удалённых отчётов
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   SELECT ksk_cleanup_old_reports();
--
-- ЗАМЕТКИ:
--   - Удаляет заголовки отчётов с remove_date < CURRENT_DATE
--   - Данные отчётов удаляются автоматически (CASCADE)
--   - Записывает результат в системный лог
--
-- ЗАВИСИМОСТИ:
--   - ksk_log_operation
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Добавлено логирование
-- ============================================================================

CREATE OR REPLACE FUNCTION upoa_ksk_reports.ksk_cleanup_old_reports()
RETURNS INTEGER AS $$
DECLARE
    v_deleted_count INTEGER;
    v_start_time    TIMESTAMP := CLOCK_TIMESTAMP();
    v_status        VARCHAR := 'success';
    v_info          TEXT;
BEGIN
    DELETE FROM upoa_ksk_reports.ksk_report_header
    WHERE remove_date < CURRENT_DATE;
    
    GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

    v_info := FORMAT(
        'Удалено устаревших отчётов: %s',
        v_deleted_count
    );

    -- Запись в системный лог
    PERFORM upoa_ksk_reports.ksk_log_operation(
        'cleanup_old_reports',
        'Очистка устаревших отчётов',
        v_start_time,
        v_status,
        v_info,
        NULL
    );

    RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_cleanup_old_reports() IS 
    'Удаляет устаревшие отчёты на основе remove_date с логированием';

-- ============================================================================
-- КОНЕЦ ФАЙЛА
-- ============================================================================
