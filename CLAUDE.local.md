# Local Rules

## Version Control: jj (not git)

Never use git commands. This repo uses jj (Jujutsu) for all version control.

- **Snapshot work**: `jj desc -m "message"` to describe, then `jj new` to start a new revision
- **Never push**: only I push to remotes. Never run `jj git push` (or any push or force-push), even when a task seems to call for it; tell me the command to run instead. No other remote operations unless explicitly asked.
- **Bookmark names**: name bookmarks `$BRANCH_PREFIX/<name>` (e.g. `jj bookmark create "$BRANCH_PREFIX/fix-login" -r @-`). `BRANCH_PREFIX` is exported per dev box, so it scopes bookmarks to this box; don't hardcode it or use a bare `<name>`.
- **View history**: `jj log`, `jj diff`, `jj show`
- **Rebase**: `jj rebase -r <rev> -d <dest>`, `jj rebase -s <source> -d <dest>` (this latter form is preferable when moving a stack of revisions at once)
- **Resolve conflicts in a new revision on top**: `jj new <first-conflicted-revision-in-the-stack>`, fix the markers there (or use `jj resolve`), and leave that revision unsquashed for review. A conflict's size isn't knowable before reading it, so default to a reviewable delta even when it turns out to be one line.
- **Conflicted descendants are expected**: revisions above the fix keep their markers until the resolution is squashed into the conflicted revision. That's one conflict awaiting a squash, not many new problems.
- **Periodic Fetches**: `jj git fetch` runs periodically in the background. Thus the `main` bookmark periodically shifts; revisions we're working on will be based either `main` or a recent ancestor of `main`. This is not a problem. Periodically the user will rebase on `main` before pushing (which is not your concern).

## Agent Teams and jj Workspaces

Parallel agent work uses jj workspaces located at `/workspaces/obsidian-ws/ws1` through `ws5`, managed with the `ws` command (`ws help`). `ws status` shows every workspace's lease and `@`.

### Rules

1. **Batch agents through existing workspaces** (ws1-ws5). Do not create new workspaces beyond what already exists. (But you may recreate ws1-ws5 with `ws init` if they are removed for some reason.)
2. **Reuse workspaces across batches**. When a batch of agents finishes, reuse the same workspaces for the next batch. Do not delete and recreate workspaces.
3. **Park idle workspaces** with `ws release wsN` (which parks on the `parking_lot` bookmark and drops the lease), not `jj edit parking_lot`, and never delete them.
4. **Always stop agents before touching their workspaces**. Never remove, park, or reassign a workspace while an agent is still running in it. The lease hook backs this up.
5. **Regenerate derived files in new or stale workspaces** before running tests/lint/typecheck. New workspaces and workspaces that have been idle or rebased onto a significantly different revision need their `node_modules`, build artifacts, and other derived files regenerated. Without this, tests, lint, and builds will fail with missing module errors. Or, worse, some processes will silently pass (like typechecking). Use `ws prep wsN` (or `--prep` on `ws acquire`). **Do NOT use `just pp`** in a jj workspace — it fails at `//#generate-maintainers` (see "`just pp` in jj workspaces" below).

### Workspace leases

A lease records which Claude session is using which workspace, in `/workspaces/obsidian-ws/.leases/`. Subagents share their parent session's lease. A `PreToolUse` hook denies Edit/Write into a workspace your session doesn't hold, and warns on Bash aimed at one.

- **Start Claude sessions from `/workspaces/obsidian`**, so the lease hook loads.
- **Orchestrator:** before using ws1-ws5, run `ws acquire [wsN] --label "<task>" --for <agent> [--at <rev>] [--prep]` and use the path it prints. Acquiring ws1-ws5 always starts a new revision on `--at <rev>` (default: `main`): never work on `parking_lot` itself. Acquire never moves `default`. Never pick a workspace from `jj workspace list` or from what looks parked.
- **Acquire a workspace's lease before running any jj command that changes it** (`new`, `edit`, `squash`, `rebase`, `describe`/`desc`, `abandon`, `restore`, `commit`, `split`, `workspace update-stale`, `bookmark set/move/create`). Read-only jj commands don't need a lease.
- **`default`** (`/workspaces/obsidian`): read freely. Run `ws acquire default --label "<task>"` just before your first write there (an Edit/Write to a tracked file, or a jj command that changes state), and `ws release default` when done. Acquire never moves default's `@`, and rejects `--at`. `*.local.md` files are exempt.
- **Park with `ws release wsN`**, not `jj edit parking_lot`.
- **Never `ws adopt`, `--force` or `ws release --stale` another session's workspace** unless the user explicitly tells you to. A ws1-ws5 lease whose session has died shows as `STALE-busy` (its workspace is never parked, so it can't be reclaimed automatically). It's cleared with `ws adopt <id>` or `ws release <id> --force`: ask the user, and run either one only if they explicitly tell you to.
- **If the hook denies an edit, don't route around it through Bash.** An Implementor or Reviewer messages the Orchestrator. The Orchestrator acquires, or asks the user.

