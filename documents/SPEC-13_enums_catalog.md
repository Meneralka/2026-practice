# SPEC-13 · Единый справочник перечислений (enum) document-service

| Параметр | Значение |
|---|---|
| Статус | Проект. Требует сверки @koshak1030 и @ArtemKvvs |
| Источники | ТЗ-08 v1.0 (разд. 5, 6, 7); Проект ответа об интеграциях v0.1 (разд. 6, 7, 8); MZD-5, MZD-6, ФТ-перечень |
| Место в коде | `common/enums/` — общий пакет, **вне** зон `document/`, `delivery/`, `link/`, `registry/`, `routing/`, `integration/` |
| Срок | до 16.08.2026 |

## 0. Правила работы со справочником

1. **Один источник истины.** Все перечисления живут в `common/enums/`. Дублировать enum внутри своего пакета (`document/`, `routing/` и т.д.) запрещено — только импорт.
2. **Владение — общее.** Изменение любого enum = PR с двумя обязательными ревьюерами (@koshak1030 + @ArtemKvvs). Добавление константы — minor; удаление/переименование — breaking, требует изменения версии контракта (OpenAPI `/v2`, `eventVersion` major).
3. **Хранение в БД:** `VARCHAR(64)` + `CHECK`-констрейнт во Flyway-миграции. JPA — `@Enumerated(EnumType.STRING)`. **Ordinal запрещён** (перестановка констант ломает данные). Нативные PG-типы `CREATE TYPE ... AS ENUM` не используем — их сложно эволюционировать во Flyway.
4. **API и события:** наружу отдаются **латинские коды**, не русские подписи. Русские подписи из ТЗ — только для UI.
5. **Подписи для UI:** заводим `GET /internal/v1/dictionaries/{enumName}` → `[{code, label, description}]`, чтобы @NITF1S не хардкодил русские строки. Каждый enum ниже несёт `label` в самой константе.
6. **Неизвестное значение из Kafka/REST** не роняет консюмер: маппится в `UNKNOWN` там, где это помечено, и уходит в DLQ/лог с `correlationId`.

---

## 1. Бизнес-справочники (прямо из ТЗ-08)

### 1.1. DocumentType — тип документа (ТЗ-08, разд. 5) — 5 значений

| Код | Подпись (ТЗ) | Источник | Владелец содержания |
|---|---|---|---|
| `REQUEST_MATERIAL` | Материалы заявки | Заявитель | request-service |
| `EXPERT_CARD` | Экспертная карта | Эксперт | expertise-service |
| `EXPERT_CONCLUSION` | Экспертное заключение | Система / эксперт | report-service |
| `COMPARATIVE_PROTOCOL` | Сравнительный протокол | Проверка | review-service |
| `SERVICE_RESOLUTION` | Служебная резолюция | Внутренний пользователь | document-service |

> **Ограничение ИБ:** `SERVICE_RESOLUTION` — строго внутренний тип. Ни карточка, ни метаданные, ни ссылка не выдаются в cabinet-service. Проверка — в `delivery/` (ФТ-20) на уровне сервиса, не только UI.

### 1.2. DocumentStatus — статус карточки документа (ТЗ-08, разд. 5) — 8 значений

| Код | Подпись (ТЗ) | Смысл | Инициаторы перехода |
|---|---|---|---|
| `DRAFT` | Черновик | Файл загружен, не включён в завершённое действие | document-service / сервис-источник |
| `UNDER_REVIEW` | На проверке | Ручная проверка комплектности/содержания. Автопроверки файла (Tika, размер, SHA-256, ClamAV) живут внутри `DRAFT` и отражаются в `FileVersion.status` (Q-1, close-questions) | document-service, request-, expertise-, review-service |
| `ACCEPTED` | Принят | Документ включён в материалы дела | request-, expertise-, review-, document-service |
| `REPLACEMENT_REQUIRED` | Требуется замена | Отклонён с замечанием, нужна новая версия | request-, expertise-, review-, workflow-service |
| `UNDER_APPROVAL` | На согласовании | Проходит маршрут ЭДО | workflow-, report-, document-service |
| `APPROVED` | Утверждён | Маршрут завершён положительно | workflow-service |
| `PUBLISHED` | Направлен заявителю | Опубликован в ЛК по профилю видимости | report-, cabinet-, document-service |
| `ARCHIVED` | Архив | Закрыт для изменений, доступен только на просмотр | workflow-, document-, report-service |

