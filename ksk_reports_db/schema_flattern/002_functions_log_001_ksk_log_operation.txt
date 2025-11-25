-- ============================================================================
-- ФУНКЦИЯ: ksk_log_operation
-- ============================================================================
-- ОПИСАНИЕ:
--   Вспомогательная функция для записи операции в системный лог
--   Используется во всех функциях системы для единообразного логирования
--
-- ПАРАМЕТРЫ:
--   @p_operation_code - Код операции (например: 'create_partitions')
--   @p_operation_name - Название операции (например: 'Создание партиций')
--   @p_begin_time     - Время начала операции
--   @p_status         - Статус: 'success' или 'error'
--   @p_info           - Дополнительная информация о результате
--   @p_err_msg        - Сообщение об ошибке (если есть)
--
-- ВОЗВРАЩАЕТ:
--   INTEGER - ID созданной записи в логе
--
-- ПРИМЕР ИСПОЛЬЗОВАНИЯ:
--   PERFORM ksk_log_operation(
--       'create_partitions',
--       'Создание партиций для всех таблиц',
--       v_start_time,
--       'success',
--       'Создано 21 партиция',
--       NULL
--   );
--
-- ИСТОРИЯ ИЗМЕНЕНИЙ:
--   2025-10-25 - Создание функции
-- ============================================================================

CREATE OR REPLACE FUNCTION ksk_log_operation(
    p_operation_code VARCHAR,
    p_operation_name VARCHAR,
    p_begin_time     TIMESTAMP(3),
    p_status         VARCHAR,
    p_info           TEXT DEFAULT NULL,
    p_err_msg        TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_log_id INTEGER;
BEGIN
    INSERT INTO upoa_ksk_reports.ksk_system_operations_log (
        operation_code,
        operation_name,
        begin_time,
        end_time,
        duration,
        status,
        info,
        err_msg
    ) VALUES (
        p_operation_code,
        p_operation_name,
        p_begin_time,
        CLOCK_TIMESTAMP(),
        CLOCK_TIMESTAMP() - p_begin_time,
        p_status,
        p_info,
        p_err_msg
    )
    RETURNING id INTO v_log_id;
    
    RETURN v_log_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION ksk_log_operation(
    p_operation_code VARCHAR,
    p_operation_name VARCHAR,
    p_begin_time     TIMESTAMP with TIME ZONE,
    p_status         VARCHAR,
    p_info           TEXT DEFAULT NULL,
    p_err_msg        TEXT DEFAULT NULL
)
RETURNS INTEGER AS $$
DECLARE
    v_log_id INTEGER;
BEGIN    
    RETURN upoa_ksk_reports.ksk_log_operation(
       p_operation_code,
       p_operation_name,
       p_begin_time::timestamp(3),
       p_status,
       p_info,
       p_err_msg);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION ksk_log_operation(VARCHAR, VARCHAR, TIMESTAMP, VARCHAR, TEXT, TEXT) IS 
    'Записывает операцию в системный лог с автоматическим расчётом длительности';
