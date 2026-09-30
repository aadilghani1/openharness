# Firmware development

Production belongs to Diego. His approved commit on `main` is the source for
customer firmware; only his release process publishes the stable manifest.
The exact release commit is his decision, not whatever `origin/main` happens
to point to when a developer builds.

## Separate branches and devices

| Work | Branch | Starting commit | Device |
| --- | --- | --- | --- |
| Round development | `dev/firmware-round` | `aa0a583cb30d82af5f600cd8b0569899f960a0ed` | `44:1B:F6:85:52:18` |
| Pro development | `dev/firmware-pro` | `92283ad62f6876a363ecfae4d2466340d7e2dd0f` | `E8:F6:0A:E7:64:61` |
| Production reference | Diego's approved release | Chosen by Diego | `28:84:85:90:65:94` |

These assignments reflect the user's correction on 2026-09-30: **65:94 is
production; the newly connected 52:18 is development.**

`devices.json` is the development deployment allowlist. The previous production
reference and orange terminal are also protected. New USB devices are excluded
until the user assigns them. Identify devices by their full MAC and detected
silicon, never their case, character, port order, or mutable `/dev` name.

The round branch starts from our last tested round source. The Pro branch
preserves the working Pro implementation: current round
`main` no longer contains the Pro target. Earlier `firmware` and `prototype/*`
branches remain as history. Do not merge the old Pro tree wholesale into round
firmware or production.

Commit and push to the matching development branch. Both branches track their
own remote branch. Never push development to `main`, move a release tag, invoke
`make upload-circle`, or write a stable firmware manifest. Bringing a production
fix into development is a deliberate, reviewed change; ordinary development
does not imply pulling or rebasing onto `main`.

## Builds

The CMake development guard gives these branches a version of
`0.0.0-dev.<commit>` (plus `-dirty` for uncommitted changes), selects their hardware
target, and rejects a production version or the other chip. Omit `PROJECT_VER`
from build commands. Use a dedicated build directory per worktree and target;
do not reuse `build-prod` or one of the old production-version build caches.
The ordinary upload script refuses to publish from either development branch.
These are workflow safeguards, not server-side access controls.

For the round target, use ESP-IDF **v5.5**, `esp32s3`, and the tracked defaults:

```sh
idf.py -C devices/harness-device/firmware -B /private/tmp/harness-dev-round/build \
  -DIDF_TARGET=esp32s3 -DSDKCONFIG=/private/tmp/harness-dev-round/build/sdkconfig \
  -DDEVICE_FORCE_PROD=1 build
```

`DEVICE_FORCE_PROD=1` only prevents embedding local provisioning secrets. It is
not a release channel and does not make a build a customer release.

For Pro, use ESP-IDF **v5.5.3**, `esp32p4`, and the existing dock-only companion
profile (`DEVICE_HABITAT=1`, `DEVICE_PRO_COMPANION=1`, `DEVICE_PRO_WIFI=1`,
`DEVICE_DEFAULT_CHARACTER=tim`). Preserve the four defaults files from the
validated Pro build: `sdkconfig.defaults`, `sdkconfig.defaults.esp32p4`,
`../prototype/pro-companion/sdkconfig.defaults`, and
`../prototype/pro-companion/sdkconfig.wifi.defaults`. Keep credentials in the
existing local provisioning mechanism, never in this repository. Battery work
was canceled; Pro is dock-only.

The current desktop updater deliberately skips non-numeric development versions
(`cli/src/cable/fwPush.ts`). Promotion back to production therefore requires an
explicit, verified flash; do not rely on automatic updates to leave development.
Do not change the customer's updater as part of this workflow.

## Deployment

Before opening a serial port or stopping the bridge, run from the correct branch:

```sh
python3 devices/harness-device/development/check_target.py \
  --mac 44:1B:F6:85:52:18 --chip esp32s3
```

For Pro, use its branch, MAC, and `esp32p4`. The check reads the local allowlist;
it does not reset, identify, or flash a device. Then verify the connected USB
identity and the bootloader's MAC/chip against those exact values. Stop if they
disagree. Keep a verified rollback image and preserve NVS, partitions, and
settings. Record commit, development version, SHA-256, target MAC, and boot
verification with each installation. No command may choose the first USB port.

A production reference also needs production app behavior: Focus selected and
Follow desktop companion off. Install Diego's production code and configure
that reference only on an explicit user request, using a clean, isolated
checkout and recording the exact commit and binary hash. The development
allowlist must reject it. Development firmware work does not authorize changing
the shared CLI or desktop installation.

## Existing installations at separation

On 2026-09-30, round `65:94` was running a local `aa0a583cb` build labeled
`0.0.87`, SHA-256
`0218b52b9857f17e1d9ec66c52ac28ecc1377cb6f1ef99c93f4bc943c98d1652`.
That image is **not** Diego's approved release. The user subsequently assigned
65:94 to production testing and requested Diego's code there, with development
moved to 52:18. If Diego uses the same version number, the updater cannot
distinguish these images: perform an explicit verified flash, not an automatic
version comparison. Do not publish the old local image or use it to certify the
customer update path.

Pro `64:61` was running the separate prototype
`0.0.87-pro.companion.12`, already excluded from stable automatic updates. This
branch separation does not itself reflash any device or change any settings;
physical deployments must be recorded separately.
