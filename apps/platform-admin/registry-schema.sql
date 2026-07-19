-- Copia di platform-admin/db/schema.sql — fonte di verità resta il repo applicativo
-- (platform-admin, `db/schema.sql`). Questa copia esiste SOLO perché registry-schema-job.bicep
-- (Container Apps Job, gira dentro la VNet) la carica via loadTextContent() a build time: bicep
-- non può leggere file da un repo diverso da questo. Se lo schema cambia lato app, rincopia qui
-- e rigenera il job (nessuna logica, solo DDL idempotente: CREATE SCHEMA/TABLE IF NOT EXISTS).
CREATE SCHEMA IF NOT EXISTS platform_admin;

CREATE TABLE IF NOT EXISTS platform_admin.apps (
  client_id       text PRIMARY KEY,
  enabled         boolean     NOT NULL DEFAULT false,
  display_name    text        NOT NULL DEFAULT '',
  icon            text        NOT NULL DEFAULT '',
  url             text        NOT NULL DEFAULT '',
  description     text        NOT NULL DEFAULT '',
  required_groups jsonb       NOT NULL DEFAULT '[]'::jsonb,
  required_users  jsonb       NOT NULL DEFAULT '[]'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS platform_admin.group_map (
  canonical_name     text PRIMARY KEY,
  entra_object_id    text        NOT NULL UNIQUE,
  entra_display_name text        NOT NULL DEFAULT '',
  updated_at         timestamptz NOT NULL DEFAULT now()
);
