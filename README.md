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
- **Cycle cards**: one per cycle run, with how it ended, files changed, lines
  added and removed, how long it took, and its API value.
- **Intel** (`V`): what a cycle changed, file by file, as a coloured diff.
  Step through cycles with `[` `]` and files with `J` `K`.

## Snapshots and rollback

In a git repository, Fireteam snapshots the project before and after every
cycle: the whole working tree, untracked files included and ignored files left
out, as commits under hidden refs (`refs/fireteam/<id>/`). They're built in a
throwaway index, so your index, branches, stash, and history never see them;
`git log` and `git status` look exactly as before. Standing an operation down
deletes its refs.

From the intel view, **Roll back to before cycle N** puts every file in the
repository back as it was when that cycle started, including changes you made
since, so it asks first. The state it replaces is snapshotted, and **Undo
rollback** brings it back. Projects that aren't git repositories still get
cycle cards, but no diffs or rollback.

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

## The board

- **Look**: a near-black ground tinted toward your Omarchy accent, pale ink,
  and the accent as the one signal colour, so a theme switch re-tints the
  whole board live. Callsigns, figures and logs are set in Martian Mono, and
  everything you read in Red Hat Text.
- **Insertion**: deploying an operation plays a short insertion screen (the
  codename and a radio call, typed in). The agent is already on its way; any key
  or click skips it.
- **Activity pulse**: each deployed operation shows a small oscilloscope of
  how much its agent is saying and doing, a quarter second per bar.
- **Reactive backdrop**: a quiet survey of contours and dust; embers rise faster the more agents are deployed. A
  finished cycle throws sparks from its operation, a finished operation sends
  a wave up the screen, and a failure flares red.
- **Theatre map** (`M`): base camp in the middle and each project as a site at
  its own bearing on a generated survey map, with every operation pinned there. Deployed operations
  pulse and are linked to camp; click one to select it.
- **Sound** (`Shift+M`): short synthesized interface sounds for hovering,
  selecting, deploying, finishing, and failing. Off until switched on, and the
  choice is remembered. `bin/sounds` regenerates them.

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

## Squads

- **Worktrees**: in a git repository with at least one commit, an operation
  can deploy into a `git worktree` of its own, on branch
  `fireteam/<codename>-<id>` from your current branch's last commit, so
  several agents can work on one repository at once. Uncommitted changes
  aren't included. Worktrees live in `~/.local/share/fireteam/worktrees/`.
  **Extract** commits the work and merges the branch into whatever you have
  checked out; if it conflicts, the merge is undone and the conflicting files
  listed, never forced. **Discard** deletes the worktree and branch. Standing
  an operation down commits its work to the branch and keeps the branch.
- **Taking turns**: operations working in place in the same directory never
  run at once; the second waits for the first.
- **Squad size**: the `−`/`+` beside *Squad* in the header sets how many
  agents may be deployed at once (3 by default, up to 6, or ∞). Past that,
  operations are **staged** and deploy in order as slots open. `X` takes one
  out of the queue.
- **Usage limits**: the header shows your plan's five-hour and seven-day
  usage as Claude Code reports it. When a run hits the limit, its operation is
  **pinned down**, nothing else starts, and everything resumes on its own a
  minute after the reset, picking up the same cycle.
- **Loadouts**: saved sets of model, rules of engagement, cycles, hand-off
  line, worktree, and standing orders, picked at the top of the briefing.
  Recon, Standard, and Heavy come built in; *Save current* adds your own.
- **Standing orders**: instructions repeated in every cycle's prompt, such as
  "Run the tests before finishing".

## Field link

Every agent gets a field link back to camp: a small MCP server built into
Fireteam (`fireteam mcp`, started by Claude Code for each run) that talks to
the board over a local socket.

- **Sitreps**: the agent reports progress at milestones; the board shows a
  progress bar and a REPORT line in the comms.
