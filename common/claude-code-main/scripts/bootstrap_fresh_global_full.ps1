<#
Teammate Read-First Checklist (Global Bootstrap)

Context:
- This project folder can be shared directly with teammates.
- Teammates should read the source files first, then run global setup.

Read order before execution:
1. TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md
2. GLOBAL_BOOTSTRAP_TEAM_GUIDE.md
3. bootstrap_fresh_global_full.ps1 (this file)
4. claude-code-main\scripts\bootstrap_fresh_global_full.ps1
5. claude-code-main\dist\global-plugins\install_global.ps1

Execution rule:
- Prefer running the script copy under: <RepoRoot>\scripts\bootstrap_fresh_global_full.ps1
- Keep arguments explicit (RepoRoot / WorkspacePath / Skills / Superpowers / OpenSpace / SelfImproving / Proactive).
- After run, verify plugins + skills + ~/.codex/config.toml MCP sections.
#>

param(
  [Parameter(Mandatory = $true)][string]$RepoRoot,
  [Parameter(Mandatory = $true)][string]$WorkspacePath,
  [string]$SkillsSourcePath = "",
  [string]$DailySmokeTime = "09:00",
  [int]$GitReviewIntervalHours = 4,
  [int]$GitReviewTimeoutSeconds = 120,
  [switch]$EnableGitReview,
  [switch]$UseSymlink,
  [string]$GithubToken = "",
  [string]$CodexHome = "",
  [string]$SelfImprovingSourcePath = "",
  [string]$ProactiveSourcePath = "",
  [string]$SuperpowersSourcePath = "",
  [string]$OpenSpaceSourcePath = "",
  [switch]$EnableNightlyMemory,
  [string]$NightlyMemoryTime = "01:30",
  [switch]$SkipScheduledTasks,
  [switch]$SkipCodexConfigSync,
  [switch]$SkipSafetyPolicySync,
  [switch]$SkipOpenSpaceSync,
  [switch]$SkipGovernanceToolkitSync,
  [switch]$SkipNativeHooksSync
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Message) {
  Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Write-Info([string]$Message) {
  Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Ok([string]$Message) {
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Resolve-FullPath([string]$PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) { return "" }
  return [System.IO.Path]::GetFullPath($PathValue)
}

function Ensure-Directory([string]$PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    New-Item -ItemType Directory -Force -Path $PathValue | Out-Null
  }
}

function Write-TextFileUtf8NoBom(
  [string]$PathValue,
  [string]$Content
) {
  $dir = Split-Path -Path $PathValue -Parent
  if (-not [string]::IsNullOrWhiteSpace($dir)) {
    Ensure-Directory -PathValue $dir
  }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($PathValue, $Content, $utf8NoBom)
}

function Ensure-File([string]$PathValue, [string]$Content) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    Write-TextFileUtf8NoBom -PathValue $PathValue -Content $Content
  }
}

function Ensure-MarkedBlock(
  [string]$PathValue,
  [string]$StartMarker,
  [string]$EndMarker,
  [string]$BlockContent
) {
  $existing = ""
  if (Test-Path -LiteralPath $PathValue) {
    $existing = Get-Content -LiteralPath $PathValue -Raw -Encoding UTF8
  }
  $pattern = "(?ms)" + [Regex]::Escape($StartMarker) + ".*?" + [Regex]::Escape($EndMarker)
  if ([Regex]::IsMatch($existing, $pattern)) {
    $updated = [Regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $BlockContent }, 1)
  }
  else {
    $updated = if ([string]::IsNullOrWhiteSpace($existing)) { $BlockContent } else { $existing.TrimEnd() + "`r`n`r`n" + $BlockContent }
  }
  Write-TextFileUtf8NoBom -PathValue $PathValue -Content $updated
}

function Sync-DirectoryMirror(
  [string]$SourcePath,
  [string]$DestinationPath,
  [string]$Label
) {
  if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "$Label source not found: $SourcePath"
  }
  Ensure-Directory -PathValue $DestinationPath
  $robocopyCmd = Get-Command robocopy -ErrorAction SilentlyContinue
  if ($null -ne $robocopyCmd) {
    & $robocopyCmd.Source $SourcePath $DestinationPath /MIR /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ge 8) {
      throw "$Label sync failed via robocopy, exit code=$rc"
    }
    return
  }

  Get-ChildItem -LiteralPath $DestinationPath -Force | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Recurse -Force
  }
  Get-ChildItem -LiteralPath $SourcePath -Force | ForEach-Object {
    $dst = Join-Path $DestinationPath $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force
  }
}

function Ensure-JunctionLink(
  [string]$LinkPath,
  [string]$TargetPath
) {
  $targetResolved = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
  if (-not (Test-Path -LiteralPath $targetResolved)) {
    throw "Junction target not found: $targetResolved"
  }

  $parent = Split-Path -Path $LinkPath -Parent
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    Ensure-Directory -PathValue $parent
  }

  if (Test-Path -LiteralPath $LinkPath) {
    $item = Get-Item -LiteralPath $LinkPath -Force
    $isReparse = (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    if ($isReparse) {
      $currentTargets = @($item.Target) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { [System.IO.Path]::GetFullPath($_).TrimEnd('\') }
      if ($currentTargets -contains $targetResolved) {
        return
      }
      Remove-Item -LiteralPath $LinkPath -Force
    }
    else {
      $backupPath = "$LinkPath.backup.$(Get-Date -Format yyyyMMddHHmmss)"
      Move-Item -LiteralPath $LinkPath -Destination $backupPath -Force
      Write-Warn "Existing non-link path moved to backup: $backupPath"
    }
  }

  New-Item -ItemType Junction -Path $LinkPath -Target $targetResolved | Out-Null
}

function Escape-TomlString([string]$Value) {
  if ($null -eq $Value) { return "" }
  return $Value.Replace("\", "\\").Replace('"', '\"')
}

function Ensure-TomlSectionBlock(
  [string]$TomlText,
  [string]$SectionHeader,
  [string[]]$BodyLines
) {
  $block = $SectionHeader + "`r`n" + ($BodyLines -join "`r`n")
  if ([string]::IsNullOrWhiteSpace($TomlText)) {
    return $block + "`r`n"
  }

  $escaped = [Regex]::Escape($SectionHeader)
  $pattern = "(?ms)^\s*$escaped\s*$.*?(?=^\s*\[|\z)"
  if ([Regex]::IsMatch($TomlText, $pattern)) {
    return $TomlText
  }
  return $TomlText.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
}

function Ensure-TomlKeyInSection(
  [string]$TomlText,
  [string]$SectionHeader,
  [string]$KeyName,
  [string]$KeyLine
) {
  $escaped = [Regex]::Escape($SectionHeader)
  $pattern = "(?ms)^\s*$escaped\s*$.*?(?=^\s*\[|\z)"
  $match = [Regex]::Match($TomlText, $pattern)

  if (-not $match.Success) {
    return Ensure-TomlSectionBlock -TomlText $TomlText -SectionHeader $SectionHeader -BodyLines @($KeyLine)
  }

  $sectionText = $match.Value
  $keyPattern = "(?m)^\s*" + [Regex]::Escape($KeyName) + "\s*="
  if ([Regex]::IsMatch($sectionText, $keyPattern)) {
    return $TomlText
  }

  $newSectionText = $sectionText.TrimEnd() + "`r`n" + $KeyLine + "`r`n"
  return $TomlText.Substring(0, $match.Index) + $newSectionText + $TomlText.Substring($match.Index + $match.Length)
}

function Ensure-CodexConfigMcp(
  [string]$ConfigPath,
  [string]$Workspace,
  [string]$FetchCmd,
  [string]$GitCmd,
  [string]$OpenSpaceWorkspace = "",
  [string]$OpenSpaceHostSkillDirs = ""
) {
  $existing = ""
  if (Test-Path -LiteralPath $ConfigPath) {
    $existing = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8
  }
  $updated = $existing

  $workspaceToml = Escape-TomlString -Value $Workspace
  $fetchToml = Escape-TomlString -Value $FetchCmd
  $gitToml = Escape-TomlString -Value $GitCmd

  $updated = Ensure-TomlKeyInSection -TomlText $updated -SectionHeader "[features]" -KeyName "multi_agent" -KeyLine "multi_agent = true"
  $updated = Ensure-TomlKeyInSection -TomlText $updated -SectionHeader "[features]" -KeyName "codex_hooks" -KeyLine "codex_hooks = true"

  $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.playwright]" -BodyLines @(
    'command = "npx"',
    'args = ["-y", "@playwright/mcp@latest"]'
  )
  $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.filesystem]" -BodyLines @(
    'command = "npx"',
    "args = [""-y"", ""@modelcontextprotocol/server-filesystem"", ""$workspaceToml""]"
  )
  $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.fetch]" -BodyLines @(
    "command = ""$fetchToml""",
    'args = []'
  )
  $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.git]" -BodyLines @(
    "command = ""$gitToml""",
    "args = [""--repository"", ""$workspaceToml""]"
  )
  $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.openaiDeveloperDocs]" -BodyLines @(
    'url = "https://developers.openai.com/mcp"'
  )

  if ((-not [string]::IsNullOrWhiteSpace($OpenSpaceWorkspace)) -and (-not [string]::IsNullOrWhiteSpace($OpenSpaceHostSkillDirs))) {
    $openSpaceWorkspaceToml = Escape-TomlString -Value $OpenSpaceWorkspace
    $openSpaceHostSkillDirsToml = Escape-TomlString -Value $OpenSpaceHostSkillDirs
    $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.openspace]" -BodyLines @(
      'command = "py"',
      'args = ["-m", "openspace.mcp_server"]'
    )
    $updated = Ensure-TomlSectionBlock -TomlText $updated -SectionHeader "[mcp_servers.openspace.env]" -BodyLines @(
      "OPENSPACE_WORKSPACE = ""$openSpaceWorkspaceToml""",
      "OPENSPACE_HOST_SKILL_DIRS = ""$openSpaceHostSkillDirsToml""",
      "PYTHONPATH = ""$openSpaceWorkspaceToml"""
    )
  }

  if ($updated -ne $existing) {
    $dir = Split-Path -Path $ConfigPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
      Ensure-Directory -PathValue $dir
    }
    Write-TextFileUtf8NoBom -PathValue $ConfigPath -Content $updated
    return $true
  }
  return $false
}

function Convert-JsonNodeToHashtable(
  [Parameter(ValueFromPipeline = $true)]$Node
) {
  if ($null -eq $Node) { return $null }

  if ($Node -is [pscustomobject]) {
    $ht = [ordered]@{}
    foreach ($p in $Node.PSObject.Properties) {
      $ht[$p.Name] = Convert-JsonNodeToHashtable -Node $p.Value
    }
    return $ht
  }

  if ($Node -is [System.Collections.IDictionary]) {
    $ht = [ordered]@{}
    foreach ($key in $Node.Keys) {
      $ht[[string]$key] = Convert-JsonNodeToHashtable -Node $Node[$key]
    }
    return $ht
  }

  if (($Node -is [System.Collections.IEnumerable]) -and (-not ($Node -is [string]))) {
    $arr = @()
    foreach ($item in $Node) {
      $arr += ,(Convert-JsonNodeToHashtable -Node $item)
    }
    return $arr
  }

  return $Node
}

function New-CodexCommandHookEntry(
  [string]$Command,
  [string]$Matcher = "",
  [string]$StatusMessage = "",
  [int]$TimeoutSeconds = 0
) {
  $hook = [ordered]@{
    type = "command"
    command = $Command
  }
  if (-not [string]::IsNullOrWhiteSpace($StatusMessage)) {
    $hook["statusMessage"] = $StatusMessage
  }
  if ($TimeoutSeconds -gt 0) {
    $hook["timeout"] = $TimeoutSeconds
  }

  $entry = [ordered]@{
    hooks = @($hook)
  }
  if (-not [string]::IsNullOrWhiteSpace($Matcher)) {
    $entry["matcher"] = $Matcher
  }
  return $entry
}

function Entry-ContainsCommand(
  $Entry,
  [string]$CommandNeedle
) {
  if ($null -eq $Entry) { return $false }

  $hooks = @()
  if ($Entry -is [System.Collections.IDictionary]) {
    if ($Entry.Contains("hooks")) {
      $hooks = @($Entry["hooks"])
    }
  }
  elseif ($Entry.PSObject -and ($Entry.PSObject.Properties.Name -contains "hooks")) {
    $hooks = @($Entry.hooks)
  }

  foreach ($h in $hooks) {
    $cmd = ""
    if ($h -is [System.Collections.IDictionary]) {
      if ($h.Contains("command")) { $cmd = [string]$h["command"] }
    }
    elseif ($h.PSObject -and ($h.PSObject.Properties.Name -contains "command")) {
      $cmd = [string]$h.command
    }
    if ($cmd -eq $CommandNeedle) { return $true }
  }
  return $false
}

