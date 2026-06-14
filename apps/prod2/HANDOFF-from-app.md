# PROD2 — Handoff lato-app → infra Azure

> Scritto dall'agent del repo **prod2-warning** dopo l'audit checklist del 2026-06-14.
> Scopo: dirti **cosa è già a posto lato app** (così non lo ri-verifichi) e **cosa resta a te**
> (i punti `DA CONFERMARE (infra)` della checklist). L'app ha superato il gate
> `app-readiness-check.sh apps/prod2 prod2-warning:fix "/app/.venv/bin/alembic upgrade head"`.

## Stato: l'app è PRONTA per il gate migrazioni
`scripts/app-readiness-check.sh apps/prod2 prod2-warning:<tag> "/app/.venv/bin/alembic upgrade head"`
→ TEST 1 ✅ (DB fresco), TEST 2 ✅ (re-run no-op), TEST 3 ✅ (13 tabelle, `alembic_version=0004_catalogo_redesign`).

Fix applicati lato app (commit su `main` di prod2-warning):
- `0003_web_session` reso idempotente (era l'unico `op.create_table` non protetto → `DuplicateTableError` su DB fresco).
- **`.dockerignore` aggiunto** — senza, una build *locale* (come quella che farai tu, dato che `az acr build`
  è bloccato su sub free) copiava il `.venv` macOS dell'host sopra `/app/.venv` e l'immagine non avviava
  né `alembic` né `uvicorn` (`not found`). **Se buildi prod2 in locale, usa un working tree pulito o assicurati
  che il `.dockerignore` sia presente.**
- `lifespan` con `await engine.dispose()` → shutdown pulito del pool su SIGTERM.

## Parametri concreti che ti servono (Task 2.x)

| Cosa | Valore |
|---|---|
| Porta di ascolto app | **`0.0.0.0:8000`** → `targetPort: 8000` in `app.bicep` |
| Endpoint health (no auth, 200) | **`GET /health`** → usalo per le probe dell'ingress |
| Comando migrazione (Job Task 2.5) | **`/app/.venv/bin/alembic upgrade head`** (alembic è nel venv uv, non sul PATH) |
| Seed post-migrazione (lingue) | Opzionale ma consigliato: `/app/.venv/bin/python -c "<seed_languages>"` — vedi `scripts/deploy-vps.sh` di prod2. È idempotente. |
| Driver DB | `postgresql+asyncpg://…` (asyncpg) |
| `onboard.sql` | già completo: ruolo `prod2`, db `prod2_warning`, ext `pg_trgm`+`unaccent`, `GRANT ALL ON SCHEMA public`. |

## Env / secret che l'app si aspetta (12-factor, tutto da env)
Niente è hardcoded: i default nel codice sono valori dev/VPS, **vanno sovrascritti**.

| Variabile | Da dove | Note |
|---|---|---|
| `DATABASE_URL` | secretRef (Key Vault) | `postgresql+asyncpg://prod2:<pwd>@<host>/prod2_warning`. **SSL**: con asyncpg usa `?ssl=require` (NON `sslmode=require` libpq). |
| `SESSION_SECRET_KEY` | **Key Vault (obbligatorio)** | firma il cookie di sessione; il default è un placeholder insicuro. Senza override il login è insicuro. |
| `OIDC_CLIENT_SECRET` | **Key Vault (obbligatorio)** | default vuoto. |
| `OIDC_ISSUER` | env | passando a Entra: `https://login.microsoftonline.com/<tenant>/v2.0`. Oggi punta a Keycloak (VPS). |
| `OIDC_CLIENT_ID` | env | id dell'app registration. |
| `APP_PUBLIC_URL` | env | URL pubblico dietro ingress; **deve combaciare** col redirect URI registrato (`<APP_PUBLIC_URL>/auth/callback`), altrimenti `AADSTS` al login. |
| `OIDC_SCOPES` | env | default `openid profile email groups`. |
| `PDP_URL` | env | endpoint decisione authz (rete interna). |

> ⚠️ Il redirect URI dell'app è **`<APP_PUBLIC_URL>/auth/callback`** (non la root). Registralo così su Entra (Task 2.0).

## Cosa resta a TE (i `DA CONFERMARE (infra)` della checklist)
- [ ] **OIDC verso Entra**: app registration + issuer v2.0 + redirect URI `<APP_PUBLIC_URL>/auth/callback` + **admin consent** (dal Portale, il MSI della Cloud Shell non può).
- [ ] **Secret in Key Vault → secretRef**: `DATABASE_URL`, `SESSION_SECRET_KEY`, `OIDC_CLIENT_SECRET` (almeno).
- [ ] **`targetPort: 8000`** in `app.bicep` + tag immagine coerente bicep↔ACR.
- [ ] **DB privato** (Private Endpoint + Private DNS); migrazioni via **Container Apps Job** (Task 2.5), non `containerapp exec`.
- [ ] **SSL nella connection string** in forma accettata da asyncpg (`?ssl=require`).

## Note di compatibilità
- L'app è **stateless**: la sessione sta nella tabella `web_session` (non in memoria) → multi-replica OK.
- **Nessuna scrittura su filesystem**: gli upload CSV sono letti in memoria (`await file.read()`), niente `/tmp`/volumi.
- **Log su stdout/stderr** (uvicorn + `logging`/`print(file=sys.stderr)`), nessun `FileHandler` → Log Analytics li cattura.
- **Nessun `create_all()` a runtime**: lo schema lo fa solo la migrazione → app e Job non si pestano i piedi.
