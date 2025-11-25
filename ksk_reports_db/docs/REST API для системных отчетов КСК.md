
# REST API для системных отчетов КСК - ФИНАЛЬНАЯ ВЕРСИЯ v1.4

**Дата:** 26 октября 2025, 20:27
**Версия:** 1.4 (все исправления учтены)

***

## **СПИСОК ФУНКЦИЙ API:**

1. `GET /api/reports/system/available-dates`
2. `GET /api/reports/system/{report_code}/data?date=YYYY-MM-DD&limit=100&offset=0`
3. `GET /api/reports/system/{report_code}/export/xlsx?date=YYYY-MM-DD`
4. `GET /api/reports/system/{report_code}/export/csv?date=YYYY-MM-DD`

***

## **ФУНКЦИЯ 1: Получить доступные даты**

### **REST API:**

```
GET /api/reports/system/available-dates
```


### **Пример JSON:**

```json
{
  "min_date": "2024-10-26",
  "max_date": "2025-10-25",
  "default_date": "2025-10-25"
}
```


***

## **ФУНКЦИЯ 2: Получить данные отчета**


***

### **2.1. ОТЧЕТ: totals**

**REST API:**

```
GET /api/reports/system/totals/data?date=2025-10-25
```

**Источник:** Таблица `ksk_report_totals_data`

**Особенность:** Всегда возвращает **1 строку** за указанную дату. Пагинация не требуется.

**Пример JSON:**

```json
{
  "report_code": "totals",
  "date": "2025-10-25",
  "data": [
    {
      "total": 1500,
      "total_without_result": 100,
      "total_with_result": 1400,
      "total_allow": 1200,
      "total_review": 150,
      "total_deny": 50,
      "total_bypass": 20
    }
  ]
}
```


***

### **2.2. ОТЧЕТ: totals_by_payment_type**

**REST API:**

```
GET /api/reports/system/totals_by_payment_type/data?date=2025-10-25
```

**Источник:** Таблица `ksk_report_totals_by_payment_type_data`

**Особенность:** Всегда возвращает **1 строку** за указанную дату. Пагинация не требуется.

**Типы платежей:**

- `i_*` - Входящий
- `o_*` - Исходящий
- `t_*` - Транзитный
- `m_*` - Межфилиальный
- `v_*` - Внутрифилиальный

**Пример JSON:**

```json
{
  "report_code": "totals_by_payment_type",
  "date": "2025-10-25",
  "data": [
    {
      "total": 1500,
      "total_without_result": 100,
      "total_with_result": 1400,
      "total_allow": 1200,
      "total_review": 150,
      "total_deny": 50,
      "total_bypass": 20,
      "i_total": 600,
      "i_total_without_result": 40,
      "i_total_with_result": 560,
      "i_total_allow": 500,
      "i_total_review": 50,
      "i_total_deny": 10,
      "i_total_bypass": 5,
      "o_total": 400,
      "o_total_without_result": 30,
      "o_total_with_result": 370,
      "o_total_allow": 320,
      "o_total_review": 40,
      "o_total_deny": 10,
      "o_total_bypass": 8,
      "t_total": 300,
      "t_total_without_result": 20,
      "t_total_with_result": 280,
      "t_total_allow": 240,
      "t_total_review": 30,
      "t_total_deny": 10,
      "t_total_bypass": 4,
      "m_total": 150,
      "m_total_without_result": 8,
      "m_total_with_result": 142,
      "m_total_allow": 110,
      "m_total_review": 25,
      "m_total_deny": 7,
      "m_total_bypass": 2,
      "v_total": 50,
      "v_total_without_result": 2,
      "v_total_with_result": 48,
      "v_total_allow": 30,
      "v_total_review": 5,
      "v_total_deny": 13,
      "v_total_bypass": 1
    }
  ]
}
```


***

### **2.3. ОТЧЕТ: list_totals**

**REST API:**

```
GET /api/reports/system/list_totals/data?date=2025-10-25&limit=100&offset=0
```

**Источник:** Таблица `ksk_report_list_totals_data`

**Особенность:** Может содержать несколько строк (по одной на каждый list_code). Пагинация поддерживается.

**Пример JSON:**

```json
{
  "report_code": "list_totals",
  "date": "2025-10-25",
  "data": [
    {
      "list_code": "4200",
      "total_with_list": 45,
      "total_without_list": 1455,
      "total_allow": 30,
      "total_review": 10,
      "total_deny": 5,
      "total_bypass": 2
    },
    {
      "list_code": "4204",
      "total_with_list": 32,
      "total_without_list": 1468,
      "total_allow": 25,
      "total_review": 5,
      "total_deny": 2,
      "total_bypass": 1
    }
  ],
  "pagination": {
    "total_records": 15,
    "limit": 100,
    "offset": 0,
    "has_more": false
  }
}
```


