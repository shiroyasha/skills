---
name: superplane
description: >-
  Research the repository, interview the user with multiple-choice questions,
  then create a SuperPlane work order (task) on workspace SUPER via the REST
  API. The skill never changes repository files; it only investigates to write
  the order. Use when the user says /superplane, asks to create a SuperPlane
  work order, or wants to file a factory task on SUPER.
disable-model-invocation: true
---

# /superplane

Create a draft work order on SuperPlane workspace SUPER. Do not dispatch the
order to a line.

## Hard rules

- This skill is read-only on the repository. Never edit, create, delete, or
  format a repository file, never run a command that changes the working tree
  (no `git` writes, no code generation, no installs, no fixes), and never start
  the work the order describes. The only file you may write is the temporary
  description file in step 4.
- The output of this skill is a work order, not a change. When the request looks
  like a bug or a small fix, still stop at the work order. If the user wants the
  fix applied now, they must ask for it outside this skill.
- Stay in the current mode. Do not call `SwitchMode`. Research, interview, and
  submit all happen where the user already is.
- Ask every question with the `AskQuestion` tool. Each question carries concrete
  candidate answers that the user picks from. Never ask an open prose question
  when you can propose options.
- Read the code before you ask. Options must name real files, packages, and
  behavior in the repository, not placeholders.
- Do not call the API until the interview is complete and the user has approved
  the final title and description.
- Do not skip a question because the first message looked complete. Fold what
  the user already said into the first option and still let the user confirm.
- Do not ask for assignees. The API assigns the caller.
- Do not print, log, or write the API token. Do not cat `~/.superplane.yaml`.
- Do not invent curl. Run `scripts/create-work-order.sh` from this skill
  directory.

## Fixed target

- Organization ID: `3ee1aa47-3a60-4c1f-b645-0b9859ab91f8`
- Workspace key: `SUPER`
- UI base: `https://app.superplane.com`
- Auth: `~/.superplane.yaml` (CLI contexts: `url`, `apiToken`, `organizationId`)

## 1. Research first

Before the first question, spend a short pass on the repository so the options
are real. Read the files the request touches, and use `explore` subagents in
parallel when the area is unclear. You want to know: which package or page owns
this, what the current behavior is, and which two or three implementations are
plausible.

Research is read and search only: `Read`, `Grep`, `Glob`, and `explore`
subagents. Do not run builds, tests, formatters, or migrations, and do not
prototype a fix to see if it works. When you find the root cause, put it in the
`## Context` heading of the description instead of fixing it.

Give the user a one-line note on what you found before you start asking.

## 2. Interview with multiple-choice questions

Ask with `AskQuestion`. Send one or two questions per call, in this order. Put
the option you recommend first and mark it `(Recommended)`. The user can always
pick "Other" and type a free answer, so you do not need an "Other" option.

| # | Question | Option style |
| --- | --- | --- |
| 1 | Goal — what should change? | Two or three concrete outcomes, each one sentence |
| 2 | Scope — which part of the system? | Real packages, pages, or files from research |
| 3 | Approach — how should it be built? | Rival implementations with the trade-off named |
| 4 | Acceptance — how do we know it is done? | `allow_multiple: true`, concrete checks |
| 5 | Out of scope — what must not change? | `allow_multiple: true`, nearby things you found |
| 6 | Constraints — deadline, environment, risk | Real constraints, plus "No constraints" |
| 7 | Title | Two or three drafts, max 256 characters each |

Rules for options:

- Each option is a decision the user can act on, not a category label.
- Name files, packages, and components (`pkg/workers`, `web_src/src/pages/...`).
- When the user's first message already answers a question, make that the first
  option and still ask.
- Never send a question whose options you invented without reading code.

Good option: `Add the retry to pkg/workers/run_finalizer.go, so only finalize
retries` — bad option: `Fix the worker`.

## 3. Draft the work order

Build the description with these headings:

```markdown
## Goal

## Context

## Acceptance

## Out of scope

## Constraints
```

Fill each heading from the chosen options. Keep the wording of the option the
user picked; do not rewrite their decision into something broader.

Show the final **title** and **description**, then ask for approval with
`AskQuestion`: submit as written, edit a section first, or cancel. Wait for the
answer.

Limits: title max 256 characters; description max 5000 characters. Trim or
ask the user to shorten before submit.

## 4. Submit

Write the description to a temp file. Then run (from this skill directory):

```bash
scripts/create-work-order.sh --title "<title>" --description-file "<temp-file>"
```

The script reads `~/.superplane.yaml`, resolves factory key `SUPER`, and POSTs
`/api/v1/factories/{factoryId}/orders`. It prints a JSON object with `id`,
`number`, `key`, and `state`.

On success, give the user this URL (use `number` from the script output):

`https://app.superplane.com/3ee1aa47-3a60-4c1f-b645-0b9859ab91f8/workspaces/SUPER/work-order/{number}`

On failure, report the script stderr. Do not retry with a leaked token or a
hand-written Authorization header.

### Failure modes

- **HTTP 401 Unauthorized** — the API token is no longer valid. A token stops
  working when the user regenerates it or changes the account password. Tell
  the user to generate a new token at
  `https://app.superplane.com/3ee1aa47-3a60-4c1f-b645-0b9859ab91f8/settings/profile`
  and to put it in `~/.superplane.yaml`. To submit without an edit to the
  config file, the user can export `SUPERPLANE_API_TOKEN` in the shell, which
  the script prefers over the config value. Never ask the user to paste the
  token into the chat.
- **HTTP 403 with a Cloudflare body** — the request did not reach the API.
  Cloudflare blocks the default `Python-urllib` agent with error 1010, so the
  script sends an explicit `User-Agent`. Do not remove that header.
