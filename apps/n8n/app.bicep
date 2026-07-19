// n8n condiviso (servizio di piattaforma): una sola istanza per tutte le app.
// Ingress PUBBLICO (serve per i webhook in ingresso), DB sul Postgres PRIVATO
// (db 'n8n' creato dal job di onboarding). La N8N_ENCRYPTION_KEY è il segreto
// critico: cifra le credenziali salvate — va preservata tra i redeploy.
// In palestra i segreti sono inline (Container App secret store); per il prod
// di Legami la encryption-key va in Key Vault (pattern keyVaultUrl, vedi prod2).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param pgHost string = '${namePrefix}-${env}-pg.postgres.database.azure.com'
param dbName string = 'n8n'
param dbUser string = 'n8n'
@secure()
param dbPassword string
@secure()
param encryptionKey string
// pin: fissare a digest al collaudo dev (B6/G2 reproducibility)
param n8nImage string = 'n8nio/n8n:latest'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

resource n8n 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-n8n'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', svc: 'n8n' }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 5678, transport: 'auto' }
      secrets: [
        { name: 'db-password', value: dbPassword }
        { name: 'encryption-key', value: encryptionKey }
      ]
    }
    template: {
      containers: [ {
        name: 'n8n'
        image: n8nImage
        resources: { cpu: json('0.5'), memory: '1Gi' }
        env: [
          { name: 'DB_TYPE', value: 'postgresdb' }
          { name: 'DB_POSTGRESDB_HOST', value: pgHost }
          { name: 'DB_POSTGRESDB_PORT', value: '5432' }
          { name: 'DB_POSTGRESDB_DATABASE', value: dbName }
          { name: 'DB_POSTGRESDB_USER', value: dbUser }
          { name: 'DB_POSTGRESDB_PASSWORD', secretRef: 'db-password' }
          { name: 'DB_POSTGRESDB_SSL_ENABLED', value: 'true' }
          { name: 'DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED', value: 'false' }
          { name: 'N8N_ENCRYPTION_KEY', secretRef: 'encryption-key' }
          { name: 'N8N_HOST', value: '${namePrefix}-${env}-n8n.${cae.properties.defaultDomain}' }
          { name: 'N8N_PROTOCOL', value: 'https' }
          { name: 'N8N_PORT', value: '5678' }
          { name: 'N8N_PROXY_HOPS', value: '1' }
          { name: 'WEBHOOK_URL', value: 'https://${namePrefix}-${env}-n8n.${cae.properties.defaultDomain}/' }
          { name: 'GENERIC_TIMEZONE', value: 'Europe/Rome' }
        ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
}

output n8nFqdn string = n8n.properties.configuration.ingress.fqdn
