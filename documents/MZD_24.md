## 10. Инфра-зависимости и поведение при отказах

### 10.1. Модель обмена (уточнена по ответу стейкхолдера)

Подтверждена **смешанная модель**:
- **REST** — команды, чтение текущего состояния, валидация контекста, выдача защищённых ссылок, идемпотентная регистрация документов (нужен немедленный результат).
- **Kafka** — доменные события, уведомления смежных сервисов о фактах, изменение статусов, асинхронное подтверждение доставки, eventual consistency.
- **Файлы** передаются между сервисами **только ссылкой** (`objectStorageRef` / `presignedUrl` / `storageKeyHash`) и метаданными — не телом межсервисного HTTP-запроса и не сообщением Kafka. Тело файла идёт только при загрузке клиентом/сервисом-источником в `document-service` через upload-endpoint.
- **Прямой доступ к чужой БД запрещён** в обе стороны.

### 10.2. Gateway

Точка входа — **nginx** (reverse proxy): маршрутизация, терминирование внешнего HTTPS, проверка JWT на границе. JWT проверяется повторно в самом сервисе (Spring Security, OAuth2 Resource Server) — defense in depth.

Отдельно: документ (разд. 12.1) закрепляет за платформенной/DevOps-командой владение **API Gateway, Schema Registry и общими политиками retry/DLQ**. Это означает, что помимо nginx в контуре появляется **Schema Registry** как самостоятельный инфраструктурный компонент (см. 10.3).

### 10.3. Kafka-топики, envelope, ключи

**Топология (по ответу стейкхолдера — конфликтует с ранее принятым «одна тема на всё»):**

| Producer | Topic |
|---|---|
| document-service | `document.events.v1` |
| request-service | `request.events.v1` |
| expertise-service | `expertise.events.v1` |
| review-service | `review.events.v1` |
| report-service | `report.events.v1` |
| cabinet-service | `cabinet.events.v1` |
| workflow-service | `workflow.events.v1` |

**Единый envelope** для всех событий: `eventId`, `eventType`, `eventVersion`, `occurredAt`, `producer`, `correlationId`, `causationId`, `businessKey`, `payload`.

**Ключ партиционирования:** `businessKey` для событий процесса, `documentId` для событий конкретного документа; для событий публикации допускается `applicantId`. **Порядок** гарантируется в пределах одного ключа; глобальный порядок не гарантируется и не должен использоваться бизнес-логикой.

**Идемпотентность consumer'а:** обязательна — consumer хранит обработанные `eventId` и не повторяет действие при дубле. **Binary content в событиях запрещён** — только ссылки (`objectStorageRef` / `secureLinkRef` / `fileVersionId`).

**Схемы:** AsyncAPI + JSON Schema/Avro в **Schema Registry**; совместимые изменения — добавление optional-полей, breaking — новая major-версия и период миграции.

### 10.4. Объектное хранилище (RustFS) и техпроверка

- **Хранилище:** RustFS, доступ по **протоколу S3** (AWS SDK for Java v2). Presigned URLs (REQ-009), versioning (REQ-004), object lock.
- Обмен документами — **ссылками** (`objectStorageRef` / `secureLinkRef`), тело файла — только на upload в `document-service`.
- **Новая зависимость:** конвейер загрузки включает **техническую/антивирусную проверку** файла (события `DocumentTechnicalCheckPassed` / `DocumentTechnicalCheckFailed`). До прохождения проверки файл держится в **карантинном** состоянии (статус «Черновик», без установления связи и статуса «На проверке»).
- Схема хранилища (bucket/prefix policy, retention, hash, quarantine, secure-link TTL) выносится в проектную документацию (разд. 12 ответа).

> ⚠️ RustFS vs MinIO стейкхолдер-документом **не разрешён** (используется абстрактный `s3://…`). Развилка сохраняется.

### 10.5. Управление секретами

| Этап | Решение | Статус |
|---|---|---|
| Текущий (dev / изолированный контур) | `.env`-файлы | Действует сейчас |
| Целевой (прод) | Secret Manager | Планируется; продукт не выбран |

Ответ стейкхолдера секретов напрямую не касается — позиция без изменений: `.env` не является прод-решением (нет ротации/защиты), переход на Secret Manager — целевое состояние, выбор продукта открыт.

### 10.6. Целевые настройки отказоустойчивости (по разд. 10 ответа)

Значения — **целевые дефолты**; для критичных операций допускается отдельная настройка, но она должна быть отражена в OpenAPI/AsyncAPI и эксплуатационной документации.

**REST (синхронные вызовы ко всем шести сервисам):**

| Параметр | Значение |
|---|---|
| Connect timeout | 2 c |
| Response timeout | 5 c (генерация защищённой ссылки — до 3 c) |
| Тяжёлые операции | Синхронный вызов запрещён — фон/событие |
| Retry | GET/HEAD и идемпотентные PUT/POST с `idempotencyKey` — до 3 попыток, backoff 200 мс / 1 c / 3 c |
| Неидемпотентные POST без `idempotencyKey` | Не ретраятся |
| Circuit breaker | Открытие при ≥50% ошибок на окне ≥20 вызовов или серии timeout; half-open — 3 пробных запроса |
| Fallback | Только локальная read-model/кэш на чтение; смена статуса по устаревшим данным запрещена |

