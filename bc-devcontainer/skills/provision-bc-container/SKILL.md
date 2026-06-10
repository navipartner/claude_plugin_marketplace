---
name: provision-bc-container
description: This skill should be used when the user needs to OBTAIN or manage a Business Central development environment itself - e.g. "spin up / order / provision a BC dev container", "I don't have a BC environment to test against", "restart my stopped BC container", or "stop / tear down the BC container". It provisions, reuses, restarts, and stops NaviPartner Crane containers. For compiling, publishing, or running tests against an environment that already exists, use the bcdev-cli skill instead.
---

# Provision BC Dev Container (Crane)

This skill obtains a Business Central development container through the NaviPartner Crane
SOAP API, then wires up an AL project to develop and test against it. Use it when the
current git worktree does not already have a working BC environment.

Once a container is ready, use the `bcdev-cli:bcdev` skill to download symbols, compile,
publish, and run tests against it.

## Prerequisites

### API key: `np_crane_api_key`

Crane requests authenticate with an API key read from the **`np_crane_api_key`**
environment variable.

**Before doing anything else, check that it is set:**

```bash
[ -n "$np_crane_api_key" ] && echo "np_crane_api_key is set" || echo "MISSING"
```

If it prints `MISSING`, **stop and ask the developer to configure it** - do not continue
and do not invent a value:

> The `np_crane_api_key` environment variable is not set. It holds your Crane API
> subscription key. Please configure it (e.g. add `export np_crane_api_key="<your-key>"`
> to your shell profile) and ask your NaviPartner administrator for a key if you don't
> have one, then re-run.

Never print, log, or echo the key's value.

### Credential storage: worktree-local `.env`

Container credentials live in the **repository-root `.env`** so parallel git worktrees
stay isolated and can each target a different container. Resolve the root, fail closed if
`.env` is tracked, and make sure it is ignored without dirtying the consuming repo:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="$REPO_ROOT/.env"

# Never risk committing secrets: refuse if .env is tracked.
if git -C "$REPO_ROOT" ls-files --error-unmatch .env >/dev/null 2>&1; then
  echo "ERROR: .env is tracked by git in this repo. Untrack it before storing container credentials."
  exit 1
fi

