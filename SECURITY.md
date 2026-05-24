# Security Notes

CK42X Ops Key is intentionally shaped as a review-gated launcher set. It is not a stealth automation payload.

## Hard rules

- Do not put API keys in Ducky/Flipper payloads.
- Do not pipe GitHub/raw URLs into PowerShell execution.
- Do not run from a mutable `main` branch during device launch.
- If a payload fetches a script, pin it to a version tag and verify SHA256 before running.
- Do not allow model output to execute silently.
- Do not use this on machines you do not own or administer.

## Secret handling

Set API keys outside the repo, preferably as user-scoped environment variables:

```powershell
[Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY','REPLACE_WITH_DEEPSEEK_KEY','User')
[Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','REPLACE_WITH_OPENROUTER_KEY','User')
```

Restart PowerShell after setting them.

The first-run DeepSeek key payload is allowed because it does **not** store a real key in GitHub source. It prompts locally with `Read-Host`, writes the pasted key to the Windows user environment, and passes it only to the current local PowerShell process.

If you intentionally generate a private preloaded-key payload with `scripts/new-private-deepseek-payload.ps1`, the generated file contains the DeepSeek key in plaintext. It is written under `private-payloads/`, which is gitignored. Do not commit, upload, screenshot, or share it. If the Flipper or SD card is lost or shared, revoke/rotate the key immediately.

## Remote script boundary

The DeepSeek Shell Agent payload downloads this tagged file:

```text
https://raw.githubusercontent.com/lordbuffcloud/ck42x-ops-key/v0.2.0/scripts/ck42x-deepseek-shell.ps1
```

It saves the file to `%TEMP%`, verifies this SHA256, then runs it:

```text
9607ce4cb26f2af09cfbffbca952bc9adcd1f8f3b68c27f7587f959c944a6f73
```

That is intentionally different from unsafe `irm | iex` or `iwr | iex` patterns. Updating the script requires a new tag, a new checksum, and a new payload.

## Execution safety

Default mode is dry-run/review-only. `-Execute` still requires confirmation for each command and only allows a narrow list of diagnostic/test commands.

Blocked patterns include:

- `Invoke-Expression`, `iex`, encoded commands, Base64 command execution
- remote download piped into execution
- destructive filesystem commands
- registry/security/firewall/Defender changes
- scheduled-task/persistence creation
- user/group/account changes
- remote shell and file transfer commands

## Publishing

Before pushing or releasing, verify there are no secrets:

```powershell
git grep -n "sk-\|OPENAI_API_KEY=\|OPENROUTER_API_KEY=\|DEEPSEEK_API_KEY="
```

The sample docs may mention variable names, but should never include real keys.
