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
 * REST контроллер для работы с отчётами КСК.
 * Минимум кода, максимум функциональности через сервисный слой.
 * 
 * ✨ ПАТТЕРН АРХИТЕКТУРЫ:
 * - Контроллер: только маршрутизация + аутентификация (56 строк)
 * - Сервис: бизнес-логика (115 строк)
 * - Репозиторий: УНИВЕРСАЛЬНАЯ работа с БД (181 строка)
 * 
 * ИТОГО: 452 строки покрывают 10 REST endpoints для системных и пользовательских отчётов
 */
@RestController
@RequestMapping("/api/reports")
@RequiredArgsConstructor
public class ReportController {

    private final ReportService reportService;

    // ========== СИСТЕМНЫЕ ОТЧЁТЫ (4 endpoint) ==========

    /**
     * GET /api/reports/system/available-dates
     * Получить доступные даты для системных отчётов
     */
    @GetMapping("/system/available-dates")
    public ResponseEntity<DateRangeDto> getAvailableDates() {
        return ResponseEntity.ok(reportService.getAvailableDates());
    }

    /**
     * GET /api/reports/system/{reportCode}/data
     * Универсальное получение данных системных отчётов любого типа
     * Типы: totals, totals_by_payment_type, list_totals, list_totals_by_payment_type, figurants, review
     * 
     * УНИВЕРСАЛЬНОСТЬ: Один метод обрабатывает все 6 типов отчётов
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
     * 
     * УНИВЕРСАЛЬНОСТЬ: Один метод для всех форматов и типов отчётов
     */
    @GetMapping("/system/{reportCode}/export/{format}")
    public ResponseEntity<byte[]> exportSystemReport(
            @PathVariable String reportCode,
            @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date,
            @PathVariable String format) {
        
        return reportService.exportSystemReport(reportCode, date, format);
    }

    // ========== ПОЛЬЗОВАТЕЛЬСКИЕ ОТЧЁТЫ (6 endpoint) ==========

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
     * 
     * Параметры:
     * - status: all, created, in_progress, done, error
     * - limit: 1-100 (default 50)
     * - offset: для пагинации (default 0)
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
     * 
     * Тело запроса:
     * {
     *   "report_code": "figurants",
     *   "start_date": "2025-10-01",
     *   "end_date": "2025-10-25",
     *   "parameters": { "list_codes": ["4200", "4204"] }
     * }
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
     * 
     * Возвращает:
     * - status: created, in_progress, done, error
     * - created_datetime, finished_datetime
     * - message: описание статуса
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
     * 
     * УНИВЕРСАЛЬНОСТЬ: Один метод для всех типов пользовательских отчётов
     * Автоматически определяет тип отчёта и выбирает правильную таблицу
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
     * 
     * Каскадное удаление: кроме ksk_report_header удаляются связанные данные
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
     * Экспорт пользовательского отчёта (xlsx, csv, pdf)
     * 
     * УНИВЕРСАЛЬНОСТЬ: Один метод для всех форматов и типов отчётов
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
