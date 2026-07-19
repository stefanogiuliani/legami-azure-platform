// LAUNCHER (portale app) — variante PALESTRA.
// Categoria: NextAuth/Next.js (Auth.js v5) + registry da platform-admin. Stateless (sessione JWT),
// NIENTE Postgres, NIENTE volume. Provider OIDC config-driven: AUTH_IDP_TYPE=entra → Microsoft Entra.
// Callback NextAuth: /api/auth/callback/microsoft-entra-id (NON /auth/callback).
// Scope auto-derivato da auth-idp.ts: "openid profile email api://<appId>/access_as_user".
// PDP: pdp-client chiama ${PDP_BASE_URL}/api/authz/decide con clientId=AUTH_KEYCLOAK_ID.
// ⚠️ GAP noti (vedi COORDINATION.md): (1) platform-admin non ha registry key → catalogo in degraded/static;
//   (2) oggetto rebac del grant (app:<appId> via aud vs app:launcher via clientId) da confermare con B.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param entraClientId string
param entraTenantId string
param imageTag string = 'latest'
@description('Base URL del PDP (platform-admin); pdp-client appende /api/authz/decide. Porta 80, no :3000.')
param pdpBaseUrl string = 'http://${namePrefix}-${env}-platform-admin'
@description('Endpoint registry su platform-admin (porta 80). Se manca la key → catalogo statico (degraded).')
param registryUrl string = 'http://${namePrefix}-${env}-platform-admin/api/registry'
@description('clientId logico usato dal PDP decide e da excludeSelf nel registry. Resta "launcher" anche in Entra.')
param appClientName string = 'launcher'
@description('Il valore vive in Key Vault (KV reference): non possiamo più dedurre da un param vuoto se la key registry esiste. Flag esplicito, settato dal deploy script in base a cosa è stato creato in KV. Key assente/false = catalogo in degraded/static (vedi registry-client.ts). Vedi COORDINATION.md GAP registry.')
param hasRegistryKey bool = false
param keyVaultName string = '${namePrefix}-${env}-kv'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-app-kv' }

var acr = '${namePrefix}${env}acr.azurecr.io'
var fqdn = '${namePrefix}-${env}-launcher.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-launcher'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'launcher' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {}, '${appKv.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 3000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      // registry-api-key: nome KV CONDIVISO con platform-admin (stesso segreto, non 'launcher-...').
      secrets: concat([
        { name: 'entra-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/launcher-entra-client-secret', identity: appKv.id }
        { name: 'nextauth-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/launcher-nextauth-secret', identity: appKv.id }
      ], hasRegistryKey ? [ { name: 'registry-api-key', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/registry-api-key', identity: appKv.id } ] : [])
    }
    template: {
      containers: [ {
        name: 'launcher'
        image: '${acr}/launcher-app:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: concat([
          // --- selettore IdP + Entra (Auth.js v5 auto-inferisce ID/SECRET/issuer dal tenant) ---
          { name: 'AUTH_IDP_TYPE', value: 'entra' }
          { name: 'AUTH_MICROSOFT_ENTRA_ID_ID', value: entraClientId }
          { name: 'AUTH_MICROSOFT_ENTRA_ID_SECRET', secretRef: 'entra-secret' }
          { name: 'AUTH_MICROSOFT_ENTRA_ID_TENANT_ID', value: entraTenantId }
          { name: 'NEXTAUTH_SECRET', secretRef: 'nextauth-secret' }
          // clientId logico per PDP decide + excludeSelf registry (resta "launcher")
          { name: 'AUTH_KEYCLOAK_ID', value: appClientName }
          // --- PDP / registry (server→server, rete interna CAE, porta 80) ---
          { name: 'PDP_BASE_URL', value: pdpBaseUrl }
          { name: 'REGISTRY_URL', value: registryUrl }
          // --- URL pubblico del launcher (no hardcode); trustHost già true nel codice ---
          { name: 'APP_BASE_URL', value: 'https://${fqdn}' }
          // ⚠️ GOTCHA NextAuth su ACA: trustHost da solo NON basta dietro l'ingress (a differenza di Caddy
          // sul VPS) → Auth.js costruisce redirect_uri da HOSTNAME:PORT = https://0.0.0.0:3000 e Entra lo
          // rifiuta. AUTH_URL esplicito forza il callback corretto. Vedi COORDINATION.md (finding 22:46).
          { name: 'AUTH_URL', value: 'https://${fqdn}' }
          // PORT lo inietta ACA; HOSTNAME 0.0.0.0 è già nel Dockerfile.
        ], hasRegistryKey ? [ { name: 'REGISTRY_API_KEY', secretRef: 'registry-api-key' } ] : [])
      } ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
