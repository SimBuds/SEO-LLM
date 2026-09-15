# IMPLEMENT.md

## Current state
- Active phase: none (Phase 7 awaiting approval and the Phase 6 commit)
- Last completed phase: 6 (Phase 3 committed in `a33329d`. Phase 1 committed in `7143421`, which also tracked `AGENTS.md` and `IMPLEMENT.md`)
- Plan approved by Casey 2026-09-15, including the proposed `prompts/system.md` and the rewrite-model wording.
- Run order: 3, 6, 7, 8, then 2, 4, 5. Phase 9 is deferred.

## Inherited decisions
- `AGENTS.md` is the source of truth for how work runs in this repo (2026-09-14).
- The repo splits into sibling repos. `~/Apps/SEO-LLM` stays the SEO repo. The tutor app moves to `~/Apps/Tutor-LLM`.
- Casey creates the Tutor-LLM folder and performs the separation. The agent does not touch anything outside this repo and never commits.
- SEO design is the Claude Code skills pipeline (skills, prompts, one shell wrapper). The Python and Streamlit `seo-app` plan is retired. It stays recoverable from commit `0c7031b`.
- Tutor-LLM starts standalone, with no dependency on `seo-app` code. Its fixes are planned in its own repo and `IMPLEMENT.md`, not here.
- Order of work: split cleanup first, then the SEO fix, then the tutor fix.
- (2026-09-15) The model runtime moves to the llama.cpp router: `POST http://localhost:8080/v1/chat/completions`, model `qwen`, `chat_template_kwargs: {"enable_thinking": false}`. Skill checks use `curl -s localhost:8080/models`. Allowlists, README, and PLAN prose follow. Done means a grep for `11434|ollama` comes back clean.
- (2026-09-15) Run order: Phase 3 (PLAN.md restore) first, then the llama.cpp migration (Phases 6 to 8), then Phases 2, 4, 5.
- (2026-09-15) Wrapper shape: `scripts/llm_call.sh <prompt-file> [temperature] [seed]`. It always sends `prompts/system.md` as the system message, which the caller cannot swap. `LLM_HOST` (default `http://localhost:8080`) and `LLM_MODEL` (default `qwen`) override the defaults.
- (2026-09-15) Casey commits Phase 1 before any new phase starts.
- (2026-09-15) Casey allowed a read-only look at `~/Apps/Local-LLM` for the old system prompt. Its README "Contract for apps" says each app sends its own system message. The router's generated `models/qwen/prompt.txt` is gitignored and carries personal context, so it is not copied or referenced.
- (2026-09-15) System message source: a new repo-owned, SEO-specific `prompts/system.md`. It borrows only from Local-LLM's tracked, non-personal `prompts/{system,formatting,personality}.md`, never from `memory/`. Casey reviews the text (below, in Phase 6) before any call uses it.

## Phases

### Phase 1: Casey moves `tutor-plan.md` out of this repo into `~/Apps/Tutor-LLM`.
- Status: complete (2026-09-14, done by Casey without the handed commands)
- Type: execution-assist. Casey runs it. The agent writes nothing.
- Files to touch: `tutor-plan.md` (removed from this repo by Casey)
- Functions to add or change: none
- Reuse audit: `grep -rn tutor` over the repo (excluding `.git`, `AGENTS.md`). Only hit is `tutor-plan.md` itself, so no other SEO-LLM file needs editing for the move.
- Simplest approach considered: move the single file. Adopted.
- Scenarios: file gone from SEO-LLM, present in Tutor-LLM. No remaining tutor references in SEO-LLM.
- Verification:
  - `git status --short` shows ` D tutor-plan.md` and nothing else new.
  - `grep -rn --exclude-dir=.git --exclude=AGENTS.md --exclude=IMPLEMENT.md -i tutor .` returns no hits.
- Deferred out of this phase: all tutor plan fixes (Tutor-LLM repo).

