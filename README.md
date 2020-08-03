# mpvacious


## Installation

1. Obtain the script
If you already have your dotfiles set up according to
[Arch Wiki recommendations](https://wiki.archlinux.org/index.php/Dotfiles#Tracking_dotfiles_directly_with_Git), execute
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
