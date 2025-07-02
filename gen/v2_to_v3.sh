#!/bin/bash
set -euo pipefail

VERSION=v18.1.1-ee

BASE_DIR=$(dirname "$(dirname "$0")")
TMP_DIR=/tmp

curl -fsSL \
    -o "${TMP_DIR}/openapi_v2.yml" \
    "https://gitlab.com/gitlab-org/gitlab/-/raw/${VERSION}/doc/api/openapi/openapi_v2.yaml"

# https://swagger.io/specification/v2/#parameter-object
# If type is "file", the consumes MUST be either "multipart/form-data",
# "application/x-www-form-urlencoded" or both and the parameter MUST be in "formData".
sed -i -e 's/type: file/type: string/' "${TMP_DIR}/openapi_v2.yml"

# https://swagger.io/specification/v2/#parameter-object
# The value MUST be one of "string", "number", "integer", "boolean", "array" or "file".
sed -i -e 's/type: text/type: string/' "${TMP_DIR}/openapi_v2.yml"

# The value MUST be one of "string", "number", "integer", "boolean", "array" or "file".
# example: executable
sed -i -e 's/type: symbol/type: string/' "${TMP_DIR}/openapi_v2.yml"

# Convert Swagger 2.0 to OpenAPI 3.0.
swagger2openapi -y -o "${BASE_DIR}/temp/openapi_v3.yml" "${TMP_DIR}/openapi_v2.yml"

# Remove API that contains '()' at URI.
yq 'del(.paths[] | select(. | key | select(. | contains("\\("))))' < "${BASE_DIR}/temp/openapi_v3.yml" > "${BASE_DIR}/temp/openapi_v3_fixed.yml"
mv -f "${BASE_DIR}/temp/openapi_v3_fixed.yml" "${BASE_DIR}/temp/openapi_v3.yml"

# Remove API that contains asterisk in path.
yq 'del(.paths[] | select(. | key | select(. | contains("*"))))' < "${BASE_DIR}/temp/openapi_v3.yml" > "${BASE_DIR}/temp/openapi_v3_fixed.yml"
mv -f "${BASE_DIR}/temp/openapi_v3_fixed.yml" "${BASE_DIR}/temp/openapi_v3.yml"

# Remove API that contains response that has `@id` and `id`.
sed -i \
    -e '/^  "\/api\/v4\/groups\/{id}\/-\/packages\/nuget\/metadata\/\*package_name\/index"/{
    :a
    N
    /operationId/!ba
    d
}' "${BASE_DIR}/temp/openapi_v3.yml"
sed -i \
    -e '/^  "\/api\/v4\/groups\/{id}\/-\/packages\/nuget\/metadata\/\*package_name\/\*package_version"/{
    :a
    N
    /operationId/!ba
    d
}' "${BASE_DIR}/temp/openapi_v3.yml"
sed -i \
    -e '/^  "\/api\/v4\/projects\/{id}\/packages\/nuget\/metadata\/\*package_name\/index"/{
    :a
    N
    /operationId/!ba
    d
}' "${BASE_DIR}/temp/openapi_v3.yml"
sed -i \
    -e '/^  "\/api\/v4\/projects\/{id}\/packages\/nuget\/metadata\/\*package_name\/\*package_version"/{
    :a
    N
    /operationId/!ba
    d
}' "${BASE_DIR}/temp/openapi_v3.yml"

# Fix type array.
# Assume array type that contains list description.
yq '.paths[].*.responses.* |= select(.description | test("list|tree")) |= select(. | has("content")) |= .content[] |= select(.schema.type != "array") |= .schema = {"type": "array", "items": .schema}'  < "${BASE_DIR}/temp/openapi_v3.yml" > "${BASE_DIR}/temp/openapi_v3_fixed.yml"
mv -f "${BASE_DIR}/temp/openapi_v3_fixed.yml" "${BASE_DIR}/temp/openapi_v3.yml"
