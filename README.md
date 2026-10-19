# Default Apps for Noctalia

A [Noctalia](https://github.com/noctalia-dev/noctalia-shell) plugin to choose your
default apps from Noctalia's settings, in a way that Dolphin and other KDE apps, GTK
apps, `xdg-open` and the desktop portal (and so Flatpaks) all follow. Made for
setups without a full desktop environment, e.g. niri + Noctalia + Dolphin.

Categories: web browser, file manager, terminal, text editor, images, videos, music,
PDF, archives and email.

## How it works

- **Defaults** are written to `~/.config/mimeapps.list`, the freedesktop standard file.
  The plugin reads and writes the `mimeapps.list` files itself, following the
  [spec](https://specifications.freedesktop.org/mime-apps-spec/latest/), instead of
  using `xdg-mime`:
  - it shows a default only if one is **explicitly set**, and says whether it comes from
    your config or the system; otherwise the category shows *Not set: each app picks
    its own* (each toolkit then falls back to its own guess)
  - if a desktop-specific file such as `~/.config/niri-mimeapps.list` (which wins
    over `mimeapps.list`) already has an entry, it is updated too
  - the chosen app is removed from `[Removed Associations]` for those types, which
    would otherwise make GLib ignore it
- **Choosing an app** sets every type of the category that the app supports. The
  category's first type is always set; any other type is only changed if it is unset,
  already uses that app, or used the category's previous default. A deliberate choice
  such as SVG → Inkscape is kept, and the notification says how many types were kept.
- **Apps** are found in every `applications` folder (`$XDG_DATA_HOME`, `$XDG_DATA_DIRS`)
  by their `MimeType=` line; an app is offered if it supports any type of the category.
  Apps marked `NoDisplay` are listed (as *hidden app*) only for the category's main type.
- **The terminal** is not a MIME type. It is written to `~/.config/kdeglobals`
  (`TerminalService` and `TerminalApplication` with the full command, so
  `flatpak run …` works), which Dolphin's *Open Terminal* uses, and to
  `~/.config/xdg-terminals.list` for
  [xdg-terminal-exec](https://github.com/Vladimir-csp/xdg-terminal-exec), which GLib and
  launchers use to start terminal apps. Without xdg-terminal-exec installed the
  plugin shows a warning, as only KDE apps get the setting then.
- After a change it runs `kbuildsycoca6` (if installed) so running KDE apps such as
  Dolphin pick it up.
- Changes are queued, so quickly changing several categories does not lose any.

## Install

This repo is a Noctalia plugin source. In Settings → Plugins → Sources, add

```
https://github.com/Evelynnsrepos/DefaultAppsNoctaliaPlugin
```

then install and enable **Default Apps** from the plugin list and open its settings
(gear icon).

Manual install: copy or symlink the `default-apps/` folder of this repo to
`~/.config/noctalia/plugins/default-apps` and restart Noctalia (it scans the plugin
folder at startup).

Recommended: `xdg-terminal-exec` (terminal for GLib apps) and `kbuildsycoca6`
(from KDE's kservice; refreshes KDE apps right away).

## Command line

`default-apps/defaultapps.sh` does the work and can be used on its own:

```sh
defaultapps.sh scan text/plain image/png        # apps + current defaults
defaultapps.sh set org.kde.kate.desktop "" text/plain text/markdown
defaultapps.sh set-terminal kitty.desktop
```

`set APP OLD MIME...`: `OLD` is the previous default whose types may be taken over
(`""` for none). Reload the plugin's app list over IPC:
`noctalia-shell ipc call plugin:default-apps refresh`.

## License

MIT, see [LICENSE](LICENSE).
