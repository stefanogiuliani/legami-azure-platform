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

// SICUREZZA (B1): su prod la CI si assume SOLO tramite il GitHub Environment 'prod' (con reviewer),
// NON via ref:refs/heads/main — altrimenti qualunque push su main assumerebbe la CI di prod bypassando
// il gate di approvazione. Su dev resta la FIC ref-based (ambiente sacrificabile).
var ficName = env == 'prod' ? 'github-env-prod' : 'github-${githubBranch}'
var ficSubject = env == 'prod'
  ? 'repo:${githubRepo}:environment:prod'
  : 'repo:${githubRepo}:ref:refs/heads/${githubBranch}'

resource fic 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: uami
  name: ficName
  properties: {
    issuer: 'https://token.actions.githubusercontent.com'
    subject: ficSubject
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

// SICUREZZA (B2): Contributor RG-wide è più del necessario per build+deploy. È accettato QUI perché
// l'assunzione dell'identità prod è gated dalla FIC environment:prod (B1, sopra). Follow-up hardening:
// sostituire con un custom role scoped a Microsoft.App/containerApps/* (senza Microsoft.Authorization/*).
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
