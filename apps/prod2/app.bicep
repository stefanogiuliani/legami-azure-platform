param namePrefix string
param env string
param location string
param caeId string
param acrLoginServer string
param keyVaultName string
param ingressPublic bool
param appId string
param tenantId string
param caeDefaultDomain string

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-prod2'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'prod2' }
  identity: { type: 'SystemAssigned' }
  properties: {
    managedEnvironmentId: caeId
    configuration: {
      ingress: { external: ingressPublic, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acrLoginServer, identity: 'system' } ]
      secrets: [
        { name: 'database-url', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod2-database-url', identity: 'system' }
        { name: 'session-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod2-session-secret', identity: 'system' }
        { name: 'oidc-secret', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/prod2-oidc-client-secret', identity: 'system' }
      ]
    }
    template: {
      containers: [ {
        name: 'prod2-warning'
        image: '${acrLoginServer}/prod2-warning:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'DATABASE_URL', secretRef: 'database-url' }
          { name: 'SESSION_SECRET_KEY', secretRef: 'session-secret' }
          { name: 'OIDC_CLIENT_SECRET', secretRef: 'oidc-secret' }
          { name: 'OIDC_CLIENT_ID', value: appId }
          { name: 'OIDC_ISSUER', value: 'https://login.microsoftonline.com/${tenantId}/v2.0' }
          { name: 'APP_PUBLIC_URL', value: 'https://${namePrefix}-${env}-prod2.${caeDefaultDomain}' }
          // ⚠️ 'groups' NON è uno scope OIDC valido su Entra (AADSTS650053 → loop di redirect al login).
          // Il default dell'app include 'groups': lo sovrascriviamo. Per i gruppi usa i groupMembershipClaims (claim, non scope).
          { name: 'OIDC_SCOPES', value: 'openid profile email' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 3 }
    }
  }
}

output appFqdn string = app.properties.configuration.ingress.fqdn
output appPrincipalId string = app.identity.principalId
