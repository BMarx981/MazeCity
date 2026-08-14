#!/bin/sh
# Builds street plans for every door configuration the city can contain, outside
# Roblox, and checks each one against what generation had already put on the
# ground.
#
# StreetPlan is a pure function of a spec table and an rng: no services, no
# instances, no yielding, no world state. That is what makes it runnable here,
# and running it here is what catches a wall standing in the slide's landing, a
# spawn pad walled off from the door it serves, or an overlook with a second way
# out. All three are invisible in a diff, and the last two only happen for some
# doors on some seeds, which is exactly the class of bug a Studio session finds
# by accident three playtests later.
#
# The rng is an LCG rather than Roblox's, so this checks the properties every
# plan must have and not the literal city. The literal city is what a double
# build with the same seed verifies.
#
# ZipPath is wrapped too: the low end of a zip cable is a reservation the plan
# has to honour, and it is read off the real curve rather than approximated.
# Reuses the pet look check's Vector3 stub, tools/ being outside the three src/
# folders Rojo maps.
#
# Usage: tools/street/check.sh
# Requires the luau CLI, which rokit already installed as a rojo dependency.

set -e

here=$(dirname "$0")
root=$here/../..

luau=$(command -v luau || echo "$HOME/.rokit/tool-storage/luau-lang/luau/0.732.0/luau")
if [ ! -x "$luau" ]; then
	echo "luau not found; install it with 'rokit add luau-lang/luau'" >&2
	exit 1
fi

run=$(mktemp -t street)
{
	cat "$root/tools/petlooks/stubs.lua"
	cat "$here/random.lua"
	echo 'ZipPath = (function()'
	cat "$root/src/server/ZipPath.lua"
	echo 'end)()'
	echo 'StreetPlan = (function()'
	cat "$root/src/server/StreetPlan.lua"
	echo 'end)()'
	cat "$here/driver.lua"
} >"$run"

# Not under set -e: the whole point is to report a non-zero exit, and the
# temporary file has to be cleaned up either way.
status=0
"$luau" "$run" || status=$?
rm -f "$run"
exit $status
