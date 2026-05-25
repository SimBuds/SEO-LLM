# AGENTS.md — Workflow contract for this project

This file is the workflow contract for any AI coding agent (Claude Code, Codex, Cursor, Aider, Cline, Copilot, or any other tool that reads `AGENTS.md`) operating in this repository. It is project-agnostic and intentionally portable — drop this file into the root of any repo and it applies as-is. Project-specific rules go in a `## Project-specific rules` section appended at the bottom; the workflow contract above that section is not edited per-project.

## How to use this template

1. Copy this file to the project root as `AGENTS.md`.
2. Leave everything above the `## Project-specific rules` heading untouched — that is the shared contract.
3. Add project-specific guidance (stack, build commands, test runners, conventions, paths to other docs) under the `## Project-specific rules` section at the bottom.
4. If the project also uses `CLAUDE.md`, `.cursorrules`, or similar, point those files at this one rather than duplicating workflow rules.

## Precedence

1. Anything under the `## Project-specific rules` section of *this* file.
2. The workflow contract in the rest of *this* file.
3. The agent's built-in defaults.

If a project-specific rule conflicts with the workflow contract, the project-specific rule wins for that topic only — the rest of the contract still applies. The agent must not silently relax a contract rule; if a project rule isn't explicit, the contract holds.

---

## The workflow contract

All non-trivial work runs through these five phases. "Non-trivial" is defined by the Blast-radius tiers section below; trivial-tier work skips to Phase 4.

### Phase 1 — Understand
- Restate the user's request in one sentence.
- Identify ambiguity. If the request has ≥ 2 reasonable interpretations, ask before proceeding.
- Read the code paths involved. Do not guess at file contents.

### Phase 2 — Plan
- Produce a written plan (in the conversation, or in a plan file if the tool supports one).
- The plan lists the **phases**, each with: goal sentence, files to touch, functions to add/change, verification steps.
- Surface the **reuse audit** (see Reuse-first rule) for every new function/class/component proposed.
- Ask the user to approve the plan before any code is written.

### Phase 3 — Phase the work
- Break the plan into phases that each pass the Phase-sizing rules below.
- At the start of Phase 3 — and at the start of *every* subsequent phase — re-state in 3–6 bullets:
  - the inherited decisions (every choice the user has made so far in this session),
  - the current plan state: phases done, phase in progress, phases remaining.
- If you cannot re-state the decisions from working context, context has drifted; re-read the plan file before continuing.

### Phase 4 — Execute one phase
- One phase at a time. No look-ahead edits into later phases.
- Honor the Surface-first audit. Touching a file or function not in the audit is a fatal scope error.
- If a decision arises mid-phase that wasn't covered by the plan, stop and ask. Do not silently choose.

### Phase 5 — Verify & hand back
- Run the verification listed in the plan for this phase. Report observed output, not predicted output.
- Satisfy the Definition of Done before claiming completion.
- End the turn with the literal handoff line, and **no tool calls after it**:

  > `Phase <N> complete. Do I have approval to begin Phase <N+1>?`

  On the final phase, use:

  > `Phase <N> complete. Do I have approval to mark this work complete?`

  Pauses without this line count as incomplete phases. This is the only sanctioned way to yield control.

---

## Phase-sizing rules

A phase is "small enough" only if **all** of the following hold. If any fails, split the phase.

- **One-sentence test.** The phase's goal fits in one declarative sentence with no "and". If you need "and", that's two phases.
- **Diff-surface budget.** ≤ ~300 lines changed, ≤ 5 files touched, ≤ 1 new public interface. Defaults, not hard limits — exceeding any requires an explicit note in the plan justifying why splitting is worse.
- **Single test plan.** Verification fits in ≤ 3 bullets. If you need 5 bullets to describe what to test, the phase is doing too much.
- **Atomic revert.** The phase is a single commit that can be reverted without breaking the build or leaving the repo half-done.
- **Walking-skeleton bias.** The first phase delivers the thinnest possible end-to-end path, even if shallow. Later phases thicken. Don't build all of layer A before any of layer B.
- **Surface-first audit (hard stop).** Before writing code, list the files you will touch and the functions you will add/change. Touching anything outside that list is a fatal scope error: immediately revert the unplanned change, pause execution, and ask for permission to expand the surface. Continuing past an unplanned edit is never acceptable, even if "it was small."
- **No piggybacking.** A phase does its one thing. Refactors, drive-by cleanups, "while I'm here" fixes go into their own phases. Bundling them is the most common way phases blow up.

