# CK42X Ops Key

Safe Flipper Zero / Rubber Ducky launchers for local LLM-assisted shell operations.

This repo contains two related launch styles:

1. **Local Ops Key** — Flipper launches a script the user installed under `%USERPROFILE%\ck42x-ops-key`.
2. **DeepSeek Shell Agent** — Flipper downloads a tagged GitHub PowerShell script, verifies SHA256, then runs a preset prompt chooser.

Neither style embeds API keys. Keys live in user environment variables.

## DeepSeek Shell Agent: how it works

```text
Flipper BadUSB .txt payload
  -> opens Windows Run
  -> downloads scripts/ck42x-deepseek-shell.ps1 from the v0.2.0 GitHub tag
  -> saves it to %TEMP%\ck42x-deepseek-shell.ps1
  -> verifies the expected SHA256 before running it
  -> shows a prompt preset menu
  -> sends selected preset + local context to DeepSeek
  -> prints a reviewed command plan
  -> optional -Execute mode still asks before each allowlisted command
```

Pinned script URL:

```text
https://raw.githubusercontent.com/lordbuffcloud/ck42x-ops-key/v0.2.0/scripts/ck42x-deepseek-shell.ps1
```

Expected SHA256:

```text
9607ce4cb26f2af09cfbffbca952bc9adcd1f8f3b68c27f7587f959c944a6f73
```

## DeepSeek setup

Set your DeepSeek API key locally, outside the repo:

```powershell
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY','REPLACE_WITH_DEEPSEEK_KEY','User')
```

Restart PowerShell so the new environment variable is visible.

Run manually:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\ck42x-ops-key\scripts\ck42x-deepseek-shell.ps1" -ChoosePrompt
```

List presets:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\ck42x-ops-key\scripts\ck42x-deepseek-shell.ps1" -ListPrompts
```

Use a specific preset:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\ck42x-ops-key\scripts\ck42x-deepseek-shell.ps1" -PromptId repo-status
```

## DeepSeek prompt presets

- `repo-status` — branch, dirty state, recent commits, next verification gate.
- `test-triage` — smallest useful test/lint/build checks.
- `explain-error` — explain pasted error/output and suggest safe diagnostics.
- `windows-health` — read-only workstation health snapshot.
- `next-action` — one highest-leverage shell check.

## Flipper Zero payloads

Flipper BadUSB wants `.txt` payloads. Copy one of these to the Flipper SD card under `badusb/`:

- `payloads/flipper/launch-deepseek-shell-agent.txt` — downloads the tagged DeepSeek shell script, verifies SHA256, then opens the review-only preset chooser.
- `payloads/flipper/launch-deepseek-shell-agent-execute-gated.txt` — same, but adds `-Execute`; commands still require allowlist approval and per-command confirmation.
- `payloads/flipper/launch-ck42x-ops-key.txt` — local installed OpenRouter/OpenAI Ops Key launcher.
- `payloads/flipper/launch-ck42x-ops-key-execute-gated.txt` — local installed Ops Key launcher with gated execution.

Legacy `.ducky` copies are also kept in `ducky/` for tooling that expects that extension.

## Local Ops Key install

Repository:

```text
https://github.com/lordbuffcloud/ck42x-ops-key
```

Install from PowerShell:

```powershell
cd $HOME
git clone https://github.com/lordbuffcloud/ck42x-ops-key.git
cd ck42x-ops-key
```

If the user downloaded a zip instead of cloning, extract it so this path exists:

```text
%USERPROFILE%\ck42x-ops-key\scripts\ck42x-ops.ps1
```

OpenRouter is the default provider for the local Ops Key script:

```powershell
[Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','REPLACE_WITH_OPENROUTER_KEY','User')
```

Optional OpenAI provider:

```powershell
[Environment]::SetEnvironmentVariable('OPENAI_API_KEY','REPLACE_WITH_OPENAI_KEY','User')
```

Run local Ops Key manually:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "$HOME\ck42x-ops-key\scripts\ck42x-ops.ps1" -PromptId repo-status
```

## Files

- `scripts/ck42x-deepseek-shell.ps1` — self-contained DeepSeek preset prompt CLI.
- `scripts/ck42x-ops.ps1` — local OpenRouter/OpenAI LLM-assisted ops harness.
- `scripts/install.ps1` — copies project to `%USERPROFILE%\ck42x-ops-key` for the local payload path.
- `prompts/prompts.json` — preset prompt library for `ck42x-ops.ps1`.
- `payloads/flipper/*.txt` — Flipper Zero BadUSB payloads.
- `ducky/*.ducky` — same payload content with Ducky extension.
- `SECURITY.md` — operating boundaries.

## Safety model

Default mode is dry-run/review-only. `-Execute` still requires confirmation for each command and only allows a narrow set of diagnostic/test commands.

Blocked patterns include:

- `Invoke-Expression`, `iex`, encoded commands, Base64 command execution
- remote download piped into execution
- destructive filesystem commands
- registry/security/firewall/Defender changes
- scheduled-task/persistence creation
- user/group/account changes
- remote shell and file transfer commands

The DeepSeek launcher does fetch a tagged GitHub script, but it does **not** pipe remote code into PowerShell. It downloads to a file, verifies the pinned SHA256, then runs that verified file.

## Public release posture

This repo is intended to be safe to open-source: no real keys, no host-specific private notes, no local CK42X infrastructure references, and no unchecked mutable-branch remote execution.
