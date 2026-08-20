#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA="$ROOT/stacks"

usage() {
  cat <<'EOF'
Usage: ./scripts/configure-stack.sh --stack <name> [options]

Options:
  --stack <name>           Pulumi stack to create or update
  --location <region>      Azure region (default: uksouth)
  --resource-group <name>  Resource group (default: backstage-<stack>-rg)
  --org-file <path>        Private production User and Group catalog YAML
  -h, --help               Show this help

Secrets can be supplied with GITHUB_TOKEN, AUTH_GITHUB_CLIENT_SECRET, and
AZDO_PAT. AUTH_GITHUB_CLIENT_ID, GITHUB_ORG, TECH_RADAR_URL,
AZURE_DEVOPS_ORGANIZATION, AZURE_DEVOPS_PROJECT, and AZURE_DEVOPS_REPOSITORY
can also be supplied. CATALOG_ORG_FILE can supply the --org-file path. Missing
values are prompted without writing secret values to a plaintext stack file.
EOF
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" ]]; then
    echo "Missing value for $option" >&2
    usage >&2
    exit 2
  fi
}

prompt_value() {
  local variable_name="$1"
  local prompt="$2"
  local secret="${3:-false}"
  local value="${!variable_name:-}"

  if [[ -z "$value" ]]; then
    if [[ "$secret" == "true" ]]; then
      read -r -s -p "$prompt: " value >&2
      echo >&2
    else
      read -r -p "$prompt: " value >&2
    fi
  fi

  if [[ -z "$value" ]]; then
    echo "$prompt cannot be empty" >&2
    exit 2
  fi

  printf '%s' "$value"
}

STACK=""
LOCATION="${AZURE_LOCATION:-uksouth}"
RESOURCE_GROUP="${RESOURCE_GROUP_NAME:-}"
ORG_FILE="${CATALOG_ORG_FILE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      require_value "$1" "${2:-}"
      STACK="$2"
      shift 2
      ;;
    --location)
      require_value "$1" "${2:-}"
      LOCATION="$2"
      shift 2
      ;;
    --resource-group)
      require_value "$1" "${2:-}"
      RESOURCE_GROUP="$2"
      shift 2
      ;;
    --org-file)
      require_value "$1" "${2:-}"
      ORG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$STACK" ]]; then
  echo "--stack is required" >&2
  usage >&2
  exit 2
fi

for command in pulumi; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

STACK_LEAF="${STACK##*/}"
ENVIRONMENT_NAME="$(printf '%s' "$STACK_LEAF" | tr '[:upper:]_' '[:lower:]-' | tr -cd '[:alnum:]-')"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:0:18}"
if [[ -z "$ENVIRONMENT_NAME" ]]; then
  echo "The stack name must contain at least one letter or number" >&2
  exit 2
fi

if [[ -z "$RESOURCE_GROUP" ]]; then
  RESOURCE_GROUP="backstage-${ENVIRONMENT_NAME}-rg"
fi

GITHUB_OAUTH_CLIENT_ID="$(prompt_value AUTH_GITHUB_CLIENT_ID "GitHub OAuth client ID")"
GITHUB_ORG="$(prompt_value GITHUB_ORG "GitHub organization")"
GITHUB_INTEGRATION_TOKEN="$(prompt_value GITHUB_TOKEN "GitHub integration token" true)"
GITHUB_OAUTH_SECRET="$(prompt_value AUTH_GITHUB_CLIENT_SECRET "GitHub OAuth client secret" true)"
AZURE_DEVOPS_PAT="$(prompt_value AZDO_PAT "Azure DevOps PAT" true)"
TECH_RADAR_URL="$(prompt_value TECH_RADAR_URL "Tech Radar URL")"
AZURE_DEVOPS_ORGANIZATION="$(prompt_value AZURE_DEVOPS_ORGANIZATION "Azure DevOps organization")"
AZURE_DEVOPS_PROJECT="$(prompt_value AZURE_DEVOPS_PROJECT "Azure DevOps project")"
AZURE_DEVOPS_REPOSITORY="$(prompt_value AZURE_DEVOPS_REPOSITORY "Azure DevOps repository")"
ORG_FILE="$(prompt_value ORG_FILE "Production organization catalog file")"

if [[ ! -r "$ORG_FILE" ]]; then
  echo "Organization catalog file is not readable: $ORG_FILE" >&2
  exit 2
fi

CATALOG_ORG_YAML_BASE64="$(base64 < "$ORG_FILE" | tr -d '\n')"

cd "$INFRA"
pulumi stack select "$STACK" --create
pulumi config set azure-native:location "$LOCATION" --plaintext
pulumi config set deploymentLocation "$LOCATION" --plaintext
pulumi config set environmentName "$ENVIRONMENT_NAME" --plaintext
pulumi config set resourceGroupName "$RESOURCE_GROUP" --plaintext
pulumi config set githubOAuthClientId "$GITHUB_OAUTH_CLIENT_ID" --plaintext
pulumi config set githubOrg "$GITHUB_ORG" --plaintext
pulumi config set githubToken "$GITHUB_INTEGRATION_TOKEN" --secret
pulumi config set githubOAuthClientSecret "$GITHUB_OAUTH_SECRET" --secret
pulumi config set azureDevOpsPat "$AZURE_DEVOPS_PAT" --secret
pulumi config set techRadarUrl "$TECH_RADAR_URL" --secret
pulumi config set azureDevOpsOrganization "$AZURE_DEVOPS_ORGANIZATION" --plaintext
pulumi config set azureDevOpsProject "$AZURE_DEVOPS_PROJECT" --plaintext
pulumi config set azureDevOpsRepository "$AZURE_DEVOPS_REPOSITORY" --plaintext
pulumi config set catalogOrgYamlBase64 "$CATALOG_ORG_YAML_BASE64" --secret

unset GITHUB_INTEGRATION_TOKEN GITHUB_OAUTH_SECRET AZURE_DEVOPS_PAT TECH_RADAR_URL
unset AZURE_DEVOPS_ORGANIZATION AZURE_DEVOPS_PROJECT AZURE_DEVOPS_REPOSITORY
unset CATALOG_ORG_YAML_BASE64

echo "Configured Pulumi stack '$STACK' for resource group '$RESOURCE_GROUP' in '$LOCATION'."
echo "Run ./deploy.sh --stack '$STACK' from the repository root to deploy it."