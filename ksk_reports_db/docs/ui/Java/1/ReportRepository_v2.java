package ru.example.ksk.repository;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;
import ru.example.ksk.dto.*;

import java.time.LocalDate;
import java.util.*;

/**
 * Репозиторий для работы с report_header (v2.0)
 * 
 * 🆕 НОВЫЙ МЕТОД: getSystemReportHeaderId(reportCode, date)
 * 
 * ЛОГИКА:
 * 1. Находим orchestrator_id по report_code
 * 2. Ищем report_header по (orchestrator_id, date, initiator='system')
 * 3. Возвращаем report_header_id
 * 
 * ПРЕИМУЩЕСТВА НОВОГО ПОДХОДА:
 * - Единая точка входа для всех отчётов через report_header
 * - Версионирование (можно иметь несколько версий за одну дату)
 * - Статус отчёта (created, in_progress, done, error)
 * - TTL для автоматического удаления старых отчётов
 * - Аудит (кто создал, когда, какой статус)
 */
@Repository
@RequiredArgsConstructor
public class ReportRepository {

    private final NamedParameterJdbcTemplate jdbcTemplate;

    /**
     * 🆕 ПОЛУЧИТЬ ID СИСТЕМНОГО ОТЧЁТА (v2.0)
     * 
     * Процесс:
     * 1. SELECT id FROM ksk_report_orchestrator WHERE report_code = ?
     * 2. SELECT id FROM ksk_report_header 
     *    WHERE orchestrator_id = ? 
     *    AND DATE(created_datetime) = ?
     *    AND initiator = 'system'
     *    AND status = 'done'  (только готовые отчёты)
     *    LIMIT 1
     * 
     * Возвращает:
     * - report_header_id (Long) — идентификатор отчёта в report_header
     * - null если отчёт не найден
     */
    public Long getSystemReportHeaderId(String reportCode, LocalDate date) {
        // ШАГ 1: Получаем orchestrator_id по report_code
        String sqlGetOrchestratorId = "" +
            "SELECT id FROM upoa_ksk_reports.ksk_report_orchestrator " +
            "WHERE report_code = :reportCode";
        
        Long orchestratorId = null;
        try {
            orchestratorId = jdbcTemplate.queryForObject(
                sqlGetOrchestratorId,
                Map.of("reportCode", reportCode),
                Long.class
            );
        } catch (Exception e) {
            throw new RuntimeException("Неизвестный тип отчёта: " + reportCode, e);
        }
        
        if (orchestratorId == null) {
            throw new RuntimeException("Orchest ratор не найден для reportCode: " + reportCode);
        }
        
        // ШАГ 2: Получаем report_header_id по (orchestrator_id, date, initiator='system')
        String sqlGetHeaderId = "" +
            "SELECT id FROM upoa_ksk_reports.ksk_report_header " +
            "WHERE orchestrator_id = :orchestratorId " +
            "  AND DATE(created_datetime) = :date " +
            "  AND initiator = 'system' " +
            "  AND status = 'done' " +
            "ORDER BY created_datetime DESC " +
            "LIMIT 1";
        
        Map<String, Object> params = Map.of(
            "orchestratorId", orchestratorId,
            "date", date
        );
        
        try {
            return jdbcTemplate.queryForObject(sqlGetHeaderId, params, Long.class);
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            return null;  // Отчёт не найден
        }
    }

    /**
     * Получить диапазон доступных дат для системных отчётов
     * 
     * ЛОГИКА:
     * SELECT MIN(DATE(created_datetime)), MAX(DATE(created_datetime))
     * FROM ksk_report_header
     * WHERE initiator = 'system' AND status = 'done'
     */
    public DateRangeDto getAvailableDateRange() {
        String sql = "" +
            "SELECT " +
            "    MIN(DATE(created_datetime)) as min_date, " +
            "    MAX(DATE(created_datetime)) as max_date " +
            "FROM upoa_ksk_reports.ksk_report_header " +
            "WHERE initiator = 'system' " +
            "  AND status = 'done'";
        
        try {
            Map<String, Object> result = jdbcTemplate.queryForMap(sql, new HashMap<>());
            
            LocalDate minDate = (LocalDate) result.get("min_date");
            LocalDate maxDate = (LocalDate) result.get("max_date");
            LocalDate defaultDate = maxDate != null ? maxDate : LocalDate.now();
            
            if (minDate == null) {
                minDate = LocalDate.now();
            }
            
            return DateRangeDto.builder()
                    .minDate(minDate)
                    .maxDate(maxDate)
                    .defaultDate(defaultDate)
                    .build();
                    
        } catch (Exception e) {
            LocalDate today = LocalDate.now();
            return DateRangeDto.builder()
                    .minDate(today)
                    .maxDate(today)
                    .defaultDate(today)
                    .build();
        }
    }

    /**
     * Получить список доступных типов отчётов
     */
    public ReportTypesDto getReportTypes() {
        String sql = "" +
            "SELECT " +
            "    report_code, " +
            "    name, " +
            "    system_ttl, " +
            "    user_ttl " +
            "FROM upoa_ksk_reports.ksk_report_orchestrator " +
            "ORDER BY report_code";
        
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql, new HashMap<>());
        // Преобразование в DTO
        // return ReportTypesDto.fromRows(rows);
        return null;  // TODO: Реализовать преобразование
    }

    /**
     * Список пользовательских отчётов с фильтрацией
     */
    public PaginatedReportListDto getUserReports(String status, Integer limit, Integer offset, String username) {
        // TODO: Реализовать
        return null;
    }

    /**
     * Создать новый пользовательский отчёт
     */
    public CreatedReportDto createUserReport(CreateReportRequest request, String username) {
        // TODO: Реализовать
        return null;
    }

    /**
     * Добавить отчёт в очередь на обработку
     */
    public void enqueueReportProcessing(Long reportId) {
        // TODO: Отправить в Kafka/очередь
    }

    /**
     * Получить статус пользовательского отчёта
     */
    public ReportStatusDto getReportStatus(Long reportId, String username) {
        // TODO: Реализовать
        return null;
    }

    /**
     * Получить header пользовательского отчёта
     */
    public ReportHeaderDto getReportHeader(Long reportId, String username) {
        // TODO: Реализовать
        return null;
    }

    /**
     * Удалить пользовательский отчёт
     */
    public void deleteUserReport(Long reportId, String username) {
        // TODO: Реализовать
    }
}
