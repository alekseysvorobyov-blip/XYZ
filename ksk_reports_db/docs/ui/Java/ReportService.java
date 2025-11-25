package ru.example.ksk.service;

import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import ru.example.ksk.dto.*;
import ru.example.ksk.repository.ReportRepository;
import ru.example.ksk.repository.ReportDataRepository;

import java.time.LocalDate;
import java.util.Map;

/**
 * Сервис для работы с отчётами КСК.
 * 
 * ПРИНЦИП: Минимум логики в контроллере, максимум в сервисе.
 * 
 * ✨ ОСОБЕННОСТИ:
 * 1. Универсальные методы для системных и пользовательских отчётов
 * 2. Автоматическое определение типа отчёта и выбор таблицы/функции
 * 3. Единая точка входа для экспорта (xlsx, csv, pdf)
 * 4. Проверка ownership через username для безопасности
 * 5. Асинхронная обработка пользовательских отчётов
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ReportService {

    private final ReportRepository reportRepository;
    private final ReportDataRepository dataRepository;
    private final ExportService exportService;

    // ========== СИСТЕМНЫЕ ОТЧЁТЫ (6 методов) ==========

    /**
     * Получить диапазон доступных дат для системных отчётов
     * 
     * ИСТОЧНИК: SELECT MIN(report_date), MAX(report_date) FROM всех таблиц
     */
    public DateRangeDto getAvailableDates() {
        return reportRepository.getAvailableDateRange();
    }

    /**
     * УНИВЕРСАЛЬНОЕ получение данных системных отчётов
     * 
     * ✨ КЛЮЧЕВАЯ ФИШКА: Автоматически определяет тип отчёта и выбирает:
     *   - таблицу: ksk_report_totals_data, ksk_report_list_totals_data и т.д.
     *   - или функцию: ksk_report_review(date)
     * 
     * Работает для всех 6 типов отчётов:
     * - totals
     * - totals_by_payment_type
     * - list_totals
     * - list_totals_by_payment_type
     * - figurants
     * - review (специальный случай: функция вместо таблицы)
     * 
     * ПРИМЕР:
     *   getSystemReportData("totals", 2025-10-25, 100, 0)
     *   → SELECT * FROM ksk_report_totals_data WHERE report_date = 2025-10-25 LIMIT 100 OFFSET 0
     */
    public ReportDataDto getSystemReportData(String reportCode, LocalDate date, Integer limit, Integer offset) {
        var reportData = dataRepository.getReportData(reportCode, date, limit, offset);
        return reportData;
    }

    /**
     * УНИВЕРСАЛЬНЫЙ экспорт системных отчётов
     * Поддерживает: xlsx, csv, pdf
     * 
     * ✨ КЛЮЧЕВАЯ ФИШКА: Один метод для всех форматов
     * Формат определяется из параметра и передаётся в ExportService
     */
    public ResponseEntity<byte[]> exportSystemReport(String reportCode, LocalDate date, String format) {
        var data = getSystemReportData(reportCode, date, 999999, 0);
        return exportService.exportReportData(data, reportCode, format);
    }

    // ========== ПОЛЬЗОВАТЕЛЬСКИЕ ОТЧЁТЫ (6 методов) ==========

    /**
     * Получить список доступных типов отчётов
     * 
     * ИСТОЧНИК: SELECT * FROM ksk_report_orchestrator
     * 
     * Возвращает для каждого типа:
     * - report_code (totals, figurants и т.д.)
     * - name (человекочитаемое имя)
     * - description
     * - user_ttl (время жизни пользовательской версии)
     * - supports_parameters (нужны ли параметры)
     * - parameters_schema (JSON schema для валидации)
     */
    public ReportTypesDto getReportTypes() {
        return reportRepository.getReportTypes();
    }

    /**
     * Список пользовательских отчётов с фильтрацией и пагинацией
     * 
     * ✨ БЕЗОПАСНОСТЬ: Фильтруем по username (ownership check)
     * 
     * ИСТОЧНИК: SELECT * FROM ksk_report_header
     *   WHERE initiator = 'user' AND user_login = {username} AND status = {status}
     * 
     * Параметры:
     * - status: all, created, in_progress, done, error
     * - limit, offset: для пагинации
     * - username: текущий пользователь (из Spring Security)
     */
    public PaginatedReportListDto getUserReports(String status, Integer limit, Integer offset, String username) {
        return reportRepository.getUserReports(status, limit, offset, username);
    }

    /**
     * Создать новый пользовательский отчёт
     * 
     * ✨ АСИНХРОННОСТЬ: Не ждём генерации, сразу возвращаем 201 Created
     * 
     * ПРОЦЕСС:
     * 1. Вставляем запись в ksk_report_header со статусом 'created'
     * 2. Отправляем задачу на обработку (очередь/Kafka/другое)
     * 3. Возвращаем информацию о созданном отчёте
     * 4. UI начинает polling статуса (см. REST API спецификацию)
     * 
     * Валидация:
     * - report_code должен быть известным типом (из ksk_report_orchestrator)
     * - start_date <= end_date
     * - end_date <= CURRENT_DATE (не будущее)
     * - end_date - start_date <= 365 дней
     */
    @Transactional
    public CreatedReportDto createUserReport(CreateReportRequest request, String username) {
        var report = reportRepository.createUserReport(request, username);
        // Асинхронно отправляем на обработку (очередь, Kafka, scheduler и т.д.)
        reportRepository.enqueueReportProcessing(report.getId());
        return report;
    }

    /**
     * Получить статус пользовательского отчёта
     * 
     * ✨ БЕЗОПАСНОСТЬ: Проверяем ownership через username
     * 
     * ИСТОЧНИК: SELECT status, created_datetime, finished_datetime, error_message 
     *   FROM ksk_report_header WHERE id = {reportId} AND user_login = {username}
     * 
     * Возвращает разные поля в зависимости от статуса:
     * - created/in_progress: time_left, progress_percentage
     * - done: duration_seconds, rows_count
     * - error: error_message
     */
    public ReportStatusDto getUserReportStatus(Long reportId, String username) {
        return reportRepository.getReportStatus(reportId, username);
    }

    /**
     * Получить данные пользовательского отчёта
     * 
     * ✨ УНИВЕРСАЛЬНОСТЬ: Один метод для всех типов пользовательских отчётов
     * 
     * ПРОЦЕСС:
     * 1. Получаем тип отчёта из ksk_report_header (report_code)
     * 2. Определяем таблицу данных (ksk_report_totals_data, ksk_report_figurants_data и т.д.)
     * 3. Выполняем SELECT из правильной таблицы по report_header_id
     * 
     * ✨ БЕЗОПАСНОСТЬ: Проверяем ownership через username в getReportHeader()
     */
    public ReportDataDto getUserReportData(Long reportId, Integer limit, Integer offset, String username) {
        var reportHeader = reportRepository.getReportHeader(reportId, username);
        return dataRepository.getReportDataByHeaderId(reportHeader.getId(), limit, offset);
    }

    /**
     * Удалить пользовательский отчёт
     * 
     * ✨ КАСКАДНОЕ УДАЛЕНИЕ: При удалении из ksk_report_header
     * удаляются связанные данные из таблиц (ON DELETE CASCADE)
     * 
     * ✨ БЕЗОПАСНОСТЬ: Проверяем ownership через username
     */
    @Transactional
    public DeletedReportDto deleteUserReport(Long reportId, String username) {
        reportRepository.deleteUserReport(reportId, username);
        return new DeletedReportDto("Отчет успешно удален", reportId);
    }

    /**
     * УНИВЕРСАЛЬНЫЙ экспорт пользовательского отчёта
     * 
     * ✨ КЛЮЧЕВАЯ ФИШКА: Один метод для всех форматов (xlsx, csv, pdf)
     * и всех типов пользовательских отчётов
     * 
     * Формат определяется из параметра и передаётся в ExportService
     */
    public ResponseEntity<byte[]> exportUserReport(Long reportId, String format, String username) {
        var data = getUserReportData(reportId, 999999, 0, username);
        return exportService.exportReportData(data, format);
    }
}