- **Requests for orders**: when a decision is genuinely yours, the agent asks
  and waits. The operation turns red ("Waiting on you"), a radio call sounds,
  and a notification goes out. `A` opens the question with the agent's
  suggested answers as buttons, or type your own. Unanswered after 30
  minutes, the agent goes with its own judgement.
- **Supervised ROE** (the default): edits are free, and any other command not
  already allowed comes to you live, mid-cycle, while the agent waits:
  **Approve once**, **Always** (for this operation, as a rule), or **Deny**.
  Unanswered after 20 minutes, it's refused.

## Authorisation

Under restricted ROE, Claude Code refuses any command your permission settings
don't already allow. Fireteam catches each refusal as it happens:

- The comms show a `BLOCK` line, the operation gets an amber "requests for
  authorisation" banner and a roster badge, and a desktop notification goes
  out if you're elsewhere.
- If cycles remain, the operation **holds** after the cycle instead of running
  into the same refusal again.
- `A` opens the requests. Approve each with a suggested rule: the command
  family (`npm test …`, `git -C . rev-parse …`) or exactly that command.
  Chained commands are approved part by part, leaving out the parts that only
  read, since Claude Code checks each part on its own. Deny tells the agent
  to work without it.
- Approved rules are passed to every later run of that operation
  (`--allowedTools`), and the agent is told they're cleared. Tick "Also allow
  in this project" to add them to the project's `.claude/settings.local.json`
  as well, for every Claude session there. Rules can be added ahead of time
  and withdrawn from the same panel.
- **Approve all and resume** (`Ctrl+Enter`) sends a held operation back in.

Agents are asked to run one command at a time, so each can be approved on its
own.

## Rules of engagement

| ROE | `claude` permission mode | Meaning |
| --- | --- | --- |
| Supervised | `acceptEdits` + Fireteam's permission prompt | Edits files; anything else not pre-approved is put to you live |
| Restricted | `acceptEdits` | Edits files; other commands follow your Claude Code permission settings, and anything not pre-approved is refused |
| Weapons free | `bypassPermissions` | Runs any command without asking |

## Controls

| Key | Action |
| --- | --- |
| `Ctrl+K` | Command palette (actions, operations, quick deploy) |
| `I` | Inbox: everything waiting on you |
| `N` | Plan a new operation |
| `Space` | Deploy, resume, or redeploy (+1 cycle) the selected operation |
| `T` | Send orders to the selected operation |
| `H` | Hold after the current cycle, or lift the hold |
| `A` | Approve or deny commands the agent was refused |
| `E` | Amend the briefing of an operation that isn't deployed |
| `X` | Abort the selected operation |
| `↑` `↓` / `J` `K` | Move through the roster |
| `V` | Intel: the latest cycle's changes, file by file |
| `[` `]` / `J` `K` | In intel: previous or next cycle, and file |
| `/` | Search the comms |
| `P` | Field terminal (phone dashboard) |
| `F` | Field manual |
| `Shift+R` | Replay the operation |
| `Ctrl+F` | Search everything |
| `G` | Knowledge graph of the project |
| `C` | Campaigns |
| `S` | Service record |
| `M` | Switch between the board and the theatre map |
| `Shift+M` | Turn interface sounds on or off (off by default) |
| `R` | Read the latest debrief |
| `B` | Budget and schedule |
| `D` | Open the dossier |
| `O` | Open the project directory |
| `Del` | Stand down (remove) the operation; `Ctrl+Z` undoes it for a few seconds |
| `Ctrl+Enter` | Deploy from the briefing |
| `Esc` | Close a panel |
| `,` | Options and About |
| `?` | Show the controls |
| `Q` | Quit (asks first while agents are deployed) |

## Command line

Fireteam can be driven from a terminal or by another agent. Every command
takes `--json`, exits 0 on success and 1 on failure, and writes errors to
stderr.