function Ensure-CodexNativeHooksConfig(
  [string]$HooksPath,
  [string]$HookScriptPath
) {
  if (-not (Test-Path -LiteralPath $HookScriptPath)) {
    throw "Native governance hook script missing: $HookScriptPath"
  }

  $existingRaw = ""
  if (Test-Path -LiteralPath $HooksPath) {
    $existingRaw = Get-Content -LiteralPath $HooksPath -Raw -Encoding UTF8
  }

  $root = [ordered]@{ hooks = [ordered]@{} }
  if (-not [string]::IsNullOrWhiteSpace($existingRaw)) {
    try {
      $parsed = $existingRaw | ConvertFrom-Json
      $root = Convert-JsonNodeToHashtable -Node $parsed
    }
    catch {
      $backupPath = "$HooksPath.bak.$(Get-Date -Format yyyyMMddHHmmss)"
      Copy-Item -LiteralPath $HooksPath -Destination $backupPath -Force
      Write-Warn "Invalid hooks.json backed up to: $backupPath"
      $root = [ordered]@{ hooks = [ordered]@{} }
    }
  }

  if (-not ($root -is [System.Collections.IDictionary])) {
    $root = [ordered]@{ hooks = [ordered]@{} }
  }
  if (-not $root.Contains("hooks") -or -not ($root["hooks"] -is [System.Collections.IDictionary])) {
    $root["hooks"] = [ordered]@{}
  }

  $hooksRoot = $root["hooks"]
  $hookCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$HookScriptPath`""
  $changed = $false

  $managed = @(
    [ordered]@{ event = "SessionStart"; matcher = "startup|resume"; status = "Loading global governance context"; timeout = 0 },
    [ordered]@{ event = "UserPromptSubmit"; matcher = ""; status = "Classifying governance profile"; timeout = 0 },
    [ordered]@{ event = "PreToolUse"; matcher = "Bash"; status = "Running governance preflight"; timeout = 0 },
    [ordered]@{ event = "PostToolUse"; matcher = "Bash"; status = "Reviewing command outcome"; timeout = 0 }
  )

  foreach ($m in $managed) {
    $eventName = [string]$m.event
    $existingEntries = @()
    if ($hooksRoot.Contains($eventName)) {
      $existingEntries = @($hooksRoot[$eventName])
    }

    $filtered = @()
    foreach ($entry in $existingEntries) {
      if (-not (Entry-ContainsCommand -Entry $entry -CommandNeedle $hookCommand)) {
        $filtered += ,$entry
      }
      else {
        $changed = $true
      }
    }

    $filtered += ,(New-CodexCommandHookEntry -Command $hookCommand -Matcher ([string]$m.matcher) -StatusMessage ([string]$m.status) -TimeoutSeconds ([int]$m.timeout))
    $hooksRoot[$eventName] = $filtered
    $changed = $true
  }

  $finalRaw = $root | ConvertTo-Json -Depth 30
  $finalRaw = $finalRaw + "`r`n"
  if ($changed -or (-not (Test-Path -LiteralPath $HooksPath)) -or ($existingRaw -ne $finalRaw)) {
    $dir = Split-Path -Path $HooksPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
      Ensure-Directory -PathValue $dir
    }
    Write-TextFileUtf8NoBom -PathValue $HooksPath -Content $finalRaw
    return $true
  }
  return $false
}

function Append-BlockIfMissing(
  [string]$PathValue,
  [string]$Marker,
  [string]$BlockContent
) {
  $existing = ""
  if (Test-Path -LiteralPath $PathValue) {
    $existing = Get-Content -LiteralPath $PathValue -Raw -Encoding UTF8
  }
  if ($existing -like "*$Marker*") {
    return $false
  }
  $updated = if ([string]::IsNullOrWhiteSpace($existing)) { $BlockContent } else { $existing + "`r`n`r`n" + $BlockContent }
  Write-TextFileUtf8NoBom -PathValue $PathValue -Content $updated
  return $true
}

function Write-IntegrationMcpConfig(
  [string]$McpPath,
  [string]$Workspace,
  [string]$FetchCommand,
  [string]$GitCommand
) {
  $mcp = [ordered]@{
    mcpServers = [ordered]@{
      playwright = [ordered]@{
        command = "npx"
        args = @("-y", "@playwright/mcp@latest")
      }
      filesystem = [ordered]@{
        command = "npx"
        args = @("-y", "@modelcontextprotocol/server-filesystem", $Workspace)
      }
      fetch = [ordered]@{
        command = $FetchCommand
        args = @()
      }
      git = [ordered]@{
        command = $GitCommand
        args = @("--repository", $Workspace)
      }
      github = [ordered]@{
        command = "npx"
        args = @("-y", "@modelcontextprotocol/server-github")
        env = [ordered]@{
          GITHUB_PERSONAL_ACCESS_TOKEN = '${GITHUB_TOKEN}'
        }
      }
      openaiDeveloperDocs = [ordered]@{
        url = "https://developers.openai.com/mcp"
      }
    }
  }
  $mcpJson = $mcp | ConvertTo-Json -Depth 20
  Write-TextFileUtf8NoBom -PathValue $McpPath -Content $mcpJson
}

function Ensure-MemoryWritebackScript([string]$TargetPath) {
  $script = @'
#!/usr/bin/env python3
"""Deterministic memory writeback helper for global Codex memories."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


DEFAULT_CODEX_HOME = Path(os.environ.get("USERPROFILE", "~")).expanduser() / ".codex"
DEFAULT_MEMORY_DIR = DEFAULT_CODEX_HOME / "memories"
DEFAULT_QUEUE_PATH = DEFAULT_CODEX_HOME / "runtime" / "proactive" / "writeback-queue.jsonl"

SIG_RE = re.compile(r"<!-- wb-sig:(?P<sig>[a-f0-9]{64}) -->")


@dataclass(frozen=True)
class EntryPayload:
    kind: str
    date: str
    context: str
    fields: dict[str, str]

    def signature(self) -> str:
        base = {
            "kind": self.kind,
            "context": normalize(self.context),
            "fields": {k: normalize(v) for k, v in sorted(self.fields.items())},
        }
        raw = json.dumps(base, ensure_ascii=False, sort_keys=True)
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def normalize(text: str) -> str:
    return re.sub(r"\s+", " ", text.strip().lower())


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def load_existing_signatures(path: Path) -> set[str]:
    if not path.exists():
        return set()
    text = path.read_text(encoding="utf-8", errors="replace")
    return {m.group("sig") for m in SIG_RE.finditer(text)}


def append_text(path: Path, text: str) -> None:
    ensure_parent(path)
    with path.open("a", encoding="utf-8") as f:
        f.write(text)


def queue_write(queue_path: Path, payload: dict) -> None:
    ensure_parent(queue_path)
    record = {"queued_at": datetime.now().isoformat(timespec="seconds"), **payload}
    with queue_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")


def target_file(kind: str, memory_dir: Path) -> Path:
    mapping = {
        "learning": "LEARNINGS.md",
        "error": "ERRORS.md",
        "feature": "FEATURE_REQUESTS.md",
    }
    return memory_dir / mapping[kind]


def render_entry(payload: EntryPayload, sig: str) -> str:
    header = f"## {payload.date} - {payload.context}\n<!-- wb-sig:{sig} -->\n"
    if payload.kind == "learning":
        body = (
            f"- Situation: {payload.fields['situation']}\n"
            f"- What worked: {payload.fields['what_worked']}\n"
            f"- Reusable pattern: {payload.fields['reusable_pattern']}\n"
            f"- Recommendation for future runs: {payload.fields['next_recommendation']}\n"
        )
    elif payload.kind == "error":
        body = (
            f"- Situation: {payload.fields['situation']}\n"
            f"- Error / failure: {payload.fields['error_failure']}\n"
            f"- Cause: {payload.fields['cause']}\n"
            f"- Fix / workaround: {payload.fields['fix_workaround']}\n"
            f"- Prevention next time: {payload.fields['prevention_next_time']}\n"
        )
    else:
        body = (
            f"- Missing capability: {payload.fields['missing_capability']}\n"
            f"- Why it matters: {payload.fields['why_it_matters']}\n"
            f"- Current workaround: {payload.fields['current_workaround']}\n"
            f"- Desired improvement: {payload.fields['desired_improvement']}\n"
        )
    return f"\n{header}{body}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Append writeback entry to global memory files.")
    parser.add_argument("--kind", choices=["learning", "error", "feature"], required=True)
    parser.add_argument("--context", required=True)
    parser.add_argument("--date", default=datetime.now().strftime("%Y-%m-%d"))
    parser.add_argument("--memory-dir", default=str(DEFAULT_MEMORY_DIR))
    parser.add_argument("--queue-path", default=str(DEFAULT_QUEUE_PATH))
    parser.add_argument("--situation")
    parser.add_argument("--what-worked")
    parser.add_argument("--reusable-pattern")
    parser.add_argument("--next-recommendation")
    parser.add_argument("--error-failure")
    parser.add_argument("--cause")
    parser.add_argument("--fix-workaround")
    parser.add_argument("--prevention-next-time")
    parser.add_argument("--missing-capability")
    parser.add_argument("--why-it-matters")
    parser.add_argument("--current-workaround")
    parser.add_argument("--desired-improvement")
    return parser.parse_args()


def build_payload(args: argparse.Namespace) -> EntryPayload:
    def require(*names: str) -> dict[str, str]:
        values: dict[str, str] = {}
        missing: list[str] = []
        for name in names:
            value = getattr(args, name.replace("-", "_"), None)
            if value is None or not str(value).strip():
                missing.append("--" + name)
            else:
                values[name.replace("-", "_")] = str(value).strip()
        if missing:
            raise ValueError(f"Missing required arguments for {args.kind}: {', '.join(missing)}")
        return values

    if args.kind == "learning":
        fields = require("situation", "what-worked", "reusable-pattern", "next-recommendation")
    elif args.kind == "error":
        fields = require("situation", "error-failure", "cause", "fix-workaround", "prevention-next-time")
    else:
        fields = require("missing-capability", "why-it-matters", "current-workaround", "desired-improvement")

    return EntryPayload(
        kind=args.kind,
        date=str(args.date).strip(),
        context=str(args.context).strip(),
        fields=fields,
    )


def ensure_header(path: Path) -> None:
    if path.exists():
        return
    title = path.stem
    ensure_parent(path)
    path.write_text(f"# {title}\n", encoding="utf-8")


def main() -> int:
    args = parse_args()
    try:
        payload = build_payload(args)
    except ValueError as exc:
        print(f"ERROR: {exc}")
        return 2

    memory_dir = Path(args.memory_dir).expanduser()
    queue_path = Path(args.queue_path).expanduser()
    target = target_file(payload.kind, memory_dir)
    sig = payload.signature()

    try:
        ensure_header(target)
        existing = load_existing_signatures(target)
        if sig in existing:
            print(f"SKIP_DUPLICATE: {payload.kind} -> {target}")
            return 0
        append_text(target, render_entry(payload, sig))
        print(f"APPENDED: {payload.kind} -> {target}")
        return 0
    except OSError as exc:
        queue_payload = {
            "reason": "memory_write_failed",
            "error": str(exc),
            "target": str(target),
            "kind": payload.kind,
            "date": payload.date,
            "context": payload.context,
            "fields": payload.fields,
            "signature": sig,
        }
        queue_write(queue_path, queue_payload)
        print(f"QUEUED: {payload.kind} -> {queue_path}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
'@
  Write-TextFileUtf8NoBom -PathValue $TargetPath -Content $script
}

function Ensure-GovernanceToolkitScripts(
  [string]$GovernanceDir
) {
  Ensure-Directory -PathValue $GovernanceDir

  $preflightPath = Join-Path $GovernanceDir "codex_preflight_gate.ps1"
  $doctorPath = Join-Path $GovernanceDir "codex_doctor.ps1"
  $regressionPath = Join-Path $GovernanceDir "codex_regression_check.ps1"
  $contractCheckPath = Join-Path $GovernanceDir "codex_project_contract_check.ps1"
  $contractInitPath = Join-Path $GovernanceDir "codex_project_contract_init.ps1"
  $contractTemplatePath = Join-Path $GovernanceDir "codex_task_contract.template.json"
  $crawlerInitPath = Join-Path $GovernanceDir "codex_crawler_project_init.ps1"
  $crawlerSmokePath = Join-Path $GovernanceDir "codex_crawler_smoke_test.ps1"
  $crawlerTemplatePath = Join-Path $GovernanceDir "codex_crawler_contract.template.json"
  $nativeHookPath = Join-Path $GovernanceDir "codex_native_governance_hook.ps1"
  $readmePath = Join-Path $GovernanceDir "README.md"

  $preflightScript = @'
param(
  [string]$TaskText = "",
  [string]$CommandLine = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$profile = "standard"
$profileReasons = @()
$decision = "advise"
$decisionReasons = @()

function Count-SignalHits([string]$Text, [string[]]$Signals) {
  if ([string]::IsNullOrWhiteSpace($Text)) { return 0 }
  $count = 0
  $lower = $Text.ToLowerInvariant()
  foreach ($s in $Signals) {
    if ([string]::IsNullOrWhiteSpace($s)) { continue }
    if ($lower.Contains($s.ToLowerInvariant())) {
      $count += 1
    }
  }
  return $count
}

$lightSignals = @(
  "doc", "docs", "readme", "comment", "typo", "markdown"
)
$strictSignals = @(
  "migration", "deploy", "production", "checkpoint", "train", "training", "inference",
  "optimizer", "scheduler", "dataset", "queue", "concurrency", "stateful",
  "external api", "payment", "billing", "model", "loss", "metric",
  "crawler", "scrape", "spider", "ml", "dl", "llm"
)

$lightScore = Count-SignalHits -Text $TaskText -Signals $lightSignals
$strictScore = Count-SignalHits -Text $TaskText -Signals $strictSignals

$unicodeLightPatterns = @(
  '\u6587\u6863',
  '\u6ce8\u91ca',
  '\u62fc\u5199',
  '\u6392\u7248'
)
$unicodeStrictPatterns = @(
  '\u8bad\u7ec3',
  '\u63a8\u7406',
  '\u6a21\u578b',
  '\u635f\u5931',
  '\u68c0\u67e5\u70b9',
  '\u4f18\u5316\u5668',
  '\u8c03\u5ea6\u5668',
  '\u6570\u636e\u96c6',
  '\u722c\u866b',
  '\u5e76\u53d1',
  '\u961f\u5217',
  '\u90e8\u7f72',
  '\u751f\u4ea7',
  '\u8fc1\u79fb'
)
foreach ($p in $unicodeLightPatterns) {
  if ($TaskText -match $p) { $lightScore += 1 }
}
foreach ($p in $unicodeStrictPatterns) {
  if ($TaskText -match $p) { $strictScore += 1 }
}

if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {
  $commandStrictPatterns = @(
    '(?i)\b(train|training|torchrun|deepspeed|accelerate)\b',
    '(?i)\b(scrapy|crawl|playwright)\b',
    '(?i)\b(alembic|migrate|migration)\b',
    '(?i)\b(kubectl|helm|terraform|ansible)\b'
  )
  foreach ($cp in $commandStrictPatterns) {
    if ($CommandLine -match $cp) {
      $strictScore += 1
      break
    }
  }
}

if ($strictScore -gt 0 -and $strictScore -ge ($lightScore + 1)) {
  $profile = "strict"
  $profileReasons += "Semantic/risk evidence indicates high-impact runtime/data behavior."
}
elseif ($lightScore -gt 0 -and $strictScore -eq 0) {
  $profile = "light"
  $profileReasons += "Signals indicate low-risk documentation/text scope."
}
else {
  $profile = "standard"
  $profileReasons += "Mixed or weak signals; using standard profile."
}

if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {
  $blockPatterns = @(
    @{ pattern = '(?i)\bgit\s+reset\s+--hard\b'; reason = 'Destructive git reset.' },
    @{ pattern = '(?i)\bgit\s+clean\s+-f(?:d|x|dx|xd)?\b'; reason = 'Destructive git clean.' },
    @{ pattern = '(?i)\b(format|diskpart|bcdedit|reg\s+delete)\b'; reason = 'Potential system-destructive command.' }
  )
  $warnPatterns = @(
    @{ pattern = '(?i)\b(remove-item|rm|del|rmdir)\b'; reason = 'Delete-like command detected.' },
    @{ pattern = '(?i)\b(move-item|move)\b'; reason = 'Move operation can be hard to rollback.' },
    @{ pattern = '(?i)\brobocopy\b.*\s+/mir\b'; reason = 'Mirror copy can delete destination content.' }
  )

  foreach ($p in $blockPatterns) {
    if ($CommandLine -match $p.pattern) {
      $decision = "block"
      $decisionReasons += $p.reason
    }
  }
  if ($decision -ne "block") {
    foreach ($p in $warnPatterns) {
      if ($CommandLine -match $p.pattern) {
        $decision = "warn"
        $decisionReasons += $p.reason
      }
    }
  }
}
else {
  $decisionReasons += "No command provided. This is a task-level profile check only."
}

if ($decisionReasons.Count -eq 0) {
  $decisionReasons += "No high-risk command pattern detected."
}

$result = [pscustomobject]@{
  timestamp = (Get-Date -Format s)
  profile = $profile
  decision = $decision
  profile_reasons = $profileReasons
  decision_reasons = $decisionReasons
  recommended_action = switch ($decision) {
    "block" { "Stop and ask for explicit confirmation with scope." }
    "warn" { "Continue only with explicit risk note and mitigation plan." }
    default { "Continue under standard safeguards." }
  }
}

if ($AsJson) {
  $result | ConvertTo-Json -Depth 6
}
else {
  $result | Format-List
}

switch ($decision) {
  "block" { exit 2 }
  "warn" { exit 1 }
  default { exit 0 }
}
'@
  Write-TextFileUtf8NoBom -PathValue $preflightPath -Content $preflightScript

  $nativeHookScript = @'
param()

$ErrorActionPreference = "Stop"

function Read-StdInText {
  $reader = [System.IO.StreamReader]::new([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
  try {
    return $reader.ReadToEnd()
  }
  finally {
    $reader.Dispose()
  }
}

function Get-PropertyValue([object]$Obj, [string[]]$Names) {
  if ($null -eq $Obj) { return $null }
  foreach ($name in $Names) {
    if ($Obj -is [System.Collections.IDictionary]) {
      if ($Obj.Contains($name)) { return $Obj[$name] }
    }
    elseif ($Obj.PSObject -and ($Obj.PSObject.Properties.Name -contains $name)) {
      return $Obj.$name
    }
  }
  return $null
}

function Get-StringValue([object]$Obj, [string[]]$Names) {
  $raw = Get-PropertyValue -Obj $Obj -Names $Names
  if ($null -eq $raw) { return "" }
  return [string]$raw
}

function Emit-JsonAndExit([object]$Obj) {
  if ($null -ne $Obj) {
    $json = $Obj | ConvertTo-Json -Depth 15 -Compress
    [Console]::Out.WriteLine($json)
  }
  exit 0
}

function Invoke-Preflight(
  [string]$PreflightPath,
  [string]$TaskText,
  [string]$CommandLine
) {
  if (-not (Test-Path -LiteralPath $PreflightPath)) { return $null }

  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PreflightPath, "-TaskText", $TaskText, "-AsJson")
  if (-not [string]::IsNullOrWhiteSpace($CommandLine)) {
    $args += @("-CommandLine", $CommandLine)
  }
  $raw = & powershell @args 2>$null
  $rawText = if ($raw -is [System.Array]) { [string]::Join("`n", @($raw)) } else { [string]$raw }
  if ([string]::IsNullOrWhiteSpace($rawText)) { return $null }
  try {
    return ($rawText | ConvertFrom-Json)
  }
  catch {
    return $null
  }
}

