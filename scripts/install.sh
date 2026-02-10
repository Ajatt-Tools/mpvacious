#!/bin/bash

# Install mpvacious using Bash on GNU/Linux or macOS.
# Based on: https://github.com/tomasklaen/uosc/tree/b77c1f95a877979bd5acef63bad84b03275a18af/installers

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

prog=mpvacious
package=subs2srs
zip_file=/tmp/${prog}.zip
install_targets=("scripts/${prog}" "scripts/${package}")
dependencies=(curl unzip)
mpv_config_dir=~/.config/mpv
latest_version=v0.0.0

abort() {
	echo "Error: $1"
	echo "Aborting!"

	rm -f -- "$zip_file" || true

	echo "Deleting potentially broken install..."
	for target in "${install_targets[@]}"; do
		rm -rf -- "${mpv_config_dir:?}/$target" || true
	done

	echo "Restoring backup..."
	for target in "${install_targets[@]}"; do
		from_path="$backup_dir/$target"
		if [[ -e "$from_path" ]]; then
			to_path="$mpv_config_dir/$target"
			to_dir="$(dirname -- "${to_path}")"
			mkdir -pv -- "$to_dir" || true
			mv -- "$from_path" "$to_path" || true
		fi
	done

	echo "Deleting backup..."
	rm -rf -- "$backup_dir" || true

	exit 1
}

die() {
	echo "$*" >&2
	exit 1
}

set_latest_version() {
	local -r api_url="https://api.github.com/repos/Ajatt-Tools/mpvacious/releases/latest"
	latest_version=$(
		curl -Ls "$api_url" |
			grep -Po '"tag_name":\s*"\K[^"]+(?=")'
	) || die "Failed to find the latest $prog version."
	if [ -z "$latest_version" ]; then
		die "Failed to find the latest $prog version."
	fi
}

check_missing_dependencies() {
	local -a missing_dependencies=()
	for name in "${dependencies[@]}"; do
		if [ ! -x "$(command -v "$name")" ]; then
			missing_dependencies+=("$name")
		fi
	done

	if [ ! ${#missing_dependencies[@]} -eq 0 ]; then
		die "Missing dependencies: ${missing_dependencies[*]}"
	fi
}

set_mpv_config_dir() {
	# Determine install directory
	OS="$(uname)"
	if [ ! -z "${MPV_CONFIG_DIR-}" ]; then
		mpv_config_dir="${MPV_CONFIG_DIR}"
		echo "Installing into (MPV_CONFIG_DIR): $mpv_config_dir"
	elif [ "${OS}" == "Linux" ]; then
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
	elif [ "${OS}" == "Darwin" ]; then
		mpv_config_dir=~/.config/mpv
		echo "Installing into Config location: $mpv_config_dir"
	else
		die "This install script works only on GNU/Linux and macOS."
	fi
}

backup_existing_mpvacious_installation() {
	echo "Backing up..."
	rm -rf -- "$backup_dir" || die "Couldn't cleanup backup directory."
	for target in "${install_targets[@]}"; do
		from_path="$mpv_config_dir/$target"
		if [[ -L "$from_path" ]]; then
			rm -f -- "$from_path" || abort "Couldn't remove symlink: $from_path"
		elif [[ -e "$from_path" ]]; then
			to_path="$backup_dir/$target"
			to_dir="$(dirname -- "${to_path}")"
			mkdir -p -- "$to_dir" || abort "Couldn't create backup folder: $to_dir"
			mv -- "$from_path" "$to_path" || abort "Couldn't move '$from_path' to '$to_path'."
		fi
	done
}

download_default_config_file() {
	# Download default config if one doesn't exist yet
	mpv_script_opts_dir="$mpv_config_dir/script-opts"
	conf_file="$mpv_script_opts_dir/${package}.conf"
	if [ ! -f "$conf_file" ]; then
		echo "Config not found, downloading default ${package}.conf..."
		mkdir -p -- "$mpv_script_opts_dir" || echo "Couldn't create: $mpv_script_opts_dir"
		curl -Ls -o "$conf_file" "$conf_url" || echo "Couldn't download: $conf_url"
	fi
}

main() {
	# Check dependencies
	check_missing_dependencies

	set_latest_version

	# Example: https://github.com/Ajatt-Tools/mpvacious/releases/download/v26.1.26.0/mpvacious_v26.1.26.0.zip
	local -r zip_url="https://github.com/Ajatt-Tools/${prog}/releases/latest/download/${prog}_${latest_version}.zip"
	local -r conf_url="https://github.com/Ajatt-Tools/${prog}/releases/latest/download/${package}.conf"

	set_mpv_config_dir

	local -r backup_dir="$mpv_config_dir/.${prog}-backup"

	case ${1-} in
	--version)
		echo "latest version: $latest_version"
		exit
		;;
	esac

	echo "→ $mpv_config_dir"
	mkdir -p -- "$mpv_config_dir/scripts" || die "Couldn't create mpv scripts directory."

	backup_existing_mpvacious_installation

	# Install new version
	echo "Downloading archive..."
	curl -Ls -o "$zip_file" "$zip_url" || abort "Couldn't download: $zip_url"
	echo "Extracting archive..."
	unzip -qod "$mpv_config_dir/scripts" "$zip_file" || abort "Couldn't extract: $zip_file"
	echo "Deleting downloaded archive..."
	rm -f -- "$zip_file" || echo "Couldn't delete: $zip_file"
	echo "Deleting backup..."
	rm -rf -- "$backup_dir" || echo "Couldn't delete: $backup_dir"

	download_default_config_file

	echo "${prog} has been installed."
}

main "$@"
