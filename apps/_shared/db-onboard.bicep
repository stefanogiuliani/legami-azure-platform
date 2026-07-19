// Job RIUSABILE di onboarding DB: gira DENTRO il Container Apps Environment
// (quindi nella VNet) ed esegue psql contro il Postgres privato per creare
// DB + ruolo dedicati a un'app. Il Postgres non si espone MAI su internet.
// Idempotente: salta create se ruolo/db esistono già.
// Segreti da Key Vault via UAMI app-kv. Convenzione per il secret del ruolo:
// <app>-db-password (es. n8n-db-password, openfga-db-password) — il chiamante
// passa il nome esatto in roleSecretName.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'

param dbName string
param roleName string
@description('Nome del secret in KV per la password del ruolo DB, convenzione <app>-db-password.')
param roleSecretName string
param adminSecretName string = 'pg-admin-password'
param adminUser string = 'pgadmin'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param keyVaultName string = '${namePrefix}-${env}-kv'
// pin: fissare a digest al collaudo dev (B6/G2 reproducibility)
param postgresImage string = 'postgres:16-alpine'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-app-kv'
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-dbonboard-${dbName}'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'db-onboard' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${appKv.id}': {} }
  }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      secrets: [
        { name: 'admin-pw', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${adminSecretName}', identity: appKv.id }
        { name: 'role-pw', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/${roleSecretName}', identity: appKv.id }
      ]
    }
    template: {
      containers: [ {
        name: 'psql'
        image: postgresImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'PGHOST', value: pgHost }
          { name: 'PGUSER', value: adminUser }
          { name: 'PGPASSWORD', secretRef: 'admin-pw' }
          { name: 'PGSSLMODE', value: 'require' }
          { name: 'ROLEPW', secretRef: 'role-pw' }
        ]
        command: [ '/bin/sh', '-c' ]
        args: [ 'set -e; psql -d postgres -tc "SELECT 1 FROM pg_roles WHERE rolname=\'${roleName}\'" | grep -q 1 || psql -d postgres -c "CREATE ROLE ${roleName} LOGIN PASSWORD \'$ROLEPW\'"; psql -d postgres -tc "SELECT 1 FROM pg_database WHERE datname=\'${dbName}\'" | grep -q 1 || psql -d postgres -c "CREATE DATABASE ${dbName} OWNER ${roleName}"; psql -d ${dbName} -c "GRANT ALL ON SCHEMA public TO ${roleName}"; echo ONBOARD-OK-${dbName}' ]
      } ]
    }
  }
}

output jobName string = job.name
