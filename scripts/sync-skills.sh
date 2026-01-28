#!/bin/bash
# Sync BC Dev CLI skill template to all platform-specific plugins

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$ROOT_DIR/templates/bcdev-skill.md"

sync_plugin() {
  local plugin_dir="$1"
  local binary_name="$2"
  local platform_notes="$3"

  local output_file="$ROOT_DIR/$plugin_dir/skills/bcdev/SKILL.md"
  local binary_path='\${CLAUDE_PLUGIN_ROOT}/bin/'"$binary_name"

  echo "Syncing $plugin_dir..."

  # Use sed for reliable placeholder replacement
  sed -e "s|{{BINARY_NAME}}|$binary_name|g" \
      -e "s|{{BINARY_PATH}}|$binary_path|g" \
      -e "s|{{PLATFORM_NOTES}}|$platform_notes|g" \
      "$TEMPLATE" > "$output_file"

  echo "  -> $output_file"
}

# Windows x64
sync_plugin "bcdev-cli-win-x64" "bcdev.exe" "**Windows (win-x64):**
- SmartScreen may warn on first run; click \"More info\" → \"Run anyway\""

# Linux x64
sync_plugin "bcdev-cli-linux-x64" "bcdev" "**Linux (x64):**
- Ensure binary is executable: \\\`chmod +x \\\${CLAUDE_PLUGIN_ROOT}/bin/bcdev\\\`"

# Linux ARM64
sync_plugin "bcdev-cli-linux-arm64" "bcdev" "**Linux (ARM64):**
- Ensure binary is executable: \\\`chmod +x \\\${CLAUDE_PLUGIN_ROOT}/bin/bcdev\\\`"

# macOS ARM64
sync_plugin "bcdev-cli-osx-arm64" "bcdev" "**macOS (Apple Silicon):**
- Binary may be quarantined after download. Remove with: \\\`xattr -d com.apple.quarantine \\\${CLAUDE_PLUGIN_ROOT}/bin/bcdev\\\`
- May require approval in System Preferences > Security \& Privacy on first run"

echo "Done!"
