# MZD-39: Маршруты и задачи согласования

Управление процессами движения документов по этапам в соответствии со специфичными стейт-машинами. Перечисления приведены к SPEC-13 (§3.5–3.7).

## 1. Статусы маршрута и задачи
* **Статусы маршрута (`RouteStatus`, SPEC-13 §3.5):** `NOT_STARTED`, `IN_PROGRESS`, `APPROVED`, `REJECTED`, `CANCELLED`, `EXPIRED`.
* **Статусы задачи согласования (`RouteTaskStatus`, SPEC-13 §3.6):** `PENDING`, `IN_PROGRESS`, `COMPLETED`, `EXPIRED`, `CANCELLED`.
* **Решения согласующего (`RouteDecision`, SPEC-13 §3.7):**
  * `APPROVE` — согласовать, продвинуть на следующий шаг; на последнем шаге маршрута документ переводится в `APPROVED`.
  * `REJECT` — отклонить с обязательным `reasonCode` (свободный текст — в `comment`, он `internalOnly` и в ЛК не уходит).
  * `RETURN_FOR_REVISION` — вернуть на доработку с обязательным `reasonCode`.

## 2. Бизнес-правила и ограничения автоматов
* **Один активный маршрут:** Для карточки документа в конкретный момент времени может существовать строго один маршрут в статусе `IN_PROGRESS`.
* **Зависимость от типов документов (MZD-22):**
  * Документ **не может** перейти в статус `UNDER_APPROVAL`, если для него отсутствует связанный маршрут в статусе `IN_PROGRESS`.
  * **Служебная резолюция (`SERVICE_RESOLUTION`):** При решении `REJECT`/`RETURN_FOR_REVISION` или отмене маршрута перевод в `REPLACEMENT_REQUIRED` запрещен на уровне Guard-условия автомата (вызывает `SecurityAccessDeniedException`, HTTP 403). Процесс переводится обратно в `DRAFT` для ручной корректировки без возможности запроса замены.
  * **Остальные типы документов (`EXPERT_CARD`, `EXPERT_CONCLUSION`, `COMPARATIVE_PROTOCOL`):** При решении `REJECT`/`RETURN_FOR_REVISION` переводятся из `UNDER_APPROVAL` в `REPLACEMENT_REQUIRED` с соответствующим `reasonCode` (`APPROVER_REJECTED` / `RETURNED_FOR_REVISION`).
* **Идемпотентность (MZD-21, ФТ-35):** `ExecuteTaskCommand` несет `idempotencyKey`; повторная обработка того же ключа не меняет статус и возвращает текущее состояние.
