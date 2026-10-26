# Building and publishing

| Mode | Produces | Needs a login |
|---|---|---|
| `--verify` | nothing; compiles and reports | no |
| *(no flag)* — live window, watches for edits | an unsigned `.riv` on every change | no |
| `--once` | an unsigned `.riv` | no |
| `--publish` | a **signed** `.riv` on disk | **yes** |
| `--publish=local` | the explicit synonym of the bare form above | **yes** |
| `--publish=web` | a hosted page: build, sign, upload | **yes** |
| `--unpublish=web` | takes a hosted page down | **yes** |
| `--list-published` | where this project is published, local and web | no\* |
| `--test` | runs the `Tests` scripts | no |
| `--screenshot` | a png of one frame, rendered headless | no |

\* `--list-published` reads the API only if the project already has a
`pages:` binding — an unpublished project answers entirely from disk and
exits 0. When the project does have a `pages:` binding, a failure to read the
web row causes `--list-published` to exit non-zero and print the reason to stderr.
`--list-published=web` always needs a session: it asks for the team's live
pages, not this project's.

The build modes are mutually exclusive — pick one. Running with no flag is the
default: it opens the live window and rebuilds as you edit.

Only handing the work on needs a session: `--publish` to ship it, `--rev` and
`rive push` to pass it to the editor. The session is checked live, so those
fail offline even with stored credentials.

## Which one you want

