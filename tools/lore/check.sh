#!/bin/sh
# Drives LoreService's unlock rule outside Roblox, which is where Clutch 7's exit
# criterion actually lives: a fresh save must be able to unlock fragments 1 to 17
# by playing, in order, with out-of-order accomplishments banked correctly.
#
# It is runnable here because the rule is a function of the profile plus what
# arrived on three channels, and none of the three needs a world: the service
# reads data.stats, banks flags into data.codex.journal, and fires a remote. So
# the harness stubs a profile and the channels and asserts on both halves, the
# unlock count and the toasts, rather than on one and hoping about the other.
#
# What it deliberately cannot cover is EnemyLore's own half, the encounter
# pairing, which needs a live controller and a humanoid to be dead or alive: that
# is the Studio pass. Everything downstream of a fact arriving is here.
#
# Usage: tools/lore/check.sh
# Requires the luau CLI, which rokit already installed as a rojo dependency.

set -e

here=$(dirname "$0")
root=$here/../..
shared=$root/src/shared
server=$root/src/server

# The rokit shim on PATH refuses to run a tool that is not in aftman.toml, and
# luau is not: it arrived as a rojo dependency. So the real binary is preferred
# over whatever `luau` resolves to.
luau="$HOME/.rokit/tool-storage/luau-lang/luau/0.732.0/luau"
if [ ! -x "$luau" ]; then
	luau=$(command -v luau || echo "$luau")
fi
if [ ! -x "$luau" ]; then
	echo "luau not found; install it with 'rokit add luau-lang/luau'" >&2
	exit 1
fi

run=$(mktemp -t lorecheck)
{
	cat "$here/stubs.lua"
	echo 'MODULES.MazeConfig = (function()'
	cat "$shared/MazeConfig.lua"
	echo 'end)()'
	echo 'MODULES.Journal = (function()'
	cat "$shared/Journal.lua"
	echo 'end)()'
	cat "$here/profiles.lua"
	echo 'require = function(marker)'
	echo '	local name = type(marker) == "table" and marker.Name or tostring(marker)'
	echo '	local m = MODULES[name]'
	echo '	assert(m, "no stub module for " .. tostring(name))'
	echo '	return m'
	echo 'end'
	# The four catalogues and Lore itself, loaded through the shim above because
	# they require each other. Lore validates its own keys at require time, so
	# standing them up here is what makes that check run every time this does:
	# an inscription for gear that does not exist stops the harness rather than
	# drawing a blank row in a chapter nobody opened yet.
	for name in EnemyTypes EnemyDefinitions PetCatalog EggCatalog AccessoryCatalog Lore; do
		echo "MODULES.$name = (function()"
		cat "$shared/$name.lua"
		echo 'end)();'
	done
	echo '(function()'
	cat "$server/LoreService.server.lua"
	echo 'end)()'
	cat "$here/driver.lua"
} >"$run"

status=0
"$luau" "$run" || status=$?
rm -f "$run"
exit $status