try {
  $stdinRaw = Read-StdInText
  if ([string]::IsNullOrWhiteSpace($stdinRaw)) { Emit-JsonAndExit $null }

  $payload = $stdinRaw | ConvertFrom-Json
  $hookEvent = Get-StringValue -Obj $payload -Names @("hook_event_name", "hookEventName", "event", "name")
  $toolName = Get-StringValue -Obj $payload -Names @("tool_name", "toolName")
  $promptText = Get-StringValue -Obj $payload -Names @("prompt", "input", "user_prompt", "userPrompt", "text")
  $toolInput = Get-PropertyValue -Obj $payload -Names @("tool_input", "toolInput")
  $commandLine = Get-StringValue -Obj $toolInput -Names @("command")

  $codexHome = Join-Path $env:USERPROFILE ".codex"
  $preflightPath = Join-Path (Join-Path $codexHome "runtime\\governance") "codex_preflight_gate.ps1"

  switch ($hookEvent) {
    "SessionStart" {
      Emit-JsonAndExit @{
        hookSpecificOutput = @{
          hookEventName = "SessionStart"
          additionalContext = "Global governance runtime is active (native Codex hooks + runtime scripts)."
        }
      }
    }
    "UserPromptSubmit" {
      $preflight = Invoke-Preflight -PreflightPath $preflightPath -TaskText $promptText -CommandLine ""
      if ($null -eq $preflight) { Emit-JsonAndExit $null }

      $profile = [string](Get-PropertyValue -Obj $preflight -Names @("profile"))
      $decision = [string](Get-PropertyValue -Obj $preflight -Names @("decision"))

      if (($profile -eq "strict") -or ($decision -eq "warn") -or ($decision -eq "block")) {
        $context = "Governance profile=$profile decision=$decision. Apply failure map + minimal patch + focused validation."
        Emit-JsonAndExit @{
          hookSpecificOutput = @{
            hookEventName = "UserPromptSubmit"
            additionalContext = $context
          }
        }
      }
      Emit-JsonAndExit $null
    }
    "PreToolUse" {
      if ($toolName -ne "Bash") { Emit-JsonAndExit $null }
      if ([string]::IsNullOrWhiteSpace($commandLine)) { Emit-JsonAndExit $null }

      $preflight = Invoke-Preflight -PreflightPath $preflightPath -TaskText $promptText -CommandLine $commandLine
      if ($null -eq $preflight) { Emit-JsonAndExit $null }

      $decision = [string](Get-PropertyValue -Obj $preflight -Names @("decision"))
      $reasons = Get-PropertyValue -Obj $preflight -Names @("decision_reasons")
      $reasonText = if ($null -eq $reasons) { "governance preflight decision" } else { ([string[]]$reasons) -join "; " }

      if ($decision -eq "block") {
        Emit-JsonAndExit @{
          decision = "block"
          reason = "Governance preflight blocked command: $reasonText"
          hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            additionalContext = "Command blocked by governance policy. Provide explicit scope and confirmation before retry."
          }
        }
      }

      if ($decision -eq "warn") {
        Emit-JsonAndExit @{
          hookSpecificOutput = @{
            hookEventName = "PreToolUse"
            additionalContext = "Governance preflight warning: $reasonText"
          }
        }
      }

      Emit-JsonAndExit $null
    }
    default {
      Emit-JsonAndExit $null
    }
  }
}
catch {
  Emit-JsonAndExit $null
}
'@
  Write-TextFileUtf8NoBom -PathValue $nativeHookPath -Content $nativeHookScript

  $doctorScript = @'
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$checks = @()

function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
  $script:checks += [pscustomobject]@{
    check = $Name
    pass = $Pass
    detail = $Detail
  }
}

function Marker-Count([string]$PathValue, [string]$Marker) {
  if (-not (Test-Path -LiteralPath $PathValue)) { return 0 }
  return (Select-String -Path $PathValue -Pattern $Marker -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count
}

function Test-Utf8NoBom([string]$PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) { return $false }
  $bytes = [System.IO.File]::ReadAllBytes($PathValue)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return $false
  }
  return $true
}

$agentsPath = Join-Path $CodexHome "AGENTS.md"
$activePath = Join-Path $CodexHome "memories\\ACTIVE.md"
$rulesPath = Join-Path $CodexHome "rules\\default.rules"
$configPath = Join-Path $CodexHome "config.toml"
$governanceDir = Join-Path $CodexHome "runtime\\governance"
$doctorPath = Join-Path $governanceDir "codex_doctor.ps1"
$preflightPath = Join-Path $governanceDir "codex_preflight_gate.ps1"
$regressionPath = Join-Path $governanceDir "codex_regression_check.ps1"
$contractCheckPath = Join-Path $governanceDir "codex_project_contract_check.ps1"
$contractInitPath = Join-Path $governanceDir "codex_project_contract_init.ps1"
$contractTemplatePath = Join-Path $governanceDir "codex_task_contract.template.json"
$crawlerInitPath = Join-Path $governanceDir "codex_crawler_project_init.ps1"
$crawlerSmokePath = Join-Path $governanceDir "codex_crawler_smoke_test.ps1"
$crawlerTemplatePath = Join-Path $governanceDir "codex_crawler_contract.template.json"
$nativeHookPath = Join-Path $governanceDir "codex_native_governance_hook.ps1"
$hooksPath = Join-Path $CodexHome "hooks.json"

$requiredFiles = @($agentsPath, $activePath, $rulesPath, $configPath, $doctorPath, $preflightPath, $regressionPath, $contractCheckPath, $contractInitPath, $contractTemplatePath, $crawlerInitPath, $crawlerSmokePath, $crawlerTemplatePath, $nativeHookPath, $hooksPath)
foreach ($f in $requiredFiles) {
  Add-Check "exists:$f" (Test-Path -LiteralPath $f) ("path=" + $f)
}

$agentMarkers = @(
  "<!-- codex-global-safety-guard:start -->",
  "<!-- codex-global-execution-policy:start -->",
  "<!-- codex-global-ml-active-trigger:start -->",
  "<!-- codex-global-reliability-policy:start -->",
  "<!-- codex-global-governance-policy:start -->",
  "<!-- codex-global-policy-runtime:start -->"
)
foreach ($m in $agentMarkers) {
  $count = Marker-Count -PathValue $agentsPath -Marker $m
  Add-Check "marker:AGENTS:$m" ($count -eq 1) ("count=" + $count)
}

$activeMarkers = @(
  "<!-- codex-active-execution-policy:start -->",
  "<!-- codex-active-reliability-policy:start -->",
  "<!-- codex-active-governance-policy:start -->",
  "<!-- codex-active-policy-runtime:start -->"
)
foreach ($m in $activeMarkers) {
  $count = Marker-Count -PathValue $activePath -Marker $m
  Add-Check "marker:ACTIVE:$m" ($count -eq 1) ("count=" + $count)
}

$rulesMarkers = @(
  "# codex-global-delete-guard:start",
  "# codex-global-risk-guard:start"
)
foreach ($m in $rulesMarkers) {
  $count = Marker-Count -PathValue $rulesPath -Marker $m
  Add-Check "marker:RULES:$m" ($count -eq 1) ("count=" + $count)
}

$utfTargets = @($agentsPath, $activePath, $rulesPath, $configPath)
foreach ($f in $utfTargets) {
  Add-Check "utf8-no-bom:$f" (Test-Utf8NoBom -PathValue $f) ("path=" + $f)
}

$requiredMcp = @("playwright", "filesystem", "fetch", "git", "openaiDeveloperDocs")
foreach ($name in $requiredMcp) {
  $pattern = "^\[mcp_servers\." + [Regex]::Escape($name) + "\]$"
  $count = if (Test-Path -LiteralPath $configPath) {
    (Select-String -Path $configPath -Pattern $pattern -ErrorAction SilentlyContinue | Measure-Object).Count
  }
  else { 0 }
  Add-Check "mcp:$name" ($count -ge 1) ("count=" + $count)
}

$openspacePattern = "^\[mcp_servers\.openspace\]$"
$openspaceCount = if (Test-Path -LiteralPath $configPath) {
  (Select-String -Path $configPath -Pattern $openspacePattern -ErrorAction SilentlyContinue | Measure-Object).Count
}
else { 0 }
Add-Check "mcp:openspace(optional)" ($openspaceCount -ge 0) ("count=" + $openspaceCount)

$codexHooksCount = if (Test-Path -LiteralPath $configPath) {
  (Select-String -Path $configPath -Pattern '^\s*codex_hooks\s*=\s*true\s*$' -ErrorAction SilentlyContinue | Measure-Object).Count
}
else { 0 }
Add-Check "feature:codex_hooks" ($codexHooksCount -ge 1) ("count=" + $codexHooksCount)

if (Test-Path -LiteralPath $hooksPath) {
  try {
    $hooksRaw = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8
    $null = $hooksRaw | ConvertFrom-Json
    Add-Check "hooks.json.parse" $true ("path=" + $hooksPath)
    $managedCount = (Select-String -InputObject $hooksRaw -Pattern 'codex_native_governance_hook\.ps1' -AllMatches | Measure-Object).Count
    Add-Check "hooks.json.managed_hook" ($managedCount -ge 1) ("count=" + $managedCount)
    $preToolCount = (Select-String -InputObject $hooksRaw -Pattern '"PreToolUse"' -AllMatches | Measure-Object).Count
    Add-Check "hooks.json.event_pretooluse" ($preToolCount -ge 1) ("count=" + $preToolCount)
  }
  catch {
    Add-Check "hooks.json.parse" $false ("error=" + $_.Exception.Message)
  }
}

$preCommitCmd = Get-Command pre-commit -ErrorAction SilentlyContinue
if ($null -eq $preCommitCmd) {
  $pyCmd = Get-Command py -ErrorAction SilentlyContinue
  if ($null -ne $pyCmd) {
    $null = & $pyCmd.Source -m pre_commit --version 2>$null
    if ($LASTEXITCODE -eq 0) {
      Add-Check "tool:pre-commit" $true "resolved via py -m pre_commit"
    }
    else {
      Add-Check "tool:pre-commit" $false "not found in PATH and py -m pre_commit unavailable"
    }
  }
  else {
    Add-Check "tool:pre-commit" $false "neither pre-commit nor py launcher found"
  }
}
else {
  Add-Check "tool:pre-commit" $true ("path=" + $preCommitCmd.Source)
}

$failed = @($checks | Where-Object { -not $_.pass })

if ($AsJson) {
  [pscustomobject]@{
    total = $checks.Count
    failed = $failed.Count
    checks = $checks
  } | ConvertTo-Json -Depth 8
}
else {
  $checks | Format-Table -AutoSize
  if ($failed.Count -gt 0) {
    Write-Host ("doctor_status=FAILED failed_checks=" + $failed.Count) -ForegroundColor Red
  }
  else {
    Write-Host "doctor_status=OK" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
'@
  Write-TextFileUtf8NoBom -PathValue $doctorPath -Content $doctorScript

  $regressionScript = @'
param(
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex"),
  [string]$BundleRoot = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$checks = @()

function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
  $script:checks += [pscustomobject]@{
    check = $Name
    pass = $Pass
    detail = $Detail
  }
}

function Marker-Count([string]$PathValue, [string]$Marker) {
  if (-not (Test-Path -LiteralPath $PathValue)) { return 0 }
  return (Select-String -Path $PathValue -Pattern $Marker -SimpleMatch -ErrorAction SilentlyContinue | Measure-Object).Count
}

$governanceDir = Join-Path $CodexHome "runtime\\governance"
$doctorPath = Join-Path $governanceDir "codex_doctor.ps1"

if (Test-Path -LiteralPath $doctorPath) {
  & powershell -ExecutionPolicy Bypass -File $doctorPath -CodexHome $CodexHome
  Add-Check "doctor.exit" ($LASTEXITCODE -eq 0) ("exit=" + $LASTEXITCODE)
}
else {
  Add-Check "doctor.exists" $false ("missing=" + $doctorPath)
}

if ([string]::IsNullOrWhiteSpace($BundleRoot) -or -not (Test-Path -LiteralPath $BundleRoot)) {
  Add-Check "distribution.bundle_root" $true "skipped (bundle root not provided or not found)"
}
else {
  $bundleCandidates = @(
    [pscustomobject]@{
      Name = "modern"
      Bootstrap = Join-Path $BundleRoot "win\\bootstrap_fresh_global_full.ps1"
      Guide = Join-Path $BundleRoot "win\\GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"
      Teammate = Join-Path $BundleRoot "win\\TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md"
      BootstrapMirror = Join-Path $BundleRoot "common\\claude-code-main\\scripts\\bootstrap_fresh_global_full.ps1"
      GuideMirror = ""
    },
    [pscustomobject]@{
      Name = "legacy"
      Bootstrap = Join-Path $BundleRoot "bootstrap_fresh_global_full.ps1"
      Guide = Join-Path $BundleRoot "GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"
      Teammate = Join-Path $BundleRoot "TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md"
      BootstrapMirror = Join-Path $BundleRoot "claude-code-main\\scripts\\bootstrap_fresh_global_full.ps1"
      GuideMirror = Join-Path $BundleRoot "claude-code-main\\GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"
    }
  )

  $selected = $null
  foreach ($candidate in $bundleCandidates) {
    if (Test-Path -LiteralPath $candidate.Bootstrap) {
      $selected = $candidate
      break
    }
  }
  if ($null -eq $selected) {
    $selected = $bundleCandidates[0]
  }
  Add-Check "distribution.layout" $true ("selected=" + $selected.Name)

  $bootstrapRoot = $selected.Bootstrap
  $guideRoot = $selected.Guide
  $teammateRoot = $selected.Teammate
  $bootstrapMirror = $selected.BootstrapMirror
  $guideMirror = $selected.GuideMirror

  $required = @($bootstrapRoot, $guideRoot, $teammateRoot, $bootstrapMirror)
  foreach ($f in $required) {
    Add-Check "distribution.exists:$f" (Test-Path -LiteralPath $f) ("path=" + $f)
  }
  if (-not [string]::IsNullOrWhiteSpace($guideMirror)) {
    Add-Check "distribution.exists_optional:$guideMirror" (Test-Path -LiteralPath $guideMirror) ("path=" + $guideMirror)
  }

  if (Test-Path -LiteralPath $bootstrapRoot) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($bootstrapRoot, [ref]$tokens, [ref]$errors)
    $errorCount = if ($null -eq $errors) { 0 } else { $errors.Count }
    Add-Check "distribution.bootstrap_parse" ($errorCount -eq 0) ("errors=" + $errorCount)

    $neededMarkers = @(
      "codex-global-reliability-policy:start",
      "codex-global-governance-policy:start",
      "codex-active-reliability-policy:start",
      "codex-active-governance-policy:start",
      "codex-global-policy-runtime:start",
      "codex-active-policy-runtime:start",
      "codex_doctor.ps1",
      "codex_regression_check.ps1",
      "codex_preflight_gate.ps1",
      "codex_project_contract_check.ps1",
      "codex_project_contract_init.ps1",
      "codex_task_contract.template.json",
      "codex_crawler_project_init.ps1",
      "codex_crawler_smoke_test.ps1",
      "codex_crawler_contract.template.json",
      "codex_native_governance_hook.ps1",
      "hooks.json",
      "codex_hooks = true"
    )
    foreach ($m in $neededMarkers) {
      $count = Marker-Count -PathValue $bootstrapRoot -Marker $m
      Add-Check "distribution.bootstrap_marker:$m" ($count -ge 1) ("count=" + $count)
    }
  }

  if ((Test-Path -LiteralPath $bootstrapRoot) -and (Test-Path -LiteralPath $bootstrapMirror)) {
    $h1 = (Get-FileHash -LiteralPath $bootstrapRoot -Algorithm SHA256).Hash
    $h2 = (Get-FileHash -LiteralPath $bootstrapMirror -Algorithm SHA256).Hash
    Add-Check "distribution.bootstrap_hash_sync" ($h1 -eq $h2) ("root=" + $h1 + " mirror=" + $h2)
  }

  if ((Test-Path -LiteralPath $guideRoot) -and (Test-Path -LiteralPath $guideMirror)) {
    $h1 = (Get-FileHash -LiteralPath $guideRoot -Algorithm SHA256).Hash
    $h2 = (Get-FileHash -LiteralPath $guideMirror -Algorithm SHA256).Hash
    Add-Check "distribution.guide_hash_sync" ($h1 -eq $h2) ("root=" + $h1 + " mirror=" + $h2)
  }

  if (Test-Path -LiteralPath $teammateRoot) {
    $teammateMarkers = @(
      "codex-global-reliability-policy:start",
      "codex-global-governance-policy:start",
      "codex-active-reliability-policy:start",
      "codex-active-governance-policy:start",
      "codex-global-policy-runtime:start",
      "codex-active-policy-runtime:start"
    )
    foreach ($m in $teammateMarkers) {
      $count = Marker-Count -PathValue $teammateRoot -Marker $m
      Add-Check "distribution.teammate_marker:$m" ($count -ge 1) ("count=" + $count)
    }
  }
}

$failed = @($checks | Where-Object { -not $_.pass })

if ($AsJson) {
  [pscustomobject]@{
    total = $checks.Count
    failed = $failed.Count
    checks = $checks
  } | ConvertTo-Json -Depth 8
}
else {
  $checks | Format-Table -AutoSize
  if ($failed.Count -gt 0) {
    Write-Host ("regression_status=FAILED failed_checks=" + $failed.Count) -ForegroundColor Red
  }
  else {
    Write-Host "regression_status=OK" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
'@
  Write-TextFileUtf8NoBom -PathValue $regressionPath -Content $regressionScript

  $contractCheckScript = @'
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string]$ContractPath = "",
  [switch]$FailOnMissingContract,
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$checks = @()

function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
  $script:checks += [pscustomobject]@{
    check = $Name
    pass = $Pass
    detail = $Detail
  }
}

function Resolve-AbsolutePath([string]$BasePath, [string]$RelativeOrAbsolute) {
  if ([string]::IsNullOrWhiteSpace($RelativeOrAbsolute)) { return "" }
  if ([System.IO.Path]::IsPathRooted($RelativeOrAbsolute)) {
    return [System.IO.Path]::GetFullPath($RelativeOrAbsolute)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $RelativeOrAbsolute))
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
  throw "ProjectRoot not found: $ProjectRoot"
}

