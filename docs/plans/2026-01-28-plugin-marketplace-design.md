# Claude Code Plugin Marketplace Design

## Overview

This document describes the design for a Claude Code plugin marketplace containing plugins for Business Central AL development. The marketplace will include:

1. **AL ID Manager** - A skill that instructs LLMs how to request next available IDs for AL objects and fields
2. **BC Dev CLI** (4 variants) - Skills that describe how to use the BC Dev CLI for downloading symbols, compiling, publishing, and testing AL apps

## Design Decisions

- **Internal use only**: This marketplace is for internal employees; API credentials are hardcoded in skills
- **Separate platform plugins**: 4 BC Dev CLI plugins (one per OS/arch) with binaries committed to repo
- **Skills are instructional**: They guide the LLM on what commands/requests to make; execution happens via Bash tool

## Marketplace Structure

```
curitiba/
├── .claude-plugin/
│   └── marketplace.json           # Marketplace index
├── templates/
│   └── bcdev-skill.md             # Canonical BC Dev CLI skill (copied to each plugin)
├── scripts/
│   └── sync-skills.sh             # Copies template to all BC Dev CLI plugins
├── al-id-manager/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   └── skills/
│       └── get-next-id/
│           └── SKILL.md
├── bcdev-cli-win-x64/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/
│   │   └── bcdev.exe
│   └── skills/
│       └── bcdev/
│           └── SKILL.md
├── bcdev-cli-linux-x64/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/
│   │   └── bcdev
│   └── skills/
│       └── bcdev/
│           └── SKILL.md
├── bcdev-cli-linux-arm64/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/
│   │   └── bcdev
│   └── skills/
│       └── bcdev/
│           └── SKILL.md
├── bcdev-cli-osx-arm64/
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── bin/
│   │   └── bcdev
│   └── skills/
│       └── bcdev/
│           └── SKILL.md
├── .github/
│   └── workflows/
│       └── validate.yml
└── README.md
```

## Plugin 1: AL ID Manager

### Purpose

Provides instructions for LLMs to request next available IDs from the AL ID Manager backend when working with Business Central AL files.

### Skill Description

```
This skill should be used when the user is working in .al files for Business Central apps and creating new objects or adding new table/tableextension fields or enum/enumextension values.
```

### API Endpoints

All requests go to the internal AL ID Manager endpoint (URL and API key hardcoded in SKILL.md for internal use).

| Use Case | Endpoint | Request Body |
|----------|----------|--------------|
| New AL object | `POST /api/object/next/{appId}` | `{ "type": "<object-type>", "ranges": [...] }` |
| New table field | `POST /api/table/next/{appId}` | `{ "tableId": <id>, "ranges": [...] }` |
| New tableextension field | `POST /api/tableextension/next/{appId}` | `{ "tableextensionId": <id>, "ranges": [...] }` |
| New enum value | `POST /api/enum/next/{appId}` | `{ "enumId": <id>, "ranges": [...] }` |
| New enumextension value | `POST /api/enumextension/next/{appId}` | `{ "enumextensionId": <id>, "ranges": [...] }` |

### Supported Object Types

`table`, `page`, `codeunit`, `report`, `query`, `xmlport`, `enum`, `enumextension`, `tableextension`, `pageextension`, `reportextension`, `interface`, `permissionset`, `permissionsetextension`, `entitlement`, `controladdin`, `profile`, `pagecustomization`, `dotnet`, `requestpage`

### Request/Response Format

**Request:**
- Content-Type: `application/json`
- `appId`: The `id` field from `app.json`
- `ranges`: Array of `{ "from": number, "to": number }` objects
  - For objects and extensions: use `idRanges` from `app.json`
  - For table/enum fields: use `[{ "from": 1, "to": 999999 }]`
- `type`: (objects only) The AL object type being created

**Response:**
```json
{
  "id": 50100,
  "available": true
}
```

## Plugin 2-5: BC Dev CLI

### Purpose

Provides instructions for LLMs to use the BC Dev CLI for Business Central AL development workflows: downloading symbols, compiling apps, publishing to BC, and running tests.

### Skill Content Management

To prevent drift between the 4 platform variants, maintain a single source of truth:
- `templates/bcdev-skill.md` - The canonical SKILL.md content
- A build script copies this to each plugin's `skills/bcdev/SKILL.md`, adjusting only the binary path

### Versioning Strategy

| Version | Description |
|---------|-------------|
| Plugin version (in `plugin.json`) | Incremented when skill content or plugin structure changes |
| BC Dev CLI version (binary) | Tracked in plugin description, e.g., "BC Dev CLI v0.4" |

When updating the binary, increment the plugin version and update marketplace.json.

### Skill Description

```
This skill should be used when the user wants to "download symbols", "compile AL app", "publish to Business Central", "run BC tests", or is working with Business Central development workflows.
```

### Platform Variants

| Plugin | Binary | Target |
|--------|--------|--------|
| `bcdev-cli-win-x64` | `bcdev.exe` | Windows x64 |
| `bcdev-cli-linux-x64` | `bcdev` | Linux x64 |
| `bcdev-cli-linux-arm64` | `bcdev` | Linux ARM64 |
| `bcdev-cli-osx-arm64` | `bcdev` | macOS Apple Silicon |

### Commands

#### `bcdev symbols` - Download Symbol Packages

Downloads symbol packages from Business Central for compilation dependencies.

| Option | Required | Description |
|--------|----------|-------------|
| `-appJsonPath` | Yes | Path to app.json file |
| `-launchJsonPath` | Yes | Path to launch.json |
| `-launchJsonName` | Yes | Configuration name in launch.json |
| `-packageCachePath` | No | Output folder (defaults to .alpackages next to app.json) |
| `-Username` | No | For UserPassword auth |
| `-Password` | No | For UserPassword auth |

