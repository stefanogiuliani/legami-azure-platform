# Prepara un'app per Azure (Container Apps + Entra + rebac)

> **A cosa serve.** Brief **agent-ready**: dato un'app del portfolio Legami, elenca **esattamente** le
> modifiche per portarla su Azure Container Apps con login **Entra ID** e authz **rebac (OpenFGA)**.
> Ogni punto qui è stato **scoperto e provato dal vivo** portando PROD2 (la reference). Niente teoria.
>
> **Come usarlo:** dai all'agente dell'app questo doc + le 3 variabili (nome app, client-id Entra, FQDN
> Azure). Le modifiche di codice sono **config-driven, default Keycloak invariato** (il VPS non si rompe).
> Consolida e supera `entra-migration-app-actions.md` + `app-onboarding-checklist.md`.

---

## 0. I findings PROVATI su PROD2 (le lezioni-chiave)
1. **Il PDP (platform-admin) richiede `AUTH_ISSUER` esplicito.** La verify NON lo deriva dal tenant
   (deriva solo il JWKS). Senza → 401 "issuer mancante" su **ogni** token. *(Config di platform-admin,
   una volta sola — non per-app.)*
2. **Le app devono emettere token v2.0** (`api.requestedAccessTokenVersion = 2`). Default = v1.0
   (`iss=sts.windows.net/...`) → "unexpected iss". Con v2.0 `iss=login.microsoftonline.com/<tid>/v2.0`.
3. **Il token al PDP dev'essere verificabile = `aud` dell'app.** Con soli scope OIDC l'access token è
   per Graph (opaco). Si **espone uno scope API** (`api://<clientid>/access_as_user`) e lo si chiede →
   `aud = l'app`. Si inoltra l'access token (nessun cambio in pdp.py).
4. **Fallback claim identità necessario.** Nel token v2.0 spesso `email` è assente, l'identità è in
   **`preferred_username`**. Il PDP estrae `user:<email>` con ordine `email→preferred_username→upn`.
5. **Logout endpoint config-driven** (Fix B): cablato su Keycloak `/protocol/openid-connect/logout` →
   su Entra è `{tenant}/oauth2/v2.0/logout`.
6. **Token-refresh endpoint config-driven** (Fix A): stesso problema del logout (path Keycloak).

---

## A. IDENTITÀ / ENTRA — modifiche al kit FastAPI (config-driven, default Keycloak)
*(App che usano il kit: PROD2, parsly, LOG1, DP1. launcher usa NextAuth → sez. A-bis. consultant = Supabase, fuori scope.)*

1. **`OIDC_SCOPES`**: togliere `groups` (invalido su Entra, AADSTS650053). Su Entra:
   `openid profile email offline_access api://<clientid>/access_as_user`.
2. **Fallback claim email** (`config.py` `OIDC_EMAIL_CLAIMS`). ⚠️ **Default = `email`** (byte-identical
   al vecchio `get("email")`: un token Keycloak SENZA `email` DEVE continuare a fallire come prima). Il
   fallback `email,preferred_username,upn` si imposta **SOLO nel profilo Entra** (il token v2.0 spesso
   non ha `email`, ha `preferred_username`). *(Catch DP1: il default a 3 claim NON è byte-identical — un
   utente KC senza email loggerebbe dove prima dava 401. Scrivi un test che lo blocchi.)*
3. **Fix A — token-refresh endpoint** (`pdp.py`): da `{issuer}/protocol/openid-connect/token` a
   discovery (`token_endpoint`) o env `OIDC_TOKEN_ENDPOINT` (Entra: `{tenant}/oauth2/v2.0/token`).
4. **Fix B — logout endpoint** (`auth_helpers.build_logout_url`): aggiungere `logout_endpoint`
   config-driven (env `OIDC_LOGOUT_ENDPOINT`); default = path Keycloak. Entra: `{tenant}/oauth2/v2.0/logout`.
5. **PEP→PDP**: si manda l'**access token** invariato (diventa verificabile grazie allo scope API).
   Niente selettore di token in `pdp.py`.

### A-bis. launcher (NextAuth v5)
- Provider `keycloak` → `microsoft-entra-id` (config-driven via env `AUTH_IDP_TYPE`).
- Env: `AUTH_MICROSOFT_ENTRA_ID_{ID,SECRET,TENANT_ID}`. Scope `openid profile email`. Callback
  `…/api/auth/callback/microsoft-entra-id`. Stesse note token v2.0 + scope API se chiama il PDP.

