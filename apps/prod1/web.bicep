// PROD1 frontend (Next.js standalone) — Container App INTERNO: lo raggiunge solo il proxy.
// Chiama il backend con path relativi /api/... (same-origin garantita dal proxy davanti).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param imageTag string = 'latest'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }
var acr = '${namePrefix}${env}acr.azurecr.io'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-prod1-web'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'prod1-web' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: false, targetPort: 3000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
    }
    template: {
      containers: [ {
        name: 'prod1-web'
        image: '${acr}/prod1-web:${imageTag}'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'PORT', value: '3000' }
          { name: 'HOSTNAME', value: '0.0.0.0' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output internalName string = app.name
