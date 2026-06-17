# Migrazione identità Keycloak → Entra ID — azioni lato app

> **Scopo.** Documentare *esattamente* cosa cambia in ogni app quando il login passa da
> Keycloak a **Microsoft Entra ID** e l'autorizzazione passa da "gruppi nel token" a
> **grant rebac (OpenFGA)**. Questo è il punto più delicato della migrazione: il grosso
> del lavoro sono **azioni lato app**, non infrastruttura.
>
> Basato sulla verifica del codice reale di: kit identità (PROD2 di riferimento),
> platform-admin, rebac-authz, parsly, LOG1, launcher, DP1, consultant-assistant.

---

## 0. I due principi che reggono tutto

1. **Il "chi" è `user:<email>`** — decisione canonica ratificata (2026-06-02). *Non* il `sub`
   di Keycloak, *non* l'`oid` di Entra. L'email esiste in entrambi gli IdP ed è stabile →
   **i permessi (tuple OpenFGA) non si toccano** quando si cambia IdP.
2. **Il login del kit FastAPI usa OIDC discovery** (`/.well-known/openid-configuration`):
   issuer, JWKS, authorize/token endpoint vengono *scoperti*, non cablati. Cambiare IdP è
   quindi quasi solo **configurazione (env)**.

## 1. La decisione che semplifica tutto: authz via rebac (① ratificata)

**Prima:** login Keycloak → il token porta il claim `groups` → platform-admin decide usando
quei gruppi (+ un registro app dentro Keycloak).

**Problema su Entra:** lo scope `groups` **non è valido** su Entra (errore `AADSTS650053`,
loop di redirect al login). I gruppi su Entra arrivano in modo diverso (security group con
config dedicata, oppure App Roles → claim `roles`, oppure via Microsoft Graph).

**Scelta adottata (①):** l'autorizzazione **non** si basa più sui gruppi nel token. Il PDP
(platform-admin) decide **interrogando OpenFGA** sui grant `user:<email>`. Conseguenze:

- Le app chiedono solo lo scope **`openid profile email`** (niente `groups`). Il problema
  "gruppi su Entra" **sparisce**.
- **rebac-authz: zero modifiche di codice** (è già IdP-agnostico).
- È l'end-state già pianificato (lo anticipiamo), coerente con il canonico `user:<email>`.
- Costo: anche il **registro app** (quali app esistono, le loro regole), oggi letto da
  Keycloak admin API in platform-admin, si sposta su **OpenFGA/DB**. È il refactor più
  sostanzioso di platform-admin, ma è il percorso coerente.

## 2. Cosa cambia, per componente

| Componente | Cosa serve | Peso |
|---|---|---|
| **Kit FastAPI** (PROD2, parsly, LOG1, DP1) | env (issuer Entra + scope senza `groups`) + **2 fix di codice** (token-refresh + logout endpoint) | 🟢 piccolo |
| **rebac-authz** (OpenFGA) | nessuna modifica di codice; DB dedicato + seed tuple | 🟢 nessuno |
| **platform-admin** (PDP) | validazione token Entra (JWKS) + decisioni via OpenFGA + registro app fuori da Keycloak + provider admin-UI Entra | 🟠 medio |
| **launcher** | NextAuth: provider Keycloak → MicrosoftEntraID | 🟢 piccolo |
| **consultant-assistant** | usa **Supabase**, non l'OIDC di piattaforma → **fuori scope** | ⚪️ escluso |

---

## 3. Kit FastAPI — i 2 fix di codice (riusabili in PROD2/parsly/LOG1/DP1)

Il kit è **~95% config-driven**. Restano **due** punti cablati sul path Keycloak che vanno
resi IdP-agnostici (o configurabili). La via robusta: **leggerli da OIDC discovery**.

### Fix A — token endpoint (refresh) in `pdp.py`
```python
# PRIMA (cablato Keycloak):
def _token_endpoint() -> str:
    return f"{settings.oidc_issuer}/protocol/openid-connect/token"

# DOPO (discovery, IdP-agnostico): leggi una volta all'avvio
#   token_endpoint = GET {issuer}/.well-known/openid-configuration -> "token_endpoint"
# In alternativa minima: env OIDC_TOKEN_ENDPOINT (Entra: {issuer}/oauth2/v2.0/token)
```