if ([string]::IsNullOrWhiteSpace($ContractPath)) {
  $ContractPath = Join-Path $ProjectRoot ".codex-task-contract.json"
}
else {
  $ContractPath = Resolve-AbsolutePath -BasePath $ProjectRoot -RelativeOrAbsolute $ContractPath
}

if (-not (Test-Path -LiteralPath $ContractPath)) {
  $msg = "Contract not found: $ContractPath"
  if ($FailOnMissingContract) {
    Add-Check "contract.exists" $false $msg
  }
  else {
    Add-Check "contract.exists" $true ($msg + " (skipped)")
  }

  $failed = @($checks | Where-Object { -not $_.pass })
  if ($AsJson) {
    [pscustomobject]@{
      project_root = $ProjectRoot
      contract_path = $ContractPath
      total = $checks.Count
      failed = $failed.Count
      checks = $checks
    } | ConvertTo-Json -Depth 8
  }
  else {
    $checks | Format-Table -AutoSize
    if ($failed.Count -gt 0) {
      Write-Host "project_contract_status=FAILED" -ForegroundColor Red
    }
    else {
      Write-Host "project_contract_status=OK" -ForegroundColor Green
    }
  }
  if ($failed.Count -gt 0) { exit 1 } else { exit 0 }
}

$contractRaw = Get-Content -LiteralPath $ContractPath -Raw -Encoding UTF8
if ($PSVersionTable.PSVersion.Major -ge 6) {
  $contract = $contractRaw | ConvertFrom-Json -Depth 20
}
else {
  $contract = $contractRaw | ConvertFrom-Json
}
Add-Check "contract.parse" $true ("path=" + $ContractPath)

$requiredPaths = @()
if ($null -ne $contract.required_paths) {
  $requiredPaths = @($contract.required_paths)
}
foreach ($rp in $requiredPaths) {
  $pathValue = Resolve-AbsolutePath -BasePath $ProjectRoot -RelativeOrAbsolute ([string]$rp)
  Add-Check ("path:" + $rp) (Test-Path -LiteralPath $pathValue) ("resolved=" + $pathValue)
}

$requiredMarkers = @()
if ($null -ne $contract.required_markers) {
  $requiredMarkers = @($contract.required_markers)
}
foreach ($m in $requiredMarkers) {
  $pathField = [string]$m.path
  $patternField = [string]$m.pattern
  if ([string]::IsNullOrWhiteSpace($pathField) -or [string]::IsNullOrWhiteSpace($patternField)) {
    Add-Check "marker.invalid" $false "required_markers item missing path or pattern"
    continue
  }
  $target = Resolve-AbsolutePath -BasePath $ProjectRoot -RelativeOrAbsolute $pathField
  if (-not (Test-Path -LiteralPath $target)) {
    Add-Check ("marker.file:" + $pathField) $false ("missing file: " + $target)
    continue
  }
  $count = (Select-String -Path $target -Pattern $patternField -ErrorAction SilentlyContinue | Measure-Object).Count
  Add-Check ("marker.match:" + $pathField) ($count -ge 1) ("pattern=" + $patternField + " count=" + $count)
}

$requiredCommands = @()
if ($null -ne $contract.required_commands) {
  $requiredCommands = @($contract.required_commands)
}
foreach ($cmd in $requiredCommands) {
  $cmdText = [string]$cmd
  if ([string]::IsNullOrWhiteSpace($cmdText)) {
    Add-Check "command.invalid" $false "empty command"
    continue
  }
  Push-Location $ProjectRoot
  try {
    & powershell -NoProfile -ExecutionPolicy Bypass -Command $cmdText
    $code = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }
  Add-Check ("command:" + $cmdText) ($code -eq 0) ("exit=" + $code)
}

$runPreCommit = $false
if ($null -ne $contract.run_pre_commit) {
  $runPreCommit = [bool]$contract.run_pre_commit
}
if ($runPreCommit) {
  $cfgPath = Join-Path $ProjectRoot ".pre-commit-config.yaml"
  if (-not (Test-Path -LiteralPath $cfgPath)) {
    Add-Check "pre-commit.config" $false ("missing: " + $cfgPath)
  }
  else {
    $preCommitCmd = Get-Command pre-commit -ErrorAction SilentlyContinue
    if ($null -ne $preCommitCmd) {
      Push-Location $ProjectRoot
      try {
        & $preCommitCmd.Source run --all-files
        $code = $LASTEXITCODE
      }
      finally {
        Pop-Location
      }
      Add-Check "pre-commit.run" ($code -eq 0) ("exit=" + $code)
    }
    else {
      $pyCmd = Get-Command py -ErrorAction SilentlyContinue
      if ($null -eq $pyCmd) {
        Add-Check "pre-commit.tool" $false "pre-commit and py are both unavailable"
      }
      else {
        Push-Location $ProjectRoot
        try {
          & $pyCmd.Source -m pre_commit run --all-files
          $code = $LASTEXITCODE
        }
        finally {
          Pop-Location
        }
        Add-Check "pre-commit.run" ($code -eq 0) ("exit=" + $code + " via py -m pre_commit")
      }
    }
  }
}
else {
  Add-Check "pre-commit.run" $true "run_pre_commit=false (skipped)"
}

$failed = @($checks | Where-Object { -not $_.pass })
if ($AsJson) {
  [pscustomobject]@{
    project_root = $ProjectRoot
    contract_path = $ContractPath
    total = $checks.Count
    failed = $failed.Count
    checks = $checks
  } | ConvertTo-Json -Depth 8
}
else {
  $checks | Format-Table -AutoSize
  if ($failed.Count -gt 0) {
    Write-Host ("project_contract_status=FAILED failed_checks=" + $failed.Count) -ForegroundColor Red
  }
  else {
    Write-Host "project_contract_status=OK" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
'@
  Write-TextFileUtf8NoBom -PathValue $contractCheckPath -Content $contractCheckScript

  $contractTemplate = @'
{
  "version": 1,
  "profile": "standard",
  "run_pre_commit": false,
  "required_paths": [],
  "required_commands": [],
  "required_markers": []
}
'@
  Write-TextFileUtf8NoBom -PathValue $contractTemplatePath -Content $contractTemplate

  $contractInitScript = @'
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$Force,
  [switch]$InstallPreCommitHook
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Gray }
function Write-Ok([string]$Message) { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
  throw "ProjectRoot not found: $ProjectRoot"
}

$codexHome = Join-Path $env:USERPROFILE ".codex"
$governanceDir = Join-Path $codexHome "runtime\\governance"
$templatePath = Join-Path $governanceDir "codex_task_contract.template.json"
$checkScriptPath = Join-Path $governanceDir "codex_project_contract_check.ps1"

if (-not (Test-Path -LiteralPath $templatePath)) {
  throw "Missing template: $templatePath"
}
if (-not (Test-Path -LiteralPath $checkScriptPath)) {
  throw "Missing contract checker: $checkScriptPath"
}

$contractOut = Join-Path $ProjectRoot ".codex-task-contract.json"
if ((-not (Test-Path -LiteralPath $contractOut)) -or $Force) {
  Copy-Item -LiteralPath $templatePath -Destination $contractOut -Force
  Write-Ok "Created contract file: $contractOut"
}
else {
  Write-Info "Contract file already exists: $contractOut"
}

$precommitOut = Join-Path $ProjectRoot ".pre-commit-config.yaml"
$entryPath = $checkScriptPath.Replace("\", "\\")
$precommitTemplate = @"
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-merge-conflict
      - id: check-yaml

  - repo: local
    hooks:
      - id: codex-project-contract
        name: codex-project-contract
        entry: powershell -ExecutionPolicy Bypass -File $entryPath -ProjectRoot .
        language: system
        pass_filenames: false
"@

if ((-not (Test-Path -LiteralPath $precommitOut)) -or $Force) {
  [System.IO.File]::WriteAllText($precommitOut, $precommitTemplate, (New-Object System.Text.UTF8Encoding($false)))
  Write-Ok "Created pre-commit config: $precommitOut"
}
else {
  Write-Info "pre-commit config already exists: $precommitOut"
}

if ($InstallPreCommitHook) {
  $preCommitCmd = Get-Command pre-commit -ErrorAction SilentlyContinue
  if ($null -ne $preCommitCmd) {
    Push-Location $ProjectRoot
    try {
      & $preCommitCmd.Source install
      if ($LASTEXITCODE -eq 0) {
        Write-Ok "Installed pre-commit hook."
      }
      else {
        Write-Warn "pre-commit install exited with code $LASTEXITCODE"
      }
    }
    finally {
      Pop-Location
    }
  }
  else {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($null -eq $pyCmd) {
      Write-Warn "Skipped install: pre-commit and py are unavailable."
    }
    else {
      Push-Location $ProjectRoot
      try {
        & $pyCmd.Source -m pre_commit install
        if ($LASTEXITCODE -eq 0) {
          Write-Ok "Installed pre-commit hook via py -m pre_commit."
        }
        else {
          Write-Warn "py -m pre_commit install exited with code $LASTEXITCODE"
        }
      }
      finally {
        Pop-Location
      }
    }
  }
}
else {
  Write-Info "InstallPreCommitHook not set; hook install skipped."
}
'@
  Write-TextFileUtf8NoBom -PathValue $contractInitPath -Content $contractInitScript

  $crawlerContractTemplate = @'
{
  "version": 1,
  "profile": "crawler-standard",
  "run_pre_commit": false,
  "required_paths": [
    ".codex-task-contract.json",
    ".pre-commit-config.yaml",
    "requirements.txt",
    "crawler.config.yaml"
  ],
  "required_commands": [],
  "required_markers": [
    { "path": "requirements.txt", "pattern": "(?m)^scrapy([<>=!~].*)?$" },
    { "path": "requirements.txt", "pattern": "(?m)^scrapy-playwright([<>=!~].*)?$" },
    { "path": "crawler.config.yaml", "pattern": "(?m)^crawler:\\\\s*$" },
    { "path": "crawler.config.yaml", "pattern": "(?m)^\\\\s*retry:\\\\s*$" },
    { "path": "crawler.config.yaml", "pattern": "(?m)^\\\\s*throttling:\\\\s*$" },
    { "path": "crawler.config.yaml", "pattern": "(?m)^\\\\s*checkpoint:\\\\s*$" }
  ]
}
'@
  Write-TextFileUtf8NoBom -PathValue $crawlerTemplatePath -Content $crawlerContractTemplate

  $crawlerInitScript = @'
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$Force,
  [switch]$InstallPreCommitHook,
  [switch]$SkipEnvExample,
  [switch]$SkipReadme
)

$ErrorActionPreference = "Stop"

function Write-Info([string]$Message) { Write-Host "[INFO] $Message" -ForegroundColor Gray }
function Write-Ok([string]$Message) { Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn([string]$Message) { Write-Host "[WARN] $Message" -ForegroundColor Yellow }

function Write-Utf8NoBom([string]$PathValue, [string]$Content) {
  $dir = Split-Path -Path $PathValue -Parent
  if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  [System.IO.File]::WriteAllText($PathValue, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Ensure-LinesInFile([string]$PathValue, [string[]]$RequiredLines) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    $content = ($RequiredLines -join "`r`n") + "`r`n"
    Write-Utf8NoBom -PathValue $PathValue -Content $content
    return "created"
  }

  $existing = Get-Content -LiteralPath $PathValue -Encoding UTF8
  $added = @()
  foreach ($line in $RequiredLines) {
    if (-not ($existing -contains $line)) {
      $added += $line
    }
  }

  if ($added.Count -gt 0) {
    $updated = @($existing + $added)
    Write-Utf8NoBom -PathValue $PathValue -Content (($updated -join "`r`n") + "`r`n")
    return "updated"
  }
  return "unchanged"
}

function Ensure-MarkedBlock([string]$PathValue, [string]$StartMarker, [string]$EndMarker, [string]$BlockContent) {
  $existing = ""
  if (Test-Path -LiteralPath $PathValue) {
    $existing = Get-Content -LiteralPath $PathValue -Raw -Encoding UTF8
  }
  $pattern = "(?ms)" + [Regex]::Escape($StartMarker) + ".*?" + [Regex]::Escape($EndMarker)
  if ([Regex]::IsMatch($existing, $pattern)) {
    $updated = [Regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $BlockContent }, 1)
  }
  else {
    $updated = if ([string]::IsNullOrWhiteSpace($existing)) { $BlockContent } else { $existing.TrimEnd() + "`r`n`r`n" + $BlockContent }
  }
  Write-Utf8NoBom -PathValue $PathValue -Content $updated
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
  throw "ProjectRoot not found: $ProjectRoot"
}

$codexHome = Join-Path $env:USERPROFILE ".codex"
$governanceDir = Join-Path $codexHome "runtime\\governance"
$baseInitPath = Join-Path $governanceDir "codex_project_contract_init.ps1"
$baseCheckPath = Join-Path $governanceDir "codex_project_contract_check.ps1"
$crawlerTemplatePath = Join-Path $governanceDir "codex_crawler_contract.template.json"

if (-not (Test-Path -LiteralPath $baseInitPath)) { throw "Missing base init script: $baseInitPath" }
if (-not (Test-Path -LiteralPath $baseCheckPath)) { throw "Missing base checker script: $baseCheckPath" }
if (-not (Test-Path -LiteralPath $crawlerTemplatePath)) { throw "Missing crawler template: $crawlerTemplatePath" }

$baseInitArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $baseInitPath,
  "-ProjectRoot", $ProjectRoot
)
if ($Force) { $baseInitArgs += "-Force" }
if ($InstallPreCommitHook) { $baseInitArgs += "-InstallPreCommitHook" }