## B. ENTRA APP-REGISTRATION (per ogni app — fatto lato palestra/Legami, non dall'agente)
1. App registration: redirect `https://<fqdn>/auth/callback` (kit) o `…/callback/microsoft-entra-id` (NextAuth).
2. **Expose an API**: App ID URI `api://<clientid>` + scope `access_as_user` (+ admin consent).
3. **`api.requestedAccessTokenVersion = 2`** (token v2.0). ⚠️ obbligatorio (finding #2).
4. Redirect URI **post-logout** = `https://<fqdn>/` (per il redirect dopo logout).
5. **Grant rebac** per gli utenti: `app:<clientid>#member@user:<email>` (via rebac-authz `/write`).

### B-bis. PUBLISH su platform-admin (mode GROUPS, il VPS) — le lezioni provate
- **Gate per DIPARTIMENTO, non role-only.** `required_groups` come fanno dp1/log1/parsly. Un gate
  role-only ha bloccato 15/17 utenti dal launcher (provato): l'utente deve stare in **almeno un**
  gruppo che matcha. role-only = solo se davvero l'app è per ruoli.
- **Formato del claim `groups` = quello dei `required_groups`.** Il mapper KC `full.path=false`
  emette il nome **foglia** (`dept-wholesale`, `role-admin`), non il path. I `required_groups`
  pubblicati devono essere nello **stesso** formato foglia, altrimenti match fallisce → deny.
- **Il claim `groups` deve stare nell'ACCESS token** (il PDP riceve l'access token, non l'id token):
  mapper con `access.token.claim=true`. Lo garantisce `provision-app-client.sh`/`provision-groups-scope.sh`.

## C. PLATFORM-ADMIN (una volta sola, non per-app)
Deploy in mode Entra/rebac con: `AUTH_IDP_TYPE=entra`, `AUTHZ_MODE=rebac`, **`AUTH_ISSUER=
https://login.microsoftonline.com/<tenant>/v2.0`** (finding #1), `AUTH_JWKS_URL` (o derivato dal tenant),
`REBAC_AUTHZ_URL=http://<np>-<env>-rebac-authz` (porta 80!), `REBAC_AUTHZ_API_KEY`, `AUTH_ENTRA_*`.

## D. RUNTIME / IMMAGINE (Container Apps)
1. Dockerfile build **linux/amd64** (Next.js → CI nativa o builder ≥8GB; tsx/Python ok anche piccolo).
2. Config 100% da **ENV**, fail-fast; bind `0.0.0.0:$PORT`.
3. `/health` + `HEALTHCHECK`. Log su stdout.
4. **Pull ACR** con identità CI (`AcrPush`⊃pull): `identity: UserAssigned` + `registries[].identity`.

## E. DATI / DB
1. DB+ruolo via **job onboarding** (`db-onboard.bicep`). Alembic **idempotente** su DB fresco (gate).
2. `DATABASE_URL` con `?ssl=require` (asyncpg).
3. Migrazioni come **job one-shot** con l'immagine dell'app.

## F. STORAGE / JOBS (solo app che ne hanno bisogno)
- **Azure Files** montato come volume per file su disco persistenti.
- **Container Apps Jobs** per worker/cron.

## ⚠️ GOTCHA RETE
URL interni = **`http://<app>`** (porta 80 dell'ingress), **NON** il targetPort (`:8080`/`:4000`/`:3000`).
- Esempio per ogni app consumer: `PDP_URL` su VPS è `http://platform-admin:3000/...`, ma su **Azure**
  diventa `http://<np>-<env>-platform-admin/api/authz/decide` **senza porta**. Metti la riga
  no-port (commentata) nel blocco Entra del `.env.example` così non si dimentica al cutover.

---

## Matrice per-app (cosa riguarda ciascuna)
| App | Auth | Scope API+v2.0 | Files | Jobs | n8n | Redis | Note speciali |
|---|---|---|---|---|---|---|---|
| **PROD2** | kit | ✅ (reference fatta) | — | — | — | — | — |
| **parsly** | kit | ✅ | ✅ PDF/output | ✅ cruncher/cron | ✅ | — | OCR Tesseract |
| **LOG1** | kit | ✅ | ✅ `/data` | — | — | — | — |
| **DP1** | kit | ✅ (auth opzionale) | ✅ SQLite | — | — | — | LibreOffice ≥1Gi |
| **launcher** | NextAuth | ✅ (swap provider) | — | — | — | — | — |
| **consultant** | Supabase | ❌ fuori scope | — | — | — | ✅ | non su identità piattaforma |

---

## Prompt-template per l'agente dell'app
```
Repo: <APP>. Branch dedicato da main. NON deployare, NON mergiare. TDD, default Keycloak invariato.

Obiettivo: rendere <APP> portabile su Azure Container Apps con login Entra ID e authz rebac, SENZA
rompere il deploy Keycloak/VPS attuale (tutto config-driven, default = comportamento attuale).

Applica le sezioni A (e A-bis se NextAuth), D, E, F del doc `prepara-app-per-azure.md` (te lo allego):
- OIDC_SCOPES senza `groups`; fallback claim email (email→preferred_username→upn) config-driven.
- Fix A (token-refresh endpoint) e Fix B (logout endpoint) config-driven (env, default path Keycloak).
- Config 100% da ENV, /health, bind 0.0.0.0:$PORT, Dockerfile build linux/amd64.
- Alembic idempotente su DB fresco; DATABASE_URL ?ssl=require.
- Se l'app scrive file su disco → predisponi il mount volume; se ha worker/cron → predisponi Jobs.

Variabili di questa app: <files? jobs? n8n? redis?> (vedi matrice).
Deliverable: cambi sul branch + test verdi + .env.example aggiornato + summary. NON deployare/mergiare.
Lascia a me (operatore) la parte Entra app-registration (sez. B) e platform-admin (sez. C).
```
