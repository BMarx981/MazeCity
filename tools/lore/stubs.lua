-- Minimal Roblox surface so LoreService can be run under the luau CLI. Enough
-- to require it, hand it a profile, and fire the three channels it listens on.
--
-- Instances are name-tagged tables and `require` dispatches on the tag, which is
-- the same trick tools/petlooks uses: the repo's requires all look like
-- require(SomeService:WaitForChild("Name")), so the marker only has to carry
-- that name.

MODULES = {}

local function container(name)
	local c = { Name = name, children = {} }
	function c:FindFirstChild(childName)
		return self.children[childName]
	end
	function c:WaitForChild(childName)
		if not self.children[childName] then
			self.children[childName] = { Name = childName, Parent = self }
		end
		return self.children[childName]
	end
	return c
end

-- A shared ModuleScript reaches its siblings as script.Parent:WaitForChild(...)
-- rather than through a service, so the catalogues need one of these to be
-- loadable here at all. Parented to ReplicatedStorage's own container, which is
-- where Rojo puts them, so both spellings of a sibling resolve to one marker.
local replicated = container("ReplicatedStorage")
script = { Name = "harness", Parent = replicated }

local SERVICES = {
	ReplicatedStorage = replicated,
	ServerScriptService = container("ServerScriptService"),
	Players = container("Players"),
	SoundService = container("SoundService"),
	Debris = container("Debris"),
	TweenService = container("TweenService"),
	CollectionService = container("CollectionService"),
	RunService = container("RunService"),
	MarketplaceService = container("MarketplaceService"),
	ServerStorage = container("ServerStorage"),
}

-- LoreService drops a player's sync floor when they leave, so the Players stub
-- carries the one signal it connects to. Nothing in the harness fires it; what
-- matters is that connecting does not error.
SERVICES.Players.PlayerRemoving = {
	Connect = function()
		return { Disconnect = function() end }
	end,
}

game = {}
function game:GetService(name)
	if not SERVICES[name] then
		SERVICES[name] = container(name)
	end
	return SERVICES[name]
end

-- The queue behind task.defer. LoreService defers its re-checks on purpose, so
-- the harness has to model that rather than flatten it: draining is explicit and
-- the driver does it where a frame boundary would be.
DEFERRED = {}
task = {
	defer = function(fn, ...)
		table.insert(DEFERRED, { fn = fn, args = table.pack(...) })
	end,
	delay = function(_, fn)
		table.insert(DEFERRED, { fn = fn, args = table.pack() })
	end,
	wait = function() end,
	spawn = function(fn, ...)
		fn(...)
	end,
}

function drain()
	local guard = 0
	while #DEFERRED > 0 do
		guard = guard + 1
		assert(guard < 1000, "deferred queue never emptied")
		local job = table.remove(DEFERRED, 1)
		job.fn(table.unpack(job.args, 1, job.args.n))
	end
end

-- Every remote and bindable this harness sees. FIRED records what reached a
-- client so the driver can assert on the toasts rather than on the profile only.
FIRED = {}

local function signal()
	local handlers = {}
	return {
		Connect = function(_, fn)
			table.insert(handlers, fn)
			return { Disconnect = function() end }
		end,
		emit = function(...)
			for _, fn in ipairs(handlers) do
				fn(...)
			end
		end,
	}
end

Instance = {}
function Instance.new(className)
	local inst = { ClassName = className, Name = "", children = {} }
	local ev = signal()
	inst.Event = ev
	inst.OnClientEvent = ev
	function inst:Fire(...)
		ev.emit(...)
	end
	inst.OnServerEvent = signal()
	function inst:FireClient(player, payload)
		table.insert(FIRED, { player = player, payload = payload })
	end
	function inst:FireAllClients(payload)
		table.insert(FIRED, { player = nil, payload = payload })
	end
	function inst:FindFirstChild(name)
		return self.children[name]
	end
	function inst:WaitForChild(name)
		return self.children[name]
	end
	function inst:Destroy() end
	setmetatable(inst, {
		__newindex = function(t, k, v)
			if k == "Parent" and v and v.children then
				v.children[rawget(t, "Name")] = t
			end
			rawset(t, k, v)
		end,
	})
	return inst
end

Color3 = {
	fromRGB = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
	new = function(r, g, b)
		return { R = r * 255, G = g * 255, B = b * 255 }
	end,
	fromHSV = function()
		return { R = 0, G = 0, B = 0 }
	end,
}

local V = {}
V.__index = V
Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V)
end
Vector3.zero = Vector3.new(0, 0, 0)
Vector2 = { new = Vector3.new }

-- Enum is asked for members it does not have all over MazeConfig; answering
-- every one with a stand-in keeps the stub from growing a list that has to be
-- maintained alongside the config.
local anyEnum = setmetatable({}, {
	__index = function(t, k)
		local v = setmetatable({ Name = k }, { __index = function(_, kk)
			return { Name = kk }
		end })
		rawset(t, k, v)
		return v
	end,
})
Enum = anyEnum

UDim2 = { new = function() return {} end, fromOffset = function() return {} end, fromScale = function() return {} end }
UDim = { new = function() return {} end }
CFrame = { new = function() return {} end, Angles = function() return {} end }
NumberRange = { new = function() return {} end }
NumberSequence = { new = function() return {} end }
ColorSequence = { new = function() return {} end }
BrickColor = { new = function() return {} end }
Font = { fromName = function() return {} end }

os = os or {}
