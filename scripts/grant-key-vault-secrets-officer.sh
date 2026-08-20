#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA="$ROOT/stacks"
ROLE_NAME="Key Vault Secrets Officer"

usage() {
  cat <<'EOF'
Usage: ./scripts/grant-key-vault-secrets-officer.sh --stack <name> (--upn <UPN> | --login-hint <email>) [--yes]

Grants the built-in Key Vault Secrets Officer role at the Key Vault scope for
the Key Vault provisioned by the selected Pulumi stack.

Options:
  --stack <name>        Existing Pulumi stack whose Key Vault is targeted
  --upn <UPN>           UPN of the user to grant access to
  --login-hint <email>  Email address used to find the target guest user after
                        signing in once as the role operator
  --yes                 Skip the confirmation prompt
  -h, --help            Show this help

For guest Microsoft accounts, prefer --login-hint. The script signs in once as
an operator, then resolves the guest's full Entra UPN, such as
name_live.com#EXT#@tenant.onmicrosoft.com, in the Key Vault tenant.
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

STACK=""
TARGET_UPN=""
LOGIN_HINT=""
AUTO_APPROVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stack)
      require_value "$1" "${2:-}"
      STACK="$2"
      shift 2
      ;;
    --upn)
      require_value "$1" "${2:-}"
      TARGET_UPN="$2"
      shift 2
      ;;
    --login-hint)
      require_value "$1" "${2:-}"
      LOGIN_HINT="$2"
      shift 2
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
  echo "--stack is required" >&2
  usage >&2
  exit 2
fi

if [[ -n "$TARGET_UPN" && -n "$LOGIN_HINT" ]]; then
  echo "Use either --upn or --login-hint, not both" >&2
  exit 2
fi

if [[ -z "$TARGET_UPN" && -z "$LOGIN_HINT" ]]; then
  echo "Either --upn or --login-hint is required" >&2
  usage >&2
  exit 2
fi

for command in az pulumi; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

echo "Sign in as an operator with permission to assign roles on the target Key Vault." >&2
az login --use-device-code >/dev/null

if [[ -n "$LOGIN_HINT" ]]; then
  TARGET_UPN="$(az ad user list \
    --filter "mail eq '$LOGIN_HINT' or otherMails/any(address:address eq '$LOGIN_HINT')" \
    --query '[0].userPrincipalName' \
    --output tsv)"
fi

if [[ -z "$TARGET_UPN" ]]; then
  echo "Could not resolve the target user in the operator's Entra tenant" >&2
  exit 1
fi

echo "Resolved target user UPN: $TARGET_UPN"

cd "$INFRA"
VAULT_NAME="$(pulumi stack output keyVaultName --stack "$STACK")"
if [[ -z "$VAULT_NAME" ]]; then
  echo "Could not resolve keyVaultName from Pulumi stack '$STACK'" >&2
  exit 1
fi

VAULT_ID="$(pulumi stack output keyVaultId --stack "$STACK" 2>/dev/null || true)"
if [[ -z "$VAULT_ID" ]]; then
  VAULT_ID="$(az keyvault show --name "$VAULT_NAME" --query id --output tsv)"
fi
if [[ -z "$VAULT_ID" ]]; then
  echo "Could not resolve the resource ID for Key Vault '$VAULT_NAME'" >&2
  exit 1
fi

TARGET_OBJECT_ID="$(az ad user show --id "$TARGET_UPN" --query id --output tsv)"
if [[ -z "$TARGET_OBJECT_ID" ]]; then
  echo "Could not resolve '$TARGET_UPN' in the operator's Entra tenant" >&2
  exit 1
fi

EXISTING_ASSIGNMENTS="$(az role assignment list \
  --assignee "$TARGET_OBJECT_ID" \
  --role "$ROLE_NAME" \
  --scope "$VAULT_ID" \
  --query 'length(@)' \
  --output tsv)"

if [[ "$EXISTING_ASSIGNMENTS" != "0" ]]; then
  echo "'$TARGET_UPN' already has '$ROLE_NAME' on Key Vault '$VAULT_NAME'."
  exit 0
fi

echo "Target Key Vault: $VAULT_NAME"
echo "Target user UPN: $TARGET_UPN"
echo "Role: $ROLE_NAME"

if [[ "$AUTO_APPROVE" != "true" ]]; then
  read -r -p "Grant this role? [y/N] " confirmation >&2
  if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
    echo "No role assignment was created."
    exit 0
  fi
fi

az role assignment create \
  --assignee-object-id "$TARGET_OBJECT_ID" \
  --assignee-principal-type User \
  --role "$ROLE_NAME" \
  --scope "$VAULT_ID" \
  --output none

echo "Granted '$ROLE_NAME' to '$TARGET_UPN' on Key Vault '$VAULT_NAME'."