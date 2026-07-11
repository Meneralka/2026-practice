# MZD-17 / SPEC-03: Входные и выходные интерфейсы (I/O) контура загрузки и доставки документов

## 1. Спецификация заголовков (Трассировка и Идемпотентность)

Для всех **мутирующих запросов** (`POST`, `PUT`, `DELETE`) обязательны следующие HTTP-заголовки. Без них вызовы отклоняются с кодом `400 Bad Request`.

*   `X-Correlation-Id` (UUID, Обязательное): Сквозной идентификатор транзакции для трассировки.
*   `X-Idempotency-Key` (UUID, Обязательное): Уникальный ключ операции для дедупликации на стороне `document-service` (защита от повторных сетевых вызовов при ретраях и сборка Outbox).

---

## 2. Спецификация REST API операций (Контур UI и Сервисы)

### 2.1. Инициация двухфазной загрузки (`POST /internal/v1/documents/uploads/init`)
Регистрирует черновик карточки документа и резервирует временный путь в изолированном карантинном бакете хранилища RustFS.

*   **Вход (Request Payload):**
```json
{
  "businessKey": "REQUEST-2026-000123",
  "documentType": "REQUEST_MATERIAL",
  "fileName": "zayavka_initial.pdf",
  "mimeType": "application/pdf",
  "fileSizeBytes": 1048576,
  "visibilityProfile": "APPLICANT_RESULT"
}
```

*   **Выход (Response Payload - 201 Created):**
```json
{
  "uploadId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "quarantineStorageTarget": "s3://quarantine-bucket/2026/07/uploads/7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f.tmp",
  "maxSize": 52428800,
  "allowedMimeTypes": ["application/pdf", "image/jpeg"]
}
```

### 2.2. Завершение загрузки (`POST /internal/v1/documents/uploads/{uploadId}/complete`)
Вызывается после отправки бинарного тела в S3-карантин. Переводит файл в статус UPLOADED и триггерит конвейер проверок.

*   **Вход (Request Payload):**
```json
{
  "fileHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
}
```

*   **Выход (Response Payload - 200 OK):**
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "fileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "status": "Черновик"
}
```

### 2.3. Получение данных карточки документа (`GET /internal/v1/documents/{documentId}`)

*   **Выход (Response Payload - 200 OK):**
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "businessKey": "REQUEST-2026-000123",
  "documentType": "REQUEST_MATERIAL",
  "status": "На проверке",
  "actualFileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "visibilityProfile": "APPLICANT_RESULT",
  "quarantined": false
}
```

### 2.4. Получение списка версий файла (`GET /internal/v1/documents/{documentId}/versions`)

*   **Выход (Response Payload - 200 OK):**
```json
[
  {
    "fileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
    "versionNumber": 1,
    "fileName": "zayavka_initial.pdf",
    "mimeType": "application/pdf",
    "size": 1048576,
    "status": "CLEAN",
    "createdAt": "2026-07-11T10:00:00Z"
  }
]
```

### 2.5. Получение защищенной ссылки (`POST /internal/v1/documents/{documentId}/secure-links`)
Запрашивает временный URL для скачивания/просмотра. Значение TTL жестко рассчитывается сервером на базе бизнес-правил домена (15 мин внутренние АРМ, 30 мин ЛК). Параметр `clientHintTtlSeconds` является рекомендательным и ограничивается сервером через верхний `clamp`.

*   **Вход (Request Payload):**
```json
{
  "action": "DOWNLOAD",
  "clientHintTtlSeconds": 7200
}
```

*   **Выход (Response Payload - 200 OK):**
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "secureLinkRef": "[https://s3.rustfs.local/main-bucket/2026/07/4a2b3c4d.pdf?X-Amz-Signature=](https://s3.rustfs.local/main-bucket/2026/07/4a2b3c4d.pdf?X-Amz-Signature=)...",
  "expiresAt": "2026-07-11T12:31:32Z"
}
```

### 2.6. Команда публикации документа (`POST /internal/v1/documents/{documentId}/publish`)
Вызывается смежными сервисами. Входной `visibilityProfile` используется только для сквозной сверки бизнес-логики с атрибутом карточки. Несовпадение вызывает `409 Conflict`.

*   **Вход (Request Payload):**
```json
{
  "applicantId": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "visibilityProfile": "APPLICANT_RESULT"
}
```

*   **Выход (Response Payload - 200 OK):**
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "status": "Направлен заявителю",
  "publishedAt": "2026-07-11T12:01:32Z"
}
```

