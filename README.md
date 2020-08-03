# mpvacious


## Installation

Clone the repo
```
$ git clone 'git@github.com:Ajatt-Tools/mpvacious.git' ~/.config/mpv/scripts/subs2srs

```
Modify ```~/.config/mpv/scripts/modules.lua```
```
local mpv_scripts_dir_path = os.getenv("HOME") ..  "/.config/mpv/scripts/"
function load(relative_path) dofile(mpv_scripts_dir_path .. relative_path) end
load("subs2srs/subs2srs.lua")
```
