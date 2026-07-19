// Job migrazioni PROD2: gira l'immagine prod2 con `alembic upgrade head` contro il DB privato.
// Il DATABASE_URL completo (utente+password+host+db) sta in Key Vault come 'prod2-database-url':
// stessa fonte usata da app.bicep, una sola verità per la connection string (B6).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param keyVaultName string = '${namePrefix}-${env}-kv'
param imageTag string = 'latest'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-app-kv' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-prod2-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'prod2-migrate' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ci.id}': {}, '${appKv.id}': {} }
  }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'database-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod2-database-url', identity: appKv.id }
      ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: '${acr}/prod2-warning:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        command: [ '/app/.venv/bin/alembic' ]
        args: [ 'upgrade', 'head' ]
        env: [ { name: 'DATABASE_URL', secretRef: 'database-url' } ]
      } ]
    }
  }
}