& powershell @baseInitArgs
if ($LASTEXITCODE -ne 0) {
  throw "Base project-contract init failed, exit code=$LASTEXITCODE"
}

$contractOut = Join-Path $ProjectRoot ".codex-task-contract.json"
if ((-not (Test-Path -LiteralPath $contractOut)) -or $Force) {
  Copy-Item -LiteralPath $crawlerTemplatePath -Destination $contractOut -Force
  Write-Ok "Applied crawler contract template: $contractOut"
}
else {
  Write-Info "Keeping existing contract file: $contractOut"
}

$requirementsPath = Join-Path $ProjectRoot "requirements.txt"
$requirementsStatus = Ensure-LinesInFile -PathValue $requirementsPath -RequiredLines @(
  "scrapy>=2.11",
  "scrapy-playwright>=0.0.43",
  "playwright>=1.40",
  "PyYAML>=6.0"
)
Write-Info "requirements.txt status: $requirementsStatus"

$crawlerConfigPath = Join-Path $ProjectRoot "crawler.config.yaml"
$crawlerConfigContent = @"
crawler:
  mode: standard
  obey_robots_txt: true
  logging:
    level: INFO
    file: logs/crawler.log
  export:
    uri: outputs/items.jsonl
    format: jsonlines
    encoding: utf-8
  checkpoint:
    enabled: true
    jobdir: .jobs/default
  concurrency:
    concurrent_requests: 16
    concurrent_requests_per_domain: 4
  throttling:
    autothrottle_enabled: true
    autothrottle_start_delay: 1.0
    autothrottle_max_delay: 30.0
    autothrottle_target_concurrency: 2.0
    download_delay: 0.25
    randomize_download_delay: true
  retry:
    enabled: true
    retry_times: 3
    retry_http_codes: [408, 429, 500, 502, 503, 504, 522, 524]
  timeout:
    download_timeout_seconds: 30
  playwright:
    enabled: false
    browser_type: chromium
    max_contexts: 4
    max_pages_per_context: 8
    navigation_timeout_ms: 30000
"@
if ((-not (Test-Path -LiteralPath $crawlerConfigPath)) -or $Force) {
  Write-Utf8NoBom -PathValue $crawlerConfigPath -Content $crawlerConfigContent
  Write-Ok "Wrote crawler config: $crawlerConfigPath"
}
else {
  Write-Info "crawler.config.yaml already exists: $crawlerConfigPath"
}

if (-not $SkipEnvExample) {
  $envPath = Join-Path $ProjectRoot ".env.example"
  $envContent = @"
HTTP_PROXY=
HTTPS_PROXY=
NO_PROXY=localhost,127.0.0.1
CRAWLER_USER_AGENT=
CRAWLER_OUTPUT_DIR=outputs
"@
  if ((-not (Test-Path -LiteralPath $envPath)) -or $Force) {
    Write-Utf8NoBom -PathValue $envPath -Content $envContent
    Write-Ok "Wrote env template: $envPath"
  }
  else {
    Write-Info ".env.example already exists: $envPath"
  }
}

if (-not $SkipReadme) {
  $readmePath = Join-Path $ProjectRoot "README.md"
  $runbookBlock = @"
<!-- codex-crawler-runbook:start -->
## Crawler Bootstrap Runbook

Install dependencies:

```powershell
py -m pip install -r requirements.txt
playwright install chromium
```

Initialize contract (if needed):

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_crawler_project_init.ps1" -ProjectRoot .
```

Run checks:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_project_contract_check.ps1" -ProjectRoot .
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_crawler_smoke_test.ps1" -ProjectRoot .
```
<!-- codex-crawler-runbook:end -->
"@
  Ensure-MarkedBlock -PathValue $readmePath -StartMarker "<!-- codex-crawler-runbook:start -->" -EndMarker "<!-- codex-crawler-runbook:end -->" -BlockContent $runbookBlock
  Write-Ok "Ensured README crawler runbook block."
}

& powershell -ExecutionPolicy Bypass -File $baseCheckPath -ProjectRoot $ProjectRoot -FailOnMissingContract
if ($LASTEXITCODE -ne 0) {
  throw "Project contract check failed after crawler init (exit=$LASTEXITCODE)"
}

Write-Ok "Crawler project initialization complete: $ProjectRoot"
'@
  Write-TextFileUtf8NoBom -PathValue $crawlerInitPath -Content $crawlerInitScript

  $crawlerSmokeScript = @'
param(
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$checks = @()

function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
  $script:checks += [pscustomobject]@{
    check = $Name
    pass = $Pass
    detail = $Detail
  }
}

function Require-Pattern([string]$PathValue, [string]$Pattern, [string]$CheckName) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    Add-Check $CheckName $false ("missing file: " + $PathValue)
    return
  }
  $count = (Select-String -Path $PathValue -Pattern $Pattern -ErrorAction SilentlyContinue | Measure-Object).Count
  Add-Check $CheckName ($count -ge 1) ("count=" + $count + " pattern=" + $Pattern)
}

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
if (-not (Test-Path -LiteralPath $ProjectRoot)) {
  throw "ProjectRoot not found: $ProjectRoot"
}

$contractPath = Join-Path $ProjectRoot ".codex-task-contract.json"
$precommitPath = Join-Path $ProjectRoot ".pre-commit-config.yaml"
$requirementsPath = Join-Path $ProjectRoot "requirements.txt"
$crawlerConfigPath = Join-Path $ProjectRoot "crawler.config.yaml"

foreach ($f in @($contractPath, $precommitPath, $requirementsPath, $crawlerConfigPath)) {
  Add-Check ("exists:" + $f) (Test-Path -LiteralPath $f) ("path=" + $f)
}

Require-Pattern -PathValue $requirementsPath -Pattern '(?m)^scrapy([<>=!~].*)?$' -CheckName "requirements:scrapy"
Require-Pattern -PathValue $requirementsPath -Pattern '(?m)^scrapy-playwright([<>=!~].*)?$' -CheckName "requirements:scrapy-playwright"
Require-Pattern -PathValue $precommitPath -Pattern '(?m)id:\s*codex-project-contract' -CheckName "precommit:contract-hook"
Require-Pattern -PathValue $crawlerConfigPath -Pattern '(?m)^crawler:\s*$' -CheckName "config:root"
Require-Pattern -PathValue $crawlerConfigPath -Pattern '(?m)^\s*retry:\s*$' -CheckName "config:retry"
Require-Pattern -PathValue $crawlerConfigPath -Pattern '(?m)^\s*throttling:\s*$' -CheckName "config:throttling"
Require-Pattern -PathValue $crawlerConfigPath -Pattern '(?m)^\s*checkpoint:\s*$' -CheckName "config:checkpoint"

$checkScript = Join-Path (Join-Path $env:USERPROFILE ".codex\runtime\governance") "codex_project_contract_check.ps1"
if (Test-Path -LiteralPath $checkScript) {
  & powershell -ExecutionPolicy Bypass -File $checkScript -ProjectRoot $ProjectRoot -FailOnMissingContract
  Add-Check "project_contract_check.exit" ($LASTEXITCODE -eq 0) ("exit=" + $LASTEXITCODE)
}
else {
  Add-Check "project_contract_check.exists" $false ("missing: " + $checkScript)
}

$failed = @($checks | Where-Object { -not $_.pass })

if ($AsJson) {
  [pscustomobject]@{
    project_root = $ProjectRoot
    total = $checks.Count
    failed = $failed.Count
    checks = $checks
  } | ConvertTo-Json -Depth 8
}
else {
  $checks | Format-Table -AutoSize
  if ($failed.Count -gt 0) {
    Write-Host ("crawler_smoke_status=FAILED failed_checks=" + $failed.Count) -ForegroundColor Red
  }
  else {
    Write-Host "crawler_smoke_status=OK" -ForegroundColor Green
  }
}

if ($failed.Count -gt 0) { exit 1 }
exit 0
'@
  Write-TextFileUtf8NoBom -PathValue $crawlerSmokePath -Content $crawlerSmokeScript

  $readme = @'
# Codex Governance Toolkit

This folder contains executable global safeguards that complement AGENTS.md and ACTIVE.md.

Files:
- `codex_preflight_gate.ps1`: classify a task/command into profile + enforcement decision (`block` / `warn` / `advise`).
- `codex_doctor.ps1`: verify global config health (markers, encoding, key MCP sections, runtime scripts).
- `codex_regression_check.ps1`: verify bootstrap/distribution sync and run doctor.
- `codex_project_contract_check.ps1`: enforce project-level contract (`.codex-task-contract.json`) with required paths/commands/markers.
- `codex_project_contract_init.ps1`: initialize project contract + `.pre-commit-config.yaml` local hook.
- `codex_task_contract.template.json`: default project contract template.
- `codex_crawler_project_init.ps1`: initialize crawler project defaults (`requirements.txt`, `crawler.config.yaml`, contract, pre-commit baseline).
- `codex_crawler_smoke_test.ps1`: run crawler project smoke checks on generated files and contract.
- `codex_crawler_contract.template.json`: crawler-specific contract template.
- `codex_native_governance_hook.ps1`: native Codex hook dispatcher that invokes preflight decisions at runtime.

Native runtime wiring:
- `%USERPROFILE%\.codex\hooks.json` is managed to call `codex_native_governance_hook.ps1`.
- `%USERPROFILE%\.codex\config.toml` must include `[features] codex_hooks = true`.

