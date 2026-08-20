#!/usr/bin/env bash
#
# Rebuild the Backstage backend bundle and deploy it to Azure with Pulumi.
#
# Usage:
#   ./deploy.sh --stack <name> --configure  # configure and deploy a new environment
#   ./deploy.sh --stack <name>              # build and deploy an existing stack
#   ./deploy.sh --stack <name> --preview    # build and preview only
#
set -euo pipefail

# Always run relative to this script's directory (the backstage repo root).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA="$ROOT/stacks"
CONFIGURE_SCRIPT="$ROOT/scripts/configure-stack.sh"

usage() {
  cat <<'EOF'
Usage: ./deploy.sh --stack <name> [options]

Options:
  --configure              Create/select and configure the stack first
  --location <region>      Region passed to --configure (default: uksouth)
  --resource-group <name>  Resource group passed to --configure
  --org-file <path>        Private production User and Group catalog YAML
  --preview                Run pulumi preview instead of pulumi up
  --skip-build             Skip dependency install, type-check, and build
  --yes                    Skip Pulumi's deployment confirmation
  -h, --help               Show this help
EOF
}

require_value() {
  if [[ -z "${2:-}" ]]; then
    echo "Missing value for $1" >&2
    usage >&2
    exit 2
  fi
}

STACK=""
LOCATION="${AZURE_LOCATION:-uksouth}"
RESOURCE_GROUP="${RESOURCE_GROUP_NAME:-}"
ORG_FILE="${CATALOG_ORG_FILE:-}"
CONFIGURE=false
PREVIEW=false
SKIP_BUILD=false
AUTO_APPROVE=false

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
    --configure)
      CONFIGURE=true
      shift
      ;;
    --preview)
      PREVIEW=true
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --yes)
      AUTO_APPROVE=true
      shift
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
  echo "--stack is required to avoid deploying to the wrong environment" >&2
  usage >&2
  exit 2
fi

if [[ "$CONFIGURE" == "true" ]]; then
  configure_args=(--stack "$STACK" --location "$LOCATION")
  if [[ -n "$RESOURCE_GROUP" ]]; then
    configure_args+=(--resource-group "$RESOURCE_GROUP")
  fi
  if [[ -n "$ORG_FILE" ]]; then
    configure_args+=(--org-file "$ORG_FILE")
  fi
  "$CONFIGURE_SCRIPT" "${configure_args[@]}"
fi

cd "$ROOT"

if [[ "$SKIP_BUILD" == "false" ]]; then
  echo "==> Installing dependencies (immutable)"
  yarn install --immutable

  echo "==> Type-checking"
  yarn tsc

  echo "==> Building frontend + backend (produces app dist + skeleton.tar.gz / bundle.tar.gz)"
  yarn build:all
fi

echo "==> Deploying with Pulumi"
cd "$INFRA"
pulumi stack select "$STACK"
if [[ "$PREVIEW" == "true" ]]; then
  pulumi preview
else
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    pulumi up --yes
  else
    pulumi up
  fi
  BACKSTAGE_URL="$(pulumi stack output backstageWebAppUrl)"
  echo "==> Backstage: $BACKSTAGE_URL"
  echo "==> GitHub OAuth callback: $BACKSTAGE_URL/api/auth/github/handler/frame"
fi

echo "==> Done"
