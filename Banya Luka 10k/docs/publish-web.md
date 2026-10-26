# Publishing to the web

`rive <project-dir> --publish=web` builds the project, signs it, and puts it
on the web as a page anyone can open — one url playing the built `.riv`, with
nothing to host yourself.

```bash
rive login                         # once per machine: same session as --publish
rive myproject --publish=web       # build, sign, upload, wait for it to go live
```

```
published my-scene
https://my-scene-k2f9qa.pages.rive.app
```

This is the only command that produces something a person outside your account
can look at. It is *not* the authoring preview — that is `rive <project-dir>`,
a window that rebuilds as you edit — and it is not `rive push`, which sends the
project to a Rive file in your account.

## A page belongs to a team

Pages hang off a team, never off your personal files. An account whose only
workspace is its own drafts has nowhere to publish to, and says so; create a
team in the editor, or ask to be added to one.

- with a single team, it is picked automatically
- with several, the CLI opens a picker: up and down move, typing narrows,
  enter chooses, escape backs out
- where no picker can draw (`TERM=dumb`, `RIVE_NO_TUI=1`) it falls back to a
  numbered prompt
- with stdin not a terminal, as in CI, it lists the teams and exits, so
  scripted runs stay deterministic
- `--team=<id>` skips all of that

## The name is the page

A page is identified by its name within the team. The name is lowercased into
a slug — everything outside `a-z0-9` becomes a dash — and the url is that slug
plus a short random suffix minted once, when the page is created.

Publishing the same name again **replaces what the url serves**. The url does
not change, so a link you handed out keeps working and starts showing the new
build. Publishing a different name creates a different page at a different url.
The one exception is a page that has expired; see below.

By default the name comes from the project's `name` in `rive.yaml`;
`--name=<name>` overrides it. `www`, `api`, `player`, `hosted` and `pages` are
reserved.

The binding is recorded in `rive.yaml` after the first publish:

```yaml
pages:
  teamId: 77
  name: "my-scene"
```

Only the first publish writes it, the same way `rive push` binds a file once.
Commit it, and everyone publishing the project updates the same page. A later
`--name=<name>` is a one-off — it publishes elsewhere without retargeting the
project; edit the block to move it for good, or delete it to be asked again.

## Pages can expire

On some plans a page only stays up for a while after its first publish. When
it has a date, the publish says so on its first line, in your own time zone:

```
published my-scene (expires 4 Oct)
https://my-scene-k2f9qa.pages.rive.app
```

Republishing a live page keeps its date. Once a page has expired, its url
stays offline and its name frees up, so publishing the name again makes a
**new page at a new url**.

## Waiting, or not

The upload returns before the page is live: the api hands the work to a
background job, and the CLI polls it. Until the job finishes, the url keeps
serving whatever it served before — a republish never leaves the page broken
in between.

`--no-wait` prints the url and exits as soon as the upload is accepted, which
is what a CI job that does not need the confirmation wants. With `--quiet`,
stdout is two lines, the name (and its expiry, if it has one) and then the
url:

```bash
url=$(rive myproject --publish=web --no-wait --quiet | tail -1)
```

What `--list-published=web` can tell you afterwards is narrower than it
looks: it reports `publishing` until a page's *first* publish finishes and
`published` from then on, including while a republish is still running. So it
answers "has this page ever gone live", not "did the publish I just started
land". For that, open the url.

## The page's controls

A published page carries a small bar of controls, for its fit, full screen
and copying its url, that shows for a moment and then hides to a lip at the
bottom of the page. `--drawer=<mode>` changes how it starts:

| Mode | The page |
|---|---|
| `docked` | keeps the bar out |
| `hidden` | starts with just the lip |
| `none` | has no bar at all |

Each publish sends its own mode, so one without `--drawer=` goes back to the
default; pass it every time, the same way as `--no-wait`. Visitors can still
dock, hide or remove the bar whatever the page starts with.

## Listing and taking down

```bash
rive myproject --list-published            # where is this project published?
rive myproject --list-published=web        # every live page on the team, with its url
rive myproject --unpublish=web             # take the project's page down
rive myproject --unpublish=web --name=prototype   # by name, or by the full page id
```

```
  my-scene   published   https://my-scene-k2f9qa.pages.rive.app
  prototype  publishing  https://prototype-8h2mza.pages.rive.app
```

