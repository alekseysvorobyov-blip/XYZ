package ru.example.ksk.repository;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;
import ru.example.ksk.dto.*;

import java.time.LocalDate;
import java.util.*;

/**
 * Репозиторий для получения данных отчётов (v2.0)
 * 
 * 🔄 ПЕРЕПИСАНО: Теперь работает через report_header_id
 * 
 * НОВАЯ ЛОГИКА:
 * 1. Получаем report_code из ksk_report_header по header_id
 * 2. Определяем таблицу данных по report_code
 * 3. SELECT * FROM {data_table} WHERE report_header_id = header_id
 * 
 * ПРЕИМУЩЕСТВА:
 * - Работает через единую точку входа (report_header)
 * - Автоматическое определение таблицы
 * - Поддержка versioning отчётов
 */
@Repository
@RequiredArgsConstructor
public class ReportDataRepository {

    private final NamedParameterJdbcTemplate jdbcTemplate;

    // Маппинг report_code → таблица данных
    private static final Map<String, String> REPORT_DATA_TABLES = Map.ofEntries(
            Map.entry("totals", "ksk_report_totals_data"),
            Map.entry("totals_by_payment_type", "ksk_report_totals_by_payment_type_data"),
            Map.entry("list_totals", "ksk_report_list_totals_data"),
            Map.entry("list_totals_by_payment_type", "ksk_report_list_totals_by_payment_type_data"),
            Map.entry("figurants", "ksk_report_figurants_data")
    );

    /**
     * 🆕 ПОЛУЧИТЬ ДАННЫЕ ОТЧЁТА ПО HEADER ID (v2.0)
     * 
     * ПРОЦЕСС:
     * 1. SELECT report_code FROM ksk_report_header WHERE id = header_id
     * 2. Определяем таблицу по report_code (из маппинга выше)
     * 3. SELECT * FROM {table} WHERE report_header_id = header_id
     * 4. Возвращаем данные с пагинацией
     * 
     * ПРЕИМУЩЕСТВА vs v1.0:
     * ✅ Работает через report_header (единая точка входа)
     * ✅ Автоматическое определение таблицы
     * ✅ Поддержка versioning отчётов
     * ✅ Может быть несколько версий за одну дату
     * 
     * СТАРАЯ ЛОГИКА (v1.0):
     * SELECT * FROM {table} WHERE report_date = date
     * 
     * НОВАЯ ЛОГИКА (v2.0):
     * SELECT * FROM {table} WHERE report_header_id = header_id
     */
    public ReportDataDto getReportDataByHeaderId(Long headerIdLong, Integer limit, Integer offset) {
        // ШАГ 1: Получаем report_code из report_header
        String sqlGetReportCode = "" +
            "SELECT " +
            "    ro.report_code, " +
            "    rh.created_datetime, " +
            "    rh.start_date, " +
            "    rh.end_date " +
            "FROM upoa_ksk_reports.ksk_report_header rh " +
            "JOIN upoa_ksk_reports.ksk_report_orchestrator ro ON rh.orchestrator_id = ro.id " +
            "WHERE rh.id = :headerId";
        
        Map<String, Object> headerInfo;
        try {
            headerInfo = jdbcTemplate.queryForMap(
                sqlGetReportCode,
                Map.of("headerId", headerIdLong)
            );
        } catch (org.springframework.dao.EmptyResultDataAccessException e) {
            throw new RuntimeException("Report header не найден: id=" + headerIdLong, e);
        }
        
        String reportCode = (String) headerInfo.get("report_code");
        LocalDate reportDate = ((java.sql.Date) headerInfo.get("created_datetime")).toLocalDate();
        
        // ШАГ 2: Определяем таблицу по report_code
        String dataTable = REPORT_DATA_TABLES.getOrDefault(reportCode, "ksk_report_totals_data");
        
        // ШАГ 3: Специальный случай для review (функция вместо таблицы)
        if ("review".equals(reportCode)) {
            return getReviewReportDataByHeaderId(headerIdLong, limit, offset);
        }
        
        // ШАГ 4: SELECT * FROM {table} WHERE report_header_id = ?
        String sqlGetData = String.format(
            "SELECT * FROM upoa_ksk_reports.%s " +
            "WHERE report_header_id = :headerId " +
            "LIMIT :limit OFFSET :offset",
            dataTable
        );
        
        Map<String, Object> params = Map.of(
            "headerId", headerIdLong,
            "limit", limit,
            "offset", offset
        );
        
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sqlGetData, params);
        long totalRecords = getTotalRecordsByHeaderId(dataTable, headerIdLong);
        
        return ReportDataDto.builder()
                .reportCode(reportCode)
                .date(reportDate)
                .data(rows)
                .pagination(PaginationDto.builder()
                        .totalRecords(totalRecords)
                        .limit(limit)
                        .offset(offset)
                        .hasMore(offset + limit < totalRecords)
                        .build())
                .build();
    }

    /**
     * Получение данных отчёта "review" через функцию
     * 
     * ЛОГИКА:
     * 1. SELECT * FROM ksk_report_review(report_date)
     * 2. Фильтруем по report_header_id (если необходимо)
     * 
     * ПРИМЕЧАНИЕ: review возвращает результат функции, а не таблицы
     */
    private ReportDataDto getReviewReportDataByHeaderId(Long headerId, Integer limit, Integer offset) {
        // Получаем дату из report_header
        String sqlGetDate = "SELECT DATE(created_datetime) as report_date FROM upoa_ksk_reports.ksk_report_header WHERE id = :headerId";
        LocalDate reportDate = jdbcTemplate.queryForObject(sqlGetDate, Map.of("headerId", headerId), LocalDate.class);
        
        // Вызываем функцию review
        String sqlGetData = "" +
            "SELECT * FROM upoa_ksk_reports.ksk_report_review(:date) " +
            "LIMIT :limit OFFSET :offset";
        
        Map<String, Object> params = Map.of(
            "date", reportDate,
            "limit", limit,
            "offset", offset
        );
        
        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sqlGetData, params);
        long totalRecords = getReviewReportTotalRecords(reportDate);
        
        return ReportDataDto.builder()
                .reportCode("review")
                .date(reportDate)
                .data(rows)
                .pagination(PaginationDto.builder()
                        .totalRecords(totalRecords)
                        .limit(limit)
                        .offset(offset)
                        .hasMore(offset + limit < totalRecords)
                        .build())
                .build();
    }

    /**
     * Получить количество записей по header_id
     */
    private long getTotalRecordsByHeaderId(String table, Long headerId) {
        String sql = String.format(
            "SELECT COUNT(*) FROM upoa_ksk_reports.%s WHERE report_header_id = :headerId",
            table
        );
        return jdbcTemplate.queryForObject(sql, Map.of("headerId", headerId), Long.class);
    }

    /**
     * Получить количество записей для review отчёта
     */
    private long getReviewReportTotalRecords(LocalDate date) {
        String sql = "SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_review(:date)";
        return jdbcTemplate.queryForObject(sql, Map.of("date", date), Long.class);
    }
}
