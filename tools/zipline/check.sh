#!/bin/sh
# Builds every zipline curve the city can contain, outside Roblox, and checks
# each one against the street it has to stay in.
#
# ZipPath is a pure function of a params table: no services, no instances, no
# yielding, no randomness. That is what makes it runnable here, and running it
# here is what catches a wrap that clips the facade it is meant to hold clear
# of, or a corkscrew whose taper stops short of the landing pad. Both are
# invisible in a diff and cost a Studio session to find, and unlike the pet
# rigs, half of them only happen on one door cell in thirty-two.
#
# Reuses the pet look check's Vector3 stub; nothing else in that file is needed
# and nothing here is shipped, tools/ being outside the three src/ folders Rojo
# maps.
#
# Usage: tools/zipline/check.sh
# Requires the luau CLI, which rokit already installed as a rojo dependency.

set -e

here=$(dirname "$0")
root=$here/../..

luau=$(command -v luau || echo "$HOME/.rokit/tool-storage/luau-lang/luau/0.732.0/luau")
if [ ! -x "$luau" ]; then
	echo "luau not found; install it with 'rokit add luau-lang/luau'" >&2
	exit 1
fi

run=$(mktemp -t zipline)
{
	cat "$root/tools/petlooks/stubs.lua"
	echo 'ZipPath = (function()'
	cat "$root/src/server/ZipPath.lua"
	echo 'end)()'
	cat "$here/driver.lua"
} >"$run"

# Not under set -e: the whole point is to report a non-zero exit, and the
# temporary file has to be cleaned up either way.
status=0
"$luau" "$run" || status=$?
rm -f "$run"
exit $status
