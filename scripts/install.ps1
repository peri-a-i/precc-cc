# install.ps1 — PRECC installer for Windows
#
# Usage (PowerShell one-liner):
#   iwr -useb https://raw.githubusercontent.com/peria-ai/precc-cc/main/scripts/install.ps1 | iex
#
# Or download and run:
#   powershell -ExecutionPolicy Bypass -File install.ps1 [-Version v0.1.0]
#
# Note: You may need to set execution policy first:
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# After installation:
#   Run 'precc init' to initialize databases.

param(
    [string]$Version = "",
    [switch]$WhatIf = $false
)

$ErrorActionPreference = "Stop"
$Repo = "peria-ai/precc-cc"
$Target = "x86_64-pc-windows-msvc"
$InstallDir = Join-Path $env:LOCALAPPDATA "precc-cc\bin"

# ---------------------------------------------------------------------------
# Resolve version
# ---------------------------------------------------------------------------
if (-not $Version) {
    Write-Host "Fetching latest release tag..."
    $releaseUrl = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ "User-Agent" = "precc-installer" }
        $Version = $release.tag_name
    } catch {
        Write-Error "Failed to fetch latest version. Pass -Version v0.x.y to specify manually."
        exit 1
    }
}

if (-not $Version) {
    Write-Error "Could not determine version to install."
    exit 1
}

Write-Host "Installing PRECC $Version..."

# ---------------------------------------------------------------------------
# Download and extract
# ---------------------------------------------------------------------------
$TmpDir = Join-Path $env:TEMP "precc-install-$(New-Guid)"

if ($WhatIf) {
    Write-Host "[WhatIf] Would download from: https://github.com/$Repo/releases/download/$Version/"
    Write-Host "[WhatIf] Would install to: $InstallDir"
    Write-Host "[WhatIf] Would wire hook in: $env:APPDATA\Claude\settings.json"
    exit 0
}

New-Item -ItemType Directory -Path $TmpDir | Out-Null

try {
    # Try .zip first (CI-built), fall back to .tar.gz
    $ZipArchive = "precc-$Version-$Target.zip"
    $TgzArchive = "precc-$Version-$Target.tar.gz"
    $ZipUrl = "https://github.com/$Repo/releases/download/$Version/$ZipArchive"
    $TgzUrl = "https://github.com/$Repo/releases/download/$Version/$TgzArchive"

    $downloaded = $false
    try {
        $ArchivePath = Join-Path $TmpDir $ZipArchive
        Write-Host "Downloading $ZipUrl..."
        Invoke-WebRequest -Uri $ZipUrl -OutFile $ArchivePath -UseBasicParsing
        Write-Host "Extracting..."
        Expand-Archive -Path $ArchivePath -DestinationPath $TmpDir -Force
        $downloaded = $true
    } catch {
        Write-Host "  .zip not found, trying .tar.gz..."
        try {
            $ArchivePath = Join-Path $TmpDir $TgzArchive
            Invoke-WebRequest -Uri $TgzUrl -OutFile $ArchivePath -UseBasicParsing
            Write-Host "Extracting..."
            tar -xzf $ArchivePath -C $TmpDir
            if ($LASTEXITCODE -ne 0) { throw "tar extraction failed" }
            $downloaded = $true
        } catch {
            Write-Error "Failed to download PRECC $Version for Windows. The Windows build may not be available yet — try again in 20 minutes."
            exit 1
        }
    }

    $Extracted = Join-Path $TmpDir "precc-$Version-$Target"

    # -----------------------------------------------------------------------
    # Install binaries
    # -----------------------------------------------------------------------
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir | Out-Null
    }

    foreach ($bin in @("precc.exe", "precc-hook.exe", "precc-learner.exe")) {
        $src = Join-Path $Extracted $bin
        if (Test-Path $src) {
            $dst = Join-Path $InstallDir $bin
            Copy-Item -Path $src -Destination $dst -Force
            Write-Host "  Installed $dst"
        }
    }

    # -----------------------------------------------------------------------
    # Add InstallDir to user PATH
    # -----------------------------------------------------------------------
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -notlike "*$InstallDir*") {
        $newPath = "$InstallDir;$userPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "  Added $InstallDir to user PATH"
        Write-Host "  Restart your terminal for PATH changes to take effect."
    } else {
        Write-Host "  $InstallDir already in PATH — skipped"
    }

    # -----------------------------------------------------------------------
    # Wire %APPDATA%\Claude\settings.json
    # -----------------------------------------------------------------------
    $HookCmd = Join-Path $InstallDir "precc-hook.exe"
    $SettingsDir = Join-Path $env:APPDATA "Claude"
    $SettingsFile = Join-Path $SettingsDir "settings.json"

    if (-not (Test-Path $SettingsFile)) {
        # No settings file — create one
        New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null
        $hookCmdEscaped = $HookCmd -replace '\\', '\\\\'
        $settingsJson = @"
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$hookCmdEscaped"
          }
        ]
      }
    ]
  }
}
"@
        Set-Content -Path $SettingsFile -Value $settingsJson -Encoding UTF8
        Write-Host "  Created $SettingsFile with precc-hook entry"
    } else {
        $content = Get-Content $SettingsFile -Raw
        if ($content -notlike "*precc-hook*") {
            Write-Host ""
            Write-Host "  NOTE: Could not automatically update $SettingsFile."
            Write-Host "  Add the following to your settings.json manually:"
            Write-Host ""
            Write-Host '  "hooks": {'
            Write-Host '    "PreToolUse": ['
            Write-Host '      {'
            Write-Host '        "matcher": "Bash",'
            Write-Host "        `"hooks`": [{`"type`": `"command`", `"command`": `"$HookCmd`"}]"
            Write-Host '      }'
            Write-Host '    ]'
            Write-Host '  }'
        } else {
            Write-Host "  Hook already configured in $SettingsFile — skipped"
        }
    }

} finally {
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
}

