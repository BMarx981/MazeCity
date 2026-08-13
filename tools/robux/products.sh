#!/bin/sh
# Prints the full developer-product table (item, coin cost, raw curve price,
# rung, product id) under the luau CLI, outside Roblox. This is the dashboard
# worklist: creating or repricing the products is reading this one list, and a
# row whose id column says unset is a product not yet created or not yet pasted
# into its catalogue row.
#
# Storefront is pure and rows() is the one enumeration of what the game sells,
# so this prints exactly what PurchaseService's price audit will check. Reuses
# tools/petlooks/stubs.lua for the Color3/Vector3/Enum the config files touch;
# tools/ is outside the three src/ folders Rojo maps, so nothing here reaches
# the place file.
#
# Usage: tools/robux/products.sh

set -e

here=$(dirname "$0")
root=$here/../..
shared=$root/src/shared

luau=$(command -v luau || echo "$HOME/.rokit/tool-storage/luau-lang/luau/0.732.0/luau")
if [ ! -x "$luau" ]; then
	echo "luau not found; install it with 'rokit add luau-lang/luau'" >&2
	exit 1
fi

# Each shared module is wrapped as a named entry in a modules table, and the
# stubbed require resolves the name that the stubbed WaitForChild returned, so
# Storefront's real require lines run unedited.
run=$(mktemp -t robuxproducts)
{
	cat "$root/tools/petlooks/stubs.lua"
	echo 'script = { Parent = { WaitForChild = function(_, name) return name end } }'
	echo 'MODULES = {}'
	echo 'require = function(name) return MODULES[name] end'
	for module in MazeConfig EggCatalog AccessoryCatalog PetCatalog Storefront; do
		echo "MODULES.$module = (function()"
		cat "$shared/$module.lua"
		echo 'end)()'
	done
	cat "$here/products.lua"
} >"$run"

status=0
"$luau" "$run" || status=$?
rm -f "$run"
exit $status
