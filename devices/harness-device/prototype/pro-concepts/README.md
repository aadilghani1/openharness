# Harness Pro: concept review

Standalone visual review firmware. Eleven pages, swiped horizontally in a loop.
Taps and holds do nothing. All displayed messages, times and modes are illustrative.
There is no connection to live app data, microphone capture, Wi-Fi, or device settings.

| Page | Context | Concept |
| --- | --- | --- |
| 01 | Docked | Companion: an animated ASCII Tim with a quiet status line |
| 02 | Docked | Focus: large type and a restrained activity trace |
| 03 | Docked | Swarm: three agent rows, readable at a glance |
| 04 | Docked | Dispatch: a result as a paper postcard, with Tux |
| 05 | On the go | Pocket brief: an editorial digest |
| 06 | On the go | Field companion: an illustrated octopus in a landscape |
| 07 | On the go | Thought catcher: creature and animated voice-like trace |
| 08 | On the go | Quiet companion: still, sparse presence |
| 09 | Screen study | Soft paper: 55% backlight command, warm palette |
| 10 | Screen study | Clear daylight: 90% backlight command, stronger contrast |
| 11 | Screen study | Night ink: 40% backlight command, dark palette |

The backlight percentages are PWM commands, not calibrated optical luminance.
Each concept carries its own backlight level. The display studies use the same
composition to compare actual backlight and palette choices. No undocumented
panel gamma, voltage or power-register settings are changed.

## Hardware fit

Sources supplied by the user: TXW395039B0-HYE_SPEC.pdf (display),
WT01P4C5-S1_datasheet_V1.3.pdf (module),
SCH_Schematic_LCD_ESP32P4_2026-09-23.pdf (carrier board), IP5306.pdf, and the
hardware test-bench README in Downloads/HarnessPro-HwTest.

- This unit was read through the ROM loader as **ESP32-P4 revision 3.2**.
  ESP-IDF 5.5 alone builds for the older silicon and is unsuitable here.
  The concept build uses ESP-IDF 5.5.3 with revision 3.x selected, following
  [Espressif's revision guide](https://documentation.espressif.com/esp32-p4-chip-revision-v3.x_user_guide_en.pdf).
- The 3.95-inch 720x720 backlit LCD uses ST7703I; touch is GT911. It has room
  for stronger type hierarchy and multiple agent rows. It cannot produce the
  round AMOLED's unlit black pixels. Light surfaces and deliberate contrast are
  useful alternatives, and a lower physical backlight is worth comparing for dark scenes.
- The panel datasheet calls out four MIPI lanes, but the supplied carrier
  schematic routes two data lanes and the existing working Pro driver uses two.
  This build reuses that driver and its timings, reset order and power rails.
- RGB565 is the existing display path. Flat colors and restrained shading avoid
  relying on very subtle gradients. This gallery bakes antialiased text at native
  resolution, with large primary text and flat labels rather than circular captions.
- The P4, PSRAM and MIPI display support rich visual scenes. Animation only
  redraws the changed rectangle; static pages stop redrawing entirely. This
  reduces compute and memory traffic, but does not switch off the LCD backlight.
- The schematic includes a battery connector, IP5306-I2C charger/boost,
  battery-voltage divider, power latch and button. A fitted battery, its capacity
  and real runtime have not been verified. No battery-life estimate is claimed.
- IP5306.pdf's register notes (PDF page 13) explicitly say it has no voltage/current
  telemetry. Use the external ADC path for voltage and calibrated estimates;
  the charge/full bits alone are not a precise fuel gauge.
- A confirmed **USB data session with the computer** can support Docked mode.
  External power or charging alone cannot distinguish a dock from a wall charger.
  The schematic also has a CHARGE_DETECT net to GPIO6, but no dedicated physical
  dock identity/switch is shown. Keep host connectivity and power source separate.
- On-the-go app connectivity would need the C5 radio and its SDIO transport.
  The current USB app path does not supply that behavior. This gallery previews
  portable visual directions without implying that wireless or offline task logic exists.
- Audio codecs, a speaker amplifier, haptic output and RGB LED are present in
  the design. They are unused here so the review is visual and swipe-only.

## Reproduce

`tools/build_sprites.py` compiles the existing shared character renderer for host
preview. `tools/design.py` draws the layouts and illustration, exports PNG/GIF/HTML
previews, packs independently compressed RGB565 frames, and verifies exact
decompression. It uses Pillow, NumPy and system Avenir/Georgia/Menlo fonts on macOS;
font binaries are not copied into the project.

Run these scripts before building with ESP-IDF 5.5.3 for esp32p4. The C firmware
also decodes every image block at boot before declaring the gallery ready.
Only the Pro's application partition is replaced for the physical trial; its
settings and a backup of the previous application are preserved outside the repo.

This is a review prototype, not production navigation or a power-management implementation.

## Physical trial — 2026-09-29

Installed `0.0.87-pro.concepts.1` on the Pro, MAC `E8:F6:0A:E7:64:61`.
The 2,964,960-byte application was verified against flash. The previous active
application is backed up in `/private/tmp/pro-concepts-20260929/flash/previous-app-ota-0.bin`;
partition metadata, OTA selection and NVS settings were checked unchanged.

Boot verified all 155 image blocks, identified GT911 at 720x720, and reached the
gallery ready state. The initial live capture recorded swipes through pages 11,
1, 2 and 3, 90 rendered animation frames, and zero touch errors. The unchanged
desktop bridge was restarted after the trial. No round device was flashed.

Build and flash evidence: `/private/tmp/pro-concepts-20260929/validated-image.json`
and `/private/tmp/pro-concepts-20260929/flash-result.json`.
Image SHA-256: `43e62d2c14c395e7561979b24ad0ad8beb1405a8d6f16535f58895c04af07d04`.
