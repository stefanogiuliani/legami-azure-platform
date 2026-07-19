// Job migrazioni LOG1: gira l'immagine log1-app con `alembic upgrade head` contro il DB privato.
// alembic è globale sul PATH (vedi Dockerfile log1), WORKDIR /app dove sta alembic.ini.
// Il DATABASE_URL completo sta in Key Vault come 'log1-database-url': stessa fonte usata da
// app-gym.bicep, una sola verità per la connection string (B6).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param imageTag string = 'latest'
param keyVaultName string = '${namePrefix}-${env}-kv'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-app-kv' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-log1-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'log1-migrate' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {}, '${appKv.id}': {} } }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [ { name: 'database-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/log1-database-url', identity: appKv.id } ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: '${acr}/log1-app:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        command: [ 'sh', '-c' ]
        // FINDING log1: alembic.ini ha sqlalchemy.url=driver://... (placeholder NON vuoto) e env.py
        // fa `get_main_option() or DATABASE_URL` → il placeholder vince e ignora l'env asyncpg → ramo
        // sync → crash. Workaround: svuoto il placeholder a runtime (fix vero lato app: invertire l'or
        // o lasciare sqlalchemy.url vuoto in alembic.ini).
        args: [ 'sed -i "s#^sqlalchemy.url.*#sqlalchemy.url =#" alembic.ini && alembic upgrade head' ]
        // FINDING: l'eseguibile `alembic` NON mette la CWD sul sys.path e alembic.ini non ha
        // prepend_sys_path → l'env.py del kit (`from identity.db import Base`) non risolve.
        // PYTHONPATH=/app lo aggiusta lato IaC (alternativa pulita: prepend_sys_path=. in alembic.ini).
        env: [
          { name: 'DATABASE_URL', secretRef: 'database-url' }
          { name: 'PYTHONPATH', value: '/app' }
        ]
      } ]
    }
  }
}
