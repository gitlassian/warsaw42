# DefiWawa — баг-лист для разработчиков

Составил Саня (QA) по итогам работы над [fixtures](../fixtures/README.md) и [Postman-коллекцией](../postman/README.md). Дата проверки: 17.10.2026, ветка `Pofa`, коммит `4714526`. Код в этом документе не менялся.

- **bug** — расходится с [PLAN.md](../PLAN.md) / [ENDPOINTS.md](../ENDPOINTS.md) или ломает работу.
- **нужно решение** — спецификация не даёт ответа, команде нужно выбрать.
- Цифры по данным посчитаны на `backend/data/out/aed.json` (710 записей).
- SQL-функции я не запускал (нет `psql` и Supabase CLI): выводы по ним сделаны чтением кода. Остальное запускалось.
- `fixtures/` и `postman/` пока не закоммичены, поэтому ссылки на них на GitHub заработают после коммита.

## Сводка

| № | Что | Статус | Кому (основной → второй) |
| --- | --- | --- | --- |
| 1 | CI-обновление данных пишет не туда; cron раз в 3 часа | bug | Вітя → Ярік |
| 2 | Пустой день = «закрыто», формат не умеет `unknown` | bug | Вітя + Ярік |
| 3 | Нумерация дней 0–6 вместо ISO 1–7 | bug (латентный) | Вітя |
| 4 | Часы без дней: regex → пн–пт, LLM → все 7 дней | нужно решение | Вітя |
| 5 | Опечатки `17:0` и `22.0` обрабатываются по-разному | нужно решение | Вітя |
| 6 | LLM теряет частично известные дни | bug | Вітя → Ярік |
| 7 | Часы метро выдуманы (05:00–24:00) | нужно решение | Вітя → Ярік |
| 8 | id 3931: противоречие помечено, но опубликовано как 24/7 | bug | Вітя → Ярік |
| 9 | Маршрут к `active=false` отдаёт 200 | нужно решение | Вітя |
| 10 | Коды причин доступности: SQL ≠ фикстуры | нужно решение | Ярік + Вітя |
| 11 | Функции не подключены к `is_inside_warsaw`: Ząbki и Łomianki = Варшава | bug (известная заглушка) | Вітя → Ярік |
| 12 | Кто делает OTP: Максім или Вітя | нужно решение | вся команда |
| 13 | Битые ссылки и 500 для id 2487 | bug (документы) | автор документов |
| 14 | Web на React, а PLAN §2 — один Flutter | нужно решение | Максім |
| 15 | Дыры в ENDPOINTS.md: код неверного SMS и тело отзыва override | нужно решение | Максім, Вітя |

**По людям.** Вітя: 1–11. Ярік: 1, 2, 6, 7, 8, 10, 11. Максім: 14, 15. Все: 12, 13.

---

## 1. CI обновления данных пишет не в `backend/data`, cron раз в 3 часа

**bug** · Вітя (пути pipeline и workflow), Ярік (импорт и расписание)

