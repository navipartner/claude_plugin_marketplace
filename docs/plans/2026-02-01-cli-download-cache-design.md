# BC Dev CLI Download & Cache Design

## Overview

This document describes the design for migrating the BC Dev CLI plugin from bundled binaries to on-demand download with local caching. This solves git clone timeouts caused by ~320MB of binaries stored in the repository.

## Problem Statement

The current plugin marketplace stores 4 platform-specific BC Dev CLI plugins, each containing a large binary (~78-85MB). When users install plugins via `claude plugin install`, it clones the Git repo, causing timeouts due to the total binary size (~320MB).

## Solution

1. Make the BC-Dev-CLI GitHub repo public
2. Replace 4 platform-specific plugins with 1 universal plugin
3. Download binaries on-demand from GitHub releases
4. Cache binaries in user's home directory

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Plugin structure | Single universal plugin | Simpler for users, single codebase to maintain |
| Binary source | Public GitHub releases | Existing infrastructure, no auth required |
| Checksum verification | Skip for now | Trust HTTPS + GitHub; can add later |
| Cache location | `~/.bcdev-cli/v{version}/` | Simple, cross-platform, survives reinstalls |
| Download trigger | Wrapper scripts | Guarantees binary exists before command runs |
| Version management | Hardcoded + env override | Stable default, power users can override |
| Windows support | Native batch file | Required for Windows users without bash |

## Plugin Structure

### New Structure

```
bcdev-cli/
├── .claude-plugin/
│   └── plugin.json
├── bin/
│   ├── bcdev-ensure          # Bash wrapper (macOS/Linux)
│   └── bcdev-ensure.cmd      # Windows batch wrapper
└── skills/
    └── bcdev/
        └── SKILL.md
```

### Files to Delete

- `bcdev-cli-win-x64/` (entire directory including 78MB binary)
- `bcdev-cli-linux-x64/` (entire directory including 78MB binary)
- `bcdev-cli-linux-arm64/` (entire directory including 85MB binary)
- `bcdev-cli-osx-arm64/` (entire directory including 84MB binary)
- `templates/` (no longer needed for sync)
- `scripts/sync-skills.sh` (no longer needed)

### Files to Update

- `.claude-plugin/marketplace.json` - Replace 4 entries with 1
- `README.md` - Update install instructions

## Wrapper Script: `bcdev-ensure` (Bash)

```bash
#!/usr/bin/env bash
set -euo pipefail

# Config
VERSION="${BCDEV_CLI_VERSION:-0.7}"
REPO="navipartner/BC-Dev-CLI"
CACHE_DIR="$HOME/.bcdev-cli/v${VERSION}"

# Platform detection
detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Darwin) os="osx" ;;
    Linux)  os="linux" ;;
    MINGW*|MSYS*|CYGWIN*) os="win" ;;
    *) echo "Error: Unsupported OS: $os" >&2; exit 1 ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "Error: Unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  echo "${os}-${arch}"
}

# Main
PLATFORM="$(detect_platform)"
BINARY="$CACHE_DIR/bcdev"
[[ "$PLATFORM" == win-* ]] && BINARY="$CACHE_DIR/bcdev.exe"

if [[ ! -x "$BINARY" ]]; then
  mkdir -p "$CACHE_DIR"
  URL="https://github.com/$REPO/releases/download/v${VERSION}/bcdev-${PLATFORM}"
  [[ "$PLATFORM" == win-* ]] && URL="${URL}.exe"

  echo "Downloading BC Dev CLI v${VERSION} for ${PLATFORM}..." >&2
  if ! curl -fSL "$URL" -o "$BINARY" 2>/dev/null; then
    echo "Error: Failed to download BC Dev CLI v${VERSION}" >&2
    echo "URL: $URL" >&2
    echo "Check your internet connection or try: export BCDEV_CLI_VERSION=0.7" >&2
    exit 1
  fi
  chmod +x "$BINARY"
fi

exec "$BINARY" "$@"
```

## Wrapper Script: `bcdev-ensure.cmd` (Windows)

