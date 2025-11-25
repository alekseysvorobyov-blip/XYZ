
# Херня какая-то получается.

Сделай нормально. Сократи. Оставь только важное.
Приоритет использование в сочетании с исходниками и ИИ.

Вот краткий README.md для таблиц отчётов — только важное для ИИ и анализа кода:

```markdown
# Система отчётов КСК — Архитектура БД

**Схема:** `upoa_ksk_reports` | **Версия:** 1.0 | **Дата:** 2025-10-27

---

## Иерархия таблиц

```

ksk_report_orchestrator (типы отчётов)
↓ FK: orchestrator_id (CASCADE DELETE)
ksk_report_header (экземпляры отчётов)
↓ FK: report_header_id (CASCADE DELETE)
├─ ksk_report_totals_data
├─ ksk_report_list_totals_data
├─ ksk_report_totals_by_payment_type_data
├─ ksk_report_list_totals_by_payment_type_data
└─ ksk_report_figurants_data

```

---

## Таблицы

### 1. ksk_report_orchestrator — метаданные типов отчётов

| Колонка | Тип | Ключ | Примечание |
|---------|-----|------|-----------|
| id | INTEGER | PK | AUTO INCREMENT |
| report_code | VARCHAR(50) | UNIQUE + индекс | Код отчёта |
| report_table | VARCHAR(100) | | Таблица данных |
| report_function | VARCHAR(100) | NOT NULL | Функция генерации |
| name | VARCHAR(200) | NOT NULL | Название |
| system_ttl | INTEGER | DEFAULT 30 | TTL системных (дни) |
| user_ttl | INTEGER | DEFAULT 7 | TTL пользовательских (дни) |

**Предустановленные отчёты:** totals, totals_by_payment_type, list_totals, list_totals_by_payment_type, figurants

**Индексы:** 1 (report_code)

---

### 2. ksk_report_header — экземпляры отчётов

| Колонка | Тип | Ключ | Примечание |
|---------|-----|------|-----------|
| id | INTEGER | PK | AUTO INCREMENT |
| orchestrator_id | INTEGER | FK + индекс | → ksk_report_orchestrator(id) CASCADE |
| name | VARCHAR(500) | NOT NULL | Название отчёта |
| initiator | VARCHAR(100) | NOT NULL CHECK | 'system' или 'user' |
| user_login | VARCHAR(100) | | Обязателен если initiator='user' |
| created_datetime | TIMESTAMP | DEFAULT NOW() + индекс | |
| finished_datetime | TIMESTAMP | | |
| status | VARCHAR(20) | DEFAULT 'created' CHECK + индекс | created/in_progress/done/error |
| ttl | INTEGER | NOT NULL | Время жизни (дни) |
| remove_date | DATE | NOT NULL + индекс | Дата удаления |
| start_date | DATE | | Период: начало |
| end_date | DATE | | Период: конец |
| parameters | JSONB | | Доп. параметры |

**CHECK constraints:** 
- `initiator IN ('system', 'user')`
- `status IN ('created', 'in_progress', 'done', 'error')`
- `chk_user_login`: user_login обязателен при initiator='user'

**Индексы:** 4 (orchestrator_id, status, remove_date, created_datetime)

---

### 3. ksk_report_totals_data — общая статистика

**Колонки:** 9 (id, report_header_id, created_date_time + 7 счётчиков)

**Счётчики:** total, total_without_result, total_with_result, total_allow, total_review, total_deny, total_bypass

**FK:** report_header_id → ksk_report_header(id) CASCADE

**Индексы:** 2 (report_header_id, created_date_time)

---

### 4. ksk_report_list_totals_data — статистика по спискам

**Колонки:** 9 (id, report_header_id, created_date_time, list_code + 6 счётчиков)

**Счётчики:** total_with_list, total_without_list, total_allow, total_review, total_deny, total_bypass

**FK:** report_header_id → ksk_report_header(id) CASCADE

**Индексы:** 3 (report_header_id, created_date_time, list_code)

---

### 5. ksk_report_totals_by_payment_type_data — по типам платежей

**Колонки:** 44 (id, report_header_id, created_date_time + 7 общих + 5 типов × 7 счётчиков)

**Типы платежей:** i_ (Входящий), o_ (Исходящий), t_ (Транзитный), m_ (Межфилиальный), v_ (Внутрифилиальный)

**Структура:** 
- Общие: total, total_without_result, total_with_result, total_allow, total_review, total_deny, total_bypass
- Для каждого типа: {prefix}_total, {prefix}_total_without_result, ... (7 полей × 5 типов)

**FK:** report_header_id → ksk_report_header(id) CASCADE

**Индексы:** 1 (report_header_id)

---

### 6. ksk_report_list_totals_by_payment_type_data — по спискам и типам

**Колонки:** 39 (id, report_header_id, created_date_time, list_code + 6 общих + 5 типов × 6 счётчиков)

**Структура:**
- Общие: total_with_list, total_without_list, total_allow, total_review, total_deny, total_bypass
- Для каждого типа: {prefix}_total_with_list, {prefix}_total_without_list, ... (6 полей × 5 типов)

**FK:** report_header_id → ksk_report_header(id) CASCADE

**Индексы:** 2 (report_header_id, list_code)

---

### 7. ksk_report_figurants_data — по фигурантам

**Колонки:** 12 (id, report_header_id, created_date_time + 5 данных фигуранта + 5 счётчиков)

**Данные:** list_code, name_figurant, president_group, auto_login, exclusion_phrase

**Счётчики:** total, total_allow, total_review, total_deny, total_bypass

**FK:** report_header_id → ksk_report_header(id) CASCADE

**Индексы:** 1 (report_header_id)

---

## Ключевые особенности

1. **БЕЗ партиционирования** — все таблицы отчётов
2. **CASCADE DELETE** — удаление оркестратора/заголовка удаляет всё связанное
3. **TTL управление** — автоматическое удаление через remove_date
4. **CHECK constraints** — на initiator и status
5. **JSONB** — только в parameters (без EXTERNAL STORAGE)
6. **Все индексы B-tree** — небольшой объём данных

---

## Порядок создания

```

