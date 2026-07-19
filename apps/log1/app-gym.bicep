// LOG1 (app consumer) — identità CI per pull ACR, segreti da Key Vault (KV reference),
// login Entra, PDP = platform-admin. Gemello di prod2 + Azure Files su /data (tariffario + upload).
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
param imageTag string = 'latest'
// GOTCHA 1: URL interno = http://<app> (porta 80), non il targetPort
param pdpUrl string = 'http://${namePrefix}-${env}-platform-admin/api/authz/decide'
@description('Nome del link storage sul CAE per i file durevoli di log1 (creato dal modulo storage).')
param dataStorageName string = 'log1-data'
param keyVaultName string = '${namePrefix}-${env}-kv'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-app-kv' }

var acr = '${namePrefix}${env}acr.azurecr.io'
var fqdn = '${namePrefix}-${env}-log1.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-log1'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'log1' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {}, '${appKv.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      // database-url: stessa fonte usata da migrate-job.bicep (B6, una sola verità).
      secrets: [
        { name: 'database-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/log1-database-url', identity: appKv.id }
        { name: 'oidc-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/log1-oidc-client-secret', identity: appKv.id }
        { name: 'session-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/log1-session-secret', identity: appKv.id }
      ]
    }
    template: {
      volumes: [ { name: 'data', storageType: 'AzureFile', storageName: dataStorageName } ]
      containers: [ {
        name: 'log1'
        image: '${acr}/log1-app:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'DATABASE_URL', secretRef: 'database-url' }
          { name: 'OIDC_CLIENT_ID', value: oidcClientId }
          { name: 'OIDC_CLIENT_SECRET', secretRef: 'oidc-secret' }
          { name: 'OIDC_ISSUER', value: oidcIssuer }
          { name: 'OIDC_SCOPES', value: oidcScopes }
          { name: 'OIDC_EMAIL_CLAIMS', value: oidcEmailClaims }
          { name: 'OIDC_TOKEN_ENDPOINT', value: oidcTokenEndpoint }
          { name: 'OIDC_LOGOUT_ENDPOINT', value: oidcLogoutEndpoint }
          { name: 'SESSION_SECRET_KEY', secretRef: 'session-secret' }
          { name: 'APP_PUBLIC_URL', value: 'https://${fqdn}' }
          { name: 'PDP_URL', value: pdpUrl }
          { name: 'DATA_DIR', value: '/data' }
        ]
        volumeMounts: [ { volumeName: 'data', mountPath: '/data' } ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
