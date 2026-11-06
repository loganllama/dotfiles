# dotfiles
dotfiles for ona environments

## Layout

* `claude/skills/` — Claude Code skills. `install_claude_skills` symlinks each
  subdirectory into `~/.claude/skills/`, so adding a skill means adding a directory
  here — no install script change. Existing non-symlink skills are left alone.
* `bin/` — scripts symlinked into `~/bin`, which `bash_additions.sh` puts on PATH.
* `bin/ws` + `ws/` — the jj workspace pool (`default` + `ws1`–`ws5`) and its
  leases, which record which Claude session is using which workspace
  (`ws help`). The libraries live in `ws/lib/`, outside `bin/` so they aren't
  put on PATH. `ws/shell.bash` (sourced by `bash_additions.sh` in interactive
  shells) adds the `ws <id>` cd wrapper and completion. `ws init` provisions
  `parking_lot`, `ws1`–`ws5` and `.leases/`; `install.sh` runs it from
  `init_agent_jj_workspaces`. Tests: `bash ws/tests/ws.test.sh`.
* `bin/ws-hook` — a Claude Code `PreToolUse` hook, registered in
  `settings.local.json`, that denies Edit/Write into a workspace the session
  hasn't leased and warns on Bash aimed at one. It does nothing until
  `~/bin/ws-hook` exists.
* `jj/config.toml`, `starship.toml` — symlinked into `~/.config/`.
* `CLAUDE.local.md` → `/workspaces/obsidian/CLAUDE.local.md`,
  `loganllama_pr_style_guide.local.md` → the same name in `/workspaces/obsidian/`
  (the PR/commit voice guide `CLAUDE.local.md` points to), and
  `settings.local.json` → `/workspaces/obsidian/.claude/settings.local.json`,
  all via `safe_obsidian_symlink`.
* dotfiles at the repo root (`.gitconfig`, …) are symlinked into `~` by name.

`install.sh` is not fully idempotent — the package installs near the bottom
(fzf, jj, starship) re-fetch and re-append on every run. The symlink helpers and
`init_agent_jj_workspaces` are safe to re-run; prefer calling an individual helper
over re-running the whole script on a live machine.