### Phase 3: Restore `PLAN.md` to the Claude Code skills blueprint from commit `2518416`.
- Status: complete (2026-09-15)
- Files to touch: `PLAN.md`
- Functions to add or change: none
- Reuse audit: `git log -- PLAN.md` shows `2518416` as the last skills-design version. Restoring it reuses that doc instead of writing a new one.
- Simplest approach considered: byte-identical restore via `git show 2518416:PLAN.md`, with content fixes left to later phases. Adopted, per the extraction rule (move verbatim first, then edit).
- Scenarios: restored file matches `2518416` exactly. No `seo-app` or `prompts/seo/` references remain in `PLAN.md`.
- Verification:
  - `git diff 2518416 -- PLAN.md` is empty.
  - `grep -n 'seo-app\|prompts/seo' PLAN.md` returns no hits.
- Deferred out of this phase: model runtime prose (Phase 8). Phase tracking still living in `PLAN.md` (Phase 9).

### Phase 6: Add `scripts/llm_call.sh`, which sends `prompts/system.md` plus a prompt file to the llama.cpp router.
- Status: complete (2026-09-15)
- Files to touch: `scripts/llm_call.sh` (new), `prompts/system.md` (new), `.claude/settings.json`, `.claude/settings.local.json`
- Functions to add or change: the wrapper script (one public interface: its command line)
- Reuse audit:
  - `grep -rniE '11434|ollama' .` lists the existing wrapper `scripts/` (old runtime, `/api/generate`, model as first argument). Its shape (`set -euo pipefail`, `jq` payload, `curl --fail-with-body`) is reused. Its endpoint, argument list, and response path cannot be.
  - `grep -rn -i 'you are\|system' prompts/` finds only per-task role lines in `ingest.md`, `outline.md`, `section.md`. No shared system prompt exists to reuse.
  - Local-LLM `prompts/{system,formatting,personality}.md`: general assistant rules addressed to Casey as a peer. Borrowed in spirit (no filler, no fabrication, no emoji, no preamble). Not reused verbatim because they target chat help, coding, and tutoring, and reference `memory/` files this repo does not have.
- Simplest approach considered: the current script with the endpoint swapped and a system message added. Adopted, plus sampling knobs sent on every call (AGENTS.md "Sampling options and context length are app-owned").
- Design:
  - Payload: `model`, `messages: [{role: system, content: prompts/system.md}, {role: user, content: <prompt-file>}]`, `temperature` (arg, default 0.7), `seed` (arg, default 0), `top_p 0.95`, `top_k 40`, `min_p 0.05`, `presence_penalty 0.0`, `repeat_penalty 1.05` (pinned from Local-LLM `build-qwen` PARAMS as of 2026-09-14), `chat_template_kwargs: {enable_thinking: false}`, `stream: false`.
  - Output: `jq -er '.choices[0].message.content'`, so a null or missing reply exits non-zero.
  - Context: fixed at 32768 tokens by the router preset. No per-request override exists, and overflow returns HTTP 400 (Local-LLM contract). Recorded, not sent.
  - Allowlist: `settings.json` drops the old wrapper, old port, and old CLI entries. It adds `Bash(scripts/llm_call.sh:*)`, `Bash(bash scripts/llm_call.sh:*)`, `Bash(./scripts/llm_call.sh:*)`, `Bash(curl -s localhost:8080/models)`, and keeps `jq`, `yq`, `pandoc`, `pdftotext`. `settings.local.json` swaps its one smoke entry for the same command on the new wrapper.
