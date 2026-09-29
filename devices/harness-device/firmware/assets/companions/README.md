The ten desktop companions, packed for the normal round-dial firmware.

Regenerate with `python3 devices/harness-device/firmware/scripts/gen_companion_art.py`
from the repository root (Pillow 12.2+). The authored geometry lives in
`daemons/tools/illustrated/daemon_art.py`, shared with the desktop. The manifest
records its hash and the generated pack's hash.

Each independently compressed block contains panel-order RGB565 followed by
straight alpha. Cropped rear, body, front, face and mail layers share five
bounded renderer caches (278,427 bytes total), with 240 px and 108 px layouts.
Animation and touch replace layers without decompressing the unchanged body.

Companions are a transient account-controlled override. The saved Tim, Tux and
Focus skin IDs retain their meanings. `followCompanion` is on by default and can
be disabled per device. Turning off the desktop creature experiment, unpairing,
signing out or losing the cable session restores the saved skin. No Zoo or
account data is persisted on the dial.

`test/test_companions.py` decodes this exact pack and compares partial redraws
against complete renders for every species and mood, both sizes, touch and mail.
Set `COMPANION_CAPTURES` to a local folder to save review images.

USB extension (protocol 3, capability detected from settings):

- `hello.settings` and `settings.state.settings` add `followCompanion: boolean`
  and `companion: string | null`. Older firmware omits them; the host sends no
  companion commands to those devices.
- `companion.set { id: "gnu" }` selects an illustrated species for this cable
  session. `id: null` restores the saved skin. Unknown or malformed IDs are
  refused. Both outcomes answer with `settings.state`, including `ok` and the
  actual active companion. Selection never writes flash.
- `settings.set { followCompanion: false }` persists the per-device preference
  through Diego's existing settings path, using bit 4 of Habitat options.
  Existing skin IDs 0, 1 and 2 remain Tim, Tux and Focus.
- The host reads the existing account Zoo cache; no new polling or account API
  is added. It sends changed selections on its one-second USB tick, retries a
  missing acknowledgement at most every five seconds, and reasserts after a
  device reboot. Gallery browsing never changes the Zoo pair.