# Ensure .env is ignored via ANY mechanism (global excludes, .gitignore, info/exclude).
# If not already ignored, add it to .git/info/exclude so the working tree stays clean.
git -C "$REPO_ROOT" check-ignore -q .env || echo '.env' >> "$REPO_ROOT/.git/info/exclude"
```

Read and write `.env` with these helpers. They quote values safely and do **not** rely on
`source`/`eval`, so special characters in a generated password cannot break parsing or
trigger shell expansion:

```bash
set_env_var() {  # set_env_var KEY VALUE  (upsert into $ENV_FILE)
  local key="$1" val="$2" esc
  esc=${val//\'/\'\\\'\'}                       # escape single quotes
  touch "$ENV_FILE"
  grep -v "^${key}=" "$ENV_FILE" > "$ENV_FILE.tmp" 2>/dev/null || true
  mv "$ENV_FILE.tmp" "$ENV_FILE"
  printf "%s='%s'\n" "$key" "$esc" >> "$ENV_FILE"
}

get_env_var() {  # get_env_var KEY  -> prints value
  local key="$1" raw
  raw=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1)
  raw=${raw#${key}=}; raw=${raw#\'}; raw=${raw%\'}
  printf '%s' "$raw"
}
```

`.env` keys used by this skill:

| Variable | Meaning |
|----------|---------|
| `BC_CONTAINER_ID` | Crane container id (used to start/stop) |
| `BC_CONTAINER_URL` | Container base URL |
| `BC_CONTAINER_USERNAME` | BC user |
| `BC_CONTAINER_PASSWORD` | BC password |
| `BC_CONTAINER_READY_AFTER` | Epoch seconds before which the container must NOT receive any request (demo-data import window) |
| `BC_CONTAINER_READY` | `true` only after a successful readiness poll |

## Decision: reuse, restart, or create

Read `$ENV_FILE` first.

1. **No `BC_CONTAINER_ID`** -> go to *Create a container*.
2. **`BC_CONTAINER_ID` present but any of `BC_CONTAINER_URL` / `BC_CONTAINER_USERNAME` /
   `BC_CONTAINER_PASSWORD` missing** -> the record is corrupt. **Stop and ask the
   developer** to remove the `BC_CONTAINER_*` lines from `$ENV_FILE` and re-run. Do not
   provision a second container while a half-recorded one may exist.
3. **All four fields present:**
   - **If `BC_CONTAINER_READY` is not `true`** -> a container was created but never
     confirmed ready (e.g. a previous session was interrupted during the import window).
     **Do not probe or restart.** Respect the import window: if
     `now < BC_CONTAINER_READY_AFTER`, sleep the remainder, then go to *Poll until ready*.
   - **If `BC_CONTAINER_READY` is `true`** -> probe once (short timeout). If it answers,
     reuse as-is and you are done. If it does not answer, it is likely stopped -> go to
     *Restart a stopped container*.

Single short probe:

```bash
BC_CONTAINER_URL="$(get_env_var BC_CONTAINER_URL)"
code=$(curl -s -L --max-time 30 -o /dev/null -w '%{http_code}' "${BC_CONTAINER_URL}/BC")
[ "$code" = "200" ] && echo "reuse" || echo "restart"
```

## Crane API

All calls are HTTP `POST` to the same endpoint with the same auth header; only the
`SOAPAction` header and body change.

- **Endpoint:** `https://api.navipartner.dk/npcase/crane/api/v1/`
- **Headers:**
  - `Ocp-Apim-Subscription-Key: ${np_crane_api_key}`
  - `Content-Type: text/xml; charset=utf-8`
  - `SOAPAction:` varies per operation (below)

### Create a container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:CreateCursorContainer`

The `CLOUD-CORE` template provisions the latest released BC version. `containerUrl`,
`userName`, and `password` are **returned** by the API - send them empty.

```bash
RESPONSE=$(curl -s -X POST "https://api.navipartner.dk/npcase/crane/api/v1/" \
  -H "Ocp-Apim-Subscription-Key: ${np_crane_api_key}" \
  -H "Content-Type: text/xml; charset=utf-8" \
  -H "SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:CreateCursorContainer" \
  -d '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cran="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <soapenv:Header/>
   <soapenv:Body>
      <cran:CreateCursorContainer>
         <cran:craneTemplateCode>CLOUD-CORE</cran:craneTemplateCode>
         <cran:containerUrl></cran:containerUrl>
         <cran:userName></cran:userName>
         <cran:password></cran:password>
      </cran:CreateCursorContainer>
   </soapenv:Body>
</soapenv:Envelope>')
```

**Parse the response.** The API returns the assigned URL, credentials, and container id as
VAR/return parameters. The response resembles the following - **confirm the exact element
names against the actual XML you receive** (extract by reading `$RESPONSE`):

```xml
<CreateCursorContainer_Result xmlns="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <return_value>{containerId}</return_value>
   <containerUrl>https://{assigned-host}</containerUrl>
   <userName>{user}</userName>
   <password>{password}</password>
</CreateCursorContainer_Result>
```

**Fail closed:** if the response is a SOAP fault, or any of containerId / containerUrl /
userName / password is missing or empty, **stop and show the raw response** (do not echo
the password) - do not write a partial record to `$ENV_FILE`.

**Persist** the four values plus the readiness marker. Saving to a local file is not a
request to the container, so doing it before the wait is fine; the readiness marker is
what protects any later/parallel session from touching the container too early:

```bash
set_env_var BC_CONTAINER_ID       "$CONTAINER_ID"
set_env_var BC_CONTAINER_URL      "$CONTAINER_URL"
set_env_var BC_CONTAINER_USERNAME "$CONTAINER_USER"
set_env_var BC_CONTAINER_PASSWORD "$CONTAINER_PASS"
set_env_var BC_CONTAINER_READY_AFTER "$(( $(date +%s) + 2100 ))"   # 35 minutes
set_env_var BC_CONTAINER_READY "false"
```

**Then wait the full 35 minutes before making ANY request to the container** (including
health-check polls). The container imports demo data during this window and premature
requests crash the import:

```bash
now=$(date +%s); ready_after=$(get_env_var BC_CONTAINER_READY_AFTER)
[ "$now" -lt "$ready_after" ] && sleep $(( ready_after - now ))
```

Then go to *Poll until ready*.

### Restart a stopped container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StartContainer`

No 35-minute wait - demo-data import already happened. Poll immediately after.

> The `StartContainer` / `StopContainer` SOAPAction names below are inferred from the
> `CreateCursorContainer` pattern (the source only documented their envelope bodies). If a
> call returns a SOAP fault about an unknown action or method, verify the exact action name
> against the Crane service contract / WSDL.

```bash
BC_CONTAINER_ID="$(get_env_var BC_CONTAINER_ID)"
curl -s -X POST "https://api.navipartner.dk/npcase/crane/api/v1/" \
  -H "Ocp-Apim-Subscription-Key: ${np_crane_api_key}" \
  -H "Content-Type: text/xml; charset=utf-8" \
  -H "SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StartContainer" \
  -d '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cran="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <soapenv:Header/>
   <soapenv:Body>
      <cran:StartContainer>
         <cran:containerId>'"${BC_CONTAINER_ID}"'</cran:containerId>
      </cran:StartContainer>
   </soapenv:Body>
</soapenv:Envelope>'
```

Then go to *Poll until ready*. If polling still fails after its timeout, the container is
likely deleted or stale: **stop and tell the developer** to remove the `BC_CONTAINER_*`
lines from `$ENV_FILE` and re-run to provision a fresh one.

### Stop a container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StopContainer`

Stop the container when you finish your task to free resources.

```bash
BC_CONTAINER_ID="$(get_env_var BC_CONTAINER_ID)"
curl -s -X POST "https://api.navipartner.dk/npcase/crane/api/v1/" \
  -H "Ocp-Apim-Subscription-Key: ${np_crane_api_key}" \
  -H "Content-Type: text/xml; charset=utf-8" \
  -H "SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StopContainer" \
  -d '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cran="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <soapenv:Header/>
   <soapenv:Body>
      <cran:StopContainer>
         <cran:containerId>'"${BC_CONTAINER_ID}"'</cran:containerId>
      </cran:StopContainer>
   </soapenv:Body>
</soapenv:Envelope>'
```

The credentials and `BC_CONTAINER_READY=true` marker stay in `$ENV_FILE`, so a later
session restarts this same container (no re-import) via the reuse decision above.

## Poll until ready

Bounded poll - never loops forever. On success, record readiness:

```bash
BC_CONTAINER_URL="$(get_env_var BC_CONTAINER_URL)"
deadline=$(( $(date +%s) + 1200 ))   # up to 20 minutes of polling
until [ "$(curl -s -L --max-time 30 -o /dev/null -w '%{http_code}' "${BC_CONTAINER_URL}/BC")" = "200" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "ERROR: ${BC_CONTAINER_URL}/BC did not return 200 within 20 minutes. The container may be stopped, deleted, or misconfigured."
    exit 1
  fi
  echo "Container not ready yet, waiting 60s..."
  sleep 60
done
set_env_var BC_CONTAINER_READY "true"
echo "Container is ready: ${BC_CONTAINER_URL}/BC"
```

## Wire up the AL project

### launch.json

`launch.json` files are gitignored. Create one per AL project under its
`.vscode/launch.json` (e.g. the main app and the test app each get their own), pointing at
the container. The password is **not** stored here - `UserPassword` auth takes it at
publish/test time:

```json
{
  "configurations": [
    {
      "name": "Crane",
      "type": "al",
      "request": "launch",
      "server": "<BC_CONTAINER_URL>",
      "port": 443,
      "serverInstance": "BC",
      "authentication": "UserPassword"
    }
  ]
}
```

Substitute the real `BC_CONTAINER_URL` (`get_env_var BC_CONTAINER_URL`). Pass the BC
username/password from `$ENV_FILE` to the `bcdev-cli:bcdev` skill when downloading
symbols, publishing, or testing.

### app.json version targeting

The container runs a specific BC version. For local compilation, temporarily align
`app.json` to it, then restore the original before committing.

1. Determine the container's BC major version (e.g. `BC27`).
2. Back up the original: `cp app.json app.json.orig`.
3. Update `platform`, `application`, `runtime`, and `preprocessorSymbols`:
   - **`runtime = BC_version - 11`** (e.g. `BC27` -> `"runtime": "16.0"`).
   - Set `preprocessorSymbols` to only the target version, e.g. `["BC27", "BC2700"]`.
4. **Do not commit `app.json` changes.** Restore with `mv app.json.orig app.json` when
   done.

## POS testing

To open the POS page directly in BC, append `?page=6150750` to the container URL:

```
<BC_CONTAINER_URL>/BC?page=6150750
```

For other pages, use the search function in the top-right of the Role Center.

## Cleanup

When the task is complete, **stop the container** (see *Stop a container*) to free
resources.
