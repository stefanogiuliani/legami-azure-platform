param namePrefix string
param env string
param location string

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${namePrefix}-${env}-log'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  properties: { sku: { name: 'PerGB2018' }, retentionInDays: 30 }
}

output workspaceId string = law.id
output workspaceName string = law.name
output customerId string = law.properties.customerId
