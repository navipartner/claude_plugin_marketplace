# BC Dev Container Provisioning Skill Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers-extended-cc:executing-plans to implement this plan task-by-task.

**Goal:** Add a `bc-devcontainer` plugin to the marketplace whose `provision-bc-container` skill lets an agent order, reuse, restart, and tear down a NaviPartner Crane Business Central dev container to compile, publish, and test against.

**Architecture:** A new standalone plugin directory (`bc-devcontainer/`) holding a single self-contained `SKILL.md`, mirroring the existing `al-id-manager` and `bcdev-cli` plugins. The skill issues Crane SOAP calls with `curl`, authenticates via the `np_crane_api_key` environment variable, and persists container credentials to the worktree-local repo-root `.env`. Registered in `.claude-plugin/marketplace.json` and documented in `README.md`.

**Tech Stack:** Claude Code plugin/skill format (Markdown + YAML frontmatter), JSON manifests, `curl`, BC Crane SOAP API. No build step, no runtime dependency.

**Testing note (adaptation):** This is a documentation/skill-authoring change, so there is no unit-test framework. The "test" after each task is `claude plugin validate --plugin-dir ./bc-devcontainer` plus JSON-parse checks and content greps — the same verification the README already prescribes for the existing plugins. Verification commands are run *after* creating each file (a pre-creation run would trivially fail because the path doesn't exist yet).

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
  "description": "Provision, reuse, restart, and stop NaviPartner Crane Business Central development containers to compile, publish, and test against",
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
description: This skill should be used when the user needs a Business Central development container/environment to compile, publish, or run tests against - e.g. "spin up a BC dev container", "order a BC environment", "I need a BC sandbox to test against", "restart my BC container", or "tear down the BC container". Provisions, reuses, restarts, and stops NaviPartner Crane BC containers.
---

# Provision BC Dev Container (Crane)

This skill provisions a Business Central development container through the NaviPartner
Crane SOAP API, then wires up an AL project to compile, publish, and test against it.
Use it to get a working BC environment when one is not already available for the current
git worktree.

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

Container credentials are stored in the **repository root `.env`** so that parallel git
worktrees stay isolated and can each target a different container. Resolve the root and
ensure `.env` is gitignored before writing secrets:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
ENV_FILE="$REPO_ROOT/.env"
grep -qxF '.env' "$REPO_ROOT/.gitignore" 2>/dev/null || echo '.env' >> "$REPO_ROOT/.gitignore"
```

The skill reads and writes these variables in `$ENV_FILE`:

| Variable | Meaning |
|----------|---------|
| `BC_CONTAINER_ID` | Crane container id (used to start/stop) |
| `BC_CONTAINER_URL` | Container base URL |
| `BC_CONTAINER_USERNAME` | BC user |
| `BC_CONTAINER_PASSWORD` | BC password |

## Decision: reuse, restart, or create

1. **Read `$ENV_FILE`.** If `BC_CONTAINER_ID` is present, a container already belongs to
   this worktree.
   - Probe it (see *Poll until ready*). If it answers, reuse it as-is - you are done.
   - If it does not answer, it is likely stopped. **Restart it** (see *Restart a stopped
     container*), then poll. Restart does **not** require the 35-minute wait.
2. **Otherwise create a new container** (see *Create a container*).

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
curl -s -X POST "https://api.navipartner.dk/npcase/crane/api/v1/" \
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
</soapenv:Envelope>'
```

**Read the response.** The API returns the assigned URL, credentials, and container id as
VAR/return parameters. The response resembles the following - confirm the exact element
names against the actual XML you receive:

```xml
<CreateCursorContainer_Result xmlns="urn:microsoft-dynamics-schemas/codeunit/CraneAPI">
   <return_value>{containerId}</return_value>
   <containerUrl>https://{assigned-host}</containerUrl>
   <userName>{user}</userName>
   <password>{password}</password>
</CreateCursorContainer_Result>
```

Extract `containerUrl`, `userName`, `password`, and the container id, then write them to
`$ENV_FILE` as `BC_CONTAINER_URL`, `BC_CONTAINER_USERNAME`, `BC_CONTAINER_PASSWORD`, and
`BC_CONTAINER_ID`.

**Then wait a full 35 minutes before making ANY request to the container** (including
health-check polls). The container imports demo data during this window and premature
requests crash the import. Only after the 35-minute grace period should you poll.

### Restart a stopped container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StartContainer`

No 35-minute wait - demo-data import already happened. Start polling immediately after.

```bash
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

### Stop a container

`SOAPAction: urn:microsoft-dynamics-schemas/codeunit/CraneAPI:StopContainer`

Stop the container when you finish your task to free resources.

```bash
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

## Poll until ready

After the 35-minute wait (create) or immediately (restart/reuse), poll the BC sign-in
endpoint following redirects until it responds:

```bash
until [ "$(curl -s -L -o /dev/null -w '%{http_code}' "${BC_CONTAINER_URL}/BC")" = "200" ]; do
  echo "Container not ready yet, waiting 60s..."
  sleep 60
done
echo "Container is ready: ${BC_CONTAINER_URL}/BC"
```

## Wire up the AL project

### launch.json

`launch.json` files are gitignored. Create one per AL project under its
`.vscode/launch.json` (e.g. the main app and the test app each get their own), pointing
at the container:

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

Substitute the real `BC_CONTAINER_URL`. These coordinates feed the `bcdev-cli:bcdev`
skill for symbol download, compile, publish, and test (pass the BC username/password from
`$ENV_FILE`).

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
resources. The credentials remain in `$ENV_FILE`, so a later session can restart the same
container without re-importing demo data.
````

**Step 4: Verify the skill frontmatter and structure**

Run: `head -5 bc-devcontainer/skills/provision-bc-container/SKILL.md`
Expected: shows `---`, `name: provision-bc-container`, a `description:` line, `---`.

Run: `grep -c 'np_crane_api_key' bc-devcontainer/skills/provision-bc-container/SKILL.md`
Expected: a count >= 3 (prereq check, README pointer, curl headers).

Confirm the old name is gone — Run: `! grep -q 'crane_key' bc-devcontainer/skills/provision-bc-container/SKILL.md && echo clean`
Expected: `clean`

**Step 5: Validate the plugin**

Run: `claude plugin validate --plugin-dir ./bc-devcontainer`
Expected: validation passes (no errors).

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

Append this object to the `plugins` array (mind the comma after the existing `bcdev-cli` entry):

```json
{
  "name": "bc-devcontainer",
  "description": "Provision BC development containers via the NaviPartner Crane API - create, reuse, restart, and stop environments to compile, publish, and test against",
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

**Step 2: Verify marketplace JSON is valid and contains the entry**

Run: `python3 -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); print([p['name'] for p in d['plugins']])"`
Expected: `['al-id-manager', 'bcdev-cli', 'bc-devcontainer']`