```sh
fireteam list --json                       # every operation
fireteam show night-spire                  # sitrep, requests, reviews, debriefs, comms
fireteam plan --dir ~/Work/app --objective "Add CSV export with tests" \
  --cycles 3 --model sonnet --overwatch review --deploy
fireteam order night-spire "Use SQLite"    # add --deploy to send a finished one back in
fireteam hold night-spire                  # or abort, extract, discard
fireteam wait night-spire --timeout 3600   # 0 complete, 1 failed, 2 needs you
fireteam serve                             # run operations with no window
fireteam skill install                     # teach Claude Code to use all of this
```

An operation is named by codename (any case, dashes for spaces), id, or the
start of an id. Only one Fireteam runs at a time: the board or `serve` holds
the operations, and commands that need agents (deploy, hold, abort, extract,
discard) are handed to it through an inbox. Planning and orders work with
nothing running. A second `fireteam open` brings the running window forward.

## Campaigns

`C` opens the campaign board. Give a campaign one large objective, such as
"build a habit tracker with an API, a web UI and sync", and a planner (a
read-only Claude Code session; it changes nothing) surveys the project and
breaks the objective into 2 to 8 operations with dependencies.

The plan appears as a graph: one column per stage, supply lines from each
operation to the ones that build on it. Before anything runs, click a card to
change its codename, objective, cycles, model, or what it waits for (a plan
whose dependencies loop is refused), add or remove operations, or replan.
**Approve and deploy** turns the plan into operations with the rules of
engagement and overwatch you pick:

- Operations deploy as their dependencies finish; independent ones run in
  parallel, each in its own worktree, within the squad limit.
- A finished operation is **extracted automatically**, so the ones after it
  start from its merged work, and their first cycle is briefed on what came
  before (its objective, result, and debrief).
- A failure, or a merge that conflicts, **blocks** the campaign rather than
  pushing on; fix it, then **Resume campaign**.
- The campaign dossier links every operation's dossier and result.

Operations in a campaign carry its name (◆) on the board.

## Proof

Fireteam checks the work itself rather than taking the agent's word for it.

- **Gates**: the project's own checks, found from `package.json` scripts
  (with the package manager its lockfile names), `Cargo.toml`, `go.mod`,
  `bin/test`, a Makefile's `test`/`check`/`lint`, or Python tests. They're
  listed in the briefing to switch off or add to. Fireteam runs them after
  every cycle. A failing gate shows red on the cycle card, its output is one
  click away in the intel view, and the next cycle is told to fix it. An
  operation isn't done while a gate is red: it gets up to two more cycles,
  then it fails.
- **Acceptance criteria**: what "done" means, one per line in the briefing,
  or written by the campaign planner. The agent marks each as met over the
  field link, with its evidence. Overwatch then rules on each one, and its
  word stands over the agent's. The board shows open ○, claimed ◐, met ●,
  or not met ✕.
- **Preview screenshot**: give a start command (such as `npm run dev`) and an
  address. After each cycle Fireteam starts it, waits for the page, takes a
  screenshot with headless Chromium, then stops the server and everything it
  started. The screenshot goes on the cycle card and in the intel view.

## Field terminal

`P` turns on a small web dashboard for checking on operations from a phone:
the roster, each operation's comms, progress, gates and criteria; answering
questions; approving or denying commands (live or refused); sending orders;
and holding, resuming, or aborting. Planning and deploying new work stays on
the desktop.

- **Off** until you switch it on. Then it listens on this machine only, or,
  if you choose, on your local network (Tailscale included). It's plain HTTP,
  so use the network option on networks you trust.
- **Pairing**: scan the QR code (needs `qrencode`) or open the address shown.
  The pairing token rides in the address's fragment, which browsers never send
  to a server. The phone keeps it, and every API call needs it. **New code**
  unpairs every device.
- **Push alerts** (optional): give an ntfy topic URL, and alerts (an agent
  waiting on you, a failure, a finished operation) go there too. Use a
  hard-to-guess topic, or your own ntfy server.
- `fireteam serve` runs the terminal without the window.

## Institutional memory

