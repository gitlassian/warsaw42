# Postman-коллекция DefiWawa

Тестовая коллекция по контракту из [ENDPOINTS.md](../ENDPOINTS.md) (упрощённый API, коммит `486c97d` в main): 48 запросов. Ответственный: Саня.

- `DefiWawa.postman_collection.json` — коллекция.
- `DefiWawa.local.postman_environment.json` — окружение для локального Supabase. Секретов в нём нет, все ключи пустые.

Импорт: Postman → Import → оба файла → выбрать окружение «DefiWawa · local (TEST)».

## Папки

| Папка | Запросов | Состояние | Что проверяет |
| --- | --- | --- | --- |
| **LIVE · Маршруты и ETA** | 27 | работает сейчас | `/routes/etas`, `/routes/walking`, `/aeds/find` на 7 фейковых AED из `_shared/fixtures.ts` |
| **KNOWN GAPS** | 1 | падает в режиме фикстур | Ząbki вне Варшавы, но внутри грубого bbox фикстур. С базой должна быть зелёной |
| **SPEC · AED** | 7 | пока 404 | `GET /aeds` (все AED и `bbox`), `GET /aeds/{id}` |
| **SPEC · Отчёты** | 11 | пока 404 | Сессия Supabase Phone Auth, затем `POST /reports` |
| **SPEC · Покрытие** | 1 | пока 404 | `GET /coverage` |
| **SPEC · Offline** | 1 | пока 404 | `GET /offline` |

Общие проверки коллекции идут для каждого запроса:

- маршруты (`aeds-find`, `routes-etas`, `routes-walking`) сохраняют прежний конверт: `{data, meta}` с `request_id` и `generated_at`, ошибка `{error: {code, message, details}, request_id}`;
- новые эндпоинты: `{data}` и `{error: {code, message}}`, как в последнем разделе ENDPOINTS.md;
- в любой ошибке нет stack trace и ключей Google;
- ответы Supabase Auth (`/auth/v1/...`) общими проверками не проверяются: это не наш формат.

## Что изменилось после упрощения API

Удалены запросы к эндпоинтам, которых в новом ENDPOINTS.md нет: `GET /aeds/{id}/availability`, `POST /aeds/nearby`, `limit` и `next_cursor` у `GET /aeds`, `POST /reports/otp/{request,resend,verify}`, одноразовый `report_token` и `Idempotency-Key`, параметры `GET /coverage` и `/coverage/{layer}/regions/{region}`, `/offline/regions/...`, `GET /data/status`, все `/admin/*` и `/internal/*`.

Добавлены:

- `GET /aeds` без `bbox` (все активные AED, без пагинации) и с `bbox` из трёх чисел;
- проверка плоского объекта AED: 16 полей из ENDPOINTS.md, допустимые значения `public_access`, `operational_status`, `hours_status`, форма `hours` (дни `1`–`7`, интервалы в минутах `0`–`1440`, даты исключений `YYYY-MM-DD`, `holiday_policy`);
- `GET /aeds/not-a-uuid`: допускается 400, 404 или 422, лишь бы не 5xx;
- отчёты: два запроса к Supabase Auth (`/auth/v1/otp`, `/auth/v1/verify`) кладут сессию в `user_jwt`; затем `POST /reports` с этой сессией, второй отчёт той же сессией, граница описания 10/9 символов после trim и 2001 символ, неизвестная категория, неизвестный AED (404), без токена (401), с anon key (401/403);
- `GET /coverage` и `GET /offline` без параметров.

Неверный ввод ждём как `400` или `422`: ENDPOINTS.md разрешает оба.

## Как запустить LIVE локально

Нужны Supabase CLI и Docker. Команды выполнять из `backend/` (см. [functions/README.md](../backend/supabase/functions/README.md)):

```sh
supabase start
supabase status
supabase functions serve --env-file supabase/functions/.env
```

1. Из вывода `supabase status` скопируй `anon key` в переменную окружения `anon_key` в Postman.
2. В `supabase/functions/.env` нужны `DEFIWAWA_USE_FIXTURES=1` и **настоящий** `GOOGLE_ROUTES_API_KEY`: фейкового провайдера маршрутов в функциях нет. Тестовый ключ попроси у Вити. Production-ключи не нужны.
3. Запусти папку LIVE через Collection Runner.

