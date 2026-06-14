# Checklist di idoneità di un'app al Pilastro 2 (Azure)

> **Scopo:** ogni app che si porta sulla piattaforma Azure (PROD2, identity/Keycloak, rebac,
> parsly, consultant-assistant, launcher…) deve superare questa checklist **prima** del
> rilascio. L'infra (Pilastro 0/1) è solida e parametrica: i rischi reali stanno nelle
> **assunzioni nascoste delle singole app**. Questa lista nasce dai bug veri trovati nel
> dry-run INT101 (2026-06-14).
>
> **Come si usa:** ogni app si sistema nel **suo repo, col suo agent**. Punti automatizzabili
> → li verifica `scripts/app-readiness-check.sh`. Il resto → revisione puntuale qui sotto.

---

## 0. Gate automatico (lo fa lo script)

```bash
scripts/app-readiness-check.sh apps/<NOME> <immagine[:tag]> ["comando-migrazione"]
# es: scripts/app-readiness-check.sh apps/prod2 prod2-warning:latest "/app/.venv/bin/alembic upgrade head"
```
> Il comando-migrazione spesso va passato esplicito: immagini uv-based hanno alembic nel venv
> (`/app/.venv/bin/alembic`), non sul PATH. Lo trovi nel Job Azure:
> `az containerapp job show … --query "properties.template.containers[0].command"`.
Riproduce in locale **onboard DB fresco → migrazioni dell'immagine** (come Task 2.1 + 2.5) e
verifica: migrazioni `exit 0` su DB vuoto · ri-eseguibili · schema effettivamente creato.
**Se questo fallisce, l'app NON è pronta.** Gli altri punti sono quelli che lo script non può vedere.

---

## 1. Database & migrazioni

- [ ] **Le migrazioni girano su un DB FRESCO** (non solo su uno già migrato come la VPS). ⟵ *bug prod2/0003: `0001_init` fa `Base.metadata.create_all()` che crea già tutto lo schema, poi `0003` faceva `op.create_table('web_session')` non protetto → `DuplicateTableError`.*
- [ ] **Ogni migrazione post-0001 è idempotente / difensiva** se 0001 usa `create_all`: guardia tipo `if "<tabella>" not in sa.inspect(bind).get_table_names(): ...`. *(Fix più pulito: togliere `create_all` da 0001 e usare DDL esplicito — rende le migrazioni successive non ridondanti.)*
- [ ] **La migrazione è ri-eseguibile** (un secondo `alembic upgrade head` è un no-op a `exit 0`): il Job del Task 2.5 può essere rilanciato.
- [ ] **Niente `create_all()` a runtime** (all'avvio dell'app / nel request path): lo schema lo fa **solo** la migrazione. Altrimenti app e Job fanno a botte sullo stesso DB.
- [ ] **Estensioni dichiarate in `apps/<NOME>/onboard.sql`** (`CREATE EXTENSION IF NOT EXISTS …`): le estensioni si creano all'onboarding, non dalle migrazioni (il ruolo app non è superuser).
- [ ] **`onboard.sql` concede lo schema** — `GRANT ALL ON SCHEMA public TO <ruolo>;` (PG15+ non lo dà più in automatico, altrimenti le migrazioni falliscono `permission denied for schema public`).
- [ ] **Driver `asyncpg` + `DATABASE_URL` da env/secret** (`postgresql+asyncpg://…`), `sslmode=require` verso Azure. Nessuna connection string hardcoded.

## 2. Autenticazione (OIDC / Entra ID)

- [ ] **Config OIDC tutta parametrica via env** — `OIDC_CLIENT_ID`, `OIDC_ISSUER`, `OIDC_CLIENT_SECRET`, `APP_PUBLIC_URL` — **niente** app id / tenant / URL hardcoded nel codice o nell'immagine.
- [ ] **`OIDC_ISSUER` = `https://login.microsoftonline.com/<tenant>/v2.0`** e **redirect URI = `APP_PUBLIC_URL`** registrato sull'app Entra (Task 2.0). Se non combaciano → `AADSTS` al login.
- [ ] **Scope OIDC = solo `openid profile email`** — **NON** chiedere `groups` come scope (non esiste su Entra → `AADSTS650053` → loop infinito di redirect al login). ⟵ *bug reale prod2 (2026-06-14): default app `OIDC_SCOPES=openid profile email groups`.* Per i gruppi usa i **groupMembershipClaims** (è un *claim* nel token, non uno scope).
- [ ] **Admin consent** dato sull'app Entra (dal Portale: il token MSI della Cloud Shell non può farlo).

## 3. Runtime & immagine

