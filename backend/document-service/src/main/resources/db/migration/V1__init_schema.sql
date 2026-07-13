-- Baseline migration: proves Flyway/schema versioning is wired up end to end.
-- Table shape is a starting point (matches the draft document lifecycle in
-- docs/document-lifecycle.md) — not a finalized design. Each backend dev
-- extends the schema with their own V<N>__*.sql migrations from here.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE documents (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    file_name   VARCHAR(255) NOT NULL,
    status      VARCHAR(32)  NOT NULL DEFAULT 'PENDING_REVIEW',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
