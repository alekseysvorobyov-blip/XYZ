package ru.example.ksk.controller;

import lombok.RequiredArgsConstructor;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import ru.example.ksk.dto.*;
import ru.example.ksk.service.ReportService;

import java.time.LocalDate;

/**
 * REST контроллер для работы с отчётами КСК (v2.0)
 * 
 * 🔄 ПЕРЕПИСАНО: getSystemReportData() теперь работает через report_header
 * 
 * НОВАЯ ЛОГИКА:
 * 1. Получаем report_header_id по (reportCode, date, initiator='system')
 * 2. Используем report_header_id для получения данных из таблицы отчёта
 * 
 * ✨ ПРЕИМУЩЕСТВА:
 * - Единая точка входа для всех отчётов через report_header
 * - Контроль доступа и статус отчёта в одном месте
 * - Кэширование и версионирование отчётов
 */
@RestController
@RequestMapping("/api/reports")
@RequiredArgsConstructor
public class ReportController {

    private final ReportService reportService;

    // ========== СИСТЕМНЫЕ ОТЧЁТЫ ==========

    /**
     * GET /api/reports/system/available-dates
     * Получить доступные даты для системных отчётов
     */
    @GetMapping("/system/available-dates")
    public ResponseEntity<DateRangeDto> getAvailableDates() {
        return ResponseEntity.ok(reportService.getAvailableDates());
    }

    /**
     * 🆕 GET /api/reports/system/{reportCode}/data
     * 
     * НОВАЯ ЛОГИКА (v2.0):
     * 1. Находим report_header по (reportCode, date, initiator='system')
     * 2. Получаем данные по report_header_id из таблицы отчёта
     * 
     * СТАРАЯ ЛОГИКА (v1.0):
     * SELECT * FROM ksk_report_totals_data WHERE report_date = date
     * 
     * НОВАЯ ЛОГИКА (v2.0):
     * SELECT header_id FROM ksk_report_header 
     *   WHERE orchestrator_id=(SELECT id FROM ksk_report_orchestrator WHERE report_code=?) 
     *   AND report_date = ? 
     *   AND initiator = 'system'
     * THEN SELECT * FROM ksk_report_totals_data WHERE report_header_id = header_id
     */
    @GetMapping("/system/{reportCode}/data")
    public ResponseEntity<ReportDataDto> getSystemReportData(
            @PathVariable String reportCode,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @RequestParam(defaultValue = "100") Integer limit,
            @RequestParam(defaultValue = "0") Integer offset) {
        
        return ResponseEntity.ok(reportService.getSystemReportData(reportCode, date, limit, offset));
    }

    /**
     * GET /api/reports/system/{reportCode}/export/{format}
     * Универсальный экспорт системных отчётов (xlsx, csv, pdf)
     */
    @GetMapping("/system/{reportCode}/export/{format}")
    public ResponseEntity<byte[]> exportSystemReport(
            @PathVariable String reportCode,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @PathVariable String format) {
        
        return reportService.exportSystemReport(reportCode, date, format);
    }

    // ========== ПОЛЬЗОВАТЕЛЬСКИЕ ОТЧЁТЫ ==========

    /**
     * GET /api/reports/user/types
     * Получить список доступных типов отчётов
     */
    @GetMapping("/user/types")
    public ResponseEntity<ReportTypesDto> getReportTypes() {
        return ResponseEntity.ok(reportService.getReportTypes());
    }

    /**
     * GET /api/reports/user
     * Список пользовательских отчётов с фильтрацией
     */
    @GetMapping("/user")
    public ResponseEntity<PaginatedReportListDto> getUserReports(
            @RequestParam(defaultValue = "all") String status,
            @RequestParam(defaultValue = "50") Integer limit,
            @RequestParam(defaultValue = "0") Integer offset,
            Authentication auth) {
        
        String username = auth.getName();
        return ResponseEntity.ok(reportService.getUserReports(status, limit, offset, username));
    }

    /**
     * POST /api/reports/user
     * Создать новый пользовательский отчёт
     */
    @PostMapping("/user")
    public ResponseEntity<CreatedReportDto> createUserReport(
            @RequestBody CreateReportRequest request,
            Authentication auth) {
        
        String username = auth.getName();
        return ResponseEntity.status(201).body(reportService.createUserReport(request, username));
    }

    /**
     * GET /api/reports/user/{reportId}/status
     * Получить статус пользовательского отчёта
     */
    @GetMapping("/user/{reportId}/status")
    public ResponseEntity<ReportStatusDto> getUserReportStatus(
            @PathVariable Long reportId,
            Authentication auth) {
        
        String username = auth.getName();
        return ResponseEntity.ok(reportService.getUserReportStatus(reportId, username));
    }

    /**
     * GET /api/reports/user/{reportId}/data
     * Получить данные готового пользовательского отчёта
     */
    @GetMapping("/user/{reportId}/data")
    public ResponseEntity<ReportDataDto> getUserReportData(
            @PathVariable Long reportId,
            @RequestParam(defaultValue = "100") Integer limit,
            @RequestParam(defaultValue = "0") Integer offset,
            Authentication auth) {
        
        String username = auth.getName();
        return ResponseEntity.ok(reportService.getUserReportData(reportId, limit, offset, username));
    }

    /**
     * DELETE /api/reports/user/{reportId}
     * Удалить пользовательский отчёт
     */
    @DeleteMapping("/user/{reportId}")
    public ResponseEntity<DeletedReportDto> deleteUserReport(
            @PathVariable Long reportId,
            Authentication auth) {
        
        String username = auth.getName();
        return ResponseEntity.ok(reportService.deleteUserReport(reportId, username));
    }

    /**
     * GET /api/reports/user/{reportId}/export/{format}
     * Экспорт пользовательского отчёта
     */
    @GetMapping("/user/{reportId}/export/{format}")
    public ResponseEntity<byte[]> exportUserReport(
            @PathVariable Long reportId,
            @PathVariable String format,
            Authentication auth) {
        
        String username = auth.getName();
        return reportService.exportUserReport(reportId, format, username);
    }
}