- **Field manual** (`F`): after each finished operation, a short read-only
  haiku session (the after-action review) writes down what a future agent in
  that project should know: how to build and test it, setup it needs,
  conventions, and pitfalls. Lessons are kept per project in Fireteam's data,
  not in the project, and every new session there starts with them. Edit,
  delete, or add lessons. **Promote to CLAUDE.md** appends the ones you choose
  under a "Notes from Fireteam" heading, for your own Claude sessions too.
  After-action reviews can be switched off in the same panel.
- **Replay** (`Shift+R`): an operation's whole run, replayed from its comms on
  a timeline at 1× to 300×, with cycles and failures marked. Drag to scrub,
  and use `←`/`→` to step.
- **Archive**: finished operations can be archived off the board instead of
  stood down; *Show the archive* brings them back into view.
- **Search** (`Ctrl+F`): objectives, debriefs, hand-off briefs, reviews and
  every comms log on disk, across all operations, archived ones included.
- **Export**: an operation, or a whole campaign, as a single self-contained
  HTML report (debriefs embedded, screenshots inline) or a Markdown write-up
  ready for a PR description, saved in `~/Documents/Fireteam/`.

## Overwatch

With overwatch on (in the briefing), a separate read-only Claude Code session
reviews the operation after its last cycle: it reads the whole diff, judges
it against the objective, and grades it **pass**, **needs work**, or **fail**
with findings. The review goes in the dossier and on the operation's chip.
*Review and fix* sends a short-of-the-mark operation back for one more cycle
with the findings as orders, then reviews it again.

## Quick work

