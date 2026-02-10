#!/bin/bash

# This script is used to install mpvacious in a development mode.
# It just symlinks the mpvacious directory to ~/.config/mpv/scripts
# This way, when you change *.lua files, the changes will be applied immediately after restarting mpv.

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

prog=mpvacious
mpv_config_dir=~/.config/mpv

die() {
	echo "$*" >&2
	exit 1
}

set_mpv_config_dir() {
	# Determine install directory (path to mpv config directory, e.g. ~/.config/mpv)
	if [[ -n "${MPV_CONFIG_DIR-}" ]]; then
		mpv_config_dir="${MPV_CONFIG_DIR}"
		echo "Installing into (MPV_CONFIG_DIR): $mpv_config_dir"
		return
	fi
	case "$(uname)" in
		Linux)
			if [ -d "$HOME/.var/app/io.mpv.Mpv" ]; then
				# Flatpak
				mpv_config_dir="$HOME/.var/app/io.mpv.Mpv/config/mpv"
				echo "Installing into (flatpak io.mpv.Mpv package): $mpv_config_dir"
			elif [ -d "$HOME/snap/mpv" ]; then
				# Snap mpv
				mpv_config_dir="$HOME/snap/mpv/current/.config/mpv"
				echo "Installing into (snap mpv package): $mpv_config_dir"
			elif [ -d "$HOME/snap/mpv-wayland" ]; then
				# Snap mpv-wayland
				mpv_config_dir="$HOME/snap/mpv-wayland/common/.config/mpv"
				echo "Installing into (snap mpv-wayland package): $mpv_config_dir"
			else
				# ~/.config
				mpv_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/mpv"
				echo "Installing into Config location: $mpv_config_dir"
			fi
			;;
		Darwin)
			mpv_config_dir=~/.config/mpv
			echo "Installing into Config location: $mpv_config_dir"
			;;
		*)
			die "This install script works only on Linux and macOS."
			;;
	esac
}

delete_existing_installation() {
	if [[ -L $install_dest ]]; then
		rm -f -- "$install_dest"
	elif [[ -e "$install_dest" ]]; then
		gio trash -- "$install_dest" ||
			trash-put -- "$install_dest" ||
			die "Couldn't delete directory: $install_dest"
	fi
}

main() {
	[[ -d $prog ]] || die "Directory does not exist: $prog"
	set_mpv_config_dir
	mkdir -p -- "$mpv_config_dir/scripts" || die "Couldn't create mpv scripts directory."
	echo "Removing existing installation..."
	install_dest="$mpv_config_dir/scripts/$prog"
	delete_existing_installation
	echo "Linking directory..."
	ln -srf "./$prog" "$install_dest" || die "Couldn't symlink: $install_dest"
	echo "${prog} has been installed in development mode."
}

main "$@"
