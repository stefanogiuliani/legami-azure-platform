param namePrefix string
param env string
param location string
param acrId string
param githubRepo string
param githubBranch string = 'main'

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${namePrefix}-${env}-ci'
  location: location
}

resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uami
  name: 'github-${githubBranch}'
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: 'repo:${githubRepo}:ref:refs/heads/${githubBranch}'
    audiences: ['api://AzureADTokenExchange']
  }
}

resource acrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrId, uami.id, 'AcrPush')
  scope: resourceGroup()
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
  }
}

resource contrib 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, uami.id, 'Contributor')
  scope: resourceGroup()
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  }
}

output uamiClientId string = uami.properties.clientId
output uamiPrincipalId string = uami.properties.principalId