```batch
@echo off
setlocal EnableDelayedExpansion

:: Config
if "%BCDEV_CLI_VERSION%"=="" (set "VERSION=0.7") else (set "VERSION=%BCDEV_CLI_VERSION%")
set "REPO=navipartner/BC-Dev-CLI"
set "CACHE_DIR=%USERPROFILE%\.bcdev-cli\v%VERSION%"
set "BINARY=%CACHE_DIR%\bcdev.exe"

:: Check if binary exists
if exist "%BINARY%" goto :run

:: Create cache directory
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

:: Download
set "URL=https://github.com/%REPO%/releases/download/v%VERSION%/bcdev-win-x64.exe"
echo Downloading BC Dev CLI v%VERSION% for Windows... >&2

:: Use curl (Windows 10+) or PowerShell fallback
where curl >nul 2>&1
if %ERRORLEVEL%==0 (
    curl -fSL "%URL%" -o "%BINARY%"
) else (
    powershell -Command "Invoke-WebRequest -Uri '%URL%' -OutFile '%BINARY%'"
)

if %ERRORLEVEL% neq 0 (
    echo Error: Failed to download BC Dev CLI v%VERSION% >&2
    echo URL: %URL% >&2
    exit /b 1
)

:run
"%BINARY%" %*
```

## Marketplace Configuration

### Updated `marketplace.json`

```json
{
  "plugins": [
    {
      "name": "al-id-manager",
      "version": "1.0.0",
      "description": "Request next available AL object/field IDs",
      "category": "Business Central",
      "tags": ["al", "business-central", "ids"]
    },
    {
      "name": "bcdev-cli",
      "version": "2.0.0",
      "description": "BC Dev CLI - download symbols, compile, publish, and test AL apps",
      "category": "Business Central",
      "tags": ["al", "business-central", "cli", "compile", "publish", "test"]
    }
  ]
}
```

Version 2.0.0 signals breaking change (different plugin name).

## SKILL.md Updates

### Binary Location

```markdown
## Binary Location

- **macOS/Linux**: `${CLAUDE_PLUGIN_ROOT}/bin/bcdev-ensure`
- **Windows**: `${CLAUDE_PLUGIN_ROOT}\bin\bcdev-ensure.cmd`

The wrapper automatically downloads the correct binary for your platform on first use.
The binary is cached at `~/.bcdev-cli/v{version}/`.
```

### Platform Notes

```markdown
## Platform Notes

The CLI is automatically downloaded for your platform on first invocation.

- **macOS**: May require quarantine removal on first run:
  `xattr -d com.apple.quarantine ~/.bcdev-cli/v*/bcdev`
- **Linux**: Binary is made executable automatically
- **Windows**: Runs natively via batch wrapper

To use a different CLI version: `export BCDEV_CLI_VERSION=0.8` (or `set BCDEV_CLI_VERSION=0.8` on Windows)
```

## Cache Structure

```
~/.bcdev-cli/
├── v0.7/
│   └── bcdev (or bcdev.exe on Windows)
└── v0.8/
    └── bcdev
```

Versioned directories allow multiple versions to coexist and enable easy rollback.

## User Migration

### For Existing Users

1. Uninstall old plugin:
   ```
   claude plugin uninstall bcdev-cli-osx-arm64@navipartner-bc-tools
   ```

2. Install new universal plugin:
   ```
   claude plugin install bcdev-cli@navipartner-bc-tools
   ```

### Install Commands

Before (platform-specific):
- `claude plugin install bcdev-cli-osx-arm64@navipartner-bc-tools`
- `claude plugin install bcdev-cli-linux-x64@navipartner-bc-tools`
- `claude plugin install bcdev-cli-win-x64@navipartner-bc-tools`

After (universal):
- `claude plugin install bcdev-cli@navipartner-bc-tools`

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Download fails | Clear error message with URL and troubleshooting hint |
| Invalid version | curl 404 error with message |
| No internet | Fails with connection error |
| macOS quarantine | Documented xattr command in skill |

## Future Enhancements

- Add SHA256 checksum verification
- Add `--version` flag to check installed version
- Add `--update` flag to force re-download
- macOS code signing and notarization

## Implementation Order

1. Create `bcdev-cli/` directory structure
2. Write `bcdev-ensure` bash wrapper
3. Write `bcdev-ensure.cmd` Windows wrapper
4. Write `plugin.json`
5. Write updated `SKILL.md`
6. Update `marketplace.json`
7. Update `README.md`
8. Delete old platform-specific plugin directories
9. Delete `templates/` and `scripts/`
10. Test on macOS, Linux, and Windows
11. Commit and push
