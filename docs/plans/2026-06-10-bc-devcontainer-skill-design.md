# BC Dev Container Provisioning Skill — Design

Date: 2026-06-10

## Motivation

BC repositories (e.g. `npcore`) carry a repo-specific `CLOUD_AGENTS.md` that tells
cloud/dev agents how to order their own Business Central development container via the
NaviPartner **Crane** SOAP API, wait for it to finish importing demo data, wire up
`launch.json` / `app.json`, and tear it down afterwards.

We want to replace that per-repo markdown with a shared, installable skill in this
marketplace so any BC repo gets the capability via
`bc-devcontainer:provision-bc-container` instead of maintaining its own copy.

## Decisions

- **New standalone plugin** `bc-devcontainer`, registered in `marketplace.json`,
  mirroring `al-id-manager` / `bcdev-cli`. Matches the existing
  `bc-devcontainer-skill` workspace symlink.
- **Single self-contained `SKILL.md`** with inline SOAP envelopes — matches the
  repo convention (`bcdev`, `get-next-id` are both single-file skills). No binary or
  helper files; SOAP calls are issued with `curl`, consistent with `al-id-manager`.
- **Skill id:** `bc-devcontainer:provision-bc-container`. Description tuned to trigger
  on "need a BC environment/container to test against", "spin up / order a BC dev
  container", "restart my BC container", "tear down the container".
- **Input secret:** read from the **`np_crane_api_key`** environment variable. The
  skill verifies it is set; if missing it **halts and asks the developer to configure
  it** rather than proceeding or inventing a value. The README documents only the
  variable name and how to set it. No real key value is read from any machine or
  embedded anywhere.
- **Crane API semantics:** `CreateCursorContainer` returns `containerUrl`, `userName`,
  `password`, and `containerId` (VAR / return parameters). The skill parses the SOAP
  response and extracts them. Exact response element names are shown as a
  representative example and the skill instructs the agent to confirm them against the
  actual returned XML.
- **Output credentials** (url, username, password, containerId) are saved to the
  **repo / worktree root `.env`** — located via `git rev-parse --show-toplevel`, not
  `~/.env`. This keeps parallel git worktrees isolated so different agents can work
  against different environments simultaneously. The reuse check reads that same
  worktree-local `.env`.
- The skill **ensures `.env` is gitignored** in the consuming repo before writing
  secrets to it.

### Scope kept (generic to any BC app repo)

- Full provisioning lifecycle: reuse-or-create, 35-minute import wait, poll-until-ready,
  start a stopped container, stop when done.
- `launch.json` wiring: per project `.vscode/launch.json`, port 443,
  `serverInstance: "BC"`, `authentication: "UserPassword"`.
- `app.json` version targeting: temporarily match the container's BC version; formula
  **`runtime = BC_version − 11`** (example `BC27 → 16.0`); set `preprocessorSymbols` to
  only the target version; back up `app.json.orig`; do not commit.
- POS testing tip: append **`?page=6150750`** to the BC URL to open the POS page.

### Scope dropped (npcore-specific)

- npcore's pinned versions ("checked-in `app.json` targets BC17", "CLOUD-CORE currently
  = BC27").
- Control-addin case-sensitivity symlink (`_ControlAddIns` → `_ControlAddins`).
- Fern API documentation repository reference.
- npcore monorepo overview (`Application/`, `Test/` paths).

## Files

```
bc-devcontainer/.claude-plugin/plugin.json              (new)
bc-devcontainer/skills/provision-bc-container/SKILL.md  (new)
.claude-plugin/marketplace.json                         (edit: register plugin)
README.md                                               (edit: plugin section + np_crane_api_key config)
docs/plans/2026-06-10-bc-devcontainer-skill-design.md   (this doc)
```

`plugin.json` mirrors the siblings: `name`, `version: "1.0.0"`, `description`,
NaviPartner author, `license: "UNLICENSED"`.

## Lifecycle encoded in SKILL.md

1. **Verify `np_crane_api_key`.** If unset, stop and ask the developer to configure it.
2. **Locate repo root** via `git rev-parse --show-toplevel`; ensure `.env` is gitignored.
3. **Reuse check.** If the root `.env` already has a `BC_CONTAINER_ID`, call
   `StartContainer` (no 35-minute wait) and poll immediately. Otherwise create new.
4. **Create.** `POST https://api.navipartner.dk/npcase/crane/api/v1/` with
   `Ocp-Apim-Subscription-Key: ${np_crane_api_key}`,
   `SOAPAction …/CraneAPI:CreateCursorContainer`, body using the `CLOUD-CORE` template
   (described as "the template providing the latest released BC version" — no pinned
   number).
5. **Read response** → extract `containerUrl`, `userName`, `password`, `containerId`;
   save to the root `.env` as `BC_CONTAINER_URL`, `BC_CONTAINER_USERNAME`,
   `BC_CONTAINER_PASSWORD`, `BC_CONTAINER_ID`.
6. **Wait** a full **35 minutes** before any request (demo-data import; premature polls
   crash the import). Stated as a hard rule.
