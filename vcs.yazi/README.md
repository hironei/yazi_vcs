# vcs.yazi

Unified Git/SVN status signs for [Yazi](https://yazi-rs.github.io/), with the
VCS kind auto-detected per directory. See
[`docs/requirements.md`](../docs/requirements.md) in the repository root for
the full specification.

**Status: Phase 1 (Status MVP) only.** Update, Commit, Diff, Log, Discard,
Push, and Branch/Switch are not implemented yet — see
[Roadmap](#roadmap) below. Don't install this expecting a full Git/SVN
client; today it only shows status signs and lets you refresh them.

## Requirements

- Yazi 26.5.6 or later
- `git` on `PATH` (any reasonably recent version; developed and tested
  against 2.x)
- `svn` on `PATH`, for SVN working copies (developed and tested against
  1.14.5)

## Installation (local development install)

This plugin is not yet published to a package registry. Copy or symlink
the `vcs.yazi/` directory into your Yazi plugins folder:

```bash
# Windows (Git Bash), PowerShell run as the same user:
# mklink /D "%APPDATA%\yazi\config\plugins\vcs.yazi" "C:\path\to\vcs.yazi"

# Linux / macOS:
ln -s /path/to/vcs.yazi ~/.config/yazi/plugins/vcs.yazi
```

## Setup

### 1. Register the fetcher (required)

Status signs are driven entirely by Yazi's fetcher mechanism (requirements
§8.7) — without this block, `vcs.yazi` never runs and nothing is shown, even
though `setup()` will have succeeded silently. Add to `~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_fetchers]]
id    = "vcs"
url   = "*"
run   = "vcs"
group = "vcs"

[[plugin.prepend_fetchers]]
id    = "vcs"
url   = "*/"
run   = "vcs"
group = "vcs"
```

(`id` can be dropped on Yazi newer than 26.1.22, matching the same note in
the official `git.yazi` plugin's README.)

### 2. Call setup

Add to `~/.config/yazi/init.lua`:

```lua
require("vcs"):setup()
```

Or with overrides (see [`config.lua`](config.lua) for every default):

```lua
require("vcs"):setup({
	signs = {
		conflict = "!",
	},
})
```

Status behavior can also be configured:

```lua
require("vcs"):setup({
	status = {
		aggregate_directories = false, -- do not roll file status up to parent directories
		ignore_externals = false,       -- include SVN externals in status queries
	},
})
```

ignore_externals affects SVN only; Git has no equivalent status option. Both
settings are merged recursively and explicit false values are preserved.

### 3. Keymap (manual status refresh)

Add to `~/.config/yazi/keymap.toml`. `v` is intentionally avoided as a
prefix — it's Yazi's built-in `visual_mode` key (requirements §19).

```toml
[[mgr.prepend_keymap]]
on   = [ "<C-g>", "s" ]
run  = "plugin vcs -- status"
desc = "Refresh VCS status"
```

## Status symbols

| Status | Default sign | Git | SVN |
|---|---:|---|---|
| Conflict | `C` | unmerged | conflicted (text or tree) |
| Missing | `!` | *(not distinguished from Deleted — see below)* | missing |
| Deleted | `D` | deleted | deleted |
| Replaced | `R` | renamed | replaced |
| Modified | `M` | modified | modified |
| Property modified | `P` | *(N/A)* | property changed, no content change |
| Added | `A` | added/staged | added |
| Untracked | `?` | untracked | unversioned |
| Locked | `L` | *(N/A)* | locked (a `<lock>` element in `svn status --xml`) |
| External | `X` | *(out of scope)* | external — **not empirically verified**, see Known limitations |
| Ignored | `I` | ignored | ignored |
| Clean | ` ` (blank) | — | — |

Every status has a distinct display priority (highest wins when a
directory rolls up multiple descendant statuses): Conflict > Missing/Deleted
> Modified/Replaced/Property-modified > Added/Untracked > Locked/External >
Ignored > Clean. Missing-vs-Deleted, Modified-vs-Replaced-vs-Property, and
Added-vs-Untracked orderings within a tier are implementation decisions —
the source spec doesn't rank them further.

## Git vs. SVN differences this plugin surfaces

- Git has no distinct "Missing" state — a file removed outside of `git rm`
  shows the same as any other worktree deletion (`Deleted`). SVN
  distinguishes `missing` (removed outside `svn rm`) from `deleted`
  (`svn rm`'d, pending commit).
- SVN can report a file as changed purely in its **properties**, with no
  content change (`Property modified`); Git has no equivalent.
- SVN reports a **repository lock** as a `<lock>` XML element, not a status
  keyword — a file can be `Locked` while otherwise clean.
- Neither backend recurses into a directory that is entirely untracked or
  ignored by default; both report it as a single row instead. Git signals
  this with a trailing `/` on the path; SVN gives no such signal, so this
  plugin does not attempt the same ancestor bookkeeping for SVN that it
  does for Git (see `backend-svn.lua`) — this is a known scope
  simplification, not a bug, since SVN's own non-recursion already avoids
  the runaway-listing problem that bookkeeping exists to prevent on the
  Git side.

## Known limitations (Phase 1)

- **`External`, `Obstructed`, and `Incomplete` SVN states are grounded only
  in `svn help status`'s documented status-letter table, not reproduced
  against a live working copy.** Everything else in `backend-svn.lua` was
  captured from real `svn status --xml` output — see the comment at the
  top of that file for exactly what was and wasn't verified.
- Property-modified's priority tier (same as Modified/Replaced) is an
  implementation decision; the source requirements document doesn't rank
  it.
- Update, Commit, Diff, Log, Discard, Push, Branch, and Switch are not
  implemented — Phase 1 is status display and manual refresh only.
- Windows/WSL/Git Bash cross-environment path translation for external
  tools (requirements §22) doesn't apply yet, since no external tool
  integration exists in this phase.

## Roadmap

See `docs/requirements.md` §29 for the full phase breakdown:

- **Phase 2**: Update, Commit, CLI Diff, CLI Log, Discard changes
- **Phase 3**: Git Push, Branch (list/create/rename/delete), Switch
- **Phase 4**: External Diff/Log (Beyond Compare and others), Windows GUI
  tool integration, WSL path translation

## Testing

Pure logic (path handling, root detection, status classification, and both
backends' output parsers) lives in files with no Yazi API references, so it
can run under a plain `lua` interpreter — see the top-of-file comments in
`core-path.lua`, `core-status.lua`, `core-detector.lua`, `backend-git.lua`,
and `backend-svn.lua` for which parts of each file are (and aren't)
Yazi-independent.

```bash
cd vcs.yazi
lua tests/run.lua
```

The suite includes fixture-based unit tests plus two integration tests that
shell out to a real `git`/`svn` binary if one is on `PATH` (skipped
otherwise) — they build a throwaway repository/working copy and check the
parser against genuine CLI output.

## License

MIT — see [LICENSE](LICENSE).
