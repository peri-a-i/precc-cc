# install.ps1 — PRECC installer for Windows
#
# Usage (PowerShell one-liner):
#   iwr -useb https://raw.githubusercontent.com/yijunyu/precc-cc/main/scripts/install.ps1 | iex
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
$Repo = "yijunyu/precc-cc"
$Target = "x86_64-pc-windows-msvc"
$InstallDir = Join-Path $env:LOCALAPPDATA "precc-cc\bin"

# ---------------------------------------------------------------------------
# WSL detection — if running under WSL, delegate to the Linux installer
# ---------------------------------------------------------------------------
$wslCheck = Get-Command "wsl" -ErrorAction SilentlyContinue
if ($wslCheck -and (wsl echo ok 2>$null) -eq "ok") {
    Write-Host "WSL detected — using Linux installer instead."
    wsl bash -c "curl -fsSL https://raw.githubusercontent.com/$Repo/main/scripts/install.sh | bash"
    exit $LASTEXITCODE
}

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
$Archive = "precc-$Version-$Target.zip"
$Url = "https://github.com/$Repo/releases/download/$Version/$Archive"
$TmpDir = Join-Path $env:TEMP "precc-install-$(New-Guid)"
$ArchivePath = Join-Path $TmpDir $Archive

if ($WhatIf) {
    Write-Host "[WhatIf] Would download: $Url"
    Write-Host "[WhatIf] Would install to: $InstallDir"
    Write-Host "[WhatIf] Would wire hook in: $env:APPDATA\Claude\settings.json"
    exit 0
}

New-Item -ItemType Directory -Path $TmpDir | Out-Null

try {
    Write-Host "Downloading $Url..."
    Invoke-WebRequest -Uri $Url -OutFile $ArchivePath -UseBasicParsing

    Write-Host "Extracting..."
    Expand-Archive -Path $ArchivePath -DestinationPath $TmpDir -Force

    $Extracted = Join-Path $TmpDir "precc-$Version-$Target"

    # -----------------------------------------------------------------------
    # Install binaries
    # -----------------------------------------------------------------------
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir | Out-Null
    }

    foreach ($bin in @("precc.exe", "precc-hook.exe", "precc-miner.exe")) {
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

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "PRECC $Version installed to $InstallDir."
Write-Host "Run 'precc init' to initialize databases."
