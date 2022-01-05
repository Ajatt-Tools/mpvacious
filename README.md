<p align="center">
<img src="https://user-images.githubusercontent.com/69171671/117440218-4ae26800-af23-11eb-87b4-1d9026fc953f.png"/>
</p>

# mpvacious

[![Chat](https://img.shields.io/badge/chat-join-green.svg)](https://tatsumoto-ren.github.io/blog/join-our-community.html)
![GitHub](https://img.shields.io/github/license/Ajatt-Tools/mpvacious)
[![Patreon](https://img.shields.io/badge/support-patreon-orange)](https://www.patreon.com/bePatron?u=43555128)
![GitHub top language](https://img.shields.io/github/languages/top/Ajatt-Tools/mpvacious)
![Lines of code](https://img.shields.io/tokei/lines/github/Ajatt-Tools/mpvacious)
[![AUR](https://img.shields.io/badge/AUR-install-blue.svg)](https://aur.archlinux.org/packages/mpv-mpvacious/)

mpvacious is your semi-automatic subs2srs for mpv.
It supports multiple workflows and allows you to quickly create Anki cards
while watching your favorite TV show.
[Video demonstration](https://youtu.be/vU85ramvyo4).

## Table of contents

* [Requirements](#requirements)
* [Installation](#installation)
    * [Manually](#manually)
    * [From the AUR](#from-the-aur)
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
* [Profiles](#profiles)
* [Hacking](#hacking)

## Requirements

<table>
<tr>
    <th><a href="https://www.gnu.org/gnu/about-gnu.html">GNU/Linux</a></th>
    <th><a href="https://www.gnu.org/proprietary/malware-microsoft.en.html">Windows 10</a></th>
    <th><a href="https://www.gnu.org/proprietary/malware-apple.en.html">macOS</a></th>
    <th>Comments</th>
</tr>
<tr>
    <td><a href="https://wiki.archlinux.org/index.php/Mpv">mpv</a></td>
    <td><a href="https://sourceforge.net/projects/mpv-player-windows/files">mpv</a></td>
    <td><a href="https://mpv.io/installation/">mpv</a></td>
    <td>v0.32.0 or newer.</td>
</tr>
<tr>
    <td><a href="https://wiki.archlinux.org/index.php/Anki">Anki</a></td>
    <td colspan="2" align="center"><a href="https://apps.ankiweb.net/">Anki</a></td>
    <td></td>
</tr>
<tr>
    <td colspan="3" align="center"><a href="https://ankiweb.net/shared/info/2055492159">AnkiConnect</a></td>
    <td>Install from AnkiWeb.</td>
</tr>
<tr>
    <td><a href="https://www.archlinux.org/packages/core/x86_64/curl/">curl</a></td>
    <td colspan="2" align="center"><a href="https://curl.haxx.se/">curl</a></td>
    <td>Installed by default on all platforms except Windows 7.</td>
</tr>
<tr>
    <td><a href="https://www.archlinux.org/packages/extra/x86_64/xclip/">xclip</a> or <a href="https://archlinux.org/packages/community/x86_64/wl-clipboard/">wl-copy</a></td>
    <td></td>
    <td>pbcopy</td>
    <td>To copy subtitle text to clipboard.</td>
</tr>
</table>

Install all dependencies at once (on [Arch-based](https://www.parabola.nu/)
[distros](https://www.gnu.org/distros/free-distros.en.html)):

```
$ sudo pacman -Syu mpv anki curl xclip --needed
```

## Prerequisites

* A guide on how to set up Anki can be found [on our site](https://tatsumoto.neocities.org/blog/setting-up-anki.html).
Note that it is not recommended to use FlatPak or similar containers.
* Most problems with adding audio or images to Anki cards can be fixed
by installing FFmpeg and enabling FFmpeg support in `mpvacious`'s config.
For details see the [configuration](#configuration) section.
* If you're on a **Windows** machine, a mpv build by `shinchiro` is recommended.
* **macOS** users are advised to use [homebrew](https://brew.sh/) or manually add `mpv` to `PATH`.
* Make sure that your build of mpv supports encoding of audio and images.
This shell command can be used to test it.
  ```
  $ mpv 'test_video.mkv' --loop-file=no --frames=1 -o='test_image.jpg'
  ```
  If the command fails, switch to FFmpeg or find a compatible build on the [mpv website](https://mpv.io/installation/).

## Installation

### Manually

Download
[the repository](https://github.com/Ajatt-Tools/mpvacious/archive/refs/heads/master.zip)
or
[the latest release](https://github.com/Ajatt-Tools/mpvacious/releases)
and extract the folder containing
[subs2srs.lua](https://raw.githubusercontent.com/Ajatt-Tools/mpvacious/master/subs2srs.lua)
to your [mpv scripts](https://github.com/mpv-player/mpv/wiki/User-Scripts) directory:

| OS | Location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/scripts/` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/scripts/` |

**Note:** in [Celluloid](https://www.archlinux.org/packages/community/x86_64/celluloid/)
user scripts are installed in `/.config/celluloid/scripts/`.

<details>

<summary>Expected directory tree</summary>

```
~/.config/mpv/scripts
|-- other_addon_1
|-- other_addon_2
`-- mpvacious
    |-- main.lua
    |-- ...
    `-- subs2srs.lua
```

</details>

### From the AUR

mpvacious can be installed with the [mpv-mpvacious](https://aur.archlinux.org/packages/mpv-mpvacious/) package.

### Using git

If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:
```
$ config submodule add 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs
```
If not, either proceed to Arch Wiki and come back when you're done, or simply clone the repo:

```
$ git clone 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs
```

<details>
<summary>A note for mpv v0.32 and older</summary>

Since you've just cloned the script to its own subfolder,
you need to tell mpv where to look for it.
mpv v0.33 does this automatically by loading the `main.lua` file in the add-on's folder.

Open or create  `~/.config/mpv/scripts/modules.lua` and add these lines:
```
local mpv_scripts_dir_path = os.getenv("HOME") ..  "/.config/mpv/scripts/"
package.path = package.path .. ';' .. home .. '/.config/mpv/scripts/subs2srs/?.lua'
function load(relative_path) dofile(mpv_scripts_dir_path .. relative_path) end
load("subs2srs/subs2srs.lua")
```

**Note:** in [Celluloid](https://www.archlinux.org/packages/community/x86_64/celluloid/)
replace  in `.config/mpv` with `.config/celluloid`
and optionally `subs2srs` with the name of the folder mpvacious is cloned into.

</details>

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

<p align="center">
  <a href="https://github.com/Ajatt-Tools/mpvacious/blob/master/.github/RELEASE/subs2srs.conf">Example configuration file</a>
</p>

Sentence field should be first in the note type settings.
Otherwise, Anki won't allow mpvacious to add new notes.

**Tip**: Try [our official note type](https://ankiweb.net/shared/info/1557722832)
if you don't want to configure note fields yourself.
Alternatively, we have a collection of user-created note types, which you can browse
[here](https://github.com/Ajatt-Tools/AnkiNoteTypes).

If you are having problems playing media files on older mobile devices,
set `audio_format` to `mp3` and/or `snapshot_format` to `jpg`.
Otherwise, I recommend sticking with `opus` and `webp`,
as they greatly reduce the size of the generated files.

If no matter what mpvacious fails to create audio clips and/or snapshots,
change `use_ffmpeg` to `yes`.
By using ffmpeg instead of the encoder built in mpv you can work around most encoder issues.
You need to have ffmpeg installed for this to work.

### Key bindings

The user may change some key bindings, though this step is not necessary.
See [Usage](#usage) for the explanation of what they do.

| OS | Config location |
| --- | --- |
| GNU/Linux | `~/.config/mpv/input.conf` |
| Windows | `C:/Users/Username/AppData/Roaming/mpv/input.conf` |

Default bindings:

```
a            script-binding mpvacious-menu-open

Ctrl+n       script-binding mpvacious-export-note

Ctrl+m       script-binding mpvacious-update-last-note
Ctrl+M       script-binding mpvacious-overwrite-last-note

Ctrl+c       script-binding mpvacious-copy-sub-to-clipboard
Ctrl+t       script-binding mpvacious-autocopy-toggle

H            script-binding mpvacious-sub-seek-back
L            script-binding mpvacious-sub-seek-forward

Alt+h        script-binding mpvacious-sub-seek-back-pause
Alt+l        script-binding mpvacious-sub-seek-forward-pause

Ctrl+h       script-binding mpvacious-sub-rewind
Ctrl+H       script-binding mpvacious-sub-replay
Ctrl+L       script-binding mpvacious-sub-play-up-to-next
```

**Note:** A capital letter means that you need to press Shift in order to activate the corresponding binding.
For example, `Ctrl+M` actually means `Ctrl+Shift+m`.
mpv accepts both variants in `input.conf`.

## Usage

### Global bindings

Menu:
* `a` - Open `advanced menu`.

Make a card:
* `Ctrl+n` - Export a card with the currently visible subtitle line on the front.
Use this when your subs are well-timed,
and the target sentence doesn't span multiple subs.

Update the last card:
* `Ctrl+m` - Append to the media fields of the newly added Anki card.
* `Ctrl+Shift+m` - Overwrite media fields of the newly added Anki card.

Clipboard:
* `Ctrl+c` - Copy current subtitle string to the system clipboard.
* `Ctrl+t` - Toggle automatic copying of subtitles to the clipboard.

Seeking:
* `Shift+h` and `Shift+l` - Seek to the previous or the next subtitle.
* `Alt+h` and `Alt+l` - Seek to the previous, or the next subtitle, and pause.
* `Ctrl+h` - Seek to the start of the currently visible subtitle. Use it if you missed something.
* `Ctrl+Shift+h` - Replay current subtitle line, and pause.
* `Ctrl+Shift+l` - Play until the end of the next subtitle, and pause. Useful for beginners who need
to look up words in each and every dialogue line.

### Menu options

Let's say your subs are well-timed,
but the sentence you want to add is split between multiple subs.
We need to combine the lines before making a card.

Advanced menu has the following options:

* `c` - Set timings to the current sub and remember the corresponding line.
It does nothing if there are no subs on screen.

Then seek with `Shift+h` and `Shift+l` to the previous/next line that you want to add.
Press `n` to make the card.

* `r` - Forget all previously saved timings and associated dialogs.

If subs are badly timed, first, you could try to re-time them.
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

**The process:**

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

It is possible to make a card with just audio, and a picture
when subtitles for the show you are watching aren't available, for example.
mpv by default allows you to do a `1` second exact seek by pressing `Shift+LEFT` and `Shift+RIGHT`.
Open the mpvacious menu by pressing `a`, seek to the position you need, and set the timings.
Then press `g` to invoke the `Add Cards` dialog.
Here's a [video demonstration](https://www.youtube.com/watch?v=BXhyckdHPGE).

If the show is hard-subbed, you can use [Tesseract](https://github.com/tesseract-ocr/tesseract)
or [ShareX](https://getsharex.com/) OCR to add text to the card.

### Other tools

If you don't like the default Yomichan Search tool, try:

* Clipboard Inserter browser add-on
([chrome](https://chrome.google.com/webstore/detail/clipboard-inserter/deahejllghicakhplliloeheabddjajm))
([firefox](https://addons.mozilla.org/ja/firefox/addon/clipboard-inserter/))
* A html page ([1](https://pastebin.com/zDY6s3NK)) ([2](https://pastebin.com/hZ4sawL4))
to paste the contents of your clipboard to

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

## Profiles

Mpvacious supports config profiles.
To make use of them, create a new config file called `subs2srs_profiles.conf`
in the same folder as your [subs2srs.conf](#Configuration).
Inside the file, define available profile names (without `.conf`) and the name of the active profile:

```
profiles=subs2srs,english,german
active=subs2srs
```

In the example above, I have three profiles.
The first one is the default,
the second one is for learning English,
the third one is for learning German.

Then in the same folder create config files for each of the defined profiles.
For example, below is the contents of my `english.conf` file:

```
deck_name=English sentence mining
model_name=General
sentence_field=Question
audio_field=Audio
image_field=Extra
```

You don't have to redefine all settings in the new profile.
Specify only the ones you want to be different from the default.

To cycle profiles, open the advanced menu by pressing `a` and then press `p`.
At any time you can see what profile is active in the menu's status bar.

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
