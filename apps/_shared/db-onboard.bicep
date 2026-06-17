// Job RIUSABILE di onboarding DB: gira DENTRO il Container Apps Environment
// (quindi nella VNet) ed esegue psql contro il Postgres privato per creare
// DB + ruolo dedicati a un'app. Il Postgres non si espone MAI su internet.
// Idempotente: salta create se ruolo/db esistono già.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'

param dbName string
param roleName string
@secure()
param rolePassword string
@secure()
param adminPassword string
param adminUser string = 'pgadmin'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-dbonboard-${dbName}'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'db-onboard' }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      secrets: [
        { name: 'admin-pw', value: adminPassword }
        { name: 'role-pw', value: rolePassword }
      ]
    }
    template: {
      containers: [ {
        name: 'psql'
        image: 'postgres:16-alpine'
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
