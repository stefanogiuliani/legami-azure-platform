-- apps/prod2/onboard.sql — esegui UNA volta sul server condiviso
CREATE ROLE prod2 WITH LOGIN PASSWORD :'prod2_pwd';
CREATE DATABASE prod2_warning OWNER prod2;
\connect prod2_warning
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS unaccent;
GRANT ALL PRIVILEGES ON DATABASE prod2_warning TO prod2;
-- PostgreSQL 15+: lo schema public NON concede più CREATE in automatico → serve il grant
-- a livello di schema, altrimenti le migrazioni falliscono con "permission denied for schema public".
GRANT ALL ON SCHEMA public TO prod2;
