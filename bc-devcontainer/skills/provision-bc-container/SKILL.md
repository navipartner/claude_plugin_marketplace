---
name: provision-bc-container
description: This skill should be used when the user needs to OBTAIN or manage a Business Central development environment itself - e.g. "spin up / order / provision a BC dev container", "I don't have a BC environment to test against", "restart my stopped BC container", or "stop / tear down the BC container". It provisions, reuses, restarts, and stops NaviPartner Crane containers. For compiling, publishing, or running tests against an environment that already exists, use the bcdev-cli skill instead.
---

# Provision BC Dev Container (Crane)

This skill obtains a Business Central development container through the NaviPartner Crane
SOAP API, then wires up an AL project to develop and test against it. Use it when the
current git worktree does not already have a working BC environment.

The steps below describe **intent**, not literal commands - implement each with whatever
tooling and wait mechanism you prefer. Code blocks are reference data (SOAP bodies, JSON
config), not scripts to copy verbatim. Once a container is ready, use the `bcdev-cli:bcdev`
skill to download symbols, compile, publish, and run tests against it.

## Prerequisites

### API key: `np_crane_api_key`

Crane requests authenticate with an API key in the **`np_crane_api_key`** environment
variable. **Check it is set before doing anything else.** If it is missing, stop and ask
the developer to configure it (e.g. `export np_crane_api_key="<your-key>"` in their shell
profile; their NaviPartner administrator issues keys) - do not continue or invent a value.
Never print, log, or echo the key.

### Credential storage: `.env` at the worktree root

Container credentials live in a `.env` at the **worktree root** (`git rev-parse
--show-toplevel`) so parallel git worktrees stay isolated and can each target a different
container. Before writing to it:

- **Fail closed if `.env` is tracked by git** - refuse to store secrets in a tracked file.
- **Ensure `.env` is git-ignored without dirtying the repo.** If it isn't already ignored,
  add it to the repo's `info/exclude`. In a linked worktree `.git` is a *file*, not a
  directory, so resolve the real exclude path with `git rev-parse --git-path info/exclude`
  rather than hard-coding `.git/info/exclude`.

Read and write `.env` as simple `KEY='value'` lines. **Quote values and do not rely on
`source`/`eval`** so special characters in a generated password cannot break parsing or
trigger shell expansion: escape single quotes when writing a value and reverse that when
reading it back.

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

Read `.env` first, then:

1. **No `BC_CONTAINER_ID`** -> *Create a container*.
2. **`BC_CONTAINER_ID` present but any of `BC_CONTAINER_URL` / `BC_CONTAINER_USERNAME` /
   `BC_CONTAINER_PASSWORD` missing** -> the record is corrupt. **Stop and ask the developer**
   to remove the `BC_CONTAINER_*` lines from `.env` and re-run. Do not provision a second
   container while a half-recorded one may exist.
3. **All four fields present:**
   - **`BC_CONTAINER_READY` is not `true`** -> a container was created but never confirmed
     ready (e.g. a previous session was interrupted during the import window). **Do not probe
     or restart.** This path needs a **numeric** `BC_CONTAINER_READY_AFTER`; if it is missing
     or non-numeric the record is corrupt -> **stop and ask the developer** to remove the
     `BC_CONTAINER_*` lines and re-run (do not poll - the import embargo time is unknown).
     Otherwise respect the remaining import window (see *Create a container*), then go to
     *Poll until ready*.
   - **`BC_CONTAINER_READY` is `true`** -> probe `<BC_CONTAINER_URL>/BC` once with a short
     timeout (a transport failure must not abort your script). If it returns HTTP 200, reuse
     as-is and you are done. Otherwise it is likely stopped -> *Restart a stopped container*.

## Crane API

All calls are HTTP `POST` to the same endpoint with the same auth header; only the
`SOAPAction` header and the body change.

- **Endpoint:** `https://api.navipartner.dk/npcase/crane/api/v1/`
- **Headers:**
  - `Ocp-Apim-Subscription-Key: ${np_crane_api_key}`
  - `Content-Type: text/xml; charset=utf-8`
  - `SOAPAction:` varies per operation (below)

Every body is a SOAP envelope in the `urn:microsoft-dynamics-schemas/codeunit/CraneAPI`
namespace. **Inspect every response for a `<faultstring>` / `<faultcode>` before
continuing**, and **redact any `<password>` element before printing a response for
debugging** - a partial or fault response can still contain a populated password.

### Create a container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:CreateCursorContainer`

The `CLOUD-CORE` template provisions the latest released BC version. Send `containerUrl`,
`userName`, and `password` **empty** - the API returns them. Body:

