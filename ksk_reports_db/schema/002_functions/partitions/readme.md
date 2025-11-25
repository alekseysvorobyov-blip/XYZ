# ФУНКЦИИ УПРАВЛЕНИЯ ПАРТИЦИЯМИ KSK

## Переименование функций (2025-10-25)

| Старое имя                              | Новое имя                              |
|----------------------------------------|----------------------------------------|
| `create_ksk_partitions`                | `ksk_create_partitions`                |
| `create_ksk_partitions_for_all_tables` | `ksk_create_partitions_for_all_tables` |
| `list_all_ksk_partitions`              | `ksk_list_partitions`                  |
| `drop_old_ksk_partitions`              | `ksk_drop_old_partitions`              |

## Структура функций
functions/
??? partitions/
¦ +-- drop_old_partition_functions.sql # Удаление старых версий
¦ +-- create_partitions.sql # ksk_create_partitions()
¦ +-- create_all_partitions.sql # ksk_create_partitions_for_all_tables()
¦ +-- list_partitions.sql # ksk_list_partitions()
¦ L-- drop_partitions.sql # ksk_drop_old_partitions()


## Краткое описание

### 1. ksk_create_partitions()
- **Назначение:** Создание партиций для одной таблицы
- **Идемпотентность:** Да (безопасно запускать многократно)
- **Рекомендации:** 7-14 дней вперёд

### 2. ksk_create_partitions_for_all_tables()
- **Назначение:** Создание партиций для всех таблиц КСК
- **Периодичность:** Ежедневно (cron)
- **Обработка ошибок:** Независимая для каждой таблицы

### 3. ksk_list_partitions()
- **Назначение:** Мониторинг партиций
- **Данные:** Размер, диапазон, примерное количество записей
- **Использование:** Анализ роста БД

### 4. ksk_drop_old_partitions()
- **Назначение:** Удаление старых партиций
- **TTL:** 365 дней по умолчанию
- **Периодичность:** Раз в день
- **?? ВНИМАНИЕ:** Необратимая операция!

## Рекомендации по использованию

### Ежедневно (cron)
SELECT ksk_create_partitions_for_all_tables(CURRENT_DATE + 1, 7);

### Еженедельно (мониторинг)
SELECT * FROM ksk_list_partitions()
ORDER BY total_size DESC
LIMIT 20;


### Ежедневно (cron)(очистка)
-- Проверка перед удалением
SELECT tablename
FROM pg_tables
WHERE tablename LIKE 'part_ksk_%'
AND tablename < 'part_ksk_result_' || TO_CHAR(CURRENT_DATE - 365, 'YYYY_MM_DD');

-- Удаление
SELECT ksk_drop_old_partitions(365);


## Порядок установки

1. Запустить `drop_old_partition_functions.sql` (удаление старых версий)
2. Запустить `create_partitions.sql`
3. Запустить `create_all_partitions.sql`
4. Запустить `list_partitions.sql`
5. Запустить `drop_partitions.sql`

## Зависимости

- `ksk_create_partitions_for_all_tables()` > вызывает > `ksk_create_partitions()`

## История изменений

- **2025-10-25:** Переименование всех функций с добавлением префикса `ksk_`
