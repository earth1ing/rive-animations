# Pushing a project to a Rive file

`rive push` builds the project and sends the result straight to a Rive file in
your workspace — no `.rev` on disk, no drag and drop. The file opens from the
editor's file browser like any other, and every push lands as a named entry in
its revision history, so any push can be inspected or restored from the
editor's revision panel.

```bash
rive login              # once per machine: same session as --publish
rive push               # build and push; the first push creates the file
```

## Starting from a file that already exists

Work that is already in Rive does not have to start over as a new project:

```bash
rive create --from-remote-file            # pick a project, then a file
rive create hero --from-remote-file=24227 # or name both
```

To find the id without a picker (an agent, or a script), list the account:

```bash
rive workspace             # the current workspace, and the ids of the others
rive workspace 408         # switch; your personal workspace until you do
rive ls                    # browse the workspace's projects (a terminal)
rive ls --plain            # the same, printed as a table
rive ls 5336               # that project: its folders, then root files
rive ls 5336 8061          # folder 8061 of project 5336
rive ls 5336 --all --json  # every file in it, one JSON object a line
rive open 24227            # open that file in the editor
```

Every row names its kind (`project`, `folder`, `file`) and its id; the JSON
keys are `projectId`, `folderId` and `fileId`, the ids the flags here take.

This downloads the file and converts it the way `--from-rev` converts a `.rev`
off disk: `scene.rml`, with every script and asset as a file laid out as the
Assets panel. The directory has to be empty or new; without one, the remote
file's name is used.

The command first tries to download the file's live content from the change log, matching
the state the editor shows. If the change log is unavailable, it receives the same live
content from the sync server, the way `rive push` does. If that fails too, it falls back to
the newest saved revision. Binary assets — images, fonts, audio — are fetched from the asset store, 
since the editor keeps their bytes outside the document itself.

The link to the file is recorded in `rive.yaml` exactly as a first push would
record it, so `rive push <dir>` sends your edits back to it, and
`rive pull <dir>` brings later editor changes down. `--from-remote-file` itself
always writes a new directory; use `pull` to refresh one that exists.

Because what you get back is meant for a push, the picker lists the projects
`rive push` lists — the ones you can write to. Naming a file id skips the
picker and pulls any file you can open, view-only projects included.

## Pulling it back down

`rive pull` is the inverse: it downloads the file the project is linked to and writes it over
the project.

A project gets that link two ways. The first `rive push` creates the file and links it, and
`rive create --from-remote-file` links the file it started from. Either way `rive pull` works
from then on, and a project with no `push:` block is told to use one of the two.

```bash
rive pull            # asks before overwriting
rive pull --yes      # skip the prompt (required in CI, an agent's shell,
                     # or anywhere with no terminal)
```

`--quiet` drops the download line and the "already matched" count, leaving only
what changed.

It rewrites the scene markup and every script, shader and asset the remote file holds, and
reports what changed:

```
downloaded 12084 bytes from changelog at 157, 3 assets
pulled file 24227 into demo
  scene.rml           updated
  ui/button.luau      updated
  images/logo.png     added
  (4 files already matched)
```

What the remote holds wins — local edits to those files are lost, which is why it asks first.
`rive.yaml`, `AGENTS.md`, `CLAUDE.md` and anything you added yourself are left alone, and a
file whose bytes already match is not rewritten at all, so an unchanged pull will not wake the
watcher.

Files that are in the project but *not* in the remote file are listed rather than deleted:
nothing can tell an asset the editor dropped from one you added on purpose. Keep the project in
source control and the whole overwrite is reviewable as a diff.

## The first push

A file lives in a folder of a project, so the first push asks where to put
it. On a terminal it opens the browser `rive ls` uses, on the projects of
the workspace you are in:

```
Rive (408)
  switch workspace…              now Rive (408)
  Personal Files/                project 2881
  Characters/                    project 5336
```

Arrows move, enter or right opens a project and then its folders, left or
backspace goes up, typing narrows the list, and escape cancels the push.
Every level offers **`choose this folder`** as its second row, and that is
what creates the file. A project's own root is a destination like any
folder, named `the project root`.

Only projects you can write to are listed, your personal files first, and
no files at all, since a file is not somewhere a file can go. A project in
another workspace is reached through `switch workspace…`, which is
remembered the way `rive ls` remembers it, so the next `rive ls`,
`rive workspace` or `rive push` starts in the new one.

Name the destination instead, and nothing is asked:

```bash
rive push --project=5336               # the project's root
rive push --project=5336 --folder=8061 # a folder in it
```