**`--verify` while authoring.** Full local compile — RML, Luau, WGSL — writing
nothing. It is the fastest loop, so it is what to run after every edit. See
[luau/protocols.md](luau/protocols.md#checking-a-script).

**`--once` for a local `.riv`.** The file plays in the CLI's own window and in
any runtime built with tools enabled. It is *unsigned*.

**`--publish` when the file ships.** Same build, but the scripts are compiled
server-side and signed.

### Signing in

`--publish` and `--rev` require a signed-in session:

```bash
rive login
```

That opens a browser to authenticate, and the session persists — you do it once,
not per build. `rive whoami` shows who you are signed in as, `rive logout`
clears it.

Signing is a separate matter from the session. Watch and `--once` build
**unsigned**, and the live window plays unsigned scripts without complaint —
so watching a file tells you nothing about whether it is shippable. Only
`--publish` signs.

Without it, `--publish` stops before sending anything and writes no file.
Somewhere a browser login is not possible — CI, a container, an automated agent
— every other mode still works, so you can author, build, test and capture.
Handing the work on, with `--publish` or `--rev`, has to run somewhere signed
in.

Credentials live outside the project — `~/.config/rive/app.rive.cli/` on
macOS and Linux, Credential Manager on Windows. A process with a different
`HOME` or user reports `Not logged in` even on a machine where you *are*
signed in, which is the usual reason an automated run fails when the same
command works in your own shell.

## Why signing exists

**A `.riv` whose scripts are unsigned is rejected by the CDN and the web
runtimes.** Nothing local tells you this: the CLI's own viewer builds with
tooling enabled and plays unsigned files happily, so a project can look
finished, run correctly in front of you, and fail the moment it is served.

If a file contains scripts and is destined for the web, it has to be built with
`--publish`. If it has no scripts, the distinction does not arise.

## What `--publish` does

1. Compiles locally first — syntax errors and WGSL problems still stop the
   build before anything is sent.
2. POSTs the rewritten Luau and WGSL to Rive's compile service and polls for
   the result.
3. Writes the returned bytecode plus a 64-byte aggregate signature into the
   built file.

It overwrites the same `build/<name>.riv` that `--once` would produce, so the
output path does not change.

**It fails closed.** Auth failure, network failure, or a timeout means no file
is written — you never get a silently-unsigned build from a publish that went
wrong.

Two caps, both hard:

| Limit | |
|---|---|
| 100 scripts | more is an error, not a truncation |
| 10 MB request | the compiled payload total |

A project with **zero** scripts skips the service entirely and writes an
unsigned `.riv`, which is correct — there is nothing to sign.

## Exporting for the editor

`--rev=<path>` attaches to `--once` or `--publish` and writes a `.rev` alongside
the build:

```bash
rive myproject --once --rev=myproject.rev
```

The `.rev` is always unsigned source — it is the editable document, not a
runtime artifact — so signing has no bearing on it. It does need a session,
though: a `.rev` is the handoff into the editor, the same artifact
`rive push` delivers, so exporting one requires `rive login`. The window's
**File ▸ Export .rev…** is the same thing by another route and asks for the
same session.

`--rev` rides on `--once` or `--publish`. It does not combine with
`--verify`, which by design writes nothing, nor with `--test`,
`--screenshot` or `--semantics`, which exit before the export.

Before handing a multi-artboard file to the editor, give each artboard an `x`
and `y`: that is its stage position, and artboards without one all land on
the origin. See [format.md](format.md#document-structure).

## Pushing to a Rive file

`rive push` skips the on-disk `.rev` entirely: it builds and sends the document
straight to a Rive file in your workspace, so the project opens from the
editor's file browser with a revision history.

```bash
rive login                        # once: same session as --publish
rive push                         # first push: creates the file, later
                                  # pushes update it
```

The first push creates the file (picking or prompting for a project) and
records it under `push:` in `rive.yaml`; every later push replaces its content
and adds a named entry to the revision history. [push.md](push.md) has the
full story.

`push`/`pull` move the *source document* between the CLI and the Rive editor,
for round-trip authoring with revision history; publishing ships the *built
artifact* to consumers. Different destinations, different things travel.

## Publishing to the web

```bash
rive myproject --publish=web      # build, sign, and host it at a url
```

Same signed build as `--publish`, uploaded to a page anyone can open — no
account needed to view it. Unlike `--rev` and `rive push`, which hand over the
editable document, this ships the built artifact: a url that plays, not a
project that opens.

The page belongs to a team, and its name identifies it: publishing that name
again replaces what the url serves. `--list-published=web` shows every live
page on the team, and `--unpublish=web` takes one down.
[publish-web.md](publish-web.md) has the full story.

## Scripting the one-shots

Exit codes are typed, so a pipeline can branch without parsing stderr:

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | build errors, or any failure without a more specific code |
| 2 | bad command line |
| 3 | not logged in, or the session was rejected |
| 6 | test cases failed (the build itself was fine) |
| 7 | a service could not be reached — safe to retry |
| 8 | this CLI is below the published minimum — run `rive update` |

Except when an outdated CLI exits 8 before command dispatch, `--format=json`
on `--once`, `--verify`, `--publish` or `--test` prints one JSON envelope
on stdout — `{"success", "command", "data", "errors", "warnings"}` — with
the problem list (script, line, message) or the test results (counts plus
each failure's group path) under `data`. Lines and columns are 1-based. Logs
stay on stderr, so stdout is only the envelope.

Without `--format=json`, `--publish` prints the file it wrote on stdout, so
the path can be taken the way `--publish=web` hands back a url:

```bash
path=$(rive myproject --publish --quiet | tail -1)
```

It prints nothing there when nothing was written — an output directory that
cannot be written to, say. The build itself still succeeded, so the exit code
is 0 and the reason is on stderr, which `--quiet` silences: test the path
rather than the status.

```bash
[ -n "$path" ] || { echo "nothing was published" >&2; exit 1; }
```

`rive doctor [dir]` checks the environment those commands assume: version and
pending updates, the session, the live-link port, and the project's
`rive.yaml`. It exits 1 only when a check hard-fails, and takes
`--format=json` too.

## In short

```bash
rive login                              # once, for --publish, --rev, push

rive myproject --verify                 # compile check           (no login)
rive myproject                          # live window             (no login)
rive myproject --once                   # a local .riv            (no login)
rive myproject --publish                # the one you ship        (login)
rive myproject --once --rev=out.rev     # plus an editable .rev   (login)
rive myproject --publish=web            # host it at a url        (login)
rive myproject --list-published         # where is this published (login if web-published)
rive doctor myproject                   # is the environment sane (no login)
```
