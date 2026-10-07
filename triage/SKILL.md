---
name: triage
description: >-
  Triage open GitHub issues: add a missing bug, papercut, enhancement, or
  feature label, close exact duplicates, and assign unassigned issues from
  previous work. Use when the user says /triage, asks which issues lack a
  type label, asks who is unassigned, or asks to assign issues from previous
  work.
disable-model-invocation: true
---

# /triage

Triage open issues on the current GitHub repo (`gh repo view`). For
`superplanehq/superplane`, the type labels are `bug`, `papercut`,
`enhancement`, and `feature`. On any other repo, read `gh label list` and
use the four labels that mean the same things.

## Hard rules

- Propose first. Do not add labels, assign people, or close issues until the user confirms that proposal (`yes`, `apply`, `do it`, `assign`).
- A request that already says to apply or assign is the confirmation. Research, then write. Do not ask a second time.
- Add exactly one type label. Leave area labels (`factory`, `intake`, and similar) alone.
- Close an exact duplicate. Do not label it and do not assign it.
- Do not assign the reporter only because they filed the issue.
- Do not hardcode a roster of owners. Look up previous work every time.

## 1. Missing type labels

```bash
gh issue list --state open --limit 500 \
  --json number,title,labels,author,createdAt --jq '
  .[] | select(
    [.labels[].name]
    | any(. == "bug" or . == "papercut" or . == "enhancement" or . == "feature")
    | not
  ) | "#\(.number)\t\(.createdAt[0:10])\t@\(.author.login)\t\(.title)"'
```

Read each body with `gh issue view`. Group issues that share a parent, a title, or a surface. Present the groups. One-by-one only when the user asks; then start with the newest and wait after each one.

| Label | Use when |
| --- | --- |
| `bug` | A flow breaks or a step is blocked. Behavior is wrong. |
| `papercut` | Small, annoying, or inconsistent. The flow still works. |
| `enhancement` | Improves something that already exists. |
| `feature` | Adds a capability that does not exist yet. |

A slice of a parent issue keeps the parent's type. A living list of an upstream limit is an `enhancement` when the product should explain or filter it. The same failure, written as a broken step with expected and actual, is a `bug`.

Exact duplicate: same title and same body as another issue, including a bot copy of a human issue. Close the copy. Point the comment at the issue you keep (prefer the human issue, otherwise the older one).

```bash
gh issue comment <copy> --body "Duplicate of #<kept>."
gh api -X PATCH repos/<owner>/<repo>/issues/<copy> \
  -f state=closed -f state_reason=duplicate
```

`gh issue close --reason` cannot set `duplicate`. Use the API above.

Show the count, the groups, and one confirm question. After confirmation:

```bash
gh issue edit <numbers> --add-label <type>
```

## 2. Unassigned issues

```bash
gh issue list --state open --limit 500 \
  --json number,title,assignees,labels,author --jq '
  .[] | select((.assignees | length) == 0)
  | "#\(.number)\t@\(.author.login)\t[\(.labels | map(.name) | join(","))]\t\(.title)"'
```

If the user only asked whether any are unassigned, list them and stop.

## 3. Choose an assignee

For each issue, find the person who already owns that behavior. Use evidence in this order:

1. Assignee of the parent issue, or of sibling issues in the same epic.
2. Assignee of a related issue about the same behavior.
3. Author of a merged PR that changed that behavior (`gh pr list --state merged --search "..."`).
4. Recent authors of the file that renders it (`git log --format='%an %s' -- <path>`).

Name the issue or PR number in the recommendation. Group the reply by person. When two people both touched the area, name the closer one and mention the other in one sentence.

Weak or conflicting evidence: say so and ask. Do not guess.

## 4. Assign

After confirmation:

```bash
gh issue edit <numbers> --add-assignee <login>
```

Then list any open issues that are still unassigned.

## Report

Keep the reply short. Lead with the count. For a proposal, end with one question. After a write, list each issue with its label or assignee, then anything left over (duplicates still open, issues still unassigned).
