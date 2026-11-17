# Multi Codex Pets

Multi Codex Pets is a small macOS menu bar app for showing more than one
Codex-compatible pet at the same time.

It is standalone: it does not modify Codex, patch Codex, or copy Codex app
files into this repo.

## What It Does

- Shows multiple floating, draggable pets at once. Drag direction follows recent
  horizontal movement, ignores small pointer jitter, and preserves the running
  animation frame when reversing direction.
- Lets you choose visible pets from a three-column settings grid with character previews.
- Can slowly roam visible pets around the screen and bounce them off edges.
- Can show Codex's built-in pets when the Codex app is installed locally.
- Can load your custom pet packages from `${CODEX_HOME:-$HOME/.codex}/pets`.
- Supports v1 (`1536x1872`, `8 x 9`) and v2 (`1536x2288`, `8 x 11`)
  pet spritesheets, both with `192x208` cells.
- Detects Codex, Claude, Orca, and Antigravity conversations with titles and activity states.
- Ships with no pet art, telemetry, networking, or user-specific data.

## Install on macOS

The prebuilt app supports **Apple Silicon Macs running macOS 13 or newer**.
No Xcode or Swift installation is needed.

[Download MultiCodexPets.dmg](https://github.com/Uhjinkim/multi-codex-pets/releases/latest/download/MultiCodexPets.dmg),
open it, then drag **MultiCodexPets.app** to **Applications**. Launch the app from
Applications and use its menu bar icon to open Settings and choose your pets.
When updating, quit the running app before replacing it. Your pet files and
settings are kept separately from the app.

Or download the latest stable release and open the installer from Terminal:

```bash
curl -fL --retry 3 -o "$HOME/Downloads/MultiCodexPets.dmg" \
  "https://github.com/Uhjinkim/multi-codex-pets/releases/latest/download/MultiCodexPets.dmg" \
  && open "$HOME/Downloads/MultiCodexPets.dmg"
```

This opens the installer. Drag the app to **Applications** to finish installation.

## Build from Source

- macOS 13 or newer.
- Xcode Command Line Tools or a Swift toolchain.
- Codex installed locally if you want the built-in Codex pets.

## Quick Start

```bash
git clone https://github.com/Uhjinkim/multi-codex-pets.git
cd multi-codex-pets
./script/build_and_run.sh
```

The menu bar contains Show/Hide Pets, a global Session sound notifications toggle,
a Mode switch, Settings, and Quit.
Open **Settings…** for the native settings dialog. Changes apply immediately:

- **Pets**: choose visible pets in a three-column grid, refresh packages, and open pet or sound folders.
- **Behavior**: choose Follow Agent Sessions, Walk Around, or Manual Animation;
  set the manual animation, cursor following, notification states, repeat interval,
  and scale from 50% to 200% with a slider or presets.
- **Sessions**: choose automatic distribution, one shared session, or per-pet
  assignments. Official service icons, service filters, title/status search, and
  clickable rows replace nested session menus. Completed sessions are hidden by
  default; failures remain visible. Sessions are grouped by agent type and activity.

The settings window and its text, controls, and images adapt to the monitor’s
usable size in macOS logical points. Moving the window between monitors updates
the layout; switching tabs preserves its size. On narrow windows, service filters
wrap instead of shrinking. The full-width three-part tab bar uses equal hit areas;
switching tabs does not resize the window.

The UI follows the system app language (Korean and English; English fallback).
Service names and user-authored session titles are kept unchanged. Service icons
come from the official installed app bundles; see the icon source notes in
`Sources/MultiCodexPets/Resources/AgentIcons/README.md`.

Local metadata is polled every two seconds, independently of the animation mode.
Activity states include Generating, Monitoring Background Tasks, Interrupted,
Status Unverified, Awaiting Approval, Waiting for Input, Completed, Failed, and
Status Unknown. **Behavior → Session Animations** maps each state to one of the
nine animations, saves overrides, and can restore the defaults. Automatic
assignment cycles through agent types and prioritizes generating sessions within
each type.

Session metadata depends on the installed provider version:

- **Codex**: matches open rollout files to thread titles in the local state DB,
  and streams lifecycle events once, then reads only newly appended bytes in
  64 KiB chunks. This preserves state through long turns and large tool outputs.
  A shared app-server process can expose several distinct conversations.
- **Claude**: matches a running PID to its session file in
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/sessions`, including title and status.
- **Orca**: reads `orca worktree ps --json` through the installed Orca CLI,
  using workspace/pane identities, conversation names, and reported activity.
  Listed completed sessions can remain visible until cleared in Orca.
- **Antigravity**: reads non-idle, non-killed conversation summaries from
  `~/.gemini/antigravity/conversation_summaries.db` while a matching agent
  process is present. Idle history is not treated as a running session.

Processes without a linked conversation appear separately as diagnostics and
cannot be assigned to pets. A running process alone never implies generation.
A conversation with unrecognized lifecycle metadata remains Status Unknown.
Metadata schemas can change between provider versions, and some providers do
not publish approval events. Unknown activity defaults to Idle rather than guessing.

Conversation assignments are restored across app restarts by provider identity.
In session-following mode, a missing assigned session uses Idle. Choosing an
assignment enables session mode unless walking is already active; walking pets
keep walking while tracking their assigned session for sound alerts.
Manual and walking modes override session animations. Launch directly into settings with:

```bash
open dist/MultiCodexPets.app --args --settings
```

The run script runs tests, builds a local app bundle at `dist/MultiCodexPets.app` and starts
it after replacing the running app. `dist/` and Swift build output are ignored by git.

Useful commands:

```bash
swift test
./script/build_and_run.sh --build  # Build without launching
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
```

## Built-In Codex Pets

The app asks macOS where `com.openai.codex` is installed. If you need to point
it somewhere else, set:

```bash
CODEX_APP_PATH=/path/to/Codex.app ./script/build_and_run.sh
```

Codex's built-in pet spritesheets are read from your local Codex app at runtime.
They are not copied into this repository and are not licensed by this project.

## Custom Pets

Each pet package should live in its own folder:

```text
~/.codex/pets/my-pet/
  pet.json
  spritesheet.webp
```

Custom folder names are pet IDs. If an ID matches an installed built-in pet,
the built-in pet takes priority; rename the custom folder to load both.
Refresh Pets reloads replaced images for visible pets while keeping their positions.

Example manifest:

```json
{
  "id": "my-pet",
  "displayName": "My Pet",
  "description": "A tiny companion.",
  "spritesheetPath": "spritesheet.webp"
}
```

The spritesheet must be PNG or WebP, either `1536x1872` (v1) or
`1536x2288` (v2). The layout is detected from the image dimensions. An optional
`"spriteVersionNumber": 1` or `2` in `pet.json` must match the image layout.
Both layouts play the nine standard animations. V2 pets are labeled in the grid.
The default cursor-tracking toggle in Behavior is enabled initially. Each V2 pet
has its own **Cursor Tracking → Off / Always / When Shaken** choice in both its
right-click menu and settings-card options. These choices persist across restarts
and leave other pets unchanged; pets without an override use the default.
When Shaken detects three quick direction reversals and looks for two seconds.
It detects mouse movement rather than the system cursor-enlargement state.
Off stops cursor polling and returns the pet to its normal animation. While idle, waiting for input, or completed, enabled v2 pets look toward
the mouse using their 16 direction poses, including when the pointer is outside
the pet window. Near the pet's center they return to the idle animation.
Generating, review, failure, running, dragging, and Reduce Motion take priority over tracking.

To use a different Codex home directory:

```bash
CODEX_HOME=/path/to/codex-home ./script/build_and_run.sh
```

## Install in Applications

Build an optimized local app, install it in `/Applications`, and launch it:

```bash
./script/build_and_run.sh --install
```

This runs the tests, builds the release configuration, replaces
`/Applications/MultiCodexPets.app`, and restarts the app. Open it later from
Applications, Finder, or Spotlight. It remains a menu bar app without a Dock icon.
Pets, sounds, names, and preferences live outside the app bundle and survive updates.
For a source-based update, pull the latest code and run the install command again.

The app icon is compiled from `Design/AppIcon/CompanionPets-v1.icon` with Apple's
Icon Composer asset compiler, including native appearance variants and an `.icns`
fallback for older macOS versions. Rebuilding also rebuilds the icon.

The local build uses an ad hoc signature. Distributing a prebuilt app to other
Macs is best done through a GitHub Release with a zipped app; Developer ID signing
and Apple notarization are separate steps for normal Gatekeeper acceptance.

## Developer ID Signing and Notarization

Install a Developer ID Application certificate with its private key, then save
notary credentials in Keychain (the command prompts securely):

```bash
xcrun notarytool store-credentials "multi-codex-pets"
./script/build_and_run.sh --notarize
```

The notarize command runs tests, builds Release, signs with Hardened Runtime and
a secure timestamp, submits to Apple, waits for acceptance, staples and validates
the ticket, and checks Gatekeeper before replacing the Applications copy. It
creates `dist/MultiCodexPets-0.1.0.zip` from the stapled app for distribution.
The installed app keeps running if authentication or notarization fails.

A single local Developer ID Application identity is selected automatically.
With multiple identities, set `CODE_SIGN_IDENTITY` explicitly. `NOTARY_PROFILE`
can select a different Keychain profile; credentials are never saved in the repo.
Version/build numbers are defined at the top of `script/build_and_run.sh`.

Normal development commands still use ad hoc signing unless an identity is set.
Use `--notarize` for signed, notarized updates; plain `--install` installs a local
build without a notarization ticket.

## DMG Distribution

After the app has been notarized, create a signed and notarized disk image:

```bash
./script/package_dmg.sh
```

This packages the stapled app and an Applications shortcut, verifies the disk
image, signs it, notarizes and staples the DMG itself, and checks Gatekeeper.
The installer opens in a fixed icon view with a Retina background and an app-to-Applications
drag direction. `./script/package_dmg.sh --local` builds an unsigned local preview
without replacing the notarized disk image. The packaging step creates an isolated Python environment under `.build/dmg-tools`
for the pinned Finder-metadata tools in `script/requirements-dmg.txt`; the app itself
has no Python dependency.

Distribute `dist/MultiCodexPets.dmg`; the adjacent `.sha256` file records its
checksum. Users open the disk image and drag the app to Applications.
The same `CODE_SIGN_IDENTITY` and `NOTARY_PROFILE` overrides are supported.

## Click and Session Alert Sounds

Open **Settings → Pets → Sounds…** for a pet. **Add Click Sounds…** and
**Add Notification Sounds…** both accept multiple WAV, MP3, M4A, AIF, AIFF, or CAF
files. Audio is validated before importing, originals are kept, and existing files
are never overwritten. The folder button remains available for manual file management.

Use the play/stop button to preview a file. Behavior contains global click and
alert volumes and **Mute All Pets**. Each pet’s Sounds dialog starts with its own
volume and mute control, plus an expandable **Global Volume — All Pets** section.
Playback combines the global role volume with the pet’s volume. Global mute
preserves individual mute choices; muted pets cannot play previews. The Alert pool menu switches between the default pool and per-state
overrides; Use default pool removes an override.

Choose the **Click** and **Alert** checkboxes independently for each file. A file
can serve both roles. Clicking a pet plays a random playable click sound; dragging
does not play it. Each click restarts that pet's click playback. A single selected
file always plays that file; multiple selected files form a random pool.

In session and walking modes, a visible pet plays one of its random alert sounds when its
assigned conversation changes to an enabled activity state. Completed, Awaiting
Approval, and Failed are enabled by default. Choose states in Behavior; repeated
alerts for the same pet and destination state have a configurable 0–60 second
quiet interval (5 seconds by default). Other important states are not suppressed
by that interval. Both explicit and
automatic assignments are supported. First connection, reassignment, duplicate
polls, detection failures, and unknown-state observations are silent. Alerts from
several pets play sequentially; a pet's newest pending alert replaces its older
pending alert to prevent a backlog. Hiding pets or changing animation modes clears
pending alerts. The global **Session sound notifications** toggle is available in
the menu bar and Behavior; both control the same saved setting for all pets.
Turning it off immediately stops playing and queued session alerts without changing
click sounds, session tracking, or sound role assignments. Turning it back on starts
from the current session state without replaying old alerts. No alert sound is configured by default.

**Behavior → Session Alerts → Orca message sent** independently enables outgoing
Orca message alerts. In each pet’s **Sounds → Alert pool → Orca message sent**,
choose a separate sound pool (the default alert pool is used until overridden).
Only pets already assigned to the sender’s conversation notify. Message events
leave the conversation’s activity and animation unchanged; completion and message
alerts have separate cooldowns and pending queue entries. Sessions shows the last
message detection time and sender, including when sound is globally muted.

The app reads `orca orchestration inbox --limit 200 --full --json`; it never
acknowledges messages or reads them with `check`. First connection, scan failures,
reconnection, reassignment, and duplicate observations are silent. Worker completion
and heartbeat records are excluded. A sender must match one current Orca pane or
chat identity exactly; unknown or ambiguous identities are ignored. The latest
200 records are inspected per two-second scan, so an unusually large burst can
exceed the observation window. Message bodies are not retained or displayed.

Files live in `${CODEX_HOME:-$HOME/.codex}/pet-sounds/<pet-id>/`. Custom pets use
their package folder name as the ID; built-in pets use `codex-default-<id>`.
Existing and manually dropped audio defaults to click use only. Imports made with
**Add Notification Sounds…** default to alert use only. `.sound-roles.json` stores
role choices and state overrides. The older `.selected-sound` marker is retained for compatibility;
playback now chooses randomly from the enabled role's pool. No audio is bundled.

Pets has a character/alias search that opens Codex Pets in your browser. Install
using the site’s instructions, then Refresh Pets. Each Sounds dialog has the same
search for Myinstants, prefilled with the character name. Preview and download in
the browser, then use Add Click Sounds or Add Notification Sounds to import it.
These searches open the default browser; the app does not scrape either website
or execute downloaded shell commands.

## Pet Placement and Quick Controls

Pet position, monitor preference, position lock, individual mute, and conversation
assignments persist across restarts. Saved conversations that are unavailable stay
Idle; they are never rebound just because a PID or title looks similar.

Hover a pet for its name, assigned conversation title, and activity. Right-click
shows the pet name, conversation and activity, followed by direct actions for
session changes, position lock, mute, sounds, names, labels and animation previews.
Cursor modes and display destinations remain submenus. The settings-card options
provide the same actions. Opening Change Session does not change the saved routing
or behavior mode until a session is selected. Open Agent App opens the owning application;
it does not navigate to a specific conversation.

Use the pet tile's **Rename Pet…** action to save a display name or restore the
original; file names, pet IDs, and conversation assignments remain unchanged.
**Name Label…**, available in both pet options menus, shows the name above or
below the pet, or hides it. Font size (9–28 pt), text color, background color, and background transparency
(0% opaque to 100% transparent) are saved per pet.
Labels follow the pet without intercepting mouse input and adjust at screen edges.
**Animations…** previews the nine animations without changing desktop pets;
V2 pets also preview cursor following through all 16 look directions.
The animation chooser uses full-width selection buttons and scrolls on small
screens. Both it and Behavior show Reduce Motion status and link to macOS
Accessibility settings (Motion on macOS 26+, Display on earlier versions); changes
there apply immediately.

The pet tile's options menu also moves a pet to a selected display. Recover Pets
brings off-screen pets into a connected display. A disconnected saved display
falls back to a connected screen. Locked pets cannot be dragged or roam.

The Sessions tab shows the last scan time, a manual refresh, and diagnostic details
when metadata or CLI access fails. Unrecognized provider state values are shown
instead of being guessed. Codex state DB versions are discovered dynamically.

## Rendering and Resource Use

Sprite sheets are decoded into bitmap pixels once. Each displayed animation cell
is copied and cached separately, avoiding repeated WebP decoding and whole-atlas
color conversion. Settings thumbnails own only one cell's pixels. Codex log
reading keeps incremental cursors and releases temporary JSON objects per line.

## Privacy

This app has no telemetry or bundled user data. It reads local pet packages,
installed Codex spritesheets, process names and parent IDs (`ps`), and open file
paths (`lsof`). Session enrichment reads provider title/status metadata, streamed
Codex rollout events, and the local Orca CLI's session snapshot. Rollout records and
CLI snapshots can contain conversation content; only titles, identities, and
lifecycle states are used for the UI. Nothing is transmitted, and provider data
is never modified. Sound-folder and pet-folder actions may create local folders.

## Development

Before opening a pull request, run:

```bash
swift format --in-place --recursive Package.swift Sources Tests
swift test
./script/build_and_run.sh --verify
```

Do not commit generated build output, app bundles, or personal pet assets.
The attributed service identification icons and original app-icon mascots are
bundled; no user pet art is included.

## License

MIT. See `LICENSE`.