- **Command palette** (`Ctrl+K`): type to find any action, operation, or
  setting, with its key shown beside it. Type a request instead ("add CSV
  export to logbook") and the first result deploys it: Fireteam finds the
  project from a path or a project's name in the text, picks a codename, and
  uses your default loadout. `Shift+Enter` opens it in the briefing first.
- **Inbox** (`I`): every question, live permission and refused command across
  all operations in one list, triaged from the keyboard: `J`/`K` to move,
  `Enter` for the main action, `A` always, `D` deny, `O` to open the
  operation. The header shows how many are waiting.
- **Recipes**: ready-made objectives in the briefing (upgrade dependencies, add
  tests, fix the build, refresh the README, security pass, tidy up), each with
  acceptance criteria and a loadout. Save your own with *Save as recipe*.
- **Setup checklist**: on first launch, and from Options, Fireteam checks
  claude, git, graphify, Chromium, qrencode and the field terminal, with each
  fix in place.
- **Undo**: standing down an operation leaves the board with an Undo toast;
  nothing is deleted for eight seconds.

## Engines

Each operation runs on an engine you choose in the briefing: **Claude Code**
(the default), **Codex**, **Gemini CLI** or **OpenCode** (which also reaches
local models through Ollama or LM Studio). Fireteam finds whichever are
installed; Options lists all four with how to install and sign in.

- Comms, debriefs, gates, criteria, the field link and the knowledge graph
  work the same on every engine.
- Only Claude Code can ask you live for permission, so *Supervised* runs as
  *Restricted* on the others, and the briefing says so.
- Codex and Gemini CLI don't report cost; Codex and Gemini don't report
  context, so they don't hand off on it and rely on their own compaction.
- Overwatch can review on a different engine or model from the one that did
  the work (*Review with* in the briefing): a second opinion catches more.
- Loadouts carry an engine, and the campaign planner may route an operation
  to another installed engine when it suits.
- The service record totals operations, cycles and cost per engine.

## Limits, reading and comfort

- **Budgets** (`B`, or the budget chip): cap an operation at an API value, a
  share of the plan's 5-hour window, or both. At 80% of the API value it
  warns; at the limit it finishes the cycle it's on and holds. A campaign can
  have a budget across all its operations.
- **Scheduling** (`B`): deploy at a time, when the plan's usage window resets,
  or after another operation completes. A scheduled operation shows its
  time on the board.
- **Comms**: agent messages read as formatted text, runs of tool calls fold
  into one line you can open, and the current action stays pinned at the foot.
  The detail view is in tabs: Comms, Brief, Proof and History (`Ctrl+1`–`4`).
- **Reader** (`R`): debriefs, reviews and hand-off briefs open in the app,
  without their scripts, styles or network access, with find (`/`) and a
  reading size. The browser is one button away.
- **Comfort** (Options): reduce motion (no pulsing, drifting, turning or
  insertion screen), high contrast, and an interface size from 80% to 150%.

## Knowledge graphs

`G` maps a project's code as a survey of its files, built by
[graphify](https://github.com/Graphify-Labs/graphify) from the code alone:
locally, with no model and no API key. Each file is a square sized by the
symbols it holds, lines join files that lean on each other, and dashed rings
mark the communities they form. Files that operations changed are lit in the
accent, brighter the more cycles touched them; pick one operation under *Work
shown*, or press *Map* (`G`) on an operation, to see only its work. Click a file
for its symbols, the files it's linked to, and who changed it. Drag to pan,
scroll or `+` `-` to zoom, `0` to fit.

- **Hands on**: the map is a live simulation. Drag any file (or symbol) and
  what it's linked to follows on springs, then settles; *Shake* stirs it.
- **3D** (`3`): the graph in three dimensions. Drag empty space to orbit,
  scroll to zoom; it turns slowly on its own until you stop it. Nearer files
  are bigger and brighter, and the far side goes unnamed until you point at it.
- **Live**: while a cycle runs, every file its agent edits pulses with a ring
  and the operation's callsign, warm for half a minute after each edit.
- **Inside a file**: double-click a file (or select it and press `Enter`) for a
  map of its own symbols and the symbols elsewhere they reach; click one of
  those to step into its file, and `Esc` for all files again.
- **On the phone**: an operation's page in the field terminal shows the
  project's map, with that operation's files lit and live edits pulsing.

- The graph is kept in Fireteam's data folder, never in the project.
- A project is mapped when its first operation deploys, and the map is redrawn
  after each cycle in the project and after each extraction.
- Agents and campaign planners get a short brief: the hubs, the files that
  work together, and how to ask the graph more. They may run graphify's
  read-only `query`, `explain`, `affected`, `path` and `god-nodes` commands
  without asking.
- Without graphify, Options (`,`) installs it into a virtual environment in
  Fireteam's data folder, or install the `graphifyy` package yourself with uv
  or pip. *Map projects automatically* turns the automatic part off.

## Options and About

`,` opens Options: interface sounds, the insertion screen, backdrop motion,
squad size, the loadout a new briefing starts from, after-action reviews,
saved loadouts, knowledge graphs, the field terminal, and the data folder. The
About tab shows the version, the Claude link, what's installed, and credits.

## Service record

`S` shows totals across every operation: cycles run, success rate, lines
changed, time in the field, API value by week, the busiest projects, and
overwatch's verdicts.

## Languages

Fireteam follows the language picked in Omarchy (Setup > Language), live. It
ships in English, Danish, German, Spanish (Mexico), French, Portuguese
(Brazil), Japanese, Simplified Chinese, and Arabic (right to left); other
languages fall back to English. Catalogs are `src/i18n/<code>.json`.
`bin/strings` lists every string, and `bin/strings --check <code>` reports what
a catalog is missing and any translation that drops a placeholder.

## Build

```sh
bin/build     # build/fireteam
bin/test      # tests, offscreen, with a fake claude
bin/install   # package and install, so it shows in the launcher
```

## Credits

Fonts bundled in the binary: [Martian Mono](https://github.com/evilmartians/mono)
by Evil Martians and [Red Hat Text and Display](https://github.com/RedHatOfficial/RedHatFont)
by Red Hat, both under the SIL Open Font License (`src/fonts/OFL-*.txt`).
The visual language draws on the Terminal and Furrow themes of
[Hallmark](https://github.com/Nutlope/hallmark).