# ===========================================================================
# Helper: resolve latest GitHub release tag
# ===========================================================================
function Get-LatestTag($repo) {
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" `
            -Headers @{ "User-Agent" = "precc-installer" }
        return $rel.tag_name
    } catch {
        return ""
    }
}

# ===========================================================================
# Helper: download and install a GitHub release binary (zip)
# ===========================================================================
function Install-GhBinary($repo, $binaryName, $url) {
    $tmpZip = Join-Path $env:TEMP "precc-dep-$(New-Guid).zip"
    $tmpExtract = Join-Path $env:TEMP "precc-dep-$(New-Guid)"
    try {
        Write-Host "  Downloading $binaryName from $repo..."
        Invoke-WebRequest -Uri $url -OutFile $tmpZip -UseBasicParsing
        New-Item -ItemType Directory -Path $tmpExtract -Force | Out-Null
        Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force
        # Find the binary recursively
        $found = Get-ChildItem -Path $tmpExtract -Filter "$binaryName.exe" -Recurse -File | Select-Object -First 1
        if (-not $found) {
            $found = Get-ChildItem -Path $tmpExtract -Filter $binaryName -Recurse -File | Select-Object -First 1
        }
        if ($found) {
            Copy-Item -Path $found.FullName -Destination (Join-Path $InstallDir "$binaryName.exe") -Force
            Write-Host "  Installed $binaryName to $InstallDir"
            return $true
        }
    } catch {
        # Download or extract failed
    } finally {
        Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
        Remove-Item -Recurse -Force $tmpExtract -ErrorAction SilentlyContinue
    }
    return $false
}

# ---------------------------------------------------------------------------
# Optional: install RTK (pre-built binary — token-optimized CLI output)
# ---------------------------------------------------------------------------
Write-Host ""
$hasRtk = Get-Command "rtk" -ErrorAction SilentlyContinue
$rtkInstalled = $false