### 2.7. Архивирование документа (`POST /internal/v1/documents/{documentId}/archive`)
Переводит карточку в финальный статус и блокирует любые последующие изменения версий файлов.

*   **Выход (Response Payload - 200 OK):**
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "status": "Архив"
}
```

### 2.8. Синхронная регистрация факта доставки (`POST /internal/v1/documents/{documentId}/delivery-receipts`)

*   **Вход (Request Payload):**
```json
{
  "receiptType": "DOWNLOADED",
  "userId": "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "ipHash": "8f9b...a1b2",
  "userAgentHash": "fe3a...45bc"
}
```

*   **Выход (Response Payload - 201 Created):**
```json
{
  "receiptId": "bc12de34-5678-abcd-ef90-1234567890ab",
  "registeredAt": "2026-07-11T12:01:32Z"
}
```

## 3. Топология хранилища RustFS и жизненный цикл файла
### 1. Изоляция в Карантине: В рамках `uploads/init` файл попадает в `quarantine-bucket`. Доступ к чтению объекта имеет только внутренний конвейер асинхронных проверок безопасности. Генерировать presigned-ссылки для пользователей из этого бакета запрещено.
### 2. Атомарный перенос при CLEAN: Если файлы признаны чистыми (`CLEAN`), `document-service` запрашивает у API RustFS операцию `CopyObject` + `DeleteObject` из `quarantine-bucket` в целевой `main-bucket` с активацией Object Lock и политик версионирования S3. Ссылка на новый объект фиксируется в `DocumentCard.actualFileVersionId`.
### 3. Очистка при заражении: При обнаружении угроз (`INFECTED`/`INVALID`), бинарный файл удаляется из карантина автоматически. В БД карточка получает флаг `quarantined: true`, а в основное хранилище данные не перемещаются

## 4. Спецификация событий Kafka (Топик `document.events.v1`)
Каждое событие оборачивается в инфраструктурный конверт системы (содержащий `eventId`, `timestamp`, `correlationId`).

### 4.1. `DocumentUploaded`
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "fileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "versionNumber": 1,
  "fileName": "zayavka_initial.pdf",
  "mimeType": "application/pdf",
  "size": 1048576,
  "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "quarantineStorageRef": "s3://quarantine-bucket/2026/07/uploads/7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f.tmp"
}
```

### 4.2. `DocumentTechnicalCheckPassed`
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "fileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "checkedAt": "2026-07-11T12:02:00Z",
  "permanentStorageRef": "s3://main-bucket/2026/07/4a2b3c4d.pdf",
  "checkDescription": "{\"clamAV\": \"CLEAN\", \"tika\": \"VALID\"}"
}
```

### 4.3. `DocumentTechnicalCheckFailed`
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "fileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "reasonCode": "ANTIVIRUS_POSITIVE",
  "reasonText": "Virus Eicar-Test-Signature detected.",
  "failedAt": "2026-07-11T12:02:05Z"
}
```

