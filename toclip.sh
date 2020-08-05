#!/usr/bin/sh
printf -- '%s\n' "$*" | xclip -selection clipboard &