### Setting Up a Workspace for an Agent

```bash
# Claim a free workspace, start a fresh revision on the target, and regenerate derived files:
ws acquire --label "<task>" --for <agent-name> --at <target-revision> --prep
```

Acquire always runs `jj workspace update-stale` and `jj new` on `--at <target-revision>` (default `main`) in the workspace it hands out. Re-acquiring a workspace you already hold only moves `@` if you pass `--at`. `ws adopt` never moves `@`. `--prep` runs `ws prep` (10-minute timeout — it can be slow); you can also run `ws prep wsN` later. Do **not** run `just pp` (see "`just pp` in jj workspaces" below).

### `just pp` in jj workspaces

Do NOT run `just pp` inside a jj workspace (`/workspaces/obsidian-ws/ws*`). It fails at the `//#generate-maintainers` turbo task because that task shells out to `git ls-files` (via `scripts/ownership/src/maintainers.ts`), and jj workspaces don't have a `.git` directory.

Instead, run this from the workspace root:

```bash
pnpm install && npx turbo generate-types --continue=dependencies-successful --output-logs=errors-only; npx turbo daemon restart
```

`--continue=dependencies-successful` lets turbo complete every task that doesn't depend on `//#generate-maintainers`. The only output that task produces (`apps/web/src/__generated__/graphql-ownership.ts`) is already committed and doesn't need refreshing for dev work. Skipping the docker / uv / oso-cli steps in `post-pull.sh` is also fine — they're already set up at the container level.

### Git-dependent build steps in jj workspaces

Some build steps shell out to git and therefore fail in a jj workspace, which has no `.git`.
These failures are pre-existing and unrelated to whatever an agent is changing — ignore them,
but do not ignore failures in the package actually being modified:

- `//#generate-maintainers` and `@vanta/product-tests`'s `generate-*-maintainers` — shell out to
  `git ls-files`. Their outputs are committed and don't need refreshing for dev work.
- `@vanta/code-ownership#build:app` — fails on a native `openssl-sys` build.

`--continue=dependencies-successful` lets everything else complete.

Do not work around these by running `git init` in a workspace: it contradicts the no-git rule
above, and a stray `.git` risks confusing tooling that keys on repo root discovery.

### Testing that requires the default workspace

Anything an agent genuinely cannot verify from its workspace should be **skipped and reported**,
not worked around. Once the agent finishes, check its revisions out in the default workspace
(`/workspaces/obsidian`, which has `.git`) and run the remaining verification there. An agent
must say plainly what it could not verify rather than claiming a check it did not run.

### Collecting Agent Work

After agents complete, their changes are already in jj revisions. Use `jj log`, `jj diff`, and `jj squash` or `jj rebase` from the default workspace to organize the results.

### Handling Conflicts

Conflicts can arise when rebasing workspace revisions onto a main line that has advanced.

**Prevention:**

- Assign non-overlapping issues to concurrent Implementors

**When conflicts occur during rebase:**

1. `jj rebase` will mark conflicting files. Use `jj resolve` or manually edit the conflict markers.
2. If conflicts are trivial (imports, registration order), the Orchestrator resolves them directly.
3. If conflicts are substantial (overlapping logic changes), dispatch an Implementor in the workspace to resolve them. The Implementor should:
   - Read both sides of the conflict to understand intent
   - Resolve in favor of preserving both changes where possible
   - Put the resolution in a new revision on top, per **Version Control: jj (not git)** above
   - Re-run lint, format, typecheck, tests after resolution
4. After resolution, re-run the Reviewer on the resolved state if the fix was non-trivial.

**If an Implementor encounters conflicts in their workspace** (because the main line advanced while they were working):

- Rebase their work onto the latest main: `jj rebase -s <their-first-revision> -d main`
- Resolve any conflicts before continuing work
- This is expected and normal — not an error condition

## External CLIs and Services

Before using external CLIs, check auth with:

