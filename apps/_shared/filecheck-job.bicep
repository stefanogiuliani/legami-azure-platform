// Job di collaudo: monta un Azure File share (via il link del CAE) come volume e ci scrive.
// Serve a validare il pattern "Azure Files montato come volume" per parsly/LOG1/DP1.
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'
@description('Nome del link storage sul CAE (es. parsly-data) — creato dal modulo storage.')
param storageName string

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: caeName
}

resource job 'Microsoft.App/jobs@2024-03-01' = {
  name: '${namePrefix}-${env}-filecheck'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', job: 'filecheck' }
  properties: {
    environmentId: cae.id
    configuration: {
      triggerType: 'Manual'
      replicaTimeout: 300
      replicaRetryLimit: 1
      manualTriggerConfig: { parallelism: 1, replicaCompletionCount: 1 }
    }
    template: {
      volumes: [ { name: 'data', storageType: 'AzureFile', storageName: storageName } ]
      containers: [ {
        name: 'filecheck'
        image: 'alpine:3'
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        command: [ '/bin/sh', '-c' ]
        args: [ 'echo "filecheck OK $(date -u)" > /data/filecheck.txt; echo "--- contenuto /data ---"; ls -la /data; echo "--- file ---"; cat /data/filecheck.txt' ]
        volumeMounts: [ { volumeName: 'data', mountPath: '/data' } ]
      } ]
    }
  }
}
