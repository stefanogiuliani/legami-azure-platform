// Storage condiviso: un Storage Account + un file share per ogni app che scrive
// file su disco, ciascuno linkato al Container Apps Environment così le app
// possono montarlo come volume (Azure Files = il "volume:" durevole su Azure).
param namePrefix string
param env string
param location string
@description('Nome del Container Apps Environment a cui agganciare i file share.')
param caeName string
@description('Un file share per app con stato su disco (parsly, LOG1, DP1).')
param shares array = [
  'parsly-data'
  'log1-data'
  'dp1-data'
]
@description('Quota per share in GiB.')
param shareQuotaGb int = 16

resource sa 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${namePrefix}${env}st'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    largeFileSharesState: 'Enabled'
  }
}

resource fileSvc 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: sa
  name: 'default'
}

resource share 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-05-01' = [for s in shares: {
  parent: fileSvc
  name: s
  properties: {
    shareQuota: shareQuotaGb
    enabledProtocols: 'SMB'
  }
}]

// CAE già esistente (creato in P0): vi aggancio i file share
resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

// SICUREZZA (B6, hardening 2c): questa risorsa (managedEnvironments/storages) richiede accountKey,
// non supporta keyVaultUrl — resta così di necessità, non per pigrizia. Il valore è risolto da ARM
// a deploy-time via listKeys() e non transita mai come parametro né come secret leggibile dall'app;
// il rischio reale (SA key passata come env a platform-admin) è chiuso a parte col KV reference 'platform-admin-sa-key'.
resource caeStorage 'Microsoft.App/managedEnvironments/storages@2024-03-01' = [for (s, i) in shares: {
  parent: cae
  name: s
  properties: {
    azureFile: {
      accountName: sa.name
      accountKey: sa.listKeys().keys[0].value
      shareName: s
      accessMode: 'ReadWrite'
    }
  }
  dependsOn: [ share ]
}]

output storageAccountName string = sa.name
output shareNames array = shares
