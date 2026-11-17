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

## Requirements

- macOS 14 or newer.
- Xcode Command Line Tools or a Swift toolchain.
- Codex installed locally if you want the built-in Codex pets.

## Quick Start

```bash
git clone <repo-url>
cd multi-codex-pets
./script/build_and_run.sh
```

The menu bar contains Show/Hide Pets, a Mode switch, Settings, and Quit.
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
An unavailable selected session leaves
its pets Idle. Choosing an assignment enables session mode and stops walking.
Manual and walking modes override session animations. With no sessions, pets
return to Idle. Launch directly into settings with:

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
The **V2 pets follow cursor** toggle in Behavior is enabled by default and saved
across app restarts. Turning it off immediately stops cursor polling and returns
the pet to its normal animation. While idle, enabled v2 pets look toward
the mouse using their 16 direction poses, including when the pointer is outside
the pet window. Near the pet's center they return to the idle animation.
Dragging, other animation states, and Reduce Motion take priority over tracking.

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

The local build uses an ad hoc signature. Distributing a prebuilt app to other
Macs is best done through a GitHub Release with a zipped app; Developer ID signing
and Apple notarization are separate steps for normal Gatekeeper acceptance.

## Click and Session Alert Sounds

Open **Settings → Pets → Sounds…** for a pet. **Add Click Sounds…** and
**Add Notification Sounds…** both accept multiple WAV, MP3, M4A, AIF, AIFF, or CAF
files. Audio is validated before importing, originals are kept, and existing files
are never overwritten. The folder button remains available for manual file management.

Use the play/stop button to preview a file and adjust click and alert volume
separately. The Alert pool menu switches between the default pool and per-state
overrides; Use default pool removes an override.

Choose the **Click** and **Alert** checkboxes independently for each file. A file
can serve both roles. Clicking a pet plays a random playable click sound; dragging
does not play it. Each click restarts that pet's click playback. A single selected
file always plays that file; multiple selected files form a random pool.

In session mode, a visible pet plays one of its random alert sounds when its
assigned conversation changes to an enabled activity state. Completed, Awaiting
Approval, and Failed are enabled by default. Choose states in Behavior; repeated
alerts for the same pet and destination state have a configurable 0–60 second
quiet interval (5 seconds by default). Other important states are not suppressed
by that interval. Both explicit and
automatic assignments are supported. First connection, reassignment, duplicate
polls, detection failures, and unknown-state observations are silent. Alerts from
several pets play sequentially; a pet's newest pending alert replaces its older
pending alert to prevent a backlog. Hiding pets or leaving session mode clears
pending alerts. The **Session sound notifications** toggle in Behavior mutes alerts
without changing click sounds or role assignments. No alert sound is configured by default.

Files live in `${CODEX_HOME:-$HOME/.codex}/pet-sounds/<pet-id>/`. Custom pets use
their package folder name as the ID; built-in pets use `codex-default-<id>`.
Existing and manually dropped audio defaults to click use only. Imports made with
**Add Notification Sounds…** default to alert use only. `.sound-roles.json` stores
role choices and state overrides. The older `.selected-sound` marker is retained for compatibility;
playback now chooses randomly from the enabled role's pool. No audio is bundled.

## Pet Placement and Quick Controls

Pet position, monitor preference, position lock, individual mute, and conversation
assignments persist across restarts. Saved conversations that are unavailable stay
Idle; they are never rebound just because a PID or title looks similar.

Hover a pet for its name, assigned conversation title, and activity. Right-click
shows the pet name and service/session header, followed by two submenus:
**Session** (Open Agent App, Change Session) and **Pet Options** (Name Label,
Lock Position, Mute This Pet). Open Agent App opens the owning application;
it does not navigate to a specific conversation.

Use the pet tile's **Rename Pet…** action to save a display name or restore the
original; file names, pet IDs, and conversation assignments remain unchanged.
**Name Label…**, available in both pet options menus, shows the name above or
below the pet, or hides it. Font size (9–28 pt) and text color are saved per pet.
Labels follow the pet without intercepting mouse input and adjust at screen edges.
**Animations…** previews the nine animations without changing desktop pets;
V2 pets also preview cursor following through all 16 look directions.

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
Only the attributed service identification icons are bundled; no pet art is included.

## License

MIT. See `LICENSE`.
