// Job: bootstrap di rebac-authz (crea store + authorization model su OpenFGA).
// Usa la NOSTRA immagine (rebac-authz) con comando override `npm run bootstrap`.
// Pull da ACR con l'identità CI (ha AcrPush⊃pull). Idempotente: ri-eseguibile.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
// Dentro il CAE le app HTTP si raggiungono a http://<app> (porta 80 dell'ingress), NON sul targetPort.
param openfgaUrl string = 'http://${namePrefix}-${env}-openfga'
param imageTag string = 'latest'
param keyVaultName string = '${namePrefix}-${env}-kv'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-ci'
}
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-app-kv'
}

var acr = '${namePrefix}${env}acr.azurecr.io'

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-rebac-bootstrap'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'rebac-bootstrap' }
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
      secrets: [ { name: 'fga-token', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/openfga-preshared-key', identity: appKv.id } ]
    }
    template: {
      containers: [ {
        name: 'bootstrap'
        image: '${acr}/rebac-authz:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        command: [ 'npm' ]
        args: [ 'run', 'bootstrap' ]
        env: [
          { name: 'OPENFGA_API_URL', value: openfgaUrl }
          { name: 'OPENFGA_API_TOKEN', secretRef: 'fga-token' }
          { name: 'OPENFGA_STORE_NAME', value: 'legami' }
        ]
      } ]
    }
  }
}
