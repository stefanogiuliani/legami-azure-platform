param namePrefix string
param env string
param location string

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${namePrefix}-${env}-vnet'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep' }
  properties: {
    addressSpace: { addressPrefixes: ['10.20.0.0/16'] }
    subnets: [
      {
        name: 'snet-aca'
        properties: {
          addressPrefix: '10.20.0.0/23'
          delegations: [ { name: 'aca', properties: { serviceName: 'Microsoft.App/environments' } } ]
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.20.2.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

output vnetId string = vnet.id
output acaSubnetId string = vnet.properties.subnets[0].id
output peSubnetId string = vnet.properties.subnets[1].id
