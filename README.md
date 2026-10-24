# Fireteam

![Fireteam](docs/screenshot.png)

A base camp for Claude Code agents, styled like a shooter's main menu. Plan an
operation (a project directory, an objective, and a number of cycles), deploy
it, and a headless `claude` agent works through the cycles one after another.
Each cycle resumes the previous cycle's session and files an HTML debrief.
Several operations can be deployed at once, each with its own agent.

Agents use the Claude Code login already on the machine (`claude auth status`
is shown in the header as the Claude link). No API key is needed beyond that.

The dollar figure on each operation is what `claude` reports the runs would
cost at API prices. On a Pro or Max login it isn't billed; it counts against
the plan's usage limits. It's only a real charge if `claude` itself is set up
with an API key (`ANTHROPIC_API_KEY` or an `apiKeyHelper`).

## What you get per operation

- **Comms**: the agent's live stream (what it says and every tool it uses).
- **Sitrep**: the agent's summary at the end of the latest cycle.
- **Debriefs**: one HTML report per cycle. The agent writes it; if it doesn't,
  Fireteam writes one from the comms so no cycle goes unreported.
- **Dossier**: an HTML index of every cycle's sitrep and debrief.
- **Intel**: changed files, from `git status`, when the project is a repository.

Everything Fireteam keeps lives in `~/.local/share/fireteam/`. The project
directory is only touched by the agent itself.

## Context and hand-offs

Each operation shows how full its session's context is, from the token usage
`claude` reports on every turn, against the model's window. When a cycle ends
past the operation's hand-off line (150k, 250k by default, 400k, 600k, or
never), and cycles remain, Fireteam asks the old session for a handoff brief
(state, decisions, how to build and test, known problems, next steps), then
starts the next cycle in a fresh session that reads the brief first. If no
brief gets written, the fresh session starts from the last debrief instead.

Hand-offs normally wait for the cycle to end. A cycle that runs on to twice the
line (the ceiling, kept under 90% of the window) is stopped there instead: the
old session writes a brief that records what was half-done, and a fresh
session finishes the same cycle.

Briefs are kept in `~/.local/share/fireteam/ops/<id>/handoffs/`.

## Steering a deployed operation

- **Orders** (`T`): a message from command. A deployed agent gets it at the
  start of its next cycle, ahead of its own plan, and says in the debrief how
  it was handled. An idle operation can be sent straight back in with it
  (Transmit) or keep it for the next deploy (Queue). Orders from a cycle that
  fails or is aborted go back in the queue.
- **Hold** (`H`): stop after the current cycle finishes, rather than aborting
  mid-cycle. Resume with `Space`.
- **Amend** (`E`): change the objective, cycles, model, rules of engagement, or
  hand-off line of an operation that isn't deployed. The project directory
  stays, because the Claude session belongs to it.
- **Retry**: a failed cycle is run again with `Space`.

When Fireteam isn't the focused window, it sends a desktop notification as
cycles finish, operations complete or fail, and sessions hand off. Clicking
one brings Fireteam up on that operation.

## Rules of engagement

| ROE | `claude` permission mode | Meaning |
| --- | --- | --- |
| Restricted | `acceptEdits` | Edits files; other commands follow your Claude Code permission settings, and anything not pre-approved is refused |
| Weapons free | `bypassPermissions` | Runs any command without asking |

## Controls

| Key | Action |
| --- | --- |
| `N` | Plan a new operation |
| `Space` | Deploy, resume, or redeploy (+1 cycle) the selected operation |
| `T` | Send orders to the selected operation |
| `H` | Hold after the current cycle, or lift the hold |
| `E` | Amend the briefing of an operation that isn't deployed |
| `X` | Abort the selected operation |
| `↑` `↓` / `J` `K` | Move through the roster |
| `R` | Open the latest debrief |
| `D` | Open the dossier |
| `O` | Open the project directory |
| `Del` | Stand down (remove) the operation |
| `Ctrl+Enter` | Deploy from the briefing |
| `Esc` | Close a panel |
| `?` | Show the controls |
| `Q` | Quit (asks first while agents are deployed) |

## Command line

```sh
fireteam              # open the board
fireteam status       # list operations
fireteam status --json
```

## Build

```sh
bin/build     # build/fireteam
bin/test      # tests, offscreen, with a fake claude
bin/install   # package and install, so it shows in the launcher
```