```xml
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cran="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <soapenv:Header/>
   <soapenv:Body>
      <cran:CreateCursorContainer>
         <cran:craneTemplateCode>CLOUD-CORE</cran:craneTemplateCode>
         <cran:containerUrl></cran:containerUrl>
         <cran:userName></cran:userName>
         <cran:password></cran:password>
      </cran:CreateCursorContainer>
   </soapenv:Body>
</soapenv:Envelope>
```

The response carries the container id, URL, and credentials (confirm the exact element
names against the XML you actually receive):

```xml
<CreateCursorContainer_Result xmlns="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <return_value>{containerId}</return_value>
   <containerUrl>https://{assigned-host}</containerUrl>
   <userName>{user}</userName>
   <password>{password}</password>
</CreateCursorContainer_Result>
```

**Fail closed:** if the response is a SOAP fault, or any of containerId / containerUrl /
userName / password is missing or empty, **stop** - do not write a partial record to `.env`.

Otherwise **persist** all four values, plus `BC_CONTAINER_READY_AFTER` = now + 35 minutes
(2100s) and `BC_CONTAINER_READY` = `false`. Writing a local file is not a request to the
container, so persisting before the wait is fine; the readiness marker is what protects a
later or parallel session from touching the container too early.

**Then wait the full 35 minutes before making ANY request to the container** (including
health-check polls) - use whatever wait mechanism you prefer. The container imports demo
data during this window and premature requests crash the import. (When reusing a
never-confirmed record per the decision above, wait only the time remaining until
`BC_CONTAINER_READY_AFTER`.) Then go to *Poll until ready*.

### Restart a stopped container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StartContainer`

No 35-minute wait - demo-data import already happened; poll immediately after. The body
sends the saved `BC_CONTAINER_ID` as `<cran:containerId>`:

```xml
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:cran="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <soapenv:Header/>
   <soapenv:Body>
      <cran:StartContainer>
         <cran:containerId>{BC_CONTAINER_ID}</cran:containerId>
      </cran:StartContainer>
   </soapenv:Body>
</soapenv:Envelope>
```

> The `StartContainer` / `StopContainer` SOAPAction names are inferred from the
> `CreateCursorContainer` pattern (the source only documented their envelope bodies). If a
> call returns a SOAP fault about an unknown action or method, verify the exact action name
> against the Crane service contract / WSDL.

Then go to *Poll until ready*. If polling still fails after its timeout, the container is
likely deleted or stale: **stop and tell the developer** to remove the `BC_CONTAINER_*`
lines from `.env` and re-run to provision a fresh one.

### Stop a container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StopContainer`

Stop the container when you finish your task to free resources. The body is identical to
*Restart a stopped container* but with the wrapper element `<cran:StopContainer>`. The
credentials and `BC_CONTAINER_READY=true` marker stay in `.env`, so a later session restarts
this same container (no re-import) via the reuse decision above.

## Poll until ready

Poll `<BC_CONTAINER_URL>/BC` until it returns HTTP 200, **bounded** so it never loops
forever: cap the total wait (~20 minutes) with a short timeout per attempt. On success, set
`BC_CONTAINER_READY=true`. On timeout, stop and report that the container may be stopped,
deleted, or misconfigured.

## Wire up the AL project

Skip this section if the worktree has no AL project - the container is still usable on its
own (e.g. via the `bcdev-cli:bcdev` skill).

### launch.json

`launch.json` files are gitignored. Create one per AL project under its `.vscode/launch.json`
(e.g. the main app and the test app each get their own), pointing at the container. The
password is **not** stored here - `UserPassword` auth takes it at publish/test time:

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

Substitute the real `BC_CONTAINER_URL`. Pass the BC username/password from `.env` to the
`bcdev-cli:bcdev` skill when downloading symbols, publishing, or testing.

### app.json version targeting

The container runs a specific BC version. For local compilation, temporarily align
`app.json` to it, then restore the original before committing.

1. Determine the container's BC major version (e.g. `BC27`).
2. Back up the original (e.g. `cp app.json app.json.orig`).
3. Update `platform`, `application`, `runtime`, and `preprocessorSymbols`:
   - **`runtime = BC_version - 11`** (e.g. `BC27` -> `"runtime": "16.0"`).
   - Set `preprocessorSymbols` to only the target version, e.g. `["BC27", "BC2700"]`.
4. **Do not commit `app.json` changes.** Restore the original when done.

## POS testing

To open the POS page directly in BC, append `?page=6150750` to the container URL:
`<BC_CONTAINER_URL>/BC?page=6150750`. For other pages, use the search function in the
top-right of the Role Center.

## Cleanup

When the task is complete, **stop the container** (see *Stop a container*) to free resources.
