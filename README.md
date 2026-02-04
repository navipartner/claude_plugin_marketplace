# NaviPartner BC Tools - Claude Code Plugin Marketplace

A Claude Code plugin marketplace for Business Central AL development at NaviPartner.

## Installation

Add this marketplace to Claude Code:

```bash
claude /plugin add-marketplace https://github.com/navipartner/claude_plugin_marketplace
```

Then install the plugins you need:

```bash
# AL ID Manager
claude plugin install al-id-manager@navipartner-bc-tools

# BC Dev CLI (universal - works on all platforms)
claude plugin install bcdev-cli@navipartner-bc-tools
```

## Plugins

### AL ID Manager

Allows the LLM to grab next AL object ID or next AL table/tableextension/enum/enumextension field/value ID from the NaviPartner AL ID Manager service.

**Use when:** Creating new AL objects, adding fields to tables/tableextensions, or adding values to enums/enumextensions.

**Skill:** `al-id-manager:get-next-id`

#### Configuration

Create a config file at:
- macOS/Linux: `~/.al-id-manager/config.json`
- Windows: `%USERPROFILE%\.al-id-manager\config.json`

```json
{
  "apiKey": "your-api-key-here",
  "baseUrl": "https://al-id-manager.npretail.io"
}
```

### BC Dev CLI

Allows the LLM to download symbols, compile, publish apps and run tests against Business Central environments.

**Use when:** Working with BC development workflows - downloading dependencies, compiling, deploying, or testing.

**Supported platforms:** macOS (arm64, x64), Linux (x64, arm64), Windows (x64)

The CLI binary is automatically downloaded and cached on first use. No manual setup required.

**Skill:** `bcdev-cli:bcdev`

#### Version Override

To use a specific CLI version:

```bash
# macOS/Linux
export BCDEV_CLI_VERSION=0.8

# Windows
set BCDEV_CLI_VERSION=0.8
```

## Development

### Validating plugins

```bash
# Validate a single plugin
claude plugin validate --plugin-dir ./al-id-manager
claude plugin validate --plugin-dir ./bcdev-cli

# Validate all plugins
for plugin in al-id-manager bcdev-cli; do
  claude plugin validate --plugin-dir ./$plugin
done
```

### Testing locally

```bash
claude --plugin-dir ./al-id-manager
claude --plugin-dir ./bcdev-cli
```

### Updating BC Dev CLI version

When a new BC Dev CLI version is released:

1. Download all platform binaries and compute SHA256 checksums
2. Add entries to `bcdev-cli/checksums.txt`
3. Update `DEFAULT_VERSION` in both wrapper scripts (`bin/bcdev-ensure` and `bin/bcdev-ensure.cmd`)
4. Bump version in `bcdev-cli/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
5. Commit and push