***

### **2.4. ОТЧЕТ: list_totals_by_payment_type**

**REST API:**

```
GET /api/reports/system/list_totals_by_payment_type/data?date=2025-10-25&limit=100&offset=0
```

**Источник:** Таблица `ksk_report_list_totals_by_payment_type_data`

**Особенность:** Может содержать несколько строк. Пагинация поддерживается.

**Пример JSON:**

```json
{
  "report_code": "list_totals_by_payment_type",
  "date": "2025-10-25",
  "data": [
    {
      "list_code": "4200",
      "total_with_list": 45,
      "total_without_list": 1455,
      "total_allow": 30,
      "total_review": 10,
      "total_deny": 5,
      "total_bypass": 2,
      "i_total_with_list": 20,
      "i_total_without_list": 580,
      "i_total_allow": 15,
      "i_total_review": 4,
      "i_total_deny": 1,
      "i_total_bypass": 1,
      "o_total_with_list": 15,
      "o_total_without_list": 385,
      "o_total_allow": 10,
      "o_total_review": 3,
      "o_total_deny": 2,
      "o_total_bypass": 0,
      "t_total_with_list": 7,
      "t_total_without_list": 293,
      "t_total_allow": 4,
      "t_total_review": 2,
      "t_total_deny": 1,
      "t_total_bypass": 1,
      "m_total_with_list": 2,
      "m_total_without_list": 148,
      "m_total_allow": 1,
      "m_total_review": 1,
      "m_total_deny": 0,
      "m_total_bypass": 0,
      "v_total_with_list": 1,
      "v_total_without_list": 49,
      "v_total_allow": 0,
      "v_total_review": 0,
      "v_total_deny": 1,
      "v_total_bypass": 0
    }
  ],
  "pagination": {
    "total_records": 15,
    "limit": 100,
    "offset": 0,
    "has_more": false
  }
}
```


***

### **2.5. ОТЧЕТ: figurants**

**REST API:**

```
GET /api/reports/system/figurants/data?date=2025-10-25&limit=100&offset=0
```

**Источник:** Таблица `ksk_report_figurants_data`

**Особенность:** Может содержать много строк (сотни-тысячи фигурантов). Пагинация **обязательна**.

**Пример JSON:**

```json
{
  "report_code": "figurants",
  "date": "2025-10-25",
  "data": [
    {
      "list_code": "4200",
      "name_figurant": "Иванов Иван Иванович",
      "president_group": "Group A",
      "auto_login": "false",
      "exclusion_phrase": "не является",
      "total": 5,
      "total_allow": 3,
      "total_review": 1,
      "total_deny": 1,
      "total_bypass": 0
    }
  ],
  "pagination": {
    "total_records": 150,
    "limit": 100,
    "offset": 0,
    "has_more": true
  }
}
```


***

### **2.6. ОТЧЕТ: review**

**REST API:**

```
GET /api/reports/system/review/data?date=2025-10-25&limit=100&offset=0
```

**Источник:** Функция `ksk_report_review(report_date DATE) RETURNS TABLE`

**Особенность:**

- Вызывается как `SELECT * FROM ksk_report_review('2025-10-25') LIMIT 100 OFFSET 0`
- Возвращает результат напрямую из JOIN таблиц (не сохраняет в промежуточную таблицу)
- Пагинация **обязательна** (могут быть сотни тысяч записей)

**Возвращаемые поля (39 полей):**
corr_id, message_timestamp, algorithm, match_value, match_payment_field, match_payment_value, list_code, name_figurant, president_group, auto_login, has_exclusion, exclusion_phrase, exclusion_name_list, is_bypass, transaction_resolution, figurant_resolition, payment_id, payment_purpose, account_debet, account_сredit, payer_inn, payer_name, payer_account_number, payer_document_type, payer_bank_name, payer_bank_account_number, receiver_account_number, receiver_name, receiver_inn, receiver_bank_name, receiver_bank_account_number, receiver_document_type, amount, currency, currency_control, match_id, figurant_id, transaction_id, rn

**Пример JSON:**