`publishing` is a page whose *first* publish has not finished; a page that has
been live once reads `published` even mid-republish. `--unpublish=web` asks
first unless `--yes` is passed, and there is no undo: the url stops resolving,
the files are removed, and the name frees up. Publishing that name again mints
a *new* url — the old link does not come back.

### Where is this project published?

`--list-published` (no target) prints one row per target, `local` then `web`,
so it always answers something even for a project that has never gone
anywhere:

```bash
rive myproject --list-published
```

```
  local  built          myproject/build/hello_rive.riv
  web    not published
```

`built` means the file is on disk, not that it is signed — `--once` writes
the same path as `--publish=local`, so a `built` local row can still be an
unsigned build.

`web` reads `not published` when there is no page to read: either the project
has no `pages:` binding in `rive.yaml`, or the page that binding names is not
among the team's. A page that *is* found reports its own state instead —
`publishing` while its first publish is still running, `published` once it is
live — so `not published` means no page was found, never a page mid-publish.

When the web row cannot be determined, it prints `unknown` instead:

```
  local  built    myproject/build/hello_rive.riv
  web    unknown
```

The reason is printed on stderr. The command exits 0 if every row is determined,
or with one of the following codes if any row is `unknown` or if an error occurs:

| Exit | Reason |
|---|---|
| 0 | every row determined |
| 1 | most failures: forbidden (403), permission denied, rate limited (429), server errors, or anything unexpected; also when the directory is not a Rive project |
| 3 | not logged in, or the stored login was rejected; also network failures while renewing an expired token |
| 7 | after login is established, a service could not be reached — safe to retry |

A project with no `pages:` binding exits 0 even if the web service is unreachable,
because there is nothing to determine — it is certainly not published.

`--list-published=web` works outside a project directory as long as
`--team=<id>` is passed; `--unpublish=web` also requires `--name=<name>`.
Bare `--list-published` does not — it needs the project, because the project
is the thing being asked about.

## Scripts are signed

A page is played by a web runtime, and web runtimes refuse unsigned scripts —
an unsigned build would load and then play nothing. So `--publish=web`
always builds the way `--publish` does: scripts compiled and signed
server-side, which is why it needs a session even for a project you could
otherwise build offline.

The same watermark rule applies as `--publish`. A project with no `push.fileId`
in `rive.yaml` has nothing for the API to attribute the publish to and is
watermarked whatever the plan; `rive push` binds the project to a file and
takes the watermark off. See [publishing.md](publishing.md).

## When something goes wrong

| Message | Meaning |
|---|---|
| `Not logged in` | no working session here, whether you never signed in, the token expired, or the api rejected it; run `rive login` |
| `no team to publish to` | the account has no team, only personal files |
| `no team to publish to: check --team=<id>` | the team id is wrong, or you are no longer a member |
| `publish aborted: build failed` | fix the build first; `rive <dir> --verify` shows the problems |
| `"<name>" is reserved` | pick another `--name` |
| `Invalid page name` | the api refused the slug; usually too long |
| `publish failed: Upload missing` | the upload did not survive to the job; publish again |
| `too many publishes for now` | the per-account rate limit for publishing; the message names the wait when the api does |
| `the publish has not finished after 300s` | the job is stuck or slow; open the url to see what the page is serving |
| `deleting a page stops its url resolving; rerun with --yes` | no terminal to confirm on: CI, `RIVE_NO_TUI`, or stdin not a tty |
| `your role on that team cannot see its pages` | you lack read permission on that team (applies to `--list-published`, `--list-published=web`) |
| `too many requests for now` | read rate limited; the message names the wait when the api does (applies to `--list-published`, `--list-published=web`) |
| `--team= applies to --publish=web, --unpublish=web and --list-published=web` (or `--name=`, `--drawer=`, `--no-wait`, `--yes`) | that flag does not apply to the publish mode you asked for |
| `unknown drawer "<mode>"; use docked, hidden or none` | `--drawer=` takes only those; nothing was built or uploaded |
| `--optimize and --define= apply to a build, not to --unpublish or --list-published` | those tune a build, and neither of those commands builds anything |
| `page listing has no pages array` | the api answered 200 with something that is not a page listing; usually a proxy or a sign-in portal answering in its place, so check the network before the CLI |

Publishes are rate limited per account — a few an hour is fine, a build loop
publishing on every save is not.

`--list-published=web` needs only view access on the team; `--publish=web`
and `--unpublish=web` need write.
