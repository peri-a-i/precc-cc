#!/usr/bin/env bash
# install.sh — PRECC installer for Linux and macOS
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/peria-ai/precc-cc/main/scripts/install.sh | bash
#   or: bash install.sh [--version v0.1.0] [--prefix ~/.local]
#
# After installation:
#   Run 'precc init' to initialize databases.

set -euo pipefail

REPO="peria-ai/precc-cc"
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

# ---------------------------------------------------------------------------
# Verify SHA256 checksum (if checksums file is available in the release)
# ---------------------------------------------------------------------------
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${VERSION}/SHA256SUMS"
if curl -fsSL -o "${TMP}/SHA256SUMS" "${CHECKSUM_URL}" 2>/dev/null; then
    echo "Verifying SHA256 checksum..."
    EXPECTED="$(grep "${ARCHIVE}" "${TMP}/SHA256SUMS" | awk '{print $1}')"
    if [[ -n "${EXPECTED}" ]]; then
        ACTUAL="$(sha256sum "${TMP}/${ARCHIVE}" 2>/dev/null || shasum -a 256 "${TMP}/${ARCHIVE}" 2>/dev/null | awk '{print $1}')"
        ACTUAL="$(echo "${ACTUAL}" | awk '{print $1}')"
        if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
            echo "Checksum mismatch!" >&2
            echo "  Expected: ${EXPECTED}" >&2
            echo "  Got:      ${ACTUAL}" >&2
            exit 1
        fi
        echo "  Checksum verified: ${ACTUAL}"
    else
        echo "  Warning: no checksum entry for ${ARCHIVE} in SHA256SUMS — skipping verification"
    fi
else
    echo "  Note: SHA256SUMS not available for this release — skipping checksum verification"
fi

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
        # No settings file — create one with the hook and statusline entries
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
  },
  "statusLine": {
    "type": "command",
    "command": "${HOOK_CMD} --statusline"
  }
}
EOF
        echo "  Created ${SETTINGS} with precc-hook and statusline entries"
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
        echo '  },'
        echo '  "statusLine": {'
        echo '    "type": "command",'
        echo '    "command": "'"${HOOK_CMD}"' --statusline"'
        echo '  }'
    else
        echo "  Hook already configured in ${SETTINGS} — skipped"
        # Wire statusline if hook exists but statusline doesn't
        if ! grep -q "statusLine" "${SETTINGS}" 2>/dev/null; then
            echo ""
            echo "  NOTE: Add the statusline to your settings.json for live PRECC metrics:"
            echo '  "statusLine": {'
            echo '    "type": "command",'
            echo '    "command": "'"${HOOK_CMD}"' --statusline"'
            echo '  }'
        fi
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
# Optional: install cocoindex-code (AST-driven semantic code search)
# ---------------------------------------------------------------------------
install_cocoindex_code() {
    echo ""
    echo "Installing cocoindex-code (AST-driven semantic code search)..."

    if command -v pipx &>/dev/null; then
        pipx install cocoindex-code 2>/dev/null && echo "  Installed cocoindex-code via pipx" && return 0
    fi

    if command -v uv &>/dev/null; then
        uv tool install --upgrade cocoindex-code --prerelease explicit 2>/dev/null && echo "  Installed cocoindex-code via uv" && return 0
    fi

    if command -v pip3 &>/dev/null; then
        pip3 install --user cocoindex-code 2>/dev/null && echo "  Installed cocoindex-code via pip3" && return 0
    fi

    echo "  Skipped: install pipx, uv, or pip3 first, then run:"
    echo "    pipx install cocoindex-code"
    return 1
}

wire_mcp_cocoindex() {
    if ! command -v ccc &>/dev/null; then
        return 1
    fi

    # Add cocoindex-code MCP server to Claude Code
    if command -v claude &>/dev/null; then
        claude mcp add cocoindex-code -- ccc mcp 2>/dev/null \
            && echo "  Configured cocoindex-code MCP server for Claude Code" \
            || echo "  Note: run 'claude mcp add cocoindex-code -- ccc mcp' manually to enable MCP"
    else
        echo "  To enable MCP integration, run:"
        echo "    claude mcp add cocoindex-code -- ccc mcp"
    fi
}

install_cocoindex_code
wire_mcp_cocoindex