```json
{
  "report_code": "review",
  "date": "2025-10-25",
  "data": [
    {
      "corr_id": "abc-123-def-456",
      "message_timestamp": "2025-10-25T10:30:15.123",
      "algorithm": "fuzzy_match",
      "match_value": "Иванов",
      "match_payment_field": "payer_name",
      "match_payment_value": "Иванов Иван Иванович",
      "list_code": "4200",
      "name_figurant": "Иванов И.И.",
      "president_group": "Group A",
      "auto_login": false,
      "has_exclusion": true,
      "exclusion_phrase": "не является",
      "exclusion_name_list": null,
      "is_bypass": "no",
      "transaction_resolution": "review",
      "figurant_resolition": "review",
      "payment_id": "PAY-2025-001234",
      "payment_purpose": "Оплата по договору №123",
      "account_debet": "40817810000001234567",
      "account_сredit": "40702810000007654321",
      "payer_inn": "1234567890",
      "payer_name": "ООО Рога и Копыта",
      "payer_account_number": "40817810000001234567",
      "payer_document_type": "Паспорт",
      "payer_bank_name": "Банк Плательщика",
      "payer_bank_account_number": "30101810000000000123",
      "receiver_account_number": "40702810000007654321",
      "receiver_name": "ООО Пример",
      "receiver_inn": "0987654321",
      "receiver_bank_name": "Банк Получателя",
      "receiver_bank_account_number": "30101810000000000456",
      "receiver_document_type": "ОГРН",
      "amount": "150000.00",
      "currency": "RUB",
      "currency_control": null,
      "match_id": 123456,
      "figurant_id": 7890,
      "transaction_id": 1111,
      "rn": 1
    }
  ],
  "pagination": {
    "total_records": 280000,
    "limit": 100,
    "offset": 0,
    "has_more": true
  }
}
```


***

## **ФУНКЦИЯ 3: Экспорт в XLSX**

```
GET /api/reports/system/{report_code}/export/xlsx?date=YYYY-MM-DD
```

**Content-Type:** `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`

***

## **ФУНКЦИЯ 4: Экспорт в CSV**

```
GET /api/reports/system/{report_code}/export/csv?date=YYYY-MM-DD
```

**Content-Type:** `text/csv; charset=utf-8`

***

## **СВОДНАЯ ТАБЛИЦА:**

| report_code | Источник | Пагинация | Строк за день |
| :-- | :-- | :-- | :-- |
| totals | Таблица `ksk_report_totals_data` | ❌ Нет | 1 |
| totals_by_payment_type | Таблица `ksk_report_totals_by_payment_type_data` | ❌ Нет | 1 |
| list_totals | Таблица `ksk_report_list_totals_data` | ✅ Да | 10-20 |
| list_totals_by_payment_type | Таблица `ksk_report_list_totals_by_payment_type_data` | ✅ Да | 10-20 |
| figurants | Таблица `ksk_report_figurants_data` | ✅ Да (обязательна) | 100-1000+ |
| review | Функция `ksk_report_review()` | ✅ Да (обязательна) | 100000+ |


***

**Примечание по источникам данных:**

- Для отчетов totals, totals_by_payment_type, list_totals, list_totals_by_payment_type, figurants: данные генерируются соответствующими функциями (`ksk_report_totals()`, `ksk_report_totals_by_payment_type()` и т.д.) и **сохраняются в таблицы**. API читает уже готовые данные из таблиц.
- Для отчета review: функция `ksk_report_review()` **напрямую возвращает** результат запроса без сохранения в таблицу.

***

**Сохрани как: `ksk-api-specification-v1.4-final.md`**

Теперь всё абсолютно точно! ✅
<span style="display:none">[^1][^10][^2][^3][^4][^5][^6][^7][^8][^9]</span>

<div align="center">⁂</div>

[^1]: https://selectel.ru/blog/pagination/

[^2]: https://www.reddit.com/r/laravel/comments/9jmq88/best_way_to_implement_optional_pagination_and/

[^3]: https://habr.com/ru/companies/selectel/articles/890824/

[^4]: https://www.reddit.com/r/ExperiencedDevs/comments/1nw9au6/which_type_of_api_pagination_do_you_most_like_to/

[^5]: https://docs.github.com/ru/rest/using-the-rest-api/using-pagination-in-the-rest-api

[^6]: https://techpulsion.com/ru/лучшие-практики-API-для-отдыха/

[^7]: https://ru.stackoverflow.com/questions/1236872/wordpress-rest-api-v2-как-получить-список-всех-постов-без-содержимого

[^8]: https://topvisor.com/ru/api/v2/basic-params/paging/

[^9]: https://habr.com/ru/articles/947410/

[^10]: https://www.tarantool.io/ru/tdg/latest/development/rest-api-requests/

