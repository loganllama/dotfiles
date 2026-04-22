# Local Rules

## Version Control: jj (not git)

Never use git commands. This repo uses jj (Jujutsu) for all version control.

- **Snapshot work**: `jj desc -m "message"` to describe, then `jj new` to start a new revision
- **Never affect remotes**: no push, no force-push, no remote operations unless explicitly asked
- **View history**: `jj log`, `jj diff`, `jj show`
- **Rebase**: `jj rebase -r <rev> -d <dest>`, `jj rebase -s <source> -d <dest>` (this latter form is preferable when moving a stack of revisions at once)

## Agent Teams and jj Workspaces

Parallel agent work uses jj workspaces located at `/workspaces/obsidian-ws/ws1` through `ws9`.

### Rules

1. **Batch agents through existing workspaces** (ws1-ws9). Do not create new workspaces beyond what already exists. (But you may recreate ws1-ws9 if they are removed for some reason.)
2. **Reuse workspaces across batches**. When a batch of agents finishes, reuse the same workspaces for the next batch. Do not delete and recreate workspaces.
3. **Park idle workspaces** on the `parking_lot` bookmark (`cd /workspace/obsidian-ws/ws1 && jj edit parking_lot`) instead of deleting them. The parking_lot revision has description "DND: workspace parking lot".
4. **Always stop agents before touching their workspaces**. Never remove, park, or reassign a workspace while an agent is still running in it.
5. **Regenerate derived files in new or stale workspaces** before running tests/lint/typecheck. New workspaces and workspaces that have been idle or rebased onto a significantly different revision need their `node_modules`, build artifacts, and other derived files regenerated. Without this, tests, lint, and builds will fail with missing module errors. Or, worse, some processes will silently pass (like typechecking). **Do NOT use `just pp`** in a jj workspace — it fails at `//#generate-maintainers` (see "`just pp` in jj workspaces" below). Use the replacement command from that subsection.

### Setting Up a Workspace for an Agent

jj workspace commands must be run from within the workspace directory. There is no `--workspace` flag on `jj edit` or `jj new`.

To point a workspace at a specific revision for agent work:

```bash
# If the workspace has been idle, update it first:
cd /workspaces/obsidian-ws/ws1 && jj workspace update-stale

# Then move it to the target revision:
cd /workspaces/obsidian-ws/ws1 && jj new <target-revision>
```

If the workspace has been parked or idle for a while, regenerate derived files before starting work (use a 10-minute timeout — it can be slow). Do **not** run `just pp` (see "`just pp` in jj workspaces" below); instead use:

```bash
cd /workspaces/obsidian-ws/ws1 && yarn install && npx turbo generate-types --continue=dependencies-successful --output-logs=errors-only
```

### `just pp` in jj workspaces

Do NOT run `just pp` inside a jj workspace (`/workspaces/obsidian-ws/ws*`). It fails at the `//#generate-maintainers` turbo task because that task shells out to `git ls-files` (via `scripts/ownership/src/maintainers.ts`), and jj workspaces don't have a `.git` directory.

Instead, run this from the workspace root:

```bash
yarn install && npx turbo generate-types --continue=dependencies-successful --output-logs=errors-only; npx turbo daemon restart
```

`--continue=dependencies-successful` lets turbo complete every task that doesn't depend on `//#generate-maintainers`. The only output that task produces (`apps/web/src/__generated__/graphql-ownership.ts`) is already committed and doesn't need refreshing for dev work. Skipping the docker / uv / oso-cli steps in `post-pull.sh` is also fine — they're already set up at the container level.

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
   - Re-run lint, format, typecheck, tests after resolution
   - Create a new revision on top describing the conflict resolution — do NOT squash into the conflicted parent. The user reviews the delta before squashing.
4. After resolution, re-run the Reviewer on the resolved state if the fix was non-trivial.

