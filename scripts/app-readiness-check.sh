#!/usr/bin/env bash
# scripts/app-readiness-check.sh
# ───────────────────────────────────────────────────────────────────────────
# GATE DI IDONEITÀ di un'app al Pilastro 2 (Azure Container Apps + Postgres condiviso).
#
# Riproduce LOCALMENTE la condizione "DB Azure appena onboardato" (Task 2.1) e ci
# lancia le migrazioni dell'immagine dell'app, ESATTAMENTE come fa il Container Apps
# Job del Task 2.5 — ma su un Postgres effimero, in pochi secondi, senza toccare Azure.
#
# Becca i bug che NON si vedono su un DB già migrato (quelli che la VPS non mostra):
#   • catena alembic NON idempotente su DB fresco  (caso reale prod2/0003 — 2026-06-14)
#   • migrazione non ri-eseguibile
#   • onboard.sql incompleto (es. manca GRANT ALL ON SCHEMA public → PG15+)
#   • estensioni mancanti
#
# USO:
#   scripts/app-readiness-check.sh <apps/NOME> <immagine[:tag]> ["comando-migrazione"] ["smoke-server-app"]
#   • smoke-server-app = comando che prova che il SERVER dell'app PARTE dentro l'immagine
#     (es. "/app/.venv/bin/uvicorn --version"). Cattura la classe .dockerignore/venv/shebang/arch
#     anche sul lato app-server, che i soli test migrazioni non vedono.
# ESEMPI:
#   scripts/app-readiness-check.sh apps/prod2 prod2-warning:latest "/app/.venv/bin/alembic upgrade head"
#   scripts/app-readiness-check.sh apps/identity legami-identity:dev  "alembic upgrade head"
# NB: le immagini uv-based hanno alembic NEL venv, non sul PATH → passa il comando completo
#     (lo trovi nel Job: az containerapp job show … --query template.containers[0].command).
#
# REQUISITI: docker. Tutto effimero (rete + Postgres usa-e-getta), ripulito a fine run.
# NON tocca Azure, NON usa il token: è un test 100% locale.
# ───────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_DIR="${1:?Uso: $0 <apps/NOME> <immagine[:tag]> [\"comando-migrazione\"]}"
IMAGE="${2:?manca l'immagine dell'app (es. prod2-warning:latest)}"
MIG_CMD="${3:-alembic upgrade head}"
APP_SMOKE="${4:-}"   # prova che il SERVER app parte DENTRO l'immagine (es. /app/.venv/bin/uvicorn --version). Vuoto = salta.

ONBOARD="$APP_DIR/onboard.sql"
[[ -f "$ONBOARD" ]] || { echo "❌ Non trovo $ONBOARD — passa la cartella dell'app (es. apps/prod2)"; exit 2; }

# --- ricava ruolo, database e nome-variabile-password DA onboard.sql (fonte di verità) ---
ROLE=$(grep -ioE 'CREATE ROLE +[a-z0-9_]+'     "$ONBOARD" | head -1 | awk '{print $3}')
DB=$(  grep -ioE 'CREATE DATABASE +[a-z0-9_]+' "$ONBOARD" | head -1 | awk '{print $3}')
PWVAR=$(grep -oE ":'[a-z0-9_]+'"               "$ONBOARD" | head -1 | tr -d ":'")
: "${ROLE:?non riesco a leggere 'CREATE ROLE' da onboard.sql}"
: "${DB:?non riesco a leggere 'CREATE DATABASE' da onboard.sql}"
: "${PWVAR:=app_pwd}"

PW="readiness_pw_$$"                 # password effimera locale, URL-safe
NET="readiness-net-$$"
PGC="readiness-pg-$$"

cleanup() { docker rm -f "$PGC" >/dev/null 2>&1 || true; docker network rm "$NET" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "▶ App:      $APP_DIR"
echo "▶ Immagine: $IMAGE"
echo "▶ Da onboard.sql → ruolo=$ROLE  db=$DB  var-pw=$PWVAR"
echo ""

docker network create "$NET" >/dev/null
echo "▶ Avvio Postgres effimero (postgres:17, stessa major di Azure Flexible)…"
docker run -d --name "$PGC" --network "$NET" -e POSTGRES_PASSWORD=admin postgres:17 >/dev/null
for _ in $(seq 1 30); do docker exec "$PGC" pg_isready -U postgres >/dev/null 2>&1 && break; sleep 1; done

echo "▶ Onboarding del DB FRESCO (eseguo $ONBOARD — come Azure al Task 2.1)…"
docker cp "$ONBOARD" "$PGC:/tmp/onboard.sql"
docker exec -e PGPASSWORD=admin "$PGC" psql -v ON_ERROR_STOP=1 -U postgres -v "$PWVAR=$PW" -f /tmp/onboard.sql

DBURL="postgresql+asyncpg://$ROLE:$PW@$PGC:5432/$DB"
run_mig() { docker run --rm --network "$NET" -e DATABASE_URL="$DBURL" --entrypoint sh "$IMAGE" -c "$MIG_CMD"; }

echo ""
echo "▶ TEST 1 — migrazioni su DB FRESCO  ($MIG_CMD)"
if run_mig; then echo "  ✅ exit 0 su DB fresco"
else echo "  ❌ FALLITO su DB fresco — tipico: catena alembic non idempotente (vedi 0001 create_all + create_table non protetto)"; exit 1; fi

echo ""
echo "▶ TEST 2 — ri-esecuzione (la migrazione DEVE poter girare due volte)"
if run_mig; then echo "  ✅ exit 0 anche alla seconda corsa"
else echo "  ❌ NON ri-eseguibile — un re-run deve essere idempotente (no-op)"; exit 1; fi

echo ""
echo "▶ TEST 3 — schema effettivamente applicato"
NTAB=$(docker exec -e PGPASSWORD="$PW" "$PGC" psql -tA -U "$ROLE" -d "$DB" -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';" | tr -d '[:space:]')
VER=$(docker exec  -e PGPASSWORD="$PW" "$PGC" psql -tA -U "$ROLE" -d "$DB" -c "SELECT version_num FROM alembic_version;" 2>/dev/null | tr -d '[:space:]' || true)
echo "  tabelle nello schema public: ${NTAB:-0}  |  alembic_version: ${VER:-<assente>}"
[[ "${NTAB:-0}" -gt 0 ]] || { echo "  ❌ nessuna tabella creata — le migrazioni non hanno prodotto schema"; exit 1; }

echo ""
echo "▶ TEST 4 — il binario del SERVER app esegue DENTRO l'immagine"
if [[ -n "$APP_SMOKE" ]]; then
  if docker run --rm --entrypoint sh "$IMAGE" -c "$APP_SMOKE" >/dev/null 2>&1; then
    echo "  ✅ '$APP_SMOKE' parte nell'immagine"
  else
    echo "  ❌ '$APP_SMOKE' NON parte nell'immagine — classe .dockerignore/venv/shebang/arch (es. .venv dell'host copiato sopra /app/.venv da 'COPY . .')"; exit 1
  fi
else
  echo "  ⚠️  saltato: nessun comando-smoke passato (4° argomento). Senza, il gate valida solo il binario delle migrazioni, non il server app."
fi

echo ""
echo "✅ READINESS OK — '$IMAGE' supera il gate su DB fresco."
echo "   (restano i check non automatizzabili: vedi docs/app-onboarding-checklist.md)"
