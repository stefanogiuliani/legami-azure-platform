#!/usr/bin/env bash
# Registrazione Entra riusabile per una app del portfolio (gym).
# Crea app-reg + Expose API (api://<appId>/access_as_user) + requestedAccessTokenVersion=2 + SP + secret.
# Uso (dalla root iac-dryrun, host con docker):
#   ./apps/_shared/entra-app-reg.sh <app> <fqdn> [callback]
#   es: ./apps/_shared/entra-app-reg.sh dp1 legami-dev-dp1.orangeforest-0e4fc967.northeurope.azurecontainerapps.io
#   launcher (NextAuth): callback /api/auth/callback/microsoft-entra-id
# Output: scrive APPID/SCOPE/SECRET a stdout e li APPENDE a /tmp/<app>-gym.env (non committare).
set -euo pipefail
APP="${1:?uso: $0 <app> <fqdn> [callback]}"
FQDN="${2:?manca fqdn}"
CB="${3:-/auth/callback}"
HERE="$(cd "$(dirname "$0")/../.." && pwd)"   # iac-dryrun
AZ() { docker run --rm -v "$HERE/.azure":/root/.azure mcr.microsoft.com/azure-cli az "$@"; }

C=$(AZ ad app create --display-name "LEGAMI ${APP} (dev)" --sign-in-audience AzureADMyOrg \
  --web-redirect-uris "https://${FQDN}${CB}" "https://${FQDN}/" \
  --query "{appId:appId,objId:id}" -o json 2>/dev/null | tail -4)
APPID=$(echo "$C" | python3 -c "import sys,json;print(json.load(sys.stdin)['appId'])")
OBJID=$(echo "$C" | python3 -c "import sys,json;print(json.load(sys.stdin)['objId'])")
SCOPE_ID=$(python3 -c "import uuid;print(uuid.uuid4())")

AZ rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/${OBJID}" \
  --headers "Content-Type=application/json" \
  --body "{\"identifierUris\":[\"api://${APPID}\"],\"api\":{\"requestedAccessTokenVersion\":2,\"oauth2PermissionScopes\":[{\"id\":\"${SCOPE_ID}\",\"adminConsentDescription\":\"Access ${APP} as the signed-in user\",\"adminConsentDisplayName\":\"Access ${APP}\",\"isEnabled\":true,\"type\":\"User\",\"userConsentDescription\":\"Access ${APP} as you\",\"userConsentDisplayName\":\"Access ${APP}\",\"value\":\"access_as_user\"}]}}" >/dev/null 2>&1

AZ ad sp create --id "$APPID" >/dev/null 2>&1 || true
CSECRET=$(AZ ad app credential reset --id "$APPID" --display-name gym --query password -o tsv 2>/dev/null | tail -1)

OUT="/tmp/${APP}-gym.env"; umask 077
# uppercase portabile (macOS ha bash 3.2 → niente ${VAR^^})
APP_UC=$(printf '%s' "$APP" | tr '[:lower:]-' '[:upper:]_')
{ echo "${APP_UC}_APPID=${APPID}"; echo "${APP_UC}_CSECRET=${CSECRET}"; echo "${APP_UC}_SCOPE=api://${APPID}/access_as_user"; } >> "$OUT"
echo "OK ${APP}: appId=${APPID}  scope=api://${APPID}/access_as_user  (secret in ${OUT})"
