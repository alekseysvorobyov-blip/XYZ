## Основные секции дашборда

### 1. **Общая статистика системы**

sql

-- Количество обработанных платежей за сегодня/неделю/месяц
SELECT COUNT(*) FROM ksk_result 
WHERE created_date >= CURRENT_DATE;

-- Статусы последних отчетов
SELECT status, COUNT(*) 
FROM ksk_report_header 
WHERE created_datetime >= NOW() - INTERVAL '1 day'
GROUP BY status;

### 2. **Производительность обработки**

sql

-- Время выполнения отчетов (перцентили)
SELECT 
  percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (finished_datetime - created_datetime))) as p50,
  percentile_cont(0.95) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (finished_datetime - created_datetime))) as p95
FROM ksk_report_header 
WHERE finished_datetime IS NOT NULL 
  AND created_datetime >= NOW() - INTERVAL '1 week';

### 3. **Ошибки и проблемы**

sql

-- Ошибки обработки (последние 24 часа)
SELECT error_code, COUNT(*) 
FROM ksk_result_error 
WHERE error_timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY error_code;

-- Длительные операции
SELECT operation_name, duration 
FROM ksk_system_operations_log 
WHERE begin_time >= NOW() - INTERVAL '1 day' 
  AND duration > 300  -- операции дольше 5 минут
ORDER BY duration DESC;

### 4. **Статистика по фигурантам**

sql

-- Топ фигурантов по срабатываниям
SELECT figurant, COUNT(*) as matches
FROM ksk_figurant_match 
WHERE date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY figurant 
ORDER BY matches DESC 
LIMIT 10;

### 5. **Мониторинг партиций**

sql

-- Использование партиций (легкий запрос через системные представления)
SELECT schemaname, tablename, 
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'upoa_ksk_reports'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

## 🎯 Рекомендуемые визуализации

### **Главный экран:**

1. **Big Numbers:**
    
    - Обработано платежей сегодня
        
    - Активных отчетов
        
    - Ошибок за 24ч
        
    - Среднее время выполнения отчета
        
2. **Графики:**
    
    - Время выполнения отчетов (тренд)
        
    - Количество ошибок по часам
        
    - Загрузка по типам платежей (I/O/T/M/V)
        
    - Статусы отчетов (pie chart)
        

### **Детальный мониторинг:**

3. **Таблицы:**
    
    - Последние ошибки с текстом
        
    - Длительные операции
        
    - Топ фигурантов
        
    - Размеры таблиц


### **Панель 1: "Общий размер БД" (Stat Panel)**

text

Запрос: 
SELECT pg_database_size(current_database()) as size_bytes

Настройки:
- Title: "Общий размер БД"
- Unit: bytes (GB)
- Thresholds:
  - Green: 0 - 500GB
  - Yellow: 500 - 600GB  
  - Red: 600GB - 1TB
- Color mode: Background

### **Панель 2: "Топ таблиц по размеру" (Table Panel)**

text

Запрос: детализация по таблицам выше

Настройки:
- Title: "Крупнейшие таблицы"
- Columns: 
  - tablename (скрыть)
  - size_pretty (отображать как "Размер")
  - size_gb (отображать как "ГБ", сортировка по убыванию)

### **Панель 3: "Динамика роста БД" (Time Series)**

text

Запрос: рост БД за 30 дней

Настройки:
- Title: "Динамика роста БД"
- Fill: 10
- Show points: always