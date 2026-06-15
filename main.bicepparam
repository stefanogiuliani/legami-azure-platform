using './main.bicep'

param namePrefix = 'legami'
param env = 'prod1'
param location = 'northeurope'
param ingressPublic = true
param pgSku = 'Standard_B1ms'
param pgAdminUser = 'pgadmin'
param pgAdminPassword = 'PLACEHOLDER_PASSED_AT_CLI'
param githubRepo = 'stefanogiuliani/legami-azure-platform'
