#!/bin/bash
set -euo pipefail

VERSION=v18.1.1-ee

BASE_DIR=$(dirname "$(dirname "$0")")
TMP_DIR=/tmp

curl -fsSLO \
    --output-dir "${TMP_DIR}" \
    "https://gitlab.com/gitlab-org/gitlab/-/raw/${VERSION}/doc/api/issues.md"

# Convert markdown to OpenAPI schema.
uv run "${BASE_DIR}/gen/md_to_schema.py" "${TMP_DIR}/issues.md" > "${TMP_DIR}/issues.json"

# Re-format YAML.
yq -r '... style=""' < "${TMP_DIR}/issues.json" > "${BASE_DIR}/temp/issues.yml"

# https://swagger.io/specification/v2/#parameter-object
# The value MUST be one of "string", "number", "integer", "boolean", "array" or "file".
sed -i -e 's/type: datetime/type: string/' "${BASE_DIR}/temp/issues.yml"

# https://swagger.io/specification/v2/#parameter-object
# The value MUST be one of "string", "number", "integer", "boolean", "array" or "file".
sed -i -e 's/type: hash/type: string/' "${BASE_DIR}/temp/issues.yml"

# https://swagger.io/specification/v2/#parameter-object
# The value MUST be one of "string", "number", "integer", "boolean", "array" or "file".
sed -i -e 's/type: integer\/string/type: string/' "${BASE_DIR}/temp/issues.yml"

# https://swagger.io/specification/v2/#parameter-object
# The value MUST be one of "string", "number", "integer", "boolean", "array" or "file".
sed -i -e 's/type: file/type: string/' "${BASE_DIR}/temp/issues.yml"
