#!/usr/bin/env sh
set -eu

if [ -z "${CATALOG_ORG_YAML_BASE64:-}" ]; then
  echo "CATALOG_ORG_YAML_BASE64 is required" >&2
  exit 1
fi

node -e "require('fs').writeFileSync('/tmp/backstage-org.yaml', Buffer.from(process.env.CATALOG_ORG_YAML_BASE64, 'base64'))"

exec node packages/backend \
  --config app-config.yaml \
  --config app-config.production.yaml