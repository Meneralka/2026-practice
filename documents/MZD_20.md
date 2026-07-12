# MZD-20: Матрица интеграционных зависимостей (v5)

Связи декомпозированы по атомарным операциям для контрактных тестов и генерации стабов. Правило владения: для синхронного API владелец — сервер; для асинхронных событий владелец — продюсер.

> **СТАТУС:** Проект содержит неподтвержденные параметры взаимодействия с бизнесом и находится на согласовании в рамках SPEC-16.

## Интеграционная матрица взаимодействия

| Смежный сервис | Направление | Операция / Интеграционный поток | Инициатор | Протокол | Владелец контракта | Описание бизнес-контекста |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **request-service** | Входной (Inbound) | REST: `getDocumentsByRequest` | `request-service` | REST | `document-service` | Запрос от модуля заявок на получение списка документов по ID заявки[cite: 5]. |
| **request-service** | Входной (Inbound) | Event: `RequestCreatedEvent` | `request-service` | Event | `request-service` | Потребление события создания новой заявки для инициализации связей документов[cite: 5]. |
| **request-service** | Выходной (Outbound)| REST: `validateRequestContext` | `document-service`| REST | `request-service` | Валидация контекста и статуса заявки перед привязкой к ней новых файлов. |
| **request-service** | Выходной (Outbound)| REST: `getRequiredDocuments` | `document-service`| REST | `request-service` | Запрос матрицы обязательности документов для проверки комплектности дела. |
| **request-service** | Выходной (Outbound)| Event: `DocumentUploaded` / `DocumentAccepted` | `document-service`| Event | `document-service` | Публикация событий изменения ЖЦ документов для синхронизации статусов внутри заявки[cite: 5]. |
| **request-service** | Выходной (Outbound)| Event: `DocumentLinkCreated` | `document-service`| Event | `document-service` | Уведомление смежного сервиса о факте успешного линкования документа к сущности[cite: 5]. |
| **expertise-service**| Входной (Inbound) | REST: `getDocumentMetadata` | `expertise-service`| REST | `document-service` | Запрос от сервиса экспертизы метаданных карточек документов. |
| **expertise-service**| Входной (Inbound) | Event: `ExpertCardReadyForRegistration` | `expertise-service`| Event | `expertise-service` | Потребление события готовности карты для генерации рег. номера[cite: 5]. |
| **expertise-service**| Выходной (Outbound)| REST: `validateExpertiseCase` | `document-service`| REST | `expertise-service` | Проверка существования и валидности дела экспертизы[cite: 5]. |
| **expertise-service**| Выходной (Outbound)| Event: `DocumentApproved` | `document-service`| Event | `document-service` | Уведомление об утверждении документов (в т.ч. Экспертных карт) для изменения статуса дела[cite: 5]. |
| **review-service** | Входной (Inbound) | REST: `registerReviewProtocol` | `review-service` | REST | `document-service` | Прием и регистрация сравнительных протоколов по результатам повторных проверок[cite: 5]. |
| **review-service** | Входной (Inbound) | Event: `ReviewProtocolReady` | `review-service` | Event | `review-service` | Сигнал от модуля проверок о том, что протокол сформирован и готов к согласованию[cite: 5]. |
| **review-service** | Выходной (Outbound)| REST: `validateReviewContext` | `document-service`| REST | `review-service` | Валидация контекста замечаний и связей с первичной экспертизой перед регистрацией[cite: 5]. |
| **review-service** | Выходной (Outbound)| Event: `DocumentReplacementRequested` | `document-service`| Event | `document-service` | Сигнал о необходимости замены файла из-за несоответствий. |
| **review-service** | Выходной (Outbound)| Event: `DocumentApproved` | `document-service`| Event | `document-service` | Уведомление об утверждении Сравнительного протокола. |
| **report-service** | Входной (Inbound) | REST: `registerReportDocument` | `report-service` | REST | `document-service` | Вызов со стороны генератора отчетов для сохранения готового файла в наше хранилище[cite: 5]. |
| **report-service** | Входной (Inbound) | REST: `requestPublication` | `report-service` | REST | `document-service` | Запрос от сервиса отчетов на запуск процедуры публикации/доставки документа[cite: 5]. |
| **report-service** | Входной (Inbound) | Event: `ReportGenerated` / `ReportApproved` | `report-service` | Event | `report-service` | Потребление событий готовности отчетов для автоматического изменения статуса карточки. |
| **report-service** | Выходной (Outbound)| REST: `validateReportContext` | `document-service`| REST | `report-service` | Валидация структуры отчета перед его физической регистрацией. |
| **report-service** | Выходной (Outbound)| Event: `DocumentApproved` / `Published` | `document-service`| Event | `document-service` | Уведомление сервиса отчетов об изменении статусов опубликованных документов. |
| **report-service** | Выходной (Outbound)| Event: `DocumentPublicationFailed` | `document-service`| Event | `document-service` | Оповещение о невозможности опубликовать отчет (сбой доставки). |
| **cabinet-service** | Входной (Inbound) | REST: `getPublishedDocuments` | `cabinet-service` | REST | `document-service` | Запрос ЛК на чтение документов со статусом `PUBLISHED`[cite: 5]. |
| **cabinet-service** | Входной (Inbound) | REST: `createSecureLink` | `cabinet-service` | REST | `document-service` | Генерация временной безопасной ссылки на скачивание бинарного файла[cite: 5]. |
| **cabinet-service** | Входной (Inbound) | REST: `registerDeliveryReceipt` | `cabinet-service` | REST | `document-service` | Фиксация сервером факта доставки документа в интерфейс заявителя[cite: 5]. |
| **cabinet-service** | Входной (Inbound) | Event: `CabinetDocumentOpened` / `Downloaded`| `cabinet-service` | Event | `cabinet-service` | Потребление событий активности заявителя для продвижения ЖЦ документов (ФТ-22)[cite: 5]. |
| **cabinet-service** | Выходной (Outbound)| Event: `DocumentPublished` | `document-service`| Event | `document-service` | Публикация транзитного события для отображения документа в Личном Кабинете[cite: 5]. |
| **workflow-service**| Входной (Inbound) | REST: `startDocumentRoute` | `workflow-service`| REST | `document-service` | Команда оркестратора на инициализацию и старт маршрута ЭДО. |
| **workflow-service**| Входной (Inbound) | REST: `completeRouteTask` | `workflow-service`| REST | `document-service` | Команда на завершение текущей задачи в рамках шага согласования. |
| **workflow-service**| Входной (Inbound) | REST: `commandStatusChange` | `workflow-service`| REST | `document-service` | Команда принудительного изменения статуса со стороны бизнес-процесса. |
| **workflow-service**| Входной (Inbound) | Event: `WorkflowTaskCompleted` | `workflow-service`| Event | `workflow-service` | Потребление сигнала о завершении внешней задачи маршрута[cite: 5]. |
| **workflow-service**| Входной (Inbound) | Event: `WorkflowRouteApproved` | `workflow-service`| Event | `workflow-service` | Потребление события о полном согласовании сквозного бизнес-процесса[cite: 5]. |
| **workflow-service**| Выходной (Outbound)| Event: `DocumentApprovalRequested` | `document-service`| Event | `document-service` | Инициация запуска внешнего процесса оркестрации при переходе в `UNDER_APPROVAL`[cite: 5]. |
| **workflow-service**| Выходной (Outbound)| Event: `DocumentStatusChanged` | `document-service`| Event | `document-service` | Синхронизационные события изменения бизнес-статусов для отслеживания шагов[cite: 5]. |

## Фиксированные архитектурные правила (Закрытые пункты)
1. **Дедупликация входящих событий:** Идемпотентность гарантируется на нашей стороне. В качестве бизнес-ключа используется уникальный `eventId` из заголовка конверта SPEC-14. Таблица обработанных сообщений обновляется в рамках единой транзакции с бизнес-логикой. Раздел закрыт.