Матрица применимости «5 типов × 8 статусов» и разрешённые переходы — приложение А. Она нужна на компиляции стейт-машины в `routing/` (ФТ-33) и на валидации `POST /documents/{id}/status`.

### 1.3. ReceiptType — тип квитанции (ТЗ-08, REQ-08-011) — 3 значения

| Код | Подпись | Кто формирует факт | Кто хранит |
|---|---|---|---|
| `DELIVERED` | Доставлен | cabinet-service (или document-service при публикации) | document-service (`DeliveryReceipt`) |
| `OPENED` | Открыт | cabinet-service | document-service |
| `DOWNLOADED` | Скачан | cabinet-service | document-service |

> Расширять не предлагаем: перечень закрыт формулировкой REQ-08-011.

---

## 2. Справочники из проекта интеграций v0.1

### 2.1. VisibilityProfile — профиль видимости (интеграции, разд. 7.1) — 3 значения

| Код | Подпись | Кому виден документ |
|---|---|---|
| `INTERNAL` | Только внутренний контур | Сотрудники по ролевой/атрибутной модели. Единственно допустимый для `SERVICE_RESOLUTION` |
| `APPLICANT_RESULT` | Результат заявителю | Заявитель видит в ЛК: `EXPERT_CONCLUSION` после публикации |
| `APPLICANT_REQUEST_MATERIAL` | Материалы заявителя | Заявитель видит собственные загруженные материалы заявки |

Инвариант (проверять в коде, а не только в ревью): `documentType == SERVICE_RESOLUTION` ⇒ `visibilityProfile == INTERNAL` и переход в `PUBLISHED` запрещён.

### 2.2. LinkType — тип связи документа с бизнес-объектом (REQ-08-005, ФТ-24) — 7 значений

| Код | Целевой объект (`targetId`) | Владелец объекта | Типичный документ |
|---|---|---|---|
| `REQUEST` | requestId / businessKey заявки | request-service | REQUEST_MATERIAL |
| `EXPERTISE_CASE` | expertiseCaseId | expertise-service | EXPERT_CARD |
| `EXPERT_CARD` | expertCardId | expertise-service | EXPERT_CARD (версия карты) |
| `REVIEW` | reviewId | review-service | COMPARATIVE_PROTOCOL |
| `PRIMARY_EXPERTISE` | expertiseCaseId первичной экспертизы | expertise-service | COMPARATIVE_PROTOCOL |
| `REPORT` | reportId | report-service | EXPERT_CONCLUSION |
| `ROUTE` | routeId | workflow-service | любой в ЭДО |

**Решение по конфликту MZD-5/MZD-6 (`relatedEntityType`):** отдельного поля `relatedEntityType` на `DocumentCard` **нет**. `LinkType` и есть тип связанной сущности; тип целевого объекта однозначно выводится из `linkType`. Связь живёт только в `DocumentLink`, кардинальность M:N (ФТ-25): один документ ↔ несколько объектов и наоборот. Уникальность связи: `UNIQUE (documentId, linkType, targetId)` — это же даёт идемпотентность создания.

### 2.3. DocumentEventType — исходящие доменные события (интеграции, разд. 6) — 16 значений

Топик один: `document.events.v1`. Ключ: `documentId` (для событий документа), `businessKey` (для процессных).

| Код события | Когда публикуется | Мин. набор (ТЗ) |
|---|---|---|
| `DocumentUploadInitiated` | Создана карточка загрузки, выдан uploadId | — |
| `DocumentUploaded` | Файл в хранилище, создана `FileVersion` | ✓ REQ-08-012 |
| `DocumentTechnicalCheckPassed` | Тех./АВ-проверка успешна | — |
| `DocumentTechnicalCheckFailed` | Файл не прошёл проверку | — |
| `DocumentLinkCreated` | Создана связь с бизнес-объектом | — |
| `DocumentVersionCreated` | Новая версия без перезаписи старой | — |
| `DocumentAccepted` | Документ принят в материалы дела | ✓ REQ-08-012 |
| `DocumentReplacementRequested` | Требуется замена, указаны замечания | — |
| `DocumentApprovalRequested` | Запуск/продолжение маршрута ЭДО | — |
| `DocumentStatusChanged` | Изменён статус карточки | — |
| `DocumentApproved` | Документ утверждён | — |
| `DocumentRejectedByApprover` | Согласующий отклонил / вернул | — |
| `DocumentPublished` | Опубликован заявителю | ✓ REQ-08-012 |
| `DocumentPublicationFailed` | Публикация не выполнена | — |
| `DocumentDeliveryReceiptRegistered` | Зафиксирована квитанция | — |
| `DocumentArchived` | Переведён в архив | — |

