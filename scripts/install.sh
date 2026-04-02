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

# ===========================================================================
# Helper: download a GitHub release binary
#   Usage: gh_install_binary <repo> <binary_name> <url>
# ===========================================================================
gh_install_binary() {
    local repo="$1" name="$2" url="$3"
    echo "  Downloading ${name} from ${repo}..."
    if curl -fsSL --progress-bar -o "${TMP}/${name}.tar.gz" "${url}" 2>/dev/null; then
        tar -xzf "${TMP}/${name}.tar.gz" -C "${TMP}" 2>/dev/null || true
        # Search for the binary in extracted files
        local found
        found="$(find "${TMP}" -name "${name}" -type f 2>/dev/null | head -1)"
        if [[ -n "${found}" ]]; then
            install -m 755 "${found}" "${BIN_DIR}/${name}"
            echo "  Installed ${name} to ${BIN_DIR}/${name}"
            return 0
        fi
    fi
    return 1
}

# ===========================================================================
# Helper: resolve latest GitHub release tag
#   Usage: gh_latest_tag <repo>
# ===========================================================================
gh_latest_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | grep '"tag_name"' \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

# ---------------------------------------------------------------------------
# Optional: install lean-ctx (pre-built binary, ~2 seconds)
# ---------------------------------------------------------------------------
install_lean_ctx() {
    if command -v lean-ctx &>/dev/null; then
        echo "  lean-ctx already installed: $(lean-ctx --version 2>/dev/null)"
        return 0
    fi

    echo ""
    echo "Installing lean-ctx (deep output compression — saves up to 88% of context tokens)..."

    # Try pre-built binary first (fast: ~2s download)
    local tag
    tag="$(gh_latest_tag yvgude/lean-ctx)" || true
    if [[ -n "${tag}" ]]; then
        local ver="${tag#v}"
        local url="https://github.com/yvgude/lean-ctx/releases/download/${tag}/lean-ctx-${TARGET}.tar.gz"
        if gh_install_binary "yvgude/lean-ctx" "lean-ctx" "${url}"; then
            return 0
        fi
    fi

    # Fallback: universal installer
    if curl -fsSL https://leanctx.com/install.sh 2>/dev/null | bash; then
        echo "  Installed lean-ctx via universal installer"
        return 0
    fi

    # Last resort: cargo (slow, compiles from source)
    if command -v cargo &>/dev/null; then
        echo "  Building lean-ctx from source (this may take a few minutes)..."
        cargo install lean-ctx 2>/dev/null && echo "  Installed lean-ctx via cargo" && return 0
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

# ---------------------------------------------------------------------------
# Optional: install RTK (pre-built binary — token-optimized CLI output)
# ---------------------------------------------------------------------------
install_rtk() {
    if command -v rtk &>/dev/null; then
        echo "  RTK already installed: $(rtk --version 2>/dev/null | head -1)"
        return 0
    fi

    echo ""
    echo "Installing RTK (token-optimized CLI output — saves 60-90% per command)..."

    local tag
    tag="$(gh_latest_tag rtk-ai/rtk)" || true
    if [[ -z "${tag}" ]]; then
        echo "  Failed to fetch RTK release tag"
        return 1
    fi

    # RTK uses slightly different target naming
    local rtk_target
    case "${TARGET}" in
        x86_64-unknown-linux-gnu)  rtk_target="x86_64-unknown-linux-musl" ;;
        aarch64-unknown-linux-gnu) rtk_target="aarch64-unknown-linux-gnu" ;;
        x86_64-apple-darwin)       rtk_target="x86_64-apple-darwin" ;;
        aarch64-apple-darwin)      rtk_target="aarch64-apple-darwin" ;;
        *)
            echo "  No pre-built RTK binary for ${TARGET}"
            return 1
            ;;
    esac

    local url="https://github.com/rtk-ai/rtk/releases/download/${tag}/rtk-${rtk_target}.tar.gz"
    if gh_install_binary "rtk-ai/rtk" "rtk" "${url}"; then
        # Cache the path for fast lookup by precc-hook
        mkdir -p "${HOME}/.local/share/precc"
        echo "${BIN_DIR}/rtk" > "${HOME}/.local/share/precc/.rtk_path"
        return 0
    fi

    # Fallback: cargo
    if command -v cargo &>/dev/null; then
        echo "  Building RTK from source..."
        cargo install rtk 2>/dev/null && echo "  Installed RTK via cargo" && return 0
    fi

    echo "  Skipped: install RTK manually — see https://github.com/rtk-ai/rtk"
    return 1
}

