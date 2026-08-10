#!/bin/sh
# Builds every pet at every stage outside Roblox and checks the geometry.
#
# PetModelGenerator.build is a pure function of (petId, stage): no services, no
# yielding, no ServerStorage. That is what makes it runnable here, and running it
# here is what catches a recipe that puts an accent inside the body it was meant
# to hang off, which is invisible in a diff and costs a Studio session to find.
#
# stubs.lua is the smallest Color3/Vector3/CFrame/Instance that will carry the
# builder; driver.lua is the checks. Neither is shipped: tools/ is outside the
# three src/ folders Rojo maps, so nothing here reaches the place file.
#
# Usage: tools/petlooks/check.sh
# Requires the luau CLI, which rokit already installed as a rojo dependency.

set -e

here=$(dirname "$0")
root=$here/../..
shared=$root/src/shared

luau=$(command -v luau || echo "$HOME/.rokit/tool-storage/luau-lang/luau/0.732.0/luau")
if [ ! -x "$luau" ]; then
	echo "luau not found; install it with 'rokit add luau-lang/luau'" >&2
	exit 1
fi

run=$(mktemp -t petlooks)
{
	cat "$here/stubs.lua"
	echo 'PetCatalog = (function()'
	cat "$shared/PetCatalog.lua"
	echo 'end)()'
	echo 'require = function() return PetCatalog end'
	echo 'PetModelGenerator = (function()'
	cat "$shared/PetModelGenerator.lua"
	echo 'end)()'
	cat "$here/driver.lua"
} >"$run"

# Not under set -e: the whole point is to report a non-zero exit, and the
# temporary file has to be cleaned up either way.
status=0
"$luau" "$run" || status=$?
rm -f "$run"
exit $status
