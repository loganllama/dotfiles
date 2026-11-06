# loganllama PR style guide

This guide takes its voice from the early PRs (#127598–#135250; the evidence is in
`loganllama_pr_voice_early.local.md`). It adds patterns from a seeded random 20% sample of the
remaining PRs (45 PRs, April–September). The stack structure comes from the recent big stacks:
#193203–#193209, #190854–#190858 and #189492–#189590.

---

## 0. The goal: precise and concise

A PR description should tell a reviewer exactly what changed and why, using as few words as that
takes.

- **Be precise.** Name the actual thing: the file, resolver, metric, config, or the number of call
  sites. "Load a single page of results on page load so the dropdown is not empty" beats "improves
  the dropdown experience". When a number matters (chunk size, character threshold, how many call
  sites), give the number.
- **Be concise.** Each sentence should change what the reviewer knows or does. Cut restatements of
  the diff, throat-clearing, and reasoning nobody would question. A one-line change gets a one-line
  description.
- When precision and brevity pull against each other, keep the precise detail and drop the prose
  around it.
- Rough numbers are fine as long as they're real. Mark them with "~" or "ish" and show the
  arithmetic if it's short: "We are seeing ~40/hr in prod. That's 40/2,000,000 = 0.002% of test
  runs" / "Before, each test/doc did ~10ish dataloader calls… Now we do ~20ish batch fetches upfront
  and none per item."

---

## 1. Voice

Write like you're explaining the change to a teammate at their desk.

- **First person.** "I" for your own decisions and uncertainty, "we" for the team and the code.
  "After that I concluded @justinjunochang was right and we just don't need the `DomainId[]`
  methods I had."
- **Be candid about tradeoffs and loose ends.** "Arguably worse in some modes because…", "a
  slightly tortured strategy", "I don't love the code changes for (1) but it is a more coherent UI",
  "I'm not totally sure how to effectively test it."
- **Hedge honestly, but don't hedge everything.** Say "AFAIK" or "(hopefully) known good" when you
  actually aren't sure. State plainly what you are sure of: "But (!) there is not going to be a
  behavioral difference."
- **Put the reason next to the change**, joined with plain *because* or *so*: "We submit chunks
  synchronously because there is a bit of an observability blind spot with background jobs."
- **Ground rules in concrete examples**, often in parentheses: "(bad experience to type in something
  like aws and only see top 20 results, implying the one you might be looking for isn't there)".
- **Punctuation:** underscore italics for spoken stress (_my_, _do_, _without a domain_),
  parenthetical "(!)" or "(?!)", "..." for a trailing thought, and casual words where they fit
  ("kinda", "well,", "w/", "e.g.,").
- **Own your uncertainty and say where your knowledge runs out:** "My understanding is the null
  segment is a strict superset of everything", "When mongo can reliably use an optimized query vs
  when it can't is opaque to me.", "It _should_ be a fairly transparent wrapper.", "I'm not entirely
  convinced of our current theories. Though, in the case that this does happen, it's probably better
  to have the failed test run than to commit an incorrect test run."
- **Narrate what you found.** "Turns out the sampling was actually flip flopping between a good
  query plan and a bad query plan." / "Turns out I was focused on the wrong part of the emitter!"
  Starting a sentence with "So" is fine: "So #158371 failed CI because CI wasn't happy I added a
  duplicative index."
- **Wonder aloud about the bigger picture**, briefly, without letting it take over the PR: "There
  is a case to be made for re-evaluating our observability story on test runner… And I'm wondering
  if we would be better off with more structured, composable responses."
- **Admit known imperfections up front:** "Also, I recognize this is labeled under Test Experience.
  I'd like to get these functional, then we can migrate them to a test-core namespace later."
- **Resolve an apparent contradiction with a concrete scenario:** "These seem somewhat conflicting
  and they kind of are! But they can happen at the same time. If you put up a PR deleting the last
  integration test, this change will both NOT run your integration test suite and warn you…"
- **CAPS for the occasional hard emphasis** on a word a reader must not miss: "This ONLY adds the
  index", "NOT run", "register ALL the stuff", "a TEMPORARY optional createdAt".
- **Amend in place** rather than quietly rewriting. Write "EDIT: turns out it can be inferred, but
  it's still there.", or strike through the old plan: "~~Will only merge this after initial prod
  backfill and dual-read monitoring period.~~ It generates so many logs even on just staging - we can
  merge now."
