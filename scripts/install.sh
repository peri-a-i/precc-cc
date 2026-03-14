#!/usr/bin/env bash
# install.sh — PRECC installer for Linux and macOS
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yijunyu/precc-cc/main/scripts/install.sh | bash
#   or: bash install.sh [--version v0.1.0] [--prefix ~/.local]
#
# After installation:
#   Run 'precc init' to initialize databases.

set -euo pipefail

REPO="yijunyu/precc-cc"
DEFAULT_PREFIX="${HOME}/.local"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
VERSION=""
PREFIX="${INSTALL_PREFIX:-$DEFAULT_PREFIX}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --prefix)
            PREFIX="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

BIN_DIR="${PREFIX}/bin"

# ---------------------------------------------------------------------------
# Detect OS and architecture
# ---------------------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"

case "${OS}" in
    Linux)
        case "${ARCH}" in
            x86_64)  TARGET="x86_64-unknown-linux-gnu" ;;
            aarch64) TARGET="aarch64-unknown-linux-gnu" ;;
            *)
                echo "Unsupported architecture: ${ARCH}" >&2
                exit 1
                ;;
        esac
        ;;
    Darwin)
        case "${ARCH}" in
            x86_64) TARGET="x86_64-apple-darwin" ;;
            arm64)  TARGET="aarch64-apple-darwin" ;;
            *)
                echo "Unsupported architecture: ${ARCH}" >&2
                exit 1
                ;;
        esac
        ;;
    *)
        echo "Unsupported OS: ${OS}. Use install.ps1 on Windows." >&2
        exit 1
        ;;
esac

echo "Detected target: ${TARGET}"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if [[ -z "${VERSION}" ]]; then
    echo "Fetching latest release tag..."
    VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep '"tag_name"' \
        | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')"
    if [[ -z "${VERSION}" ]]; then
        echo "Failed to fetch latest version. Pass --version v0.x.y to specify manually." >&2
        exit 1
    fi
fi

echo "Installing PRECC ${VERSION}..."

# ---------------------------------------------------------------------------
# Download and extract
# ---------------------------------------------------------------------------
ARCHIVE="precc-${VERSION}-${TARGET}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARCHIVE}"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${URL}..."
curl -fsSL --progress-bar -o "${TMP}/${ARCHIVE}" "${URL}"

echo "Extracting..."
tar -xzf "${TMP}/${ARCHIVE}" -C "${TMP}"
EXTRACTED="${TMP}/precc-${VERSION}-${TARGET}"

# ---------------------------------------------------------------------------
# Install binaries
# ---------------------------------------------------------------------------
mkdir -p "${BIN_DIR}"

for bin in precc precc-hook precc-miner; do
    if [[ -f "${EXTRACTED}/${bin}" ]]; then
        install -m 755 "${EXTRACTED}/${bin}" "${BIN_DIR}/${bin}"
        echo "  Installed ${BIN_DIR}/${bin}"
    fi
done

# ---------------------------------------------------------------------------
# Wire ~/.claude/settings.json
# ---------------------------------------------------------------------------
HOOK_CMD="${BIN_DIR}/precc-hook"
SETTINGS="${HOME}/.claude/settings.json"

wire_hook() {
    if [[ ! -f "${SETTINGS}" ]]; then
        # No settings file — create one with the hook entry
        mkdir -p "$(dirname "${SETTINGS}")"
        cat > "${SETTINGS}" <<EOF
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${HOOK_CMD}"
          }
        ]
      }
    ]
  }
}
EOF
        echo "  Created ${SETTINGS} with precc-hook entry"
    elif ! grep -q "precc-hook" "${SETTINGS}" 2>/dev/null; then
        # Settings file exists but no hook — print manual instructions
        echo ""
        echo "  NOTE: Could not automatically update ${SETTINGS}."
        echo "  Add the following to your settings.json manually:"
        echo ""
        echo '  "hooks": {'
        echo '    "PreToolUse": ['
        echo '      {'
        echo '        "matcher": "Bash",'
        echo '        "hooks": [{"type": "command", "command": "'"${HOOK_CMD}"'"}]'
        echo '      }'
        echo '    ]'
        echo '  }'
    else
        echo "  Hook already configured in ${SETTINGS} — skipped"
    fi
}

wire_hook

# ---------------------------------------------------------------------------
# PATH hint
# ---------------------------------------------------------------------------
if ! echo ":${PATH}:" | grep -q ":${BIN_DIR}:"; then
    echo ""
    echo "  Add ${BIN_DIR} to your PATH:"
    echo "    echo 'export PATH=\"${BIN_DIR}:\$PATH\"' >> ~/.bashrc  # or ~/.zshrc"
    echo "  Then restart your shell or run: export PATH=\"${BIN_DIR}:\$PATH\""
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "PRECC ${VERSION} installed to ${BIN_DIR}."
echo "Run 'precc init' to initialize databases."
