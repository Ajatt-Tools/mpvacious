# mpvacious
Because voracious is bloated.
![screenshot](https://user-images.githubusercontent.com/69171671/92329311-30838200-f056-11ea-9351-f76bb2d72cf7.jpg)
## Requirements
* A [distribution](https://www.gnu.org/distros/free-distros.html) of
[GNU/Linux](https://www.gnu.org/gnu/about-gnu.html).
Preferably [Arch-based](https://www.parabola.nu/).
Probably works on windows too, but you're completely on your own there.
* [Anki](https://wiki.archlinux.org/index.php/Anki)
* [FFmpeg](https://wiki.archlinux.org/index.php/FFmpeg)
* The [AnkiConnect](https://ankiweb.net/shared/info/2055492159) plugin
* [xdotool](https://www.archlinux.org/packages/community/x86_64/xdotool/)
(to avoid a certain Ankiconnect [bug](https://github.com/FooSoft/anki-connect/issues/82))
* [curl](https://www.archlinux.org/packages/core/x86_64/curl/) (you should already have this)

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
mpv doesn't tolerate spaces before and after `=`.

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

# Size of the font used in the menu
menu_font_size=24
```
Note that by default mpvacious assumes that "user" and "profile" are equal.
So if your collection path looks like this:
`/home/john/.local/share/Anki2/john/collection.media/`
then you don't need to specify `collection_path` in the config.

Key bindings are configured in ```~/.config/mpv/input.conf```.
This step is not necessary.
```
Ctrl+e script-binding anki-export-note
Ctrl+h script-binding sub-rewind
a      script-binding mpvacious-menu-open
```
These additional bindings aren't enabled by default but can be accessed via the menu (`a`).
```
Ctrl+s script-binding set-starting-line
Ctrl+r script-binding reset-timings
Ctrl+t script-binding toggle-sub-autocopy
```
## Usage
### Global bindings
These bindings work everywhere, even if the menu (covered later) is not envoked.
* `Ctrl+e` - Export a card with the currently visible subtitle line on the front.
Use this when your subs are perfectly timed and the target sentence doesn't span multiple subs.
* `Ctrl+h` - Seek to the start of the currently visible subtitle. Use it if you missed something.
* `Ctrl+c` - Copy current subtitle string to the system clipboard. For automatic copying see `advanced menu`.
### Menu options
* `a` - Open `advanced menu` with a list of all available keybindings.

Let's say your subs are still perfectly timed,
but the sentence you want to add is split between multiple subs.
We need to combine the lines before making a card.
* `c` - Set timings to the current sub and remember the corresponding line.
It does nothing if there's no subs on screen.

Then seek or continue watching until the next line that you want to combine appears on screen.
Press `n` to make the card.

* `r` - Forget all previously saved timings and associated dialogs.

If subs are badly timed, first of all, you could try to re-time them.
[ffsubsync](https://github.com/smacke/ffsubsync) is a program that will do it for you.
Another option would be to shift timings using key bindings provided by mpv.

* `z` and `shift+z` - Adjust subtitle delay.

If above fails, you have to manually set timings.
* `s` - Set the start time.
* `e` - Set the end time.

Then, as earlier, press `n` to make the card.

### How do I add definitions to the card I just made
After the card is created, you can find it by typing ```tag:subs2srs added:1```
in the Anki Browser. Then use [qolibri](https://aur.archlinux.org/packages/qolibri/)
or similar software to add definitions to the card.

Pressing `t` in the `advanced menu` toggles the `autoclip` option.
Now as subtitles appear on the screen, they will be immediately copied to the clipboard.
You can use it in combination with
[Yomichan](https://foosoft.net/projects/yomichan/) clipboard monitor.
`Yomichan Search` is activated by pressing `Alt+Insert` in your web browser.

### Adding media to existing cards
You can add a card using Yomichan first,
and then append an audioclip and snapshot to it.

####You'll need:
* Clipboard Inserter
([chrome](https://chrome.google.com/webstore/detail/clipboard-inserter/deahejllghicakhplliloeheabddjajm))
([firefox](https://addons.mozilla.org/ja/firefox/addon/clipboard-inserter/))
* An [html page](https://pastebin.com/zDY6s3NK)
to paste the contents of you clipboard to

You can use any html page as long as it has \<body\>\</body\> in it.

####The process:
1) Open the html page in a web browser
2) Enable Clipboard Inserter on the page
3) Enable `clipboard autocopy` in mpvacious
by pressing `t` in the `advanced menu`
4) When you find an unknown word, make a card with Yomichan
5) Go back to mpv and add the snaphot and the audio clip to the card you've just made
by pressing `m` in the `advanced menu`

Don't forget to set the right timings if the sentence is split between multiple subs.

### Additional mpv key bindings
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
If you want to modify this script
or make an entirely new one from scratch,
these links may help.
* https://mpv.io/manual/master/#lua-scripting
* https://github.com/mpv-player/mpv/blob/master/player/lua/defaults.lua
* https://github.com/SenneH/mpv2anki
* https://github.com/kelciour/mpv-scripts/blob/master/subs2srs.lua
* https://pastebin.com/M2gBksHT
* https://pastebin.com/NBudhMUk
* https://pastebin.com/W5YV1A9q

## Further hacking
* https://github.com/ayuryshev/subs2srs
* https://github.com/erjiang/subs2srs
