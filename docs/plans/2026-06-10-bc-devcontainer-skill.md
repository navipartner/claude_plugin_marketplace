# BC Dev Container Provisioning Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a `bc-devcontainer` plugin to the marketplace whose `provision-bc-container` skill lets an agent order, reuse, restart, and tear down a NaviPartner Crane Business Central dev container to develop and test against.

**Architecture:** A new standalone plugin directory (`bc-devcontainer/`) holding a single self-contained `SKILL.md`, mirroring the existing `al-id-manager` and `bcdev-cli` plugins. The skill issues Crane SOAP calls with `curl`, authenticates via the `np_crane_api_key` environment variable, and persists container credentials plus a readiness marker to the worktree-local repo-root `.env`. Registered in `.claude-plugin/marketplace.json` and documented in `README.md`.

**Tech Stack:** Claude Code plugin/skill format (Markdown + YAML frontmatter), JSON manifests, `curl`, BC Crane SOAP API. No build step, no runtime dependency.

**Verification note (adaptation):** This is a documentation/skill-authoring change, so there is no unit-test framework. The "test" after each task is `claude plugin validate <path>` plus JSON-parse checks and content greps. Verification commands run *after* creating each file (a pre-creation run would trivially fail because the path doesn't exist yet).

**CLI facts verified for this plan (Claude Code 2.1.146):**
- `claude plugin validate <path>` is the correct syntax. `--plugin-dir` is **not** a valid option for `validate` (the repo's current README uses it incorrectly; this plan fixes the lines it touches).
- `claude plugin validate <path>` accepts either a plugin directory or a marketplace manifest.
- `claude plugin validate .claude-plugin/marketplace.json` currently reports **1 pre-existing warning** unrelated to this work: the `bcdev-cli` marketplace entry says `2.0.0` while its `plugin.json` says `2.3.0`. Non-strict passes with that warning; `--strict` fails on it. This plan does **not** change that entry (see the open decision in the handoff). The new `bc-devcontainer` entry must add **no new** warning.

---

### Task 1: Create the `bc-devcontainer` plugin (manifest + skill)

**Files:**
- Create: `bc-devcontainer/.claude-plugin/plugin.json`
- Create: `bc-devcontainer/skills/provision-bc-container/SKILL.md`

**Step 1: Create the plugin manifest**

`bc-devcontainer/.claude-plugin/plugin.json`:

```json
{
  "name": "bc-devcontainer",
  "version": "1.0.0",
  "description": "Provision, reuse, restart, and stop NaviPartner Crane Business Central development containers to develop and test against",
  "author": {
    "name": "NaviPartner",
    "email": "dev@navipartner.com"
  },
  "license": "UNLICENSED"
}
```

**Step 2: Verify the manifest is valid JSON**

Run: `python3 -c "import json; json.load(open('bc-devcontainer/.claude-plugin/plugin.json')); print('ok')"`
Expected: `ok`

**Step 3: Create the skill**

`bc-devcontainer/skills/provision-bc-container/SKILL.md`:

````markdown
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
````

**Step 4: Verify the skill frontmatter and content**

Run: `head -4 bc-devcontainer/skills/provision-bc-container/SKILL.md`
Expected: shows `---`, `name: provision-bc-container`, a `description:` line.

Run: `grep -c 'np_crane_api_key' bc-devcontainer/skills/provision-bc-container/SKILL.md`
Expected: count >= 3.

Run: `! grep -q 'crane_key' bc-devcontainer/skills/provision-bc-container/SKILL.md && echo clean`
Expected: `clean` (old env-var name fully replaced).

Run: `grep -Eq 'BC_CONTAINER_READY_AFTER|check-ignore' bc-devcontainer/skills/provision-bc-container/SKILL.md && echo guards-present`
Expected: `guards-present` (readiness marker + gitignore safety landed).

**Step 5: Validate the plugin (correct CLI syntax)**

Run: `claude plugin validate ./bc-devcontainer`
Expected: `✔ Validation passed`.

Run: `claude plugin validate --strict ./bc-devcontainer`
Expected: `✔ Validation passed` (the new plugin is clean; no warnings).

**Step 6: Commit**

```bash
git add bc-devcontainer/
git commit -m "feat(bc-devcontainer): add Crane container provisioning skill"
```

---

### Task 2: Register the plugin in the marketplace

**Files:**
- Modify: `.claude-plugin/marketplace.json` (append to the `plugins` array, after the `bcdev-cli` entry)

**Step 1: Add the marketplace entry**

Append this object to the `plugins` array (add a comma after the existing `bcdev-cli` entry's closing brace):

```json
{
  "name": "bc-devcontainer",
  "description": "Provision BC development containers via the NaviPartner Crane API - create, reuse, restart, and stop environments to develop and test against",
  "version": "1.0.0",
  "author": {
    "name": "NaviPartner",
    "email": "dev@navipartner.com"
  },
  "source": "./bc-devcontainer",
  "category": "development",
  "tags": ["business-central", "al", "devcontainer", "crane", "provisioning", "environment"]
}
```

**Step 2: Verify marketplace JSON is valid and lists three plugins**

Run: `python3 -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); print([p['name'] for p in d['plugins']])"`
Expected: `['al-id-manager', 'bcdev-cli', 'bc-devcontainer']`

**Step 3: Validate the marketplace manifest; confirm the new entry adds no new warning**

Run: `claude plugin validate .claude-plugin/marketplace.json`
Expected: `✔ Validation passed with warnings` — exactly **1** warning, and it concerns `plugins[1]` / `bcdev-cli` (the pre-existing version drift), **not** `bc-devcontainer`.

If any warning mentions `bc-devcontainer`, fix the new entry until it is clean.

**Step 4: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat(bc-devcontainer): register plugin in marketplace"
```

---

### Task 3: Document the plugin in the README

**Files:**
- Modify: `README.md` (install commands, Plugins section, Development section)

**Step 1: Add the install command** under the existing install block:

```bash
# BC Dev Container (provision Crane environments)
claude plugin install bc-devcontainer@navipartner-bc-tools
```

**Step 2: Add a plugin section** after the "### BC Dev CLI" section:

```markdown
### BC Dev Container

Provisions Business Central development containers via the NaviPartner Crane API so the LLM can develop and test against a real environment. Creates a new container, reuses or restarts an existing one for the current git worktree, and stops it when done. Pair it with the BC Dev CLI plugin to compile, publish, and test once the container is ready.

**Use when:** You need a BC environment to validate development against and don't already have one running - spinning up, restarting, or tearing down a Crane dev container.

**Skill:** `bc-devcontainer:provision-bc-container`

#### Configuration

The skill authenticates to Crane with an API key read from the `np_crane_api_key` environment variable:

```bash
# macOS/Linux
export np_crane_api_key="your-crane-api-key"

# Windows
set np_crane_api_key=your-crane-api-key
```

Ask your NaviPartner administrator if you don't have a key. The skill stops and prompts you to configure this variable if it is missing.

Container credentials (URL, username, password, id) are written to the repository root `.env` (gitignored) so parallel git worktrees stay isolated against different environments.
```

**Step 3: Extend the Development section AND fix the broken `validate` syntax in the lines being edited.**

The current README "Validating plugins" block uses `claude plugin validate --plugin-dir ./...`, which is **not** valid in the installed CLI (the option does not exist for `validate`). Replace that block with the correct positional syntax and include the new plugin:

```bash
# Validate a single plugin
claude plugin validate ./al-id-manager
claude plugin validate ./bcdev-cli
claude plugin validate ./bc-devcontainer

# Validate all plugins
for plugin in al-id-manager bcdev-cli bc-devcontainer; do
  claude plugin validate ./$plugin
done
```

Add to the "Testing locally" block (note: `claude --plugin-dir` *is* valid for launching Claude; only `claude plugin validate --plugin-dir` was wrong):

```bash
claude --plugin-dir ./bc-devcontainer
```

**Step 4: Verify the README references**

Run: `grep -c 'bc-devcontainer' README.md`
Expected: count >= 5 (install, skill id, single-validate, validate loop, test-locally).

Run: `grep -c 'np_crane_api_key' README.md`
Expected: count >= 2.

Run: `! grep -q 'plugin validate --plugin-dir' README.md && echo fixed`
Expected: `fixed` (no `validate --plugin-dir` misuse remains).

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs(bc-devcontainer): document plugin, np_crane_api_key, and fix validate syntax"
```

---

### Task 4: Final end-to-end validation

**Files:** none (verification only)

**Step 1: Validate every plugin (positional syntax)**

Run:
```bash
for plugin in al-id-manager bcdev-cli bc-devcontainer; do
  echo "== $plugin =="; claude plugin validate ./$plugin
done
```
Expected: all three pass.

**Step 2: Validate the marketplace manifest**

Run: `claude plugin validate .claude-plugin/marketplace.json`
Expected: passes; the only warning (if any) is the pre-existing `bcdev-cli` version drift, never `bc-devcontainer`.

Run: `python3 -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); assert len(d['plugins'])==3; print('ok')"`
Expected: `ok`

**Step 3: Confirm no stale `crane_key` (old name) anywhere new**

Run: `! grep -rn 'crane_key' bc-devcontainer README.md .claude-plugin && echo clean`
Expected: `clean`

**Step 4: Confirm the working tree is clean (everything committed)**

Run: `git status --short`
Expected: empty output.