- **Credit people and link feedback:** "Per @miasya, we believe…", "@omavi brought up that…",
  "Followup on feedback in #131827".

### Avoid (these come from my drafts, not your voice)

- "X rather than Y, because Z" as a stock construction, and "That is what makes…" or "which is what
  lets…" signposting.
- Heavy em dashes. Use parentheses, plain hyphens, or a new sentence.
- Bold lead-ins and scattered bold. At most one bolded sentence per PR, for the single point that
  must not be missed: "**_The purpose of this PR is to assess the correctness of
  TestsPageMaterializedViewV2._**"
- Double-hyphen asides (" -- ") and bodies hard-wrapped at 100 columns. Both show up only in the
  Claude-drafted PRs.
- Tidy one-line closing sentences ("Proven rather than asserted.").
- Removing all first person and hedging to sound authoritative.
- A paragraph of justification for every design decision. Explain the decisions a reviewer would
  actually question.

---

## 2. Titles

- `TICKET-NNNN: <lowercase imperative>`, for example "TCORE-390: tag the heartbeat with the state
  it was emitted from".
- **Every PR should have a ticket.** If none is obvious, ask which ticket to associate rather than
  leaving it off.
- Name the thing being changed, and the behaviour where that's short: "update run-test-panel.tsx to
  use paginated search", "remove non-paginated test ID resolver".
- A little humour is fine on small PRs: "Sample Less Please", "make isTestId do the thing", "Back
  to 5% sample because 100% made 1M logs overnight".
- For a series of PRs on one area, a `[area]` tag after the ticket keeps them grouped:
  "[test-freshness] Switch getLatestRunAtsByTestIds hint to covering index".

---

## 3. Sections

Changes and Motivation are always there. Drop Testing, Deployment, and "AI Model used and major
prompts used" when they would have nothing useful to say. Don't pad them with filler like "N/A" or
"none".

This overrides AGENTS.md, which says the `pr-template-guard` hook blocks PRs missing any template
section. It doesn't block, so leave out the sections that add nothing.

When two sections would each be a sentence or two, merge them under one heading: "## Changes +
Motivation", "## Changes & Motivation", "## Testing & Deployment".

Two optional sections are worth adding when they apply:

- **Not in this PR:** adjacent work you deliberately left out. Example: "It has higher potential
  with another change to fuse `segmentId` into the existing indices…"
- **Future Improvements:** open questions or ideas, e.g. "I'd like to support MAX in some
  capacity, but that depends on culling (domainId, testId) pairs that will never run again. Can we
  do that efficiently in the materialized view job?"

### Changes

- 1 to 4 short paragraphs, or a numbered list followed by a short paragraph. Refer back to the
  numbers later: "like (2) and (3)".
- Trivial PRs get one sentence: "All the queries depending on this resolver have been migrated to
  `testRunnerTestIdsPaginated`, so we can remove this now."
- Give the reason for anything a reviewer would question, in the same sentence or the next one.
  This includes a deprecated helper used on purpose, a threshold, or a sync-vs-async choice.
- Say whether behaviour changes. If it doesn't, say so ("there is not going to be a behavioral
  difference", "drop-in replacement").
- Say what this PR deliberately doesn't do yet, and where that work goes ("in a following PR").
- Where it helps, add an "end result" sentence and a "how to use it" sentence: "The end result is
  that `server-common/test-metadata` has no dependencies on the rest of `server-common`… To _use_
  `packages/test-metadata`, one would import…"
- Point out anything odd in the diff and give review guidance: "The git diff is kinda wrong…" /
  "You can review the changes commit-by-commit for more clarity."
- Call out a bug you fixed along the way in its own sentence, so it isn't buried.
- **For code that isn't live, say what the PR is for and what it doesn't do:** "It _does not_
  enable it/register it/replace V1 in any environment yet." / "This does not register either the
  view job or the metrics emission job, it only creates them."
- **Point reviewers at context the diff hides:** "if you expand the diff up a little, you can see
  where we log on mismatch or missing."
- **Mention alternatives you considered** casually, and say why you didn't take them: "Another more
  in depth alternative is looking at adding transactions or sessions… Both would require research
  as to the implications." / "We could also register ALL the stuff from …, but I thought it might be
  easier not to deal with ALL of them."
- **Give consumers a snippet** when the PR adds something others will instantiate: "so instantiate
  with `const seeded: IVantaTestRegistryService = new FakeVantaTestRegistryService(…)`".
