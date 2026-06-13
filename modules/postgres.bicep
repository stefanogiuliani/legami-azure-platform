param namePrefix string
param env string
param location string
param pgSku string
param adminUser string
@secure()
param adminPassword string
param peSubnetId string
param vnetId string

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2023-12-01-preview' = {
  name: '${namePrefix}-${env}-pg'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  sku: { name: pgSku, tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    storage: { storageSizeGB: 32 }
    backup: { backupRetentionDays: 7 }
    network: { publicNetworkAccess: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
  }
}

resource ext 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2023-12-01-preview' = {
  parent: pg
  name: 'azure.extensions'
  properties: { value: 'PG_TRGM,UNACCENT', source: 'user-override' }
}

resource dns 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.postgres.database.azure.com'
  location: 'global'
}
resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: dns
  name: '${namePrefix}-${env}-pg-dnslink'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: vnetId } }
}

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${namePrefix}-${env}-pg-pe'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [ {
      name: 'pg'
      properties: { privateLinkServiceId: pg.id, groupIds: [ 'postgresqlServer' ] }
    } ]
  }
}
resource peDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: pe
  name: 'default'
  properties: { privateDnsZoneConfigs: [ { name: 'pg', properties: { privateDnsZoneId: dns.id } } ] }
}

output pgFqdn string = pg.properties.fullyQualifiedDomainName
output pgName string = pg.name
