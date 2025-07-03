#!/usr/bin/env python3
# /// script
# dependencies = ["mdit_py_plugins"]
# requires-python = ">=3.11"
# ///

import json
import re
import sys
from typing import Any
from urllib.parse import urlparse

from markdown_it import MarkdownIt
from markdown_it.tree import SyntaxTreeNode
from mdit_py_plugins.footnote import footnote_plugin
from mdit_py_plugins.front_matter import front_matter_plugin


class Operation:
    def __init__(self, title):
        self.title = title
        self.uri = None
        self.attribute = None
        self.example_request = None
        self.example_response = None


class Attribute:
    def __init__(self, name):
        self.name = name
        self.type = None
        self.required = None
        self.description = None


class Parameter:
    def __init__(self, name, kind):
        self.name = name
        self.kind = kind
        self.description = None
        self.required = False
        self.schema = None


def get_title(node) -> str:
    text = find_first_text(node)
    if text is not None:
        return text

    raise Exception("Not found section title.")


def find_first_text(node) -> str | None:
    content = ""
    for text in node.walk(include_self=False):
        if text.type == "text" or text.type == "code_inline":
            content += text.content

    if content:
        return content.strip()

    return None


def parse_attribute(node) -> list[Attribute]:
    attrs = []

    tbody = node.children[1]
    for tr in tbody.children:
        name = find_first_text(tr.children[0])
        if name is None:
            continue

        attr = Attribute(name)
        attr.type = find_first_text(tr.children[1])
        attr.required = find_first_text(tr.children[2])
        attr.description = find_first_text(tr.children[3])

        attrs.append(attr)

    return attrs


def parse_operations(file_path: str) -> list[Operation]:
    md = MarkdownIt().use(front_matter_plugin).use(footnote_plugin).enable("table")

    with open(file_path) as f:
        content = f.read()
        tokens = md.parse(content)
        root = SyntaxTreeNode(tokens)

        operations = []
        operation = None
        next_kind = None
        for node in root.children:
            if node.markup == "##" or node.markup == "###":
                if operation and operation.uri:
                    operations.append(operation)

                operation = Operation(title=get_title(node))
                next_kind = "uri"
                continue

            if operation is None:
                continue

            text = find_first_text(node)

            if text == "Supported attributes:":
                next_kind = "attribute"
                continue

            if text == "Example request:":
                next_kind = "request"
                continue

            if text == "Example response:":
                next_kind = "response"
                continue

            if node.type == "table":
                if operation.attribute is None and next_kind == "attribute":
                    operation.attribute = parse_attribute(node) or ""

            if node.type == "fence":
                if operation.uri is None and next_kind == "uri":
                    operation.uri = node.content or ""
                elif operation.example_request is None and next_kind == "request":
                    operation.example_request = node.content or ""
                elif operation.example_response is None and next_kind == "response":
                    operation.example_response = node.content or ""

        if operation and operation.uri:
            operations.append(operation)

        return operations


def parse_uri(example_uri: str) -> tuple[str, str]:
    first_uri = example_uri.split("\n")[0]
    method, *path_and_query = first_uri.split(" ", 1)

    if method not in ["GET", "PATCH", "POST", "PUT", "DELETE", "HEAD", "OPTION"]:
        raise Exception(f"Unknown http method {method}")

    uri = urlparse(path_and_query[0])
    return (method, re.sub(r":([^/]+)", r"{\1}", uri.path))


def parse_path(path: str) -> list[str]:
    paths = []

    for m in re.finditer(r"/{([^}]+)}", path):
        paths.append(m.group(1))

    return paths


def parse_example_request(example: str) -> list[str]:
    forms = []
    if example is None:
        return forms

    for line in example.split("\n"):
        if m := re.search(r"--form '?([^=]+)=.*'?", line):
            forms.append(m.group(1))

    return forms


def parse_parameter(
    attributes, paths, forms
) -> tuple[list[Parameter], list[Attribute]]:
    parameters = []
    body = []

    if not attributes:
        return ([], [])

    for attr in attributes:
        kind = "query"
        if attr.name in paths:
            kind = "path"
        elif attr.name in forms:
            body.append(attr)
            continue

        parameter = Parameter(attr.name, kind)
        parameter.description = attr.description
        parameter.required = attr.required in ["Yes", "yes"]
        parameter.schema = attr.type

        parameters.append(parameter)

    return (parameters, body)


def parse_example_response(example: str) -> dict[str, Any]:
    if example is None:
        return {}

    def conv_ty(value):
        if isinstance(value, bool):
            return {"type": "boolean"}
        elif isinstance(value, int):
            return {"type": "integer"}
        elif isinstance(value, str):
            return {"type": "string"}
        elif isinstance(value, list):
            schema = {"type": "array", "items": None}
            if len(value) == 0:
                # TODO:
                schema["items"] = conv_ty("string")
            else:
                schema["items"] = conv_ty(value[0])
            return schema
        elif isinstance(value, dict):
            schema = {"type": "object", "properties": None}
            schema["properties"] = {k: conv_ty(v) for k, v in value.items()}
            return schema
        elif value is None:
            # TODO:
            return conv_ty("string")
        else:
            raise Exception(value)

    d = json.loads(example)
    return conv_ty(d)


def conv_path(
    path: str,
    method: str,
    description: str,
    parameters: list[Parameter],
    request: list[Attribute],
    response: dict[str, Any],
) -> tuple[str, Any]:
    path = f"/api/v4{path}"
    method = method.lower()

    operation: dict[str, Any] = {
        path: {
            method: {
                "description": description,
            }
        }
    }

    if len(parameters) > 0:
        params: list[dict[str, Any]] = []
        for parameter in parameters:
            params.append(
                {
                    "name": parameter.name,
                    "in": parameter.kind,
                    "description": parameter.description,
                    "required": parameter.required,
                    "schema": {"type": parameter.schema.lower()},
                }
            )

            ty = params[-1]["schema"]["type"]
            if ty == "string array":
                params[-1]["schema"] = {
                    "type": "array",
                    "items": {"type": "string"},
                }
            elif ty == "integer array":
                params[-1]["schema"] = {
                    "type": "array",
                    "items": {"type": "integer"},
                }
        operation[path][method]["parameters"] = params

    if len(request) > 0:
        properties: dict[str, Any] = {}
        required = []
        for req in request:
            properties |= {
                req.name: {
                    "description": req.description,
                    "type": req.type,
                }
            }

            if req.required:
                required.append(req.name)

        operation[path][method]["requestBody"] = {
            "content": {
                "application/x-www-form-urlencoded": {
                    "schema": {
                        "type": "object",
                        "properties": properties,
                        "required": required,
                    }
                }
            }
        }

    if len(response) > 0:
        operation[path][method]["responses"] = {
            "2XX": {
                "description": "success",
                "content": {
                    "application/json": {
                        "schema": response,
                    }
                },
            },
        }
    else:
        operation[path][method]["responses"] = {
            "2XX": {
                "description": "not provided",
            },
        }

    return list(operation.items())[0]


operations: dict[str, Any] = {}
for operation in parse_operations(sys.argv[1]):
    method, path = parse_uri(operation.uri)

    paths = parse_path(path)
    forms = parse_example_request(operation.example_request)
    params, body = parse_parameter(operation.attribute, paths, forms)
    response = parse_example_response(operation.example_response)

    (key, value) = conv_path(path, method, operation.title, params, body, response)
    if key in operations:
        operations[key] |= value
    else:
        operations[key] = value

print(json.dumps({"paths": operations}))
