# mpvacious
Because voracious is bloated.

## Requirements
* A distribution of GNU/Linux. Preferably Arch-based. (Windows *might* work, but is not officially supported)
* [Anki](https://wiki.archlinux.org/index.php/Anki)
* [FFmpeg](https://wiki.archlinux.org/index.php/FFmpeg)
* The [AnkiConnect](https://ankiweb.net/shared/info/2055492159) plugin
* curl (you should already have this)

## Installation

If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:
```
config submodule add 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs

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
If you're using [voidrice](https://github.com/LukeSmithxyz/voidrice), you should [already have it](https://github.com/LukeSmithxyz/voidrice/blob/master/.config/mpv/scripts/modules.lua). In this case only add the last line: ```load("subs2srs/subs2srs.lua")```.

## Configuration

Configuration file is located at ```~/.config/mpv/script-opts/subs2srs.conf```
and should be created by the user.

Example configuration file:
```
# Absolute path to the `collection.media` folder.
# `~` or `$HOME` are not supported due to mpv limitaions.
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
# When mpv starts, automatically copy subs to the clipboard as they appear on screen.
# This option can be also toggled with `Ctrl+t`.
autoclip=no
# Remove all spaces from the subtitle text.
# Only makes sense for languages without spaces like japanese.
nuke_spaces=yes
# Format timestamps according to this pattern: `%dh%02dm%02ds%03dms`. Use seconds otherwise.
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

## Usage
* `Ctrl+t` **t**oggles `autoclip` option. When enabled, you can use it in
combination with [Yomichan](https://foosoft.net/projects/yomichan/)'s clipboard monitor. `Yomichan Search` is activated
by pressing `Alt+Insert` in your web browser.
* `Ctrl+e` **e**xports a card with currently visible subtitle text on the front.
* `Ctrl+s` sets the **s**tarting line. It is supposed to be used when the sentence spans
multiple subtitle lines. After pressing `Ctrl+s` wait for the next line(s) to
appear and then press `Ctrl+e` to set the **e**nding line and create the card.

After the card is created, you can find it by typing ```tag:subs2srs added:1```
in the Anki Browser. Then use [qolibri](https://aur.archlinux.org/packages/qolibri/)
or similar software to add definitions to the card.

## Hacking
* https://mpv.io/manual/master/#lua-scripting
* https://github.com/mpv-player/mpv/blob/master/player/lua/defaults.lua
* https://github.com/SenneH/mpv2anki
* https://github.com/kelciour/mpv-scripts/blob/master/subs2srs.lua
* https://pastebin.com/M2gBksHT

## Further hacking
* https://github.com/ayuryshev/subs2srs
* https://github.com/erjiang/subs2srs
