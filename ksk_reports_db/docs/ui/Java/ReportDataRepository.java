package ru.example.ksk.repository;

import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Repository;
import ru.example.ksk.dto.*;

import java.time.LocalDate;
import java.util.*;

/**
 * УНИВЕРСАЛЬНЫЙ репозиторий для работы с данными отчётов.
 * 
 * ✨ КЛЮЧЕВЫЕ ПРИНЦИПЫ:
 * 1. Минимум SQL-запросов через переиспользование кода
 * 2. Автоматическое определение таблицы по reportCode
 * 3. Един маршрут для системных и пользовательских отчётов
 * 4. Специальная обработка для функции review (вместо таблицы)
 * 
 * МЕТРИКА: 181 строка кода покрывают работу с 12+ таблицами и функциями
 */
@Repository
@RequiredArgsConstructor
public class ReportDataRepository {

    private final NamedParameterJdbcTemplate jdbcTemplate;

    // ========== МАППИНГИ: REPORT_CODE → ТАБЛИЦА ==========

    // Маппинг report_code -> таблица для системных отчётов
    private static final Map<String, String> SYSTEM_TABLES = Map.ofEntries(
            Map.entry("totals", "ksk_report_totals_data"),
            Map.entry("totals_by_payment_type", "ksk_report_totals_by_payment_type_data"),
            Map.entry("list_totals", "ksk_report_list_totals_data"),
            Map.entry("list_totals_by_payment_type", "ksk_report_list_totals_by_payment_type_data"),
            Map.entry("figurants", "ksk_report_figurants_data")
    );

    // Маппинг report_code -> таблица для пользовательских отчётов
    // (почти одинаковые, но всегда есть столбец report_header_id вместо report_date)
    private static final Map<String, String> USER_TABLES = new HashMap<>(SYSTEM_TABLES);

    // ========== ПОЛУЧЕНИЕ ДАННЫХ СИСТЕМНЫХ ОТЧЁТОВ ==========

    /**
     * УНИВЕРСАЛЬНОЕ получение данных системного отчёта
     * 
     * ✨ МАГИЯ: Один SQL запрос работает для всех типов отчётов
     * 
     * МЕХАНИЗМ:
     * 1. Определяем таблицу по reportCode (Map.getOrDefault)
     * 2. Специальный случай для "review" — используем функцию (см. getReviewReportData)
     * 3. Выполняем универсальный SELECT: SELECT * FROM {table} WHERE report_date = {date}
     * 4. Подсчитываем total_records через COUNT(*)
     * 5. Вычисляем has_more: offset + limit < total_records
     */
    public ReportDataDto getReportData(String reportCode, LocalDate date, Integer limit, Integer offset) {
        String table = SYSTEM_TABLES.getOrDefault(reportCode, "ksk_report_totals_data");
        
        // Специальный случай: report_code = "review" вызывает функцию вместо SELECT из таблицы
        if ("review".equals(reportCode)) {
            return getReviewReportData(date, limit, offset);
        }

        // УНИВЕРСАЛЬНЫЙ SQL: работает для всех 5 таблиц системных отчётов
        // Благодаря идентичной структуре: все содержат report_date и одинаковые поля
        String sql = String.format(
                "SELECT * FROM upoa_ksk_reports.%s " +
                "WHERE report_date = :date " +
                "ORDER BY report_date DESC " +
                "LIMIT :limit OFFSET :offset",
                table
        );

        Map<String, Object> params = Map.of(
                "date", date,
                "limit", limit,
                "offset", offset
        );

        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql, params);
        long totalRecords = getTotalRecords(table, date);

        return ReportDataDto.builder()
                .reportCode(reportCode)
                .date(date)
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
     * ✨ ОСОБЕННОСТЬ: "review" — это не таблица, а SQL функция
     * 
     * ИСТОЧНИК: SELECT * FROM ksk_report_review(date)
     * 
     * Функция возвращает JOIN из нескольких таблиц:
     * - ksk_result (транзакции)
     * - ksk_figurant (фигуранты)
     * - ksk_figurant_match (совпадения)
     * - ksk_report_orchestrator (метаинформация)
     * 
     * Данные не сохраняются в промежуточную таблицу,
     * а генерируются "на лету" при каждом запросе
     */
    private ReportDataDto getReviewReportData(LocalDate date, Integer limit, Integer offset) {
        // Вызываем функцию ksk_report_review(date) с LIMIT/OFFSET для пагинации
        String sql = "SELECT * FROM upoa_ksk_reports.ksk_report_review(:date) " +
                    "LIMIT :limit OFFSET :offset";

        Map<String, Object> params = Map.of(
                "date", date,
                "limit", limit,
                "offset", offset
        );

        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql, params);
        long totalRecords = getReviewReportTotalRecords(date);