- [ ] **Endpoint di health** che risponde **200** senza auth (es. `/health`): serve alle probe dell'ingress e alla verifica del Task 2.4.
- [ ] **Ascolta su `0.0.0.0:<porta>`, NON su `127.0.0.1`/`localhost`** — altrimenti l'ingress non riceve traffico (l'app sembra su, ma 502). PROD2 = `0.0.0.0:8000`.
- [ ] **`targetPort` coerente** con la porta su cui l'app ascolta (PROD2 = `8000`). Va allineato in `app.bicep`.
- [ ] **Immagine `linux/amd64`** — `docker build --platform linux/amd64`. Su sub free `az acr build` non va (ACR Tasks bloccato): build locale + push, oppure la pipeline CI.
- [ ] **Esiste un `.dockerignore`** che esclude almeno `.venv/`, `venv/`, `__pycache__/`, `.env`, `.git/`. ⟵ *bug reale prod2 (2026-06-14): senza, su build LOCALE il `COPY . .` copiava il `.venv` macOS dell'host sopra `/app/.venv` → nell'immagine né `alembic` né `uvicorn` partivano (`not found`). Sulla VPS non si vedeva (build da git clone, niente `.venv`). **Critico per chi builda in locale** (cioè su sub free, dove ACR Tasks è bloccato).*
- [ ] **I binari girano DENTRO l'immagine** — non solo "il codice è giusto": `<mig-cmd> --version` **e** il server app (`uvicorn --version` o equivalente) devono **eseguire nell'immagine buildata**. Lo verifica il gate (TEST 1 = migrazioni in-image, TEST 4 = server app in-image, col 4° argomento). Cattura `.dockerignore`/venv/shebang/arch-mismatch.
- [ ] **Nessun segreto nell'immagine o nel codice** — tutto via Key Vault → secretRef (Task 2.2). Config 12-factor via env.
- [ ] **Log su stdout/stderr** (niente file): Container Apps cattura solo la console → Log Analytics. Senza, niente diagnosi (è successo nel dry-run: zero log app).
- [ ] **Shutdown pulito su SIGTERM** — a ogni nuova revision/scale-down Azure manda SIGTERM: chiudi connessioni/pool e termina entro il grace period, così niente richieste troncate.

## 3b. Stato & scalabilità (l'app gira con 1–N repliche, container effimero)

- [ ] **Stateless** — niente stato in memoria condiviso fra richieste/repliche (sessioni, lock, cache "calde"): va esternalizzato (DB/Redis). *Buon segno in PROD2: la sessione è la tabella `web_session`, non in-memory.*
- [ ] **Nessuna persistenza su filesystem locale** — il disco del container è effimero e per-replica. Upload/file → Blob Storage o simili, non `/tmp` o volumi locali.
- [ ] **Idempotente sui job schedulati/startup** — se più repliche eseguono lo stesso task all'avvio, non deve duplicare effetti.

## 4. Build & CI

- [ ] **Tag immagine coerente** fra `app.bicep`/`app.json` e ciò che viene pushato in ACR.
- [ ] **Comando migrazione noto** per il Job del Task 2.5 (default `alembic upgrade head`; se l'immagine usa un entrypoint/venv diverso, passalo allo script e annotalo).

## 5. Rete & dipendenze tra app

- [ ] **DB raggiunto come privato** (Private Endpoint + Private DNS): le migrazioni passano da **Container Apps Job** (Task 2.5), non da `containerapp exec` (inaffidabile) né assumendo accesso pubblico.
- [ ] **Mappa le dipendenze verso altre app interne** — hostname della rete docker della VPS (es. `http://platform-admin:3000/api/authz/decide` come PDP/authz, altre API interne) **non risolvono** su Azure. ⟵ *visto su prod2 (2026-06-14): authz delegata al PDP `platform-admin` → su Azure irraggiungibile → l'app **fail-close** (deny corretto), ma nessuno può accedere finché il PDP non è migrato.* Decidi l'**ordine di migrazione** (il PDP/identity prima dei suoi consumatori) e cabla i nuovi URL via env.
- [ ] **Provisioning del primo utente/grant** — dopo che il PDP è su Azure, serve un **grant** per il primo utente (seed), altrimenti login OK ma "non autorizzato". È dato applicativo, non infra.

## 6. Auth: compatibilità IdP (se si cambia provider, es. Keycloak → Entra)

- [ ] **Endpoint token coerenti col provider** — se l'app fa refresh server-side dell'access_token (es. per un PDP), l'URL del token **dipende dall'IdP**: Keycloak `={issuer}/protocol/openid-connect/token`, Entra `=https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token`. ⟵ *trovato su prod2: `pdp.py` costruisce l'endpoint in forma Keycloak; su Entra il refresh fallirebbe. Oggi non morde (PDP comunque assente), ma va gestito quando il PDP sarà su Azure con Entra.*

---

### Pattern per le app successive
Per ogni nuova app si ripetono **solo** i Task 2.0–2.8 cambiando il nome app + questa checklist.
Le foundations (Pilastro 0) e l'estate (Pilastro 1) non si ritoccano. Aggiungere qui i temi
nuovi man mano che emergono (ogni bug trovato in un dry-run diventa una riga di questa lista).
