param namePrefix string
param env string
param location string
param tenantId string = subscription().tenantId
@description('Purge protection del Key Vault. true = ambienti reali (es. prod di Legami); false = palestra, così il vault è purgabile e distruggi/ricostruisci senza bruciare il nome per 7 giorni.')
param purgeProtection bool = true

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${namePrefix}-${env}-kv'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  properties: {
    sku: { family: 'A', name: 'standard' }
    tenantId: tenantId
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
    // Azure rifiuta enablePurgeProtection:false esplicito → quando off lo si OMETTE (null)
    enablePurgeProtection: purgeProtection ? true : null
  }
}

output keyVaultId string = kv.id
output keyVaultName string = kv.name
