# mpvacious
Because voracious is bloated.

## Requirements
* A [distribution](https://www.gnu.org/distros/free-distros.html) of
[GNU/Linux](https://www.gnu.org/gnu/about-gnu.html).
Preferably [Arch-based](https://www.parabola.nu/).
* [Anki](https://wiki.archlinux.org/index.php/Anki)
* [FFmpeg](https://wiki.archlinux.org/index.php/FFmpeg)
* The [AnkiConnect](https://ankiweb.net/shared/info/2055492159) plugin
* curl (you should already have this)

## Installation

If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:
```
$ config submodule add 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs
```
If not, either proceed to Arch Wiki and come back when you're done, or simply clone the repo:

```
$ git clone 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs
```
Open or create  ```~/.config/mpv/scripts/modules.lua``` and add these lines:
```
local mpv_scripts_dir_path = os.getenv("HOME") ..  "/.config/mpv/scripts/"
function load(relative_path) dofile(mpv_scripts_dir_path .. relative_path) end
load("subs2srs/subs2srs.lua")
```
If you're using [voidrice](https://github.com/LukeSmithxyz/voidrice),
you should [already have it](https://github.com/LukeSmithxyz/voidrice/blob/master/.config/mpv/scripts/modules.lua).
In this case only add the last line: ```load("subs2srs/subs2srs.lua")```.

## Updating
Submodules are updated using standard git commands:
```
$ config submodule update --remote --merge
```
or
```
$ cd ~/.config/mpv/scripts/subs2srs && git pull
```
## Configuration
Configuration file is located at ```~/.config/mpv/script-opts/subs2srs.conf```
and should be created by the user. If a parameter is not specified
in the config file, the default value will be used.

Example configuration file:
```
# Absolute path to the `collection.media` folder.
# `~` or `$HOME` are not supported due to mpv limitations.
# Replace "user" and "profile" with your own.
collection_path=/home/user/.local/share/Anki2/profile/collection.media/

# The deck will be created if it doesn't exist. Subdecks are supported.
deck_name=Bank::subs2srs

# Model names are listed in `Tools -> Manage note types` menu in Anki.
model_name=Japanese sentences

# Field names as they appear in the selected note type.
sentence_field=SentKanji
audio_field=SentAudio
image_field=Image

# Togglebles. Possble values: `yes` or `no`.
# When mpv starts, automatically copy subs to the clipboard
# as they appear on screen.
# This option can be also toggled with `Ctrl+t`.
autoclip=no
# Remove all spaces from the subtitle text.
# Only makes sense for languages without spaces like Japanese.
nuke_spaces=yes
# Format timestamps according to this pattern: `%dh%02dm%02ds%03dms`.
# Use seconds otherwise.
human_readable_time=yes

# Media quality
# 0 = lowest, 100=highest
snapshot_quality=5
# Sane values are from 16k to 32k.
audio_bitrate=18k

# Image dimensions
# If either (but not both) of the width or height parameters is -2,
# the value will be calculated preserving the aspect-ratio.
snapshot_width=-2
snapshot_height=200
```
Note that by default mpvacious assumes that "user" and "profile" are equal.
So if your collection path looks like this:
`/home/john/.local/share/Anki2/john/collection.media/`
then you don't need to specify `collection_path` in the config.

Key bindings are configured in ```~/.config/mpv/input.conf```.
This step is not necessary.
```
Ctrl+e script-binding anki-export-note
Ctrl+s script-binding set-starting-point
Ctrl+r script-binding reset-starting-point
Ctrl+t script-binding toggle-sub-autocopy
```
## Usage
* `Ctrl+t` - **T**oggles the `autoclip` option.
When enabled, you can use it in combination with
[Yomichan](https://foosoft.net/projects/yomichan/)'s clipboard monitor.
`Yomichan Search` is activated by pressing `Alt+Insert` in your web browser.
* `Ctrl+e` - **E**xports a card with the currently visible subtitle line on the front.
* `Ctrl+s` - Sets the **s**tarting line.
It is supposed to be used when a sentence spans multiple subtitle lines.
After pressing `Ctrl+s`, wait for the next line(s) to appear
and then press `Ctrl+e` to set the **e**nding line and create the card.
* `Ctrl+r` - If you pressed `Ctrl+s` but changed your mind,
it **r**esets the starting line.

After the card is created, you can find it by typing ```tag:subs2srs added:1```
in the Anki Browser. Then use [qolibri](https://aur.archlinux.org/packages/qolibri/)
or similar software to add definitions to the card.

## Additional mpv key bindings
I recommend adding these lines to your ```~/.config/mpv/input.conf```
for smoother experience.
```
# vim-like seeking
l seek 5
h seek -5
j seek -60
k seek 60

# Cycle between subtitle files
K cycle sub
J cycle sub down

# Skip to previous/next subtitle line
H no-osd sub-seek -1
L no-osd sub-seek 1

# Add/subtract 50 ms delay from subs
Z add sub-delay +0.05
z add sub-delay -0.05

# Adjust timing to previous/next subtitle
X sub-step 1
x sub-step -1
```
## Hacking
* https://mpv.io/manual/master/#lua-scripting
* https://github.com/mpv-player/mpv/blob/master/player/lua/defaults.lua
* https://github.com/SenneH/mpv2anki
* https://github.com/kelciour/mpv-scripts/blob/master/subs2srs.lua
* https://pastebin.com/M2gBksHT

## Further hacking
* https://github.com/ayuryshev/subs2srs
* https://github.com/erjiang/subs2srs
