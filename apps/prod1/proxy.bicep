// PROD1 proxy (Caddy) — Container App PUBBLICO (unica origin). Replica lo split per path del VPS:
//   /api/* /auth/* /login /logout /health -> backend interno;  tutto il resto -> frontend interno.
// Config Caddy scritta inline a runtime (niente immagine custom). GOTCHA: target interni = porta 80.
// ⭐ GOTCHA 2 (Caddy v2 + ingress interno ACA): reverse_proxy in Caddy v2 PRESERVA l'Host del client →
// l'upstream riceve Host=<fqdn-esterno-proxy>, ma l'ingress INTERNO di ACA instrada PER Host → non match → 404
// su tutto (anche se gli upstream sono sani). FIX: `header_up Host <nome-interno>` per riscrivere l'Host.
// PATTERN RIUSABILE per ogni app FE/BE-split (vedi runbook P3).
param namePrefix string
param env string
param location string = resourceGroup().location
param caeName string = '${namePrefix}-${env}-cae'

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' existing = { name: caeName }

var apiHost = '${namePrefix}-${env}-prod1-api'
var webHost = '${namePrefix}-${env}-prod1-web'
var caddyfile = ':8080 {\n@api path /api/* /auth/* /login /logout /health /healthz\nhandle @api {\nreverse_proxy ${apiHost}:80 {\nheader_up Host ${apiHost}\n}\n}\nhandle {\nreverse_proxy ${webHost}:80 {\nheader_up Host ${webHost}\n}\n}\n}\n'

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: '${namePrefix}-${env}-prod1'
  location: location
  tags: { project: 'INT101', env: env, owner: 'DNAI', managedBy: 'bicep', app: 'prod1-proxy' }
  properties: {
    managedEnvironmentId: cae.id
    configuration: {
      ingress: { external: true, targetPort: 8080, transport: 'auto' }
    }
    template: {
      containers: [ {
        name: 'proxy'
        image: 'caddy:2-alpine'
        resources: { cpu: json('0.25'), memory: '0.5Gi' }
        command: [ 'sh', '-c' ]
        args: [ 'printf \'${caddyfile}\' > /etc/caddy/Caddyfile && exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile' ]
      } ]
      scale: { minReplicas: 1, maxReplicas: 2 }
    }
  }
}

output fqdn string = app.properties.configuration.ingress.fqdn