### Fix B — logout endpoint in `auth_helpers.py` (`build_logout_url`)
```python
# PRIMA:  f"{issuer}/protocol/openid-connect/logout?..."
# DOPO:   usa "end_session_endpoint" dalla discovery
#         (Entra: {issuer}/oauth2/v2.0/logout). In minimo: env OIDC_LOGOUT_ENDPOINT.
```

### Fix C — token PEP→PDP verificabile (⚠️ scoperto nel dry-run, IMPORTANTE)
Il kit manda al PDP l'**access token** (`pdp.py: call_pdp`). Su Entra, con soli scope OIDC
(`openid profile email`), l'access token è un **token per Microsoft Graph**: opaco, **non
verificabile** da terzi → il PDP (platform-admin) risponde **401** → la `require_auth` lo
interpreta come `reauth` → **ERR_TOO_MANY_REDIRECTS** (loop di login silenzioso). Mandare
l'`id_token` non basta (rifiutato anch'esso: serve allineare issuer/claim).
**Fix:** il PEP deve inviare al PDP un **token Entra-verificabile dell'app**. Via consigliata:
esporre uno **scope API** sull'app-registration (`api://<clientid>/access_as_user`) e aggiungerlo
a `OIDC_SCOPES` → l'access token avrà **aud = l'app** (JWT v2.0 verificabile, con `email`/
`preferred_username`). In alternativa: usare l'`id_token` + verificare lato PDP issuer e claim
identità. Va deciso decodificando il token reale (lavoro per l'agente, TDD su branch).
**Riguarda tutte le app FastAPI** (parsly, LOG1, DP1, PROD2).

> **Tassello finale (da dry-run):** esporre lo scope API rende il token **verificabile** (sign-in ok,
> niente più loop "couldn't sign in"), ma il PDP può ancora dare 401 se il token **non porta un claim
> identità** (email/preferred_username/upn) o ha un **issuer da account personale (MSA)**. Fix:
> configurare gli **optional claims** sull'app-reg (`email`/`preferred_username` su **access E id token**)
> e **decodificare un token reale** (jwt.io) per confermare `iss`/`aud`/claim. Su un **tenant aziendale
> reale** (account di lavoro) questo è lineare; nel tenant-palestra (account personale @yahoo.it) ci sono
> quirk MSA non rappresentativi — non bloccano la produzione.

**Tutto il resto del kit NON cambia:** login (discovery), validazione token (authlib +
JWKS da discovery), `user:<email>` come subject, sessioni server-side (tabella `web_session`).
La **chiamata al PDP** invece richiede il Fix C qui sopra (NON è già a posto su Entra).

### Env da impostare per Entra (qualunque app del kit)
| Env | Keycloak (oggi) | **Entra (target)** |
|---|---|---|
| `OIDC_ISSUER` | `https://auth.…/realms/legami` | `https://login.microsoftonline.com/<TENANT_ID>/v2.0` |
| `OIDC_CLIENT_ID` | es. `prod2` | **App Registration ID (GUID)** della app su Entra |
| `OIDC_CLIENT_SECRET` | (segreto) | **secret della App Registration** |
| `OIDC_SCOPES` | `openid profile email groups` | **`openid profile email`** (no `groups`) |
| `APP_PUBLIC_URL` | URL VPS | URL Azure dell'app |
| `PDP_URL` | `http://platform-admin:3000/api/authz/decide` | invariato (interno alla piattaforma) |

---

## 4. platform-admin (PDP) — il cambiamento medio

1. **Validazione token (`verify-token.ts`)**: oggi costruisce il JWKS sul path Keycloak
   `${issuer}/protocol/openid-connect/certs`. Per Entra: JWKS =
   `https://login.microsoftonline.com/<tenant>/discovery/v2.0/keys`. Renderlo configurabile
   (`AUTH_JWKS_URL`) o derivarlo dall'issuer. Libreria `jose` → resta. Claim chiave: **`email`**
   (su Entra: `email`, fallback `preferred_username`/`upn`).
2. **Decisione (`/api/authz/decide`)**: oggi legge `groups` dal token e le regole app da
   Keycloak. Con ①: **interroga OpenFGA** su `user:<email>`. Il formato canonico
   (`user:<email>`, `group:<dim>-<slug>`) isola la logica dall'IdP → il motore decisionale è
   IdP-agnostico.
3. **Registro app**: spostarlo da Keycloak admin API a OpenFGA/DB (OpenFGA già modella
   `app:<id>` con `admin`/`member`).
4. **Admin UI (`auth.ts`)**: provider NextAuth Keycloak → **MicrosoftEntraID**
   (`clientId`/`clientSecret`/`tenantId`, scope `openid profile email`).

## 5. rebac-authz (OpenFGA) — nessuna modifica

- Subject già `user:<email>`, gruppi `group:<dim>-<slug>` → **Entra-safe**.
- Nessun import o claim Keycloak. `IDP_ISSUER` è opzionale/non consumato.
- Infra: **Postgres dedicato** per OpenFGA + `openfga migrate` (datastore). Store + model
  via bootstrap (una volta per ambiente). Auth engine: preshared key.
- Azione: **seed tuple** keyate su email + grant dell'utente di test.

## 6. launcher — swap provider NextAuth

- `next-auth/providers/keycloak` → `next-auth/providers/microsoft-entra-id`.
- Env: rimuovi `AUTH_KEYCLOAK_*`, aggiungi `AUTH_MICROSOFT_ENTRA_ID_{ID,SECRET,TENANT_ID}`.
- Scope `openid profile email` (no `groups`). Callback:
  `…/api/auth/callback/microsoft-entra-id`.

## 7. consultant-assistant — fuori scope (per ora)

Usa **Supabase** (auth + JWT backend custom), **non** l'OIDC di piattaforma. Non è parte
della migrazione Keycloak→Entra: portarlo sull'identità di piattaforma è un lavoro a sé.

---

## 8. Checklist azioni per-app

| App | Stile auth | Redirect URI da registrare su Entra | Sforzo | `groups` da togliere? |
|---|---|---|---|---|
| **PROD2** | kit FastAPI | `https://<fqdn>/auth/callback` | env (+2 fix kit) | già fatto ✅ |
| **parsly** | kit FastAPI | `https://<fqdn>/auth/callback` | env + reg + 2 fix kit | ✅ |
| **LOG1** | kit FastAPI | `https://<fqdn>/auth/callback` | env + reg + 2 fix kit | ✅ |
| **DP1** | kit FastAPI | `https://<fqdn>/auth/callback` | env + reg + 2 fix kit | ✅ |
| **launcher** | NextAuth | `https://<fqdn>/api/auth/callback/microsoft-entra-id` | env + reg + swap provider | ✅ |
| **consultant** | Supabase | — | fuori scope | — |

**Per ogni app OIDC (PROD2/parsly/LOG1/DP1/launcher):**
1. **App Registration su Entra** (tenant Legami): client ID + secret, redirect URI come sopra,
   scope `openid profile email`. *(Per il kit: serve anche `offline_access` se vuoi il refresh token.)*
2. **Env** aggiornate (sez. 3 / sez. 6).
3. **Fix codice** (kit: i 2 fix sez. 3 — una volta sola, poi vendorati in ogni app; launcher: swap provider).
4. **Grant rebac**: scrivi la tupla `user:<email>` per l'accesso all'app.
5. **Test**: login end-to-end → decisione PDP (via OpenFGA) → logout.

## 9. Cosa NON cambia (rassicurazioni)
- Il **subject** `user:<email>` e tutte le **tuple** OpenFGA.
- Le **sessioni** server-side (tabella `web_session`).
- La **forma della chiamata al PDP** (Bearer token).
- Il **modello OpenFGA** e rebac-authz (codice).
- I **dati applicativi** su Postgres.
