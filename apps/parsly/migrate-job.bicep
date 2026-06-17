// Job migrazioni PARSLY: alembic upgrade head contro il Postgres privato.
// PULITO (a differenza di log1): alembic/env.py fa set_main_option("sqlalchemy.url", DATABASE_URL) e
// alembic.ini ha prepend_sys_path=. → NESSUN workaround PYTHONPATH/placeholder. Solo DATABASE_URL + alembic.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbUser string = 'parsly'
param dbName string = 'parsly'
param imageTag string = 'latest'
@secure()
param dbPassword string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-parsly-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'parsly-migrate' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [ { name: 'database-url', value: 'postgresql+asyncpg://${dbUser}:${dbPassword}@${pgHost}:5432/${dbName}?ssl=require' } ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: '${acr}/parsly-app:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        // GOTCHA (Dockerfile parsly): il venv è creato in /build/.venv e COPIATO in /app/.venv → lo
        // script console `alembic` ha lo shebang hardcoded `#!/build/.venv/bin/python` (inesistente) →
        // eseguirlo dà "not found" (manca l'interprete, non il file). Il binario `python` invece è reale.
        // Fix: invocare alembic come MODULO con il python del venv. (env.py legge DATABASE_URL; prepend_sys_path=.)
        command: [ 'sh', '-c' ]
        args: [ 'cd /app && /app/.venv/bin/python -m alembic upgrade head' ]
        env: [ { name: 'DATABASE_URL', secretRef: 'database-url' } ]
      } ]
    }
  }
}