if ($hasRtk) {
    Write-Host "  RTK already installed: $(rtk --version 2>$null | Select-Object -First 1)"
    $rtkInstalled = $true
} else {
    Write-Host "Installing RTK (token-optimized CLI output — saves 60-90% per command)..."
    $rtkTag = Get-LatestTag "rtk-ai/rtk"
    if ($rtkTag) {
        $rtkUrl = "https://github.com/rtk-ai/rtk/releases/download/$rtkTag/rtk-x86_64-pc-windows-msvc.zip"
        $rtkInstalled = Install-GhBinary "rtk-ai/rtk" "rtk" $rtkUrl
    }

    if (-not $rtkInstalled -and (Get-Command "cargo" -ErrorAction SilentlyContinue)) {
        Write-Host "  Building RTK from source..."
        try {
            $null = cargo install rtk *>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Installed RTK via cargo"
                $rtkInstalled = $true
            }
        } catch { }
    }

    if (-not $rtkInstalled) {
        Write-Host "  Skipped: install RTK manually — see https://github.com/rtk-ai/rtk"
    }
}

# Cache RTK path for fast lookup by precc-hook
if ($rtkInstalled) {
    $rtkPath = (Get-Command "rtk" -ErrorAction SilentlyContinue).Path
    if ($rtkPath) {
        $preccData = Join-Path $env:LOCALAPPDATA "precc-cc"
        New-Item -ItemType Directory -Path $preccData -Force | Out-Null
        Set-Content -Path (Join-Path $preccData ".rtk_path") -Value $rtkPath
    }
}

# ---------------------------------------------------------------------------
# Optional: install lean-ctx (pre-built binary, ~2 seconds)
# ---------------------------------------------------------------------------
Write-Host ""
$hasLeanCtx = Get-Command "lean-ctx" -ErrorAction SilentlyContinue
$leanCtxInstalled = $false

if ($hasLeanCtx) {
    Write-Host "  lean-ctx already installed: $(lean-ctx --version 2>$null)"
    $leanCtxInstalled = $true
} else {
    Write-Host "Installing lean-ctx (deep output compression — saves up to 88% of context tokens)..."

    # Try pre-built binary first (fast: ~2s)
    $leanTag = Get-LatestTag "yvgude/lean-ctx"
    if ($leanTag) {
        $leanUrl = "https://github.com/yvgude/lean-ctx/releases/download/$leanTag/lean-ctx-x86_64-pc-windows-msvc.zip"
        $leanCtxInstalled = Install-GhBinary "yvgude/lean-ctx" "lean-ctx" $leanUrl
    }

    # Fallback: cargo (slow)
    if (-not $leanCtxInstalled) {
        $hasCargo = Get-Command "cargo" -ErrorAction SilentlyContinue
        if ($hasCargo) {
            Write-Host "  Building lean-ctx from source (this may take a few minutes)..."
            $null = cargo install lean-ctx *>&1
            if ($LASTEXITCODE -eq 0) {
                $leanCtxInstalled = $true
                Write-Host "  Installed lean-ctx via cargo"
            }
        }
    }

    if (-not $leanCtxInstalled) {
        Write-Host "  Skipped: install lean-ctx manually — see https://github.com/yvgude/lean-ctx"
        Write-Host "  Then set PRECC_LEAN_CTX=1 to enable deep output compression."
    }
}

if ($leanCtxInstalled) {
    $hasClaude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($hasClaude) {
        claude mcp add lean-ctx -- lean-ctx 2>$null
        Write-Host "  Configured lean-ctx MCP server for Claude Code"
    } else {
        Write-Host "  To enable MCP integration, run:"
        Write-Host "    claude mcp add lean-ctx -- lean-ctx"
    }
}

# ---------------------------------------------------------------------------
# Optional: install Nushell (pre-built binary via winget or GitHub, ~2 seconds)
# ---------------------------------------------------------------------------
Write-Host ""
$hasNu = Get-Command "nu" -ErrorAction SilentlyContinue
$nuInstalled = $false