**Step 3: Re-validate the plugin against the marketplace**

Run: `claude plugin validate --plugin-dir ./bc-devcontainer`
Expected: validation passes.

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

Provisions Business Central development containers via the NaviPartner Crane API so the LLM can compile, publish, and test against a real environment. Creates a new container, reuses or restarts an existing one for the current git worktree, and stops it when done.

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

**Step 3: Extend the Development section** so validate/test loops include the new plugin.

Update the "Validate all plugins" loop:

```bash
# Validate all plugins
for plugin in al-id-manager bcdev-cli bc-devcontainer; do
  claude plugin validate --plugin-dir ./$plugin
done
```

Add to the "Testing locally" block:

```bash
claude --plugin-dir ./bc-devcontainer
```

**Step 4: Verify the README references**

Run: `grep -c 'bc-devcontainer' README.md`
Expected: count >= 4 (install, skill id, validate loop, test-locally).

Run: `grep -c 'np_crane_api_key' README.md`
Expected: count >= 2 (the two export/set examples).

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs(bc-devcontainer): document plugin and np_crane_api_key config"
```

---

### Task 4: Final end-to-end validation

**Files:** none (verification only)

**Step 1: Validate every plugin**

Run:
```bash
for plugin in al-id-manager bcdev-cli bc-devcontainer; do
  echo "== $plugin =="; claude plugin validate --plugin-dir ./$plugin
done
```
Expected: all three pass.

**Step 2: Confirm marketplace JSON parses and lists three plugins**

Run: `python3 -c "import json; d=json.load(open('.claude-plugin/marketplace.json')); assert len(d['plugins'])==3; print('ok')"`
Expected: `ok`

**Step 3: Confirm no stale `crane_key` (old name) remains anywhere new**

Run: `! grep -rn 'crane_key' bc-devcontainer README.md .claude-plugin && echo clean`
Expected: `clean`

**Step 4: Confirm the working tree is clean (everything committed)**

Run: `git status --short`
Expected: empty output.
```
