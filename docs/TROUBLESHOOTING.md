# Troubleshooting

Start with the section that matches what you see. None of these checks use `sudo`.

## The setup program says a command is missing

Classic Windows requires Omarchy Quattro. First update Omarchy normally, restart the computer, and run `./setup.sh` again.

Do not install random replacements for `hyprpm`, `hyprctl`, or `omarchy` from an internet guide. Those commands are supplied by Omarchy and Hyprland.

## Super+T floats the window, but there is no title bar

Log out of Omarchy and sign in again. The official hyprbars plugin must be loaded at the beginning of the graphical session.

If the bar is still missing, run:

```bash
hyprctl plugin list
```

You should see:

```text
Plugin hyprbars by Vaxry
```

Then check for configuration errors:

```bash
hyprctl configerrors
```

No output means there are no configuration errors.

## The red X is visible but does not close the window

Update and re-run setup:

```bash
cd ~/omarchy-classic-windows
git pull --ff-only
./setup.sh
```

The current release uses Hyprland's Lua close dispatcher. Older `killactive` examples from pre-Quattro configuration guides do not work with current Lua dispatch syntax.

## I cannot resize by dragging the border

Make sure the window is floating first by pressing **Super+T**. Tiled windows are sized by the layout and are not resized by dragging their edges.

Check the setting:

```bash
hyprctl getoption general:resize_on_border
```

It should report `bool: true`.

## The window needs two Super+T presses before the title bar changes

Update and re-run setup. This project includes a workaround for the current hyprbars dynamic-rule refresh issue:

```bash
cd ~/omarchy-classic-windows
git pull --ff-only
./setup.sh
```

Log out and back in once after updating so old window tags are cleared.

## An Omarchy update disabled hyprbars

Run setup again:

```bash
cd ~/omarchy-classic-windows
./setup.sh
```

Hyprland plugins are compiled against a specific Hyprland version. Re-running setup reloads the compatible plugin after an Omarchy/Hyprland update.

## I want to return to normal Omarchy behavior

Run:

```bash
cd ~/omarchy-classic-windows
./uninstall.sh
```

Then log out and sign in again if an already-open window still has an old title bar.

## Getting help

When opening a GitHub issue, include the output of these commands:

```bash
hyprctl version
hyprpm list
hyprctl plugin list
hyprctl configerrors
```

Also describe whether the problem happens before or after pressing **Super+T**. Do not post passwords, access tokens, private keys, or the contents of unrelated personal configuration files.