- **Batches of independent sibling PRs** (e.g. a migration done one call site per PR) share one
  context paragraph, then add a single line naming the specific change: "We're introducing the
  TestMetadataService as part of the encapsulation project… Migrate `monitorsHelpers.ts` to use
  `TestMetadataService` instead of `TestProvider`."
- **Flag the one non-mechanical bit** in an otherwise mechanical PR: "The main thing here is that we
  don't have a plural `getLatestTests`, but the response for `getTestMetadatasByTestIds` is sorted
  to easily get the latest."

### Motivation

- Start with the ticket URL on its own line.
- For a standalone PR, the ticket link plus a sentence or two is often enough. If the ticket states
  the problem well, quote it as a blockquote.
- Add a human reason when there is one: "To save someone the headaches and headpounding I had." /
  "My last attempt to make `testFreshnessMatViewJob` have no timeouts in prod before I say 'just
  raise the threshold on the alert'."
- **Operational triggers:** when the PR comes from an alert, incident or on-call shift, link the
  source (Datadog monitor, incident doc, Slack thread). Quote the alert text verbatim if that helps:
  "`Triggered: [prod] Job [testFreshnessMetricsEmitter] … exhausted all retries` keeps going off
  despite the new index." A bare "on-call followup" is fine for small fixes.
- **Continuations:** say what this PR continues, e.g. "Continuation of #146100 on the journey to
  make `isTestId` do the thing it says." / "Followup from #174150 which…"
- **Correct the record** if the backstory is murkier than it looks: "My change was probably not
  actually responsible for a perf drop noticed in <thread> (Barlock profiled it…), but we talked a
  lot about TPMV and how it ought to be faster."
- Stacks work differently; see §4.

### Testing

Say what you actually did, briefly and honestly:

- Name the scenarios, not just "added tests". For example: "Some unit tests for the search
  thresholds; manual testing that the dropdown shows all pages."
- Manual testing counts. Say what you ran and what you observed: "Ran the backfill on DEV and then
  ran a bespoke script against ~10k tests on a test domain through the dual-read comparator. The
  only mismatches were due to this subdocument ID and the mismatches went away after stripping
  them."
- If the PR is only tests, say so in one line: "That's literally all this is."
- If a test was confirmed to fail without the fix, say so in one clause. It's the cheapest evidence
  a reviewer can get.
- Name the gaps: "I have not tested X because…" / "The dispatch in `index.ts` is uncovered, as it
  was before."
- When there are no new tests, give one line of why: "No real tests since it re-uses `trigger(...)`
  as the underlying implementation." / "No tests yet. I will add tests in a following PR before
  replacing the implementation."

### Deployment

- **Feature flag:** if there's no flag, give the reason in one line: "None, the new service should
  be a drop-in replacement." / "None, `disable_build_and_deploy` is still `true`."
- **Rollback:** say how to roll back if it isn't simply "revert": "Set the percentages back to 0" /
  "We can simply revert (or mute alerting monitors and fix forward)."
- **Prerequisites and ordering:** for example, "Needs the Statsig config created first", "Wait on
  #177713 so the monitors are in place."
- **Gates:** name the metric and the window, e.g. "merge once
  `test_runner.message_received{schema:legacy}` has been at zero for longer than the queue retention."
- **Migrations:** say where the migration has run and what to do if it misbehaves. If it hasn't run
  anywhere yet, say so, since that's what makes changing it in place safe: "(not yet run in
  staging/ prod, so safe to change in place)".
- **Multi-step rollouts:** use a checkbox plan and tick items off as you go.
  ```
  - [x] create feature flag in statsig
  - [ ] post-merge, ramp up feature flag
  - [ ] inline new versions (remove feature flag gates)
  - [ ] feature flag cleanup
  ```
- **Reverts:** one line on why the revert exists. Example: "Hopefully not necessary, the build isn't
  even started on staging yet. But creating so it's ready, if needed."

### AI Model used and major prompts used

Named to match the template heading. Omit it entirely unless it says something useful. In a stack,
write it on the PRs where it does, and don't add "see PR 1" stubs to the rest.

When it's there, be frank about what the AI did and what you'd do differently by hand:

> Claude absolutely did the UI with my corrections… If I was doing this by hand, I might prefer
> breaking out the forms into a series of subcomponents…

> Just for batch PR creation.

