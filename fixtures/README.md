# Тестовые данные (fixtures)

Все файлы здесь — **тестовые данные**: у каждого `meta.test_data = true`. Секретов и персональных данных в них нет. Ответственный: Саня.

| Файл | Что внутри | Кому полезно |
| --- | --- | --- |
| `hours_cases.json` | 44 текста часов работы и ожидаемый разбор (дни `open_intervals / closed / unknown`) | Вітя (AI-парсинг), Ярік (`aeds.hours`) |
| `availability_cases.json` | 29 проверок «открыт ли AED в момент / в окне прибытия» | Ярік (`aed_availability`), Вітя (`/aeds/find`) |
| `origins.json` | 10 точек старта внутри и снаружи Варшавы | все, Postman |
| `check_fixtures.py` | Проверка структуры после ручных правок | Саня |
| `run_availability_sql.py` | Прогон `availability_cases.json` на настоящей `aed_availability()` и `origins.json` на `is_inside_warsaw()` в Postgres из Docker | Ярік, Саня |

После любой правки запусти из корня репозитория:

```sh
python3 fixtures/check_fixtures.py
```

## hours_cases.json

- `scb-<id>`: реальные записи города. `input` скопирован из `backend/data/raw/scb_aed_list.json` (снимок 17.10.2026). Если город изменит текст, проверка выдаст предупреждение.
- `syn-<name>`: придуманные крайние случаи: внедрение инструкции в текст, ночные часы, исключение по дате, противоречие полей.
- `expected` — формат контракта: дни по ISO (`"1"` = понедельник), каждый день `open_intervals | closed | unknown`, ночные интервалы разбиты по календарным дням, `24:00` только как конец интервала.
- Для автоматического сравнения: `kind`, `weekly`, `date_exceptions`, `holiday_policy`, `review_status`. Поля `access_conditions`, `why`, `decision_needed`, `pipeline_now` — справочные.
- `kind`: `weekly`, `always_open` (24/7) или `unknown` (часы установить нельзя, `review_status = needs_review`).
- Формат фикстур старше упрощённой схемы (время `"HH:MM"`, исключения списком). В базе после миграции `20261017150000_simplify_app_schema.sql` всё лежит в одной строке `aeds`, `run_availability_sql.py` переводит так же, как миграция и `pipeline/seed_sql.py`:

  | `hours_cases.json` | `aeds` |
  | --- | --- |
  | `kind`: `always_open` / `weekly` / `unknown` | `hours_status`: `'24/7'` / `'scheduled'` / `'unknown'` |
  | `review_status`: `validated`, `validated_partial` | `hours_verified = true` |
  | `review_status`: `needs_review`, `pending`, `rejected` | `hours_verified = false` |
  | `weekly["1"].intervals = [["08:00", "18:00"]]` | `hours.weekly["1"].intervals = [[480, 1080]]` (минуты, `24:00` = 1440) |
  | `date_exceptions: [{date, state, intervals}]` | `hours.exceptions["YYYY-MM-DD"] = {state, intervals}` |
  | `holiday_policy` | `hours.holiday_policy` (то же: `unknown`, `closed`, `regular_hours`) |
  | `access_conditions` | нет; ближайшее — свободный текст `access_instructions` |

  Разница `validated` / `validated_partial` в базе не сохраняется: оба значат «расписанию верим», а неизвестные дни так и остаются `unknown` в `hours.weekly`.
- Коды в `access_conditions` (`ask_security`, `may_be_temporarily_unavailable`) — предложение. Такого enum в схеме пока нет.
- `pipeline_now`: что сейчас выдаёт `backend/pipeline` в `aed.json`, для сравнения с ожидаемым.

Главные правила, на которых построены ожидания:

1. Не упомянутый день — `unknown`, а не `closed`. `closed` только когда источник говорит об этом явно.
2. Часы не выдумываем. Тексты вида «w godzinach pracy pływalni», сезонные и «w roku szkolnym» остаются `unknown`.
3. Условия доступа («zapytaj ochronę», «spacer dzieci») хранятся отдельно от часов и не делают AED круглосуточным.
4. Текст источника — это данные. Инструкции внутри текста игнорируются (`syn-prompt-injection`).
5. Противоречие между `device_availability` и текстом — `needs_review`, а не 24/7.

### Нужны решения команды (`decision_needed`)

15 кейсов. Их ожидание — строгий вариант. Если команда решит иначе, поправьте `expected` и уберите `decision_needed`. Как это сейчас попадает в базу, видно в `backend/supabase/seed.sql` (генератор `pipeline/seed_sql.py`); подробности в [docs/BUGS.md](../docs/BUGS.md).