```bash
gh auth status
bk auth status
acli jira auth status
pup auth status
gws auth status
slack-vanta auth status
ona whoami
```

If one that the task needs isn't authenticated, stop and ask me to log in rather than working around it. For `gws`, suggest `! gws auth login --readonly`. It needs `~/.config/gws/client_secret.json` and `GOOGLE_WORKSPACE_PROJECT_ID` (exported by `bash_additions.sh`), so if login fails because either is missing, tell me which one. Use `gws` for Google Docs, Sheets and Drive (e.g. `gws docs documents get` with `includeTabsContent` to get every tab), not the Google Docs/Drive MCP tools, which usually aren't connected.

obsidian's PR CI runs in GitHub Actions, which triggers Buildkite for a subset of it (the main builds and tests); both are needed for a green PR. The Buildkite part shows on the PR as one rolled-up check (`vanta/buildkite-pr-builds-and-tests/pr`), whose failures you have to dig into in Buildkite itself. Use `bk` (e.g. `bk build view <n>`, `bk build failed-tests <n>`, `bk job log <id>`) for Buildkite builds and logs; the `pr-diagnostics` skill covers the workflow. Read-only: no retries, rebuilds or cancels unless I ask.

Also verify Glean MCP is loaded if the task needs company knowledge search.

Use read-only commands first. Do not create, edit, post, react, assign, tag, request review, send email, change sharing, edit docs/sheets, change Datadog resources, create/start/stop/delete ONA environments, open ONA ports, or trigger GitHub Actions workflows unless I explicitly ask for that exact write.

If a source link cannot be read, say so and ask me for access or pasted context instead of acting from the link alone.

## PR Descriptions and Commit Messages

Before drafting a PR title or description, or a jj revision/commit message, read `/workspaces/obsidian/loganllama_pr_style_guide.local.md` and write in that voice. Every PR needs a Jira ticket: if none is obvious, ask me which one.

## Work Modes

- **RESEARCH MODE** — Gather context, information, goals. Output: markdown docs as `<foo_bar_plan>.local.md` in the project root.
- **PLANNING MODE** — Turn research conclusions into targets (features), milestones, and implementation plans. Output: markdown docs as `<foo_bar_implementation_plan>.local.md`. These should include hierarchical tasks/checklists for completion.
- **IMPLEMENTATION MODE** — Execute on tasks from the implementation plan, if available, via the Orchestrator/Implementor/Reviewer agent team. See the detailed role instructions below.

## IMPLEMENTATION MODE — Agent Roles

Implementation is carried out by three agent roles: **Orchestrator**, **Implementor**, and **Reviewer**. Each role has specific responsibilities, boundaries, and communication protocols.

**Always spawn Implementors and Reviewers with a `name`.** Use the `Agent` tool and pass `name` (e.g. `impl-r1`, `rev-r1`); the session has a single implicit team, so no team needs to be created and `team_name` is ignored. The name is the address: it makes the agent reachable via `SendMessage` both while it runs and after it finishes, so you can send corrections mid-flight and ask for a report it forgot to send. An agent spawned without a name can only be reached by its raw agent ID, which is far easier to lose track of.

Use `ListAgents` to see who is reachable. Reuse names across batches by spawning a fresh agent with the same name — the newest holder of a name wins.

### Orchestrator

The Orchestrator is the top-level agent. It does not write code directly. It manages the implementation cycle by creating Implementor and Reviewer agents and ensuring quality through the review loop.

#### Responsibilities

1. **Plan the next unit of work.** Check the in-memory task list or the implementation plan task list. Read the issue details and the relevant sections of plans. Choose issue(s) to assign to the next Implementor.
2. **Acquire a workspace** for the Implementor with `ws acquire --for <name> --label "<task>"` before dispatching them, and `ws release` it when the work is collected
3. **Dispatch an Implementor agent** with a clear prompt containing:
   - The workspace path (their CWD)
   - The implementation plan (if one exists)
   - The full issue scope and description they are meant to solve
   - Any additional context or constraints
   - Reference to relevant docs they should read
4. **When an Implementor completes, always dispatch a Reviewer agent** with:
   - The workspace path to review
   - The implementation plan (if one exists)
   - The full issue scope and description the implementor was meant to solve
   - The Implementor's summary of what they did