- Proposed `prompts/system.md` (for Casey's review):
  ```markdown
  # SEO content model

  You write and structure SEO content. Each request carries its own task, brief, and required output format in the user message. Follow that task exactly.

  ## Output
  - Return only the requested deliverable. No preamble, no sign-off, no notes about what you did or about being an AI.
  - Match the format the task specifies exactly (markdown headings, YAML keys and order, fixed section names). Do not wrap the reply in a code fence unless the task asks for one.
  - No emoji.

  ## Facts
  - Do not invent statistics, prices, dates, studies, quotes, URLs, or named businesses. When a point needs a figure the brief does not supply, make it without the figure.
  - Do not claim first-hand experience the brief does not give you.

  ## Voice
  - Calm, direct, specific. Write for the stated audience in the stated tone.
  - No filler openers or stock phrases ("In today's fast-paced world", "Certainly!", "Furthermore").
  - Say the concrete thing instead of hedging around it.
  ```
- Scenarios (from the requirement):
  - Happy path, defaults: prompt file only, exit 0, non-empty reply, no thinking text in the output.
  - System message sent: a prompt asking "In one sentence, what is your role?" gets an SEO-content answer drawn from `prompts/system.md`.
  - No arguments: usage error, non-zero exit.
  - Unreadable prompt file: message naming the file, exit 2.
  - Missing `prompts/system.md` (moved aside and restored in the same command): message naming it, exit 2.
  - Server error (`LLM_MODEL=nonexistent`): non-zero exit with the server's error body shown.
  - Context overflow (HTTP 400): same code path as the server error case, so not tested separately.
  - Router down: not testable without stopping the router, which is Casey's system (tier 0). Covered by the same `curl --fail` path.
  - Fail-first: before the change, `bash scripts/llm_call.sh` fails because the file does not exist.
- Verification:
  - Live: the defaults call and the role-check call both exit 0 with the expected content (observed output pasted).
  - Error cases above each exit non-zero with the named message.
  - `jq . .claude/settings.json .claude/settings.local.json` parses, and a grep shows the new entries present and the old ones gone.
- Deferred out of this phase: skills still call the old wrapper until Phase 7.

### Phase 7: Point the three skills at `scripts/llm_call.sh` and the router check, and delete the old wrapper.
- Status: planned
- Files to touch: `.claude/skills/seo-ingest.md`, `.claude/skills/seo-outline.md`, `.claude/skills/seo-draft.md`, old wrapper in `scripts/` (delete)
- Functions to add or change: none (skill steps only)
- Reuse audit: case-insensitive grep lists the lines to change. Preconditions at lines 16 to 17 in each skill. Run step at `seo-ingest.md:31`, `seo-outline.md:31`, `seo-draft.md:34`. "via Ollama" wording at `seo-outline.md:8`, `seo-draft.md:8`. Failure wording at `seo-draft.md:40`. `seo-draft.md:17` names the old model and build script.
- Simplest approach considered: replace the two precondition lines with one check, `curl -s localhost:8080/models | jq -e '.data[] | select(.id=="qwen") | .id'`, which must print `qwen`. If it does not, the skill tells the user the llama.cpp router is not serving `qwen` and stops. Swap the run command to `bash scripts/llm_call.sh <prompt-file> <temp> <seed>` with each skill's existing temperature and seed. Adopted.
- Scenarios:
  - Precondition passes against the live router.
  - Precondition fails loudly when the model is absent (same check with a nonexistent id exits non-zero).
  - End-to-end outline, draft, and ingest each produce their file through the new wrapper.
  - No skill mentions the old wrapper, old port, or old model names.
- Verification (manual, live model, steps run by hand because slash-command loading is an open Phase 9 question):
  - The precondition check prints `qwen`. With a nonexistent id, it exits non-zero.
  - Following the skill steps on `briefs/example.yaml` writes `outline.md` (has H1, `## FAQ`, `## Conclusion`) and `draft.md`. Ingest on a scratch `.md` source writes a brief that `yq` parses with all six keys. The token `usage` of the draft call is recorded. Generated files are removed afterwards.
  - `grep -niE '11434|ollama|qwen-custom|~/ai' .claude/skills/*.md` returns no hits.
- Deferred out of this phase: none

### Phase 8: Rewrite the model-runtime prose in `README.md` and `PLAN.md` for the llama.cpp router.
- Status: planned
- Files to touch: `README.md`, `PLAN.md`
- Functions to add or change: none
- Reuse audit: case-insensitive grep finds 20 README lines and 30 lines in the restored `PLAN.md` naming the old runtime, port, model tags, or `~/ai` build scripts. Router facts come from Local-LLM's README "Contract for apps".
- Simplest approach considered: edit only the lines that name the runtime, port, wrapper, model tags, and build/setup steps. Point setup at the Local-LLM router (`make serve` there) and `curl -s localhost:8080/models`. Leave unrelated prose for Phases 4 and 9. Adopted.
- Open item for approval: the future rewrite pass named `llama-custom`, which the router does not serve (it serves `gemma`, `qwen`, `lite`). Proposal: the docs say the rewrite model is chosen when that phase is planned, rather than naming one now.
- Scenarios: the diagram, layout, prerequisites, quickstart, and wrapper usage match `scripts/llm_call.sh`. The determinism table no longer lists a per-stage context size (fixed by the preset). No stale runtime mention in any tracked file.
- Verification:
  - `grep -rniE --exclude-dir=.git --exclude=IMPLEMENT.md '11434|ollama' .` returns no hits (exit 1). Hits inside `IMPLEMENT.md` are plan history and are listed separately.
  - `grep -rnE --exclude-dir=.git --exclude=IMPLEMENT.md 'qwen-custom|llama-custom|~/ai' .` returns no hits.
  - The README quickstart check command runs and prints the router's model list.
- Deferred out of this phase: none

### Phase 2: Add a `.gitignore` so working files and generated output stay out of git.
- Status: planned (after Phase 8)
- Files to touch: `.gitignore` (new), `outputs/_smoke/_prompt.txt` (delete, generated smoke artifact)
- Functions to add or change: none
- Reuse audit: `ls -a` shows no existing `.gitignore`. `grep -rn _smoke` finds only `.claude/settings.local.json` (a local allow entry).
- Simplest approach considered: one `.gitignore` with four entries (`IMPLEMENT.md`, `outputs/`, `briefs/_ingest/`, `.claude/settings.local.json`). Adopted.
- Discovered 2026-09-15: `IMPLEMENT.md` is already tracked (commit `7143421`), so the ignore rule alone will not untrack it. Casey runs `git rm --cached IMPLEMENT.md` as a handed command in this phase (tier 0 reserves git index writes to Casey). Verification of the `IMPLEMENT.md` ignore depends on it.
- Scenarios: `IMPLEMENT.md` ignored. A new file under `outputs/` ignored. A file under `briefs/_ingest/` ignored. `briefs/example.yaml` and `.claude/settings.json` still tracked.
- Verification:
  - `git check-ignore -v IMPLEMENT.md outputs/x/draft.md briefs/_ingest/x.txt .claude/settings.local.json` names a rule for each.
  - `git check-ignore briefs/example.yaml .claude/settings.json` prints nothing and exits 1.
- Deferred out of this phase: none

### Phase 4: Point `README.md` at `AGENTS.md` as the source of truth and describe the post-split repo.
- Status: planned (after Phase 2)
- Files to touch: `README.md`
- Functions to add or change: none
- Reuse audit: `grep -n 'IMPLEMENT.md\|seo-cli' README.md` finds line 95 (dead `IMPLEMENT.md` link) and line 30 (tree label `seo-cli/`). Line numbers are rechecked after Phase 8.
- Simplest approach considered: edit only the "Working in this repo" section and the tree label. Adopted.
- Scenarios: no link to a missing file. `IMPLEMENT.md` described as the untracked working file per `AGENTS.md`. Tree label matches the repo name. No tutor mention.
- Verification:
  - `grep -n '](IMPLEMENT.md)\|seo-cli' README.md` returns no hits.
  - Every relative link in `README.md` resolves to an existing file (checked with a `test -e` loop).
- Deferred out of this phase: remaining README audit findings (Phase 9).

### Phase 5: Fill the `## Project-specific rules` section of `AGENTS.md` for SEO-LLM.
- Status: planned (after Phase 4)
- Files to touch: `AGENTS.md` (final section only, universal body untouched)
- Functions to add or change: none
- Reuse audit: the section currently holds only the reset template comment. Facts come from `README.md`, `.claude/settings.json`, and `scripts/llm_call.sh`.
- Simplest approach considered: a short bullet list covering stack (Claude Code skills, bash, `jq`, `curl`, the llama.cpp router at `localhost:8080` with model `qwen`), the system message rule (`prompts/system.md` on every call, dated 2026-09-15 with its reason), no Python app (dated decision), environment labels (local terminal, Claude Code session), and the test posture (live generation is manual, no automated suite yet). Adopted.
- Scenarios: universal body byte-identical to before. Section header present exactly once. Each rule that records a decision carries a date and reason.
- Verification:
  - `git diff --no-index` against a pre-edit copy shows changes only after the `## Project-specific rules` line.
  - `grep -c '^## Project-specific rules$' AGENTS.md` prints `1`.
- Deferred out of this phase: none

### Phase 9 (deferred): Remaining SEO fixes.
- Status: planned, to be broken into phases after Phase 5.
- Scope: skill file layout (`.claude/skills/<name>/SKILL.md` vs flat files, and whether slash commands load), README quickstart duplicate step and placeholder list, restored `PLAN.md` phase tracking moved to match `AGENTS.md` (status belongs in `IMPLEMENT.md`).

## Phase reports

### Phase 6 report
- Changed: `scripts/llm_call.sh` (new, 54 lines, mode 755 like the old wrapper), `prompts/system.md` (new, 17 lines, the approved text verbatim), `.claude/settings.json` (old wrapper, old port, and old CLI entries replaced by the new wrapper and `curl -s localhost:8080/models`), `.claude/settings.local.json` (smoke entry now calls the new wrapper). `settings.local.json` is ignored by `~/.config/git/ignore`, so it does not show in `git status`.
- Bug found and fixed in-phase: on HTTP error, `set -e` exited at the `RESPONSE=$(curl ...)` capture, so the server's error body was never printed (only `curl: (22) ... 400`). The old wrapper had the same defect. Fix: `|| { rc=$?; echo "$RESPONSE" >&2; exit "$rc"; }`. Observed failing first, then passing (S6 below).
- Tested (live router, observed):
  - Fail-first: before the change, `bash scripts/llm_call.sh` exited 127 (no such file).
  - S1 defaults (prompt file only): exit 0, one-sentence reply, no thinking text. 10.7 s including the `qwen` load.
  - S2 role check: with the wrapper, "help you write and structure SEO content according to specific tasks and briefs". Control call without a system message: "provide helpful, accurate, and safe information across a wide range of topics". The system message is being sent. The control response's `message` keys were only `content` and `role` (no `reasoning_content`), so thinking is off.
  - S3 no args: exit 1, "prompt file required". S4 unreadable prompt: exit 2 with the path. S5 missing `prompts/system.md`: exit 2 with the path, file restored.
  - S6 `LLM_MODEL=nonexistent`: before the fix exit 22 with no body. After the fix exit 22 and `{"error":{"code":400,"message":"model 'nonexistent' not found",...}}` on stderr.
  - Settings: both files parse with `jq`. The `11434|ollama` grep over them exits 1. `curl -s localhost:8080/models | jq -e ...` finds `qwen` (status `loaded`).
- Docs: `IMPLEMENT.md` updated. README and PLAN prose are Phase 8.
- Deferred: skills still call the old wrapper until Phase 7.

### Phase 3 report
- Changed: `PLAN.md` restored byte-identical from `2518416` via `git show 2518416:PLAN.md > PLAN.md`.
- Tested: before, `git diff --stat 2518416 -- PLAN.md` showed 162 insertions and 149 deletions, and the `seo-app|prompts/seo` grep counted 5 hits. After, `git diff --exit-code 2518416 -- PLAN.md` exits 0 and the grep exits 1.
- Docs: `IMPLEMENT.md` updated. It now shows in `git diff --stat` because `7143421` tracked it. Untracking it is part of Phase 2.
- Deferred: runtime prose in the restored plan (Phase 8). Phase tracking still inside `PLAN.md` (Phase 9).

### Phase 1 report
- Changed: `tutor-plan.md` removed from SEO-LLM by Casey. Tutor-LLM now holds `tutor-plan.md` and a copy of `AGENTS.md`.
- Tested: `git status --short` shows ` D tutor-plan.md` plus the two untracked docs. Tutor grep over SEO-LLM returned no hits (exit 1). `cmp` of `HEAD:tutor-plan.md` and of `AGENTS.md` against the Tutor-LLM copies both exit 0.
- Docs: `IMPLEMENT.md` updated.
- Deferred: in Tutor-LLM the plan is still named `tutor-plan.md` (the pillar name is `PLAN.md`), and its `AGENTS.md` still needs its project section reset. Both belong to the tutor fix in that repo.
