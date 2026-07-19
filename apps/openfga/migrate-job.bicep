// Job: migrazione del datastore OpenFGA (crea le tabelle OpenFGA nel DB 'openfga').
// Gira dentro il CAE (rete privata) ed esegue `openfga migrate` contro il Postgres privato.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param keyVaultName string = '${namePrefix}-${env}-kv'
// pin: fissare a digest al collaudo dev (B6/G2 reproducibility)
param openfgaImage string = 'openfga/openfga:latest'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-app-kv'
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-openfga-migrate'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'openfga-migrate' }
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
        { name: 'datastore-uri', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/openfga-datastore-uri', identity: appKv.id }
      ]
    }
    template: {
      containers: [ {
        name: 'migrate'
        image: openfgaImage
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
