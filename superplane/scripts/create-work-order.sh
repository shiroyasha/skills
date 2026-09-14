#!/usr/bin/env bash
# Create a draft work order on workspace SUPER. Never prints the API token.
set -euo pipefail

ORG_ID="3ee1aa47-3a60-4c1f-b645-0b9859ab91f8"
FACTORY_KEY="SUPER"
CONFIG_PATH="${HOME}/.superplane.yaml"
MAX_TITLE=256
MAX_DESC=5000

usage() {
  echo "Usage: $0 --title <title> (--description-file <path> | --description <text>)" >&2
  exit 2
}

TITLE=""
DESCRIPTION=""
DESC_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || usage
      TITLE="$2"
      shift 2
      ;;
    --description)
      [[ $# -ge 2 ]] || usage
      DESCRIPTION="$2"
      shift 2
      ;;
    --description-file)
      [[ $# -ge 2 ]] || usage
      DESC_FILE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "$TITLE" ]]; then
  echo "error: --title is required" >&2
  exit 2
fi

if [[ -n "$DESCRIPTION" && -n "$DESC_FILE" ]]; then
  echo "error: specify only one of --description or --description-file" >&2
  exit 2
fi

if [[ -n "$DESC_FILE" ]]; then
  DESCRIPTION="$(cat "$DESC_FILE")"
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "error: missing config file ${CONFIG_PATH}" >&2
  exit 1
fi

python3 - "$ORG_ID" "$FACTORY_KEY" "$CONFIG_PATH" "$TITLE" "$DESCRIPTION" "$MAX_TITLE" "$MAX_DESC" <<'PY'
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

org_id, factory_key, config_path, title, description, max_title, max_desc = sys.argv[1:8]
max_title = int(max_title)
max_desc = int(max_desc)

title = title.strip()
if not title:
    print("error: title is empty", file=sys.stderr)
    sys.exit(2)
if len(title) > max_title:
    print(f"error: title is {len(title)} characters; max is {max_title}", file=sys.stderr)
    sys.exit(2)
if len(description) > max_desc:
    print(
        f"error: description is {len(description)} characters; max is {max_desc}",
        file=sys.stderr,
    )
    sys.exit(2)


def load_yaml(path):
    try:
        import yaml  # type: ignore

        with open(path, encoding="utf-8") as handle:
            data = yaml.safe_load(handle) or {}
        if not isinstance(data, dict):
            raise ValueError("config root must be a mapping")
        return data
    except ImportError:
        pass

    try:
        raw = subprocess.check_output(
            [
                "ruby",
                "-ryaml",
                "-rjson",
                "-e",
                "print JSON.generate(YAML.load_file(ARGV[0]) || {})",
                path,
            ],
            stderr=subprocess.DEVNULL,
        )
        data = json.loads(raw.decode())
        if not isinstance(data, dict):
            raise ValueError("config root must be a mapping")
        return data
    except (FileNotFoundError, subprocess.CalledProcessError, json.JSONDecodeError) as err:
        print(f"error: failed to parse {path}: {err}", file=sys.stderr)
        sys.exit(1)


def pick_context(cfg):
    contexts = cfg.get("contexts") or []
    if not isinstance(contexts, list):
        contexts = []

    for ctx in contexts:
        if not isinstance(ctx, dict):
            continue
        if str(ctx.get("organizationId") or "").strip() == org_id:
            return ctx

    current = str(cfg.get("currentContext") or "").rstrip("/")
    for ctx in contexts:
        if not isinstance(ctx, dict):
            continue
        url = str(ctx.get("url") or "").rstrip("/")
        oid = str(ctx.get("organizationId") or ctx.get("organization") or "").strip()
        if oid and f"{url}/{oid}" == current:
            return ctx

    print(
        f"error: no context in {config_path} for organization {org_id}",
        file=sys.stderr,
    )
    sys.exit(1)


try:
    cfg = load_yaml(config_path)
except FileNotFoundError:
    print(f"error: missing config file {config_path}", file=sys.stderr)
    sys.exit(1)

ctx = pick_context(cfg)
base_url = str(ctx.get("url") or "").strip().rstrip("/")
# SUPERPLANE_API_TOKEN lets you use a fresh token without editing the config.
token = os.environ.get("SUPERPLANE_API_TOKEN", "").strip() or str(ctx.get("apiToken") or "").strip()
if not base_url:
    print("error: context url is empty", file=sys.stderr)
    sys.exit(1)
if not token:
    print("error: context apiToken is empty", file=sys.stderr)
    sys.exit(1)

# Cloudflare in front of app.superplane.com rejects the default
# "Python-urllib" agent with error 1010, so send an explicit one.
headers = {
    "Authorization": f"Bearer {token}",
    "x-organization-id": org_id,
    "Accept": "application/json",
    "Content-Type": "application/json",
    "User-Agent": "superplane-work-order-skill/1.0",
}


def request(method, url, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, json.loads(resp.read().decode() or "null")
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")
        print(f"error: HTTP {err.code} {method} {url}", file=sys.stderr)
        if detail:
            print(detail, file=sys.stderr)
        if err.code == 401:
            print(
                "hint: the API token is rejected. Generate a new token at "
                f"{base_url}/{org_id}/settings/profile, then put it in "
                f"{config_path} or in SUPERPLANE_API_TOKEN.",
                file=sys.stderr,
            )
        if "cloudflare" in detail.lower():
            print(
                "hint: Cloudflare blocked the request before it reached the API",
                file=sys.stderr,
            )
        sys.exit(1)
    except urllib.error.URLError as err:
        print(f"error: request failed: {err}", file=sys.stderr)
        sys.exit(1)


# Check the token first so a bad credential is reported as such.
request("GET", f"{base_url}/api/v1/me")

_, list_body = request("GET", f"{base_url}/api/v1/factories")
factories = []
if isinstance(list_body, dict):
    factories = list_body.get("factories") or []

factory_id = None
for factory in factories:
    if not isinstance(factory, dict):
        continue
    if str(factory.get("key") or "").strip() == factory_key:
        factory_id = str(factory.get("id") or "").strip()
        break

if not factory_id:
    print(f"error: factory key {factory_key!r} not found", file=sys.stderr)
    sys.exit(1)

payload = {"title": title}
if description:
    payload["description"] = description

_, create_body = request(
    "POST",
    f"{base_url}/api/v1/factories/{factory_id}/orders",
    payload,
)

order = {}
if isinstance(create_body, dict):
    order = create_body.get("order") or {}
if not isinstance(order, dict):
    print("error: create response missing order", file=sys.stderr)
    sys.exit(1)

out = {
    "id": order.get("id"),
    "number": order.get("number"),
    "key": order.get("key"),
    "state": order.get("state"),
}
print(json.dumps(out, separators=(",", ":")))
PY
