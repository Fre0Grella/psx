# psx

Named [psmux](https://github.com/marlocarlo/psmux) layouts for Windows PowerShell, with a
visual editor. Draw a workspace once, reopen it with one word.

```
psx new              draw a template
psx dev              build it in this folder and attach
psx ls               templates and running sessions
psx edit dev         change it
psx delete dev       remove it
psx kill dev         kill that session
psx -h               full usage
```

psmux has no templating of its own — there is no `save-session`, no layout file, no
tmuxinator equivalent. It is fully scriptable though, which is all this needs.

## The editor

`psx new` asks for a name, then opens the layout so you can see it:

```
┌───────────────────────────────────┬────────────────────────────┐
│                                   │            git             │
│                                   │     typed: git status      │
│            Claude Code            ├────────────────────────────┤
│            run: claude            │         dev server         │
│                                   │     typed: npm run dev     │
└───────────────────────────────────┴────────────────────────────┘
```

| key | does |
|---|---|
| arrows (or `hjkl`) | move between panes |
| `\` | split side by side |
| `-` | split top and bottom |
| `enter` | choose what runs in this pane |
| `x` | delete the pane |
| `[` `]` | resize |
| `f` | this pane is focused when the session opens |
| `d` | description |
| `w` / `q` | save / quit |

`\` and `-` are deliberate: neither needs Shift, and they match the split bindings in
`~/.psmux.conf`.

## What can go in a pane

Claude Code, a plain shell, htop, ssh (asks for the host), `git status`, npm dev/build,
pytest, Jupyter, or a custom command. Programs you do not have installed stay in the list,
greyed out and labelled — hiding them would look like psx did not support them.

Every command is either **run** or **typed**:

- **run** — `send-keys "<cmd>" Enter`, starts immediately. Right for Claude Code, htop, ssh.
- **typed** — `send-keys "<cmd>"`, waits on the prompt for you to press Enter. The safer
  default for anything that builds, watches, or assumes a particular project — `npm run dev`
  in a repo with no `package.json` should not just fire.

## Install

Requires [psmux](https://github.com/marlocarlo/psmux) (`winget install marlocarlo.psmux`) and
PowerShell 7.

```powershell
git clone https://github.com/Fre0Grella/psx.git $HOME\psx
```

Or unzip a build from [Releases](https://github.com/Fre0Grella/psx/releases) into `$HOME\psx`.

Then add to your PowerShell profile (`$PROFILE`):

```powershell
function psx { & "$HOME\psx\bin\psx.ps1" @args }
```

Open a new terminal. First run copies the starter templates into `~/.psx/templates`.

## Where things live

| | |
|---|---|
| `~/.psx/templates/*.json` | your templates — plain JSON, hand-editable |
| `templates/` in this repo | starter templates, copied in only when missing |

Updating psx never touches your templates. Editing `dev` and then pulling keeps your version.

## Shorthand

Nothing needs Shift, and verb order does not matter:

```
psx ls      psx l      psx -l
psx edit dev    psx e dev    psx dev e
psx kill dev    psx k dev    psx dev k    psx dev -k
```

Short flags are explicit aliases rather than PowerShell's prefix matching, because `-l`
would otherwise be ambiguous and refuse to bind.

Options: `-p <dir>` build elsewhere, `-n <name>` session name (default: the folder name),
`-d` build without attaching.

## Development

```powershell
pwsh -File tests\run.ps1          # model, geometry, render, store, editor keys
pwsh -File tests\e2e.ps1          # builds a real session on an isolated socket
pwsh -File tools\preview.ps1 dev  # print a template as the editor draws it
```

The layout model, geometry and renderer are pure functions returning strings and
hashtables, so almost everything is testable without a terminal; only the input loop
touches the console. `e2e.ps1` runs against `psmux -L psxe2e`, its own server, so it can
never disturb a session you are using.

## Notes on psmux 3.3.7

Things found by testing rather than by reading the docs:

- **Pane indices are off by one.** Index lookup ignores `pane-base-index`, so with
  `pane-base-index 1` the target `:1.1` resolves to the *second* pane and the first is
  unreachable by index. psx uses stable pane ids (`%1`, `%2`) everywhere.
- **An invalid pane target is not an error.** psmux falls back to the *active* pane, so a
  bad target shows up as commands landing in the wrong place rather than as a failure.
  `Invoke-PsxBuildPlan` validates every id it resolves.
- **Keys sent to a shell that is still starting are silently lost.** A fixed sleep is not
  enough — it only covers the first pane, so the last pane created reliably came up empty.
  psx polls each pane for a rendered prompt instead.
- `--help` claims `base-index` defaults to 1; the running server reports 0.
- The plugin docs advertise `psmux-yank`, which does not exist in the plugin repo.
- The logging plugin's README lists the wrong keys — the real ones are `prefix + Alt-o`
  (toggle), `Alt-p` (screenshot), `Alt-i` (history).
