package ru.example.ksk.service;

import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import ru.example.ksk.dto.*;
import ru.example.ksk.repository.ReportRepository;
import ru.example.ksk.repository.ReportDataRepository;

import java.time.LocalDate;

/**
 * Сервис для работы с отчётами КСК (v2.0)
 * 
 * 🔄 ПЕРЕПИСАНО: getSystemReportData() теперь ищет report_header
 * 
 * НОВАЯ АРХИТЕКТУРА:
 * 1. getSystemReportData(reportCode, date) 
 *    → ReportRepository.getSystemReportHeaderId(reportCode, date)
 *    → ReportDataRepository.getReportDataByHeaderId(headerId)
 * 
 * ПРЕИМУЩЕСТВА:
 * - Единая таблица report_header для контроля версий
 * - Статус отчёта (created, in_progress, done, error)
 * - TTL и удаление старых версий
 * - Кэширование и реиспользование отчётов
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ReportService {

    private final ReportRepository reportRepository;
    private final ReportDataRepository dataRepository;
    private final ExportService exportService;

    // ========== СИСТЕМНЫЕ ОТЧЁТЫ ==========

    /**
     * Получить диапазон доступных дат для системных отчётов
     */
    public DateRangeDto getAvailableDates() {
        return reportRepository.getAvailableDateRange();
    }

    /**
     * 🆕 ПОЛУЧИТЬ ДАННЫЕ СИСТЕМНОГО ОТЧЁТА (v2.0)
     * 
     * НОВАЯ ЛОГИКА:
     * 1. Ищем report_header по (reportCode, date, initiator='system')
     *    SELECT id FROM ksk_report_header 
     *    WHERE orchestrator_id = (SELECT id FROM ksk_report_orchestrator WHERE report_code = ?)
     *      AND DATE(created_datetime) = ?
     *      AND initiator = 'system'
     *    LIMIT 1
     * 
     * 2. Получаем данные по report_header_id
     *    SELECT * FROM ksk_report_totals_data WHERE report_header_id = ?
     * 
     * ПРЕИМУЩЕСТВА vs v1.0:
     * ✅ Версионирование (можно хранить несколько версий за дату)
     * ✅ Статус (можем видеть статус создания отчёта)
     * ✅ TTL (автоматическое удаление старых отчётов)
     * ✅ Кэширование (можем переиспользовать отчёт)
     * ✅ Аудит (who, when, initiator)
     * 
     * СТАРАЯ ЛОГИКА (v1.0):
     * Прямое чтение из ksk_report_totals_data WHERE report_date = date
     */
    public ReportDataDto getSystemReportData(String reportCode, LocalDate date, Integer limit, Integer offset) {
        // ШАГ 1: Получаем report_header_id по (reportCode, date, initiator='system')
        Long reportHeaderId = reportRepository.getSystemReportHeaderId(reportCode, date);
        
        if (reportHeaderId == null) {
            throw new RuntimeException("Отчёт не найден: reportCode=" + reportCode + ", date=" + date);
        }
        
        // ШАГ 2: Получаем данные отчёта по report_header_id
        // Репозиторий автоматически выбирает правильную таблицу по типу отчёта
        return dataRepository.getReportDataByHeaderId(reportHeaderId, limit, offset);
    }

    /**
     * Экспорт системного отчёта
     */
    public ResponseEntity<byte[]> exportSystemReport(String reportCode, LocalDate date, String format) {
        var data = getSystemReportData(reportCode, date, 999999, 0);
        return exportService.exportReportData(data, reportCode, format);
    }

    // ========== ПОЛЬЗОВАТЕЛЬСКИЕ ОТЧЁТЫ ==========

    /**
     * Получить список доступных типов отчётов
     */
    public ReportTypesDto getReportTypes() {
        return reportRepository.getReportTypes();
    }

    /**
     * Список пользовательских отчётов с фильтрацией
     */
    public PaginatedReportListDto getUserReports(String status, Integer limit, Integer offset, String username) {
        return reportRepository.getUserReports(status, limit, offset, username);
    }

    /**
     * Создать новый пользовательский отчёт
     */
    @Transactional
    public CreatedReportDto createUserReport(CreateReportRequest request, String username) {
        var report = reportRepository.createUserReport(request, username);
        reportRepository.enqueueReportProcessing(report.getId());
        return report;
    }

    /**
     * Получить статус пользовательского отчёта
     */
    public ReportStatusDto getUserReportStatus(Long reportId, String username) {
        return reportRepository.getReportStatus(reportId, username);
    }

    /**
     * Получить данные пользовательского отчёта
     */
    public ReportDataDto getUserReportData(Long reportId, Integer limit, Integer offset, String username) {
        var reportHeader = reportRepository.getReportHeader(reportId, username);
        return dataRepository.getReportDataByHeaderId(reportHeader.getId(), limit, offset);
    }

    /**
     * Удалить пользовательский отчёт
     */
    @Transactional
    public DeletedReportDto deleteUserReport(Long reportId, String username) {
        reportRepository.deleteUserReport(reportId, username);
        return new DeletedReportDto("Отчет успешно удален", reportId);
    }

    /**
     * Экспорт пользовательского отчёта
     */
    public ResponseEntity<byte[]> exportUserReport(Long reportId, String format, String username) {
        var data = getUserReportData(reportId, 999999, 0, username);
        return exportService.exportReportData(data, format);
    }
}
