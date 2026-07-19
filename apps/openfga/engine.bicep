// OpenFGA engine come Container App INTERNA (motore authz). Solo rete privata:
// rebac-authz lo raggiunge a http://<namePrefix>-<env>-openfga:8080. Auth preshared.
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

resource openfga 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-openfga'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', svc: 'openfga' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${appKv.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: false, targetPort: 8080, transport: 'http' }
      secrets: [
        { name: 'datastore-uri', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/openfga-datastore-uri', identity: appKv.id }
        { name: 'preshared-key', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/openfga-preshared-key', identity: appKv.id }
      ]
    }
    template: {
      containers: [ {
        name: 'openfga'
        image: openfgaImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
        args: [ 'run' ]
        env: [
          { name: 'OPENFGA_DATASTORE_ENGINE', value: 'postgres' }
          { name: 'OPENFGA_DATASTORE_URI', secretRef: 'datastore-uri' }
          { name: 'OPENFGA_AUTHN_METHOD', value: 'preshared' }
          { name: 'OPENFGA_AUTHN_PRESHARED_KEYS', secretRef: 'preshared-key' }
          { name: 'OPENFGA_HTTP_ADDR', value: '0.0.0.0:8080' }
          { name: 'OPENFGA_PLAYGROUND_ENABLED', value: 'false' }
          { name: 'OPENFGA_LOG_FORMAT', value: 'json' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output openfgaHost string = openfga.name
