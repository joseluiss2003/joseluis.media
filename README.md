# Now Playing

An Apple Music–style now playing popup for Omarchy. Icon-only button in the bar that opens a compact card with album artwork, track info, progress, and playback controls. It reuses Omarchy's built-in MPRIS service (`omarchy.media`) through the plugin clone mechanism, so there is no extra daemon.

## Features

- Icon-only bar button, visible only while an MPRIS player is available.
- Popup with artwork, title/artist/album, elapsed/remaining times, seek bar, and transport controls.
- Source list to switch between active players.
- Left-click opens/closes the popup, right-click play/pauses, middle-click skips, scroll wheel seeks through tracks.
- Accurate progress bar driven by `playerctl` (no position drift).

## Install

```sh
omarchy plugin add https://github.com/joseluiss2003/joseluis.media.git --enable --yes
```

## Requirements

- Omarchy with the Quickshell shell.
- A media player exposing the MPRIS interface (Spotify, mpv, browsers, …).

No extra packages or helper scripts are required.

## Remove

```sh
omarchy plugin remove joseluis.media --yes
```
