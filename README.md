# dotfiles
dotfiles for ona environments

## Layout

* `claude/skills/` — Claude Code skills. `install_claude_skills` symlinks each
  subdirectory into `~/.claude/skills/`, so adding a skill means adding a directory
  here — no install script change. Existing non-symlink skills are left alone.
* `bin/` — scripts symlinked into `~/bin`, which `bash_additions.sh` puts on PATH.
* `jj/config.toml`, `starship.toml` — symlinked into `~/.config/`.
* `CLAUDE.local.md` → `/workspaces/obsidian/CLAUDE.local.md` and
  `settings.local.json` → `/workspaces/obsidian/.claude/settings.local.json`,
  both via `safe_obsidian_symlink`.
* dotfiles at the repo root (`.gitconfig`, …) are symlinked into `~` by name.

`install.sh` is not fully idempotent — the package installs near the bottom
(fzf, jj, starship) re-fetch and re-append on every run. The symlink helpers and
`init_agent_jj_workspaces` are safe to re-run; prefer calling an individual helper
over re-running the whole script on a live machine.