# ---------------------------------------------------------------------------
# Optional: install Nushell (structured output for further token savings)
# ---------------------------------------------------------------------------
install_nushell() {
    if command -v nu &>/dev/null; then
        echo "  Nushell already installed: $(nu --version 2>/dev/null)"
        return 0
    fi

    echo ""
    echo "Installing Nushell (structured shell for compact CLI output)..."

    case "${OS}" in
        Linux)
            if ! command -v cargo &>/dev/null; then
                echo "  Rust/Cargo not found — installing via rustup..."
                curl -fsSL https://sh.rustup.rs | sh -s -- -y 2>/dev/null
                # shellcheck disable=SC1091
                source "${HOME}/.cargo/env" 2>/dev/null || true
            fi
            if command -v cargo &>/dev/null; then
                cargo install nu 2>/dev/null && echo "  Installed Nushell via cargo" && return 0
            fi
            # Try GitHub release binary
            local NU_VERSION
            NU_VERSION="$(curl -fsSL https://api.github.com/repos/nushell/nushell/releases/latest \
                | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')" 2>/dev/null || true
            if [[ -n "${NU_VERSION}" ]]; then
                local NU_ARCHIVE="nu-${NU_VERSION}-${ARCH}-unknown-linux-gnu.tar.gz"
                local NU_URL="https://github.com/nushell/nushell/releases/download/${NU_VERSION}/${NU_ARCHIVE}"
                if curl -fsSL -o "${TMP}/nu.tar.gz" "${NU_URL}" 2>/dev/null; then
                    tar -xzf "${TMP}/nu.tar.gz" -C "${TMP}" 2>/dev/null
                    local NU_BIN
                    NU_BIN="$(find "${TMP}" -name nu -type f -executable 2>/dev/null | head -1)"
                    if [[ -n "${NU_BIN}" ]]; then
                        install -m 755 "${NU_BIN}" "${BIN_DIR}/nu"
                        echo "  Installed Nushell ${NU_VERSION} to ${BIN_DIR}/nu"
                        return 0
                    fi
                fi
            fi
            ;;
        Darwin)
            if command -v brew &>/dev/null; then
                brew install nushell 2>/dev/null && echo "  Installed Nushell via Homebrew" && return 0
            fi
            ;;
    esac

    echo "  Skipped: install Nushell manually from https://www.nushell.sh/book/installation.html"
    echo "  Then set PRECC_NUSHELL=1 to enable compact output rewriting."
    return 1
}

install_nushell

# ---------------------------------------------------------------------------
# Optional: install lean-ctx (deep output compression for further token savings)
# ---------------------------------------------------------------------------
install_lean_ctx() {
    if command -v lean-ctx &>/dev/null; then
        echo "  lean-ctx already installed: $(lean-ctx --version 2>/dev/null)"
        return 0
    fi

    echo ""
    echo "Installing lean-ctx (deep output compression — saves up to 88% of context tokens)..."

    if command -v cargo &>/dev/null; then
        cargo install lean-ctx 2>/dev/null && echo "  Installed lean-ctx via cargo" && return 0
    fi

    # Try the universal installer
    if curl -fsSL https://leanctx.com/install.sh | bash 2>/dev/null; then
        echo "  Installed lean-ctx via universal installer"
        return 0
    fi

    echo "  Skipped: install lean-ctx manually — see https://github.com/yvgude/lean-ctx"
    echo "  Then set PRECC_LEAN_CTX=1 to enable deep output compression."
    return 1
}

wire_mcp_lean_ctx() {
    if ! command -v lean-ctx &>/dev/null; then
        return 1
    fi

    # Add lean-ctx MCP server to Claude Code
    if command -v claude &>/dev/null; then
        claude mcp add lean-ctx -- lean-ctx 2>/dev/null \
            && echo "  Configured lean-ctx MCP server for Claude Code" \
            || echo "  Note: run 'claude mcp add lean-ctx -- lean-ctx' manually to enable MCP"
    else
        echo "  To enable MCP integration, run:"
        echo "    claude mcp add lean-ctx -- lean-ctx"
    fi
}

install_lean_ctx
wire_mcp_lean_ctx

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "PRECC ${VERSION} installed to ${BIN_DIR}."
echo "Run 'precc init' to initialize databases."
echo ""
if command -v nu &>/dev/null; then
    echo "Nushell is available. Set PRECC_NUSHELL=1 to enable compact output rewriting."
fi
if command -v ccc &>/dev/null; then
    echo "cocoindex-code is available. Run 'ccc init && ccc index' in your project to enable AST-based semantic search."
fi
if command -v lean-ctx &>/dev/null; then
    echo "lean-ctx is available. Set PRECC_LEAN_CTX=1 to enable deep output compression."
fi
