#!/bin/bash
set -euo pipefail

VERSION=v18.1.0-ee

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
swagger2openapi -y -o "${TMP_DIR}/openapi_v3.yml" "${TMP_DIR}/openapi_v2.yml"

# Remove API that contains '()' at URI.
sed -i \
    -e '/^  "/{
    /\\(/!b
    :a
    N
    /operationId/!ba
    d
}' "${TMP_DIR}/openapi_v3.yml"

# Remove API that contains response that has `@id` and `id`.
sed -i \
    -e '/^  "\/api\/v4\/groups\/{id}\/-\/packages\/nuget\/metadata\/\*package_name\/index"/{
    :a
    N
    /operationId/!ba
    d
}' "${TMP_DIR}/openapi_v3.yml"
sed -i \
    -e '/^  "\/api\/v4\/groups\/{id}\/-\/packages\/nuget\/metadata\/\*package_name\/\*package_version"/{
    :a
    N
    /operationId/!ba
    d
}' "${TMP_DIR}/openapi_v3.yml"
sed -i \
    -e '/^  "\/api\/v4\/projects\/{id}\/packages\/nuget\/metadata\/\*package_name\/index"/{
    :a
    N
    /operationId/!ba
    d
}' "${TMP_DIR}/openapi_v3.yml"
sed -i \
    -e '/^  "\/api\/v4\/projects\/{id}\/packages\/nuget\/metadata\/\*package_name\/\*package_version"/{
    :a
    N
    /operationId/!ba
    d
}' "${TMP_DIR}/openapi_v3.yml"

# Re-format
redocly bundle -d --remove-unused-components -o "${BASE_DIR}/openapi.yml" "${TMP_DIR}/openapi_v3.yml"
