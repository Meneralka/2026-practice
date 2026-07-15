# MZD-32: Жизненный цикл карточки документа и статусная модель

Статусная модель приведена в строгое соответствие со SPEC-13 (§1.1, §1.2, приложение А) и графами переходов MZD-22. Разграничение со статусами версии файла — MZD-16 / MZD-33; отслеживание доставки — MZD-34.

## 1. Реестр статусов документа (`DocumentStatus`, 8 статусов)

1. **Черновик (`DRAFT`)**: Начальное состояние карточки. Создается на шаге `/uploads/init`. Здесь же карточка находится всё время автопроверок файла и остаётся здесь при их провале (карантин): технический результат несёт `FileVersion.status`, статус карточки его не дублирует (Q-1, close-questions).
2. **На проверке (`UNDER_REVIEW`)**: Ручная проверка комплектности/содержания координатором. Карточка попадает сюда автоматически при `FileVersion.status = CLEAN` + валидном контексте бизнес-объекта; дальше статусом управляют сервисы-владельцы процессов.
3. **Принят (`ACCEPTED`)**: Документ включён в материалы дела. Перевод выполняет внешний бизнес-сервис (`request-`, `expertise-`, `review-service`) — конвейер проверок бизнес-статусы не двигает (MZD-16 §3).
4. **Требуется замена (`REPLACEMENT_REQUIRED`)**: Документ отклонён с замечанием (`reasonCode`), ожидается новая версия файла.
5. **На согласовании (`UNDER_APPROVAL`)**: Документ проходит маршрут ЭДО (MZD-39). Требуется маршрут в статусе `IN_PROGRESS`.
6. **Утверждён (`APPROVED`)**: Маршрут завершён положительно.
7. **Направлен заявителю (`PUBLISHED`)**: Опубликован в ЛК по профилю видимости (MZD-36). Публикуется событие `DocumentPublished`.
8. **Архив (`ARCHIVED`)**: Терминальный статус. Карточка полностью заморожена для любых изменений (MZD-43).

Статусы «Доставлен / Просмотрен / Скачан» **не являются статусами карточки**: факты доставки и ознакомления фиксируются иммутабельными квитанциями `DeliveryReceipt` (`ReceiptType`: `DELIVERED`, `OPENED`, `DOWNLOADED`) — см. MZD-34.

## 2. Матрица применимости статусов по типам документов

5 типов документов (`DocumentType`, SPEC-13 §1.1): `REQUEST_MATERIAL`, `EXPERT_CARD`, `EXPERT_CONCLUSION`, `COMPARATIVE_PROTOCOL`, `SERVICE_RESOLUTION`.

| Статус | `REQUEST_MATERIAL` | `EXPERT_CARD` | `EXPERT_CONCLUSION` | `COMPARATIVE_PROTOCOL` | `SERVICE_RESOLUTION` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `DRAFT` | Да | Да | Да | Да | Да |
| `UNDER_REVIEW` | Да | Да | Да | Да | Нет (guard) |
| `ACCEPTED` | Да | Да | Да | Да | Нет |
| `REPLACEMENT_REQUIRED` | Да | Да | Да | Да | Нет (guard) |
| `UNDER_APPROVAL` | Нет | Да | Да | Да | Да |
| `APPROVED` | Нет | Да | Да | Да | Да |
| `PUBLISHED` | Нет | Нет (закрыто, SPEC-01) | Да | Нет (условно, MZD-45 E1.5) | Нет (guard) |
| `ARCHIVED` | Да | Да | Да | Да | Да |

## 3. Переходы: создание и технический цикл

**3.1. Создание карточки → `DRAFT`**
**Триггер:** запрос на создание сессии загрузки `/uploads/init`.
**Условия:** валидна структура JSON; `documentType` поддерживается; `fileSizeBytes` не превышает лимит конфигурационной матрицы для типа. Если `documentType == SERVICE_RESOLUTION`, система принудительно переопределяет профиль видимости на `visibilityProfile = INTERNAL` (инвариант SPEC-13 §2.1).

**3.2. Автопроверки внутри `DRAFT`**
После `/uploads/{uploadId}/complete` (вызов в пределах TTL сессии — 2 часа; HEAD-размер совпал с заявленным `fileSizeBytes`; SHA-256 совпал — MZD-35 §2.3) версия файла проходит цикл `UPLOADED → CHECKING → CLEAN | INFECTED | INVALID`. **Карточка всё это время остаётся в `DRAFT`** (Q-1, close-questions).

**3.3. Провал автопроверок (карантин)**
**Триггер:** версия файла переведена в `INFECTED` (вирус) или `INVALID` (подмена MIME-типа, размер, hash); публикуется `DocumentTechnicalCheckFailed`.
**Последствия:** карточка остаётся в `DRAFT`, выставляется флаг `quarantined: true`, бинарный объект в `quarantine-bucket` стирается. Из этого состояния допустима только загрузка новой версии файла.

