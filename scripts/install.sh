#!/usr/bin/env bash
# install.sh — PRECC installer for Linux and macOS
#
# Usage:
#   curl -fsSL https://peria.ai/install.sh | bash
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
NO_VERIFY=""
# Companion tools (lean-ctx, rtk, nushell, cocoindex-code) are installed by
# default because they contribute the bulk of token savings in live
# measurements (lean-ctx is the top-performing mode). Use --no-extras to
# opt out and install only the precc binary.
EXTRAS=1
EXTRAS_ONLY=""

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
        --no-verify)
            NO_VERIFY=1
            shift
            ;;
        --extras)
            # Kept for backward compatibility — extras are now default-on
            EXTRAS=1
            shift
            ;;
        --no-extras)
            EXTRAS=""
            shift
            ;;
        --extras-only)
            # Skip the precc binary download/install entirely; only run the
            # companion installers (lean-ctx, rtk, nushell, cocoindex-code).
            # Used by `precc update` to back-fill companion tools for users
            # who originally installed without --extras.
            EXTRAS_ONLY=1
            EXTRAS=1
            shift
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

if [[ -n "${EXTRAS_ONLY}" ]]; then
    echo "Skipping precc binary install (--extras-only); installing companion tools only..."
else

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
# Verify SHA256 checksum (mandatory — use --no-verify to skip)
# ---------------------------------------------------------------------------
CHECKSUM_URL="https://github.com/${REPO}/releases/download/${VERSION}/SHA256SUMS"
if curl -fsSL -o "${TMP}/SHA256SUMS" "${CHECKSUM_URL}" 2>/dev/null; then
    echo "Verifying SHA256 checksum..."
    EXPECTED="$(grep "${ARCHIVE}" "${TMP}/SHA256SUMS" | awk '{print $1}')"
    if [[ -z "${EXPECTED}" ]]; then
        echo "ERROR: no checksum entry for ${ARCHIVE} in SHA256SUMS — aborting." >&2
        exit 1
    fi
    ACTUAL="$(sha256sum "${TMP}/${ARCHIVE}" 2>/dev/null || shasum -a 256 "${TMP}/${ARCHIVE}" 2>/dev/null | awk '{print $1}')"
    ACTUAL="$(echo "${ACTUAL}" | awk '{print $1}')"
    if [[ "${ACTUAL}" != "${EXPECTED}" ]]; then
        echo "Checksum mismatch!" >&2
        echo "  Expected: ${EXPECTED}" >&2
        echo "  Got:      ${ACTUAL}" >&2
        exit 1
    fi
    echo "  Checksum verified: ${ACTUAL}"
elif [[ -n "${NO_VERIFY}" ]]; then
    echo "  Warning: SHA256SUMS not available — skipping verification (--no-verify)"
else
    echo "ERROR: SHA256SUMS not available for this release — aborting for security." >&2
    echo "  Use --no-verify to skip checksum verification (not recommended)." >&2
    exit 1
fi

echo "Extracting..."
tar -xzf "${TMP}/${ARCHIVE}" -C "${TMP}"
EXTRACTED="${TMP}/precc-${VERSION}-${TARGET}"

# ---------------------------------------------------------------------------
# Install binaries
# ---------------------------------------------------------------------------
mkdir -p "${BIN_DIR}"

for bin in precc precc-hook precc-learner; do
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
    ],
    "PostToolUse": [
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
        # Settings file exists but no precc-hook entry — merge it in via
        # python3 (preserves existing keys, formatting, comments are lost
        # but JSON has no real comments anyway).
        if command -v python3 &>/dev/null; then
            python3 - "${SETTINGS}" "${HOOK_CMD}" <<'PYEOF'
import json, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
hooks = data.setdefault("hooks", {})
def ensure_bash_hook(event):
    bucket = hooks.setdefault(event, [])
    bash_block = next((b for b in bucket if isinstance(b, dict) and b.get("matcher") == "Bash"), None)
    if bash_block is None:
        bash_block = {"matcher": "Bash", "hooks": []}
        bucket.append(bash_block)
    cmds = bash_block.setdefault("hooks", [])
    if not any(h.get("command") == hook_cmd for h in cmds):
        cmds.append({"type": "command", "command": hook_cmd})
# Wire both Pre (rewrite/correct) and Post (measure) so savings_measurements
# gets populated by real Claude Code usage, not just manual campaign runs.
ensure_bash_hook("PreToolUse")
ensure_bash_hook("PostToolUse")
sl = data.get("statusLine")
sl_cmd = f"{hook_cmd} --statusline"
if not isinstance(sl, dict):
    data["statusLine"] = {"type": "command", "command": sl_cmd}
elif "precc-hook" in str(sl.get("command", "")) and sl.get("command") != sl_cmd:
    sl["command"] = sl_cmd
elif sl.get("command") is None:
    sl.update({"type": "command", "command": sl_cmd})
# else: user has their own statusLine — leave alone
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
            echo "  Merged precc-hook into ${SETTINGS}"
        else
            echo ""
            echo "  NOTE: python3 not found — could not auto-merge ${SETTINGS}."
            echo "  Add the following manually:"
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
        fi
    else
        # precc-hook is already in settings.json — but it may only be wired
        # for PreToolUse from older installs. Re-run the merge to add the
        # PostToolUse entry as well (idempotent — won't duplicate Pre).
        if command -v python3 &>/dev/null; then
            python3 - "${SETTINGS}" "${HOOK_CMD}" <<'PYEOF'
import json, sys
path, hook_cmd = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
hooks = data.setdefault("hooks", {})
def ensure_bash_hook(event):
    bucket = hooks.setdefault(event, [])
    bash_block = next((b for b in bucket if isinstance(b, dict) and b.get("matcher") == "Bash"), None)
    if bash_block is None:
        bash_block = {"matcher": "Bash", "hooks": []}
        bucket.append(bash_block)
    cmds = bash_block.setdefault("hooks", [])
    if not any(h.get("command") == hook_cmd for h in cmds):
        cmds.append({"type": "command", "command": hook_cmd})
ensure_bash_hook("PreToolUse")
ensure_bash_hook("PostToolUse")
sl = data.get("statusLine")
sl_cmd = f"{hook_cmd} --statusline"
if not isinstance(sl, dict):
    data["statusLine"] = {"type": "command", "command": sl_cmd}
elif "precc-hook" in str(sl.get("command", "")) and sl.get("command") != sl_cmd:
    sl["command"] = sl_cmd
elif sl.get("command") is None:
    sl.update({"type": "command", "command": sl_cmd})
# else: user has their own statusLine — leave alone
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
            echo "  Reconciled precc-hook entries (Pre + Post) in ${SETTINGS}"
        else
            echo "  Hook already configured in ${SETTINGS} — skipped"
        fi
    fi
}

