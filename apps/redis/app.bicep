// Redis self-hosted come Container App INTERNA (cache, non persistente).
// Servizio condiviso di piattaforma: raggiungibile solo dalle app dentro il CAE
// all'hostname '<namePrefix>-<env>-redis' sulla porta 6379. Nessun ingress pubblico.
// Template separato (deploy autonomo) → non ri-valida le foundations.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

resource redis 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-redis'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', svc: 'redis' }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      // TCP, solo interno: nessuna esposizione su internet
      ingress: {
        external: false
        transport: 'tcp'
        targetPort: 6379
        exposedPort: 6379
      }
    }
    template: {
      containers: [ {
        name: 'redis'
        image: 'redis:7-alpine'
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        // cache pura: niente persistenza su disco (no RDB, no AOF)
        command: [ 'redis-server', '--save', '', '--appendonly', 'no' ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output redisHost string = redis.name
output redisPort int = 6379