**Kafka:**

| Параметр | Значение |
|---|---|
| Consumer retry | **5 попыток**, экспоненциальная задержка; для временных ошибок — delayed-retry-топик |
| DLQ | После исчерпания retry; содержит исходное сообщение, `errorClass`, `errorMessage`, `stackTraceHash`, `consumer`, `failedAt`, `retryCount`, `correlationId` |
| Хранение DLQ | ≥ 14 календарных дней (или срок по регламенту эксплуатации) |
| Replay | Ручной |
| Outbox | Обязателен; потеря события при успешной транзакции изменения документа недопустима |

**Пользователю** показывается функциональное сообщение без технических деталей; детали — в логах/трассировке по `correlationId`.

### 10.7. Поведение по сервисам при недоступности (разд. 10.1 ответа)

| Сервис | Поведение |
|---|---|
| request-service | Критичная зависимость. Без валидации заявки файл сохраняется в карантинном «Черновике», связь с заявкой и статус «На проверке» не ставятся до восстановления |
| expertise-service | Без подтверждения `expertiseCaseId` карта загружается, но не принимается |
| review-service | Блокирует регистрацию протокола; повтор по `idempotencyKey` |
| report-service | Блокирует публикацию/согласование; повтор публикации асинхронно через outbox/job |
| cabinet-service | Не должна вести к потере утверждённого документа; `DocumentPublished` может быть отложен, ссылка выдаётся после восстановления |
| workflow-service | Блокирует новые маршруты и команды смены статуса; без `routeId`/подтверждённой команды статус «На согласовании» не ставится |

### 10.8. Обсервабилити

| Столп | Инструмент | Применение |
|---|---|---|
| Логи | Loki / ELK | gateway, сервис, consumer'ы |
| Метрики | Micrometer + Prometheus | HTTP-latency, retry/CB-состояния, лаг consumer'ов, ошибки publish, DLQ-счётчики |
| Трассировка | OpenTelemetry / Jaeger | Сквозная по `correlationId`/`causationId`, включая переход REST → Kafka → consumer |
| Health / Readiness | Spring Boot Actuator | Готовность + коннект к PostgreSQL / Kafka / RustFS / Schema Registry |

`correlationId` и `causationId` из envelope пробрасываются в логи и трейсы consumer'ов для связи асинхронной обработки с исходным запросом.

### 10.9. Матрица SPEC-06 (заполнена по ответу стейкхолдера)

Формат `service → direction → initiator → REST/event → owner → contract`. Значения помечены **`ПОДТВ.(проект)`** — подтверждено проектом ответа стейкхолдера v0.1, финальная фиксация после рабочей группы. Владение по документу: API владеет предоставляющий сервис, событие — сервис-продюсер.

| service | direction | initiator | REST / event | owner | contract |
|---|---|---|---|---|---|
| request-service | вход/выход | Обе стороны (doc-svc валидирует заявку; request-svc запрашивает список/комплектность) | REST + Kafka | каждая сторона — своё API/события | OpenAPI `contracts/request-service` + AsyncAPI `request.events.v1` / `document.events.v1` |
| expertise-service | вход/выход | В осн. expertise-svc (регистрация карт); doc-svc публикует статусы | REST + Kafka | каждая сторона | OpenAPI `contracts/expertise-service` + AsyncAPI `expertise.events.v1` / `document.events.v1` |
| review-service | вход/выход | review-svc (регистрация протокола); doc-svc публикует статус/версию | REST + Kafka | каждая сторона | OpenAPI `contracts/review-service` + AsyncAPI `review.events.v1` / `document.events.v1` |
| report-service | вход/выход | report-svc (передача заключения); workflow-svc может инициировать согласование; doc-svc публикует публикацию | REST + Kafka | каждая сторона | OpenAPI `contracts/report-service` + AsyncAPI `report.events.v1` / `document.events.v1` |
| cabinet-service | вход/выход | cabinet-svc (запрос опубликованных, факты просмотра/скачивания) | REST + Kafka/REST (delivery-receipt) | каждая сторона | OpenAPI `contracts/cabinet-service` + AsyncAPI `cabinet.events.v1` / `document.events.v1` |
| workflow-service | вход/выход | workflow-svc (команды маршрута); doc-svc публикует факты смены статуса | REST + Kafka | каждая сторона | OpenAPI `contracts/workflow-service` + AsyncAPI `workflow.events.v1` / `document.events.v1` |

Инфраструктурная сверка с DevOps (**SPEC-10**) по-прежнему не проведена — числится за платформенной командой (владелец Gateway / Schema Registry / общих политик retry/DLQ).

