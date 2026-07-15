# MZD-22: Специфичные стейт-машины по типам документов

Жизненные циклы документов разделены на 5 изолированных тип-специфичных автоматов. Коды типов документов, статусы и перечисления приведены в строгое соответствие со спецификацией SPEC-13[cite: 3, 4].

## 1. Архитектурный статус «Карантин» (ФТ-07)
* Проверка файлов на вирусы вынесена на уровень **`FileVersion.status`**[cite: 3]. Допустимые значения enum берутся строго из SPEC-13 §3.1 / MZD-16 (`NEW`, `UPLOADED`, `CHECKING`, `CLEAN`, `INFECTED`, `INVALID`).
* На время технических проверок конвейер переводит карточку в `UNDER_REVIEW`; для `SERVICE_RESOLUTION` карточка остаётся в `DRAFT` — статус `UNDER_REVIEW` исключён её графом, проверки идут на уровне `FileVersion` (MZD-16 §3). Переход на бизнес-стадии разрешен только для файлов в статусе `CLEAN`.

## 2. Изолированные графы переходов по типам документов (SPEC-13)

### 1. Материалы заявки (`REQUEST_MATERIAL`)
* **Разрешенные статусы:** `DRAFT` -> `UNDER_REVIEW` -> (`ACCEPTED` | `REPLACEMENT_REQUIRED`) -> `ARCHIVED`.
* **Правило возврата:** Из статуса `UNDER_REVIEW` при обнаружении ошибок документ переводится в `REPLACEMENT_REQUIRED`. После перезагрузки файла (статус `CLEAN`) карточка возвращается в `UNDER_REVIEW`.
* **Ограничение:** Статусы `UNDER_APPROVAL`, `APPROVED` и `PUBLISHED` исключены из графа конфигурации.

### 2. Экспертная карта (`EXPERT_CARD`)
* **Разрешенные статусы:** `DRAFT` -> `UNDER_REVIEW` -> `ACCEPTED` -> `UNDER_APPROVAL` -> `APPROVED` -> `ARCHIVED`.
* **Правило возврата:** Перевод в `REPLACEMENT_REQUIRED` доступен со стадий `UNDER_REVIEW` и `UNDER_APPROVAL`.
* **Закрыто:** Статус `PUBLISHED` исключён из графа окончательно — экспертная карта заявителю не публикуется. Если карту потребуется показать заявителю, это оформляется отдельным документом (выпиской), а не расширением данной матрицы.

### 3. Экспертное заключение (`EXPERT_CONCLUSION`)
* **Разрешенные статусы:** `DRAFT` -> `UNDER_REVIEW` -> `ACCEPTED` -> `UNDER_APPROVAL` -> `APPROVED` -> `PUBLISHED` -> `ARCHIVED`.
* **Закрыто:** Статус `ACCEPTED` — обязательный шаг единого шаблона переходов, не условный. Ветвление автомата по этому статусу не вводится.
* **Правило возврата:** Перевод в `REPLACEMENT_REQUIRED` доступен со стадий `UNDER_REVIEW` и `UNDER_APPROVAL`.

### 4. Сравнительный протокол (`COMPARATIVE_PROTOCOL`)
* **Разрешенные статусы:** `DRAFT` -> `UNDER_REVIEW` -> `ACCEPTED` -> `UNDER_APPROVAL` -> `APPROVED` -> `ARCHIVED`.
* **Правило возврата:** Перевод в `REPLACEMENT_REQUIRED` доступен из точек `UNDER_REVIEW` и `UNDER_APPROVAL`.

### 5. Служебная резолюция (`SERVICE_RESOLUTION`)
* **Разрешенные статусы:** `DRAFT` -> `UNDER_APPROVAL` -> `APPROVED` -> `ARCHIVED`.
* **Ограничение:** Статусы `UNDER_REVIEW`, `ACCEPTED`, `PUBLISHED`, а также промежуточный статус возврата `REPLACEMENT_REQUIRED` полностью недопустимы по матрице и исключены из графа.
* **🔒 ЖЕСТКИЙ GUARD:** На уровне конфигурации переходов автомата для `SERVICE_RESOLUTION` установлен безусловный запрет (`Guard`) на транзиты в любые внешние или проверочные статусы. Попытка вызова данных интерфейсов генерирует `SecurityAccessDeniedException`.

## 3. Семантический маппинг событий
* Физическое добавление новой версии файла генерирует `DocumentUploaded`[cite: 3].
* Переход в `REPLACEMENT_REQUIRED` -> `DocumentReplacementRequested`.
* Переход в `ACCEPTED` -> `DocumentAccepted`[cite: 3].
* Переход в `APPROVED` -> `DocumentApproved`[cite: 3].
* Переход в `PUBLISHED` -> `DocumentPublished`[cite: 3].

## 4. Управление полем status
Матрица переходов инкапсулирована внутри пакета `document/`[cite: 3]. Модуль `routing/` взаимодействует с состоянием только через внутренний интерфейс сервиса документов[cite: 3].