#### `bcdev compile` - Compile AL App

Compiles an AL application using alc.exe (auto-downloaded based on platform version).

| Option | Required | Description |
|--------|----------|-------------|
| `-appJsonPath` | Yes | Path to app.json file |
| `-packageCachePath` | No | Path to .alpackages folder (defaults to .alpackages in app folder) |
| `-suppressWarnings` | No | Suppress compiler warnings from output |

#### `bcdev publish` - Publish to Business Central

Publishes an AL application to Business Central.

| Option | Required | Description |
|--------|----------|-------------|
| `-launchJsonPath` | Yes | Path to launch.json |
| `-launchJsonName` | Yes | Configuration name |
| `-appPath` | Yes* | Path to .app file (*required if not using -recompile) |
| `-recompile` | No | Compile before publishing |
| `-appJsonPath` | Yes* | Path to app.json (*required if using -recompile) |
| `-packageCachePath` | No | Package cache for recompile |
| `-Username` | No | For UserPassword auth |
| `-Password` | No | For UserPassword auth |

#### `bcdev test` - Run Tests

Runs tests against Business Central.

| Option | Required | Description |
|--------|----------|-------------|
| `-launchJsonPath` | Yes | Path to launch.json |
| `-launchJsonName` | Yes | Configuration name |
| `-Username` | No | For UserPassword auth |
| `-Password` | No | For UserPassword auth |
| `-CodeunitId` | No | Specific test codeunit ID |
| `-MethodName` | No | Specific test method name |
| `-all` | No | Run all test codeunits (default: false) |
| `-testSuite` | No | Test suite name (default: "DEFAULT") |
| `-timeoutMinutes` | No | Timeout in minutes (default: 30) |

### Typical Workflow

```
symbols → compile → publish → test
```

### Test Iteration Note

When iterating on tests:
- If **test app code** is modified → compile and publish the test app before running tests
- If **primary app code** is modified → compile and publish the primary app before running tests
- Only then run `bcdev test`

### Authentication

Two authentication methods supported:
1. **UserPassword (NavUserPassword)**: Use `-Username` and `-Password` options
2. **Azure AD (Microsoft Entra ID)**: Device code flow - CLI prompts for browser authentication if needed

### Platform-Specific Notes

**macOS (osx-arm64):**
- Binary may be quarantined after download. Remove with: `xattr -d com.apple.quarantine ${CLAUDE_PLUGIN_ROOT}/bin/bcdev`
- May require approval in System Preferences > Security & Privacy on first run

**Linux (x64/arm64):**
- Ensure binary is executable: `chmod +x ${CLAUDE_PLUGIN_ROOT}/bin/bcdev`

**Windows (win-x64):**
- SmartScreen may warn on first run; click "More info" → "Run anyway"

## Validation Pipeline

### Local Development

```bash
# Test plugin loading
claude --plugin-dir ./al-id-manager

# Validate plugin structure
claude plugin validate --plugin-dir ./al-id-manager
```

### GitHub Actions CI

`.github/workflows/validate.yml`:

```yaml
name: Validate Plugins

on: [push, pull_request]

jobs:
  validate-structure:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install Claude Code
        run: npm install -g @anthropic-ai/claude-code

      - name: Validate AL ID Manager
        run: claude plugin validate --plugin-dir ./al-id-manager

      - name: Validate BC Dev CLI plugins
        run: |
          for plugin in bcdev-cli-win-x64 bcdev-cli-linux-x64 bcdev-cli-linux-arm64 bcdev-cli-osx-arm64; do
            echo "Validating $plugin..."
            claude plugin validate --plugin-dir ./$plugin
          done

      - name: Validate JSON syntax
        run: |
          for f in $(find . -name "*.json" -not -path "./.git/*"); do
            echo "Checking $f..."
            jq . "$f" > /dev/null
          done

  smoke-test-linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check binary exists and is executable
        run: |
          chmod +x ./bcdev-cli-linux-x64/bin/bcdev
          ./bcdev-cli-linux-x64/bin/bcdev --help

  smoke-test-macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check binary exists and runs
        run: |
          chmod +x ./bcdev-cli-osx-arm64/bin/bcdev
          ./bcdev-cli-osx-arm64/bin/bcdev --help

  smoke-test-windows:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Check binary exists and runs
        run: ./bcdev-cli-win-x64/bin/bcdev.exe --help
```

## Implementation Order

1. Create marketplace structure and `marketplace.json`
2. Create AL ID Manager plugin with skill
3. Create BC Dev CLI skill template in `templates/bcdev-skill.md`
4. Download BC Dev CLI binaries from GitHub releases (v0.4)
5. Create 4 BC Dev CLI plugins with `plugin.json` and binary
6. Create `scripts/sync-skills.sh` to copy template to all plugins
7. Run sync script to populate all SKILL.md files
8. Add GitHub Actions validation workflow
9. Update README with installation instructions

## Binary Sources

BC Dev CLI binaries will be downloaded from:
`https://github.com/user/BC-Dev-CLI/releases/tag/v0.4`

Files:
- `bcdev-win-x64.exe` → `bcdev-cli-win-x64/bin/bcdev.exe`
- `bcdev-linux-x64` → `bcdev-cli-linux-x64/bin/bcdev`
- `bcdev-linux-arm64` → `bcdev-cli-linux-arm64/bin/bcdev`
- `bcdev-osx-arm64` → `bcdev-cli-osx-arm64/bin/bcdev`
