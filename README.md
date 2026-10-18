# Player Equaliser for piCorePlayer

A live 10-band equaliser page in Lyrion Music Server for your
[piCorePlayer](https://www.picoreplayer.org) players. Made for tuning a
player to its room by ear: stand in the room with your phone, move a slider,
hear the change.

- Changes play **while you drag**. On piCorePlayer's own page, nothing changes
  until you press *Test*.
- Settings are **saved by themselves** a few seconds after you stop, so they
  survive a restart. No *Save* button to forget.
- Values are shown in dB (one step is 0.72 dB; flat is pCP's default of 66).
  There are −/+ buttons for fine steps and a curve showing the overall shape.
- **Restore original**: the first time the plugin sees a player, it records
  that player's equaliser settings, so you can always go back to them.
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
