<p align="center">
<img src="https://user-images.githubusercontent.com/69171671/94564113-1dc82b80-0257-11eb-8cc9-1c7d7b6973a0.png"/>
</p>

# mpvacious

![GitHub](https://img.shields.io/github/license/Ajatt-Tools/mpvacious)
[![Patreon](https://img.shields.io/badge/support-patreon-orange)](https://www.patreon.com/tatsumoto_ren)
![GitHub top language](https://img.shields.io/github/languages/top/Ajatt-Tools/mpvacious)
![Lines of code](https://img.shields.io/tokei/lines/github/Ajatt-Tools/mpvacious)
[![Matrix](https://img.shields.io/badge/Japanese_study_room-join-green.svg)](https://app.element.io/#/room/#djt:g33k.se)

mpvacious is your semi-automatic subs2srs for mpv.
It supports multiple workflows and allows you to quickly create Anki cards
while watching your favorite TV show.
[Video demonstration](https://youtu.be/vU85ramvyo4).

## Table of contents

* [Requirements](#requirements)
* [Installation](#installation)
    * [Manually](#manually)
    * [Using curl](#using-curl)
    * [Using git](#using-git)
    * [Updating with git](#updating-with-git)
* [Configuration](#configuration)
* [Usage](#usage)
    * [Global bindings](#global-bindings)
    * [Menu options](#menu-options)
    * [How to add definitions to new cards](#how-to-add-definitions-to-new-cards)
    * [Modifying cards added with Yomichan](#modifying-cards-added-with-yomichan)
    * [Example sentence card](#example-sentence-card)
    * [Audio cards](#audio-cards)
    * [Other tools](#other-tools)
    * [Additional mpv key bindings](#additional-mpv-key-bindings)
* [Hacking](#hacking)

## Requirements

<table>
<tr>
    <th><a href="https://www.gnu.org/gnu/about-gnu.html">GNU/Linux</a></th>
    <th><a href="https://www.gnu.org/proprietary/malware-microsoft.en.html">Windows 10</a></th>
    <th>Comments</th>
</tr>
<tr>
    <td><a href="https://wiki.archlinux.org/index.php/Mpv">mpv</a></td>
    <td><a href="https://sourceforge.net/projects/mpv-player-windows/files">mpv</a></td>
    <td>v0.32.0 or newer.</td>
</tr>
<tr>
    <td><a href="https://wiki.archlinux.org/index.php/Anki">Anki</a></td>
    <td><a href="https://apps.ankiweb.net/">Anki</a></td>
    <td></td>
</tr>
<tr>
    <td colspan="2" align="center"><a href="https://ankiweb.net/shared/info/2055492159">AnkiConnect</a></td>
    <td></td>
</tr>
<tr>
    <td><a href="https://www.archlinux.org/packages/core/x86_64/curl/">curl</a></td>
    <td><a href="https://curl.haxx.se/">curl</a></td>
    <td>Should be installed by default on all platforms</td>
</tr>
<tr>
    <td><a href="https://www.archlinux.org/packages/extra/x86_64/xclip/">xclip</a></td>
    <td></td>
    <td>To copy subtitle text to clipboard</td>
</tr>
</table>

Install all dependencies at once (on [Arch-based](https://www.parabola.nu/)
[distros](https://www.gnu.org/distros/free-distros.en.html)):

```
$ sudo pacman -Syu mpv anki curl xclip --needed
```

If you're on Windows machine, watch [this tutorial](https://youtu.be/bbg6ztWecbU?t=103).
Make sure you choose a build by `shinchiro`,
otherwise you may encounter problems when making Anki cards.

## Installation

### Manually

Save [subs2srs.lua](https://raw.githubusercontent.com/Ajatt-Tools/mpvacious/master/subs2srs.lua)
in  the [mpv scripts](https://github.com/mpv-player/mpv/wiki/User-Scripts) folder:

| OS | Location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/scripts/` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/scripts/` |

**Note:** in [Celluloid](https://www.archlinux.org/packages/community/x86_64/celluloid/)
user scripts are installed by switching to the "Plugins" tab
in the preferences dialog and dropping the files there.

### Using curl

```
$ curl -o ~/.config/mpv/scripts/subs2srs.lua 'https://raw.githubusercontent.com/Ajatt-Tools/mpvacious/master/subs2srs.lua'
```

### Using git
However, if you want to keep up with the updates, it's better to install the script using `git`.

If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:
```
$ config submodule add 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs
```
If not, either proceed to Arch Wiki and come back when you're done, or simply clone the repo:

```
$ git clone 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs
```
Since you've just cloned the script to its own subfolder,
you need to tell mpv where to look for it.

**Note:** the step below is not necessary if you're running mpv `v0.33` or newer.

Open or create  `~/.config/mpv/scripts/modules.lua` and add these lines:
```
local mpv_scripts_dir_path = os.getenv("HOME") ..  "/.config/mpv/scripts/"
function load(relative_path) dofile(mpv_scripts_dir_path .. relative_path) end
load("subs2srs/subs2srs.lua")
```

### Updating with git

| Install method | Command |
| --- | --- |
| Submodules | `$ config submodule update --remote --merge` |
| Plain git | `$ cd ~/.config/mpv/scripts/subs2srs && git pull` |

## Configuration

The config file should be created by the user, if needed.

| OS | Config location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/script-opts/subs2srs.conf` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/script-opts/subs2srs.conf` |
| Windows (portable) | `mpv.exeフォルダ/portable_config/script-opts/subs2srs.conf` |

If a parameter is not specified
in the config file, the default value will be used.
mpv doesn't tolerate spaces before and after `=`.

Example configuration file:
```
####################
# General settings #
####################

# Your Anki username. It is displayed on the title bar of the Anki window.
anki_user=User 1

# The deck will be created if it doesn't exist. Subdecks are supported.
deck_name=Bank::subs2srs

# Model names are listed in `Tools -> Manage note types` menu in Anki.
model_name=Japanese sentences

# Field names as they appear in the selected note type.
sentence_field=SentKanji
audio_field=SentAudio
image_field=Image

# The tag that is added to new notes.
# Leave nothing after `=` to disable tagging completely.
note_tag=subs2srs
#note_tag=

# Size of the font used in the menu
menu_font_size=24

##############################################
# Togglebles. Possble values: `yes` or `no`. #
##############################################

# When mpv starts, automatically copy subs to the clipboard as they appear on screen.
# This option can be also toggled in the addon's OSD menu.
autoclip=no

# Remove all spaces from the subtitle text.
# Only makes sense for languages without spaces like Japanese.
nuke_spaces=yes

# if set to `yes`, the volume of the outputted audio file
# depends on the volume of the player at the time of export
tie_volumes=no

# Remove text in parentheses that may interfere with Yomichan
# before copying subtitles to the clipboard
clipboard_trim_enabled=yes

##################
# Image settings #
##################

# Snapshot format.
snapshot_format=webp
#snapshot_format=jpg

# Quality of produced image files. 0 = lowest, 100=highest.
snapshot_quality=5

# Image dimensions
# If either (but not both) of the width or height parameters is -2,
# the value will be calculated preserving the aspect-ratio.
snapshot_width=-2
snapshot_height=200

##################
# Audio settings #
##################

# Audio format.
audio_format=opus
#audio_format=mp3

# Sane values are 16k-32k for opus, 64k-128k for mp3.
audio_bitrate=18k

# Set a pad to the dialog timings. 0.5 = half a second
audio_padding=0.0
#audio_padding=0.5

#######################################
# Forvo support (Yomichan users only) #
#######################################

# yes    - fetch audio from Forvo if Yomichan couldn't find the audio (default)
# always - always fetch audio from Forvo and replace the audio added by Yomichan
# no     - never use Forvo
use_forvo=yes

# Vocab field should be equal to {expression} field in Yomichan
vocab_field=VocabKanji

# Vocab Audio field should be equal to {audio} field in Yomichan
vocab_audio_field=VocabAudio
```

If you run Anki in portable mode, the path to your `collection.media` folder
may differ from the default. In this case, if you run into troubles making Anki cards with the add-on,
specify full path to the collection in the `config file` as well:
```
collection_path=C:\AnkiDataFolder\collection.media
```

Sentence field should be first in the note type settings.
Otherwise Anki won't allow mpvacious to add new notes.
Alternatively, refer to [Modifying cards added with Yomichan](#modifying-cards-added-with-yomichan)
or use an addon that [allows empty first field](https://ankiweb.net/shared/info/46741504).

If you are having problems playing media files on older mobile devices,
set `audio_format` to `mp3` and/or `snapshot_format` to `jpg`.
Otherwise, I recommend sticking with `opus` and `webp`,
as they greatly reduce the size of the generated files.

### Key bindings

The user may change some of the key bindings, though this step is not necessary.

| OS | Config location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/input.conf` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/input.conf` |

Default bindings:

```
Ctrl+c script-binding mpvacious-copy-sub-to-clipboard
Ctrl+e script-binding mpvacious-export-note
Ctrl+h script-binding mpvacious-sub-rewind
a      script-binding mpvacious-menu-open
H      script-binding mpvacious-sub-seek-back
L      script-binding mpvacious-sub-seek-forward
```

These additional bindings aren't enabled by default but can be accessed via the menu by pressing `a`.

```
Ctrl+s script-binding mpvacious-set-starting-line
Ctrl+r script-binding mpvacious-reset-timings
Ctrl+t script-binding mpvacious-toggle-sub-autocopy
Ctrl+u script-binding mpvacious-update-last-note
```

## Usage

### Global bindings

These bindings work everywhere, even if the menu (covered later) is closed.
* `Shift+h` and `Shift+l` - Seek to the previous or the next subtitle.
* `Ctrl+h` - Seek to the start of the currently visible subtitle. Use it if you missed something.
* `Ctrl+e` - Export a card with the currently visible subtitle line on the front.
Use this when your subs are perfectly timed and the target sentence doesn't span multiple subs.
* `Ctrl+c` - Copy current subtitle string to the system clipboard. For automatic copying see
[Modifying cards added with Yomichan](#modifying-cards-added-with-yomichan).

### Menu options

* `a` - Open `advanced menu` with a list of all available keybindings.

Let's say your subs are still perfectly timed,
but the sentence you want to add is split between multiple subs.
We need to combine the lines before making a card.
* `c` - Set timings to the current sub and remember the corresponding line.
It does nothing if there's no subs on screen.

Then seek with `shift+h` and `shift+l` to the previous/next line that you want to add.
Press `n` to make the card.

* `r` - Forget all previously saved timings and associated dialogs.

If subs are badly timed, first of all, you could try to re-time them.
[ffsubsync](https://github.com/smacke/ffsubsync) is a program that will do it for you.
Another option would be to shift timings using key bindings provided by mpv.

* `z` and `Shift+z` - Adjust subtitle delay.

If above fails, you have to manually set timings.
* `s` - Set the start time.
* `e` - Set the end time.

Then, as earlier, press `n` to make the card.

**Tip**: change playback speed by pressing `[` and `]`
to precisely mark start and end of the phrase.

### How to add definitions to new cards

After the card is created, you can find it by typing ```tag:subs2srs added:1```
in the Anki Browser. Then use [qolibri](https://aur.archlinux.org/packages/qolibri/)
or similar software to add definitions to the card.

### Modifying cards added with Yomichan

You can add a card first using Yomichan,
and then append an audio clip and a snapshot to it.

Pressing `t` in the `advanced menu` toggles the `autoclip` option.
Now as subtitles appear on the screen, they will be immediately copied to the clipboard.
You can use it in combination with
[Yomichan](https://foosoft.net/projects/yomichan/) clipboard monitor.

#### The process:

1) Open `Yomichan Search` by pressing `Alt+Insert` in your web browser.
2) Enable `Clipboard autocopy` in mpvacious by pressing `t` in the `advanced menu`.
3) When you find an unknown word, click
[![＋](https://foosoft.net/projects/yomichan/img/btn-add-expression.png)](https://foosoft.net/projects/yomichan/index.html#flashcard-creation)
in Yomichan to make a card for it.
4) Go back to mpv and add the snapshot and the audio clip
to the card you've just made by pressing `m` in the `advanced menu`.
Pressing `Shift+m` will overwrite any existing data in media fields.

Don't forget to set the right timings and join lines together
if the sentence is split between multiple subs.

### Example sentence card

With the addon you can make cards like this in just a few seconds.

![card-example](https://user-images.githubusercontent.com/69171671/92900057-e102d480-f40e-11ea-8cfc-b00848ca66ff.png)

### Audio cards

It is possible to make a card with just audio and a picture
when subtitles for the show you are watching aren't available, for example.
mpv by default allows you to do a `1` second exact seek by pressing `Shift+LEFT` and `Shift+RIGHT`.
Open the mpvacious menu by pressing `a`, seek to the position you need, and set the timings.
Then press `g` to invoke the `Add Cards` dialog.

If the show is hardsubbed, you can use [Tesseract](https://github.com/tesseract-ocr/tesseract)
or [ShareX](https://getsharex.com/) OCR to add text to the card.

### Other tools

If you don't like the default Yomichan Search tool, try:

* Clipboard Inserter browser add-on
([chrome](https://chrome.google.com/webstore/detail/clipboard-inserter/deahejllghicakhplliloeheabddjajm))
([firefox](https://addons.mozilla.org/ja/firefox/addon/clipboard-inserter/))
* An [html page](https://pastebin.com/zDY6s3NK) to paste the contents of you clipboard to

You can use any html page as long as it has \<body\>\</body\> in it.

### Additional mpv key bindings

I recommend adding these lines to your [input.conf](#key-bindings) for smoother experience.
```
# vim-like seeking
l seek 5
h seek -5
j seek -60
k seek 60

# Cycle between subtitle files
K cycle sub
J cycle sub down

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
* https://github.com/ayuryshev/subs2srs
* https://github.com/erjiang/subs2srs
