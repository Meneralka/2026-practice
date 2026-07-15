# MZD-30: Сценарии загрузки документов

Спецификация сценариев контура загрузки: двухфазная схема `init`/`complete`, множественная загрузка (REQ-08-001) и загрузка новой версии на тот же документ. Контракты API и события — по MZD-17 / MZD-40, статусы версии — по MZD-33, статусы карточки — по MZD-32, исключения — по MZD-31.

## 1. Двухфазная схема загрузки (обзор)

Бинарный файл никогда не проходит через `document-service` — сервис управляет только метаданными и правами. Загрузка разбита на две фазы плюс асинхронный конвейер:

| Фаза | Канал | Результат |
| :--- | :--- | :--- |
| 1. `POST /uploads/init` | REST, синхронно | Черновик карточки + версия `NEW`, presigned-политика на `quarantine-bucket` |
| 2. Заливка бинаря | Клиент → S3 (RustFS) напрямую | Объект во временном пути карантина |
| 3. `POST /uploads/{uploadId}/complete` | REST, синхронно | Версия `UPLOADED`, постановка в очередь проверок |
| 4. Конвейер проверок | Асинхронно (ClamAV + Tika) | `CLEAN` (перенос в `main-bucket`) либо `INFECTED`/`INVALID` (карантин) |

Все мутирующие вызовы требуют заголовков `X-Correlation-Id` и `X-Idempotency-Key` (иначе `400`). TTL сессии загрузки — 2 часа; незавершённые сессии вычищает воркер (MZD-33 §4).

## 2. Сценарий: инициация загрузки (`/uploads/init`)

* **Кто запускает:** пользователь UI (заявитель/сотрудник через форму загрузки) или смежный сервис; технически — клиентское приложение через API-шлюз.
* **Что проверяется (синхронно):**
  * обязательные заголовки трассировки и идемпотентности;
  * `fileSizeBytes` против конфигурационной матрицы лимитов (ERR-03-A → `422`);
  * заявленный `mimeType` против вайтлиста для `documentType`;
  * инвариант `SERVICE_RESOLUTION → visibilityProfile = INTERNAL` (BR-10 → `409`);
  * доступность RustFS для резервирования пути (ERR-05-A → `503`, БД откатывается, ничего не создаётся).
* **Что на выходе:**
  * карточка `DocumentCard` в статусе `DRAFT`;
  * запись `FileVersion` в статусе `NEW` (бинаря ещё нет);
  * ответ `201`: `uploadId`, `documentId`, `quarantineStorageTarget`, `maxSize`, `allowedMimeTypes`; presigned POST Policy содержит `content-length-range` (страховка от превышения размера на уровне бакета, ERR-03-B).
* **События:** `DocumentUploadInitiated` (documentId, uploadId, documentType) — аудит.

## 3. Сценарий: завершение загрузки (`/uploads/{uploadId}/complete`)

* **Кто запускает:** клиент, после успешной отправки бинаря в `quarantine-bucket`; в теле передаёт `fileHash` (SHA-256).
* **Что проверяется:**
  * существование и валидность сессии загрузки (аннулирована/истёк TTL → `404 UPLOAD_SESSION_NOT_FOUND`);
  * синхронно: HEAD-запрос к S3 — фактический размер против заявленного и лимита (расхождение → версия `INVALID`, `reasonCode = FILE_SIZE_EXCEEDED`, `422`); сверка SHA-256 (`HASH_MISMATCH`); доступность RustFS (ERR-05-B → `503`, версия остаётся `NEW`);
  * асинхронно (конвейер, версия `UPLOADED → CHECKING`): ClamAV — вирусные сигнатуры; Apache Tika — реальный MIME по magic bytes против вайтлиста.
* **Что на выходе:**
  * успех синхронной фазы: версия `UPLOADED`, ответ `200` (`documentId`, `fileVersionId`, статус карточки), скачивание версии заблокировано, ID версии в очереди конвейера;
  * успех конвейера: версия `CLEAN`, атомарный перенос `CopyObject`+`DeleteObject` в `main-bucket` (Object Lock), обновление `DocumentCard.actualFileVersionId`, автопереход карточки `DRAFT → UNDER_REVIEW` при валидном бизнес-контексте (кроме `SERVICE_RESOLUTION`);
  * провал конвейера: версия `INFECTED`/`INVALID`, бинарь удаляется из карантина, карточка остаётся в `DRAFT` с `quarantined: true`, бизнес-операции блокируются (`409`, ФТ-07); допустима только загрузка новой версии.
* **События:**
  * `DocumentUploaded` — после успешного `/complete`;
  * `DocumentTechnicalCheckPassed` — при `CLEAN`;
  * `DocumentTechnicalCheckFailed` (`reasonCode`: `ANTIVIRUS_INFECTED` / `MIME_TYPE_NOT_ALLOWED` / `FILE_SIZE_EXCEEDED` / `HASH_MISMATCH`) — при провале;
  * `DocumentStatusChanged` — на автопереходе `DRAFT → UNDER_REVIEW`.

