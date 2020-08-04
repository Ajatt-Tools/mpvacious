# mpvacious
Because voracious is bloated.

## Installation

Make sure you have [AnkiConnect](https://ankiweb.net/shared/info/2055492159)
and [FFmpeg](https://wiki.archlinux.org/index.php/FFmpeg) installed.

If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:
```
config submodule add 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs

```
If not, either proceed to Arch Wiki and come back when you're done, or simply clone the repo:

```
$ git clone 'https://github.com/Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs

```
Open  ```~/.config/mpv/scripts/modules.lua``` and add these lines:
```
local mpv_scripts_dir_path = os.getenv("HOME") ..  "/.config/mpv/scripts/"
function load(relative_path) dofile(mpv_scripts_dir_path .. relative_path) end
load("subs2srs/subs2srs.lua")
```
## Configuration

Configuration file is located at ```~/.config/mpv/script-opts/subs2srs.conf```
and should be created by the user.

Available options:

| Name                  | Default value        | Description                                                                                                                                     |
| ---                   | ---                  | ---                                                                                                                                             |
| `collection_path`     |                      | Full path to the `collection.media` folder.                                                                                                     |
| `autoclip`            | `false`              | When mpv starts, automatically copy subs to the clipboard as they appear on screen.                                                             |
| `nuke_spaces`         | `true`               | Remove all spaces from the subtitle text. Only makes sense for languages without spaces like japanese.                                          |
| `human_readable_time` | `true`               | Format timestamps according to this pattern: `%dh%02dm%02ds%03dms`. Otherwise use seconds.                                                      |
| `snapshot_quality`    | `5`                  | 0 = lowest, 100=highest                                                                                                                         |
| `snapshot_width`      | `-2`                 | A positive integer. If either (but not both) of the width or height parameters is -2, the value will be calculated preserving the aspect-ratio. |
| `snapshot_height`     | `200`                | Same as `snapshot_width`.                                                                                                                       |
| `audio_bitrate`       | `18k`                | Sane values are from 16k to 32k.                                                                                                                |
| `deck_name`           | `Learning`           | The deck will be created if it doesn't exist.                                                                                                   |
| `model_name`          | `Japanese sentences` | Model names are listed in `Tools -> Manage note types` menu in Anki.                                                                            |
| `sentence_field`      | `SentKanji`          |                                                                                                                                                 |
| `audio_field`         | `SentAudio`          |                                                                                                                                                 |
| `image_field`         | `Image`              |                                                                                                                                                 |

Example configuration file:
```
collection_path=/home/user/.local/share/Anki2/user/collection.media/
deck_name=sub2srs
sentence_field=Expression
```
## Usage
* `Ctrl+t` toggles `autoclip` option. When enabled, you can use it in
combination with Yomichan's clipboard monitor. Yomichan Search is activated
by pressing `Alt+Insert` in your web browser.
* `Ctrl+e` creates the card using currently visible sub-text.
* `Ctrl+s` sets the starting line. Supposed to be used when the sentence spans
multiple subtitle lines. After pressing `Ctrl+s` wait for the next line(s) to
appear and then press `Ctrl+e` to set the ending line and create the card.

After the card is created, you can find it by typing ```tag:subs2srs added:1```
in the Anki Browser. Then use [qolibri](https://aur.archlinux.org/packages/qolibri/)
or similar software to add definitions to the card.

## Hacking
* https://mpv.io/manual/master/#lua-scripting
* https://github.com/mpv-player/mpv/blob/master/player/lua/defaults.lua
* https://github.com/SenneH/mpv2anki
* https://github.com/kelciour/mpv-scripts/blob/master/subs2srs.lua

## Further hacking
* https://github.com/ayuryshev/subs2srs
* https://github.com/erjiang/subs2srs