> ⚠ 13 из 16 — за пределами REQ-08-012 (ФТ-40, статус «требует подтверждения стейкхолдера»). До подтверждения **реализуем все 16 в outbox**, но в контрактных тестах жёстко закреплены только три из ТЗ. Публикуем не «на каждое изменение», а по явному маппингу переход→событие (ФТ-39, приложение Б).

### 2.4. Входящие события смежных сервисов (для консюмеров, ФТ-41)

Не Java-enum, а таблица подписок — коды владеют чужие команды, у нас это строки + `UNKNOWN`-fallback.

| Топик | Producer | Потребляемые eventType |
|---|---|---|
| `request.events.v1` | request-service | RequestCreated, RequestSubmitted, RequestAccepted, RequestReturnedForRevision, RequestClosed, RequiredDocumentSetChanged |
| `expertise.events.v1` | expertise-service | ExpertiseCaseCreated, ExpertCardDraftCreated, ExpertCardReadyForRegistration, ExpertCardApproved, ExpertCardReturnedForRevision, ExpertiseCaseClosed |
| `review.events.v1` | review-service | ReviewStarted, ReviewProtocolReady, ReviewProtocolApproved, ReviewProtocolRejected, ReviewClosed |
| `report.events.v1` | report-service | ReportGenerated, ReportReadyForApproval, ReportApproved, ReportPublicationRequested, ReportWithdrawn |
| `cabinet.events.v1` | cabinet-service | CabinetDocumentOpened, CabinetDocumentDownloaded, DeliveryReceiptCreated, ApplicantNotified |
| `workflow.events.v1` | workflow-service | WorkflowRouteStarted, WorkflowTaskCreated, WorkflowTaskCompleted, WorkflowRouteApproved, WorkflowRouteRejected, WorkflowRouteArchived, WorkflowStatusCommanded |

---

## 3. Выводимые справочники (нет в ТЗ, нужны для реализации)

Всё в этом разделе — реконструкция; помечать в PR как «выводимое», выносить на согласование.

### 3.1. FileVersionStatus — статус версии файла (MZD-16 / SPEC-02)

MZD-5 оставил `FileVersion.status` без enum, с пересечением с `checkResult` и `isCurrent`. Семантика разведена на три независимых поля (решение зафиксировано в MZD-16, согласовано с @ArtemKvvs):

| Поле | Тип | Смысл |
|---|---|---|
| `FileVersion.status` | `FileVersionStatus` | Стадия конвейера обработки и результат технической/АВ-проверки **этой версии**. Статуса ЭДО на `FileVersion` нет |
| `DocumentCard.actualFileVersionId` | UUID | Актуальность версии. Отдельного `isCurrent` на `FileVersion` **нет** — иначе два источника истины |
| `DocumentCard.status` | `DocumentStatus` | Статус документооборота |

`FileVersionStatus` — 6 значений (MZD-16 §1):

| Код | Смысл |
|---|---|
| `NEW` | Запись создана на фазе `/uploads/init`, бинарный файл в хранилище ещё не передан |
| `UPLOADED` | Файл загружен в S3-карантин, `/uploads/complete` выполнен, синхронные проверки пройдены |
| `CHECKING` | Асинхронные проверки выполняются (Tika / размер / SHA-256 / ClamAV) |
| `CLEAN` | Все проверки пройдены, файл перемещён в `main-bucket` |
| `INFECTED` | Обнаружено вредоносное ПО; файл изолирован и удалён (карантин, ФТ-07), `reasonCode = ANTIVIRUS_INFECTED` |
| `INVALID` | Провал технической валидации (MIME-подмена, размер, hash), `reasonCode` заполнен |

### 3.2. CheckType — вид проверки файла (REQ-08-002)

`MIME_TYPE` (Tika, whitelist) · `FILE_SIZE` (maxSize) · `ANTIVIRUS` (ClamAV/clamd) · `INTEGRITY` (SHA-256).

