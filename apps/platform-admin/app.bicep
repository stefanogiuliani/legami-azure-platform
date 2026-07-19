// platform-admin (PDP + admin UI) come Container App PUBBLICA (admin UI per umani +
// /api/authz/decide chiamato dalle app). Modalità ENTRA + REBAC. Pull ACR via identità CI.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param rebacUrl string = 'http://${namePrefix}-${env}-rebac-authz'
param entraClientId string
param entraTenantId string
param imageTag string = 'latest'
param keyVaultName string = '${namePrefix}-${env}-kv'
@description('CSV di client-id (azp) accettati dal PDP oltre a quelli derivati dalla registry (allowlist di rete di sicurezza). Il codice (src/lib/authz/accepted-azp.ts) è fail-closed: in MODE rebac, se questa lista è vuota E la registry non ha app pubblicate, ogni azp viene rifiutato.')
param acceptedAzp string = ''
@description('CSV di audience (aud) accettate dal verificatore token del PDP (env AUTH_ACCEPTED_AUDIENCES, vedi src/lib/authz/verifier-config.ts). Vuota = nessuna restrizione di audience lato verificatore.')
param acceptedAudiences string = ''
@description('OPT-IN, default INVARIATO. "keycloak" (default, Day-1) = catalogo statico via Keycloak, comportamento attuale identico. "db" = catalogo dinamico da Postgres (gap D1): aggiunge le env DATABASE_URL/REGISTRY_API_KEY da Key Vault SOLO in questo ramo. Cambiare a "db" solo dopo aver eseguito db-onboard.bicep + registry-schema-job.bicep e popolato i secret — vedi runbook Day-2 "G — registry dinamica".')
param registrySource string = 'keycloak'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-ci'
}
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-app-kv'
}

var acr = '${namePrefix}${env}acr.azurecr.io'
var fqdn = '${namePrefix}-${env}-platform-admin.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-platform-admin'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', svc: 'platform-admin' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ci.id}': {}, '${appKv.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 3000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      // registry-api-key: nome KV CONDIVISO col launcher (stesso segreto, non 'platform-admin-...'),
      // vedi apps/launcher/app-gym.bicep. Aggiunto SOLO se registrySource=='db' (opt-in).
      secrets: concat([
        { name: 'auth-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/platform-admin-auth-secret', identity: appKv.id }
        { name: 'entra-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/platform-admin-entra-client-secret', identity: appKv.id }
        { name: 'rebac-key', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/pdp-api-key', identity: appKv.id }
        { name: 'sa-key', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/platform-admin-sa-key', identity: appKv.id }
      ], registrySource == 'db' ? [
        { name: 'database-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/platform-admin-database-url', identity: appKv.id }
        { name: 'registry-api-key', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/registry-api-key', identity: appKv.id }
      ] : [])
    }
    template: {
      containers: [ {
        name: 'platform-admin'
        image: '${acr}/platform-admin:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        // REGISTRY_SOURCE/DATABASE_URL/REGISTRY_API_KEY aggiunte SOLO se registrySource=='db'
        // (default 'keycloak' → array vuoto, env identiche a prima: nessun cambio di comportamento).
        env: concat([
          { name: 'AUTH_SECRET', secretRef: 'auth-secret' }
          { name: 'AUTH_URL', value: 'https://${fqdn}' }
          { name: 'AUTH_TRUST_HOST', value: 'true' }
          { name: 'NEXT_SERVER_ACTIONS_ENCRYPTION_KEY', secretRef: 'sa-key' }
          { name: 'AUTH_IDP_TYPE', value: 'entra' }
          { name: 'AUTHZ_MODE', value: 'rebac' }
          { name: 'AUTH_ENTRA_CLIENT_ID', value: entraClientId }
          { name: 'AUTH_ENTRA_CLIENT_SECRET', secretRef: 'entra-secret' }
          { name: 'AUTH_ENTRA_TENANT_ID', value: entraTenantId }
          { name: 'REBAC_AUTHZ_URL', value: rebacUrl }
          { name: 'REBAC_AUTHZ_API_KEY', secretRef: 'rebac-key' }
          { name: 'AUTHZ_ACCEPTED_AZP', value: acceptedAzp }
          { name: 'AUTH_ACCEPTED_AUDIENCES', value: acceptedAudiences }
        ], registrySource == 'db' ? [
          { name: 'REGISTRY_SOURCE', value: 'db' }
          { name: 'DATABASE_URL', secretRef: 'database-url' }
          { name: 'REGISTRY_API_KEY', secretRef: 'registry-api-key' }
        ] : [])
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
