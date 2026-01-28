# NaviPartner BC Tools - Claude Code Plugin Marketplace

A Claude Code plugin marketplace for Business Central AL development at NaviPartner.

## Installation

Add this marketplace to Claude Code:

```bash
claude /plugin add-marketplace https://github.com/navipartner/curitiba
```

Then install the plugins you need:

```bash
# AL ID Manager (all platforms)
claude plugin install al-id-manager@navipartner-bc-tools

# BC Dev CLI (choose your platform)
claude plugin install bcdev-cli-win-x64@navipartner-bc-tools      # Windows
claude plugin install bcdev-cli-linux-x64@navipartner-bc-tools    # Linux x64
claude plugin install bcdev-cli-linux-arm64@navipartner-bc-tools  # Linux ARM64
claude plugin install bcdev-cli-osx-arm64@navipartner-bc-tools    # macOS Apple Silicon
```

## Plugins

### AL ID Manager

Allows the LLM to grab next AL object ID or next AL table/tableextension/enum/enumextension field/value ID from the NaviPartner AL ID Manager service.

**Use when:** Creating new AL objects, adding fields to tables/tableextensions, or adding values to enums/enumextensions.

**Skill:** `al-id-manager:get-next-id`

### BC Dev CLI

Allows the LLM to download symbols, compile, publish apps and run tests against Business Central environments.

**Use when:** Working with BC development workflows - downloading dependencies, compiling, deploying, or testing.

**Platform variants:**
- `bcdev-cli-win-x64` - Windows x64
- `bcdev-cli-linux-x64` - Linux x64
- `bcdev-cli-linux-arm64` - Linux ARM64
- `bcdev-cli-osx-arm64` - macOS Apple Silicon

**Skill:** `bcdev-cli-*:bcdev`

## Development

### Syncing BC Dev CLI skills

The BC Dev CLI skill content is maintained in `templates/bcdev-skill.md`. To sync changes to all platform plugins:

```bash
./scripts/sync-skills.sh
```

### Validating plugins

```bash
# Validate a single plugin
claude plugin validate --plugin-dir ./al-id-manager

# Validate all plugins
for plugin in al-id-manager bcdev-cli-*; do
  claude plugin validate --plugin-dir ./$plugin
done
```

### Testing locally

```bash
claude --plugin-dir ./al-id-manager
```
