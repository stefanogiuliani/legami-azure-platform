// Job di collaudo: dall'interno del CAE chiama /health e /check di rebac-authz,
// per validare end-to-end il motore authz (OpenFGA → rebac-authz → decisione) su Azure.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
param rebacUrl string = 'http://${namePrefix}-${env}-rebac-authz'
@secure()
param apiKey string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-rebac-check'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'rebac-check' }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 120
      replicaRetryLimit: 0
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
      secrets: [ { name: 'api-key', value: apiKey } ]
    }
    template: {
      containers: [ {
        name: 'check'
        image: 'curlimages/curl:latest'
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        env: [
          { name: 'REBAC_URL', value: rebacUrl }
          { name: 'API_KEY', secretRef: 'api-key' }
        ]
        command: [ 'sh', '-c' ]
        args: [ 'echo HEALTH:; curl -s -m 10 "$REBAC_URL/health"; echo; echo CHECK:; curl -s -m 10 -X POST "$REBAC_URL/check" -H "x-api-key: $API_KEY" -H "content-type: application/json" -d \'{"user":"user:test@legami.it","action":"can_operate","resource":"app:demo"}\'; echo' ]
      } ]
    }
  }
}
