# Player Equaliser for piCorePlayer

A live 10-band equaliser page in Lyrion Music Server for your
[piCorePlayer](https://www.picoreplayer.org) players. Made for tuning a
player to its room by ear: stand in the room with your phone, move a slider,
hear the change.

- Changes play **while you drag**. On piCorePlayer's own page, nothing changes
  until you press *Test*.
- **Save** keeps the settings over a restart; **Reset** goes back to the last
  saved settings. The plugin remembers what was last saved itself (pCP's page
  only knows what is playing), so a player still playing unsaved changes
  from an earlier session is shown as such. The page shows when there are unsaved changes, draws the
  saved curve behind the one you're editing, and asks before you switch
  player or close the page with unsaved changes.
- Values are shown in dB (one step is 0.72 dB; flat is pCP's default of 66),
  with −/+ buttons for fine steps. Tap a band's dB value to set it to 0 dB;
  *Flat* sets all bands to 0 dB.
- Sliders only move when you **drag the handle**: tapping the track does
  nothing and swiping up or down scrolls the page, so a stray touch can't
  change the sound.
- A graph of the equaliser's **actual effect**, computed from its filters
  (CAPS Eq10: ten overlapping bandpass filters added together), with the
  slider settings as dots. Neighbouring bands overlap, so a band's effect is
  wider and usually smaller than its slider: a −8 dB cut at 125 Hz, for
  example, lowers that region by about 3 dB. While you have unsaved changes,
  the saved curve is shown dotted behind it.
- **Restore original**: the first time the plugin sees a player, it records
  that player's equaliser settings, so you can always go back to them (then
  press Save to keep them).
- pCP's presets (from `/home/tc/.alsaequal.presets` on the player) can be
  applied with one tap.

## Requirements

- Lyrion Music Server 8.0 or newer
- piCorePlayer players with the equaliser switched on (pCP: *Tweaks →
  Use 10 band ALSA equalizer*)
- If you set a password on pCP's web interface, the plugin can't reach it
  (not supported yet).

Nothing is installed on the players. The plugin sends the same requests as
pCP's equaliser page (`cgi-bin/xtras_alsaequal.cgi`), only to players
connected to your Lyrion server, with values limited to 0–100.

## Install

In Lyrion: **Settings → Plugins → Additional Repositories**, add

```
https://raw.githubusercontent.com/NikolajChristensen/lms-pcp-eq/main/repo.xml
```

then enable **Player Equaliser** and restart Lyrion.

## Use

Open `http://<your-lms>:9000/plugins/PcpEqualiser/index.html`; on a phone,
bookmark it or add it to the home screen. It's also the plugin's *Settings*
link under Settings → Plugins, and appears under *Extras* in the classic web
interface.

## Development

```
tools/test-compile.sh                 # Perl syntax (Slim::* stubbed), XML
tools/release.sh 0.1.1                # bump, build zip, rewrite repo.xml; nothing published
tools/release.sh 0.1.1 --publish      # ...then commit, tag, push and create the GitHub release
```

## License

MIT, see [LICENSE](LICENSE).
