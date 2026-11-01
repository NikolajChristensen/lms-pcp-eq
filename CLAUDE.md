# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Lyrion Music Server (LMS) plugin, in Perl, that serves a live 10-band
equaliser page for [piCorePlayer](https://www.picoreplayer.org) players.
Unlike piCorePlayer's own equaliser page (which only applies sliders on
*Test* and only persists them on *Save*), this plugin's page applies changes
while you drag the slider. There is no build step — the plugin runs as-is
inside LMS's Perl process. It talks to each player over the same HTTP
request pCP's own page sends (`cgi-bin/xtras_alsaequal.cgi`); nothing is
installed on the players themselves.

## Commands

```
tools/test-compile.sh                 # Perl syntax (Slim::* stubbed) + XML validity
tools/release.sh 0.1.1                # run tests, bump version, rebuild dist/*.zip, rewrite repo.xml
tools/release.sh 0.1.1 --publish      # ...then git commit, tag v0.1.1, push, and create the GitHub release
```

There are no per-module unit test scripts here (unlike the sibling `lms-drlive`
repo) — `test-compile.sh` is the only check, and it only verifies the module
loads and the XML parses, not runtime behaviour. To exercise the plugin for
real, load it into an actual LMS instance with a piCorePlayer player attached
and open `plugins/PcpEqualiser/index.html`.

### Releasing

`install.xml`'s `<version>`, and `repo.xml`'s `<version>`/`<url>`/`<sha>`,
must all move together — LMS downloads the zip named in `repo.xml`'s `<url>`
and rejects it if the sha1 doesn't match `<sha>`. `tools/release.sh` rewrites
all of them from one version argument and fails loudly if any didn't take;
don't hand-edit these three fields separately. `<changes>` in `repo.xml` is
not touched by the script — edit it by hand before releasing.

## Architecture

Everything lives in one module, `Plugins/PcpEqualiser/Plugin.pm`:

- Serves `plugins/PcpEqualiser/index.html` as a **page function**
  (`Slim::Web::Pages->addPageFunction`), not a static file — LMS caches
  static files under `html/` for a week, which would hide any update to the
  page.
- Two JSON routes back the page: `api/players` (read every connected
  player's current equaliser state, in parallel) and `api/set` (send new
  values, action `Test` or `Save` — exactly the two buttons on pCP's own
  page).
- State the plugin needs to remember itself, since pCP's page only reflects
  whatever is currently playing: `originals` (each player's values the first
  time the plugin ever saw it, so "Restore original" always has somewhere to
  go back to) and `saved` (the values last explicitly saved per player, so a
  player still playing unsaved changes from an earlier session can be shown
  as such). Both persist via `Slim::Utils::Prefs`, keyed by player id.
- `_readEq` parses pCP's equaliser HTML page with regexes (`name="R$n"`,
  `CUR_EQUAL_DEVICE`, the preset `<option>` list) rather than a proper HTML
  parser — pCP has no JSON API for this. Returns `no_eq` if the page is from
  a real pCP but the ALSA equaliser is switched off, `unreachable` if the
  player isn't a pCP at all or doesn't answer.
- `_numbers`: Perl stringifies a number the moment it's used as a string
  (e.g. interpolated into a log message), after which JSON::XS would encode
  it as `"66"` and the page's client-side arithmetic would treat it as text.
  Every value sent to the page is forced back through `_numbers` (`0 + $_`)
  right before encoding — the changelog in `repo.xml` for 0.4.1 names the bug
  this guards against (a slider could jump to 100 on first load / after a
  Lyrion restart).
- `_apiSet` validates fully before touching a player: unknown player id,
  wrong value count, any value outside 0–100, an action other than
  `Test`/`Save`, or a device name with unexpected characters all fail with a
  400 and no HTTP request sent.
- `PCPEQ_TEST_PORT` env var redirects `_pcpUrl` to a stand-in server for
  testing against something other than a real pCP player.

`backups/` (gitignored, not part of the plugin) holds ad hoc manual snapshots
of a real player's equaliser page taken before testing changes on it — a
safety net for the developer's own hardware, not a feature.

See the README for the full user-facing feature list (the dB scale, the
effective-response graph computed from the CAPS Eq10 filter math, the
unsaved-changes guard) and rationale.
