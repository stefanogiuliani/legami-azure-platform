// PARSLY (Sales Order Automation) — order-processor (web) — variante PALESTRA.
// Categoria: consumer-kit PG+OIDC (come log1) + worker (cruncher, file separato) + AI esterna (Anthropic).
// NON è "n8n": n8n (legami-dev-n8n) è infra già esistente; parsly la CHIAMA via webhook (env N8N_*).
// /health tocca il DB (Depends(get_session)) → DB onboarded+migrato PRIMA dello smoke. Bind 0.0.0.0:8000 (default).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbUser string = 'parsly'
param dbName string = 'parsly'
param oidcClientId string
param oidcIssuer string
param oidcScopes string = 'openid profile email'
param oidcEmailClaims string = 'email,preferred_username,upn'
param oidcLogoutEndpoint string = ''
param imageTag string = 'latest'
param rebacUrl string = 'http://${namePrefix}-${env}-rebac-authz'
@description('Slug tenant + riferimenti al workflow n8n esistente (legami-dev-n8n). Non deploya n8n.')
param n8nTenantSlug string = 'legami'
@description('Nome del link Azure Files sul CAE per i PDF/data durevoli di parsly.')
param dataStorageName string = 'parsly-data'
@secure()
param dbPassword string
@secure()
param oidcSecret string
@secure()
param sessionSecret string
@description('Chiave Anthropic (Claude Document API). Necessaria al PROCESSING (cruncher), non a /health|/login. In gym = placeholder.')
@secure()
param anthropicKey string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }

var acr = '${namePrefix}${env}acr.azurecr.io'
var fqdn = '${namePrefix}-${env}-parsly.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-parsly'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'parsly' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'database-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/${dbName}?ssl=require' }
        { name: 'oidc-secret', value: oidcSecret }
        { name: 'session-secret', value: sessionSecret }
        { name: 'anthropic-key', value: anthropicKey }
      ]
    }
    template: {
      volumes: [ { name: 'data', storageType: 'AzureFile', storageName: dataStorageName } ]
      containers: [ {
        name: 'parsly'
        image: '${acr}/parsly-app:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'DATABASE_URL', secretRef: 'database-url' }
          { name: 'OIDC_CLIENT_ID', value: oidcClientId }
          { name: 'OIDC_CLIENT_SECRET', secretRef: 'oidc-secret' }
          { name: 'OIDC_ISSUER', value: oidcIssuer }
          { name: 'OIDC_SCOPES', value: oidcScopes }
          { name: 'OIDC_EMAIL_CLAIMS', value: oidcEmailClaims }
          { name: 'OIDC_TOKEN_ENDPOINT', value: '' }
          { name: 'OIDC_LOGOUT_ENDPOINT', value: oidcLogoutEndpoint }
          { name: 'SESSION_SECRET_KEY', secretRef: 'session-secret' }
          { name: 'ANTHROPIC_API_KEY', secretRef: 'anthropic-key' }
          { name: 'PDF_STORAGE_ROOT', value: '/app/data/pdfs' }
          { name: 'REBAC_URL', value: rebacUrl }
          { name: 'AUTHZ_ENFORCER', value: 'local' }
          { name: 'N8N_TENANT_SLUG', value: n8nTenantSlug }
          { name: 'APP_PUBLIC_URL', value: 'https://${fqdn}' }
        ]
        volumeMounts: [ { volumeName: 'data', mountPath: '/app/data' } ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