### 3.3. ReasonCode — коды причин

Единый enum на все контексты: отклонение файла, требование замены, отклонение согласующим, ошибка публикации, архивация. Поле `reasonCode` присутствует в `DocumentStatusChanged`, `DocumentReplacementRequested`, `DocumentTechnicalCheckFailed`, `DocumentRejectedByApprover`, `DocumentPublicationFailed`, `DocumentArchived`. Свободный текст — в `comment`, он `internalOnly` и в ЛК не уходит.

**Технические (@koshak1030, `document/`):**

| Код | Подпись |
|---|---|
| `MIME_TYPE_NOT_ALLOWED` | Формат файла не поддерживается |
| `FILE_SIZE_EXCEEDED` | Превышен максимальный размер файла |
| `FILE_CORRUPTED` | Файл повреждён или нечитаем |
| `ANTIVIRUS_INFECTED` | Обнаружено вредоносное ПО |
| `ANTIVIRUS_SCAN_FAILED` | Антивирусная проверка не выполнена |
| `HASH_MISMATCH` | Нарушена целостность файла |
| `EMPTY_FILE` | Файл пустой |

**Содержательные / комплектность (замечания координатора, эксперта, проверяющего):**

| Код | Подпись |
|---|---|
| `INCOMPLETE_DOCUMENT_SET` | Комплект документов неполный |
| `WRONG_DOCUMENT_TYPE` | Документ не соответствует требуемому типу |
| `ILLEGIBLE_CONTENT` | Документ нечитаем / плохое качество скана |
| `EXPIRED_DOCUMENT` | Истёк срок действия документа |
| `DATA_MISMATCH` | Данные документа противоречат заявке |
| `MISSING_SIGNATURE` | Отсутствует подпись / реквизит |

**Маршрут и согласование (@ArtemKvvs, `routing/`):**

| Код | Подпись |
|---|---|
| `APPROVER_REJECTED` | Отклонено согласующим |
| `RETURNED_FOR_REVISION` | Возвращено на доработку |
| `ROUTE_CANCELLED` | Маршрут отменён инициатором |
| `ROUTE_EXPIRED` | Истёк срок согласования (SLA) |

**Публикация и доставка (`delivery/`):**

| Код | Подпись |
|---|---|
| `CABINET_UNAVAILABLE` | Личный кабинет недоступен |
| `VISIBILITY_DENIED` | Публикация запрещена профилем видимости |
| `PUBLICATION_REVOKED` | Публикация отозвана |
| `APPLICANT_NOT_FOUND` | Заявитель не найден |

**Архивация и системные:**

| Код | Подпись |
|---|---|
| `SUPERSEDED_BY_NEW_VERSION` | Заменён новой версией |
| `BUSINESS_PROCESS_CLOSED` | Заявка/дело закрыто |
| `RETENTION_POLICY` | Регламентное хранение |
| `MANUAL_BY_OPERATOR` | Решение оператора |
| `SYSTEM_ERROR` | Техническая ошибка (детали в логах по correlationId) |

### 3.4. SecureLinkAction — действие защищённой ссылки (REQ-08-009)

`VIEW` (предпросмотр в браузере, REQ-08-008) · `DOWNLOAD` (скачивание). TTL — параметр, не enum.

### 3.5. RouteStatus — статус маршрута ЭДО (REQ-08-007, `routing/`)

`NOT_STARTED` · `IN_PROGRESS` · `APPROVED` · `REJECTED` · `CANCELLED` · `EXPIRED`.

> Не путать с `DocumentStatus`: маршрут — сущность `document-service` (`DocumentRoute`), но глобальная оркестрация ЭДО принадлежит workflow-service. Статус документа двигает **только** `document/` по протоколу ФТ-34.

### 3.6. RouteTaskStatus — статус задачи согласования

`PENDING` · `IN_PROGRESS` · `COMPLETED` · `EXPIRED` · `CANCELLED`.

### 3.7. RouteDecision — решение согласующего

`APPROVE` (согласовано) · `REJECT` (отклонено) · `RETURN_FOR_REVISION` (на доработку). Маппинг на статус документа: `APPROVE` (последний шаг) → `APPROVED`; `REJECT`/`RETURN_FOR_REVISION` → `REPLACEMENT_REQUIRED` + соответствующий `reasonCode`.

