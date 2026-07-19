// rebac-authz (PDP API) come Container App INTERNA (porta 4000). Pull da ACR con
// identità CI. Config 100% da env. Raggiunta dalle app a http://${NP}-${ENV}-rebac-authz:4000.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
// Dentro il CAE le app HTTP si raggiungono a http://<app> (porta 80 dell'ingress), NON sul targetPort.
param openfgaUrl string = 'http://${namePrefix}-${env}-openfga'
param storeId string
param modelId string
param imageTag string = 'latest'
@secure()
param presharedKey string
@secure()
param pdpApiKey string
@secure()
param pdpAdminApiKey string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-ci'
}

var acr = '${namePrefix}${env}acr.azurecr.io'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-rebac-authz'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', svc: 'rebac-authz' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ci.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: false, targetPort: 4000, transport: 'http' }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'fga-token', value: presharedKey }
        { name: 'pdp-key', value: pdpApiKey }
        { name: 'pdp-admin-key', value: pdpAdminApiKey }
      ]
    }
    template: {
      containers: [ {
        name: 'rebac-authz'
        image: '${acr}/rebac-authz:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'OPENFGA_API_URL', value: openfgaUrl }
          { name: 'OPENFGA_STORE_ID', value: storeId }
          { name: 'OPENFGA_MODEL_ID', value: modelId }
          { name: 'OPENFGA_API_TOKEN', secretRef: 'fga-token' }
          { name: 'PDP_API_KEY', secretRef: 'pdp-key' }
          { name: 'PDP_ADMIN_API_KEY', secretRef: 'pdp-admin-key' }
          { name: 'PORT', value: '4000' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output rebacHost string = app.name
