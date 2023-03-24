#!/bin/sh

# Find full path to an opened Anki collection.

readlink -f -- /proc/$(pgrep '^anki$')/fd/* | grep 'collection.anki2$'
