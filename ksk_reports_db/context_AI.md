
# Сделай сжатую выгрузку нашего диалога в md файл.

В ней такой контекст чтобы я мог потом дать его тебе или другому ИИ для быстрого погружения в тему когда придется открыть новый диалог.

К сожалению, я исчерпал лимит на использование инструментов и не могу создать файл напрямую. Но я предоставлю вам полный контент MD файла, который вы можете скопировать и сохранить самостоятельно:

***

# Контекст проекта: Система отчетов КСК (PostgreSQL)

**Дата:** 2025-10-25
**БД:** PostgreSQL
**Схема:** `upoa_ksk_reports`

***

## Архитектура системы

### Основные таблицы данных (партиционированные)

1. **ksk_result** - транзакции КСК
    - Партиционирование: по `output_timestamp` (daily)
    - Поля: corr_id, resolution, has_bypass, list_codes, payment_type
    - Дополнительные поля платежей: payment_id, payer_*, receiver_*, amount, currency
2. **ksk_figurant** - фигуранты из санкционных списков
    - Партиционирование: по `timestamp` (daily)
    - Поля: source_id, list_code, name_figurant, president_group, auto_login, has_exclusion, exclusion_phrase, is_bypass
    - Связь: source_id → ksk_result.id
3. **ksk_figurant_match** - совпадения
    - Партиционирование: по `timestamp` (daily)
    - Поля: figurant_id, algorithm, match_value, match_payment_field, match_payment_value
    - Связь: figurant_id → ksk_figurant.id

### Таблицы отчётов

- **ksk_report_orchestrator** - метаданные типов отчётов (5 типов)
- **ksk_report_header** - заголовки созданных отчётов
- **ksk_report_totals_data** - общая статистика
- **ksk_report_list_totals_data** - итоги по спискам
- **ksk_report_totals_by_payment_type_data** - статистика по типам платежей
- **ksk_report_list_totals_by_payment_type_data** - итоги по спискам и типам
- **ksk_report_figurants_data** - отчёт по фигурантам


### Служебные таблицы

- **ksk_system_operations_log** - системный лог всех операций

***

## Типы платежей (русские названия)

В системе используются **русские названия** типов платежей (не коды I/O/T/M/V):

- Входящий
- Исходящий
- Транзитный
- Межфилиальный
- Внутрифилиальный

***

## Ключевые функции

### Управление партициями

- `ksk_create_partitions(table_name, base_date, days_ahead)` - создать партиции для таблицы
- `ksk_create_partitions_for_all_tables(base_date, days_ahead)` - создать для всех таблиц
- `ksk_list_partitions(table_name)` - список партиций
- `ksk_drop_old_partitions(cutoff_days)` - удалить старые партиции
- `ksk_cleanup_empty_partitions(table_name, days_old)` - удалить пустые партиции


### Очистка данных

- `ksk_cleanup_empty_records(days_old)` - удалить пустые записи (resolution='empty')
- `ksk_cleanup_with_logging(days_old)` - то же с логированием


### Генерация отчётов

- `ksk_run_report(report_code, initiator, user_login, start_date, end_date, parameters)` - универсальная функция
- `ksk_report_totals()` - общая статистика
- `ksk_report_list_totals()` - итоги по спискам
- `ksk_report_totals_by_payment_type()` - по типам платежей
- `ksk_report_list_totals_by_payment_type()` - по спискам и типам
- `ksk_report_figurants()` - по фигурантам
- `ksk_report_review(report_date)` - детальный отчёт review
- `ksk_cleanup_old_reports()` - удалить устаревшие отчёты


### Служебные

- `ksk_log_operation(operation_code, operation_name, begin_time, status, info, err_msg)` - запись в лог

***

## Важные решения

### Оптимизации

1. **Использование структурированных полей** вместо JSON в отчётах:
    - `ksk_figurant` содержит распакованные поля: list_code, name_figurant и т.д.
    - Отчёты используют эти поля напрямую → в 5-10 раз быстрее
2. **Оптимизация проверки пустоты партиций**:
    - Вместо `SELECT COUNT(*) FROM table` используется `SELECT NOT EXISTS (SELECT 1 FROM table LIMIT 1)`
3. **Системное логирование**:
    - Все операции записываются в `ksk_system_operations_log`
    - Автоматический расчёт длительности операции

### Конвенции именования

- Все функции: префикс `ksk_`
- Старые функции без префикса удаляются при миграции
- Партиции: `part_{table_name}_YYYY_MM_DD`


### TTL отчётов

| Тип отчёта | System TTL | User TTL |
| :-- | :-- | :-- |
| totals, list_totals, по типам платежей | 365 дней | 14 дней |
| figurants | 30 дней | 7 дней |


***

## Примеры использования

### Создание партиций

```sql
-- Создать партиции на 30 дней вперёд
SELECT upoa_ksk_reports.ksk_create_partitions_for_all_tables(CURRENT_DATE, 30);
```


### Генерация отчётов

```sql
-- Системный отчёт за вчера
SELECT upoa_ksk_reports.ksk_run_report('totals', 'system', NULL, CURRENT_DATE - 1, NULL, NULL);

-- Пользовательский отчёт с фильтром
SELECT upoa_ksk_reports.ksk_run_report(
    'figurants', 
    'user', 
    'ivanov', 
    '2025-10-20', 
    '2025-10-22', 
    '{"list_codes": ["4200", "4204"]}'::JSONB
);
```


### Очистка данных

```sql
-- Удалить пустые записи старше 14 дней
SELECT * FROM upoa_ksk_reports.ksk_cleanup_with_logging(14);

-- Удалить пустые партиции старше 7 дней
SELECT * FROM upoa_ksk_reports.ksk_cleanup_empty_partitions('all', 7);

-- Удалить устаревшие отчёты
SELECT upoa_ksk_reports.ksk_cleanup_old_reports();
```


***

## Файлы миграции

**Основной файл:** `ksk-full-migration.sql`

Включает:

- 11 таблиц (3 основных + 1 служебная + 7 отчётных)
- 15 функций
- Инициализацию оркестратора
- Проверку существования таблиц (не удаляет данные)
- Удаление старых функций (без префикса ksk_)

**Запуск:**

```bash
psql -h localhost -U postgres -d your_database -f ksk-full-migration.sql
```


***

## Ежедневные задачи (cron)

1. **02:00** - Очистка устаревших отчётов
2. **03:00** - Генерация ежедневных отчётов (totals, list_totals, по типам)
3. **04:00** - Генерация недельных отчётов (понедельник)
4. **05:00** - ANALYZE таблиц

***

## Известные проблемы и решения

- ❌ **Vacuum не включён** - функционал намеренно убран, выполняется отдельно
- ✅ **Русские типы платежей** - в запросах используются полные названия, не коды
- ✅ **Схема** - все объекты в `upoa_ksk_reports`, не в public
- ✅ **Логирование** - все операции пишут в `ksk_system_operations_log`

***

**Этот документ содержит весь контекст для быстрого возобновления работы над проектом.**

***

**Скопируйте этот текст и сохраните как `project-context.md`. При следующем диалоге просто прикрепите этот файл!**