### 3.8. RegistryCode — регистрационные журналы (REQ-08-006, `registry/`)

Один журнал на тип документа, номер уникален в пределах (journal, год):

| Код | Журнал | Предлагаемый формат номера |
|---|---|---|
| `REQUEST_MATERIAL_JOURNAL` | Журнал материалов заявок | `RM-2026-000123` |
| `EXPERT_CARD_JOURNAL` | Журнал экспертных карт | `EC-2026-000123` |
| `CONCLUSION_JOURNAL` | Журнал экспертных заключений | `EZ-2026-000123` |
| `PROTOCOL_JOURNAL` | Журнал сравнительных протоколов | `SP-2026-000123` |
| `RESOLUTION_JOURNAL` | Журнал служебных резолюций | `SR-2026-000123` |

> Формат номера и безразрывность (gapless) — **открытый вопрос ФТ-29**, ждём стейкхолдера. `SELECT FOR UPDATE` даёт уникальность в обоих сценариях; gapless дополнительно запрещает откат номера при rollback транзакции.

### 3.9. ActorType — тип инициатора действия (аудит, ФТ-45)

`APPLICANT` · `COORDINATOR` · `EXPERT` · `MANAGER` · `ADMIN` · `SERVICE` (межсервисный вызов по JWT client credentials). Роли — из разд. 3 ТЗ.

### 3.10. ConfidentialityLevel — уровень конфиденциальности

`PUBLIC` · `INTERNAL` · `RESTRICTED`. Приходит из expertise-service в `registerExpertCardDocument`; влияет на выдачу ссылок и попадание полей в ЛК (маркировка `internalOnly` / `restricted` в схемах).

### 3.11. OutboxStatus — технический, `integration/`

`NEW` · `IN_PROGRESS` · `SENT` · `FAILED` · `DEAD` (ушло в DLQ после исчерпания retry). Наружу не отдаётся, в API/событиях отсутствует.

---

## 4. Java-код (`common/enums/`)

Общий шаблон — код + русская подпись, чтобы словарный endpoint строился из самого enum:

```java
package ru.practice.documentservice.common.enums;

public enum DocumentType {
    REQUEST_MATERIAL("Материалы заявки"),
    EXPERT_CARD("Экспертная карта"),
    EXPERT_CONCLUSION("Экспертное заключение"),
    COMPARATIVE_PROTOCOL("Сравнительный протокол"),
    SERVICE_RESOLUTION("Служебная резолюция");

    private final String label;

    DocumentType(String label) { this.label = label; }

    public String getLabel() { return label; }

    /** Внутренний документ: не публикуется заявителю ни при каких условиях. */
    public boolean isInternalOnly() { return this == SERVICE_RESOLUTION; }
}
```

```java
public enum DocumentStatus {
    DRAFT("Черновик"),
    UNDER_REVIEW("На проверке"),
    ACCEPTED("Принят"),
    REPLACEMENT_REQUIRED("Требуется замена"),
    UNDER_APPROVAL("На согласовании"),
    APPROVED("Утверждён"),
    PUBLISHED("Направлен заявителю"),
    ARCHIVED("Архив");

    private final String label;
    DocumentStatus(String label) { this.label = label; }
    public String getLabel() { return label; }

    /** Терминальный статус: изменения запрещены. */
    public boolean isTerminal() { return this == ARCHIVED; }
}
```

Остальные по той же схеме: `VisibilityProfile`, `LinkType`, `ReceiptType`, `ReasonCode`, `FileVersionStatus`, `CheckType`, `SecureLinkAction`, `RouteStatus`, `RouteTaskStatus`, `RouteDecision`, `RegistryCode`, `ActorType`, `ConfidentialityLevel`, `OutboxStatus`, `DocumentEventType`.

Применимость статусов по типам и переходы **не хардкодим в enum** — это конфигурация стейт-машины в `routing/` (`StatusTransitionPolicy`), таблицы приложений А и Б. Enum отвечает только за перечень значений.

**Flyway (пример):**

```sql
ALTER TABLE document_card
    ADD CONSTRAINT chk_document_status CHECK (
        status IN ('DRAFT','UNDER_REVIEW','ACCEPTED','REPLACEMENT_REQUIRED',
                   'UNDER_APPROVAL','APPROVED','PUBLISHED','ARCHIVED')
    );
```

