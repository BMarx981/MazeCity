-- Minimal Roblox datatype stubs so PetModelGenerator can be run under the luau
-- CLI. Enough to execute build() and read the geometry back out.

local V = {}
V.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X * self.X + self.Y * self.Y + self.Z * self.Z)
	end
	if key == "Unit" then
		local length = self.Magnitude
		return Vector3.new(self.X / length, self.Y / length, self.Z / length)
	end
	return rawget(V, key)
end
function V.__mul(a, b)
	if type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
function V.__add(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
function V.__sub(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
function V.__unm(a)
	return Vector3.new(-a.X, -a.Y, -a.Z)
end

Vector3 = {}
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __t = "Vector3" }, V)
end
Vector3.zero = Vector3.new(0, 0, 0)

Color3 = {}
function Color3.fromRGB(r, g, b)
	return { R = r, G = g, B = b, __t = "Color3" }
end
function Color3.new(r, g, b)
	return { R = r * 255, G = g * 255, B = b * 255, __t = "Color3" }
end

local C = {}
C.__index = function(self, key)
	if key == "Position" then
		return Vector3.new(self.p[1], self.p[2], self.p[3])
	end
	if key == "X" then
		return self.p[1]
	end
	if key == "Y" then
		return self.p[2]
	end
	if key == "Z" then
		return self.p[3]
	end
	return rawget(C, key)
end

local function cframe(r, p)
	return setmetatable({ r = r, p = p, __t = "CFrame" }, C)
end

local IDENTITY = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }

function C.__mul(a, b)
	if b.__t == "Vector3" then
		return Vector3.new(
			a.p[1] + a.r[1][1] * b.X + a.r[1][2] * b.Y + a.r[1][3] * b.Z,
			a.p[2] + a.r[2][1] * b.X + a.r[2][2] * b.Y + a.r[2][3] * b.Z,
			a.p[3] + a.r[3][1] * b.X + a.r[3][2] * b.Y + a.r[3][3] * b.Z
		)
	end
	local r = {}
	for i = 1, 3 do
		r[i] = {}
		for j = 1, 3 do
			local sum = 0
			for k = 1, 3 do
				sum = sum + a.r[i][k] * b.r[k][j]
			end
			r[i][j] = sum
		end
	end
	local p = {}
	for i = 1, 3 do
		p[i] = a.p[i] + a.r[i][1] * b.p[1] + a.r[i][2] * b.p[2] + a.r[i][3] * b.p[3]
	end
	return cframe(r, p)
end

-- The transpose plus the negated, rotated position, which is the whole of a
-- rigid inverse. PetRigDriver needs it to turn a pose it wants into the Transform
-- that produces it.
function C.Inverse(self)
	local r = {}
	for i = 1, 3 do
		r[i] = {}
		for j = 1, 3 do
			r[i][j] = self.r[j][i]
		end
	end
	local p = {}
	for i = 1, 3 do
		p[i] = -(r[i][1] * self.p[1] + r[i][2] * self.p[2] + r[i][3] * self.p[3])
	end
	return cframe(r, p)
end

CFrame = {}
function CFrame.new(x, y, z)
	if type(x) == "table" and x.__t == "Vector3" then
		return cframe(IDENTITY, { x.X, x.Y, x.Z })
	end
	return cframe(IDENTITY, { x or 0, y or 0, z or 0 })
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx = math.cos(rx), math.sin(rx)
	local cy, sy = math.cos(ry), math.sin(ry)
	local cz, sz = math.cos(rz), math.sin(rz)
	local Rx = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Ry = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Rz = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return cframe(Rx, { 0, 0, 0 }) * cframe(Ry, { 0, 0, 0 }) * cframe(Rz, { 0, 0, 0 })
end

function typeof(value)
	if type(value) == "table" and value.__t then
		return value.__t
	end
	return type(value)
end

Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, {
			__index = function(_, item)
				return { EnumItem = group .. "." .. item }
			end,
		})
	end,
})

CREATED = {}

Instance = {}
function Instance.new(className)
	local inst = {
		-- typeof(x) == "Instance" is how rigOf tells a single joint from the list
		-- of them it keeps under the same key, so the stub has to answer it.
		__t = "Instance",
		ClassName = className,
		Name = className,
		CFrame = CFrame.new(0, 0, 0),
		Size = Vector3.new(1, 1, 1),
		Position = Vector3.new(0, 0, 0),
		attributes = {},
		children = {},
	}
	function inst:SetAttribute(key, value)
		self.attributes[key] = value
	end
	function inst:GetAttribute(key)
		return self.attributes[key]
	end
	function inst:FindFirstChild(name)
		for _, child in ipairs(self.children) do
			if child.Name == name then
				return child
			end
		end
		return nil
	end
	setmetatable(inst, {
		__newindex = function(t, key, value)
			if key == "Parent" and value ~= nil then
				table.insert(value.children, t)
			end
			rawset(t, key, value)
		end,
	})
	table.insert(CREATED, inst)
	return inst
end

local rsChild = {}
function rsChild:WaitForChild(name)
	return name
end

game = {}
function game:GetService()
	return rsChild
end