## 4. Сценарий: множественная загрузка (REQ-08-001, MUST)

* **Кто запускает:** пользователь UI — перетаскивает N файлов в область Drag & Drop (MZD-48 §1). Технически пакет разворачивается в N независимых пар `init`/`complete`: одна карточка + одна версия на файл, единый `X-Correlation-Id` пакета, свой `X-Idempotency-Key` на каждый файл.
* **Что проверяется:** для каждого файла — полный набор проверок из §2–§3 **независимо**. Изоляция ошибок (BR-09): провал одного файла (вирус, размер, MIME) не откатывает и не блокирует остальные — транзакционного отката пакета нет.
* **Что на выходе:**
  * частичный успех: успешные файлы создают карточки/версии и идут по конвейеру, проблемные получают `INFECTED`/`INVALID` и `quarantined: true`;
  * по-файловый ответ: batch-структура с per-file статусами и кодами ошибок (mzd_25 C1);
  * действие фиксируется в журнале; UI показывает счётчик «Загружено успешно: K из N» и ошибку под каждым проблемным файлом.
  * Критерий приёмки: пакет из 3 файлов с 1 заражённым → 2 чистые карточки валидны, заражённая — `DRAFT` + `quarantined: true`.
* **События:** по каждому файлу независимо — `DocumentUploadInitiated`, `DocumentUploaded`, затем `DocumentTechnicalCheckPassed` или `DocumentTechnicalCheckFailed`. Пакетного события нет; корреляция — через общий `correlationId` конверта.

## 5. Сценарий: загрузка новой версии на тот же документ

* **Кто запускает:** пользователь (заявитель/исполнитель) — в двух случаях:
  1. предыдущая версия провалила автопроверки — карточка в `DRAFT` с `quarantined: true`;
  2. документ отклонён с замечанием — карточка в `REPLACEMENT_REQUIRED` (`reasonCode` от координатора/согласующего).
  Технически — те же две фазы `init`/`complete`, но в контексте существующего `documentId` (новая карточка не создаётся).
* **Что проверяется:**
  * статус карточки допускает загрузку новой версии: `DRAFT`, `UNDER_REVIEW`, `ACCEPTED`, `REPLACEMENT_REQUIRED` — да; `UNDER_APPROVAL`, `APPROVED`, `PUBLISHED`, `ARCHIVED` — нет, guard `409 INVALID_STATE_TRANSITION` (матрица MZD-32 §2; архив блокирует любые изменения версий);
  * далее — полный конвейер проверок новой версии как в §3.
* **Что на выходе:**
  * новая запись `FileVersion` с `versionNumber = prev + 1` и ссылкой `previousFileVersionId`; WORM-модель — старая версия не перезаписывается и остаётся в истории (`CLEAN`-версии из `main-bucket` не удаляются);
  * `actualFileVersionId` переключается на новую версию **строго после** её перехода в `CLEAN`; при провале новой версии указатель не меняется — продолжает указывать на предыдущую чистую (или `null`, если чистых не было);
  * для `REPLACEMENT_REQUIRED`: после `CLEAN` карточка возвращается в `UNDER_REVIEW`; для карантинного `DRAFT`: снимается признак карантина, стандартный автопереход `DRAFT → UNDER_REVIEW`.
* **События:**
  * `DocumentUploaded` — новая версия загружена;
  * `DocumentVersionCreated` (documentId, fileVersionId, versionNumber > 1, previousFileVersionId);
  * `DocumentTechnicalCheckPassed` / `DocumentTechnicalCheckFailed` — итог проверок;
  * `DocumentStatusChanged` — при возврате `REPLACEMENT_REQUIRED → UNDER_REVIEW` или `DRAFT → UNDER_REVIEW`.

## 6. Сводка «сценарий → события»

| Сценарий | События (топик `document.events.v1`) |
| :--- | :--- |
| `/uploads/init` | `DocumentUploadInitiated` |
| `/uploads/complete` + проверки | `DocumentUploaded`; затем `DocumentTechnicalCheckPassed` **или** `DocumentTechnicalCheckFailed`; `DocumentStatusChanged` при автопереходе |
| Множественная загрузка | тот же набор × N файлов, независимо; общий `correlationId` |
| Новая версия на тот же документ | `DocumentUploaded`, `DocumentVersionCreated`, `DocumentTechnicalCheckPassed`/`Failed`, `DocumentStatusChanged` |

Все события — в конверте SPEC-14 (`eventId`, `correlationId`, `causationId`); payload — только метаданные и идентификаторы, без бинарного содержимого и прямых `s3://`-ссылок (MZD-40 §2).
