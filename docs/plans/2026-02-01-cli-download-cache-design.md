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
5. Verify integrity via SHA256 checksums

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Plugin structure | Single universal plugin | Simpler for users, single codebase to maintain |
| Binary source | Public GitHub releases | Existing infrastructure, no auth required |
| Checksum verification | SHA256 via checksums.txt | Prevents supply-chain compromise |
| Cache location | `~/.bcdev/cli/v{version}/` | Same base dir as CLI artifacts, survives reinstalls |
| Download trigger | Wrapper scripts | Guarantees binary exists before command runs |
| Version management | Hardcoded + env override | Stable default, power users can override |
| Windows support | Native batch file | Required for Windows users without bash |
| Concurrency control | Lock file during download | Prevents race conditions |

## Supported Platforms

Based on available release assets:

| Platform | Asset Name | Supported |
|----------|------------|-----------|
| macOS arm64 | `bcdev-osx-arm64` | Yes |
| macOS x64 | `bcdev-osx-x64` | Yes |
| Linux x64 | `bcdev-linux-x64` | Yes |
| Linux arm64 | `bcdev-linux-arm64` | Yes |
| Windows x64 | `bcdev-win-x64.exe` | Yes |
| Windows arm64 | N/A | No (not available) |

## Plugin Structure

### New Structure

```
bcdev-cli/
├── .claude-plugin/
│   └── plugin.json
├── bin/
│   ├── bcdev-ensure          # Bash wrapper (macOS/Linux)
│   └── bcdev-ensure.cmd      # Windows batch wrapper
├── checksums.txt             # SHA256 checksums per version/platform
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

## Checksums File Format

The `checksums.txt` file maps version/platform to expected SHA256:

```
# Format: version platform sha256
0.7 osx-arm64 abc123...
0.7 osx-x64 def456...
0.7 linux-x64 789abc...
0.7 linux-arm64 012def...
0.7 win-x64 345ghi...
```

This file is updated when a new CLI version is released.

## Wrapper Script: `bcdev-ensure` (Bash)

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Config
DEFAULT_VERSION="0.7"
VERSION="${BCDEV_CLI_VERSION:-$DEFAULT_VERSION}"
REPO="navipartner/BC-Dev-CLI"

# Validate version format (security: prevent path traversal)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9._]+)?$ ]]; then
  echo "Error: Invalid version format: $VERSION" >&2
  echo "Version must match pattern: X.Y or X.Y.Z (e.g., 0.7, 1.0.0)" >&2
  exit 1
fi

CACHE_DIR="$HOME/.bcdev/cli/v${VERSION}"
LOCK_FILE="$HOME/.bcdev/.lock"
CHECKSUMS_FILE="$SCRIPT_DIR/checksums.txt"

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

  # Validate platform is supported
  local platform="${os}-${arch}"
  case "$platform" in
    osx-arm64|osx-x64|linux-x64|linux-arm64|win-x64)
      echo "$platform"
      ;;
    win-arm64)
      echo "Error: Windows ARM64 is not supported." >&2
      echo "Supported platforms: osx-arm64, osx-x64, linux-x64, linux-arm64, win-x64" >&2
      exit 1
      ;;
    *)
      echo "Error: Unsupported platform: $platform" >&2
      echo "Supported platforms: osx-arm64, osx-x64, linux-x64, linux-arm64, win-x64" >&2
      exit 1
      ;;
  esac
}

# Get expected checksum from checksums.txt
get_expected_checksum() {
  local version="$1" platform="$2"
  if [[ -f "$CHECKSUMS_FILE" ]]; then
    grep "^${version} ${platform} " "$CHECKSUMS_FILE" | awk '{print $3}'
  fi
}

# Verify SHA256 checksum
verify_checksum() {
  local file="$1" expected="$2"
  local actual
  if command -v sha256sum &>/dev/null; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum &>/dev/null; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    echo "Warning: Cannot verify checksum (sha256sum/shasum not found)" >&2
    return 0
  fi

  if [[ "$actual" != "$expected" ]]; then
    echo "Error: Checksum verification failed!" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    return 1
  fi
}

# Download with curl or wget fallback
download_file() {
  local url="$1" output="$2"
  if command -v curl &>/dev/null; then
    curl -fSL "$url" -o "$output"
  elif command -v wget &>/dev/null; then
    wget -q -O "$output" "$url"
  else
    echo "Error: Neither curl nor wget found. Please install one." >&2
    exit 1
  fi
}

# Acquire lock (simple mkdir-based lock)
acquire_lock() {
  local lock_dir="$(dirname "$LOCK_FILE")"
  mkdir -p "$lock_dir"
  local attempts=0
  while ! mkdir "$LOCK_FILE" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ $attempts -ge 30 ]]; then
      echo "Error: Could not acquire lock after 30 seconds" >&2
      exit 1
    fi
    sleep 1
  done
  trap 'rm -rf "$LOCK_FILE"' EXIT
}

# Release lock
release_lock() {
  rm -rf "$LOCK_FILE"
  trap - EXIT
}

# Main
PLATFORM="$(detect_platform)"
BINARY="$CACHE_DIR/bcdev"
[[ "$PLATFORM" == win-* ]] && BINARY="$CACHE_DIR/bcdev.exe"

if [[ ! -x "$BINARY" ]]; then
  acquire_lock

  # Re-check after acquiring lock (another process may have downloaded)
  if [[ ! -x "$BINARY" ]]; then
    mkdir -p "$CACHE_DIR"
    URL="https://github.com/$REPO/releases/download/v${VERSION}/bcdev-${PLATFORM}"
    [[ "$PLATFORM" == win-* ]] && URL="${URL}.exe"

    TEMP_FILE="$(mktemp)"
    trap 'rm -f "$TEMP_FILE"; rm -rf "$LOCK_FILE"' EXIT

    echo "Downloading BC Dev CLI v${VERSION} for ${PLATFORM}..." >&2
    if ! download_file "$URL" "$TEMP_FILE"; then
      echo "Error: Failed to download BC Dev CLI v${VERSION}" >&2
      echo "URL: $URL" >&2
      echo "Check your internet connection or verify the version exists." >&2
      exit 1
    fi

    # Verify checksum if available
    EXPECTED_CHECKSUM="$(get_expected_checksum "$VERSION" "$PLATFORM")"
    if [[ -n "$EXPECTED_CHECKSUM" ]]; then
      echo "Verifying checksum..." >&2
      if ! verify_checksum "$TEMP_FILE" "$EXPECTED_CHECKSUM"; then
        rm -f "$TEMP_FILE"
        exit 1
      fi
    else
      echo "Warning: No checksum available for v${VERSION} ${PLATFORM}" >&2
    fi

    # Atomic move to final location
    chmod +x "$TEMP_FILE"
    mv "$TEMP_FILE" "$BINARY"
    trap 'rm -rf "$LOCK_FILE"' EXIT
  fi

  release_lock
fi

exec "$BINARY" "$@"
```

