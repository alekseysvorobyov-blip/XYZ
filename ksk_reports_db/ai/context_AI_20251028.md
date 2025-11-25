
# ИС КСК - Контекст проекта для AI

**Дата создания:** 28 октября 2025
**Версия:** 2.1
**Статус:** Production Ready

***

## 📋 Оглавление

1. [О проекте](#%D0%BE-%D0%BF%D1%80%D0%BE%D0%B5%D0%BA%D1%82%D0%B5)
2. [Архитектура системы](#%D0%B0%D1%80%D1%85%D0%B8%D1%82%D0%B5%D0%BA%D1%82%D1%83%D1%80%D0%B0-%D1%81%D0%B8%D1%81%D1%82%D0%B5%D0%BC%D1%8B)
3. [Структура базы данных](#%D1%81%D1%82%D1%80%D1%83%D0%BA%D1%82%D1%83%D1%80%D0%B0-%D0%B1%D0%B0%D0%B7%D1%8B-%D0%B4%D0%B0%D0%BD%D0%BD%D1%8B%D1%85)
4. [Система отчётности](#%D1%81%D0%B8%D1%81%D1%82%D0%B5%D0%BC%D0%B0-%D0%BE%D1%82%D1%87%D1%91%D1%82%D0%BD%D0%BE%D1%81%D1%82%D0%B8)
5. [Мониторинг](#%D0%BC%D0%BE%D0%BD%D0%B8%D1%82%D0%BE%D1%80%D0%B8%D0%BD%D0%B3)
6. [Оптимизации производительности](#%D0%BE%D0%BF%D1%82%D0%B8%D0%BC%D0%B8%D0%B7%D0%B0%D1%86%D0%B8%D0%B8-%D0%BF%D1%80%D0%BE%D0%B8%D0%B7%D0%B2%D0%BE%D0%B4%D0%B8%D1%82%D0%B5%D0%BB%D1%8C%D0%BD%D0%BE%D1%81%D1%82%D0%B8)
7. [Технологический стек](#%D1%82%D0%B5%D1%85%D0%BD%D0%BE%D0%BB%D0%BE%D0%B3%D0%B8%D1%87%D0%B5%D1%81%D0%BA%D0%B8%D0%B9-%D1%81%D1%82%D0%B5%D0%BA)
8. [Критические параметры](#%D0%BA%D1%80%D0%B8%D1%82%D0%B8%D1%87%D0%B5%D1%81%D0%BA%D0%B8%D0%B5-%D0%BF%D0%B0%D1%80%D0%B0%D0%BC%D0%B5%D1%82%D1%80%D1%8B)

***

## О проекте

**ИС КСК (Информационная система контроля соответствия контрагентов)** - система автоматизированной проверки финансовых транзакций на соответствие требованиям законодательства РФ по ПОД/ФТ (противодействие отмыванию доходов и финансированию терроризма).

### Назначение

- Автоматическая проверка транзакций по санкционным спискам
- Минимизация рисков пропуска транзакций с проблемными контрагентами
- Формирование отчётности для СФМ (Служба финансового мониторинга) и регуляторов
- Соблюдение требований ЦБ РФ и 115-ФЗ


### Бизнес-показатели

- Обработка: **~3 миллиона транзакций в день**
- Объём БД: **~3 TB** (основные данные)
- Retention: **365 дней** для основных данных, **30 дней** для отчётов
- SLA: Доступность **99.5%**, RTO **4 часа**, RPO **5 минут**

***

## Архитектура системы

```
┌─────────────────────┐
│  Banking Core       │
│  (Source System)    │
└──────────┬──────────┘
           ↓
┌──────────────────────────────────┐
│  Apache Kafka                    │
│  - upoa_enriched_transactions    │  <- Входящие транзакции
│  - upoa_ksk_results              │  <- Результаты проверки
└──────────┬───────────────────────┘
           ↓
┌──────────────────────────────────┐
│  KSK Consumer (Java/Spring Boot) │
│  - Join by corrId                │  <- Соединение пары сообщений
│  - Business Logic                │  <- Обработка совпадений
│  - Micrometer Metrics            │  <- Метрики для Prometheus
└──────────┬───────────────────────┘
           ↓
┌──────────────────────────────────┐
│  PostgreSQL 14+ Database         │
│  Schema: upoa_ksk_reports        │
│  - ksk_result (partitioned)      │  <- Основные данные (3TB)
│  - ksk_figurant (partitioned)    │  <- Фигуранты из списков
│  - ksk_figurant_match (part.)    │  <- Детали совпадений
│  - ksk_report_* (6 tables)       │  <- Система отчётности
│  - ksk_system_operation_log      │  <- Аудит операций
└──────────┬───────────────────────┘
           ↓
┌──────────────────────────────────┐
│  Reporting Module                │
│  - ksk_report_orchestrator       │  <- Управление отчётами
│  - 5 автоматических отчётов      │  <- Ежедневно в 03:00
│  - TTL-based cleanup             │  <- Автоудаление старых
└──────────┬───────────────────────┘
           ↓
┌──────────────────────────────────┐
│  Web UI (Browser)                │
│  - Просмотр отчётов              │
│  - Генерация по запросу          │
│  - Экспорт в Excel/CSV           │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│  Monitoring Stack                │
│  - Prometheus (метрики)          │
│  - Grafana (визуализация)        │
│  - Kafka Exporter                │
│  - PostgreSQL Exporter           │
└──────────────────────────────────┘
```


***

## Структура базы данных

### Схема: `upoa_ksk_reports`

#### 1. Основные таблицы данных (партиционированные по дате)

**ksk_result** - главная таблица транзакций

- Партиционирование: **RANGE по output_timestamp (daily)**
- Объём: ~3 TB, ~3M записей/день
- Retention: 365 дней
- JSONB поля: input_json, output_json (STORAGE EXTERNAL на HDD)

**Ключевые поля:**

```sql
id INTEGER (auto-increment)
date DATE NOT NULL
corr_id VARCHAR(100) NOT NULL -- для join сообщений
input_timestamp TIMESTAMP
output_timestamp TIMESTAMP NOT NULL
payment_type VARCHAR(20) -- I, O, T, M, V
resolution VARCHAR(20) -- allow, review, deny, empty
list_codes TEXT[] -- массив кодов санкционных списков
has_bypass VARCHAR(10) -- empty, yes, no
-- Структурированные поля из JSON
payment_id, payer_inn, payer_name, receiver_inn, receiver_name
amount, currency, ...
```

**ksk_figurant** - фигуранты из санкционных списков

- Партиционирование: **RANGE по timestamp (daily)**
- Связь: source_id → ksk_result.id (1:N)

**Ключевые поля:**

```sql
id INTEGER (auto-increment)
timestamp TIMESTAMP NOT NULL
source_id INTEGER -- FK to ksk_result.id
list_code VARCHAR(10) -- 4200, 4204, 4205, ...
name_figurant TEXT
president_group TEXT
auto_login TEXT
has_exclusion TEXT
exclusion_phrase TEXT
is_bypass TEXT
```

**ksk_figurant_match** - детали совпадений

- Партиционирование: **RANGE по timestamp (daily)**
- Связь: figurant_id → ksk_figurant.id (1:N)

**Ключевые поля:**

```sql
id INTEGER (auto-increment)
timestamp TIMESTAMP NOT NULL
figurant_id INTEGER -- FK to ksk_figurant.id
algorithm VARCHAR(50)
match_value TEXT
match_payment_field TEXT
match_payment_value TEXT
```


#### 2. Система отчётности (7 таблиц)

**ksk_report_orchestrator** - метаданные отчётов

```sql
id INTEGER PRIMARY KEY
report_code VARCHAR(50) UNIQUE -- totals, figurants, etc.
report_table VARCHAR(100) -- имя таблицы для хранения
report_function VARCHAR(100) -- функция генерации
name VARCHAR(200) -- описание
system_ttl INTEGER DEFAULT 30 -- TTL для system-отчётов (дни)
user_ttl INTEGER DEFAULT 7 -- TTL для user-отчётов (дни)
```

**Типы отчётов:**

1. **totals** - общая статистика (365/14 дней)
2. **totals_by_payment_type** - по типам платежей (365/14)
3. **list_totals** - по санкционным спискам (365/14)
4. **list_totals_by_payment_type** - список×тип (365/14)
5. **figurants** - детальный список фигурантов (30/7)
6. **review** - контрольный отчёт (30 дней)

**ksk_report_header** - заголовки отчётов

```sql
id INTEGER PRIMARY KEY
report_code VARCHAR(50) -- FK to orchestrator
initiator VARCHAR(20) -- 'system' или 'user'
user_login VARCHAR(100) -- для user-отчётов
start_date DATE
end_date DATE
parameters JSONB -- доп. параметры (фильтры)
status VARCHAR(20) -- created, in_progress, done, error
created_at TIMESTAMP
completed_at TIMESTAMP
error_message TEXT
```

**ksk_report_*_data** - 5 таблиц данных отчётов

- ksk_report_totals_data
- ksk_report_totals_by_payment_type_data
- ksk_report_list_totals_data
- ksk_report_list_totals_by_payment_type_data
- ksk_report_figurants_data


#### 3. Служебные таблицы

**ksk_system_operation_log** - аудит операций

```sql
id BIGINT PRIMARY KEY
operation_code VARCHAR(50)
operation_name VARCHAR(200)
start_time TIMESTAMP
end_time TIMESTAMP
status VARCHAR(20) -- success, error
info JSONB
error_message TEXT
```

**Операции:**

- create_partitions_all
- drop_old_partitions
- cleanup_empty_records
- cleanup_empty_partitions
- generate_report_* (для каждого типа)
- cleanup_old_reports

***

## Система отчётности

### Автоматические отчёты (pg_cron, ежедневно в 03:00)

```sql
-- Генерация 4 отчётов за предыдущий день
SELECT ksk_run_report('totals', 'system', NULL, CURRENT_DATE - 1);
SELECT ksk_run_report('totals_by_payment_type', 'system', NULL, CURRENT_DATE - 1);
SELECT ksk_run_report('list_totals', 'system', NULL, CURRENT_DATE - 1);
SELECT ksk_run_report('list_totals_by_payment_type', 'system', NULL, CURRENT_DATE - 1);
```


### Ручная генерация отчётов

```sql
-- Отчёт по фигурантам за период с фильтром
SELECT ksk_run_report(
  'figurants',
  'user',
  'ivanov',
  '2025-10-01',
  '2025-10-31',
  '{"list_codes": ["4200", "4204"]}'::jsonb
);
```


### TTL и автоочистка (pg_cron, ежедневно в 05:00)

```sql
-- Удаление устаревших отчётов
SELECT ksk_cleanup_old_reports();
```

Логика:

- **System-отчёты**: удаляются через `system_ttl` дней после создания
- **User-отчёты**: удаляются через `user_ttl` дней после создания

***

## Мониторинг

### 27 метрик в 3 категориях

#### Категория 1: Доступность компонента (5 метрик)

1. PostgreSQL connections (<300 норма, >400 критично)
2. Database size (рост ~100 GB/месяц)
3. Kafka consumer group members (1 норма, 0 критично)
4. Kafka topics availability
5. KSK Consumer Service health

#### Категория 2: Производительность (12 метрик)

1. PostgreSQL TPS (30-50 норма, <10 или >1000 критично)
2. Cache Hit Ratio (>99% норма, <95% критично)
3. Table Bloat % (0-10% норма, >30% критично)
4. Index Usage % (>90% оптимально, <50% критично)
5. Kafka Consumer Lag (<100K норма, >200K критично)
6. Kafka Messages Rate (<1300 msg/sec норма, >1500 критично)
7. PostgreSQL Locks (0-5 норма, >50 проверка)
8. Checkpoints ratio
9. Database Age (<1B норма, >1.5B критично)
10. Temporary files usage
11. Deadlocks (>0 критично)
12. Autovacuum activity

#### Категория 3: Прикладной мониторинг (10 метрик)

1. Consumer processing rate (30-50 msg/sec норма)
2. Join success rate (>98% норма, <95% критично)
3. Join delay p95 (<2 sec норма, >10 sec критично)
4. DB write duration p95 (<100ms норма, >200ms критично)
5. DB write errors (<1% критично)
6. Orphan messages (0-10 норма, >100 критично)
7. Report generation success
8. Report generation time (Totals <5 мин, Figurants <15 мин)
9. pg_cron jobs success
10. Operation log errors

### Инструменты

- **Prometheus** - сбор метрик
- **Grafana** - визуализация (3 готовых dashboard)
- **Kafka Exporter** - метрики Kafka
- **postgres_exporter** - метрики PostgreSQL
- **Micrometer** (Java/Spring Boot) - метрики KSK Consumer

***

## Оптимизации производительности

### PostgreSQL Оптимизации

#### 1. Партиционирование

- **Daily partitions** по timestamp/output_timestamp
- Автосоздание на **7 дней вперёд** (pg_cron, 02:00)
- Автоудаление партиций **старше 365 дней** (pg_cron, 04:00)

```sql
-- Создание партиций
SELECT ksk_create_partitions_for_all_tables(CURRENT_DATE, 7);

-- Удаление старых
SELECT ksk_drop_old_partitions('ksk_result', 365);
```


#### 2. Индексы

```sql
-- ksk_result
CREATE INDEX idx_ksk_result_output_timestamp ON ksk_result(output_timestamp);
CREATE INDEX idx_ksk_result_corr_id ON ksk_result(corr_id);
CREATE INDEX idx_ksk_result_date ON ksk_result(date);
CREATE INDEX idx_ksk_result_resolution ON ksk_result(resolution);
CREATE INDEX idx_ksk_result_payment_type ON ksk_result(payment_type);

-- ksk_figurant
CREATE INDEX idx_ksk_figurant_source_id ON ksk_figurant(source_id);
CREATE INDEX idx_ksk_figurant_list_code ON ksk_figurant(list_code);

-- ksk_figurant_match
CREATE INDEX idx_ksk_figurant_match_figurant_id ON ksk_figurant_match(figurant_id);
```


#### 3. JSONB Storage

```sql
-- EXTERNAL storage для JSONB (хранение на HDD для экономии)
ALTER TABLE ksk_result ALTER COLUMN input_json SET STORAGE EXTERNAL;
ALTER TABLE ksk_result ALTER COLUMN output_json SET STORAGE EXTERNAL;
```


#### 4. Извлечение из JSONB в структурированные поля

- **До:** парсинг JSONB при каждом запросе (медленно)
- **После:** денормализация - извлечение часто используемых полей в TEXT колонки при вставке
- **Результат:** ускорение отчётов в 5-10 раз

```sql
-- Пример извлечения в put_ksk_result()
vpayment_info := pinputjson->'paymentInfo';
vpayer_inn := vpayment_info->>'payerInn';
vpayer_name := vpayment_info->>'payerName';
-- вставка в TEXT поля
```


#### 5. Оптимизация отчётов

**Проблема:** Отчёт list_totals_by_payment_type генерировался 110 секунд (LOOP по массиву list_codes)

**Решение:** UNNEST + COUNT(*) FILTER вместо LOOP

```sql
-- ДО (медленно):
FOR vlist_code IN SELECT unnest(list_codes) LOOP
  -- множественные SELECT COUNT(*)
END LOOP;

-- ПОСЛЕ (быстро):
INSERT INTO report_table
SELECT 
  list_code,
  COUNT(*) FILTER (WHERE payment_type = 'I') AS i_total,
  COUNT(*) FILTER (WHERE payment_type = 'O') AS o_total,
  ...
FROM ksk_result
CROSS JOIN UNNEST(list_codes) AS list_code
GROUP BY list_code;
```

**Результат:** 110 сек → 10-20 сек (ускорение в 5-10 раз)

#### 6. Автоматическая очистка

```sql
-- Очистка некорректных записей (resolution пустой)
SELECT ksk_cleanup_empty_records(14); -- старше 14 дней

-- Очистка пустых партиций
SELECT ksk_cleanup_empty_partitions('ksk_result', 7); -- старше 7 дней
```


#### 7. Мониторинг Bloat

```sql
-- Функция для отслеживания раздутия таблиц
SELECT * FROM ksk_monitor_table_bloat('upoa_ksk_reports');
```


***

## Технологический стек

| Компонент | Технология | Версия | Примечание |
| :-- | :-- | :-- | :-- |
| Message Broker | Apache Kafka | 2.8+ | 2-3 партиции |
| Consumer | Java + Spring Boot | 2.7+ / 3.x | Micrometer metrics |
| Database | PostgreSQL | 14+ | 3TB data, partitioned |
| Scheduler | pg_cron | 1.4+ | Автозадачи |
| Monitoring | Prometheus | 2.x+ | Метрики |
| Visualization | Grafana | 8.x+ | Dashboards |
| Metrics | Micrometer | 1.9+ | Java metrics |
| Deployment | Kubernetes | 1.24+ | Container orchestration |

### Инфраструктура

**PostgreSQL Server:**

- CPU: 16+ cores
- RAM: 64 GB
- Disk: 5 TB SSD + HDD для JSONB
- Network: 10 Gbit/s

**KSK Consumer:**

- CPU: 4 cores
- RAM: 8 GB
- Instances: 1-3 (зависит от нагрузки)

***

## Критические параметры

### Kafka

- **Consumer Lag**: <100K норма, >200K критично
- **Messages Rate**: <1300 msg/sec норма, >1500 критично
- **Join Success Rate**: >98% норма, <95% критично
- **Join Delay p95**: <2 sec норма, >10 sec критично
- **Orphan Messages**: 0-10 норма, >100 критично


### PostgreSQL

- **Connections**: <300 норма, >400 критично
- **TPS**: 30-50 норма, <10 или >1000 критично
- **Cache Hit Ratio**: >99% норма, <95% критично
- **Bloat %**: 0-10% норма, >30% критично (нужен VACUUM)
- **Index Usage**: >90% оптимально, <50% критично
- **Database Age**: <1B норма, >1.5B критично (wraparound риск)


### Application

- **Consumer Processing**: 30-50 msg/sec норма, <10 критично
- **DB Write Duration p95**: <100ms норма, >200ms критично
- **DB Write Errors**: 0% норма, >1% критично
- **Report Generation**: Totals <5 мин, Figurants <15 мин

***

## Важные особенности реализации

### 1. Типы платежей (payment_type)

- **I** - Входящий
- **O** - Исходящий
- **T** - Транзитный
- **M** - Межфилиальный
- **V** - Внутрифилиальный

В отчётах используются **русские названия** для полей:

- `i_total` - Входящий: Всего
- `o_total` - Исходящий: Всего
- и т.д.


### 2. Решения системы (resolution)

- **allow** - разрешить транзакцию
- **review** - на ручную проверку СФМ
- **deny** - запретить транзакцию
- **empty** - некорректная запись (подлежит удалению)


### 3. Bypass (has_bypass)

- **empty** - обычная проверка
- **yes** - техническое исключение (пропустить несмотря на совпадения)
- **no** - не bypass


### 4. corrId (Correlation ID)

Ключ для join двух Kafka-сообщений:

1. Транзакция из `upoa_enriched_transactions`
2. Результат проверки из `upoa_ksk_results`

Consumer ожидает пару максимум 10 секунд (p99)

### 5. Санкционные списки (list_code)

Примеры кодов:

- **4200** - ЦБ РФ: Организации, связанные с терроризмом
- **4204** - ЦБ РФ: Физлица, связанные с терроризмом
- **4205** - ЦБ РФ: Организации под санкциями
- **4206** - ООН: Санкционный список
- **4207** - EU: Европейские санкции
- **4208** - OFAC: США (SDN List)

***

## Ключевые функции PostgreSQL

### Основные операции

```sql
-- Запись результата проверки
SELECT put_ksk_result(
  p_input_timestamp, 
  p_output_timestamp, 
  p_input_json, 
  p_output_json
);

-- Проверка статуса транзакции
SELECT check_transaction_status(p_corr_id);

-- Проверка статуса фигуранта
SELECT check_figurant_status(p_source_id, p_list_code, p_name_figurant);
```


### Управление партициями

```sql
-- Создать партиции для одной таблицы
SELECT ksk_create_partitions('ksk_result', CURRENT_DATE, 7);

-- Создать для всех таблиц
SELECT ksk_create_partitions_for_all_tables(CURRENT_DATE, 7);

-- Удалить старые партиции
SELECT ksk_drop_old_partitions('ksk_result', 365);

-- Список партиций
SELECT * FROM ksk_list_partitions('ksk_result');
```


### Генерация отчётов

```sql
-- Универсальная функция запуска
SELECT ksk_run_report(
  p_report_code,      -- 'totals', 'figurants', etc.
  p_initiator,        -- 'system' или 'user'
  p_user_login,       -- NULL для system
  p_start_date,
  p_end_date,         -- NULL = p_start_date
  p_parameters        -- JSONB или NULL
);

-- Очистка устаревших отчётов
SELECT ksk_cleanup_old_reports();
```


### Логирование

```sql
-- Записать операцию в лог
SELECT ksk_log_operation(
  p_operation_code,
  p_operation_name,
  p_start_time,
  p_status,
  p_info,
  p_error_message
);
```


***

## pg_cron расписание

```sql
-- 02:00 - Создание партиций на 7 дней вперёд
SELECT ksk_create_partitions_for_all_tables(CURRENT_DATE, 7);

-- 03:00 - Генерация автоматических отчётов
SELECT ksk_run_report('totals', 'system', NULL, CURRENT_DATE - 1);
SELECT ksk_run_report('totals_by_payment_type', 'system', NULL, CURRENT_DATE - 1);
SELECT ksk_run_report('list_totals', 'system', NULL, CURRENT_DATE - 1);
SELECT ksk_run_report('list_totals_by_payment_type', 'system', NULL, CURRENT_DATE - 1);

-- 04:00 - Удаление старых партиций (>365 дней)
SELECT ksk_drop_old_partitions('ksk_result', 365);
SELECT ksk_drop_old_partitions('ksk_figurant', 365);
SELECT ksk_drop_old_partitions('ksk_figurant_match', 365);

-- 04:00 - Очистка пустых записей (>14 дней)
SELECT ksk_cleanup_empty_records(14);

-- 04:00 - Очистка пустых партиций (>7 дней)
SELECT ksk_cleanup_empty_partitions('ksk_result', 7);
SELECT ksk_cleanup_empty_partitions('ksk_figurant', 7);
SELECT ksk_cleanup_empty_partitions('ksk_figurant_match', 7);

-- 05:00 - Удаление устаревших отчётов (по TTL)
SELECT ksk_cleanup_old_reports();
```


***

## Часто используемые запросы

### Статистика за день

```sql
-- Общая статистика
SELECT 
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE resolution = 'allow') AS allow_count,
  COUNT(*) FILTER (WHERE resolution = 'review') AS review_count,
  COUNT(*) FILTER (WHERE resolution = 'deny') AS deny_count,
  COUNT(*) FILTER (WHERE has_bypass = 'yes') AS bypass_count
FROM ksk_result
WHERE date = CURRENT_DATE;

-- По типам платежей
SELECT 
  payment_type,
  COUNT(*) AS total
FROM ksk_result
WHERE date = CURRENT_DATE
GROUP BY payment_type
ORDER BY total DESC;

-- По санкционным спискам
SELECT 
  unnest(list_codes) AS list_code,
  COUNT(*) AS count
FROM ksk_result
WHERE date = CURRENT_DATE
  AND list_codes IS NOT NULL
GROUP BY list_code
ORDER BY count DESC;
```


### Мониторинг производительности

```sql
-- Bloat таблиц
SELECT * FROM ksk_monitor_table_bloat('upoa_ksk_reports');

-- Размеры таблиц
SELECT 
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'upoa_ksk_reports'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Статус отчётов
SELECT 
  r.report_code,
  h.status,
  h.start_date,
  h.end_date,
  h.created_at,
  h.completed_at,
  h.error_message
FROM ksk_report_header h
JOIN ksk_report_orchestrator r ON h.report_code = r.report_code
WHERE h.created_at > CURRENT_DATE - 7
ORDER BY h.created_at DESC;

-- Системный лог операций
SELECT *
FROM ksk_system_operation_log
WHERE start_time > CURRENT_DATE - 1
ORDER BY start_time DESC;
```


***

## Следующие шаги (TODO)

1. ✅ Оптимизация отчётов (DONE - ускорение в 5-10 раз)
2. ✅ Настройка мониторинга (DONE - 27 метрик, 3 dashboard)
3. ✅ Автоматизация партиционирования (DONE - pg_cron)
4. ⏳ Разработка Web UI для просмотра отчётов
5. ⏳ Интеграция с системой аутентификации (LDAP/AD)
6. ⏳ Алертинг (настройка уведомлений Email/Telegram/SMS)
7. ⏳ Disaster Recovery процедуры (backup/restore тестирование)
8. ⏳ Load Testing (проверка на нагрузку >1500 msg/sec)

***

## Контакты и документация

**Разработчик БД:** Database Developer/Engineer
**Язык системы:** Русский
**Дата последнего обновления:** 28.10.2025

**Документы:**

- Business Requirements (бизнес-требования)
- Monitoring Specification (спецификация мониторинга)
- Report Specification (спецификация отчётов)
- HTML Monitoring Dashboard
- CSV Metrics Export

***

**Примечание:** Этот документ содержит полный контекст проекта для быстрого восстановления понимания системы. Загрузите его в новую сессию с AI для продолжения работы над проектом.
<span style="display:none">[^1][^10][^2][^3][^4][^5][^6][^7][^8][^9]</span>

<div align="center">⁂</div>

[^1]: https://kskgroup.ru

[^2]: https://kskspr.ru/documents/main/?id=1634

[^3]: https://kb.msk-ix.ru/dns/ksk/

[^4]: https://www.kck.ru/bpm-system-process-management

[^5]: https://denuo.legal/ru/insights/news/A6/

[^6]: https://kskgroup.ru/press-center/news/liberalizatsiya-korporativnogo-zakonodatelstva/

[^7]: https://minfin.gov.ru/ru/permission/

[^8]: https://www.garant.ru/article/886139/

[^9]: https://samojlovskij-r64.gosweb.gosuslugi.ru/ofitsialno/struktura-munitsipalnogo-obrazovaniya/kontrolno-schetnyy-organ-munitsipalnogo-obrazovaniya/otchety-xk-o-provedennyh-proverkah/

[^10]: https://solutions.1c.ru/projects/1104415/

