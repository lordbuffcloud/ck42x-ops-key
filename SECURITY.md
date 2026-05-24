# Security Notes

CK42X Ops Key is intentionally shaped as a local, review-gated launcher. It is not a stealth automation payload.

## Hard rules

- Do not put API keys in Ducky payloads.
- Do not pipe GitHub/raw URLs into PowerShell execution.
- Do not run from a mutable `main` branch during device launch.
- Do not allow model output to execute silently.
- Do not use this on machines you do not own or administer.

## Secret handling

Set API keys outside the repo, preferably as a user-scoped environment variable:

```powershell
[Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','REPLACE_WITH_OPENROUTER_KEY','User')
```

Restart PowerShell after setting it.

## Execution safety

Default mode is dry-run/review-only. `-Execute` still requires confirmation for each command and only allows a narrow list of diagnostic/test commands.

Blocked patterns include:

- `Invoke-Expression`, `iex`, encoded commands, Base64 command execution
- remote download helpers such as `irm`, `iwr`, `curl`, `wget`
- destructive filesystem commands
- registry/security/firewall/Defender changes
- scheduled-task/persistence creation
- user/group/account changes
- remote shell and file transfer commands

## Publishing

If this project is pushed to GitHub, first verify there are no secrets:

```powershell
git grep -n "sk-\|OPENAI_API_KEY=\|OPENROUTER_API_KEY="
```

The sample docs may mention variable names, but should never include real keys.
