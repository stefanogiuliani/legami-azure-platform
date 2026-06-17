// PROD2 (app consumer) — variante PALESTRA: identità CI per pull ACR, segreti inline,
// login Entra, PDP = platform-admin. (In prod: segreti da Key Vault, vedi app.bicep.)
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbUser string = 'prod2'
param oidcClientId string
param oidcIssuer string
param oidcScopes string = 'openid profile email'
param imageTag string = 'latest'
param oidcLogoutEndpoint string = ''
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
var fqdn = '${namePrefix}-${env}-prod2.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-prod2'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'prod2' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'database-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/prod2?ssl=require' }
        { name: 'oidc-secret', value: oidcSecret }
        { name: 'session-secret', value: sessionSecret }
      ]
    }
    template: {
      containers: [ {
        name: 'prod2-warning'
        image: '${acr}/prod2-warning:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'DATABASE_URL', secretRef: 'database-url' }
          { name: 'OIDC_CLIENT_ID', value: oidcClientId }
          { name: 'OIDC_CLIENT_SECRET', secretRef: 'oidc-secret' }
          { name: 'OIDC_ISSUER', value: oidcIssuer }
          { name: 'OIDC_SCOPES', value: oidcScopes }
          { name: 'OIDC_LOGOUT_ENDPOINT', value: oidcLogoutEndpoint }
          { name: 'SESSION_SECRET_KEY', secretRef: 'session-secret' }
          { name: 'APP_PUBLIC_URL', value: 'https://${fqdn}' }
          { name: 'PDP_URL', value: pdpUrl }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
