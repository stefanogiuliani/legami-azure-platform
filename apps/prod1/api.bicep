// PROD1 backend (FastAPI) — Container App INTERNO (ingress interno): lo raggiunge solo il proxy.
// 2 database del kit (analytics + operational) nello stesso Postgres + redis condiviso. Login Entra, PDP.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param oidcClientId string
param oidcIssuer string
param oidcScopes string = 'openid profile email'
param oidcEmailClaims string = 'email'
param oidcTokenEndpoint string = ''
param oidcLogoutEndpoint string = ''
@description('URL pubblico = FQDN del proxy (per redirect OIDC e APP_PUBLIC_URL).')
param appPublicUrl string
param redisUrl string = 'redis://${namePrefix}-${env}-redis:6379/3'
param imageTag string = 'latest'
// GOTCHA 1: URL interno = http://<app> (porta 80), non il targetPort
param pdpUrl string = 'http://${namePrefix}-${env}-platform-admin/api/authz/decide'
param keyVaultName string = '${namePrefix}-${env}-kv'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-app-kv' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-prod1-api'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'prod1-api' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {}, '${appKv.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: false, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      // analytics-db-url / operational-db-url: stessa fonte usata da migrate-job.bicep (B6, una sola verità).
      secrets: [
        { name: 'analytics-db-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod1-analytics-db-url', identity: appKv.id }
        { name: 'operational-db-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod1-operational-db-url', identity: appKv.id }
        { name: 'oidc-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod1-oidc-client-secret', identity: appKv.id }
        { name: 'session-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod1-session-secret', identity: appKv.id }
      ]
    }
    template: {
      containers: [ {
        name: 'prod1-api'
        image: '${acr}/prod1-api:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'PRODUCT_CENTRAL_ENV', value: 'prod' }
          { name: 'AUTH_ENABLED', value: 'true' }
          { name: 'ANALYTICS_DB_URL', secretRef: 'analytics-db-url' }
          { name: 'OPERATIONAL_DB_URL', secretRef: 'operational-db-url' }
          { name: 'REDIS_URL', value: redisUrl }
          { name: 'OIDC_CLIENT_ID', value: oidcClientId }
          { name: 'OIDC_CLIENT_SECRET', secretRef: 'oidc-secret' }
          { name: 'OIDC_ISSUER', value: oidcIssuer }
          { name: 'OIDC_SCOPES', value: oidcScopes }
          { name: 'OIDC_EMAIL_CLAIMS', value: oidcEmailClaims }
          { name: 'OIDC_TOKEN_ENDPOINT', value: oidcTokenEndpoint }
          { name: 'OIDC_LOGOUT_ENDPOINT', value: oidcLogoutEndpoint }
          { name: 'SESSION_SECRET_KEY', secretRef: 'session-secret' }
          { name: 'APP_PUBLIC_URL', value: appPublicUrl }
          { name: 'PDP_URL', value: pdpUrl }
          { name: 'DEFAULT_HOME', value: '/' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output internalName string = app.name