Quick start:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_doctor.ps1"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_preflight_gate.ps1" -TaskText "add migration for training checkpoint resume" -CommandLine "git reset --hard"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_regression_check.ps1" -BundleRoot "C:\path\to\bundle-root"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_project_contract_init.ps1" -ProjectRoot "C:\path\to\repo" -InstallPreCommitHook
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_project_contract_check.ps1" -ProjectRoot "C:\path\to\repo"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_crawler_project_init.ps1" -ProjectRoot "C:\path\to\repo"
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.codex\runtime\governance\codex_crawler_smoke_test.ps1" -ProjectRoot "C:\path\to\repo"
Get-Content "$env:USERPROFILE\.codex\hooks.json" -Raw
```
'@
  Write-TextFileUtf8NoBom -PathValue $readmePath -Content $readme
}

$RepoRoot = Resolve-FullPath $RepoRoot
$WorkspacePath = Resolve-FullPath $WorkspacePath
$CodexHome = if ([string]::IsNullOrWhiteSpace($CodexHome)) { Join-Path $env:USERPROFILE ".codex" } else { Resolve-FullPath $CodexHome }
if (-not [string]::IsNullOrWhiteSpace($SkillsSourcePath)) {
  $SkillsSourcePath = Resolve-FullPath $SkillsSourcePath
}
if (-not [string]::IsNullOrWhiteSpace($SelfImprovingSourcePath)) {
  $SelfImprovingSourcePath = Resolve-FullPath $SelfImprovingSourcePath
}
if (-not [string]::IsNullOrWhiteSpace($ProactiveSourcePath)) {
  $ProactiveSourcePath = Resolve-FullPath $ProactiveSourcePath
}
if (-not [string]::IsNullOrWhiteSpace($SuperpowersSourcePath)) {
  $SuperpowersSourcePath = Resolve-FullPath $SuperpowersSourcePath
}
if (-not [string]::IsNullOrWhiteSpace($OpenSpaceSourcePath)) {
  $OpenSpaceSourcePath = Resolve-FullPath $OpenSpaceSourcePath
}

if (-not (Test-Path -LiteralPath $RepoRoot)) {
  throw "RepoRoot not found: $RepoRoot"
}
if (-not (Test-Path -LiteralPath $WorkspacePath)) {
  throw "WorkspacePath not found: $WorkspacePath"
}
if (-not [string]::IsNullOrWhiteSpace($SelfImprovingSourcePath) -and -not (Test-Path -LiteralPath $SelfImprovingSourcePath)) {
  throw "SelfImprovingSourcePath not found: $SelfImprovingSourcePath"
}
if (-not [string]::IsNullOrWhiteSpace($ProactiveSourcePath) -and -not (Test-Path -LiteralPath $ProactiveSourcePath)) {
  throw "ProactiveSourcePath not found: $ProactiveSourcePath"
}
if (-not [string]::IsNullOrWhiteSpace($SuperpowersSourcePath) -and -not (Test-Path -LiteralPath $SuperpowersSourcePath)) {
  throw "SuperpowersSourcePath not found: $SuperpowersSourcePath"
}
if (-not [string]::IsNullOrWhiteSpace($SuperpowersSourcePath) -and -not (Test-Path -LiteralPath (Join-Path $SuperpowersSourcePath "skills"))) {
  throw "Superpowers skills folder missing under source path: $SuperpowersSourcePath\skills"
}
if (-not [string]::IsNullOrWhiteSpace($OpenSpaceSourcePath) -and -not (Test-Path -LiteralPath $OpenSpaceSourcePath)) {
  throw "OpenSpaceSourcePath not found: $OpenSpaceSourcePath"
}
if (-not [string]::IsNullOrWhiteSpace($OpenSpaceSourcePath) -and -not (Test-Path -LiteralPath (Join-Path $OpenSpaceSourcePath "openspace\\host_skills\\skill-discovery"))) {
  throw "OpenSpace host skill missing: $OpenSpaceSourcePath\openspace\host_skills\skill-discovery"
}
if (-not [string]::IsNullOrWhiteSpace($OpenSpaceSourcePath) -and -not (Test-Path -LiteralPath (Join-Path $OpenSpaceSourcePath "openspace\\host_skills\\delegate-task"))) {
  throw "OpenSpace host skill missing: $OpenSpaceSourcePath\openspace\host_skills\delegate-task"
}

$installScript = Join-Path $RepoRoot "dist\global-plugins\install_global.ps1"
$sourceScriptsDir = Join-Path $RepoRoot "scripts"
if (-not (Test-Path -LiteralPath $installScript)) {
  throw "Missing installer: $installScript"
}
if (-not (Test-Path -LiteralPath $sourceScriptsDir)) {
  throw "Missing scripts dir: $sourceScriptsDir"
}

$globalPluginsRoot = Join-Path $env:USERPROFILE ".agents\plugins"
$globalPluginsDir = Join-Path $globalPluginsRoot "plugins"
$globalAutomationRoot = Join-Path $env:USERPROFILE ".agents\automation"
$globalAutomationScripts = Join-Path $globalAutomationRoot "scripts"
$globalSkillsDir = Join-Path $env:USERPROFILE ".agents\skills"
$activeRepoFilePath = Join-Path $env:USERPROFILE ".agents\active-repo.txt"
$fetchCommand = "mcp-server-fetch"
$gitCommand = "mcp-server-git"

$codexAgentsPath = Join-Path $CodexHome "AGENTS.md"
$codexMemoriesDir = Join-Path $CodexHome "memories"
$codexRuntimeDir = Join-Path $CodexHome "runtime"
$codexGovernanceDir = Join-Path $codexRuntimeDir "governance"
$codexProactiveDir = Join-Path $codexRuntimeDir "proactive"
$codexSelfImprovingDir = Join-Path $CodexHome "self-improving-for-codex"
$codexSelfImprovingScriptsDir = Join-Path $codexSelfImprovingDir "scripts"
$codexWritebackScriptPath = Join-Path $codexSelfImprovingScriptsDir "memory_writeback.py"
$codexDoctorScriptPath = Join-Path $codexGovernanceDir "codex_doctor.ps1"
$codexPreflightScriptPath = Join-Path $codexGovernanceDir "codex_preflight_gate.ps1"
$codexRegressionScriptPath = Join-Path $codexGovernanceDir "codex_regression_check.ps1"
$codexProjectContractCheckPath = Join-Path $codexGovernanceDir "codex_project_contract_check.ps1"
$codexProjectContractInitPath = Join-Path $codexGovernanceDir "codex_project_contract_init.ps1"
$codexProjectContractTemplatePath = Join-Path $codexGovernanceDir "codex_task_contract.template.json"
$codexCrawlerProjectInitPath = Join-Path $codexGovernanceDir "codex_crawler_project_init.ps1"
$codexCrawlerSmokePath = Join-Path $codexGovernanceDir "codex_crawler_smoke_test.ps1"
$codexCrawlerContractTemplatePath = Join-Path $codexGovernanceDir "codex_crawler_contract.template.json"
$codexNativeHookScriptPath = Join-Path $codexGovernanceDir "codex_native_governance_hook.ps1"
$codexHooksConfigPath = Join-Path $CodexHome "hooks.json"
$codexSuperpowersDir = Join-Path $CodexHome "superpowers"
$codexSuperpowersSkillsDir = Join-Path $codexSuperpowersDir "skills"
$globalSuperpowersSkillLink = Join-Path $globalSkillsDir "superpowers"
$codexOpenSpaceDir = Join-Path $CodexHome "openspace"
$globalOpenSpaceSkillDiscoveryDir = Join-Path $globalSkillsDir "openspace-skill-discovery"
$globalOpenSpaceDelegateTaskDir = Join-Path $globalSkillsDir "openspace-delegate-task"
$codexConfigPath = Join-Path $CodexHome "config.toml"
$codexRulesDir = Join-Path $CodexHome "rules"
$codexDefaultRulesPath = Join-Path $codexRulesDir "default.rules"

$repoParent = Split-Path -Path $RepoRoot -Parent
$bundleRoot = $repoParent
if ((Split-Path -Leaf $repoParent).ToLowerInvariant() -eq "common") {
  $bundleRoot = Split-Path -Path $repoParent -Parent
}
$readFirstFiles = @(
  (Join-Path $bundleRoot "win\TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md"),
  (Join-Path $bundleRoot "win\GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"),
  (Join-Path $bundleRoot "win\bootstrap_fresh_global_full.ps1"),
  (Join-Path $bundleRoot "common\claude-code-main\scripts\bootstrap_fresh_global_full.ps1"),
  (Join-Path $bundleRoot "common\claude-code-main\dist\global-plugins\install_global.ps1"),
  (Join-Path $bundleRoot "external\modules\mod-b\README.md"),
  # legacy layout fallbacks
  (Join-Path $bundleRoot "TEAMMATE_GLOBAL_SETUP_INSTRUCTIONS.md"),
  (Join-Path $bundleRoot "GLOBAL_BOOTSTRAP_TEAM_GUIDE.md"),
  (Join-Path $bundleRoot "bootstrap_fresh_global_full.ps1"),
  (Join-Path $bundleRoot "claude-code-main\scripts\bootstrap_fresh_global_full.ps1"),
  (Join-Path $bundleRoot "claude-code-main\dist\global-plugins\install_global.ps1"),
  (Join-Path $bundleRoot "mod-b\README.md")
)

Write-Step "Read-first checklist (for teammate handoff)"
foreach ($f in $readFirstFiles) {
  $status = if (Test-Path -LiteralPath $f) { "FOUND" } else { "MISSING" }
  Write-Info "[$status] $f"
}

Write-Step "Preflight checks"
foreach ($cmd in @("git", "npx")) {
  if ($null -eq (Get-Command $cmd -ErrorAction SilentlyContinue)) {
    Write-Warn "Command not found: $cmd (some MCP/plugin features may not work)."
  } else {
    Write-Ok "Command found: $cmd"
  }
}
if ($null -eq (Get-Command py -ErrorAction SilentlyContinue)) {
  Write-Warn "Python launcher 'py' not found. Python-based setup will be limited."
} else {
  Write-Ok "Python launcher found: py"
}

if (-not [string]::IsNullOrWhiteSpace($GithubToken)) {
  Write-Step "Setting user-level GITHUB_TOKEN"
  [Environment]::SetEnvironmentVariable("GITHUB_TOKEN", $GithubToken, "User")
  Write-Ok "GITHUB_TOKEN set."
}

Write-Step "Installing global plugins"
$installArgs = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $installScript,
  "-WorkspacePath", $WorkspacePath
)
if ($UseSymlink) {
  $installArgs += "-UseSymlink"
}
& powershell @installArgs
if ($LASTEXITCODE -ne 0) {
  throw "Global plugin install failed, exit code=$LASTEXITCODE"
}
Write-Ok "Global plugins installed."

Write-Step "Copying automation scripts to global runtime"
Ensure-Directory -PathValue $globalAutomationScripts
$scriptFiles = @(
  "automation_daily_smoke.ps1",
  "automation_git_review.ps1",
  "setup_automations.ps1",
  "remove_automations.ps1",
  "set_active_repo.ps1",
  "validate_global_runtime.ps1",
  "run_smoke_prompts.ps1"
)
foreach ($name in $scriptFiles) {
  $src = Join-Path $sourceScriptsDir $name
  if (-not (Test-Path -LiteralPath $src)) {
    throw "Missing required script: $src"
  }
  Copy-Item -LiteralPath $src -Destination (Join-Path $globalAutomationScripts $name) -Force
}
Write-Ok "Automation scripts copied: $globalAutomationScripts"

Write-Step "Syncing integration-runtime MCP workspace paths"
$integrationMcpPath = Join-Path $globalPluginsDir "integration-runtime\.mcp.json"
if (Test-Path -LiteralPath $integrationMcpPath) {
  Write-IntegrationMcpConfig -McpPath $integrationMcpPath -Workspace $WorkspacePath -FetchCommand $fetchCommand -GitCommand $gitCommand
  Write-Ok "MCP workspace paths synced to: $WorkspacePath"
}
else {
  Write-Warn "integration-runtime .mcp.json not found: $integrationMcpPath"
}

Write-Step "Installing python MCP dependencies (fetch/git)"
if ($null -ne (Get-Command py -ErrorAction SilentlyContinue)) {
  & py -m pip install --user --disable-pip-version-check mcp-server-fetch mcp-server-git
  if ($LASTEXITCODE -eq 0) {
    Write-Ok "Python MCP dependencies installed."
    $pyScriptsPath = (& py -c "import sysconfig; print(sysconfig.get_path('scripts', 'nt_user'))" 2>$null | Select-Object -First 1)
    if (-not [string]::IsNullOrWhiteSpace($pyScriptsPath)) {
      $fetchExe = Join-Path $pyScriptsPath "mcp-server-fetch.exe"
      $gitExe = Join-Path $pyScriptsPath "mcp-server-git.exe"
      if (Test-Path -LiteralPath $fetchExe) {
        $fetchCommand = $fetchExe
      }
      if (Test-Path -LiteralPath $gitExe) {
        $gitCommand = $gitExe
      }
      Write-Info "Resolved fetch command: $fetchCommand"
      Write-Info "Resolved git command: $gitCommand"
    }
    if (Test-Path -LiteralPath $integrationMcpPath) {
      Write-IntegrationMcpConfig -McpPath $integrationMcpPath -Workspace $WorkspacePath -FetchCommand $fetchCommand -GitCommand $gitCommand
      Write-Ok "MCP command paths refreshed after python install."
    }
  }
  else {
    Write-Warn "Python MCP dependency install returned exit code $LASTEXITCODE."
  }
}

Write-Step "Ensuring pre-commit runtime for project-contract checks"
$pyCmdForPreCommit = Get-Command py -ErrorAction SilentlyContinue
if ($null -eq $pyCmdForPreCommit) {
  Write-Warn "Skipping pre-commit bootstrap; 'py' launcher not found."
}
else {
  & $pyCmdForPreCommit.Source -m pre_commit --version *> $null
  if ($LASTEXITCODE -eq 0) {
    Write-Ok "pre-commit is available."
  }
  else {
    Write-Info "pre-commit not found; installing via pip --user"
    & $pyCmdForPreCommit.Source -m pip install --user pre-commit
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "pre-commit installed."
    }
    else {
      Write-Warn "Failed to install pre-commit (exit=$LASTEXITCODE). Project-contract hooks may be unavailable."
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($SkillsSourcePath)) {
  Write-Step "Syncing skills to user-level directory"
  if (-not (Test-Path -LiteralPath $SkillsSourcePath)) {
    throw "SkillsSourcePath not found: $SkillsSourcePath"
  }
  Ensure-Directory -PathValue $globalSkillsDir
  Get-ChildItem -Path $SkillsSourcePath -Force | ForEach-Object {
    $dst = Join-Path $globalSkillsDir $_.Name
    Copy-Item -LiteralPath $_.FullName -Destination $dst -Recurse -Force
  }
  Write-Ok "Skills synced: $SkillsSourcePath -> $globalSkillsDir"
}
else {
  Write-Info "SkillsSourcePath not provided; skipping skill sync."
}

if (-not [string]::IsNullOrWhiteSpace($SuperpowersSourcePath)) {
  Write-Step "Syncing superpowers into global Codex home"
  Sync-DirectoryMirror -SourcePath $SuperpowersSourcePath -DestinationPath $codexSuperpowersDir -Label "superpowers"
  if (-not (Test-Path -LiteralPath $codexSuperpowersSkillsDir)) {
    throw "Expected superpowers skills path not found after sync: $codexSuperpowersSkillsDir"
  }
  Ensure-JunctionLink -LinkPath $globalSuperpowersSkillLink -TargetPath $codexSuperpowersSkillsDir
  Write-Ok "Superpowers linked: $globalSuperpowersSkillLink -> $codexSuperpowersSkillsDir"

  if (($null -ne (Get-Command git -ErrorAction SilentlyContinue)) -and (Test-Path -LiteralPath (Join-Path $codexSuperpowersDir ".git"))) {
    & git -C $codexSuperpowersDir remote get-url upstream *> $null
    if ($LASTEXITCODE -ne 0) {
      & git -C $codexSuperpowersDir remote add upstream https://github.com/obra/superpowers.git
      if ($LASTEXITCODE -eq 0) {
        Write-Info "Added official superpowers upstream remote."
      }
      else {
        Write-Warn "Failed to add superpowers upstream remote, exit code=$LASTEXITCODE"
      }
    }
  }
}
else {
  Write-Info "SuperpowersSourcePath not provided; skipping superpowers sync."
}

if (-not $SkipOpenSpaceSync -and -not [string]::IsNullOrWhiteSpace($OpenSpaceSourcePath)) {
  Write-Step "Syncing OpenSpace into global Codex home"
  Sync-DirectoryMirror -SourcePath $OpenSpaceSourcePath -DestinationPath $codexOpenSpaceDir -Label "openspace"

  $openSpaceHostSkillsRoot = Join-Path $codexOpenSpaceDir "openspace\host_skills"
  $openSpaceSkillDiscoverySource = Join-Path $openSpaceHostSkillsRoot "skill-discovery"
  $openSpaceDelegateTaskSource = Join-Path $openSpaceHostSkillsRoot "delegate-task"
  if (-not (Test-Path -LiteralPath $openSpaceSkillDiscoverySource)) {
    throw "OpenSpace host skill source missing after sync: $openSpaceSkillDiscoverySource"
  }
  if (-not (Test-Path -LiteralPath $openSpaceDelegateTaskSource)) {
    throw "OpenSpace host skill source missing after sync: $openSpaceDelegateTaskSource"
  }

  Sync-DirectoryMirror -SourcePath $openSpaceSkillDiscoverySource -DestinationPath $globalOpenSpaceSkillDiscoveryDir -Label "openspace-skill-discovery"
  Sync-DirectoryMirror -SourcePath $openSpaceDelegateTaskSource -DestinationPath $globalOpenSpaceDelegateTaskDir -Label "openspace-delegate-task"
  Write-Ok "OpenSpace host skills synced: $globalOpenSpaceSkillDiscoveryDir + $globalOpenSpaceDelegateTaskDir"
}
elseif ($SkipOpenSpaceSync) {
  Write-Info "SkipOpenSpaceSync enabled; skipping OpenSpace sync."
}
else {
  Write-Info "OpenSpaceSourcePath not provided; skipping OpenSpace sync."
}

$openSpaceMcpWorkspace = ""
$openSpaceMcpHostSkillDirs = ""
if ((Test-Path -LiteralPath $codexOpenSpaceDir) -and (Test-Path -LiteralPath $globalOpenSpaceSkillDiscoveryDir) -and (Test-Path -LiteralPath $globalOpenSpaceDelegateTaskDir)) {
  $openSpaceMcpWorkspace = $codexOpenSpaceDir
  $openSpaceMcpHostSkillDirs = "$globalOpenSpaceSkillDiscoveryDir,$globalOpenSpaceDelegateTaskDir,$globalSkillsDir"
}

if (-not $SkipCodexConfigSync) {
  Write-Step "Syncing ~/.codex/config.toml baseline (features + MCP)"
  $changed = Ensure-CodexConfigMcp -ConfigPath $codexConfigPath -Workspace $WorkspacePath -FetchCmd $fetchCommand -GitCmd $gitCommand -OpenSpaceWorkspace $openSpaceMcpWorkspace -OpenSpaceHostSkillDirs $openSpaceMcpHostSkillDirs
  if ($changed) {
    Write-Ok "Updated Codex config: $codexConfigPath"
  }
  else {
    Write-Info "Codex config already contained baseline entries."
  }
}
else {
  Write-Info "SkipCodexConfigSync enabled; skipping ~/.codex/config.toml sync."
}

if (-not $SkipSafetyPolicySync) {
  Write-Step "Syncing global safety policy (default.rules + AGENTS guard)"
  Ensure-Directory -PathValue $codexRulesDir
  Ensure-File -PathValue $codexDefaultRulesPath -Content ""

  $deleteGuardBlock = @'
# codex-global-delete-guard:start
prefix_rule(
    pattern = ["rm"],
    decision = "prompt",
    justification = "Any deletion command must require confirmation.",
    match = ["rm a.txt", "rm -rf build"],
)

prefix_rule(
    pattern = ["del"],
    decision = "prompt",
    justification = "Any Windows delete command must require confirmation.",
    match = ["del a.txt"],
)

prefix_rule(
    pattern = ["rmdir"],
    decision = "prompt",
    justification = "Directory deletion must require confirmation.",
    match = ["rmdir /s temp"],
)

prefix_rule(
    pattern = ["powershell", "Remove-Item"],
    decision = "prompt",
    justification = "PowerShell deletion must require confirmation.",
    match = ["powershell Remove-Item a.txt"],
)

prefix_rule(
    pattern = ["cmd", "/c", "del"],
    decision = "prompt",
    justification = "cmd deletion must require confirmation.",
    match = ["cmd /c del a.txt"],
)
# codex-global-delete-guard:end
'@
  Ensure-MarkedBlock -PathValue $codexDefaultRulesPath -StartMarker "# codex-global-delete-guard:start" -EndMarker "# codex-global-delete-guard:end" -BlockContent $deleteGuardBlock

  $riskGuardBlock = @'
# codex-global-risk-guard:start
prefix_rule(
    pattern = ["git", "reset", "--hard"],
    decision = "prompt",
    justification = "Destructive git reset must require confirmation.",
    match = ["git reset --hard HEAD~1"],
)

prefix_rule(
    pattern = ["git", "clean", "-fd"],
    decision = "prompt",
    justification = "Destructive git clean must require confirmation.",
    match = ["git clean -fd"],
)

prefix_rule(
    pattern = ["git", "clean", "-fdx"],
    decision = "prompt",
    justification = "Destructive git clean must require confirmation.",
    match = ["git clean -fdx"],
)

prefix_rule(
    pattern = ["format"],
    decision = "forbidden",
    justification = "System format command is forbidden in Codex sessions.",
    match = ["format C:"],
)
# codex-global-risk-guard:end
'@
  Ensure-MarkedBlock -PathValue $codexDefaultRulesPath -StartMarker "# codex-global-risk-guard:start" -EndMarker "# codex-global-risk-guard:end" -BlockContent $riskGuardBlock

  $safetyAgentBlock = @'
<!-- codex-global-safety-guard:start -->
全局安全规则：

- 允许在当前项目目录内创建、编辑、重命名普通项目文件。
- 禁止主动删除任何文件或目录；如确需删除，必须先请求我的确认。
- 禁止删除 C:、D:、E: 上当前项目目录之外的任何文件。
- 不要执行 rm、del、rmdir、Remove-Item，除非我明确同意。
- 如果任务涉及清理、重置、移除、删除、覆盖或批量移动文件，先向我说明影响范围。
<!-- codex-global-safety-guard:end -->
'@
  # Override with clean UTF-8 Chinese content to avoid mojibake in generated AGENTS.md.
  $safetyAgentBlock = @'
<!-- codex-global-safety-guard:start -->
全局安全规则：

- 允许在当前项目目录内创建、编辑、重命名普通项目文件。
- 禁止主动删除任何文件或目录；如确需删除，必须先请求我的确认。
- 禁止删除 C:、D:、E: 上当前项目目录之外的任何文件。
- 不要执行 rm、del、rmdir、Remove-Item，除非我明确同意。
- 如果任务涉及清理、重置、移除、删除、覆盖或批量移动文件，先向我说明影响范围。
<!-- codex-global-safety-guard:end -->
'@
  # Override with stable ASCII content to prevent mojibake on mixed codepages.
  $safetyAgentBlock = @'
<!-- codex-global-safety-guard:start -->
Global safety rules:
- Allow create/edit/rename only within the current project scope.
- Never delete files/directories unless explicitly confirmed by user.
- Never delete files outside the current project scope on C:/D:/E:.
- Do not run rm/del/rmdir/Remove-Item unless user clearly approves.
- If task involves cleanup/reset/remove/overwrite/bulk move, explain impact scope first.
<!-- codex-global-safety-guard:end -->
'@
  Ensure-MarkedBlock -PathValue $codexAgentsPath -StartMarker "<!-- codex-global-safety-guard:start -->" -EndMarker "<!-- codex-global-safety-guard:end -->" -BlockContent $safetyAgentBlock
  Write-Ok "Synced safety policy blocks into ~/.codex/rules/default.rules and ~/.codex/AGENTS.md"
}
else {
  Write-Info "SkipSafetyPolicySync enabled; skipping safety policy sync."
}

if (-not $SkipScheduledTasks) {
  Write-Step "Registering scheduled tasks"
  $globalSetupScript = Join-Path $globalAutomationScripts "setup_automations.ps1"
  & powershell -ExecutionPolicy Bypass -File $globalSetupScript `
    -ScriptRootPath $globalAutomationRoot `
    -WorkspacePath $WorkspacePath `
    -GitRepoPath $WorkspacePath `
    -ActiveRepoFilePath $activeRepoFilePath `
    -DailySmokeTime $DailySmokeTime `
    -GitReviewIntervalHours $GitReviewIntervalHours `
    -GitReviewTimeoutSeconds $GitReviewTimeoutSeconds
  if ($LASTEXITCODE -ne 0) {
    throw "setup_automations failed, exit code=$LASTEXITCODE"
  }
  Write-Ok "Scheduled tasks registered."

  if (-not $EnableGitReview) {
    Write-Step "Disabling Git-Review task (requested)"
    $gitTask = Get-ScheduledTask -TaskName "Codex-Auto-Git-Review" -ErrorAction SilentlyContinue
    if ($null -ne $gitTask) {
      Unregister-ScheduledTask -TaskName "Codex-Auto-Git-Review" -Confirm:$false
      Write-Ok "Removed task: Codex-Auto-Git-Review"
    }
  }
}
else {
  Write-Info "SkipScheduledTasks enabled; scheduled task setup skipped."
}

