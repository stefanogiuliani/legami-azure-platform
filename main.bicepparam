using './main.bicep'

param namePrefix = 'legami'
param env = 'dev'
param location = 'northeurope'
param kvPurgeProtection = false // palestra: vault purgabile (vedi memoria azure-gym)
param ingressPublic = true
param pgSku = 'Standard_B1ms'
param pgAdminUser = 'pgadmin'
param pgAdminPassword = 'PLACEHOLDER_PASSED_AT_CLI'
param githubRepo = 'stefanogiuliani/legami-azure-platform'
