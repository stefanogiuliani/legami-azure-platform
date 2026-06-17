// DP1 (allestimento negozi) — variante PALESTRA.
// ⚠️ DIVERGE da log1/prod2: dp1 NON è un consumer-kit Postgres. Usa job-store su FILESYSTEM
// (default) con artifact su Azure Files montato in /data, e schema creato idempotente all'init
// → NIENTE Postgres, NIENTE db-onboard, NIENTE migrate-job/alembic. Vedi COORDINATION.md (finding 22:10).
// Vincoli app: memory >=1Gi (LibreOffice headless), scale 1-1 (job-store in-memory/single-worker),
// PYTHONPATH=/app/src già nel Dockerfile, entrypoint apps.api.main:app, porta 8000.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param oidcClientId string
param oidcIssuer string
param oidcScopes string = 'openid profile email'
param oidcEmailClaims string = 'email,preferred_username,upn'
param oidcLogoutEndpoint string = ''
param imageTag string = 'latest'
// GOTCHA 1: URL interno = http://<app> (porta 80), non il targetPort
param pdpUrl string = 'http://${namePrefix}-${env}-platform-admin/api/authz/decide'
@description('Nome del link storage Azure Files sul CAE per i job durevoli di dp1 (artifact).')
param dataStorageName string = 'dp1-data'
@secure()
param oidcSecret string
@secure()
param sessionSecret string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource ci 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: '${namePrefix}-${env}-ci' }

var acr = '${namePrefix}${env}acr.azurecr.io'
var fqdn = '${namePrefix}-${env}-dp1.${cae.properties.defaultDomain}'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-dp1'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'dp1' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${ci.id}': {} } }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 8000, transport: 'auto' }
      registries: [ { server: acr, identity: ci.id } ]
      secrets: [
        { name: 'oidc-secret', value: oidcSecret }
        { name: 'session-secret', value: sessionSecret }
      ]
    }
    template: {
      volumes: [ { name: 'data', storageType: 'AzureFile', storageName: dataStorageName } ]
      containers: [ {
        name: 'dp1'
        image: '${acr}/dp1-app:${imageTag}'
        // >=1Gi obbligatorio: LibreOffice headless (png_render) va OOM con meno.
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          // --- auth / OIDC Entra (opt-in: il PEP→PDP si attiva con AUTH_ENABLED=true) ---
          { name: 'AUTH_ENABLED', value: 'true' }
          { name: 'OIDC_CLIENT_ID', value: oidcClientId }
          { name: 'OIDC_CLIENT_SECRET', secretRef: 'oidc-secret' }
          { name: 'OIDC_ISSUER', value: oidcIssuer }
          { name: 'OIDC_SCOPES', value: oidcScopes }
          { name: 'OIDC_EMAIL_CLAIMS', value: oidcEmailClaims }
          { name: 'OIDC_LOGOUT_ENDPOINT', value: oidcLogoutEndpoint }
          { name: 'SESSION_SECRET', secretRef: 'session-secret' }
          { name: 'APP_PUBLIC_URL', value: 'https://${fqdn}' }
          { name: 'PDP_URL', value: pdpUrl }
          // --- storage: artifact su Azure Files; backend filesystem (default ACA consigliato dall'app) ---
          { name: 'TMP_DIR', value: '/data/dp1_jobs' }
          { name: 'JOB_STORE_BACKEND', value: 'filesystem' }
        ]
        volumeMounts: [ { volumeName: 'data', mountPath: '/data' } ]
      } ]
      // scale 1-1: job-store filesystem è in-memory/single-worker → multi-replica spezzerebbe i job.
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
