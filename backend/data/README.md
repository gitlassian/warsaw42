# Снимок данных для проекта AED (17.10.2026, ~10:00)

Сырые данные, выгруженные до начала хакатона. Это только данные: обработки и кода решения здесь нет (регламент §4.3). На хакатоне в 11:00 стоит повторить выгрузку свежих версий, а этот снимок держать как запасной на случай, если API города упадёт.

Ключ API в файлах не хранится.

## Структура

```
data/
├── aed/
│   ├── scb_aed_list.json            710 AED, ответ API как есть (GeoJSON-подобный список)
│   ├── scb_aed_details.json         те же 709 записей из запроса по каждому id, без base64 фото + поле photo_file
│   ├── scb_aed_details_failed.json  id 2487: детальный запрос стабильно отдаёт 500 (в списке запись есть)
│   ├── photos/                      709 фото AED (703 jpg, 6 png), ~1,5 ГБ, имя = defibrillator_id
│   ├── osm_aed_warszawa.json        1 062 AED из OpenStreetMap (Overpass), включая частные
│   └── meta/                        метаданные датасета, описание полей, примеры запросов с портала
├── geo/
│   ├── punkty_adresowe.geojson      126 923 адресные точки (WFS города, без ключа)
│   ├── budynki.geojson              184 488 зданий с этажностью и типом (WFS города, без ключа)
│   └── osm_dzielnice_raw.json       границы 18 районов (OSM admin_level=9, сырой ответ Overpass с геометрией)
├── population/
│   ├── GRID_NSP2021_RES.zip         сетка населения GUS, перепись 2021, 1 км, вся Польша
│   └── GRID_NSP2021_RES/            распакованный SHP (EPSG:2180)
├── bo/
│   ├── bo_<год>_<статус>.json       Budżet Obywatelski 2019–2026, zrealizowane и w_realizacji
│   ├── bo_2024_zr.json              дубль bo_2024_zrealizowane.json (из ранней проверки, не удалял)
│   ├── dataset_metadata.json
│   └── fields.json
└── _fetch_log.json                  время выгрузки и размеры файлов
```

## Источники и как перевыгрузить

| Данные | Откуда | Лицензия |
|---|---|---|
| AED (SCB) | `POST https://dane.um.warszawa.pl/api/action/get_scb_lokalizacja_defibrylatorow`, заголовок `Authorization: <ключ>`. Тело `{"defibrillator_id": "622"}` возвращает одну запись **с фото** в поле `properties.attachment` (base64) | CC BY, Stołeczne Centrum Bezpieczeństwa |
| Адресные точки | `https://wms2.um.warszawa.pl/geoserver/wfs/wfs?service=WFS&version=2.0.0&request=GetFeature&typeNames=wfs:punkty_adresowe&outputFormat=application/json&srsName=EPSG:4326` | данные м.ст. Варшавы |
| Здания | то же, `typeNames=wfs:budynki` | данные м.ст. Варшавы |
| Население | GUS ATOM: `https://geo.stat.gov.pl/atom-web/atom/PD` → «Rozmieszczenie ludności – demografia 2021r. (siatka, rezydenci)» | GUS, открытые данные |
| AED и районы из OSM | Overpass API, `emergency=defibrillator` и `boundary=administrative` + `admin_level=9` внутри Варшавы | ODbL, нужна атрибуция «© OpenStreetMap contributors» |
| Budżet Obywatelski | `POST .../get_cks_budzet_obywatelski`, тело `{"rok": 2024, "status": "zrealizowane"}`. **Нужны оба параметра**, иначе 500 | CC BY, CKS |

## Что важно знать о данных

### AED (SCB)
- Координаты вложенные: `geometry.coordinates = [[lon, lat]]`.
- `device_availability`: `Tak` 100, `Nie` 513, `Ograniczona` 95 и ещё 2 записи со свободным текстом. По описанию поля это ответ на вопрос «доступен ли AED 24/7».
- `device_location`: внутри здания 690, снаружи 20.
- `device_access_description` — часы свободным текстом, у 96 записей пусто (94 из них `Tak`, то есть круглосуточные: часы не указывают). Частые форматы: «dni powszednie 07:00-17:00», «Poniedziałek - Piątek w godzinach …», «W godzinach otwarcia stacji metra» (38).
- `device_public_access`: публичный 610, частный 100.
- Детальный запрос отличается от списка только фото, все остальные поля совпадают.
- В фото есть EXIF (модель телефона, дата съёмки). Перед публикацией фото в приложении EXIF лучше вырезать.

### OSM AED
- 1 062 точки: у 444 указаны `opening_hours`, у 101 это `24/7`. `access`: customers 534, yes 248, private 130.
- Это дополнение к данным SCB: частные AED, которые не заявлены городу. На питче основной источник — данные города (§4.9).

### Здания
- `KONDYGNACJE_NADZIEMNE` — число надземных этажей.
- `RODZAJ`: m 110 517, i 29 747, t 24 484, h 7 168, b 3 331, g 3 259, k 2 119, s 2 078, p 1 212, z 573.
- Вероятная расшифровка по классификации EGiB (проверить): m — жилые, i — прочие нежилые, t — транспорта и связи, h — торговые и сервисные, b — офисные, g — сельскохозяйственные, k — образования, науки, культуры и спорта, s — больницы и здравоохранение, p — промышленные, z — склады.
- `ID_BUDYNKU` начинается с TERYT района (например `146505_8…`).

### Население GUS
- Ячейки 1 × 1 км. Поля: `RES` (все жители), `RES_MALE`, `RES_FEM`, `RES_0_14`, `RES_15_64`, `RES_65_` (65+).
- Проекция EPSG:2180. Для Варшавы нужна вырезка по границе города.
- 1 км грубовато для радиуса 100–400 м. Жителей ячейки можно распределить по жилым зданиям пропорционально площади × этажности.

### Budżet Obywatelski
- 3 238 уникальных проектов, только профинансированные. Голоса в данных всегда 0.
- В записях есть имена авторов (`firstName`, `lastName`): не показывать (RODO).
- Про AED около 31 проекта (поиск по «AED» / «defibryl» в названии и кратком описании).
