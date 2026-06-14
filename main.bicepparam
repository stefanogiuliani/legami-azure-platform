using './main.bicep'

param namePrefix = 'legami'
param env = 'prod1'
param location = 'westeurope'
param ingressPublic = true
param pgSku = 'Standard_B1ms'
param pgAdminUser = 'pgadmin'
param pgAdminPassword = 'PLACEHOLDER_PASSED_AT_CLI'
param githubRepo = 'DNAIOFFICE/legami-azure-platform'
