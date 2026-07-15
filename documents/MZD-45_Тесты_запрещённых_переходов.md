# MZD-45: Тесты запрещённых переходов статусов (MZD-22 / SPEC-13)

**Принцип:** каждый недопустимый переход — **отдельный** тест. Тест зелёный, только если система **отказала**. Группировать запреты в один тест нельзя: при падении должно быть однозначно видно, какой guard сломан.

**Уровень:** матрица переходов инкапсулирована в пакете `document/` (MZD-22 §4) → основная проверка **INT**. SCC проверяет только код на границе (`POST /documents/{id}/status`).

**Коды отказа:**

| Причина | Код |
|---|---|
| Жёсткий guard `SERVICE_RESOLUTION` (`SecurityAccessDeniedException`) | **403** |
| Нарушение матрицы (статус вне графа / пропуск стадии / обратный переход) | **422** |
| Файл не в `CLEAN` (карантин, ФТ-07) | **409** |

## E1. Статус исключён из графа типа

| # | Тип | Из | В | Код | Основание |
|---|---|---|---|---|---|
| E1.1 | `REQUEST_MATERIAL` | `UNDER_REVIEW` | `UNDER_APPROVAL` | 422 | MZD-22 §2.1 |
| E1.2 | `REQUEST_MATERIAL` | `ACCEPTED` | `APPROVED` | 422 | MZD-22 §2.1 |
| E1.3 | `REQUEST_MATERIAL` | `ACCEPTED` | `PUBLISHED` | 422 | MZD-22 §2.1 |
| E1.4 | `EXPERT_CARD` | `APPROVED` | `PUBLISHED` | 422 | MZD-22 §2.2 (запрет закрыт окончательно, см. SPEC-01) |
| E1.5 | `COMPARATIVE_PROTOCOL` | `APPROVED` | `PUBLISHED` | 422 | MZD-22 §2.4 ⚠️ условный, см. ниже |
| E1.6 | `SERVICE_RESOLUTION` | `DRAFT` | `UNDER_REVIEW` | **403** | MZD-22 §2.5 guard |
| E1.7 | `SERVICE_RESOLUTION` | `DRAFT` | `ACCEPTED` | **403** | MZD-22 §2.5 guard |
| E1.8 | `SERVICE_RESOLUTION` | `APPROVED` | `PUBLISHED` | **403** | MZD-22 §2.5 guard |
| E1.9 | `SERVICE_RESOLUTION` | `UNDER_APPROVAL` | `REPLACEMENT_REQUIRED` | **403** | MZD-22 §2.5 guard |

## E2. Пропуск обязательной стадии

| # | Тип | Из | В | Код | Пропущено |
|---|---|---|---|---|---|
| E2.1 | `REQUEST_MATERIAL` | `DRAFT` | `ACCEPTED` | 422 | `UNDER_REVIEW` |
| E2.2 | `EXPERT_CARD` | `DRAFT` | `APPROVED` | 422 | вся цепочка |
| E2.3 | `EXPERT_CARD` | `UNDER_REVIEW` | `APPROVED` | 422 | `ACCEPTED`, `UNDER_APPROVAL` |
| E2.4 | `EXPERT_CONCLUSION` | `DRAFT` | `PUBLISHED` | 422 | вся цепочка согласования |
| E2.5 | `EXPERT_CONCLUSION` | `UNDER_APPROVAL` | `PUBLISHED` | 422 | `APPROVED` |
| E2.6 | `COMPARATIVE_PROTOCOL` | `DRAFT` | `APPROVED` | 422 | вся цепочка |
| E2.7 | `SERVICE_RESOLUTION` | `DRAFT` | `APPROVED` | 422 | `UNDER_APPROVAL` |

## E3. Обратные переходы и терминальный статус

| # | Тип | Из | В | Код | Основание |
|---|---|---|---|---|---|
| E3.1 | `EXPERT_CONCLUSION` | `PUBLISHED` | `UNDER_REVIEW` | 422 | обратный переход не в графе |
| E3.2 | `EXPERT_CARD` | `APPROVED` | `DRAFT` | 422 | обратный переход не в графе |
| E3.3 | любой | `ARCHIVED` | любой | 422 | терминальный, блокировка изменений (MZD-43) |
| E3.4 | `EXPERT_CARD` | `ACCEPTED` | `REPLACEMENT_REQUIRED` | 422 | MZD-22 §2.2: возврат только из `UNDER_REVIEW`/`UNDER_APPROVAL` |
| E3.5 | `EXPERT_CONCLUSION` | `DRAFT` | `REPLACEMENT_REQUIRED` | 422 | MZD-22 §2.3: то же |
| E3.6 | `COMPARATIVE_PROTOCOL` | `APPROVED` | `REPLACEMENT_REQUIRED` | 422 | MZD-22 §2.4: то же |

## E4. Карантин блокирует бизнес-переходы (ФТ-07)

Статусы версии файла — по MZD-16 (`FileVersion.status`).

| # | Условие | Из | В | Код |
|---|---|---|---|---|
| E4.1 | `FileVersion.status = INFECTED` | `DRAFT` | `UNDER_REVIEW` | **409** |
| E4.2 | `FileVersion.status = CHECKING` | `DRAFT` | `UNDER_REVIEW` | **409** |
| E4.3 | `FileVersion.status = INFECTED` | `DRAFT` | `UNDER_APPROVAL` (`SERVICE_RESOLUTION`) | **409** |

## E5. Сквозные проверки (применяются к каждому кейсу выше)

| Проверка | Ожидание |
|---|---|
| Событие при отказе | **не публикуется** (нет `DocumentStatusChanged`) |
| Аудит при отказе | попытка фиксируется как отклонённая (`actor`, `action`, `reasonCode`, `correlationId`) |
| Состояние после отказа | статус **не изменился** (перечитать карточку) |
| Утечка `SERVICE_RESOLUTION` | после отказа метаданные отсутствуют в выдаче ЛК (`getPublishedDocuments`) |

**Итого: 25 тестов** (E1: 9, E2: 7, E3: 6, E4: 3) + 4 сквозные проверки на каждый.

## Открытые вопросы по блоку E

- **E1.5** (`COMPARATIVE_PROTOCOL` → `PUBLISHED`) — запрет условный («не применяется, если протокол не подлежит выдаче»). Требует подтверждения признака выдаваемости.
