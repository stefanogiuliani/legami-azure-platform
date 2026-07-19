// UAMI condivisa per le Container App: legge i secret dal Key Vault via secretRef.keyVaultUrl.
// Non system-assigned: alla creazione della Container App l'identità di sistema non esiste ancora,
// quindi keyVaultUrl/registry con identity:'system' non risolvono e il primo deploy fallisce (B6).
param namePrefix string
param env string
param location string = resourceGroup().location
param kvName string

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-${env}-app-kv'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
}

resource kvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, uami.id, 'KeyVaultSecretsUser')
  scope: kv
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}

output uamiId string = uami.id
output principalId string = uami.properties.principalId
output uamiName string = uami.name
