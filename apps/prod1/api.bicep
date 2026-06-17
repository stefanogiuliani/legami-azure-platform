// PROD1 backend (FastAPI) — Container App INTERNO (ingress interno): lo raggiunge solo il proxy.
// 2 database del kit (analytics + operational) nello stesso Postgres + redis condiviso. Login Entra, PDP.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbUser string = 'prod1'
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
@secure()
param dbPassword string
@secure()
param oidcSecret string
@secure()
param sessionSecret string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-prod1-api'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'prod1-api' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: false, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'analytics-db-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/analytics?ssl=require' }
        { name: 'operational-db-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/operational?ssl=require' }
        { name: 'oidc-secret', value: oidcSecret }
        { name: 'session-secret', value: sessionSecret }
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
