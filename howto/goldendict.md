# Modifying cards added with GoldenDict

You can add a card first using GoldenDict,
and then append an audio clip and a picture to it.

**Note:** the only version of GoldenDict that can create Anki cards with configurable fields is
[this one](https://github.com/xiaoyifang/goldendict).
Read [How to connect with Anki](https://github.com/xiaoyifang/goldendict/blob/staged/howto/how%20to%20connect%20with%20anki.md)
if you are new to GoldenDict.

To send subtitles from `mpv` directly to GoldenDict,
append the following line to `subs2srs.conf`:

```
autoclip_command=goldendict
```

**Note:** If `goldendict` is not in the PATH, you have to specify the entire path to the executable.

1) Press <kbd>a</kbd> to open `advanced menu`.
2) Press <kbd>t</kbd> to toggle the `autoclip` option.

Now as subtitles appear on the screen,
they will be immediately sent to GoldenDict instead of the system clipboard.

1) Open GoldenDict.
2) Play a video in `mpv`.
3) When you find an unknown word, select the definition text, right-click and select "send word to anki" to make a card.
4) Go back to mpv and add an image and an audio clip
   to the card you've just made by pressing <kbd>m</kbd> while the `advanced menu` is open.
   Pressing <kbd>Shift+m</kbd> will overwrite any existing data in media fields.

Don't forget to set the right timings and join lines together
if the sentence is split between multiple subs.
To do it, enter interactive selection by pressing <kbd>c</kbd>
and seek to the next or previous subtitle.

To pair Mecab and GoldenDict, install [gd-tools](https://github.com/Ajatt-Tools/gd-tools).
