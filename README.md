# CK42X Ops Key

A safe local launcher for LLM-assisted shell operations.

The design is deliberately bounded:

- Flipper/Rubber Ducky only launches a **local** PowerShell script.
- No API keys are embedded in payloads or source files.
- No `irm | iex`, no mutable remote script execution, no silent shell autonomy.
- Default mode is dry-run/review-only.
- `-Execute` mode still requires human confirmation for each allowlisted command.

## Files

- `scripts/ck42x-ops.ps1` — local LLM-assisted ops harness.
- `scripts/install.ps1` — copies project to `%USERPROFILE%\ck42x-ops-key` for the Ducky payload path.
- `prompts/prompts.json` — preset prompt library.
- `ducky/launch-ck42x-ops-key.ducky` — review-only launcher.
- `ducky/launch-ck42x-ops-key-execute-gated.ducky` — gated execution launcher.
- `SECURITY.md` — operating boundaries.

## Setup

From PowerShell:

```powershell
cd $HOME\ck42x-ops-key
[Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','REPLACE_WITH_OPENROUTER_KEY','User')
```

Restart PowerShell so the new environment variable is visible.

Optional OpenAI provider:

```powershell
[Environment]::SetEnvironmentVariable('OPENAI_API_KEY','REPLACE_WITH_OPENAI_KEY','User')
```

## Run manually

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

## Ducky use

Load one of these onto the Ducky/Flipper BadUSB app:

- `ducky/launch-ck42x-ops-key.ducky` — opens review-only mode.
- `ducky/launch-ck42x-ops-key-execute-gated.ducky` — opens confirm-before-each-command mode.

The payload assumes this project exists at:

```text
%USERPROFILE%\ck42x-ops-key
```

## Prompt presets

- `repo-status` — branch/dirty state/recent commit checks.
- `test-triage` — safest test/lint/build commands.
- `windows-health` — read-only workstation health snapshot.
- `dev-lab-brief` — concise dev-lab status brief from the current directory.

## Public release posture

This repo is safe to open-source only if it contains no real keys, host-specific private notes, or personal paths beyond generic Windows examples. Run the checks in `SECURITY.md` before pushing.
