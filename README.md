# mpvacious


## Installation

1. Obtain the script

If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute:
```
config submodule add 'git@github.com:Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs

```

If not, either proceed to Arch Wiki and come back, or simply clone the repo:


```
$ git clone 'git@github.com:Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs

```

2. Create or open  ```~/.config/mpv/scripts/modules.lua``` and add these lines:
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
| `collection_path`     |                      | Path to the `collection.media` folder. Trailing slash is necessary.                                                                             |
| `autoclip`            | `false`              | when mpv starts, automatically copy subs to the clipboard as they appear on screen.                                                             |
| `nuke_spaces`         | `true`               | remove all spaces from the subtitle text. only makes sense for languages without spaces like japanese.                                          |
| `human_readable_time` | `true`               | format timestamps according to this pattern: `%dh%02dm%02ds%03dms`. otherwise use seconds.                                                      |
| `snapshot_quality`    | `5`                  | 0 = lowest, 100=highest                                                                                                                         |
| `snapshot_width`      | `-2`                 | a positive integer. if either (but not both) of the width or height parameters is -2, the value will be calculated preserving the aspect-ratio. |
| `snapshot_height`     | `200`                | same as `snapshot_width`.                                                                                                                       |
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
