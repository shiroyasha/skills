---
name: shipit
description: >-
  Open a branch if needed, commit local changes, push, open a pull request,
  print the PR URL, then babysit until the PR is merge-ready. Use when the
  user says /shipit, shipit, or ship it.
disable-model-invocation: true
---

# /shipit

Ship the current work: branch → commit → PR → babysit.

Do not ask whether to commit, push, or open a PR. The user already asked to ship.

## Hard rules

- Never skip git hooks (`--no-verify`) unless the user explicitly asks.
- Never force-push to `main`/`master`.
- Never amend a commit the user did not ask to amend, except when this session's commit succeeded and a hook only rewrote files that must be included.
- Never commit secrets (`.env`, credentials, private keys).
- Never run `git add -i` or other interactive git flags.
- Do not update git config.

## 1. Inspect state

In parallel:

```bash
git status
git diff
git diff --staged
git log -8 --oneline
git rev-parse --abbrev-ref HEAD
git remote show origin 2>/dev/null | sed -n 's/.*HEAD branch: //p'
```

Default branch is `origin/HEAD` (usually `main` or `master`). Treat `main` and `master` as protected base branches.

If there is nothing to commit and no unique commits vs the default branch, stop and say so. Do not open an empty PR.

## 2. Branch

If HEAD is the default branch (or another protected base branch), create and switch to a new branch before committing.

- Name from the change: short, lowercase, hyphens (`fix-widget-empty-state`).
- If already on a non-base branch, keep it.

```bash
git checkout -b <branch-name>
```

## 3. Commit

If there are uncommitted changes:

1. Stage the relevant files. Prefer named paths over `git add -A`. Do not stage secrets or unrelated junk.
2. Draft the message from the diff: subject explains why, not a file list.
3. Follow repo commit conventions when they exist (Conventional Commits, DCO/`git commit -s`, STE). Otherwise use Beams/Pope: imperative subject (~50 chars), blank line, body wrapped at 72 that explains why.
4. Commit with a HEREDOC:

```bash
git commit -m "$(cat <<'EOF'
Subject line

Body explaining why.

EOF
)"
```

Use `git commit -s` when the repo requires DCO.

If the commit fails because of a hook, fix the issue and create a **new** commit. Do not amend a failed commit.

If everything is already committed on the feature branch, skip this step.

## 4. Pull request

Push and open (or reuse) a PR with `gh`.

```bash
git push -u origin HEAD
gh pr view --json url,title,state 2>/dev/null
```

If no PR exists:

1. Read `git log` and `git diff <default-branch>...HEAD` for the full change set, not only the last commit.
2. Follow repo PR conventions when they exist. Otherwise title is an imperative summary; body:

```markdown
## Summary
<why this change exists>

## Test plan
- [ ] <how to verify>
```

```bash
gh pr create --title "..." --body "$(cat <<'EOF'
## Summary
...

## Test plan
- [ ] ...

EOF
)"
```

**Always print the PR URL** in the user-facing reply as soon as it exists, before babysitting.

## 5. Babysit

Follow the built-in **babysit** skill: triage unresolved comments (including Bugbot), fix CI caused by this PR, and resolve real merge conflicts. Then apply these extra rules:

**Do not update the branch just because it is behind the default branch.**

Ignore GitHub "Update branch" / "out of date with `main`" (or `master`) when the PR has **no merge conflicts**. Do not merge or rebase the default branch in that case.

Update from the default branch **only when there are merge conflicts** (or the user explicitly asks). Resolve conflicts while preserving intent on both sides; if intents clash, abort and ask.

**Take Greptile comments with a grain of salt.**

Greptile is a noisy automated reviewer. Its comments are often wrong, speculative, or style nits. A Greptile thread, review, or "request changes" is not required work.

- Read the claim and check it against the code yourself.
- Fix only when you independently confirm a real bug in this PR's scope.
- Otherwise dismiss the thread with a short concrete reason. Do not change code to satisfy Greptile.
- After that triage, an unresolved Greptile thread does not block merge-ready.

Loop until the PR is merge-ready (green CI, comments triaged, no unresolved conflicts) or you are blocked and must ask the user.

## 6. Report

Keep the final message short:

- PR URL (again)
- Branch name
- What you committed / whether you reused existing commits
- Babysit outcome: merge-ready, or what is still blocked
