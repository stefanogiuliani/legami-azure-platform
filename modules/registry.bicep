param namePrefix string
param env string
param location string

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: '${namePrefix}${env}acr'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

output acrId string = acr.id
output acrLoginServer string = acr.properties.loginServer