wire_hook

fi  # end !EXTRAS_ONLY

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

    # Fallback: cargo (slow, compiles from source)
    if command -v cargo &>/dev/null; then
        echo "  Building lean-ctx from source (this may take a few minutes)..."
        cargo install lean-ctx 2>/dev/null && echo "  Installed lean-ctx via cargo" && return 0
    fi

    echo "  Skipped: install lean-ctx manually — see https://github.com/yvgude/lean-ctx"
    echo "  Then set PRECC_LEAN_CTX=1 to enable deep output compression."
    return 1
}

wire_mcp_lean_ctx() {
    # Don't fail the install if lean-ctx isn't yet on PATH (it may have just
    # been installed to a prefix not in PATH). Just return 0 — wiring is best-effort.
    if ! command -v lean-ctx &>/dev/null; then
        return 0
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
    return 0
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

# ---------------------------------------------------------------------------
# Companion tools (rtk, lean-ctx, nushell, cocoindex-code) are installed
# by default because they contribute the bulk of measured token savings.
# Use --no-extras to skip them.
# ---------------------------------------------------------------------------
if [[ -n "${EXTRAS}" ]]; then
    echo ""
    echo "Installing companion tools for best performance:"
    echo "  - lean-ctx:        deep output compression (top-performing mode in live measurements)"
    echo "  - RTK:             token-optimized CLI output (60-90% on small commands)"
    echo "  - nushell:         structured shell (best for find/grep)"
    echo "  - cocoindex-code:  AST-driven semantic code search"
    echo "  (Pass --no-extras to skip)"
    echo ""

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

    # uv is fastest (uses pre-built wheels when available). cocoindex-code
    # depends on a pre-release of cocoindex, so we need --prerelease=allow.
    if command -v uv &>/dev/null; then
        echo "  Using uv..."
        timeout 180 uv tool install --upgrade cocoindex-code --prerelease=allow \
            && echo "  Installed cocoindex-code via uv" && return 0
        echo "  uv install failed or timed out"
    fi

    if command -v pipx &>/dev/null; then
        echo "  Using pipx..."
        timeout 240 pipx install --pip-args='--pre' cocoindex-code \
            && echo "  Installed cocoindex-code via pipx" && return 0
        echo "  pipx install failed or timed out"
    fi

    # PEP 668 fallback: create a dedicated venv at ~/.local/share/precc/ccc-venv
    # and symlink the entry point into ~/.local/bin so distros that mark the
    # system Python "externally-managed" (Debian/Raspberry Pi OS) still work.
    if command -v python3 &>/dev/null; then
        echo "  Using python3 venv (PEP 668 fallback)..."
        local venv="${HOME}/.local/share/precc/ccc-venv"
        if python3 -m venv "${venv}" 2>/dev/null \
            && timeout 240 "${venv}/bin/pip" install --pre cocoindex-code 2>&1 | tail -5; then
            mkdir -p "${HOME}/.local/bin"
            if [ -x "${venv}/bin/ccc" ]; then
                ln -sf "${venv}/bin/ccc" "${HOME}/.local/bin/ccc"
                echo "  Installed cocoindex-code into ${venv} (symlinked ccc → ~/.local/bin)"
                return 0
            fi
        fi
        echo "  python3 venv install failed"
    fi

    echo "  Skipped: install manually with one of:"
    echo "    uv tool install cocoindex-code --prerelease=allow"
    echo "    pipx install --pip-args='--pre' cocoindex-code"
    return 1
}

wire_mcp_cocoindex() {
    # Best-effort: don't fail the install if ccc isn't yet on PATH.
    if ! command -v ccc &>/dev/null; then
        return 0
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
    return 0
}

install_cocoindex_code
wire_mcp_cocoindex

else
    echo ""
    echo "Skipped companion tools. To install later: bash install.sh --extras"
fi

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