### 4.4. `DocumentVersionCreated`
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "fileVersionId": "8b9c0d1e-2f3a-4b5c-6d7e-5a6b7c8d9e0f",
  "versionNumber": 2,
  "previousFileVersionId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f",
  "createdAt": "2026-07-11T12:05:00Z"
}
```

### 4.5. `DocumentPublished`
```json
{
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "applicantId": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "publishedAt": "2026-07-11T12:01:32Z"
}
```

### 4.6. `DocumentDeliveryReceiptRegistered` (Асинхронные события ЛК, ФТ-22)
Потребляется сервисом из топика интеграции клик-стрима для асинхронного трекинга. Содержит дедупликационный `receiptId`.
```json
{
  "receiptId": "bc12de34-5678-abcd-ef90-1234567890ab",
  "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "receiptType": "DOWNLOADED",
  "userId": "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
  "occurredAt": "2026-07-11T12:01:30Z"
}
```

## 5. Спецификация кодов ответов и ошибок с примерами
Каждая структура ответа об ошибке возвращает стандартный контракт `{"errorCode": "строка", "message": "текст", "timestamp": "ISO", "details": {}}`.

### 5.1. Пример для эндпоинта `/uploads/init`
*   **`400 Bad Request` (`MISSING_MANDATORY_HEADERS`)**
```json
{ "errorCode": "MISSING_MANDATORY_HEADERS", "message": "Заголовок X-Idempotency-Key обязателен для выполнения запроса.", "timestamp": "2026-07-11T12:01:32Z", "details": {} }
```

*   **`503 Service Unavailable` (`STORAGE_UNAVAILABLE`) — отказ RustFS на этапе выделения места.**
```json
{ "errorCode": "STORAGE_UNAVAILABLE", "message": "Объектное хранилище временно недоступно.", "timestamp": "2026-07-11T12:01:32Z", "details": { "component": "RustFS" } }
```

### 5.2. Пример для эндпоинта `/uploads/{uploadId}/complete`
*   **`404 Not Found` (`UPLOAD_SESSION_NOT_FOUND`)**
```json
{ "errorCode": "UPLOAD_SESSION_NOT_FOUND", "message": "Указанная сессия загрузки не найдена или истекла по TTL.", "timestamp": "2026-07-11T12:01:32Z", "details": { "uploadId": "7a8b9c0d-1e2f-3a4b-5c6d-4a2b3c4d5e6f" } }
```

### 5.3. Пример для эндпоинта `GET /documents/{documentId}`
*   **`404 Not Found` (`DOCUMENT_NOT_FOUND`)**
```json
{ "errorCode": "DOCUMENT_NOT_FOUND", "message": "Карточка документа не найдена.", "timestamp": "2026-07-11T12:01:32Z", "details": { "documentId": "4a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d" } }
```

### 5.4. Пример для эндпоинта `GET /documents/{documentId}/versions`
*   **`401 Unauthorized` (`INVALID_CREDENTIALS`)**
```json
{ "errorCode": "INVALID_CREDENTIALS", "message": "Токен авторизации недействителен.", "timestamp": "2026-07-11T12:01:32Z", "details": {} }
```

### 5.5. Пример для эндпоинта `/secure-links`
*   **`403 Forbidden` (`ACCESS_DENIED`) — Попытка доступа к `INTERNAL` файлу из публичной зоны.**
```json
{ "errorCode": "ACCESS_DENIED", "message": "Недостаточно прав для генерации ссылки с указанным профилем видимости.", "timestamp": "2026-07-11T12:01:32Z", "details": { "required": "INTERNAL" } }
```

*   **`422 Unprocessable Entity` (`FILE_QUARANTINED`) — Попытка скачать зараженный файл.**
```json
{ "errorCode": "FILE_QUARANTINED", "message": "Запрошенная версия файла находится в карантине из-за провала техпроверок.", "timestamp": "2026-07-11T12:01:32Z", "details": { "status": "INFECTED" } }
```

### 5.6. Пример для эндпоинта `/publish`
*   **`409 Conflict` (`VISIBILITY_PROFILE_MISMATCH`) — Несовпадение переданного профиля с атрибутом карточки.**
```json
{ "errorCode": "VISIBILITY_PROFILE_MISMATCH", "message": "Переданный профиль видимости противоречит значению в карточке документа.", "timestamp": "2026-07-11T12:01:32Z", "details": { "cardProfile": "INTERNAL", "requestedProfile": "APPLICANT_RESULT" } }
```

### 5.7. Пример для эндпоинта `/archive`
*   **`409 Conflict` (`INVALID_STATE_TRANSITION`) — Попытка архивировать документ, который уже находится в архивном или некорректном статусе.**
```json
{ "errorCode": "INVALID_STATE_TRANSITION", "message": "Невозможно перевести документ в Архив из текущего состояния.", "timestamp": "2026-07-11T12:01:32Z", "details": { "currentStatus": "Архив" } }
```