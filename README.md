# rofi-screens

Display management from a [rofi](https://github.com/davatorium/rofi) menu, for X11.

Supports:
- **Resolution**: switch the internal panel between modes at its native
  aspect ratio, including scaled modes the driver doesn't offer

New backends can be added under `lib/`. See [Adding a backend](#adding-a-backend).

## Features

- **Resolution**: lists every mode the panel has at its native ratio (3:2 on
  a 2256x1504 panel, 16:9 on a 1920x1080 one), marks the native and current
  modes, and switches to the one you pick. Modes the driver doesn't offer are
  generated with `cvt` and added through `xrandr --newmode`, either as
  percentages of the native width or as an exact list.

## Dependencies

| Package | Used for |
| --- | --- |
| `bash` 4.3+ | everything |
| `rofi` | menus |
| `xorg-xrandr` | querying and setting modes |
| `libxcvt` (`cvt`) | timings for added modes |
| `libnotify` (`notify-send`) | status and error notifications |
| `util-linux` (`setsid`) | detaching background work from the menu |
| `shellcheck` | `make check` |

## Installation

```sh
git clone https://github.com/michaelgilch/rofi-screens.git
cd rofi-screens
make install
```

This installs `rofi-screens` to `~/.local/bin` and the backends to
`~/.local/lib/rofi-screens`. Make sure `~/.local/bin` is on your `PATH`.

`PREFIX` and `DESTDIR` work as usual. Remove it with `make uninstall` (using
the same `PREFIX`).

`make install` also writes `.desktop` entries for the top menu and each
backend to `~/.local/share/applications`, so `rofi -show drun` finds them by
name or by typing `screens`.

For development, `make link` symlinks the script from your working tree
instead, so edits take effect immediately.

## Usage

```
rofi-screens [backend | --init | --xorg-conf | --list]
```

With no argument it opens the top-level menu. With a backend name
(`resolution`, or any you've added) it opens that backend directly.

```
# i3
bindsym $mod+F9 exec --no-startup-id rofi-screens resolution
```

### Making added modes permanent

Modes added with `xrandr --newmode` only last until X restarts. The menu
re-adds them whenever it opens, but anything that switches to one before that
(an autorandr profile, a startup script) fails. There are two fixes.

**Xorg config (recommended).** Define the modes in Xorg's config so they exist
from X startup:

```sh
rofi-screens --xorg-conf | sudo tee /etc/X11/xorg.conf.d/10-monitor.conf
```

This prints a `Monitor` section for the managed output, with a `Modeline`
for every mode in `RES_MODES` (or `RES_SCALES`), generated with `cvt`. Restart
X to load it. It's tied to the output name, so if the output is renamed X
silently ignores the section; rerun the command if you change the config or
the output.

**At session start.** Without root, run `rofi-screens --init`, which adds
the modes without showing a menu, from your window manager's startup:

```
# i3
exec --no-startup-id rofi-screens --init
```

and, for autorandr, from a preswitch hook so profiles can use them:

```sh
mkdir -p ~/.config/autorandr
printf '#!/bin/sh\nrofi-screens --init\n' > ~/.config/autorandr/preswitch
chmod +x ~/.config/autorandr/preswitch
```

## Configuration

Copy the example config and edit it. Every setting is optional.

```sh
mkdir -p ~/.config/rofi-screens
cp config.example ~/.config/rofi-screens/config
```

The file is sourced as bash from `${XDG_CONFIG_HOME:-~/.config}/rofi-screens/config`.

| Variable | Default | Description |
| --- | --- | --- |
| `ROFI_ARGS` | | Extra flags for every rofi call. Split on whitespace; quotes aren't honored |
| `ON_CHANGE` | | Command run (via `bash -c`) after any change, e.g. to relaunch a bar |
| `RES_OUTPUT` | first connected eDP/LVDS/DSI, else primary | Output the resolution menu manages |
| `RES_SCALES` | `(90 80 67)` | Modes to add, as percentages of the native width, rounded to the nearest mode at exactly the native ratio |
| `RES_MODES` | `()` | Exact modes to add instead of `RES_SCALES` |

Panels whose ratio doesn't reduce cleanly (1366x768 is 683:384) have no
useful exact-ratio modes, so `RES_SCALES` produces nothing there. Use
`RES_MODES`.

## Adding a backend

Backends work the same way as in
[rofi-netmenu](https://github.com/michaelgilch/rofi-netmenu#adding-a-backend).
Each is one file in `lib/` that registers itself at the top:

```bash
backend <name> <prefix> <order> <label> <icon>
```

and defines:

- **`<prefix>_available`**: success if the backend applies right now. Called
  every time the top menu is drawn, so keep it cheap.
- **`<prefix>_menu [back]`**: shows the menu. With an argument it was opened
  from the top menu and should offer a Back row. `return 0` goes back,
  `exit 0` closes.
- **`<prefix>_init`** (optional): run by `rofi-screens --init`.
- **`<prefix>_xorg_conf`** (optional): prints Xorg config sections for
  `rofi-screens --xorg-conf`. Errors go to stderr with a non-zero return.

### Helpers

| Helper | Purpose |
| --- | --- |
| `menu_reset`, `row <key> <label> [icon]`, `menu <prompt>` | Build and show a menu; `menu` prints the chosen key |
| `xr_query` | Snapshot `xrandr --query`; call again after changing anything |
| `xr_internal` | Internal panel name, else the primary output |
| `xr_modes <output>` | `WxH<TAB>flags` per mode; flags hold `*` (current) and `+` (preferred) |
| `notify <summary> [body] [urgency]` | Desktop notification |
| `run_bg <ok msg> <fail msg> <cmd...>` | Run in the background, notify, run `ON_CHANGE`, close the menu |
| `on_change` | Run the user's `ON_CHANGE` hook |

## Development

```
rofi-screens          entry point: loads config and backends, top menu, CLI
lib/screens-lib.sh    backend registry, menu, xrandr and notification helpers
lib/resolution.sh     Resolution backend
config.example        documented example config
```

## License

TODO: choose a license and add a `LICENSE` file.