**3.4. `DRAFT` → `UNDER_REVIEW` (автоматически, при успехе автопроверок)**
**Триггер:** версия файла перешла в `CLEAN` (файл перемещён в `main-bucket` с Object Lock, обновлён `actualFileVersionId`, опубликовано `DocumentTechnicalCheckPassed`).
**Условия:** валидный контекст бизнес-объекта (Q-1). Дальнейшее движение по бизнес-цепочке инициируют сервисы-владельцы процессов — в целевые бизнес-статусы (`ACCEPTED` и далее) конвейер карточку не переводит (MZD-16 §3).
**Исключение:** для `SERVICE_RESOLUTION` переход не выполняется — `UNDER_REVIEW` исключён её графом; карточка остаётся в `DRAFT` до запуска согласования (`DRAFT → UNDER_APPROVAL`), который заблокирован (409), пока версия не `CLEAN`.

## 4. Бизнес-переходы по графам типов (MZD-22)

* **`REQUEST_MATERIAL`:** `DRAFT → UNDER_REVIEW → (ACCEPTED | REPLACEMENT_REQUIRED) → ARCHIVED`. Из `REPLACEMENT_REQUIRED` после загрузки новой версии (`CLEAN`) — возврат в `UNDER_REVIEW`.
* **`EXPERT_CARD`:** `DRAFT → UNDER_REVIEW → ACCEPTED → UNDER_APPROVAL → APPROVED → ARCHIVED`; возврат в `REPLACEMENT_REQUIRED` — из `UNDER_REVIEW` и `UNDER_APPROVAL`.
* **`EXPERT_CONCLUSION`:** `DRAFT → UNDER_REVIEW → ACCEPTED → UNDER_APPROVAL → APPROVED → PUBLISHED → ARCHIVED`; возврат — из `UNDER_REVIEW` и `UNDER_APPROVAL`.
* **`COMPARATIVE_PROTOCOL`:** `DRAFT → UNDER_REVIEW → ACCEPTED → UNDER_APPROVAL → APPROVED → ARCHIVED`; возврат — из `UNDER_REVIEW` и `UNDER_APPROVAL`.
* **`SERVICE_RESOLUTION`:** `DRAFT → UNDER_APPROVAL → APPROVED → ARCHIVED`. Транзиты в `UNDER_REVIEW`, `ACCEPTED`, `PUBLISHED`, `REPLACEMENT_REQUIRED` запрещены безусловным guard'ом (`SecurityAccessDeniedException`).

**Общие условия бизнес-переходов:**
* Любой переход вперёд возможен, только если актуальная версия файла в статусе `CLEAN` (ФТ-07, MZD-33 §5) — иначе `409 Conflict`.
* Переход в `UNDER_APPROVAL` требует маршрут в статусе `IN_PROGRESS` (MZD-39).
* Переход в `PUBLISHED` — только из `APPROVED`, только для типов с `PUBLISHED` в графе и `visibilityProfile ≠ INTERNAL` (MZD-36).
* Переход в `ARCHIVED` — только из финального рабочего статуса графа типа (MZD-43 §2); архивация при незавершённых автопроверках файла (версия не в `CLEAN`) запрещена — `409`.

## 5. Запрещённые переходы и коды ошибок

Конвенция кодов (MZD-25, MZD-45):

| Причина отказа | Код | Пример |
| :--- | :--- | :--- |
| Жёсткий guard `SERVICE_RESOLUTION` | `403 Forbidden` (`SecurityAccessDeniedException`) | `SERVICE_RESOLUTION`: `APPROVED → PUBLISHED` |
| Нарушение матрицы: статус вне графа, пропуск стадии, обратный переход, переход из `ARCHIVED` | `422 Unprocessable Entity` | `REQUEST_MATERIAL`: `DRAFT → ACCEPTED` |
| Конфликт состояния: файл не в `CLEAN`, публикация не из `APPROVED`, квитанция по неопубликованному документу | `409 Conflict` | бизнес-переход при `FileVersion.status = CHECKING` |

Ключевые запреты:
1. **Обход проверок:** нельзя двигать карточку по бизнес-цепочке, минуя технический цикл (файл не в `CLEAN`) — `409`.
2. **Реанимация архива:** `ARCHIVED` терминален и однонаправлен — любые переходы из него `422`.
3. **Публикация внутренних типов:** `PUBLISHED` для `SERVICE_RESOLUTION` — `403` (guard); для прочих типов с исключённым по графу `PUBLISHED` — `422`.
4. Полный реестр негативных кейсов с кодами — MZD-45 (блоки E1–E4).

При любом отказе: статус не меняется, событие `DocumentStatusChanged` не публикуется, попытка фиксируется в аудите (`actor`, `action`, `reasonCode`, `correlationId`).
