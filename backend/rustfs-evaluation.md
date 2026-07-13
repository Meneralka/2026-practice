# Оценка RustFS для document-management backend

Дата: 2026-07-13

## Проверенные требования

1. **Версионирование объектов** — работает.
   RustFS поддерживает S3-совместимое версионирование на уровне бакета (Unversioned / Enabled / Suspended), каждой версии присваивается version ID, есть delete markers. Ограничение: требует erasure coding и минимум 4 диска, версии нельзя отключить обратно, растёт объём хранилища. Источник: https://docs.rustfs.com/features/versioning/

2. **Presigned/временные ссылки** — работает с оговорками.
   Базовая генерация presigned URL (SigV4) реализована (есть отдельная библиотека rustfs-signer), максимальный срок жизни — 7 дней (ограничение самого протокола SigV4, не RustFS). Но есть открытые/недавние баги: presigned POST upload не работал (issue #608), presigned URL при включённом TLS давал NoSuchBucket (issue #1083), SignatureDoesNotMatch при аплоаде (issue #700), неясность с presigned URL для multipart upload по частям (issue #1635, без подтверждённого решения). Источники: https://github.com/rustfs/rustfs/issues/608, https://github.com/rustfs/rustfs/issues/1083, https://github.com/rustfs/rustfs/issues/700, https://github.com/rustfs/rustfs/issues/1635

3. **Иммутабельность подтверждённых файлов (WORM / Object Lock)** — работает с оговорками.
   Есть Governance и Compliance режимы retention + Legal Hold, заявлено соответствие Cohasset/SEC 17a-4(f)/FINRA/CFTC. В Compliance-режиме удаление запрещено даже root-пользователю — это то, что нужно для "нельзя изменить/удалить после approve". Но есть открытые баги именно в Compliance-режиме: удаление всё же проходит вопреки блокировке (discussion #1459), Compliance-lock мешает создать новую версию существующего объекта (issue #3174). Также retention/legal hold не переносятся при репликации. Источники: https://docs.rustfs.com/features/worm/, https://github.com/orgs/rustfs/discussions/1459, https://github.com/rustfs/rustfs/issues/3174

## Рекомендация

Версионирование — готово к использованию. Presigned URL и, что критичнее, Object Lock/WORM (Compliance mode) имеют документированные баги в текущих версиях (issues открыты/недавно закрыты без полного подтверждения). Поскольку иммутабельность approved-файлов — ключевое требование, а именно в Compliance-режиме найдены баги с обходом блокировки, **перед принятием решения нужен hands-on spike**: поднять RustFS локально, воспроизвести кейс "approve → retention Compliance → попытка удалить/перезаписать" и проверить presigned URL на нужной версии. Если спайк подтвердит баги — резервный вариант MinIO (более зрелая реализация тех же трёх фич).
