// Job MANUALE e OPT-IN: applica il DDL della registry dinamica (platform_admin.apps,
// platform_admin.group_map) sul Postgres privato. Serve SOLO se/quando si attiva
// REGISTRY_SOURCE=db su platform-admin (gap D1, fuori scope Day-1 — vedi runbook-day1-dev.md).
// Precondizione: DB + ruolo già creati da apps/_shared/db-onboard.bicep (dbName/roleName a scelta
// dell'operatore, es. platform_admin_registry / platform_admin) e il secret
// <dbName-KV-secret>-database-url già in Key Vault con connection string completa
// (postgres://ruolo:pwd@host/db?sslmode=require — vedi nota SSL sotto).
// DDL idempotente (CREATE SCHEMA/TABLE IF NOT EXISTS): rieseguibile senza rischio.
// Pattern: stesso schema di apps/_shared/db-onboard.bicep (job psql dentro la VNet del CAE), ma qui
// applica lo schema applicativo invece di creare ruolo/db. Il DDL è la copia locale
// `registry-schema.sql` (fonte di verità: platform-admin/db/schema.sql, vedi commento nel file).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param keyVaultName string = '${namePrefix}-${env}-kv'
@description('Nome del secret in KV con la connection string completa. Convenzione: platform-admin-database-url (stessa usata dalla env DATABASE_URL di app.bicep quando registrySource=db).')
param databaseUrlSecretName string = 'platform-admin-database-url'
// pin: fissare a digest al collaudo dev (B6/G2 reproducibility), coerente con db-onboard.bicep
param postgresImage string = 'postgres:16-alpine'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-app-kv'
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  // Nome accorciato: 'legami-dev-platform-admin-registry-schema' = 41 char > 32 (limite Container Apps Job).
  name: '${namePrefix}-${env}-paregistry-schema'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'paregistry-schema' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${appKv.id}': {} }
  }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 300
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      secrets: [
        { name: 'database-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${databaseUrlSecretName}', identity: appKv.id }
      ]
    }
    template: {
      containers: [ {
        name: 'psql'
        image: postgresImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'DBURL', secretRef: 'database-url' }
          { name: 'SCHEMA_SQL', value: loadTextContent('registry-schema.sql') }
        ]
        command: [ '/bin/sh', '-c' ]
        args: [ 'set -e; printf %s "$SCHEMA_SQL" | psql "$DBURL" -v ON_ERROR_STOP=1 -f -; echo REGISTRY-SCHEMA-OK' ]
      } ]
    }
  }
}

output jobName string = job.name
