# Жизненный цикл документа: от загрузки до архива

> Диаграмма отражает целевой процесс, реконструированный по бэклогу
> (`backend/tasks`) и `backend/rustfs-evaluation.md`. **В коде
> `document-service` на данный момент (2026-07-14) ни один из этих шагов ещё
> не реализован** — есть только пустой каркас Spring Boot. Диаграмму нужно
> сверить с командой перед тем, как проектировать сущности/эндпоинты.

## Известные и открытые вопросы

| Вопрос | Статус |
|---|---|
| Кто согласовывает документ | Один ревьюер, вручную |
| Что при отклонении | Возврат автору на доработку (новая версия) |
| Триггер архивации | **Не решено** — кандидаты: retention policy / вручную / при загрузке новой версии |

## Диаграмма (UML activity)

```mermaid
flowchart TD
    start((Начало)) --> upload[Загрузка документа<br/><small>POST /documents</small>]

    subgraph auto1 [Document Service — авто]
        upload --> scan[Антивирусная проверка<br/><small>ClamAV</small>]
        scan --> infected{Заражён?}
        infected -- да --> rejectUpload[Отклонить загрузку,<br/>уведомить автора]
        rejectUpload --> endReject((Конец))

        infected -- нет --> store[Сохранение в object storage<br/><small>RustFS/MinIO, версионирование</small>]
        store --> meta[Запись метаданных<br/><small>status = PENDING_REVIEW</small>]
        meta --> assign[Назначение ревьюеру]
    end

    subgraph reviewer [Ревьюер]
        assign --> review[Ручная проверка<br/><small>один ревьюер</small>]
        review --> approved{Согласовано?}
    end

    approved -- нет --> rejected[status = REJECTED<br/>уведомление автора]
    rejected --> rework[Возврат на доработку<br/><small>автор готовит новую версию</small>]
    rework -.-> upload

    subgraph auto2 [Document Service — авто]
        approved -- да --> approvedStatus[status = APPROVED]
        approvedStatus --> lock[Блокировка объекта<br/><small>WORM / immutable</small>]
        lock --> publish[Публикация события<br/><small>Kafka: document.approved</small>]
    end

    subgraph tbd [Retention / архив — не определено]
        publish --> trigger[["⚠ Триггер архивации — TBD<br/><small>retention policy · вручную · новая версия</small>"]]
        trigger --> archive[Архивирование<br/><small>status = ARCHIVED, холодное хранилище</small>]
    end

    archive --> endOk((Конец))

    classDef tbdNode fill:#fff3cd,stroke:#c99a2e,stroke-width:1.5px,color:#5c4500;
    classDef rejectNode fill:#fde2e2,stroke:#b23b3b,color:#7a1f1f;
    classDef terminator fill:#eee,stroke:#888,color:#333;
    class trigger tbdNode;
    class rejectUpload,rejected terminator;
```

## Легенда

- **Прямоугольник** — активность/шаг процесса.
- **Ромб** — точка решения.
- **Жёлтый пунктирный блок** — шаг, чей триггер ещё не определён (TBD).
- **Пунктирная стрелка** (`rework -.-> upload`) — возврат в начало цикла при отклонении документа.

## Что подтверждено, а что предположение

- **Код (2026-07-14):** в `document-service` нет ни одного контроллера, entity
  или Flyway-миграции — только пустой каркас Spring Boot приложения.
- **Из бэклога (`backend/tasks`):** антивирус (ClamAV), object storage с
  версионированием (RustFS/MinIO), Kafka, требование неизменяемости файла
  после approve.
- **Из обсуждения с командой:** согласование выполняет один ревьюер вручную;
  отклонение — возврат автору на доработку; триггер архивации пока не выбран.
- Названия статусов (`PENDING_REVIEW`, `APPROVED`, `REJECTED`, `ARCHIVED`) и
  эндпоинтов предложены для диаграммы и не закреплены в коде — это предмет
  для обсуждения при проектировании сущности `Document`.