Тест-страховка (обязателен, иначе enum и БД разъедутся): параметризованный тест, который сверяет `values()` каждого enum с `CHECK`-констрейнтом в Testcontainers-Postgres.

---

## Приложение А. Матрица применимости статусов (5 типов × 8 статусов)

✓ применим · — не применим · ? открытый вопрос

| Статус | Материалы заявки | Экспертная карта | Экспертное заключение | Сравнит. протокол | Служебная резолюция |
|---|:--:|:--:|:--:|:--:|:--:|
| DRAFT | ✓ | ✓ | ✓ | ✓ | ✓ |
| UNDER_REVIEW | ✓ | ✓ | ✓ | ✓ | — |
| ACCEPTED | ✓ | ✓ | ✓ | ✓ | — |
| REPLACEMENT_REQUIRED | ✓ | ✓ | ✓ | ✓ | — |
| UNDER_APPROVAL | — | ✓ | ✓ | ✓ | ✓ |
| APPROVED | — | ✓ | ✓ | ✓ | ✓ |
| PUBLISHED | — | — | ✓ | — | — |
| ARCHIVED | ✓ | ✓ | ✓ | ✓ | ✓ |

Бывшие «?» закрыты решениями MZD-22: `ACCEPTED` для заключения — обязательный шаг единого шаблона переходов (MZD-22 §2.3); `UNDER_REVIEW` для резолюции — исключён guard'ом, техническая/АВ-проверка файла идёт на уровне `FileVersion.status` без смены статуса карточки (MZD-22 §2.5, MZD-16 §3); `PUBLISHED` для экспертной карты — исключён из графа окончательно (MZD-22 §2.2, SPEC-01).

## Приложение Б. Маппинг «переход статуса → событие» (ФТ-39)

| Переход / факт | Событие |
|---|---|
| создана карточка загрузки | `DocumentUploadInitiated` |
| файл в хранилище, создана FileVersion | `DocumentUploaded` (+ `DocumentVersionCreated`, если versionNumber > 1) |
| `FileVersion.status` → CLEAN | `DocumentTechnicalCheckPassed` |
| `FileVersion.status` → INFECTED / INVALID | `DocumentTechnicalCheckFailed` |
| создан DocumentLink | `DocumentLinkCreated` |
| → ACCEPTED | `DocumentAccepted` |
| → REPLACEMENT_REQUIRED | `DocumentReplacementRequested` (+ `DocumentRejectedByApprover`, если инициатор — согласующий) |
| → UNDER_APPROVAL | `DocumentApprovalRequested` |
| → APPROVED | `DocumentApproved` |
| → PUBLISHED | `DocumentPublished` |
| публикация не выполнена | `DocumentPublicationFailed` |
| зарегистрирована квитанция | `DocumentDeliveryReceiptRegistered` |
| → ARCHIVED | `DocumentArchived` |
| **любой** переход статуса | `DocumentStatusChanged` (единственное «на каждый переход») |

## Приложение В. Чек-лист сверки (Definition of Done SPEC-13)

- [ ] @koshak1030: `DocumentType`, `DocumentStatus`, `FileVersionStatus`, `CheckType`, `SecureLinkAction`, `VisibilityProfile`, `ReceiptType`, технические и delivery-`ReasonCode` — расхождений с `document/`, `delivery/` нет
- [ ] @ArtemKvvs: `LinkType`, `RegistryCode`, `RouteStatus`, `RouteTaskStatus`, `RouteDecision`, `DocumentEventType`, `OutboxStatus`, routing-`ReasonCode` — расхождений с `link/`, `registry/`, `routing/`, `integration/` нет
- [ ] Оба: `relatedEntityType` на `DocumentCard` не заводим, тип связи = `LinkType` в `DocumentLink`
- [ ] Оба: `FileVersion.status` — технический статус конвейера (`FileVersionStatus`, MZD-16); статуса ЭДО и `isCurrent` на версии нет
- [ ] @Hqhzx: тест «enum ↔ CHECK-констрейнт» в контуре Testcontainers
- [ ] @NITF1S: подписи берутся из `/dictionaries`, русские строки не хардкодятся
- [ ] Тимлид: открытые вопросы (gapless-нумерация, «?» в приложении А, каталог событий ФТ-40) вынесены стейкхолдеру