> I did the changes in `test-helpers.ts` which came from [this DD query]. Some of my changes were to
> remove `isTestId` by just changing the function argument from `testId: string` to
> `testId: TestId`, so then I had claude propagate fixes for the resulting typechecking problems.

Cover the model, the split between what you did and what it did, and the primary input (an RFC, a
doc, a query). Keep it to a few lines.

---

## 4. Stacks

Use GitHub's PR stacks feature for navigation. Don't add a stack tree (a diagram of branches or PR
links) to the body. The stack map table below is different: it says what each PR lands, and it goes
in PR 1 only.

### PR 1: motivation for the whole stack

- The ticket, then the problem the whole stack solves, in a few sentences.
- **Narrate the plan** in plain "then… then…" steps, and say where it ends up. Example: "the idea is
  to continue migrating to TMS/TES, then drop a few dead methods, then the difficult remaining items…
  need to be migrated by setting up optional injection sites, … then making that injection
  required, then removing the fallbacks. By the end, `TestProvider` is isolated in the
  `test-execution` package (and not exported). Not quite done…, but on the way!"
- **Stack map** (for stacks of about 4 or more): one line per PR saying what it lands, in order. A
  table works well:

  | | Lands |
  | --- | --- |
  | 1 | This PR: the schema surface the service needs |
  | 2 | Service scaffolding: boots, serves `/health`, replicates nothing |
  | 3 | Plan an event, apply one write |

- **Safety of the in-between states:** say why a half-merged stack is OK. For example, "each PR
  passes CI on its own, and nothing deploys until the flag flips."
- **Gates across the stack:** if later steps wait on a signal (a metric at zero, a flag ramp), name
  that signal here once.

### Later PRs: motivation for this position in the stack

- The ticket link, then **why this PR is here**. Cover what the previous PR made possible, or why
  this one has to come before the next:
  - "The previous PR taught the consumer both shapes, so now we can start sending the new one."
  - "This lands the deployable service before any logic, so the rest of the stack is only about
    replication."
- If the change is in this stack rather than being a separate PR, say why in a sentence: "The
  previous PR made this check always pass for autogenerated tests, so fixing it here keeps it from
  silently going dead."
- **Defer out loud:** "Reconnecting after a stream error isn't handled yet. Any error ends
  replication with a log. That's the next PR."
- **When the plan changes mid-stack**, explain it in your own voice: "So #158371 failed CI because
  CI wasn't happy I added a duplicative index… So let's remove the hint (temporarily slowing down
  queries if it doesn't choose the right plan). Then we'll add/remove both indices in a single PR
  like CI seems to want. Then in a third PR we'll re-add the hint with the new index."
- **Refer to other PRs by position:** "the previous PR", "PR 4". Correct earlier estimates when they
  turn out wrong: "It came to 9 references, not the 11 PR 5 estimated, because…"
- **Per-step safety:** say what makes this step OK to merge and revert on its own.
- **Repeat stable facts briefly** so each PR reads on its own, e.g. "`disable_build_and_deploy` is
  still `true`."

### Changes and Testing in a stack

- **Scope fence:** end Changes with what the system does after this PR. "The service now seeds a
  region and idles." / "Nothing sends the new shape yet."
- **Monolith splits:** open each PR with a pointer to the original and a one-line goal: "Split from
  #177712 for reviewability. This PR: make the replication decision a pure function."
- **Follow-ups:** a PR that finishes something an earlier PR deferred says so. Example: "Deletes the
  loader PR 5 left in place."

---

## 5. PR size and revisions

- Prefer small PRs, each with one small revision.
- Put several revisions in one PR, or split a change into a stack of PRs, only when:
  1. the revisions only work together, or
  2. the split is especially helpful to a reviewer, e.g. a types-only revision followed by the
     revision that uses the types.
- When a PR does have several revisions, say in Changes how to review them (for example, commit by
  commit).

## 6. Commit messages

- One short, concise line when possible. Use the imperative. For a single-revision PR, keep it
  close to the PR title. That's a guideline, not a requirement that they match exactly.
- Add a short bullet list underneath only when the commit needs details the line can't carry.
- Small follow-up revisions can be as terse as "pr feedback" or "extra limits".

## 7. Security risk label

- Default to `security-risk-low`, and bump it up when the content warrants it (see the label table
  and minimums in AGENTS.md).
- The label is per PR, so each PR in a stack gets its own.