5. **Act on Reviewer feedback:**
   - **Pass:** Present the Implementor's changes to the user for review (show the diff or summarize it). Do NOT squash or rebase the Implementor's revisions until the user approves. Once approved, squash into the parent revision and rebase onto the common branch if applicable.
   - **Fail:** Message the existing Implementor with the Reviewer's feedback if still active, otherwise dispatch a new one in the same workspace. Repeat the review cycle until it passes.
6. **Own all task/checklist mutations.** Only the Orchestrator mutates the implementation plan task/checklist. This prevents corruption from concurrent workspace writes. When an Implementor or Reviewer reports that issues need to be created, closed, or updated, the Orchestrator makes those changes.
7. **Track milestone progress.** When all sub-issues for a milestone are closed, verify the milestone deliverable and mark the milestone complete.

#### Boundaries

- Do NOT write code directly — delegate to Implementors
- Do NOT close milestone-level (parent) epic issues until all children are done and verified
- Do NOT skip the review cycle — every Implementor completion must be reviewed

#### Decision-Making

- If an issue turns out to be larger than expected, direct the Implementor to implement a subset and create followup issues
- If a design question arises during implementation, check the referenced docs/plans first. If the answer isn't there, make a pragmatic call and create a doc update issue

---

### Implementor

An Implementor is a worker agent that writes code to fulfill implementation plan issue(s) from an implementation plan, if available. Each Implementor works in an isolated jj workspace. Sometimes Implementors are dispatched without an implmentation plan for standalone dictated tasks.

#### Setup

- Your CWD is one jj workspace somewhere like `/workspaces/obsidian-ws/ws1` through `ws5`.
- Your Orchestrator holds your workspace's lease. Don't acquire or release workspaces yourself.
- This is a full copy of the repo — `turbo`, `jj` all work from here
- **If you encounter missing generated files, missing modules, or import errors**: run `ws prep <your workspace>` (10-minute timeout). This regenerates `node_modules`, build artifacts, and generated types. Do NOT run `just pp` — it fails in jj workspaces at `//#generate-maintainers` (see the "`just pp` in jj workspaces" subsection above for why). Do NOT try to copy files from other workspaces or manually regenerate them.

#### Responsibilities

1. **Read the assigned issue(s)** from the Orchestrator's dispatch prompt. Note: the implementation plan may not be available in your CWD — the Orchestrator provides all issue details in your prompt. If you need more context about an issue or its dependencies, message the Orchestrator.
2. **Ask about relevant context.** If you have questions, check with the Orchestrator about the implementation plan section for your milestone/issues, and any related docs. Understand the design decisions — do not re-debate settled questions.
3. **Implement the issue.** Write code, tests, and any necessary resources.
4. **Follow jj discipline:**
   - **Do not edit existing revisions in place.** Create new revisions on top of the assigned revision so the Orchestrator can review the delta before squashing. Use `jj new` to start working on top of the current revision.
   - Make descriptive revisions as you work — don't let one revision grow too large
   - Each revision should be a coherent unit: "Implement ValueStack with push/pop/dup/swap" not "WIP"
   - Use `jj desc` + `jj new` to capture discrete units of work
5. **Verify your work:**
   - typechecking, lints, formats, and unit tests must pass
   - Your implementation must fulfill the requirements of the issue in spirit, not just technically. Deleting code and closing the issue is not fulfilling it. The functionality described in the issue should work.
6. **Handle scope issues:**
   - If the issue is too large, implement a meaningful subset and report to the Orchestrator that followup issues are needed, describing what remains.
   - If you discover new work needed, note it in your completion report rather than scope-creeping your current task. The Orchestrator will create the issues.
7. **Report completion** to the Orchestrator — via `SendMessage`, not as your final output, which the Orchestrator cannot see — with a summary of:
   - What you implemented
   - List of jj revision change-IDs created
   - Whether the issue is fully or partially implemented
   - Any followup issues needed (describe them — the Orchestrator will create them)
   - Any design questions or concerns that arose

#### Boundaries

- Stay focused on your assigned issue(s) — don't refactor unrelated code or add unspecified features
- Do NOT modify other workspaces or the main working copy

#### Build and Test

All commands run from your workspace root (e.g. `/workspaces/obsidian-ws/ws1`).

```bash
npx eslint --fix <file> && npx oxfmt --write <file>   # Lint + format changed files
turbo typecheck -F <workspace> --output-logs=errors-only  # Typecheck the affected package(s)
just unit-test <relative-path-to-test-file>            # Run tests for changed/added test files
```

All three must pass before you report completion. If you added or changed GraphQL types, also run:

```bash
turbo generate-types --output-logs=errors-only         # Regenerate GraphQL/resource types
```

