param namePrefix string
param env string
param location string
param acaSubnetId string
param logWorkspaceName string

// existing: il nome è noto a inizio deployment, quindi listKeys() è calcolabile
resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logWorkspaceName
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${namePrefix}-${env}-cae'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: law.properties.customerId
        sharedKey: listKeys(law.id, '2023-09-01').primarySharedKey
      }
    }
    vnetConfiguration: { infrastructureSubnetId: acaSubnetId, internal: false }
  }
}

output caeId string = cae.id
output caeDefaultDomain string = cae.properties.defaultDomain