- **Что.** Данные в репозитории лежат в `backend/data/`. Коммит `648c56b` оставил `data/` в корне и сдвинул пути pipeline на `../..`. Коммит `a5f93f2` («backend structure changes») потом переместил `data/` в `backend/data/`, но пути не поправил. Теперь все пять путей pipeline указывают на `<repo>/data`, где ничего нет: [fetch_aed.py](../backend/pipeline/fetch_aed.py#L18), [build.py](../backend/pipeline/build.py#L23), [building.py](../backend/pipeline/building.py#L16), [llm_hours.py](../backend/pipeline/llm_hours.py#L19), [osm_levels.py](../backend/pipeline/osm_levels.py#L14). Шаг `git add data/raw data/out data/cache` в [workflow](../.github/workflows/refresh-aed.yml#L34) идёт от корня и ориентируется на те же пути.
- **Важно: «git add падает с 128» верно только для этой рабочей копии.** Здесь `<repo>/data` ещё нет. В настоящем CI шаги fetch и build сами создают `<repo>/data/`, и `git add` проходит (exit 0). Тогда бот коммитит и пушит **новый каталог `data/` в корне**, а `backend/data/` не обновляется никогда.
- **Последствия** (эмуляция CI: чистая копия репозитория, снимок в `<repo>/data/raw`, `python -m pipeline.build --no-llm`):
  - **Разово, в первый запуск.** `hours_cache.json` не найден, и все 75 текстов с LLM-разбором оплачиваются заново (без ключа они становятся `unparsed/unknown`). Дальше кэш живёт в `<repo>/data/cache`, а закоммиченный `backend/data/cache/hours_cache.json` становится мёртвым;
  - **В каждый запуск.** `osm_levels.json` и `aed_building.json` в workflow не генерируются ([osm_levels.py](../backend/pipeline/osm_levels.py) и [building.py](../backend/pipeline/building.py) там не вызываются) и в `<repo>/data` их нет: `floor_source=osm` пропадает у 111 записей, `in_footprint` заполнен у 0 из 710 (в закоммиченном файле у всех 710);
  - предыдущий снимок не найден, поэтому `changes.jsonl` не получает диффа;
  - `.gitignore` ([строки 3–7](../.gitignore#L3-L7)) закрывает только `<repo>/data/aed|geo|population|bo`. Если снимок из [backend/data/README.md](../backend/data/README.md) (1,8 ГБ) положить в `backend/data/`, он не игнорируется.
- **Воспроизвести** (из корня репозитория):
  ```sh
  git add --dry-run data/raw data/out data/cache; echo "exit=$?"
  # fatal: pathspec 'data/raw' did not match any files, exit=128 (только пока <repo>/data нет)
  python3 -c "import os,sys; sys.path.insert(0,'backend'); from pipeline import build; print(os.path.normpath(build.ROOT))"
  # <repo>/data, а не <repo>/backend/data
  ```
- **Ожидается.** Pipeline читает и пишет `backend/data/{raw,out,cache}`, а workflow коммитит именно их. Варианты: (а) заменить `"..", ".."` на `".."` в пяти файлах pipeline и в workflow писать `git add backend/data/raw backend/data/out backend/data/cache` (рекомендую: `check_fixtures.py` уже читает `backend/data/raw`); (б) вернуть `data/` в корень.
- **Отдельно: cron.** [Строка 5](../.github/workflows/refresh-aed.yml#L5): `0 */3 * * *`, раз в 3 часа. [PLAN §4](../PLAN.md#L147) и [критерий приёмки](../PLAN.md#L367) требуют раз в 2 часа (см. также [ENDPOINTS.md](../ENDPOINTS.md#L142)). Нужно `0 */2 * * *`.

## 2. Пустой день трактуется как «закрыто», формат `aed.json` не умеет `unknown`

**bug** · Вітя (формат pipeline), Ярік (загрузка в `aed_day_state`)

- **Что.** [`is_open`](../backend/pipeline/hours.py#L247-L252) для пустого списка дня возвращает `False` (закрыто). [PLAN §5](../PLAN.md#L167): «Empty intervals alone must not imply closure». Сам формат расписания ([hours.py](../backend/pipeline/hours.py#L8), [validate_schedule](../backend/pipeline/hours.py#L148-L165)) хранит день только списком интервалов, поэтому «закрыто» и «неизвестно» в нём не различить. В БД [`aed_day_state`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L253-L260) это различие есть.
- **Масштаб.** У 470 из 710 записей `sat: []`: 428 со статусом `scheduled` (из них 44 с `weekdays_assumed`) и 42 `unknown`. Загрузчик из `aed.json` в БД не сможет решить, чем заменить `[]`.
- **Оговорка.** `is_open` нигде не вызывается, кроме [теста](../backend/tests/test_hours.py#L55-L59), который закрепляет `False` для субботы. Дефект сейчас в формате и в будущем загрузчике.
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import sys; sys.path.insert(0,'backend'); from pipeline.hours import parse_regex, is_open; p=parse_regex('Poniedziałek: godz. 8:00-18:00; Wtorek-Piątek: godz. 8:00-16:00'); print(p.schedule['sat'], is_open(p.schedule, 5, 600))"
  # [] False: пример из PLAN §5, суббота «закрыта» в 10:00
  python3 -c "import json;print(sum(not r['schedule']['sat'] for r in json.load(open('backend/data/out/aed.json'))))"
  # 470
  ```
- **Ожидается.** [PLAN §5](../PLAN.md#L192) и [приёмка](../PLAN.md#L369): суббота и воскресенье в этом примере остаются `unknown`. Для этого в `aed.json` нужно состояние дня (`open_intervals | closed | unknown`), как в контракте.

## 3. Нумерация дней: в pipeline 0 = понедельник, в контракте ISO 1 = понедельник

**bug (латентный)** · Вітя

- **Что.** В pipeline день — индекс 0–6: [`DAY_KEYS`](../backend/pipeline/hours.py#L14), [`_DAY_INDEX`](../backend/pipeline/hours.py#L25-L33), [`_range`](../backend/pipeline/hours.py#L86-L89), [`is_open(dow)`](../backend/pipeline/hours.py#L247-L249) с docstring «0=Mon». В контракте ISO: [PLAN §5](../PLAN.md#L167), [`dow BETWEEN 1 AND 7`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L253-L260), [`extract(isodow ...)`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L734), [fixtures.ts](../backend/supabase/functions/_shared/fixtures.ts#L90-L95).
- **Оговорка.** В `aed.json` дни записаны именами (`mon`…`sun`), так что число видно только в аргументе `is_open` и в будущем загрузчике. Сейчас ошибки нет, но на стыке со сдвигом на 1 она тихая.
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import sys; sys.path.insert(0,'backend'); from pipeline.hours import parse_regex, is_open; s=parse_regex('Poniedziałek: godz. 8:00-18:00; Wtorek-Piątek: godz. 8:00-16:00').schedule; print(is_open(s, 0, 17*60), is_open(s, 1, 17*60))"
  # True False: ISO-понедельник (1) функция читает как вторник
  ```
- **Ожидается.** Один способ нумерации на границе pipeline → БД. Либо `is_open` принимает ISO, либо в загрузчике явно `DAY_KEYS.index(k) + 1`.

## 4. Часы без дней: regex ставит пн–пт, LLM — все 7 дней

**нужно решение** · Вітя

- **Что.** Для текста «только часы» regex подставляет пн–пт и ставит флаг `weekdays_assumed` ([hours.py](../backend/pipeline/hours.py#L199-L205); 44 записи, например id 700 `7.30-18.00`, 723 `7-19`, 907 `8-16`). Это поведение закреплено [тестом](../backend/tests/test_hours.py#L28-L31). В [системном промпте LLM](../backend/pipeline/llm_hours.py#L21-L29) правила для текста без дней нет, и id 3303 и 3991 («W godzinach 5:30-0:30 …») модель разворачивает на все 7 дней. Тексты одного типа получают разные дни.
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import sys,json; sys.path.insert(0,'backend'); from pipeline.hours import parse_regex; print(parse_regex('8-16').assumed); d={r['id']:r for r in json.load(open('backend/data/out/aed.json'))}; print(list(k for k,v in d['3303']['schedule'].items() if v))"
  # ['weekdays_assumed'] (пн–пт), затем все 7 дней для id 3303
  ```
- **Ожидается.** [PLAN §5](../PLAN.md#L192): не названные дни остаются `unknown`; допущения города оформляются версионированным правилом источника (поле [`applied_source_rules`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L239)), а не догадкой. Вариант (а): `unknown` для не названных дней (в фикстуре `scb-3303` ждём `unknown` + `needs_review`). Вариант (б): город подтверждает «часы без дней = пн–пт», тогда правило одно для regex и LLM. Если выберете (б), добавьте его в промпт и обновите тест.

## 5. Опечатки `17:0` и `22.0` обрабатываются по-разному

**нужно решение** · Вітя

- **Что.** Оба текста regex отдаёт в LLM: хвост с цифрой даёт `None` ([hours.py](../backend/pipeline/hours.py#L211-L212)). Модель отвечает по-разному:
  - id 1324 `Dni powszednie 07:00-17:0` → `unknown` («godzina zakończenia jest niekompletna»);
  - id 3500 `poniedziałek-sobota w godz. 6.00 - 22.0` → пн–сб 06:00–22:00.
- Кэш по [строкам 111–116](../backend/pipeline/llm_hours.py#L111-L116) закрепляет первый ответ модели.
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import json;d={r['id']:r for r in json.load(open('backend/data/out/aed.json'))};[print(i,d[i]['status'],d[i]['parse_source'],repr(d[i]['raw_hours'])) for i in ('1324','3500')]"
  ```
- **Ожидается.** [PLAN §5](../PLAN.md#L203): часы не выдумываем, неразобранное остаётся `unknown`. Нужно одно правило для обеих опечаток. Рекомендую `unknown` + `needs_review`. Если решите читать `X:0` как `X:00`, делайте это в детерминированном парсере, а не в LLM.

## 6. LLM теряет частично известные дни

**bug** · Вітя (схема и промпт), Ярік (если в `aed.json` нужно состояние дня, см. п. 2)

- **Что.** Схема ответа LLM содержит один `status` на весь AED и ни одного состояния дня ([llm_hours.py](../backend/pipeline/llm_hours.py#L31-L58)), а [промпт](../backend/pipeline/llm_hours.py#L25-L27) велит при сомнении возвращать `unknown`. Поэтому частично известные расписания схлопываются целиком:
  - id 750 «пн 08–18, вт–чт 08–16», пятница не названа → весь AED `unknown`;
  - id 2957 «пн–пт 8–18; wybrane soboty i niedziele 9–21» → весь AED `unknown`, хотя будни известны.
- id 750 повторяет пример из [PLAN §5](../PLAN.md#L169-L190) (`validated_partial`). Фикстуры `scb-750` и `scb-2957` ждут `weekly` + `validated_partial`.
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import json;d={r['id']:r for r in json.load(open('backend/data/out/aed.json'))};[print(i,d[i]['status'],d[i]['note']) for i in ('750','2957')]"
  ```
- **Ожидается.** Известные дни сохраняются, неизвестные получают `unknown` ([PLAN §5](../PLAN.md#L192), [приёмка](../PLAN.md#L369)).
- **Осторожно при исправлении.** Кэш [ключуется только текстом](../backend/pipeline/llm_hours.py#L113-L116): после правки промпта старые ответы не пересчитаются, пока кэш не сбросить (в схеме БД кэш ключуется ещё и версией парсера).

## 7. `metro_hours_assumed`: выдуманные часы 05:00–24:00

**нужно решение** · Вітя → Ярік

- **Что.** Для «W godzinach otwarcia stacji metra» (39 записей: 38 + 1 с опечаткой «otwacia») pipeline ставит [05:00–24:00 каждый день](../backend/pipeline/hours.py#L17-L18) ([ветка](../backend/pipeline/hours.py#L173-L178)); `osm_hours` = `Mo-Su 05:00-24:00`. Комментарий в коде признаёт, что реальное расписание имеет ночной перерыв. Флаг `assumed` попадает в `aed.json`, но у `aed_hours` в БД места под него нет (есть только `applied_source_rules`).
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import json;print(sum('metro_hours_assumed' in r['assumed'] for r in json.load(open('backend/data/out/aed.json'))))"  # 39
  ```
- **Ожидается.** [PLAN §5](../PLAN.md#L203): «Never invent missing hours». Либо версионированное правило источника (`applied_source_rules`, например `metro_station_hours@1`) с реальными часами метро, либо `unknown`. Тест [`test_metro_is_flagged_as_assumption`](../backend/tests/test_hours.py#L33-L35) придётся обновить.

## 8. id 3931: `device_availability=Tak` + сезонные часы → публикуется как 24/7

**bug** · Вітя (pipeline) → Ярік (загрузчик: `suspicious` → `review_status`)

- **Что.** Текст id 3931: «Ochrona 24h. Dla odwiedzających: maj-wrzesień pn-pt 12:00-20:00, weekendy 10:00-20:00; październik-kwiecień pn-nd 12:00-18:00». Ветка `Tak` ([build.py](../backend/pipeline/build.py#L72-L75)) безусловно ставит `24/7`. Запись при этом помечена `suspicious: true` («24/7 flag but the text lists limited hours»), то есть противоречие pipeline заметил, но опубликовал как 24/7. В выходной записи [нет поля `review_status`](../backend/pipeline/build.py#L93-L106), а в БД значение `needs_review` [есть](../backend/supabase/migrations/20261017120000_initial_schema.sql#L27) и непроверенные часы дают [`unknown`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L779-L781).
- **Воспроизвести** (из корня):
  ```sh
  python3 -c "import json;r=[x for x in json.load(open('backend/data/out/aed.json')) if x['id']=='3931'][0];print(r['status'],r['suspicious'],r['suspicious_reasons'])"
  # 24/7 True ['24/7 flag but the text lists limited hours', '24/7 indoors outside a staffed building']
  ```
- **Ожидается.** [PLAN §5](../PLAN.md#L203) (сомнение не превращается в 24/7) и [приёмка](../PLAN.md#L370) (conflicting classifications). Фикстура `scb-3931`: `unknown` + `needs_review`. Для сведения: ещё у 74 записей `24/7` помечен `suspicious` по эвристике «в помещении вне охраняемого здания». Это только флаг, но он тоже не доходит до БД.

## 9. `POST /routes/walking` к AED с `active=false` отвечает 200

**нужно решение** · Вітя

- **Что.** [walking.ts](../backend/supabase/functions/_shared/handlers/walking.ts#L29-L30) возвращает 404 только когда AED не найден. Для снятого с учёта AED маршрут строится, ответ 200, `eligible_for_automatic_selection=false`, `warnings=["inactive"]` ([eligibility.ts](../backend/supabase/functions/_shared/eligibility.ts#L19-L23)). [ENDPOINTS.md](../ENDPOINTS.md#L65) явно разрешает ручной выбор закрытых и неопределённых AED, но про неактивные молчит. [PLAN §6](../PLAN.md#L213) исключает неактивные только из автоматического выбора.
- **Воспроизвести.** Postman: `LIVE · … / POST /routes/walking / Маршрут к fx-inactive → inactive`. Либо в тестовом окружении `makeDeps()` из [helpers.ts](../backend/tests/helpers.ts): `POST` с `aed_id: "fx-inactive"` → `200`, `warnings: ["inactive"]`.
- **Ожидается — решить.** Строить маршрут (как сейчас, с предупреждением) или отвечать `404 aed_not_found` (по [ENDPOINTS.md](../ENDPOINTS.md#L169) 404 — «unknown resources»). Результат записать в ENDPOINTS.md.

## 10. Коды причин доступности расходятся: SQL и фикстуры

**нужно решение** · Ярік (SQL) + Вітя (фикстуры)

- **Что.**
  - Явно закрытый день: SQL отдаёт `weekly_hours` ([строка 737](../backend/supabase/migrations/20261017120000_initial_schema.sql#L737), возвращается через [`ARRAY[d.reason]`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L793-L796)), фикстуры отдают `day_closed` ([fixtures.ts](../backend/supabase/functions/_shared/fixtures.ts#L68)).
  - Нет расписания: SQL — `no_hours` ([строка 773](../backend/supabase/migrations/20261017120000_initial_schema.sql#L773)) или `hours_unknown` ([784](../backend/supabase/migrations/20261017120000_initial_schema.sql#L784)), фикстуры — `no_schedule` ([fixtures.ts](../backend/supabase/functions/_shared/fixtures.ts#L61)).
  - Совпадают: `day_unknown`, `outside_hours`, `weekly_hours` для открытого дня, `always_open`.
- **Воспроизвести.** Фикстуры (из `backend/`, Node 22.18+): вызвать `createFixtureEvaluator([...]).evaluate(...)` для AED с `weekly: {"1": {state: "closed", intervals: []}}` в понедельник → `reasons: ["day_closed"]`. SQL: читать код (я его не запускал).
- **Ожидается.** [ENDPOINTS.md](../ENDPOINTS.md#L41) говорит о `reasons`, но не перечисляет коды. Нужен закрытый список кодов в ENDPOINTS.md, и SQL с фикстурами должны выдавать одни и те же. Клиенты локализуют стабильные коды ([ENDPOINTS.md](../ENDPOINTS.md#L170)). Сейчас `reason_hint` в [availability_cases.json](../fixtures/availability_cases.json) следует SQL.

## 11. Edge Functions не подключены к `is_inside_warsaw`: Ząbki и Łomianki проходят как Варшава

**bug (известная заглушка)** · Вітя (подключение), Ярік (граница в `service_area`)

- **Что.** Единственная реализация репозитория — фикстурная: [`isInsideWarsaw`](../backend/supabase/functions/_shared/fixtures.ts#L30-L34) сравнивает с грубым bbox ([строки 23–24](../backend/supabase/functions/_shared/fixtures.ts#L23-L24): долгота 20.85–21.28, широта 52.09–52.37). [deps.ts](../backend/supabase/functions/_shared/deps.ts#L21-L25) без `DEFIWAWA_USE_FIXTURES=1` вообще не стартует. Настоящая проверка [`is_inside_warsaw`](../backend/supabase/migrations/20261017120000_initial_schema.sql#L648-L654) в БД есть, но не вызывается. В репозитории не загружена и реальная граница: единственный `INSERT INTO service_area` лежит в [schema_smoke.sql](../backend/supabase/tests/schema_smoke.sql#L40).
- **Воспроизвести.** Postman: `KNOWN GAPS / Ząbki: вне Варшавы, но внутри bbox фикстур → должно быть 422`. Либо `POST /routes/walking` или `/aeds/find` с origin Ząbki `{52.2927, 21.1053}` или Łomianki `{52.3337, 20.8866}` (координаты из [origins.json](../fixtures/origins.json), ±50 м) → `200` вместо `422 outside_service_area` ([validation.ts](../backend/supabase/functions/_shared/validation.ts#L52-L56)). Pruszków и Piaseczno отсекаются.
- **Ожидается.** [PLAN §1](../PLAN.md#L9) и [приёмка](../PLAN.md#L368): origin вне административной границы города получает отказ. Нужно подключить `is_inside_warsaw` (через RPC) и загрузить границу. До тех пор не считать Postman-тест «outside» пройденным.

## 12. Кто отвечает за OTP: Максім или Вітя

**нужно решение** · вся команда (подтвердить)

- **Что.** В репозитории всё согласовано: OTP и Twilio у **Максіма** ([ENDPOINTS.md](../ENDPOINTS.md#L20-L21) — строки таблицы; [строка 27](../ENDPOINTS.md#L27); три эндпоинта `reports/otp/*` в [строках 77–79](../ENDPOINTS.md#L77-L79)). Расхождение — с распределением задач команды вне репозитория (по нему OTP у **Віті**). Самого распределения в репозитории нет, поэтому проверить его я не мог.
- **Воспроизвести.** Сверить ENDPOINTS.md с актуальным распределением.
- **Ожидается.** Один ответственный. Если OTP у Віті, поправить строки 20–21, 26–27 и 77–79; тогда `POST /reports` ([строка 80](../ENDPOINTS.md#L80)) и выдача `report_token` оказываются у одного человека, и согласование между двумя (строка 27) не нужно.

## 13. Битые ссылки в документах и id 2487

**bug (документы)** · автор ENDPOINTS.md / DESIGN.md

- **Ссылки на `plan.md`.** В [ENDPOINTS.md:3](../ENDPOINTS.md#L3) и [ENDPOINTS.md:147](../ENDPOINTS.md#L147) стоит `plan.md`, а файл называется `PLAN.md`. На macOS работает (`core.ignorecase=true`), на Linux и в GitHub-рендере ссылка битая.
- **Ссылка на несуществующий файл.** [DESIGN.md:5](../DESIGN.md#L5) ссылается на `DESIGN_RESEARCH.md`; такого файла в репозитории нет (`git ls-files | grep -i design`).
- **id 2487.** [backend/data/README.md](../backend/data/README.md#L14): детальный запрос по id 2487 стабильно отдаёт 500; о том же говорит [комментарий](../backend/pipeline/fetch_aed.py#L90) в `fetch_aed.py`. Я это **не воспроизводил** (нужен ключ API города, а файла `scb_aed_details_failed.json` в репозитории нет). Запись 2487 в списочном ответе есть, regex её разбирает (пн–пт 07:30–19:00). Не работает только запрос фото и деталей: `--photos` пропустит id 2487 с сообщением в stderr, фото для него не будет.
- **Ожидается.** Поправить регистр в двух местах, убрать или создать `DESIGN_RESEARCH.md`. Для 2487 нужно решение, как показывать AED без фото (и спросить город, почему падает запрос).

## 14. Web на React + Vite, а PLAN §2 предполагает один Flutter-код

**нужно решение** · Максім

- **Что.**
  - [PLAN §2](../PLAN.md#L35): «One Flutter codebase, built separately for web, Android, and iOS»; то же в [DESIGN.md:5](../DESIGN.md#L5) и [frontend/AGENTS.md:4](../frontend/AGENTS.md#L4).
  - В коде: [frontend/web](../frontend/web/README.md#L3) — React 19 + TypeScript + Vite ([package.json](../frontend/web/package.json#L12-L16)); [frontend/mobile](../frontend/mobile/pubspec.yaml#L2) — Flutter только для iOS и Android, каталога `web/` нет.
  - Это два независимых кода. Дублируются дизайн-токены ([tokens.css](../frontend/web/src/design-system/tokens.css) и [tokens.dart](../frontend/mobile/packages/design_system/lib/src/tokens.dart)), а «общий Dart-оценщик доступности» из PLAN недоступен вебу. Критерий [«UI parity»](../PLAN.md#L374) придётся проверять между двумя реализациями.
  - Сам [PLAN §1](../PLAN.md#L11-L14) описывает «Web app» и «Flutter mobile app» отдельно, то есть документ и сам противоречит себе.
- **Воспроизвести.** `ls frontend/mobile` (нет `web/`) и `cat frontend/web/package.json`.
- **Ожидается — решить.** Либо добавить web-таргет Flutter (как в PLAN), либо оставить React и обновить PLAN §2, DESIGN.md, AGENTS.md с указанием, где живёт логика доступности (сервер/SQL как единственный оценщик или дубль на TS).

## 15. В ENDPOINTS.md не зафиксированы код ошибки неверного SMS-кода и тело PATCH отзыва override

**нужно решение** · Максім (OTP), Вітя (override)

- **Что.**
  - **Неверный код.** Для `POST /reports/otp/verify` ([строка 79](../ENDPOINTS.md#L79)) не указан ни код ошибки, ни HTTP-статус для: неверного кода, истёкшего кода, исчерпанных попыток (лимит «пять попыток» только упомянут в [строке 84](../ENDPOINTS.md#L84)). Общие правила ([строки 169–170](../ENDPOINTS.md#L169-L170)) допускают и `422`, и `401`, и `429`. Для отчётов определён только `409 authorization_used` ([строка 88](../ENDPOINTS.md#L88)).
  - **Отзыв override.** `PATCH /admin/aeds/{id}/overrides/{override_id}` ([строка 132](../ENDPOINTS.md#L132)) описан словами: «revoke … with a reason and `expected_version`». Имена полей не названы. Для сравнения, у `PATCH /admin/reports/{id}` ([строка 130](../ENDPOINTS.md#L130)) поля перечислены. В Postman-коллекции стоит предположение `{"revoke": true, "reason", "expected_version"}`.
- **Воспроизвести.** Прочитать указанные строки; в Postman запросы SPEC для OTP verify и PATCH override пока 404.
- **Ожидается.** В ENDPOINTS.md: (а) коды `invalid_otp` / `otp_expired` / `otp_attempts_exceeded` (имена предлагаю) со статусами и признаком «можно ли повторить»; (б) явное тело PATCH (например `{"status": "revoked", "reason", "expected_version"}`).

---

## Как проверялось

Каждый пункт сверялся с кодом на ветке `Pofa`: pipeline запускался на `aed.json`, Edge Functions вызывались через обработчики с фейковым провайдером маршрутов (`backend/tests/helpers.ts`), CI эмулировался на чистой копии репозитория. SQL читался, но не выполнялся. Пункты 12 и 13 (id 2487) невозможно подтвердить из репозитория полностью, это отмечено в тексте.