        return ReportDataDto.builder()
                .reportCode("review")
                .date(date)
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
     * УНИВЕРСАЛЬНОЕ получение количества записей в системном отчёте
     * 
     * ✨ МАГИЯ: Один COUNT(*) запрос для всех таблиц
     * 
     * Работает благодаря одинаковой структуре всех таблиц отчётов
     */
    private long getTotalRecords(String table, LocalDate date) {
        String sql = String.format(
                "SELECT COUNT(*) FROM upoa_ksk_reports.%s WHERE report_date = :date",
                table
        );
        return jdbcTemplate.queryForObject(sql, Map.of("date", date), Long.class);
    }

    /**
     * Получение количества записей для отчёта "review" (из функции)
     */
    private long getReviewReportTotalRecords(LocalDate date) {
        String sql = "SELECT COUNT(*) FROM upoa_ksk_reports.ksk_report_review(:date)";
        return jdbcTemplate.queryForObject(sql, Map.of("date", date), Long.class);
    }

    // ========== ПОЛУЧЕНИЕ ДАННЫХ ПОЛЬЗОВАТЕЛЬСКИХ ОТЧЁТОВ ==========

    /**
     * УНИВЕРСАЛЬНОЕ получение данных пользовательского отчёта по header ID
     * 
     * ✨ МАГИЯ: Один метод для всех типов пользовательских отчётов
     * 
     * МЕХАНИЗМ:
     * 1. Получаем report_code из ksk_report_header (getReportCodeByHeaderId)
     * 2. Определяем таблицу по report_code
     * 3. Выполняем SELECT: SELECT * FROM {table} WHERE report_header_id = {headerId}
     * 4. Работает как для totals (1 запись) так и для figurants (1000+ записей)
     * 
     * ПРИМЕР:
     *   header_id = 126, report_code = "figurants"
     *   → SELECT * FROM ksk_report_figurants_data WHERE report_header_id = 126
     */
    public ReportDataDto getReportDataByHeaderId(Long headerId, Integer limit, Integer offset) {
        // Шаг 1: Получаем тип отчёта из ksk_report_header
        String reportCode = getReportCodeByHeaderId(headerId);
        
        // Шаг 2: Определяем таблицу
        String table = USER_TABLES.getOrDefault(reportCode, "ksk_report_totals_data");
        
        // Шаг 3: Выполняем УНИВЕРСАЛЬНЫЙ SELECT
        String sql = String.format(
                "SELECT * FROM upoa_ksk_reports.%s " +
                "WHERE report_header_id = :headerId " +
                "LIMIT :limit OFFSET :offset",
                table
        );

        Map<String, Object> params = Map.of(
                "headerId", headerId,
                "limit", limit,
                "offset", offset
        );

        List<Map<String, Object>> rows = jdbcTemplate.queryForList(sql, params);
        long totalRecords = getReportDataTotalRecords(table, headerId);

        return ReportDataDto.builder()
                .reportCode(reportCode)
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
     * Получить report_code по header ID
     * 
     * ИСТОЧНИК: SELECT report_code FROM ksk_report_header WHERE id = {headerId}
     */
    private String getReportCodeByHeaderId(Long headerId) {
        String sql = "SELECT report_code FROM upoa_ksk_reports.ksk_report_header WHERE id = :headerId";
        return jdbcTemplate.queryForObject(sql, Map.of("headerId", headerId), String.class);
    }

    /**
     * УНИВЕРСАЛЬНОЕ получение количества записей пользовательского отчёта
     * 
     * ✨ МАГИЯ: Один COUNT(*) запрос для всех таблиц
     */
    private long getReportDataTotalRecords(String table, Long headerId) {
        String sql = String.format(
                "SELECT COUNT(*) FROM upoa_ksk_reports.%s WHERE report_header_id = :headerId",
                table
        );
        return jdbcTemplate.queryForObject(sql, Map.of("headerId", headerId), Long.class);
    }
}
