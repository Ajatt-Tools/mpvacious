# Flatpak notes

We think it's best to never use Flatpak.
Specifically, try not to use Flatpak to install `mpv` and `anki`.
Install packages from the official repositories of your distro or from the AUR.

Read the following notes if you still decide to use Flatpak.

Make these changes in Flatseal:

* Enable "Filesystem > All system files"
  so it could see `wl-copy`.
  Unfortunately, there's no option to provide only a specific system file.
* Add `~/.var/app/net.ankiweb.Anki` to "Filesystem > Other Files"
  so mpvacious could add encoded snapshots and audio to Anki.
* Add `PATH=/home/USERNAME/.local/bin:/home/USERNAME/bin:/app/bin:/usr/bin:/run/host/usr/bin` to "Environment > Variables".
  There's no option to add a path to `PATH` in Flatseal,
  so I opened container,
  saved it's PATH and added `/run/host/usr/bin`
  so mpvacuous could access `wl-copy`.
* Enable "Shared > Network".
  It's enabled by default, but anyway.

The mpv config root is `~/.var/app/io.mpv.Mpv/config/mpv`

* `~/.var/app/io.mpv.Mpv/config/mpv/scripts`
* `~/.var/app/io.mpv.Mpv/config/mpv/script-opts`