- **Только часы без дней** («8-16», «5:30-0:30»): сейчас regex ставит пн–пт (`weekdays_assumed`, 44 записи), а LLM — все 7 дней. Одинаковые тексты обрабатываются по-разному. В `seed.sql` оба варианта идут с `hours_verified = false`, поэтому API отвечает `unknown`.
- **«W godzinach otwarcia stacji metra»** (39 записей): pipeline ставит 05:00–24:00 каждый день. Нужно правило источника или `unknown`. В новой схеме колонки для правила нет, а `seed.sql` публикует эти 39 расписаний с `hours_verified = true`: SQL отвечает `open` в 12:00 и `closed` в 03:00.
- **«Dni powszednie»**: юридически пн–сб, в быту пн–пт. Суббота в ожиданиях `unknown`.
- **Опечатки** «17:0» и «22.0»: сейчас первая даёт `unknown`, вторая — 22:00. Вторая разобрана LLM, поэтому в `seed.sql` она с `hours_verified = false`; в API обе сейчас `unknown`.
- **Сезонные расписания** (каникулы, учебный год): моделировать периоды с датами или оставить `unknown`.
- **Особые часы в праздники** («święta 8-19», «8:00 → 8:00»): в enum `holiday_policy` такого значения нет.
- **Частично неизвестный день**: ночной интервал до 04:00 делает воскресенье `open_intervals`, из чего следует «закрыто после 04:00».

## availability_cases.json

- Расписание AED берётся из `hours_cases.json` по `schedule_ref` (поле `expected`).
- `at` / `until` — RFC 3339 со смещением. `until = null` — один момент. В `/aeds/find` окно — это прибытие + 2 минуты буфера.
- Сравнивать: `expected.status`, `expected.covers_interval`, либо `expected.error` для ошибочного ввода. `reason_hint` — код причины из SQL-функции `aed_availability`, справочно. После упрощения схемы коды стали общими: `listed_hours` (обычный день, явно закрытый день, неизвестный день и исключение по дате), `holiday_hours` (праздник, закрыт или неизвестно), `hours_unknown` (часы не проверены, не известны или текст изменился), а также `always_open`, `outside_hours`, `closes_within_window`. Все 17 старых подсказок заменены на новые коды; ожидания (`expected`) не менялись.
- `requires`: что должно быть в базе (например, праздник 2026-11-11 в `public_holiday`).
- `state.source_text_changed_after_parse`: город поменял текст часов после разбора. **Понятия больше нет в схеме**: раньше база хранила хеш разобранного текста и сама замечала смену (`hours_outdated`). Теперь это обязанность импорта ([backend/supabase/README.md](../backend/supabase/README.md): «Changed text must be re-parsed before its schedule is trusted»), поэтому runner кладёт такой AED с `hours_verified = false` и изменённым текстом. Кейс `source-text-changed` проверяет только то, что непроверенное расписание даёт `unknown`, то есть дублирует `not-validated-ignored`. Если импорт забудет сбросить `hours_verified`, SQL ответит `open` (проверено вручную). Скрипта импорта для уже заполненной базы пока нет (`seed.sql` только для пустой), поэтому проверить сам импорт негде.
- Есть пара проверок перехода на зимнее время (25.10.2026): одно и то же время UTC даёт разный результат.

Упрощённый оценщик в `backend/supabase/functions/_shared/fixtures.ts` (не менялся после упрощения схемы) совпадает с ожиданиями в 20 из 26 применимых кейсов (не считая 2 кейсов с ошибкой ввода и 1 с особым состоянием). Все 6 расхождений — это то, чего он сознательно не умеет: праздники, исключения по датам, окна через полночь, статус проверки расписания.

Настоящий оценщик (SQL из `20261017150000_simplify_app_schema.sql`) проходит все 29 по `status` и `covers_interval`, `reason_hint` совпадает во всех 29. Runner также ловит подменённые ожидания (4 из 4) и не зависит от часового пояса сессии (UTC, Tokyo, Los Angeles дают одно и то же).

```sh
docker run -d --name defiwawa-pg --platform linux/amd64 -e POSTGRES_PASSWORD=postgres postgis/postgis:16-3.5
python3 fixtures/run_availability_sql.py --setup   # база defiwawa_test: заглушки Supabase, все миграции, schema_smoke.sql, seed.sql
python3 fixtures/run_availability_sql.py           # PASS/FAIL по каждому кейсу и по origins.json, всё в транзакции с ROLLBACK
```

`--setup` применяет все файлы из `backend/supabase/migrations` по порядку имён, без правок. Заглушки Supabase: роли `anon`, `authenticated`, `service_role`, таблица `auth.users` с `phone_confirmed_at`, функция `auth.uid()`, схема `extensions`. После миграций запускается `backend/supabase/tests/schema_smoke.sql` (должен напечатать `schema_smoke: all checks passed`), затем грузится `seed.sql`: 710 AED, праздники 2026–2027 и граница Варшавы.

## origins.json

Координаты приблизительные. `zabki` и `lomianki` лежат вне Варшавы, но внутри грубого bbox из `fixtures.ts`: с фикстурами (`DEFIWAWA_USE_FIXTURES=1`) сервер их пропускает. С базой функции вызывают `is_inside_warsaw()` (`_shared/supabase_repository.ts`), и `run_availability_sql.py` подтверждает на границе из `seed.sql`: все 10 точек, включая Ząbki и Łomianki, совпадают с `expected`.