if (Test-Path -LiteralPath (Join-Path $WorkspacePath ".git")) {
  Write-Step "Setting active repo pointer"
  $setActiveScript = Join-Path $globalAutomationScripts "set_active_repo.ps1"
  & powershell -ExecutionPolicy Bypass -File $setActiveScript -RepoPath $WorkspacePath -ActiveRepoFilePath $activeRepoFilePath
  if ($LASTEXITCODE -ne 0) {
    Write-Warn "set_active_repo returned exit code $LASTEXITCODE"
  }
}
else {
  Write-Info "Workspace is not a git repo; active-repo pointer not set."
}

Write-Step "Initializing global Codex memory/proactive runtime"
Ensure-Directory -PathValue $CodexHome
Ensure-Directory -PathValue $codexMemoriesDir
Ensure-Directory -PathValue $codexGovernanceDir
Ensure-Directory -PathValue $codexProactiveDir
Ensure-Directory -PathValue $codexSelfImprovingScriptsDir

Ensure-File -PathValue (Join-Path $codexMemoriesDir "PROFILE.md") -Content "# PROFILE`r`n"
Ensure-File -PathValue (Join-Path $codexMemoriesDir "ACTIVE.md") -Content "# ACTIVE`r`n"
Ensure-File -PathValue (Join-Path $codexMemoriesDir "LEARNINGS.md") -Content "# LEARNINGS`r`n"
Ensure-File -PathValue (Join-Path $codexMemoriesDir "ERRORS.md") -Content "# ERRORS`r`n"
Ensure-File -PathValue (Join-Path $codexMemoriesDir "FEATURE_REQUESTS.md") -Content "# FEATURE_REQUESTS`r`n"
Ensure-File -PathValue (Join-Path $codexMemoriesDir "AUDIT_LOG.jsonl") -Content ""
Ensure-File -PathValue (Join-Path $codexProactiveDir "context-recovery-latest.md") -Content "# Context Recovery`r`n"
Ensure-File -PathValue (Join-Path $codexProactiveDir "heartbeat-latest.json") -Content "{}"
Ensure-File -PathValue (Join-Path $codexProactiveDir "writeback-queue.md") -Content "# Writeback Queue`r`n"
Ensure-File -PathValue (Join-Path $codexProactiveDir "writeback-queue.jsonl") -Content ""

if (-not [string]::IsNullOrWhiteSpace($SelfImprovingSourcePath)) {
  Write-Step "Syncing self-improving assets into global Codex home"
  $sourceScripts = Join-Path $SelfImprovingSourcePath "scripts"
  if (Test-Path -LiteralPath $sourceScripts) {
    Copy-Item -LiteralPath $sourceScripts -Destination $codexSelfImprovingDir -Recurse -Force
    Write-Ok "Synced scripts: $sourceScripts -> $codexSelfImprovingScriptsDir"
  }
  else {
    Write-Warn "Self-improving scripts folder missing: $sourceScripts"
  }
  foreach ($name in @("README.md", "SKILL.md")) {
    $src = Join-Path $SelfImprovingSourcePath $name
    if (Test-Path -LiteralPath $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $codexSelfImprovingDir $name) -Force
    }
  }
}
else {
  Write-Info "SelfImprovingSourcePath not provided; only base memory scaffold created."
}

if (-not (Test-Path -LiteralPath $codexWritebackScriptPath)) {
  Write-Step "Creating memory_writeback.py"
  Ensure-MemoryWritebackScript -TargetPath $codexWritebackScriptPath
  Write-Ok "Created: $codexWritebackScriptPath"
}
else {
  Write-Info "memory_writeback.py already exists; keeping current file."
}

if (-not $SkipGovernanceToolkitSync) {
  Write-Step "Syncing governance toolkit scripts (preflight/doctor/regression/project-contract/crawler/native-hook)"
  Ensure-GovernanceToolkitScripts -GovernanceDir $codexGovernanceDir
  Write-Ok "Governance toolkit synced: $codexGovernanceDir"
}
else {
  Write-Info "SkipGovernanceToolkitSync enabled; skipping governance toolkit sync."
}

if (-not $SkipNativeHooksSync) {
  if (-not (Test-Path -LiteralPath $codexNativeHookScriptPath)) {
    Write-Warn "Native hook sync skipped; governance hook script missing: $codexNativeHookScriptPath"
  }
  else {
    Write-Step "Syncing native Codex hooks (hooks.json + governance hook command)"
    $hooksChanged = Ensure-CodexNativeHooksConfig -HooksPath $codexHooksConfigPath -HookScriptPath $codexNativeHookScriptPath
    if ($hooksChanged) {
      Write-Ok "Native hooks updated: $codexHooksConfigPath"
    }
    else {
      Write-Info "Native hooks already up to date."
    }
  }
}
else {
  Write-Info "SkipNativeHooksSync enabled; skipping hooks.json sync."
}

if (-not [string]::IsNullOrWhiteSpace($ProactiveSourcePath)) {
  Write-Step "Recording proactive source metadata"
  $notePath = Join-Path $codexProactiveDir "source-note.md"
  $note = @(
    "# Proactive Source"
    ""
    "- Source path: $ProactiveSourcePath"
    "- Imported at: $(Get-Date -Format s)"
    "- Strategy: fuse reusable proactive behavior into one global Codex system."
  ) -join "`r`n"
  Write-TextFileUtf8NoBom -PathValue $notePath -Content $note
  Write-Ok "Wrote proactive source note: $notePath"
}
else {
  Write-Info "ProactiveSourcePath not provided; proactive source note skipped."
}

Write-Step "Patching global AGENTS.md with non-destructive append"
Ensure-File -PathValue $codexAgentsPath -Content ""

$selfImprovingBlock = @"
<!-- codex-global-self-improving:start -->
## Self-Improvement (Global Memory Loop)

Use global memory at `$codexMemoriesDir`.

Before each task:
1. Read `$codexMemoriesDir\PROFILE.md`.
2. Read `$codexMemoriesDir\ACTIVE.md`.
3. Apply those constraints before planning and execution.

Log non-trivial reusable information into memory files:
- `$codexMemoriesDir\LEARNINGS.md`: reusable lessons and best practices.
- `$codexMemoriesDir\ERRORS.md`: durable debugging and environment fixes.
- `$codexMemoriesDir\FEATURE_REQUESTS.md`: recurring missing capabilities.

Promotion rules:
- Promote only stable cross-task rules into `ACTIVE.md`.
- Promote only durable user preferences into `PROFILE.md`.
- Keep uncertain or one-off items in raw logs.
<!-- codex-global-self-improving:end -->
"@

$proactiveBlock = @"
<!-- codex-global-proactive:start -->
## Proactive Execution Strategy (Global Fusion)

- Keep one global system rooted in `$CodexHome`.
- For each task: provide decomposition, first executable step, and risks.
- After each milestone: propose next step (priority ordered, no repetition).
- On interruption recovery: read `$codexProactiveDir\context-recovery-latest.md`.
- On heartbeat checks: read `$codexProactiveDir\heartbeat-latest.json`.
- Report blocker facts first, then provide recovery path.
- Do not deploy a second agent runtime under another home directory.
<!-- codex-global-proactive:end -->
"@

$writebackBlock = @"
<!-- codex-global-writeback:start -->
## Writeback Protocol (Mandatory Final Step)

- Memory writeback is the final required step when a task finishes.
- Success with reusable method/pattern -> append to `$codexMemoriesDir\LEARNINGS.md`.
- Failure from environment/permission/dependency/path/command -> append to `$codexMemoriesDir\ERRORS.md`.
- Missing capability/tooling gap -> append to `$codexMemoriesDir\FEATURE_REQUESTS.md`.
- Use fixed template: date + context + conclusion + next recommendation.
- Append-only; do not overwrite historical entries.
- Skip writeback when entry is highly similar to recent records.
- Preferred writer:
  `python $codexWritebackScriptPath ...`
- If memory files are not writable, queue to:
  `$codexProactiveDir\writeback-queue.jsonl`.
<!-- codex-global-writeback:end -->
"@

$executionPolicyBlock = @"
<!-- codex-global-execution-policy:start -->
Continuous Execution Policy (Global):

- For normal tasks, continue by default until completion or a real blocker; do not ask "whether to continue" after every micro-step.
- Default sequence:
  1) understand context
  2) short plan when needed
  3) implement
  4) run relevant validation
  5) keep fixing if follow-up issues appear
  6) stop only when completed or truly blocked

Decision Rules:
- For low-risk, small-scope, reasonable decisions, decide autonomously.
- Prefer minimal, correct edits aligned with existing style/architecture.
- Do not expand scope with unrelated refactors or features.

Ask user only when:
1. destructive/irreversible action is required
2. blocked by permission/credentials/external access limits
3. multiple materially different options affect cost/risk/architecture
4. critical requirements are missing and likely to cause wrong execution

Validation:
- After code edits, proactively run the most relevant checks (tests/lint/type-check/build/repro/manual).
- If validation fails, continue debugging and fix when feasible before handoff.

Output:
- Keep progress updates concise; do not default to "continue?" prompts.
- At completion, summarize changes, validation, and residual risk.

Done Criteria:
1) target delivered
2) validation done (or clear reason it could not be run)
3) no obvious must-fix leftovers remain
<!-- codex-global-execution-policy:end -->
"@

$mlActiveTriggerBlock = @"
<!-- codex-global-ml-active-trigger:start -->
ML/DL Active Trigger Policy (Global):

- Trigger classification is based on semantic intent + concrete evidence, not keyword-only matching.
- Evidence includes (not limited to): training/eval/inference chain, tensor shape/loss/metric/optimizer/scheduler, checkpoint/reproducibility, preprocessing consistency.
- If user input has typos/noisy wording/mixed-domain phrasing, normalize intent first before deciding.
- If classified as ML/DL: enter diagnosis-first mode.
- If classified as non-ML/DL or evidence is insufficient: fallback to generic workflow.
- If uncertain: state uncertainty briefly and use conservative fallback (minimal validation), do not force full ML pipeline.

Diagnosis-first requires relation mapping before patching:
1) data loading / preprocessing
2) model forward
3) loss
4) evaluation/metrics
5) config source and override path
6) checkpoint/optimizer/scheduler restore chain

- Classify issue first: data / shape / loss / optimization / eval / inference mismatch / reproducibility.
- Before classification+mapping is complete, avoid broad refactors; prefer minimal validation and minimal patch.
- Required checks by relevance: critical tensor-shape assertions, train-vs-eval preprocessing diff, label range/dtype/device checks, one-batch overfit smoke test.
- Always explain side effects: checkpoint/config compatibility, metric definitions, training speed and memory impact.
- Never silently change metric definitions.
- For multi-step, uncertain-root-cause, or repeated-failure tasks, proactively try OpenSpace skill-discovery/delegation; fallback locally if unavailable.
<!-- codex-global-ml-active-trigger:end -->
"@

$activeExecutionPolicyBlock = @"
<!-- codex-active-execution-policy:start -->
## Execution Policy (Global)
- [EXEC-001] For normal tasks, continue execution by default until completion or real blocker; do not ask ""whether to continue"" after each micro-step.
- [EXEC-002] Apply default sequence: context -> short plan (if needed) -> implement -> validate -> keep fixing if needed -> stop only when done/blocked.
- [EXEC-003] Ask user only for destructive/irreversible actions, permission/credential blockers, major architecture tradeoff choices, or missing critical requirements.
- [EXEC-004] After code changes, run relevant validation proactively; if failing, continue debugging and fix before handoff when feasible.
<!-- codex-active-execution-policy:end -->
"@

$reliabilityPolicyBlock = @"
<!-- codex-global-reliability-policy:start -->
AI Coding Reliability Policy (Global):

- Treat failure handling as a first-class requirement, not a post-generation patch.
- Before meaningful code generation for backend/data/automation flows, produce a brief failure map:
  - dependency failure (network, upstream API/schema changes)
  - data anomalies (invalid/partial/duplicate/out-of-order)
  - load/resource pressure (10x traffic/data, memory/CPU/IO limits)
  - concurrency/idempotency hazards
  - external system latency and timeout behavior
- For each relevant failure mode, define:
  - detection signal
  - containment strategy
  - recovery path
  - whether degrade/fallback is required

Failure Contract Requirements:
- External calls must have explicit timeout and bounded retry/backoff policy.
- Writes that can corrupt state must be atomic or recoverable (transaction/temp+rename/checkpoint).
- Re-run safety must be explicit for side-effecting paths (idempotency or duplicate protection).
- Unbounded queues, loops, or accumulation are prohibited without limits/backpressure.
- Silent failure paths are prohibited; emit actionable errors and logs.