1. ksk_report_orchestrator  -- независимая
2. ksk_report_header        -- зависит от orchestrator
3. ksk_report_*_data        -- зависят от header
```

---

## Идемпотентность

Все скрипты используют:
- DO блоки с проверкой существования
- `add_column_if_not_exists()` для колонок
- `CREATE INDEX IF NOT EXISTS`
- Динамическое удаление ненужных индексов
- `INSERT ... ON CONFLICT (report_code) DO NOTHING`

---

**Документация актуальна на:** 2025-10-27
```

Готово! Короткий, структурированный README с фокусом на:
✅ Иерархию и связи FK
✅ Структуру колонок (без лишних деталей)
✅ Ключевые ограничения (CHECK, CASCADE)
✅ Индексы
✅ Особенности для ИИ-анализа
<span style="display:none">[^1][^2][^3][^4][^5][^6][^7][^8][^9]</span>

<div align="center">⁂</div>

[^1]: https://pro1c.kz/articles/zhkkh/otchet-po-upravleniyu-obektom-kondominiuma-i-soderzhaniyu-obshchego-imushchestva-v-1c-rating-bukhga3/

[^2]: https://kapster.kz/post/novye_pravila_v_otcetnosti_dlia_ksk_i_osi_652

[^3]: https://www.bcc.kz/bcc-journal/category/glossary/housing-cooperative/

[^4]: https://krisha.kz/content/articles/2025/2025-kak-zastavit-ksk-otchitatsya-o-rashodah

[^5]: https://www.kn.kz/article/8197

[^6]: https://www.gov.kz/memleket/entities/almobl/press/news/details/1056862?lang=ru

[^7]: https://liter.kz/novye-pravila-dlia-ksk-i-osi-chto-delat-esli-net-otcheta-1761582792/

[^8]: https://kskgroup.ru/academy-ksk/glossary/finansovaya-otchetnost/

[^9]: https://www.youtube.com/watch?v=mBM9FHGGW7A

