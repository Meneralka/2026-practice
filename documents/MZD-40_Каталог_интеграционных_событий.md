# MZD-40: Каталог интеграционных событий (Envelope Pattern)

Все события упаковываются в единый транзитный конверт строго в соответствии со SPEC-14 и MZD-21 и публикуются в топик `document.events.v1`. Реестр событий приведен к SPEC-13 §2.3 (16 значений `DocumentEventType`) и маппингу «переход → событие» из приложения Б SPEC-13.

## 1. Структура конверта (Event Envelope)
Согласно REQ-08-012, наличие сквозных идентификаторов (`correlationId`) строго обязательно для обеспечения трассировки.

```json
{
  "eventId": "UUID",
  "eventVersion": "1.0.0",
  "eventType": "String",
  "occurredAt": "ISO-8601",
  "producer": "document-service",
  "causationId": "UUID",
  "correlationId": "UUID",
  "businessKey": "UUID",
  "payload": {}
}
```

**Ключ партиционирования:** `documentId` для событий документа, `businessKey` для процессных.

## 2. Инварианты payload (MZD-46)

1. **Только метаданные и идентификаторы.** Поля типа `bytes` / `base64` / `content` / `fileData` запрещены схемой: бинарное содержимое файлов через брокер не передается.
2. **Без прямых ссылок.** `secureLinkRef` — **идентификатор** защищенной ссылки, а не presigned URL. Получатель обменивает его на временный URL отдельным REST-вызовом. Пути объектного хранилища (`s3://…`) в payload не включаются — вместо них `fileVersionId`.
3. `reasonCode` (SPEC-13 §3.3) присутствует в `DocumentStatusChanged`, `DocumentReplacementRequested`, `DocumentTechnicalCheckFailed`, `DocumentRejectedByApprover`, `DocumentPublicationFailed`, `DocumentArchived`. Свободный текст — в `comment` (`internalOnly`, в ЛК не уходит).

## 3. Реестр событий (16, SPEC-13 §2.3)

Отметка ✓ — событие входит в минимальный набор ТЗ (REQ-08-012); остальные реализуются в outbox, но контрактными тестами жестко закреплены только три из ТЗ (ФТ-40).

| Событие (eventType) | Условие публикации | Мин. payload | Основные потребители |
| :--- | :--- | :--- | :--- |
| `DocumentUploadInitiated` | Создана карточка загрузки, выдан `uploadId` | documentId, uploadId, documentType | аудит |
| `DocumentUploaded` ✓ | Файл в хранилище, создана `FileVersion` | documentId, fileVersionId, fileName, mimeType, sha256 | request-service, review-service |
| `DocumentTechnicalCheckPassed` | `FileVersion.status` → `CLEAN` | documentId, fileVersionId | сервис-владелец процесса |
| `DocumentTechnicalCheckFailed` | `FileVersion.status` → `INFECTED` / `INVALID` | documentId, fileVersionId, reasonCode | сервис-источник, cabinet-service |
| `DocumentLinkCreated` | Создана связь с бизнес-объектом | documentId, targetId, linkType | request-service |
| `DocumentVersionCreated` | Новая версия без перезаписи старой (versionNumber > 1) | documentId, fileVersionId, versionNumber | сервис-владелец процесса |
| `DocumentAccepted` ✓ | Переход в `ACCEPTED` | documentId, regNumber, acceptedAt | request-service, workflow-service |
| `DocumentReplacementRequested` | Переход в `REPLACEMENT_REQUIRED` | documentId, reasonCode, stepCode | review-service, cabinet-service |
| `DocumentApprovalRequested` | Переход в `UNDER_APPROVAL` (запуск/продолжение маршрута ЭДО) | documentId, routeId | workflow-service |
| `DocumentStatusChanged` | Любой переход статуса карточки | documentId, oldStatus, newStatus, reasonCode | мониторинг, аудит |
| `DocumentApproved` | Переход в `APPROVED` | documentId, regNumber, approvedAt | expertise-service, report-service |
| `DocumentRejectedByApprover` | Согласующий отклонил / вернул на доработку | documentId, routeId, taskId, reasonCode | workflow-service |
| `DocumentPublished` ✓ | Переход в `PUBLISHED` | documentId, regNumber, applicantId, visibilityProfile, secureLinkRef, publishedAt | cabinet-service, report-service |
| `DocumentPublicationFailed` | Сбой при доставке документа в ЛК | documentId, reasonCode | report-service, monitoring-service |
| `DocumentDeliveryReceiptRegistered` | Зафиксирована квитанция доставки (MZD-34) | documentId, recipientId, receiptType, registeredAt | report-service |
| `DocumentArchived` | Переход в `ARCHIVED` | documentId, reasonCode | все подписчики |

> Для документов типа `SERVICE_RESOLUTION` событие `DocumentPublished` не публикуется никогда (жесткий guard, MZD-22 §2.5): полный цикл резолюции — `DRAFT → UNDER_APPROVAL → APPROVED → ARCHIVED`.
