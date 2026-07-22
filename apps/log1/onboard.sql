-- apps/log1/onboard.sql — esegui UNA volta sul Postgres condiviso per creare ruolo + DB di log1.
-- Modellato su apps/prod2/onboard.sql, ma con i valori di log1 (NIENTE valori prod2-specifici).
--
-- Coerenza con l'IaC già presente in apps/log1/:
--   - migrate-job.bicep e app-gym.bicep leggono la connection string dal KV secret
--     'log1-database-url' → deve puntare a  db=log1  utente=log1  (i nomi qui sotto).
--   - Su Azure DEV, il Postgres è privato (VNet): NON si raggiunge via psql dall'esterno.
--     L'equivalente idempotente eseguito DENTRO la rete è il job generico
--       apps/_shared/db-onboard.bicep  con  dbName=log1 roleName=log1 roleSecretName=log1-db-password
--     (stessa convenzione usata per parsly/openfga). Questo file resta la fonte del SQL esatto
--     e il percorso "manuale su server condiviso" (profilo VPS, come prod2).
--
-- NB: NESSUNA CREATE EXTENSION. Le migrazioni alembic di log1 (0001→0030) non usano pg_trgm/unaccent
--     (quelle sono prod2-specifiche, per la ricerca fuzzy). Non aggiungerle "per abitudine".
CREATE ROLE log1 WITH LOGIN PASSWORD :'log1_pwd';
CREATE DATABASE log1 OWNER log1;
\connect log1
GRANT ALL PRIVILEGES ON DATABASE log1 TO log1;
-- PostgreSQL 15+: lo schema public NON concede più CREATE in automatico → serve il grant
-- a livello di schema, altrimenti le migrazioni falliscono con "permission denied for schema public".
GRANT ALL ON SCHEMA public TO log1;
