// Job: scrive un grant rebac (POST /write, chiave admin) per concedere un'app a un utente.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param rebacUrl string = 'http://${namePrefix}-${env}-rebac-authz'
// pin: fissare a digest al collaudo dev (B6/G2 reproducibility)
param curlImage string = 'curlimages/curl:latest'
param tupleUser string
param tupleRelation string
param tupleObject string
@description('Suffisso per nome job univoco per-app (es. -dp1), così agenti in parallelo non collidono sul singleton.')
param jobSuffix string = ''
param keyVaultName string = '${namePrefix}-${env}-kv'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }
resource appKv 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: '${namePrefix}-${env}-app-kv'
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-rebac-grant${jobSuffix}'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'rebac-grant' }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${appKv.id}': {} }
  }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 120
      replicaRetryLimit: 0
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      secrets: [ { name: 'admin-key', keyVaultUrl: 'https://${keyVaultName}.vault.azure.net/secrets/pdp-admin-api-key', identity: appKv.id } ]
    }
    template: {
      containers: [ {
        name: 'grant'
        image: curlImage
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [
          { name: 'REBAC_URL', value: rebacUrl }
          { name: 'ADMIN_KEY', secretRef: 'admin-key' }
          { name: 'TUSER', value: tupleUser }
          { name: 'TREL', value: tupleRelation }
          { name: 'TOBJ', value: tupleObject }
        ]
        command: [ 'sh', '-c' ]
        args: [ 'echo GRANT:; curl -s -m 10 -X POST "$REBAC_URL/write" -H "x-api-key: $ADMIN_KEY" -H "content-type: application/json" -d \'{"writes":[{"user":"\'"$TUSER"\'","relation":"\'"$TREL"\'","object":"\'"$TOBJ"\'"}]}\'; echo; echo DONE' ]
      } ]
    }
  }
}
