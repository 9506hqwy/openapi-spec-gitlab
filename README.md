# OpenAPI Schema for GitLab Server Web API v4

## Generating

Convert Swagger 2.0 to OpenAPI 3.0.

```sh
./gen/v2_to_v3.sh
```

Generate missing OpenAPI schema.

```sh
./gen/md_to_schema.sh
```

Merge schema.

```sh
yq '.paths = .paths + (load("./temp/issues.yml") | .paths)' ./temp/openapi_v3.yml > ./temp/openapi.yml
```

Bundle one file.

```sh
redocly bundle -d --remove-unused-components ./temp/openapi.yml | yq 'explode(.)' > openapi.yml
```

Verify OpenAPI schema format.

```sh
redocly lint openapi.yml
```

Preview documents.

```sh
redocly preview-docs openapi.yml
```

## References

* [Missing endpoints in OpenAPI documentation](https://gitlab.com/gitlab-org/gitlab/-/issues/486493)