**If an Implementor encounters conflicts in their workspace** (because the main line advanced while they were working):
- Rebase their work onto the latest main: `jj rebase -s <their-first-revision> -d main`
- Resolve any conflicts before continuing work
- This is expected and normal — not an error condition

## Work Modes

- **RESEARCH MODE** — Gather context, information, goals. Output: markdown docs as `<foo_bar_plan>.local.md` in the project root.
- **PLANNING MODE** — Turn research conclusions into targets (features), milestones, and implementation plans. Output: markdown docs as `<foo_bar_implementation_plan>.local.md`. These should include hierarchical tasks/checklists for completion.
- **IMPLEMENTATION MODE** — Execute on tasks from the implementation plan, if available, via the Orchestrator/Implementor/Reviewer agent team. See the detailed role instructions below.

## IMPLEMENTATION MODE — Agent Roles

Implementation is carried out by three agent roles: **Orchestrator**, **Implementor**, and **Reviewer**. Each role has specific responsibilities, boundaries, and communication protocols.

**Use agent teams, not standalone subagents.** Create a team once with `TeamCreate` at the start of an implementation session. Then spawn Implementor and Reviewer agents onto that team using the `Agent` tool with `team_name` and `name` parameters. This makes them teammates that can message back via `SendMessage`. Do not spawn Implementors or Reviewers as standalone subagents (no `team_name`) — standalone subagents cannot be messaged after creation and cannot ask for clarification. Reuse the same team across batches; do not create a new team for each dispatch.

### Orchestrator

The Orchestrator is the top-level agent. It does not write code directly. It manages the implementation cycle by creating Implementor and Reviewer agents and ensuring quality through the review loop.

#### Responsibilities

1. **Plan the next unit of work.** Check the in-memory task list or the implementation plan task list. Read the issue details and the relevant sections of plans. Choose issue(s) to assign to the next Implementor.
2. **Assign a free jj workspace** for the Implementor before dispatching them
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

- Your CWD is one jj workspace somewhere like `/workspaces/obsidian-ws/ws1` through `ws9`.
- This is a full copy of the repo — `turbo`, `jj` all work from here
- **If you encounter missing generated files, missing modules, or import errors**: run `yarn install && npx turbo generate-types --continue=dependencies-successful --output-logs=errors-only` in your workspace (10-minute timeout). This regenerates `node_modules`, build artifacts, and generated types. Do NOT run `just pp` — it fails in jj workspaces at `//#generate-maintainers` (see the "`just pp` in jj workspaces" subsection above for why). Do NOT try to copy files from other workspaces or manually regenerate them.

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
7. **Report completion** to the Orchestrator with a summary of:
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

If builds fail with missing module errors, run `yarn install && npx turbo generate-types --continue=dependencies-successful --output-logs=errors-only` in your workspace first (10-minute timeout), then retry. Do NOT run `just pp` — it fails in jj workspaces (see the "`just pp` in jj workspaces" subsection above).

---

### Reviewer

A Reviewer is an agent that evaluates an Implementor's work for quality, correctness, design coherence, and issue completeness. Reviewers do not modify code.

#### Setup

- You are given a workspace path and issue(s) to review
- Your CWD is one jj workspace somewhere like `/workspaces/obsidian-ws/ws1` through `ws9`.
- This is a full copy of the repo — `turbo`, `jj` all work from here
- Read the code changes in the workspace by examining jj revisions

#### Responsibilities

1. **Understand the requirements.** Read the issue details from the Orchestrator's dispatch prompt. 
2. **Read the relevant design docs.**  If you have questions, check with the Orchestrator about the implementation plan section for your milestone/issues, and any related docs. Understand the design decisions — do not re-debate settled questions. Verify the implementation matches settled design decisions.
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

4. **Deliver a verdict:**

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

### Orchestrator → Implementor

Provide in the agent prompt:
- Workspace path: a jj workspace somewhere like `/workspaces/obsidian-ws/ws1` through `ws9`.
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