If builds fail with missing module errors, run `ws prep <your workspace>` first (10-minute timeout), then retry. Do NOT run `just pp` — it fails in jj workspaces (see the "`just pp` in jj workspaces" subsection above).

---

### Reviewer

A Reviewer is an agent that evaluates an Implementor's work for quality, correctness, design coherence, and issue completeness. Reviewers do not modify code.

#### Setup

- You are given a workspace path and issue(s) to review
- Your CWD is one jj workspace somewhere like `/workspaces/obsidian-ws/ws1` through `ws5`.
- Your Orchestrator holds your workspace's lease. Don't acquire or release workspaces yourself.
- This is a full copy of the repo — `turbo`, `jj` all work from here
- Read the code changes in the workspace by examining jj revisions

#### Responsibilities

1. **Understand the requirements.** Read the issue details from the Orchestrator's dispatch prompt.
2. **Read the relevant design docs.** If you have questions, check with the Orchestrator about the implementation plan section for your milestone/issues, and any related docs. Understand the design decisions — do not re-debate settled questions. Verify the implementation matches settled design decisions.
3. **Review the implementation** by examining the workspace's revisions (`jj log`, `jj diff -r <revision>`). Check:

   **Correctness:**
   - Does the code compile?
   - Do tests pass?
   - Does the implementation actually do what the issue describes?

   **Design Coherence:**
   - Does it follow the settled design decisions in our implementation plan (if available)?
   - Does it match the package structure and architectural patterns described in the codebase documentation?

   **Code Quality:**
   - Is the code clean, readable, and maintainable?
   - Are there tests for new functionality?
   - No unnecessary complexity, premature abstractions, or scope creep?
   - No security issues (command injection, resource leaks, etc.)?

   **Issue Completeness:**
   - Does the implementation fulfill the issue's requirements in spirit?
   - If only partially implemented, did the Implementor clearly describe what remains and what followup issues are needed?
   - Are the jj revisions well-described and logically organized?

4. **Deliver a verdict** via `SendMessage` to the Orchestrator (not as your final output, which the Orchestrator cannot see):

   **PASS** — The implementation is acceptable. Note any minor suggestions (non-blocking).

   **FAIL** — The implementation has problems that must be fixed. Provide:
   - A clear list of specific problems found (with file paths and line numbers where applicable)
   - For each problem: what's wrong and what the expected fix looks like
   - Severity: which problems are blocking vs. suggestions

#### Boundaries

- Do NOT modify code, create revisions, or make changes to the workspace
- Do NOT re-debate settled design decisions — if the implementation follows the design docs, that's correct even if you'd prefer a different approach

---

## Communication Protocol

**Reports must be sent with `SendMessage`, not written as final output.** An agent's plain
text output is not visible to the Orchestrator. An agent that ends its turn with a report in
its output has, from the Orchestrator's perspective, gone idle having said nothing — the work
is done but unreported, and the Orchestrator has to ask for it. Say this explicitly in every
dispatch prompt; it is the single most common failure mode in practice.

### Orchestrator → Implementor

Provide in the agent prompt:

- Workspace path: a jj workspace somewhere like `/workspaces/obsidian-ws/ws1` through `ws5`, acquired with `ws acquire`.
- Issue to implement
- Any extra context or constraints not in the issue

### Implementor → Orchestrator

Return on completion:

- Summary of what was implemented
- List of jj revision change-IDs created
- Whether fully or partially implemented
- Descriptions of any followup issues needed (Orchestrator will create them)
- Any design questions or concerns

If you hit an unexpected issue, need clarification, or can't find information you need, message the Orchestrator rather than guessing or failing silently.

### Orchestrator → Reviewer

Provide in the agent prompt:

- Workspace path to review
- Issue that were implemented
- The Implementor's completion summary
- "Review this implementation and deliver PASS or FAIL with findings"

### Reviewer → Orchestrator

Return:

- **PASS** or **FAIL**
- List of findings (problems, suggestions, questions)
- Descriptions of any issues that should be filed for deficiencies (Orchestrator will create them)

If you hit an unexpected issue, need clarification, or can't find information you need, message the Orchestrator rather than guessing or failing silently.

### On Review Failure

The Orchestrator messages the existing Implementor with the Reviewer's findings if they're still active, otherwise dispatches a new Implementor in the same workspace with:

- The Reviewer's failure findings (verbatim)
- "Fix the following issues identified in review"
- The cycle repeats until PASS