## Wrapper Script: `bcdev-ensure.cmd` (Windows)

```batch
@echo off
setlocal EnableDelayedExpansion

:: Get script directory
set "SCRIPT_DIR=%~dp0.."

:: Config
set "DEFAULT_VERSION=0.7"
if "%BCDEV_CLI_VERSION%"=="" (set "VERSION=%DEFAULT_VERSION%") else (set "VERSION=%BCDEV_CLI_VERSION%")
set "REPO=navipartner/BC-Dev-CLI"

:: Validate version format (prevent path traversal)
echo %VERSION% | findstr /R "^[0-9][0-9]*\.[0-9][0-9]*" >nul
if %ERRORLEVEL% neq 0 (
    echo Error: Invalid version format: %VERSION% >&2
    echo Version must match pattern: X.Y or X.Y.Z ^(e.g., 0.7, 1.0.0^) >&2
    exit /b 1
)

set "CACHE_DIR=%LOCALAPPDATA%\bcdev\cli\v%VERSION%"
set "BINARY=%CACHE_DIR%\bcdev.exe"
set "LOCK_DIR=%LOCALAPPDATA%\bcdev\.lock"
set "CHECKSUMS_FILE=%SCRIPT_DIR%\checksums.txt"

:: Check if binary exists
if exist "%BINARY%" goto :run

:: Acquire lock (mkdir-based)
set "LOCK_ATTEMPTS=0"
:acquire_lock
mkdir "%LOCK_DIR%" 2>nul
if %ERRORLEVEL% neq 0 (
    set /a LOCK_ATTEMPTS+=1
    if !LOCK_ATTEMPTS! geq 30 (
        echo Error: Could not acquire lock after 30 seconds >&2
        exit /b 1
    )
    timeout /t 1 /nobreak >nul
    goto :acquire_lock
)

:: Re-check after lock
if exist "%BINARY%" goto :release_and_run

:: Create cache directory
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

:: Download
set "URL=https://github.com/%REPO%/releases/download/v%VERSION%/bcdev-win-x64.exe"
set "TEMP_FILE=%TEMP%\bcdev-download-%RANDOM%.exe"

echo Downloading BC Dev CLI v%VERSION% for Windows... >&2

:: Use curl (Windows 10+) or PowerShell fallback with TLS 1.2
where curl >nul 2>&1
if %ERRORLEVEL%==0 (
    curl -fSL "%URL%" -o "%TEMP_FILE%"
) else (
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%URL%' -OutFile '%TEMP_FILE%'"
)

if %ERRORLEVEL% neq 0 (
    echo Error: Failed to download BC Dev CLI v%VERSION% >&2
    echo URL: %URL% >&2
    del "%TEMP_FILE%" 2>nul
    rmdir "%LOCK_DIR%" 2>nul
    exit /b 1
)

:: Verify checksum if available
if exist "%CHECKSUMS_FILE%" (
    for /f "tokens=3" %%a in ('findstr /B /C:"%VERSION% win-x64 " "%CHECKSUMS_FILE%"') do set "EXPECTED_CHECKSUM=%%a"
    if defined EXPECTED_CHECKSUM (
        echo Verifying checksum... >&2
        for /f "skip=1 tokens=*" %%b in ('certutil -hashfile "%TEMP_FILE%" SHA256') do (
            if not defined ACTUAL_CHECKSUM set "ACTUAL_CHECKSUM=%%b"
        )
        set "ACTUAL_CHECKSUM=!ACTUAL_CHECKSUM: =!"
        if /i "!ACTUAL_CHECKSUM!" neq "!EXPECTED_CHECKSUM!" (
            echo Error: Checksum verification failed! >&2
            echo Expected: !EXPECTED_CHECKSUM! >&2
            echo Actual:   !ACTUAL_CHECKSUM! >&2
            del "%TEMP_FILE%" 2>nul
            rmdir "%LOCK_DIR%" 2>nul
            exit /b 1
        )
    ) else (
        echo Warning: No checksum available for v%VERSION% win-x64 >&2
    )
)

:: Atomic move to final location
move /y "%TEMP_FILE%" "%BINARY%" >nul

:release_and_run
rmdir "%LOCK_DIR%" 2>nul

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
The binary is cached at:
- **macOS/Linux**: `~/.bcdev/cli/v{version}/bcdev`
- **Windows**: `%LOCALAPPDATA%\bcdev\cli\v{version}\bcdev.exe`
```

