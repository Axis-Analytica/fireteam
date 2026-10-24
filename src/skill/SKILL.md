---
name: fireteam
description: Run Claude Code agents through development cycles with Fireteam, the Omarchy base camp app. Use when asked to send an agent or a fireteam at a project, run several agents on a codebase, plan an operation, check on or steer running operations, or read their debriefs. Triggers: fireteam, operation, deploy an agent, run cycles, base camp.
---

# Fireteam

Fireteam runs Claude Code agents through cycles of work on a project, one
operation each, and files an HTML debrief per cycle. The `fireteam` command
drives it. Every command takes `--json`, exits 0 on success and 1 on failure,
and writes errors to stderr.

## See what's running

```sh
fireteam list --json          # every operation: id, codename, status, cycles, directory
fireteam show <op> --json     # one operation: sitrep, comms tail, debriefs, reviews, requests
```

`<op>` is a codename (`night-spire`), an id, or the start of an id.

Statuses: `standby`, `staged` (queued for a slot), `deployed`, `held`
(stopped between cycles; check `requests`), `pinned` (waiting on the plan's
usage limit), `complete`, `failed`, `aborted`, `interrupted`.

## Plan and deploy

```sh
fireteam plan --dir ~/Work/app --objective "Add CSV export with tests" \
  --cycles 3 --model sonnet --overwatch review --deploy --json
```

Options: `--codename`, `--cycles N` (1–20), `--model opus|sonnet|haiku`,
`--roe restricted|free`, `--handoff 250000` (0 never hands off),
`--in-place` (the default is a git worktree of its own when the repository
has a commit), `--standing "orders for every cycle"`,
`--overwatch off|review|fix`, `--deploy`.

Deploying needs Fireteam running: the app, or `fireteam serve` with no
window. Planning and orders work either way.

## Steer and wait

```sh
fireteam order <op> "Use SQLite, not JSON files"   # goes out with the next cycle
fireteam order <op> "Add a README" --deploy        # sends a finished one back in
fireteam hold <op>                                 # stop after this cycle
fireteam abort <op>                                # stop now, or leave the queue
fireteam wait <op> --timeout 3600 --json           # until it stops moving
fireteam extract <op>                              # merge a worktree's branch back
```

`wait` exits 0 when the operation completes, 1 when it fails or is aborted,
and 2 when it needs the operator: held for authorisation, pinned, or held.
Approving refused commands is the operator's call; tell the user to press `A`
in Fireteam rather than working around a refusal.

## Read the results

`show` lists the debriefs (HTML, one per cycle), the dossier, and any
overwatch reviews by path. Read the latest debrief for what the agent did and
what it recommends next.
