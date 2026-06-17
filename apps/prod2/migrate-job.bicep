// Job migrazioni PROD2: gira l'immagine prod2 con `alembic upgrade head` contro il DB privato.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbUser string = 'prod2'
@secure()
param dbPassword string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-prod2-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'prod2-migrate' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [ { name: 'database-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/prod2?ssl=require' } ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: '${acr}/prod2-warning:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        command: [ '/app/.venv/bin/alembic' ]
        args: [ 'upgrade', 'head' ]
        env: [ { name: 'DATABASE_URL', secretRef: 'database-url' } ]
      } ]
    }
  }
}