LIVE работает только с `DEFIWAWA_USE_FIXTURES=1`. Без этого флага функции читают базу через `_shared/supabase_repository.ts`: id вида `fx-*` там не находятся (маршрут к ним даст 404), а проверка границы идёт через `is_inside_warsaw()`. Если база недоступна, функции отвечают `503 data_unavailable` (`_shared/http.ts`). С фикстурами этот ответ не воспроизвести, отдельного запроса для него нет.

Результат `/aeds/find` зависит от времени запуска:
- в будни 08:00–16:00 выбирается `fx-sample`;
- в остальное время — `fx-centrum-247` (24/7, второй круг поиска до 5 км).

Тесты учитывают оба варианта.

## Как проверялось без Postman

Newman, Deno и Supabase CLI в рабочей копии не установлены, поэтому коллекция проверена так (17.10.2026, ветка `Pofa` после слияния main):

- **синтаксис**: все 50 скриптов (общий и скрипты запросов) прошли `node --check`;
- **LIVE**: все запросы LIVE и KNOWN GAPS прогнаны через обработчики Вити (`createEtasHandler`, `createFindHandler`, `createWalkingHandler`) с фикстурами и фейковым провайдером маршрутов из `backend/tests/helpers.ts`, в понедельник 10:00, понедельник 21:00 и субботу 12:00. Скрипты исполнялись с заглушкой `pm` и небольшой реализацией `pm.expect`. В каждом прогоне 96 проверок LIVE прошли; в KNOWN GAPS прошла общая проверка формата, а единственная упавшая — сама проверка Ząbki, как и задумано;
- **SPEC**: эндпоинтов ещё нет, поэтому скрипты прогнаны против макета, который отвечает строго по ENDPOINTS.md. AED для макета выгружены из тестовой базы с `seed.sql` (710 записей с реальными `hours`): 70 из 70 проверок прошли. Против «не реализовано» (404 на всё) падают 31 проверка. Испорченные AED (нет `updated_at`, день недели `"0"`, `hours_status = "always_open"`) тесты ловят.

## Переменные окружения

| Переменная | Что это |
| --- | --- |
| `functions_url` | Адрес локальных Edge Functions, `http://127.0.0.1:54321/functions/v1` |
| `supabase_url` | Адрес локального Supabase для запросов к Auth, `http://127.0.0.1:54321` |
| `api_url` | Адрес для SPEC-запросов. Пути `/api/v1` требуют прокси при развёртывании (ENDPOINTS.md), **адрес прокси ещё не решён** — поменяй, когда команда договорится |
| `anon_key` | Публичный ключ локального Supabase |
| `aed_id` | uuid AED из базы (не номер города). Если пусто, его заполнит «AED: все активные» |
| `test_phone`, `test_otp_code` | Только тестовый номер и код из Supabase Auth → Providers → Phone → Test OTP. Личный номер не использовать |
| `user_jwt` | Сессия Supabase Phone Auth, заполняется запросом «подтвердить код» |
| `report_id` | Заполняется тестом «Отчёт: отправить» |

## Вопросы к команде, найденные при составлении

Подробно — в [docs/BUGS.md](../docs/BUGS.md).

- `POST /routes/walking` к AED с `active=false` (`fx-inactive`) с фикстурами отвечает 200 с предупреждением `inactive`, а с базой — 404 (`aed_public` содержит только активные AED). Какой ответ правильный?
- Имена полей в ответах `GET /coverage` (дата расчёта) и `GET /offline` (размер, контрольная сумма, дата) в ENDPOINTS.md не названы. Тесты ищут их по смыслу и ждут SHA-256 как контрольную сумму.
- Объект AED в ENDPOINTS.md не содержит `photo_path` и `district`, хотя миграция `20261017170000_aed_photo_district.sql` их добавила. Отдавать ли их в API?
- Чем отвечать на `GET /aeds/{id}` с id не в формате uuid: 400/422 или 404?
- Коды причин доступности расходятся: SQL отдаёт `listed_hours` для явно закрытого дня, фикстуры — `day_closed`.
