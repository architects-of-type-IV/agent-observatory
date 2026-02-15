---
name: team-task
description: Agent protocol for team-based task execution. Covers orientation from HANDOFF.md, task claiming, scoped implementation, build verification (mix format, compile, credo, tests), progress tracking, and team lead reporting. Use when an agent is assigned work as part of a multi-agent team.
disable-model-invocation: true
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, SendMessage, TaskUpdate, TaskList, TaskGet
---

# Team Task Agent Protocol

Follow this protocol exactly for every assigned task.

## 1. Orient

- Read `HANDOFF.md` for current context, recent changes, and known issues.
- Read `BRAIN.md` for domain knowledge and established patterns.
- Read `progress.txt` to see what has been done and what remains.

## 2. Claim Your Task

- Identify your assigned task from the team lead's message or TaskList.
- Update `progress.txt`: `[IN PROGRESS] <task description> -- <your agent name>`
- Mark the task `in_progress` via TaskUpdate if using the task system.

## 3. Execute

- Read all target files before editing. Never modify code you haven't read.
- Only touch files within your assigned scope. Do not refactor beyond the task.
- Follow existing patterns in the codebase. Do not invent new conventions.
- If blocked, **stop and SendMessage to team lead immediately**. Do not silently spin.

## 4. Build Verification

Run all applicable checks after your changes:

**Elixir:**
1. `mix format` -- auto-format changed `.ex`/`.exs` files
2. `mix compile --warnings-as-errors` -- zero warnings policy
3. `mix credo --strict` -- static analysis, fix all issues
4. `mix test` -- run if changes touch tested modules

**TypeScript:**
1. `npm run build` or `tsc --noEmit`

Every check must pass. If a check fails, fix it before proceeding. Never report a task complete with a failing build or formatting issues. After 2 failed fix attempts, report to team lead with the error.

## 5. Update Tracking

Update `progress.txt`:
```
[DONE] <task description> -- <your agent name>
  Files changed: <list>
  Build: clean
```

Update `HANDOFF.md`:
- What changed and why (1-3 sentences)
- Follow-up work discovered
- Anything the next agent or human should know

## 6. Report Completion

SendMessage to team lead with:
- Task ID and status
- Files changed
- Build status
- Follow-up items

## 7. Await Shutdown

- Wait for team lead to acknowledge or assign new work.
- Approve shutdown requests when received.
- Do not self-terminate without reporting first.

## Rules

- **No silent completion.** Always SendMessage when done or blocked.
- **No scope creep.** Only do what was assigned. Note other issues for follow-up.
- **No inventing.** Use existing patterns and conventions. Read before writing.
- **Build must pass.** A task is not done until all checks are clean.
- **Max ~15 file edits.** Flag larger tasks to team lead for splitting.
