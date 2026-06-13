targetScope = 'resourceGroup'

param namePrefix string
param env string
param location string
param ingressPublic bool
param pgSku string
param pgAdminUser string
@secure()
param pgAdminPassword string
param githubRepo string

module network './modules/network.bicep' = {
  name: 'network'
  params: { namePrefix: namePrefix, env: env, location: location }
}
module obs './modules/observability.bicep' = {
  name: 'obs'
  params: { namePrefix: namePrefix, env: env, location: location }
}
module kv './modules/keyvault.bicep' = {
  name: 'kv'
  params: { namePrefix: namePrefix, env: env, location: location }
}
module acr './modules/registry.bicep' = {
  name: 'acr'
  params: { namePrefix: namePrefix, env: env, location: location }
}
module ci './modules/ci-identity.bicep' = {
  name: 'ci'
  params: { namePrefix: namePrefix, env: env, location: location, acrId: acr.outputs.acrId, githubRepo: githubRepo }
}
module cae './modules/container-env.bicep' = {
  name: 'cae'
  params: {
    namePrefix: namePrefix, env: env, location: location
    acaSubnetId: network.outputs.acaSubnetId
    logWorkspaceName: obs.outputs.workspaceName
  }
}
module pg './modules/postgres.bicep' = {
  name: 'pg'
  params: {
    namePrefix: namePrefix, env: env, location: location, pgSku: pgSku
    adminUser: pgAdminUser, adminPassword: pgAdminPassword
    peSubnetId: network.outputs.peSubnetId
    vnetId: network.outputs.vnetId
  }
}