7. **Poll** `{containerUrl}/BC` following redirects until the sign-in page responds.
8. **Use** — wire `launch.json` + `app.json` targeting, then compile/publish/test (via
   the `bcdev-cli` skill).
9. **Stop** with `SOAPAction …/CraneAPI:StopContainer` by `containerId` when done.
   Restart later via `StartContainer` (no 35-minute wait).

`StartContainer` / `StopContainer` reuse the same endpoint and auth header with the
matching `SOAPAction`.

## Security & ops

- Secret supplied via environment variable; never echoed or logged. Container password
  likewise not printed.
- Crane auth uses a request **header** (`Ocp-Apim-Subscription-Key`), not a query
  string, limiting exposure in proxy/access logs.
- Credentials at rest live in the worktree-local `.env`, gitignored, isolated per
  worktree.
- Provisioning is expensive (~35-minute import). The reuse-or-create check plus
  stop-when-done avoid needless re-provisioning; the 35-minute wait applies only on
  first create, not on restart.

## Non-goals

- Editing npcore's `CLOUD_AGENTS.md` to remove migrated content / point at the skill —
  a separate follow-up in the npcore repo. When that doc is retired, its non-Crane
  guidance (control-addin symlink, Fern pointer) must be relocated, not lost.
- Wrapping the Crane SOAP calls in a binary/CLI — the skill uses `curl`.

## Post-review revisions (GPT-5.5 plan review)

The implementation plan was reviewed by GPT-5.5 (extra-high reasoning) via `pal:clink`.
Verified findings folded into the plan and skill:

- **Readiness marker (correctness):** credentials are saved before the 35-minute import
  wait, so a resumed/parallel session could otherwise reuse-and-probe a container still
  mid-import and crash it. The skill now persists `BC_CONTAINER_READY_AFTER` (epoch) and
  `BC_CONTAINER_READY`; reuse never probes/restarts until readiness is confirmed, and a
  not-yet-ready record waits out the remaining window instead.
- **CLI syntax:** `claude plugin validate <path>` is correct; `--plugin-dir` is not a
  valid `validate` option (verified on CLI 2.1.146). Plan and the README lines it touches
  use the positional form.
- **Marketplace validation gate:** validate `marketplace.json` itself (not just JSON
  parse). A pre-existing, unrelated warning exists today (`bcdev-cli` entry `2.0.0` vs
  `plugin.json` `2.3.0`); the new entry must add no new warning. Whether to fix the
  pre-existing drift is an open decision, not silently bundled in.
- **Safe `.env` I/O:** quote-escaped upsert + non-`eval` read helpers so special
  characters in a generated password cannot break parsing or expand.
- **`.gitignore` safety:** use `git check-ignore` (covers all ignore sources) and append
  to `.git/info/exclude` rather than dirtying a tracked `.gitignore`; fail closed if
  `.env` is already tracked.
- **Fail-closed parsing:** require all four returned values non-empty before writing.
- **Bounded poll:** per-request `--max-time` and an overall deadline; no infinite wait.
- **Decision-tree robustness:** require all four stored fields; clear failure branch when
  restart does not recover.
- **Triggering:** narrowed the frontmatter `description` to provision/order/reuse/
  restart/stop intents and deferred compile/publish/test to `bcdev-cli` to avoid
  over-firing.
- **SOAPAction provisionality:** `StartContainer`/`StopContainer` action names are
  inferred from the `CreateCursorContainer` pattern; the skill flags this and says to
  verify against the service contract if a fault occurs.

## Post-implementation code-review hardening (commit dc2b42e)

After the skill was implemented, GPT-5.5 (extra-high) code-reviewed the shipped
`SKILL.md` via `pal:clink`. One blocking bug and four should-fix issues were found and
fixed (re-review confirmed all resolved, no regressions). The shipped
`bc-devcontainer/skills/provision-bc-container/SKILL.md` is authoritative; the copy
embedded in the implementation plan is the pre-hardening snapshot.

- **Worktree-safe ignore path (blocking):** `.git` is a *file* in a linked worktree, so
  the original `echo '.env' >> "$REPO_ROOT/.git/info/exclude"` failed in exactly the
  parallel-worktree scenario the skill targets. Now resolved via
  `git rev-parse --git-path info/exclude` from within `$REPO_ROOT`.
- **`.env` single-quote round-trip:** `get_env_var` now reverses `set_env_var`'s
  `'\''` escaping, so a generated password containing a quote round-trips correctly
  (verified for `pa'ss`, `a"b$c d=e`, `tri'ple''quote`).
- **Readiness embargo fails closed:** missing/non-numeric `BC_CONTAINER_READY_AFTER` now
  halts instead of polling a container that may still be importing demo data.
- **`set -e` probe guard:** the reuse probe uses `code=$(curl …) || code=000` so a
  transport failure routes to the restart branch instead of aborting.
- **No password leak:** a failed `CreateCursorContainer` response is redacted
  (`<password>` → `[REDACTED]`) before being surfaced for debugging.
- **SOAP fault check:** Start/Stop responses are inspected for `<faultstring>` /
  `<faultcode>` before polling/finishing.