Verification Gate (after code changes):
- Run relevant tests/lint/type/build.
- Add or run at least one failure-oriented check when risk exists:
  - timeout/network interruption
  - malformed input/data drift
  - partial-write or retry replay
  - load increase smoke (resource sanity)
- If checks fail, continue fixing unless truly blocked.
<!-- codex-global-reliability-policy:end -->
"@

$activeReliabilityPolicyBlock = @"
<!-- codex-active-reliability-policy:start -->
## Reliability Policy (Global)
- [REL-001] For medium/high-risk coding tasks, map likely failure modes before implementation (dependency/data/load/concurrency/recovery).
- [REL-002] External calls require explicit timeout and bounded retry/backoff; no unbounded waits.
- [REL-003] State-changing writes must be atomic/recoverable and re-run safe (idempotent or duplicate-protected).
- [REL-004] Reject unbounded queues/loops/memory growth without backpressure or hard limits.
- [REL-005] Run at least one failure-oriented validation for risky changes; fix forward on failures when feasible.
<!-- codex-active-reliability-policy:end -->
"@

$governancePolicyBlock = @"
<!-- codex-global-governance-policy:start -->
Policy Enforcement Levels (Global):

- `block`: hard stop for actions with clear safety/reliability risk.
  Typical examples:
  - destructive/irreversible operations without explicit user intent
  - out-of-scope or unauthorized filesystem/system operations
  - unbounded resource patterns (queues/loops/memory growth) in risky code paths
- `warn`: continue allowed, but must surface risk and mitigation plan in output.
  Typical examples:
  - missing failure map on medium/high-risk changes
  - missing side-effect analysis for behavior-changing patches
- `advise`: best-practice recommendation only; does not block execution.

Scenario-Based Execution Profiles:

- `light` (small changes): docs/comments/minor non-critical edits.
  - Keep flow concise; still require basic correctness checks.
- `standard` (regular development): feature/bugfix with normal impact.
  - Use default validation + targeted failure checks when relevant.
- `strict` (high-risk): data migration, stateful writes, external integrations, concurrency/resource-sensitive changes, ML training/inference consistency, deployment/runtime controls.
  - Require explicit failure map, failure contracts, and failure-oriented validation before handoff.

Classification Rule:
- Determine profile from semantic intent + concrete risk evidence, not keyword-only matching.
- If uncertain, classify conservatively upward (`standard` -> `strict`) and explain briefly.
<!-- codex-global-governance-policy:end -->
"@

$activeGovernancePolicyBlock = @"
<!-- codex-active-governance-policy:start -->
## Governance Policy (Global)
- [GOV-001] Apply enforcement levels by risk: `block` (hard stop), `warn` (continue with explicit risk note), `advise` (recommendation only).
- [GOV-002] Choose execution profile per task: `light` / `standard` / `strict`; high-risk domains must use `strict`.
- [GOV-003] Profile and enforcement decisions must be based on semantic intent plus concrete risk evidence, not keyword-only matching.
- [GOV-004] If uncertain, escalate profile one level and state the reason briefly.
<!-- codex-active-governance-policy:end -->
"@

$policyRuntimeBlock = @"
<!-- codex-global-policy-runtime:start -->
Runtime policy enforcement (global):

- Do not rely on AGENTS length alone. Use executable governance scripts under `$codexGovernanceDir`.
- Native runtime trigger is enabled via `$codexHooksConfigPath` + `codex_hooks = true` in `config.toml`.
- Native hook dispatcher: `$codexNativeHookScriptPath`.
- Preflight gate:
  `powershell -ExecutionPolicy Bypass -File $codexPreflightScriptPath -TaskText "<task>" -CommandLine "<candidate command>"`
- Doctor:
  `powershell -ExecutionPolicy Bypass -File $codexDoctorScriptPath -CodexHome $CodexHome`
- Regression:
  `powershell -ExecutionPolicy Bypass -File $codexRegressionScriptPath -CodexHome $CodexHome`
- Project contract init:
  `powershell -ExecutionPolicy Bypass -File $codexProjectContractInitPath -ProjectRoot "<repo>" -InstallPreCommitHook`
- Project contract check:
  `powershell -ExecutionPolicy Bypass -File $codexProjectContractCheckPath -ProjectRoot "<repo>"`
- Crawler project init:
  `powershell -ExecutionPolicy Bypass -File $codexCrawlerProjectInitPath -ProjectRoot "<repo>" -InstallPreCommitHook`
- Crawler smoke test:
  `powershell -ExecutionPolicy Bypass -File $codexCrawlerSmokePath -ProjectRoot "<repo>"`
<!-- codex-global-policy-runtime:end -->
"@

$activePolicyRuntimeBlock = @"
<!-- codex-active-policy-runtime:start -->
## Runtime Governance (Global)
- [RUN-001] Enforce safety/reliability with runtime scripts in `$codexGovernanceDir`, not AGENTS length.
- [RUN-002] Keep native hooks enabled (`codex_hooks = true`) and managed via `$codexHooksConfigPath`.
- [RUN-003] Run doctor after bootstrap or major config changes.
- [RUN-004] Run regression check before team handoff.
- [RUN-005] For repositories with task contracts, run project-contract check before claiming completion.
- [RUN-006] For crawler projects, run crawler init once then crawler smoke before claiming completion.
<!-- codex-active-policy-runtime:end -->
"@

$added1 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-self-improving:start" -BlockContent $selfImprovingBlock
$added2 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-proactive:start" -BlockContent $proactiveBlock
$added3 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-writeback:start" -BlockContent $writebackBlock
$added4 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-execution-policy:start" -BlockContent $executionPolicyBlock
$added5 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-ml-active-trigger:start" -BlockContent $mlActiveTriggerBlock
$added6 = Append-BlockIfMissing -PathValue (Join-Path $codexMemoriesDir "ACTIVE.md") -Marker "codex-active-execution-policy:start" -BlockContent $activeExecutionPolicyBlock
$added7 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-reliability-policy:start" -BlockContent $reliabilityPolicyBlock
$added8 = Append-BlockIfMissing -PathValue (Join-Path $codexMemoriesDir "ACTIVE.md") -Marker "codex-active-reliability-policy:start" -BlockContent $activeReliabilityPolicyBlock
$added9 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-governance-policy:start" -BlockContent $governancePolicyBlock
$added10 = Append-BlockIfMissing -PathValue (Join-Path $codexMemoriesDir "ACTIVE.md") -Marker "codex-active-governance-policy:start" -BlockContent $activeGovernancePolicyBlock
$added11 = Append-BlockIfMissing -PathValue $codexAgentsPath -Marker "codex-global-policy-runtime:start" -BlockContent $policyRuntimeBlock
$added12 = Append-BlockIfMissing -PathValue (Join-Path $codexMemoriesDir "ACTIVE.md") -Marker "codex-active-policy-runtime:start" -BlockContent $activePolicyRuntimeBlock

if ($added1 -or $added2 -or $added3 -or $added4 -or $added5 -or $added6 -or $added7 -or $added8 -or $added9 -or $added10 -or $added11 -or $added12) {
  Write-Ok "AGENTS.md / ACTIVE.md updated with missing global sections."
}
else {
  Write-Info "AGENTS.md / ACTIVE.md already contained all global sections."
}

if ($EnableNightlyMemory) {
  Write-Step "Registering nightly memory maintenance task"
  $runPipelineScript = Join-Path $codexSelfImprovingScriptsDir "run_night_memory_pipeline.py"
  if (-not (Test-Path -LiteralPath $runPipelineScript)) {
    Write-Warn "Nightly task skipped; missing script: $runPipelineScript"
  }
  else {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($null -eq $pyCmd) {
      Write-Warn "Nightly task skipped; 'py' launcher not found."
    }
    else {
      $taskName = "Codex-Auto-Nightly-Memory"
      $nightlyStatusPath = Join-Path $CodexHome "runtime\night-memory-pipeline\last_run.json"
      Ensure-Directory -PathValue (Split-Path -Path $nightlyStatusPath -Parent)

      $userId = "$env:USERDOMAIN\$env:USERNAME"
      $principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
      $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 3)
      $args = "`"$runPipelineScript`" --apply --codex-home `"$CodexHome`" --status-path `"$nightlyStatusPath`""
      $action = New-ScheduledTaskAction -Execute $pyCmd.Source -Argument $args
      $trigger = New-ScheduledTaskTrigger -Daily -At $NightlyMemoryTime
      Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Codex nightly memory pipeline" -Force | Out-Null
      Write-Ok "Registered: $taskName (daily at $NightlyMemoryTime)"
    }
  }
}
else {
  Write-Info "EnableNightlyMemory not set; nightly memory task not created."
}

Write-Step "Final verification"
if (Test-Path -LiteralPath $globalPluginsDir) {
  Write-Host "Global plugins:"
  Get-ChildItem -Path $globalPluginsDir -Directory | Select-Object -ExpandProperty Name | ForEach-Object { " - $_" }
}
if (Test-Path -LiteralPath $codexMemoriesDir) {
  Write-Host "Codex memories:"
  Get-ChildItem -Path $codexMemoriesDir -File | Select-Object -ExpandProperty Name | ForEach-Object { " - $_" }
}
if (Test-Path -LiteralPath $globalSuperpowersSkillLink) {
  $spLink = Get-Item -LiteralPath $globalSuperpowersSkillLink -Force
  $spTarget = if (($spLink.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { (@($spLink.Target) -join ", ") } else { "(not a junction)" }
  Write-Host "Superpowers skill link: $globalSuperpowersSkillLink -> $spTarget"
}
if (Test-Path -LiteralPath $codexSuperpowersDir) {
  Write-Host "Codex superpowers path: $codexSuperpowersDir"
}
if (Test-Path -LiteralPath $codexOpenSpaceDir) {
  Write-Host "Codex OpenSpace path: $codexOpenSpaceDir"
}
if (Test-Path -LiteralPath $globalOpenSpaceSkillDiscoveryDir) {
  Write-Host "OpenSpace skill path: $globalOpenSpaceSkillDiscoveryDir"
}
if (Test-Path -LiteralPath $globalOpenSpaceDelegateTaskDir) {
  Write-Host "OpenSpace skill path: $globalOpenSpaceDelegateTaskDir"
}
if (Test-Path -LiteralPath $codexConfigPath) {
  Write-Host "Codex config path: $codexConfigPath"
  $mcpLines = Select-String -Path $codexConfigPath -Pattern '^\[mcp_servers\.(playwright|filesystem|fetch|git|openaiDeveloperDocs|openspace)\]$' -AllMatches
  if ($null -ne $mcpLines) {
    Write-Host "Codex config MCP sections:"
      $mcpLines | ForEach-Object { " - $($_.Line)" }
  }
  $hookFeatureLines = Select-String -Path $codexConfigPath -Pattern '^\s*codex_hooks\s*=\s*true\s*$' -AllMatches
  if ($null -ne $hookFeatureLines -and $hookFeatureLines.Count -gt 0) {
    Write-Host "Codex hook features:"
    $hookFeatureLines | ForEach-Object { " - $($_.Line)" }
  }
}
if (Test-Path -LiteralPath $codexDefaultRulesPath) {
  Write-Host "Codex rules path: $codexDefaultRulesPath"
  $ruleMarkers = Select-String -Path $codexDefaultRulesPath -Pattern '^# codex-global-delete-guard:start$|^# codex-global-risk-guard:start$'
  if ($null -ne $ruleMarkers) {
    Write-Host "Codex rules markers:"
    $ruleMarkers | ForEach-Object { " - $($_.Line)" }
  }
}
if (Test-Path -LiteralPath $codexAgentsPath) {
  $agentMarkers = Select-String -Path $codexAgentsPath -Pattern '^<!-- codex-global-safety-guard:start -->$'
  if ($null -ne $agentMarkers) {
    Write-Host "AGENTS safety markers:"
    $agentMarkers | ForEach-Object { " - $($_.Line)" }
  }
}
if (Test-Path -LiteralPath $codexGovernanceDir) {
  Write-Host "Codex governance path: $codexGovernanceDir"
}
if (Test-Path -LiteralPath $codexPreflightScriptPath) {
  Write-Host "Governance script: $codexPreflightScriptPath"
}
if (Test-Path -LiteralPath $codexDoctorScriptPath) {
  Write-Host "Governance script: $codexDoctorScriptPath"
}
if (Test-Path -LiteralPath $codexRegressionScriptPath) {
  Write-Host "Governance script: $codexRegressionScriptPath"
}
if (Test-Path -LiteralPath $codexProjectContractCheckPath) {
  Write-Host "Governance script: $codexProjectContractCheckPath"
}
if (Test-Path -LiteralPath $codexProjectContractInitPath) {
  Write-Host "Governance script: $codexProjectContractInitPath"
}
if (Test-Path -LiteralPath $codexProjectContractTemplatePath) {
  Write-Host "Governance template: $codexProjectContractTemplatePath"
}
if (Test-Path -LiteralPath $codexCrawlerProjectInitPath) {
  Write-Host "Governance script: $codexCrawlerProjectInitPath"
}
if (Test-Path -LiteralPath $codexCrawlerSmokePath) {
  Write-Host "Governance script: $codexCrawlerSmokePath"
}
if (Test-Path -LiteralPath $codexCrawlerContractTemplatePath) {
  Write-Host "Governance template: $codexCrawlerContractTemplatePath"
}
if (Test-Path -LiteralPath $codexNativeHookScriptPath) {
  Write-Host "Governance script: $codexNativeHookScriptPath"
}
if (Test-Path -LiteralPath $codexHooksConfigPath) {
  Write-Host "Codex hooks config: $codexHooksConfigPath"
  $hooksMarker = Select-String -Path $codexHooksConfigPath -Pattern 'codex_native_governance_hook\.ps1' -AllMatches
  if ($null -ne $hooksMarker -and $hooksMarker.Count -gt 0) {
    Write-Host "Hooks marker: codex_native_governance_hook.ps1"
  }
}
$preCommitCmd = Get-Command pre-commit -ErrorAction SilentlyContinue
if ($null -ne $preCommitCmd) {
  & $preCommitCmd.Source --version
}
else {
  $pyCmd = Get-Command py -ErrorAction SilentlyContinue
  if ($null -ne $pyCmd) {
    & $pyCmd.Source -m pre_commit --version
  }
}

$codexCmd = Get-Command codex -ErrorAction SilentlyContinue
if ($null -ne $codexCmd) {
  try {
    & $codexCmd.Source --version
    if ($LASTEXITCODE -eq 0) {
      Write-Ok "codex command is runnable."
    }
    else {
      Write-Warn "codex command exists but '--version' exited with code $LASTEXITCODE."
    }
  }
  catch {
    Write-Warn "codex command exists but '--version' failed: $($_.Exception.Message)"
  }
}
else {
  Write-Warn "codex command not found in PATH."
}

$githubTokenUser = [Environment]::GetEnvironmentVariable("GITHUB_TOKEN", "User")
if ([string]::IsNullOrWhiteSpace($githubTokenUser)) {
  Write-Warn "GITHUB_TOKEN is not set at User scope. GitHub MCP auth may be incomplete."
}
else {
  Write-Ok "GITHUB_TOKEN is configured at User scope."
}

Get-ScheduledTask -TaskName "Codex-Auto-Daily-Smoke" -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize
Get-ScheduledTask -TaskName "Codex-Auto-Git-Review" -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize
Get-ScheduledTask -TaskName "Codex-Auto-Nightly-Memory" -ErrorAction SilentlyContinue | Select-Object TaskName, State | Format-Table -AutoSize

if (Test-Path -LiteralPath $activeRepoFilePath) {
  Write-Host "Active repo:"
  Get-Content -LiteralPath $activeRepoFilePath
}

if (Test-Path -LiteralPath $codexDoctorScriptPath) {
  Write-Step "Running governance doctor quick check"
  & powershell -ExecutionPolicy Bypass -File $codexDoctorScriptPath -CodexHome $CodexHome
  if ($LASTEXITCODE -eq 0) {
    Write-Ok "Governance doctor passed."
  }
  else {
    Write-Warn "Governance doctor reported failures (exit=$LASTEXITCODE)."
  }
}

Write-Ok "Full bootstrap completed."
