# CK42X Ops Key

A safe Flipper Zero / Rubber Ducky launcher for local LLM-assisted shell operations.

This is **not** a remote-code-execution payload. The payload only opens PowerShell and starts a local script that the user installed first.

## How it works

```text
Flipper BadUSB .txt payload
  -> opens Windows Run
  -> starts %USERPROFILE%\ck42x-ops-key\scripts\ck42x-ops.ps1
  -> script reads the user's local API key from an environment variable
  -> script asks OpenRouter/OpenAI for a cautious command plan
  -> default mode prints the plan only
  -> optional -Execute mode asks before each allowlisted command
```

The important part: **the Flipper payload does not contain an API key and does not download or run a GitHub script.** Users install the repo locally, set their own API key, then the payload launches that local install.

## Public GitHub install

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

## Set API key

OpenRouter is the default provider. Set the key locally, outside the repo:

```powershell
[Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','REPLACE_WITH_OPENROUTER_KEY','User')
```

Restart PowerShell so the new environment variable is visible.

Optional OpenAI provider:

```powershell
[Environment]::SetEnvironmentVariable('OPENAI_API_KEY','REPLACE_WITH_OPENAI_KEY','User')
```

## Run manually first

Review-only mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "$HOME\ck42x-ops-key\scripts\ck42x-ops.ps1" -PromptId repo-status
```

Gated execution mode:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "$HOME\ck42x-ops-key\scripts\ck42x-ops.ps1" -PromptId repo-status -Execute
```

List prompt presets:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "$HOME\ck42x-ops-key\scripts\ck42x-ops.ps1" -ListPrompts
```

Use a custom prompt:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "$HOME\ck42x-ops-key\scripts\ck42x-ops.ps1" -PromptId test-triage -PromptText "Focus on the smallest checks for this Node project."
```

## Flipper Zero payloads

Flipper BadUSB wants `.txt` payloads. Copy one of these to the Flipper SD card under `badusb/`:

- `payloads/flipper/launch-ck42x-ops-key.txt` — review-only launcher.
- `payloads/flipper/launch-ck42x-ops-key-execute-gated.txt` — confirm-before-each-command mode.

Legacy `.ducky` copies are also kept in `ducky/` for tooling that expects that extension.

## Files

- `scripts/ck42x-ops.ps1` — local LLM-assisted ops harness.
- `scripts/install.ps1` — copies project to `%USERPROFILE%\ck42x-ops-key` for the payload path.
- `prompts/prompts.json` — preset prompt library.
- `payloads/flipper/*.txt` — Flipper Zero BadUSB payloads.
- `ducky/*.ducky` — same payload content with Ducky extension.
- `SECURITY.md` — operating boundaries.

## Prompt presets

- `repo-status` — branch/dirty state/recent commit checks.
- `test-triage` — safest test/lint/build commands.
- `windows-health` — read-only workstation health snapshot.
- `dev-lab-brief` — concise dev-lab status brief from the current directory.

## Safety model

Default mode is dry-run/review-only. `-Execute` still requires confirmation for each command and only allows a narrow set of diagnostic/test commands.

Blocked patterns include:

- `Invoke-Expression`, `iex`, encoded commands, Base64 command execution
- remote download helpers such as `irm`, `iwr`, `curl`, `wget`
- destructive filesystem commands
- registry/security/firewall/Defender changes
- scheduled-task/persistence creation
- user/group/account changes
- remote shell and file transfer commands

## Public release posture

This repo is intended to be safe to open-source: no real keys, no host-specific private notes, no local CK42X infrastructure references, and no remote pipe-to-exec bootstrap.