### Platform Notes

```markdown
## Platform Notes

The CLI is automatically downloaded for your platform on first invocation.

**Supported platforms:** macOS (arm64, x64), Linux (x64, arm64), Windows (x64)

- **macOS**: May require quarantine removal on first run:
  `xattr -dr com.apple.quarantine ~/.bcdev/cli/`
- **Linux**: Binary is made executable automatically
- **Windows**: Runs natively via batch wrapper

To use a different CLI version:
- macOS/Linux: `export BCDEV_CLI_VERSION=0.8`
- Windows: `set BCDEV_CLI_VERSION=0.8`
```

## Cache Structure

```
# macOS/Linux
~/.bcdev/
├── .lock/                    # Lock directory (temporary during download)
├── cache/                    # CLI artifacts (compiler, symbols) - managed by bcdev
└── cli/
    ├── v0.7/
    │   └── bcdev
    └── v0.8/
        └── bcdev

# Windows
%LOCALAPPDATA%\bcdev\
├── .lock\                    # Lock directory (temporary during download)
├── cache\                    # CLI artifacts (compiler, symbols) - managed by bcdev
└── cli\
    ├── v0.7\
    │   └── bcdev.exe
    └── v0.8\
        └── bcdev.exe
```

Versioned directories allow multiple versions to coexist and enable easy rollback.

## Security Measures

| Measure | Implementation |
|---------|----------------|
| Checksum verification | SHA256 verified against checksums.txt before execution |
| Version validation | Regex prevents path traversal via malicious VERSION |
| Atomic download | Download to temp file, verify, then move |
| Lock file | Prevents race conditions during concurrent downloads |
| TLS enforcement | PowerShell fallback forces TLS 1.2+ |

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
| Download fails | Clear error message with URL, shows curl/wget stderr |
| Invalid version format | Error with expected format pattern |
| Checksum mismatch | Error with expected vs actual hash |
| Unsupported platform | Error listing supported platforms |
| Lock timeout | Error after 30 seconds |
| No curl/wget | Error with install instructions |
| macOS quarantine | Documented xattr -dr command in skill |

## Implementation Order

1. Generate checksums for current release (v0.7)
2. Create `bcdev-cli/` directory structure
3. Write `checksums.txt`
4. Write `bcdev-ensure` bash wrapper
5. Write `bcdev-ensure.cmd` Windows wrapper
6. Write `plugin.json`
7. Write updated `SKILL.md`
8. Update `marketplace.json`
9. Update `README.md`
10. Delete old platform-specific plugin directories
11. Delete `templates/` and `scripts/`
12. Test on macOS, Linux, and Windows
13. Commit and push

## Maintenance: Adding New CLI Versions

When a new BC Dev CLI version is released:

1. Download all platform binaries
2. Generate SHA256 checksums
3. Add entries to `checksums.txt`
4. Update `DEFAULT_VERSION` in both wrapper scripts
5. Bump plugin version in `plugin.json` and `marketplace.json`
6. Commit and push
