// Job: migrazione del datastore OpenFGA (crea le tabelle OpenFGA nel DB 'openfga').
// Gira dentro il CAE (rete privata) ed esegue `openfga migrate` contro il Postgres privato.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbName string = 'openfga'
param dbUser string = 'openfga'
@secure()
param dbPassword string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-openfga-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'openfga-migrate' }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 600
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      secrets: [
        { name: 'datastore-uri', value: 'postgres://${dbUser}:${dbPassword}@${pgHost}:5432/${dbName}?sslmode=require' }
      ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: 'openfga/openfga:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        args: [ 'migrate' ]
        env: [
          { name: 'OPENFGA_DATASTORE_ENGINE', value: 'postgres' }
          { name: 'OPENFGA_DATASTORE_URI', secretRef: 'datastore-uri' }
        ]
      } ]
    }
  }
}

output jobName string = job.name
