param namePrefix string
param env string
param location string
param tenantId string = subscription().tenantId

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${namePrefix}-${env}-kv'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: tenantId
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
    enablePurgeProtection: true
  }
}

output keyVaultId string = kv.id
output keyVaultName string = kv.name
