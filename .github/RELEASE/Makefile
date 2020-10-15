PROJECT = mpvacious
VERSION = v0.2

.PHONY: clean all windows linux
all: linux windows

linux:
	git show "remotes/origin/master:subs2srs.lua"  > $(PROJECT)_$@_$(VERSION).lua

windows:
	git show "remotes/origin/windows:subs2srs.lua" > $(PROJECT)_$@_$(VERSION).lua

clean:
	rm -v -- ./$(PROJECT)_*.lua