---

## Decision gates — when to stop and ask

You **MUST** ask, not assume, when:

- The user's request has ≥ 2 reasonable interpretations and the choice affects the diff.
- A naming, data-shape, or API-shape decision will be load-bearing for later phases.
- The change crosses into the **risky** blast-radius tier.
- You discover mid-phase that the plan was wrong. Surface the discovery and re-plan; don't silently adapt.
- A test that was passing now fails for a reason you don't fully understand.

You **MAY** proceed without asking when:

- The change is trivial-tier and reversible by a single `git revert`.
- The user has already answered the same question in this session or in the project's `AGENTS.md` / `CLAUDE.md`.

When in doubt, present the options as a multiple-choice question with a recommended default and the tradeoff for each. Do not invent a single path forward when a meaningful fork exists.

---

## Blast-radius tiers

- **Trivial** — single-file, ≤ 20 lines, no public API change, no shared-state effect. Examples: typo fixes, comment edits, renaming a local variable, tightening a single regex. Proceed and report in one sentence.
- **Standard** — multi-file or new function, but contained to one module. Tests run locally. Use the full phase contract: plan → execute one phase → verify → hand back for approval before the next phase.
- **Risky** — destructive ops (`rm -rf`, `git reset --hard`, force-push, branch deletion), schema/migration changes, dependency upgrades, CI/CD edits, modifications to shared infrastructure or permissions, sending external messages (Slack, email, PR/issue comments), uploads to third-party services. Stop and ask before *each* such action, even within an approved plan. Plan approval is not destructive-step approval.

---

## Reuse-first rule

Before introducing a new utility, class, component, or helper, run a concrete search (`grep`, `rg`, or equivalent) for existing implementations in the project and in any referenced shared libraries. In the plan, state:

- (a) the exact search terms used,
- (b) the candidates found,
- (c) why each candidate cannot be reused (wrong signature, wrong invariants, would require destabilizing changes, etc.).

"I didn't see one" is not a valid answer. The search itself must be shown.

---

## Definition of Done (per phase)

A phase is not done until:

1. The code change matches the planned diff surface — no extras.
2. New behavior has at least one test that fails without the change and passes with it. If the project has no test suite, run the feature end-to-end and report the observed output.
3. Existing tests still pass, or you have explicitly enumerated which broke and why that's expected.
4. **Documentation is updated in the same phase as the code.** Every phase that changes behavior, public surface, config, commands, env vars, or workflows must also update the relevant docs (`README`, `CLAUDE.md`, `AGENTS.md`, in-repo guides, inline doc comments on public APIs, and changelog if the project keeps one) in the *same* commit/phase. Docs are part of the diff-surface budget and must be listed in the surface-first audit. "I'll document it later" is a deferred phase, not a skipped step — and a phase that ships code without its docs update fails Definition of Done.
5. You have posted a phase report — *what changed, what was tested, what docs were updated, what was deferred*. Deferred items go into the plan as named follow-up phases, never as `TODO` comments in code.
6. The user has approved before the next phase begins.

---

## Anti-patterns

- "While I was in there I also…" — scope creep. Defer or split.
- "I'll add a TODO for that" — silent debt. Use a follow-up phase.
- "The tests probably still pass" — run them.
- "I'll mock this for now" — say so loudly; mocks default to phase-end removal.
- Re-asking a question the user already answered in this session.
- Marking a phase done when the verification step was skipped.
- Shipping code in a phase without updating the docs that describe it.
- Ending a phase without the literal handoff line.
- Bundling a refactor into a bugfix, or a bugfix into a feature.
- Inventing a single path forward when a meaningful decision fork exists.

---

## Notes on tone

Keep responses tight. State results and decisions directly. Don't narrate internal deliberation. The phase report and the handoff line are the contract — everything else is optional.

---

## Project-specific rules

*Everything above this line is the shared workflow contract and should not be edited per-project. Add project-specific guidance below — stack, build/test commands, conventions, paths to other docs, domain rules.*

<!-- Examples (delete these and replace):
- **Stack:** <language/framework versions>
- **Build:** `<command>`
- **Test:** `<command>` — required before phase handoff
- **Lint/format:** `<command>`
- **Key docs:** `README.md`, `docs/<file>.md`
- **Conventions:** <naming, layout, anything an agent would otherwise guess wrong>
-->