`rive ls` prints both ids, and `--folder` on its own is an error, since a
folder id alone does not say which project holds it.

Where no browser can draw, naming it is the only way through. CI, a pipe,
an agent's shell, `TERM=dumb`, `RIVE_NO_TUI=1` and a window too short all
stop with that message rather than creating somewhere you did not choose.
So does a redirect of any of the three streams, `rive push > log`
included, since a browser needs a terminal on each of them.

The link to the created file is recorded in `rive.yaml`:

```yaml
push:
  projectId: 5336
  fileId: 24227
```

Commit this so everyone pushing the project updates the same file. Delete the
`fileId` line (or the whole block) to make the next push create a fresh file;
edit `projectId` to create it somewhere else. The folder is not recorded,
since the file keeps the one it was created in, so a file recreated this way
starts at the project root again.

## Every push after

A push to a file the project is already linked to asks first, because it
overwrites that file:

```
Pushing rive-cli project "two_shape_lib" will overwrite remote file 37611.
Proceed? [y/N]
```

`--yes` skips it, and is required wherever nothing can answer: CI, a
redirected terminal, `RIVE_NO_TUI=1`, or an agent's shell. The first push
does not ask, since it creates the file and there is nothing to overwrite.

A later push diffs the new build against the file's live content and sends
only what differs, then names a revision. A changed object is patched in
place and keeps its id; only an object that is gone, or that changed type, is
removed. An editor with the file open drops an object's children from its
session when the object is removed, and recreating the parent does not bring
them back. `--name` labels it —
useful when a push marks something:

```bash
rive push --name="before the terrain rewrite"
```

A push with nothing new reports `already up to date` and adds no revision.
The previous content is never lost: it stays in the revision history, and the
editor can restore any entry. If someone has the file open in the editor while
you push, they see the content swap live, like a collaborator's edit — and
any editor-made changes to pushed content are overwritten, the push is
authoritative.

## Ids stay stable

Logically-same things keep their coop object ids across pushes: an asset by
its module path, an artboard (and its layout graph) by its name, folders by
their path. That matters when the pushed file is used as a library — a
consumer's reference to a library component points at an object id in this
file, and renaming *other* assets or adding new ones does not move it. Ids do
change when the thing itself is renamed or moved (it reads as a new object),
and the internal code line/run tree is renumbered whenever a source file's
text changes.

## Sessions

Push uses the same `rive login` token as `--publish` and watermark, and so do
`rive create --from-remote-file` and `rive pull`. After the API started issuing
`cli:write` on new logins, anyone who signed in before that must run
`rive login` again — refresh does not upgrade an old token.

A 401 on `/api/me` or on opening the linked file means the session is
no longer accepted.

## What is pushed

Exactly what `--rev` would export: the project's own scripts, assets and
artboards, minus everything `excludeFromRev` drops. A library's content stays
out, because it belongs to that library's own file rather than to this one.
See [project/rive-yaml.md](project/rive-yaml.md#libraries).

## When something goes wrong

| Message | Meaning |
|---|---|
| `Not logged in` | no working session here, whether you never signed in, the token expired, or the api rejected it; run `rive login` |
| `file <id> is missing or not accessible` | the linked file was deleted or you lost access; clear `push.fileId` to create a new one |
| `not authorized for this file` | no edit permission on it, or the session is no longer accepted; try `rive login` |
| `push aborted: build failed` | fix the build first; `rive <dir> --verify` shows the problems |
| `<dir> already contains files` | `--from-remote-file` writes a whole tree, so it wants an empty or new directory |
| `has never been saved` | the file has no content to download; open it in the editor once |
| `asset <id> download failed` | an asset the file references is not readable by your account |
| `rive-cli project "<name>" is not linked to a remote Rive file` | the project was never linked; push once, or start it with `rive create --from-remote-file` |
| `... will overwrite ... Rerun with --yes to confirm` | `push` and `pull` both ask before overwriting, and there is nobody to ask: CI, `RIVE_NO_TUI`, an agent's shell, or no terminal |
| `a first push needs somewhere to create the file` | nothing here can browse, so name it: `--project=<id>`, and `--folder=<id>` for a folder in it |
| `--folder needs the project holding it` | a folder id does not say which project it is in; pass `--project=<id>` too, or set `push.projectId` |
| `could not create a file in folder <id> of project <id>` | usually a folder of some other project; `rive ls <projectId>` lists the ones it can take |

A failed push never half-applies: content changes only land once the server
has accepted every change set, and the revision entry is added after that.
