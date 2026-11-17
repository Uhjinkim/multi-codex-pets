# Multi Codex Pets

[![English](https://img.shields.io/badge/English-2563eb?style=for-the-badge)](README.md)
[![한국어](https://img.shields.io/badge/한국어-475569?style=for-the-badge)](README.ko.md)

Desktop pets that react to your coding agents. Keep several companions on screen,
follow their sessions, and give each pet its own sounds and personality.

## Install

**Apple Silicon Mac · macOS 13 or newer**

[**Download for Mac**](https://github.com/Uhjinkim/multi-codex-pets/releases/latest/download/MultiCodexPets.dmg)

Open the DMG, drag **MultiCodexPets.app** to **Applications**, and launch it.
Use the menu bar icon to open **Settings** and choose your pets.

Or download the latest version and open the installer from Terminal:

```bash
curl -fL --retry 3 -o "$HOME/Downloads/MultiCodexPets.dmg" \
  "https://github.com/Uhjinkim/multi-codex-pets/releases/latest/download/MultiCodexPets.dmg" \
  && open "$HOME/Downloads/MultiCodexPets.dmg"
```

Finish installation by dragging the app to **Applications**.
To update, quit the app and replace it with the new version. Your pets, sounds,
and settings are kept.

## Make yourself at home

- **Choose your pets:** show several at once, use locally installed Codex pets,
  or add custom pets. No pet collection is included with the app.
- **Follow your agents:** connect pets to Codex, Claude, Orca, or Antigravity
  sessions and see their activity through animations.
- **Choose how they move:** follow sessions, walk around, or play a chosen
  animation. Drag pets into place or lock their positions.
- **Give them a voice:** add your own click and alert sounds. Adjust volume and
  mute for all pets together or for each pet separately.
- **Make each one yours:** rename pets, style their name labels, and move them
  between displays.

Right-click a pet for its settings and quick actions. The pet grid also has
**animation preview**, **sound settings**, and an options menu for each pet.

## Cursor tracking for V2 pets

Right-click a V2 pet and choose **Cursor Tracking**:

- **Off:** keep its normal animation.
- **Always:** look toward the cursor while idle, waiting for input, or completed.
- **When Shaken:** briefly look toward the cursor when you shake the mouse.

Each choice applies only to that pet. Active task animations, dragging, and macOS
Reduce Motion take priority. “When Shaken” responds to mouse movement; it does
not require the system cursor-enlargement option.

## Add pets and sounds

Use the pet search in Settings to browse characters on Codex Pets. Follow the
website's installation instructions, then choose **Refresh Pets**.
Custom pets are normally stored in `~/.codex/pets`.

Open a pet's sound settings to search Myinstants by name or alias. Listen and
download on the website, then add the file as a click or notification sound.
You can preview sounds before choosing which ones to use.

## Session alerts

Choose which activity changes play a sound in **Settings → Behavior**.
You can also enable separate alerts for outgoing Orca agent messages.
Use **Session sound notifications** in the menu bar to turn session alerts on or off.

## Privacy

Session tracking uses local data. The app does not send conversation data or
collect telemetry. Pet and sound searches open the corresponding website in your browser.

## Development

For source builds, custom pet formats, and release instructions, see the
[development reference](DEVELOPMENT.md).

## License

[MIT](LICENSE)
