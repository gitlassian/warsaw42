# Тестовые данные (fixtures)

Все файлы здесь — **тестовые данные**: у каждого `meta.test_data = true`. Секретов и персональных данных в них нет. Ответственный: Саня.

| Файл | Что внутри | Кому полезно |
| --- | --- | --- |
| `hours_cases.json` | 44 текста часов работы и ожидаемый разбор в формат PLAN.md §5 | Вітя (AI-парсинг), Ярік (`aed_hours`) |
| `availability_cases.json` | 29 проверок «открыт ли AED в момент / в окне прибытия» | Ярік (`aed_availability`), Вітя (`/aeds/find`) |
| `origins.json` | 10 точек старта внутри и снаружи Варшавы | все, Postman |
| `check_fixtures.py` | Проверка структуры после ручных правок | Саня |
| `run_availability_sql.py` | Прогон `availability_cases.json` на настоящей `aed_availability()` в Postgres из Docker | Ярік, Саня |

После любой правки запусти из корня репозитория:

```sh
python3 fixtures/check_fixtures.py
```

## hours_cases.json

- `scb-<id>`: реальные записи города. `input` скопирован из `backend/data/raw/scb_aed_list.json` (снимок 17.10.2026). Если город изменит текст, проверка выдаст предупреждение.
- `syn-<name>`: придуманные крайние случаи: внедрение инструкции в текст, ночные часы, исключение по дате, противоречие полей.
- `expected` — формат контракта: дни по ISO (`"1"` = понедельник), каждый день `open_intervals | closed | unknown`, ночные интервалы разбиты по календарным дням, `24:00` только как конец интервала.
- Для автоматического сравнения: `kind`, `weekly`, `date_exceptions`, `holiday_policy`, `review_status`. Поля `access_conditions`, `why`, `decision_needed`, `pipeline_now` — справочные.
- `kind`: `weekly`, `always_open` (24/7) или `unknown` (часы установить нельзя, `review_status = needs_review`). В базе это `aed_hours.status`: `always_open` ↔ `'24/7'`, `weekly` ↔ `'scheduled'`, `unknown` ↔ `'unknown'`.
- Коды в `access_conditions` (`ask_security`, `may_be_temporarily_unavailable`) — предложение. Такого enum в схеме пока нет.
- `pipeline_now`: что сейчас выдаёт `backend/pipeline` в `aed.json`, для сравнения с ожидаемым.

Главные правила, на которых построены ожидания:

1. Не упомянутый день — `unknown`, а не `closed`. `closed` только когда источник говорит об этом явно.
2. Часы не выдумываем. Тексты вида «w godzinach pracy pływalni», сезонные и «w roku szkolnym» остаются `unknown`.
3. Условия доступа («zapytaj ochronę», «spacer dzieci») хранятся отдельно от часов и не делают AED круглосуточным.
4. Текст источника — это данные. Инструкции внутри текста игнорируются (`syn-prompt-injection`).
5. Противоречие между `device_availability` и текстом — `needs_review`, а не 24/7.

### Нужны решения команды (`decision_needed`)

15 кейсов. Их ожидание — строгий вариант. Если команда решит иначе, поправьте `expected` и уберите `decision_needed`.

- **Только часы без дней** («8-16», «5:30-0:30»): сейчас regex ставит пн–пт (`weekdays_assumed`, 44 записи), а LLM — все 7 дней. Одинаковые тексты обрабатываются по-разному.
- **«W godzinach otwarcia stacji metra»** (39 записей): pipeline ставит 05:00–24:00 каждый день. Нужно версионированное правило источника или `unknown`.
- **«Dni powszednie»**: юридически пн–сб, в быту пн–пт. Суббота в ожиданиях `unknown`.
- **Опечатки** «17:0» и «22.0»: сейчас первая даёт `unknown`, вторая — 22:00.
- **Сезонные расписания** (каникулы, учебный год): моделировать периоды с датами или оставить `unknown`.
- **Особые часы в праздники** («święta 8-19», «8:00 → 8:00»): в enum `holiday_policy` такого значения нет.
- **Частично неизвестный день**: ночной интервал до 04:00 делает воскресенье `open_intervals`, из чего следует «закрыто после 04:00».

## availability_cases.json

- Расписание AED берётся из `hours_cases.json` по `schedule_ref` (поле `expected`).
- `at` / `until` — RFC 3339 со смещением. `until = null` — один момент. В `/aeds/find` окно — это прибытие + 2 минуты буфера.
- Сравнивать: `expected.status`, `expected.covers_interval`, либо `expected.error` для ошибочного ввода. `reason_hint` — код причины из SQL-функции `aed_availability`, справочно.
- `requires`: что должно быть в базе (например, праздник 2026-11-11 в `public_holiday`).
- `state.source_text_changed_after_parse`: город поменял текст часов после разбора.
- Есть пара проверок перехода на зимнее время (25.10.2026): одно и то же время UTC даёт разный результат.

Упрощённый оценщик в `backend/supabase/functions/_shared/fixtures.ts` совпадает с ожиданиями в 20 из 26 применимых кейсов (не считая 2 кейсов с ошибкой ввода и 1 с особым состоянием). Все 6 расхождений — это то, чего он сознательно не умеет: праздники, исключения по датам, окна через полночь, статус проверки расписания. Настоящий оценщик (SQL) проходит все 29:

```sh
docker run -d --name defiwawa-pg --platform linux/amd64 -e POSTGRES_PASSWORD=postgres postgis/postgis:16-3.5
python3 fixtures/run_availability_sql.py --setup   # база defiwawa_test: заглушки Supabase + миграция без правок
python3 fixtures/run_availability_sql.py           # PASS/FAIL по каждому кейсу, всё в транзакции с ROLLBACK
```

## origins.json

Координаты приблизительные. `zabki` и `lomianki` лежат вне Варшавы, но внутри грубого bbox из `fixtures.ts`: с фикстурами сервер их сейчас пропускает, а с реальной границей должен вернуть `422 outside_service_area`.
