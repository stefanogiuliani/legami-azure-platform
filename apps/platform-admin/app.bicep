// platform-admin (PDP + admin UI) come Container App PUBBLICA (admin UI per umani +
// /api/authz/decide chiamato dalle app). Modalità ENTRA + REBAC. Pull ACR via identità CI.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param rebacUrl string = 'http://${namePrefix}-${env}-rebac-authz'
param entraClientId string
param entraTenantId string
@secure()
param entraClientSecret string
@secure()
param authSecret string
@secure()
param rebacApiKey string
@secure()
param serverActionsKey string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-ci'
}

var acr = '${namePrefix}${env}acr.azurecr.io'
var fqdn = '${namePrefix}-${env}-platform-admin.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-platform-admin'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', svc: 'platform-admin' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${ci.id}': {} }
  }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 3000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'auth-secret', value: authSecret }
        { name: 'entra-secret', value: entraClientSecret }
        { name: 'rebac-key', value: rebacApiKey }
        { name: 'sa-key', value: serverActionsKey }
      ]
    }
    template: {
      containers: [ {
        name: 'platform-admin'
        image: '${acr}/platform-admin:latest'
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'AUTH_SECRET', secretRef: 'auth-secret' }
          { name: 'AUTH_URL', value: 'https://${fqdn}' }
          { name: 'AUTH_TRUST_HOST', value: 'true' }
          { name: 'NEXT_SERVER_ACTIONS_ENCRYPTION_KEY', secretRef: 'sa-key' }
          { name: 'AUTH_IDP_TYPE', value: 'entra' }
          { name: 'AUTHZ_MODE', value: 'rebac' }
          { name: 'AUTH_ENTRA_CLIENT_ID', value: entraClientId }
          { name: 'AUTH_ENTRA_CLIENT_SECRET', secretRef: 'entra-secret' }
          { name: 'AUTH_ENTRA_TENANT_ID', value: entraTenantId }
          { name: 'REBAC_AUTHZ_URL', value: rebacUrl }
          { name: 'REBAC_AUTHZ_API_KEY', secretRef: 'rebac-key' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
