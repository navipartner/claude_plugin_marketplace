---
name: bcdev
description: This skill should be used when the user wants to "download symbols", "compile AL app", "publish to Business Central", "run BC tests", or is working with Business Central development workflows.
---

# BC Dev CLI

This skill provides instructions for using the BC Dev CLI to download symbols, compile, publish, and test Business Central AL applications.

## Binary Location

**Path:** `${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe`

**Windows (win-x64):**
- SmartScreen may warn on first run; click "More info" → "Run anyway"

## Prerequisites

Before using the CLI, ensure you have:
1. A Business Central environment (SaaS sandbox, hosted, or on-premises)
2. An `app.json` file for your AL project
3. A `.vscode/launch.json` with at least one configuration

## Commands Overview

| Command | Purpose |
|---------|---------|
| `bcdev symbols` | Download symbol packages for dependencies |
| `bcdev compile` | Compile AL app (auto-downloads compiler) |
| `bcdev publish` | Publish .app file to Business Central |
| `bcdev test` | Run tests against Business Central |

## Typical Workflow

```
symbols → compile → publish → test
```

## Command: bcdev symbols

Downloads symbol packages for compilation dependencies. By default, downloads from Microsoft's public NuGet feeds (faster, works offline/CI). Optionally download from a BC server with `-fromServer`.

**NuGet mode (default):**
```bash
# Download symbols from NuGet feeds (no BC server required)
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe symbols -appJsonPath "/path/to/app.json"

# With country-specific packages (e.g., us, de, dk)
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe symbols -appJsonPath "/path/to/app.json" -country us
```

**Server mode (opt-in):**
```bash
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe symbols \
  -appJsonPath "/path/to/app.json" \
  -fromServer \
  -launchJsonPath "/path/to/.vscode/launch.json" \
  -launchJsonName "Your Configuration Name" \
  -Username "bcuser" \
  -Password "bcpassword"
```

**Options:**

| Option | Required | Description |
|--------|----------|-------------|
| `-appJsonPath` | Yes | Path to app.json file |
| `-packageCachePath` | No | Output folder (defaults to .alpackages next to app.json) |
| `-country` | No | Country code for localized symbols (e.g., us, de, dk). Default `w1` uses country-less packages |
| `-fromServer` | No | Download from BC server instead of NuGet feeds |
| `-launchJsonPath` | No* | Path to launch.json (*required with `-fromServer`) |
| `-launchJsonName` | No* | Configuration name (*required with `-fromServer`) |
| `-Username` | No** | For UserPassword auth (**required for UserPassword auth with `-fromServer`) |
| `-Password` | No** | For UserPassword auth (**required for UserPassword auth with `-fromServer`) |

## Command: bcdev compile

Compiles an AL application. The compiler (alc.exe/alc) is automatically downloaded based on the platform version in app.json.

**Usage:**
```bash
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe compile \
  -appJsonPath "/path/to/app.json"
```

**Options:**

| Option | Required | Description |
|--------|----------|-------------|
| `-appJsonPath` | Yes | Path to app.json file |
| `-packageCachePath` | No | Path to .alpackages folder (defaults to .alpackages in app folder) |
| `-suppressWarnings` | No | Suppress compiler warnings from output |

**Output:** Creates a `.app` file in the same directory as app.json.

## Command: bcdev publish

Publishes an AL application to Business Central.

**Usage (pre-compiled .app):**
```bash
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe publish \
  -launchJsonPath "/path/to/.vscode/launch.json" \
  -launchJsonName "Your Configuration Name" \
  -appPath "/path/to/MyApp.app" \
  -Username "bcuser" \
  -Password "bcpassword"
```

**Usage (compile and publish):**
```bash
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe publish \
  -recompile \
  -appJsonPath "/path/to/app.json" \
  -launchJsonPath "/path/to/.vscode/launch.json" \
  -launchJsonName "Your Configuration Name" \
  -Username "bcuser" \
  -Password "bcpassword"
```

**Options:**

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

## Command: bcdev test

Runs tests against Business Central.

**Usage (run all tests):**
```bash
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe test \
  -launchJsonPath "/path/to/.vscode/launch.json" \
  -launchJsonName "Your Configuration Name" \
  -all \
  -Username "bcuser" \
  -Password "bcpassword"
```

**Usage (run specific test):**
```bash
${CLAUDE_PLUGIN_ROOT}/bin/bcdev.exe test \
  -launchJsonPath "/path/to/.vscode/launch.json" \
  -launchJsonName "Your Configuration Name" \
  -CodeunitId 50100 \
  -MethodName "TestSomething" \
  -Username "bcuser" \
  -Password "bcpassword"
```

**Options:**

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

## Authentication

Two authentication methods are supported:

### UserPassword (NavUserPassword)
Pass credentials via command-line options:
```bash
-Username "your-bc-user" -Password "your-bc-password"
```

### Azure AD (Microsoft Entra ID)
When `-Username` and `-Password` are not provided, the CLI uses device code flow:
1. A URL and code are displayed
2. Open the URL in a browser
3. Enter the code to authenticate
4. The CLI receives the token and proceeds

**Note:** Tokens are cached, so you won't need to re-authenticate every time.

## Test Iteration Workflow

When iterating on tests:
- If **test app code** is modified → compile and publish the test app before running tests
- If **primary app code** is modified → compile and publish the primary app before running tests
- Only then run `bcdev test`

## Finding launch.json Configurations

To find available configuration names, read `.vscode/launch.json` and look for objects in the `configurations` array. The `name` field is what you pass to `-launchJsonName`.

Example launch.json:
```json
{
  "configurations": [
    {
      "name": "My Dev Environment",
      "type": "al",
      "server": "https://businesscentral.dynamics.com",
      ...
    }
  ]
}
```

Use: `-launchJsonName "My Dev Environment"`

## Error Handling

Common issues and solutions:

| Error | Solution |
|-------|----------|
| Authentication failed | Check credentials or re-authenticate via device code |
| Symbols not found | Ensure launch.json points to a valid BC environment |
| Compilation failed | Check for AL syntax errors; ensure symbols are downloaded |
| Publish failed | Verify app dependencies are satisfied; check BC permissions |
| Test timeout | Increase `-timeoutMinutes` or check for infinite loops |
