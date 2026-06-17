// Job migrazioni PROD1: lancia ENTRAMBE le config alembic (analytics + operational) con
// l'immagine prod1-api. Gli ini hanno sqlalchemy.url vuoto + prepend_sys_path=. (no bug placeholder,
// no PYTHONPATH necessario); la URL la legge env.py da settings.{analytics,operational}_db_url.
// AUTH_ENABLED=false → le settings non pretendono i secret OIDC durante la migrazione.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbUser string = 'prod1'
param imageTag string = 'latest'
param redisUrl string = 'redis://${namePrefix}-${env}-redis:6379/3'
@secure()
param dbPassword string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-prod1-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'prod1-migrate' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 900
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'analytics-db-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/analytics?ssl=require' }
        { name: 'operational-db-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/operational?ssl=require' }
      ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: '${acr}/prod1-api:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        command: [ 'sh', '-c' ]
        args: [ '/app/.venv/bin/alembic -c packages/data_access/alembic_analytics/alembic.ini upgrade head && /app/.venv/bin/alembic -c packages/data_access/alembic_operational/alembic.ini upgrade head' ]
        env: [
          { name: 'PRODUCT_CENTRAL_ENV', value: 'prod' }
          { name: 'AUTH_ENABLED', value: 'false' }
          { name: 'SESSION_SECRET_KEY', value: 'migrate-only-not-used' }
          { name: 'REDIS_URL', value: redisUrl }
          { name: 'ANALYTICS_DB_URL', secretRef: 'analytics-db-url' }
          { name: 'OPERATIONAL_DB_URL', secretRef: 'operational-db-url' }
        ]
      } ]
    }
  }
}