install_rtk

install_lean_ctx
wire_mcp_lean_ctx

# ---------------------------------------------------------------------------
# Optional: install Nushell (pre-built binary, ~2 seconds)
# ---------------------------------------------------------------------------
install_nushell() {
    if command -v nu &>/dev/null; then
        echo "  Nushell already installed: $(nu --version 2>/dev/null)"
        return 0
    fi

    echo ""
    echo "Installing Nushell (structured shell for compact CLI output)..."

    # Try pre-built binary first (fast: ~2s download)
    local tag
    tag="$(gh_latest_tag nushell/nushell)" || true
    if [[ -n "${tag}" ]]; then
        local url="https://github.com/nushell/nushell/releases/download/${tag}/nu-${tag}-${TARGET}.tar.gz"
        if gh_install_binary "nushell/nushell" "nu" "${url}"; then
            return 0
        fi
    fi

    # Fallback: brew on macOS
    if [[ "${OS}" == "Darwin" ]] && command -v brew &>/dev/null; then
        brew install nushell 2>/dev/null && echo "  Installed Nushell via Homebrew" && return 0
    fi

    # Last resort: cargo (very slow, compiles 300+ crates)
    if command -v cargo &>/dev/null; then
        echo "  Building Nushell from source (this may take several minutes)..."
        cargo install nu 2>/dev/null && echo "  Installed Nushell via cargo" && return 0
    fi

    echo "  Skipped: install Nushell manually from https://www.nushell.sh/book/installation.html"
    echo "  Then set PRECC_NUSHELL=1 to enable compact output rewriting."
    return 1
}

install_nushell

# ---------------------------------------------------------------------------
# Optional: install cocoindex-code (Python package — no pre-built binary)
# ---------------------------------------------------------------------------
install_cocoindex_code() {
    if command -v ccc &>/dev/null; then
        echo "  cocoindex-code already installed: $(ccc --version 2>/dev/null || echo 'unknown')"
        return 0
    fi

    echo ""
    echo "Installing cocoindex-code (AST-driven semantic code search)..."

    # uv is fastest (uses pre-built wheels when available)
    if command -v uv &>/dev/null; then
        echo "  Using uv..."
        timeout 120 uv tool install --upgrade cocoindex-code --prerelease explicit && echo "  Installed cocoindex-code via uv" && return 0
        echo "  uv install failed or timed out"
    fi

    if command -v pipx &>/dev/null; then
        echo "  Using pipx..."
        timeout 180 pipx install cocoindex-code && echo "  Installed cocoindex-code via pipx" && return 0
        echo "  pipx install failed or timed out"
    fi

    if command -v pip3 &>/dev/null; then
        echo "  Using pip3..."
        timeout 180 pip3 install --user cocoindex-code && echo "  Installed cocoindex-code via pip3" && return 0
        echo "  pip3 install failed or timed out"
    fi

    echo "  Skipped: install manually with: pipx install cocoindex-code"
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
# Done
# ---------------------------------------------------------------------------
echo ""
echo "PRECC ${VERSION} installed to ${BIN_DIR}."
echo "Run 'precc init' to initialize databases."
echo ""
if command -v rtk &>/dev/null; then
    echo "✓ RTK is available — token-optimized output active by default."
else
    echo "⚠ RTK not installed — output compression limited to diet rules only."
    echo "  Install manually: cargo install rtk  (or visit https://github.com/rtk-ai/rtk)"
fi
if command -v lean-ctx &>/dev/null; then
    echo "✓ lean-ctx is available — deep output compression active by default."
fi
if command -v nu &>/dev/null; then
    echo "✓ Nushell is available — compact output rewriting active by default."
fi
if command -v ccc &>/dev/null; then
    echo "cocoindex-code is available. Run 'ccc init && ccc index' in your project to enable AST-based semantic search."
fi
