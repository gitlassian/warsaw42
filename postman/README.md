# Postman-коллекция DefiWawa

Тестовая коллекция по контракту из [ENDPOINTS.md](../ENDPOINTS.md): 74 запроса. Ответственный: Саня.

- `DefiWawa.postman_collection.json` — коллекция.
- `DefiWawa.local.postman_environment.json` — окружение для локального Supabase. Секретов в нём нет, все ключи пустые.

Импорт: Postman → Import → оба файла → выбрать окружение «DefiWawa · local (TEST)».

## Папки

| Папка | Состояние | Что проверяет |
| --- | --- | --- |
| **LIVE · Маршруты и ETA** | работает сейчас | `/routes/etas`, `/routes/walking`, `/aeds/find` на 7 фейковых AED из `_shared/fixtures.ts` |
| **KNOWN GAPS** | должна падать | Ząbki вне Варшавы, но внутри грубого bbox фикстур. Станет зелёной, когда подключат реальную границу города |
| **SPEC · …** | пока 404 | Остальные эндпоинты по спецификации. Ожидания будут уточняться, когда их реализуют |

Каждый запрос дополнительно проходит общие проверки коллекции: успешный ответ имеет вид `{data, meta}` с `request_id` и `generated_at`, ошибка — `{error: {code, message, details}, request_id}`, без stack trace и без ключей Google.

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

Результат `/aeds/find` зависит от времени запуска:
- в будни 08:00–16:00 выбирается `fx-sample`;
- в остальное время — `fx-centrum-247` (24/7, второй круг поиска до 5 км).

Тесты учитывают оба варианта.

Проверено без Postman: все запросы LIVE прогнаны напрямую через обработчики Вити с фейковым провайдером маршрутов (`backend/tests/helpers.ts`) — в понедельник в 10:00, в понедельник в 21:00 и в субботу в 12:00. В каждом прогоне 97 проверок прошли, а единственная упавшая — из KNOWN GAPS, как и задумано.

## Переменные окружения

| Переменная | Что это |
| --- | --- |
| `functions_url` | Адрес локальных Edge Functions, `http://127.0.0.1:54321/functions/v1` |
| `api_url` | Адрес для SPEC-запросов. **Сопоставление с `/api/v1` ещё не решено** — поменяй, когда команда договорится |
| `anon_key` | Публичный ключ локального Supabase |
| `aed_id` | uuid AED из базы Ярика (не номер города) |
| `test_phone`, `test_otp_code` | Только тестовый номер из Supabase Auth → Phone → Test OTP. Личный номер не использовать |
| `admin_jwt` | JWT тестового модератора |
| `internal_token` | Серверный ключ для внутренних задач, только для локального окружения |
| остальные | Заполняются тестами автоматически (`challenge_id`, `report_token`, `report_id`, …) |

## Вопросы к команде, найденные при составлении

- `POST /routes/walking` к AED с `active=false` (`fx-inactive`) отвечает 200 с предупреждением `inactive`. Нужен ли маршрут к снятому с учёта AED, или лучше 404?
- Код ошибки для неверного SMS-кода в ENDPOINTS.md не зафиксирован.
- Формат тела `PATCH /admin/aeds/{id}/overrides/{override_id}` для отзыва правки в ENDPOINTS.md не описан. В коллекции стоит предположение `{"revoke": true, "reason", "expected_version"}`.
- Коды причин доступности расходятся: SQL отдаёт `weekly_hours` для явно закрытого дня, фикстуры — `day_closed`.