if ($hasNu) {
    Write-Host "  Nushell already installed: $(nu --version 2>$null)"
    $nuInstalled = $true
} else {
    Write-Host "Installing Nushell (structured shell for compact CLI output)..."

    # Try winget first (fast, prebuilt)
    $hasWinget = Get-Command "winget" -ErrorAction SilentlyContinue
    if ($hasWinget) {
        Write-Host "  Installing Nushell via winget..."
        $null = winget install nushell --accept-source-agreements --accept-package-agreements *>&1
        if ($LASTEXITCODE -eq 0) {
            $nuInstalled = $true
            Write-Host "  Installed Nushell via winget"
        }
    }

    # Try GitHub release binary (fast: ~2s)
    if (-not $nuInstalled) {
        $nuTag = Get-LatestTag "nushell/nushell"
        if ($nuTag) {
            $nuUrl = "https://github.com/nushell/nushell/releases/download/$nuTag/nu-$nuTag-x86_64-pc-windows-msvc.zip"
            $nuInstalled = Install-GhBinary "nushell/nushell" "nu" $nuUrl
        }
    }

    # Last resort: cargo (very slow)
    if (-not $nuInstalled) {
        $hasCargo = Get-Command "cargo" -ErrorAction SilentlyContinue
        if ($hasCargo) {
            Write-Host "  Building Nushell from source (this may take several minutes)..."
            $null = cargo install nu *>&1
            if ($LASTEXITCODE -eq 0) {
                $nuInstalled = $true
                Write-Host "  Installed Nushell via cargo"
            }
        }
    }

    if (-not $nuInstalled) {
        Write-Host "  Skipped: install Nushell manually from https://www.nushell.sh/book/installation.html"
        Write-Host "  Then set PRECC_NUSHELL=1 to enable compact output rewriting."
    }
}

# ---------------------------------------------------------------------------
# Optional: install cocoindex-code (Python package — no pre-built binary)
# ---------------------------------------------------------------------------
Write-Host ""
$hasCcc = Get-Command "ccc" -ErrorAction SilentlyContinue
$cccInstalled = $false

if ($hasCcc) {
    Write-Host "  cocoindex-code already installed"
    $cccInstalled = $true
} else {
    Write-Host "Installing cocoindex-code (AST-driven semantic code search)..."

    $hasUv = Get-Command "uv" -ErrorAction SilentlyContinue
    $hasPipx = Get-Command "pipx" -ErrorAction SilentlyContinue
    $hasPip = Get-Command "pip3" -ErrorAction SilentlyContinue

    if ($hasUv) {
        Write-Host "  Using uv..."
        $null = uv tool install --upgrade cocoindex-code --prerelease explicit *>&1
        if ($LASTEXITCODE -eq 0) { $cccInstalled = $true; Write-Host "  Installed cocoindex-code via uv" }
        else { Write-Host "  uv install failed" }
    } elseif ($hasPipx) {
        Write-Host "  Using pipx..."
        $null = pipx install cocoindex-code *>&1
        if ($LASTEXITCODE -eq 0) { $cccInstalled = $true; Write-Host "  Installed cocoindex-code via pipx" }
        else { Write-Host "  pipx install failed" }
    } elseif ($hasPip) {
        Write-Host "  Using pip3..."
        $null = pip3 install --user cocoindex-code *>&1
        if ($LASTEXITCODE -eq 0) { $cccInstalled = $true; Write-Host "  Installed cocoindex-code via pip3" }
        else { Write-Host "  pip3 install failed" }
    } else {
        Write-Host "  Skipped: install uv, pipx, or pip3 first, then run: pipx install cocoindex-code"
    }
}

if ($cccInstalled) {
    $hasClaude = Get-Command "claude" -ErrorAction SilentlyContinue
    if ($hasClaude) {
        claude mcp add cocoindex-code -- ccc mcp 2>$null
        Write-Host "  Configured cocoindex-code MCP server for Claude Code"
    } else {
        Write-Host "  To enable MCP integration, run:"
        Write-Host "    claude mcp add cocoindex-code -- ccc mcp"
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "PRECC $Version installed to $InstallDir."
Write-Host "Run 'precc init' to initialize databases."
if ($rtkInstalled) {
    Write-Host "RTK is available — token-optimized output active by default."
} else {
    Write-Host "WARNING: RTK not installed — output compression limited to diet rules only."
    Write-Host "  Install manually: cargo install rtk  (or visit https://github.com/rtk-ai/rtk)"
}
if ($leanCtxInstalled) {
    Write-Host "lean-ctx is available — deep output compression active by default."
}
if ($nuInstalled) {
    Write-Host "Nushell is available — compact output rewriting active by default."
}
if ($cccInstalled) {
    Write-Host "cocoindex-code is available. Run 'ccc init && ccc index' in your project to enable AST-based semantic search."
}
