--[[
    AEROVOLT  |  LocalScript -> StarterPlayer > StarterPlayerScripts
    ClickGUI style dropdown menu.

    RightShift         open / close menu (changeable in Settings > GUI)
    Left click module  toggle it (Action modules run, Settings-tab entries expand)
    Right click module drop down its settings + keybind
    Drag panel header  move panel      |  Right click header: collapse panel
    Search bar         Ctrl+F or click it. Enter toggles the top result
]]

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local UIS             = game:GetService("UserInputService")
local TweenService    = game:GetService("TweenService")
local Lighting        = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local Stats           = game:GetService("Stats")
local TextService     = game:GetService("TextService")
local GuiService      = game:GetService("GuiService")

local LP     = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local Mouse  = LP:GetMouse()
local PG     = LP:WaitForChild("PlayerGui")

local oldGui = PG:FindFirstChild("AerovoltClient"); if oldGui then oldGui:Destroy() end
local oldBlur = Lighting:FindFirstChild("AerovoltBlur"); if oldBlur then oldBlur:Destroy() end
pcall(function() RunService:UnbindFromRenderStep("AerovoltRender") end)

local CLIENT, VERSION = "AEROVOLT", "v2.10"
local FONT, FONT_B = Enum.Font.GothamMedium, Enum.Font.GothamBold

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local Conns = {}
local function Conn(sig, fn) local c = sig:Connect(fn); table.insert(Conns, c); return c end
local function Safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then warn("[Aerovolt] " .. tostring(err)) end
end
local function Hum() local c = LP.Character return c and c:FindFirstChildOfClass("Humanoid") end
local function Root() local c = LP.Character return c and c:FindFirstChild("HumanoidRootPart") end
local function Typing() return UIS:GetFocusedTextBox() ~= nil end
local function Down(k) return UIS:IsKeyDown(k) and not Typing() end
local function RayParams()
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { LP.Character }
	return p
end
local function New(class, props, parent)
	local i = Instance.new(class)
	for k, v in pairs(props) do i[k] = v end
	if parent then i.Parent = parent end
	return i
end
local function Fmt(v) return string.format("%g", v) end
local function B255(x) return math.floor(x * 255 + 0.5) end
local function Rgb(c) return string.format("rgb(%d,%d,%d)", B255(c.R), B255(c.G), B255(c.B)) end

----------------------------------------------------------------------
-- theme + painters (anything that depends on accent / state)
----------------------------------------------------------------------
local Themes = {
	Purple = Color3.fromRGB(160, 90, 255), Blue = Color3.fromRGB(70, 130, 255),
	Cyan = Color3.fromRGB(0, 200, 215),    Green = Color3.fromRGB(70, 215, 110),
	Red = Color3.fromRGB(255, 70, 80),     Orange = Color3.fromRGB(255, 150, 50),
	Pink = Color3.fromRGB(255, 100, 200),  Rainbow = Color3.new(1, 1, 1),
}
local ThemeOrder = { "Purple", "Blue", "Cyan", "Green", "Red", "Orange", "Pink", "Rainbow" }
local ThemeName, RainbowSpeed = "Purple", 0.25

local function Accent(offset)
	if ThemeName == "Rainbow" then
		return Color3.fromHSV((tick() * RainbowSpeed + (offset or 0)) % 1, 0.65, 1)
	end
	return Themes[ThemeName]
end

local Painters = {}
local function AddPainter(inst, fn, mod)
	fn()
	table.insert(Painters, { inst = inst, fn = fn, mod = mod })
end
local function Repaint(mod)
	for i = #Painters, 1, -1 do
		local p = Painters[i]
		if not p.inst.Parent then table.remove(Painters, i)
		elseif mod == nil or p.mod == mod then p.fn() end
	end
end
local function Reg(inst, prop, offset)
	AddPainter(inst, function() inst[prop] = Accent(offset) end)
end

local C_HEAD, C_ROW, C_ROWHOV, C_SET = Color3.fromRGB(16, 16, 22), Color3.fromRGB(24, 24, 32), Color3.fromRGB(38, 38, 50), Color3.fromRGB(15, 15, 20)
local C_DIM, C_LIGHT, WHITE = Color3.fromRGB(135, 135, 150), Color3.fromRGB(200, 200, 212), Color3.new(1, 1, 1)

----------------------------------------------------------------------
-- module system
----------------------------------------------------------------------
local Categories = { "Combat", "Movement", "Player", "Render", "Utility", "Settings" }
local CatDesc = {
	Combat = "Aim helpers, hitbox tools and targeting for your own game.",
	Movement = "Modules that change how you move around the world.",
	Player = "Modules that change or protect your own character.",
	Render = "Modules that change what you see on your screen.",
	Utility = "Teleports, tools and quality-of-life modules.",
	Settings = "Configure Aerovolt itself: theme, menu, array list and more.",
}
local Modules, ByCat = {}, {}
for _, c in ipairs(Categories) do ByCat[c] = {} end
local ui = {}

local function Module(def)
	def.Enabled, def.Values, def._conns = false, {}, {}
	def.BindMode = "Toggle"
	for _, s in ipairs(def.Settings or {}) do
		if s.Type == "Mode" then
			local o = type(s.Options) == "function" and s.Options() or s.Options
			def.Values[s.Name] = s.Default or o[1]
		else
			def.Values[s.Name] = s.Default
		end
	end
	table.insert(Modules, def)
	table.insert(ByCat[def.Category], def)
	return def
end
local function Hook(m, sig, fn) table.insert(m._conns, sig:Connect(fn)) end

local function SetEnabled(m, state, silent)
	if m.Action or m.Passive or m.Enabled == state then return end
	m.Enabled = state
	if state then
		if m.OnEnable then Safe(m.OnEnable, m) end
	else
		for _, c in ipairs(m._conns) do c:Disconnect() end
		table.clear(m._conns)
		if m.OnDisable then Safe(m.OnDisable, m) end
	end
	if ui.OnToggle then ui.OnToggle(m, silent) end
end
local function ToggleModule(m)
	if m.Action then Safe(m.Action, m) elseif not m.Passive then SetEnabled(m, not m.Enabled) end
end

local function PlayerNames()
	local t = {}
	for _, p in ipairs(Players:GetPlayers()) do if p ~= LP then table.insert(t, p.Name) end end
	if #t == 0 then t[1] = "<none>" end
	return t
end
local function Target(m)
	local p = Players:FindFirstChild(m.Values.Target or "")
	if p and p ~= LP then return p end
	for _, o in ipairs(Players:GetPlayers()) do if o ~= LP then return o end end
end

local function Slider(name, min, max, step, default, desc) return { Name = name, Type = "Slider", Min = min, Max = max, Step = step, Default = default, Desc = desc } end
local function Toggle(name, default, desc) return { Name = name, Type = "Toggle", Default = default, Desc = desc } end
local function Mode(name, options, default, desc, suffix) return { Name = name, Type = "Mode", Options = options, Default = default, Desc = desc, Suffix = suffix } end
local function ColorSet(name, default, desc) return { Name = name, Type = "Color", Default = default, Desc = desc } end
local ColorModes = { "Accent", "Team", "Rainbow", "White", "Red" }

local D_COLOR = "Color used: your accent color, the player's team color, rainbow, white or red."
local D_TEAM = "Ignores players who are on your own team."
local D_DIST = "Players farther away than this (in studs) are ignored."
local D_TARGET = "Which player to use. Left-click for the next player, right-click for the previous one."

----------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------
Module{ Name = "Speed", Category = "Movement", Desc = "Run faster than normal. Pick WalkSpeed for the simplest option, or CFrame / Velocity to push your character along manually.",
	Settings = {
		Mode("Mode", { "WalkSpeed", "CFrame", "Velocity" }, "WalkSpeed", "How speed is applied. WalkSpeed edits your walk speed; CFrame and Velocity move you manually, which works in games that keep resetting WalkSpeed.", true),
		Slider("Speed", 16, 250, 1, 40, "Target speed in studs per second. Roblox's default is 16."),
	},
	OnEnable = function(m) local h = Hum(); m._orig = h and h.WalkSpeed or 16 end,
	OnDisable = function(m) local h = Hum(); if h then h.WalkSpeed = m._orig or 16 end end,
	OnTick = function(m, dt)
		local h, r = Hum(), Root(); if not h or not r then return end
		local mode, sp = m.Values.Mode, m.Values.Speed
		if mode == "WalkSpeed" then h.WalkSpeed = sp; return end
		h.WalkSpeed = m._orig
		local md = h.MoveDirection
		if md.Magnitude > 0 then
			if mode == "CFrame" then
				r.CFrame = r.CFrame + md * math.max(sp - h.WalkSpeed, 0) * dt
			else
				local v = r.AssemblyLinearVelocity
				r.AssemblyLinearVelocity = Vector3.new(md.X * sp, v.Y, md.Z * sp)
			end
		end
	end }

local function FlyClear(m)
	for _, k in ipairs({ "_lv", "_ao", "_att" }) do
		if m[k] then m[k]:Destroy(); m[k] = nil end
	end
end
local function FlyBuild(m, r)
	FlyClear(m)
	m._yaw = m._yaw or 0
	m._att = New("Attachment", { Name = "AerovoltFly" }, r)
	m._lv = New("LinearVelocity", { Attachment0 = m._att, RelativeTo = Enum.ActuatorRelativeTo.World, VelocityConstraintMode = Enum.VelocityConstraintMode.Vector, MaxForce = math.huge, VectorVelocity = Vector3.zero }, r)
	m._ao = New("AlignOrientation", { Attachment0 = m._att, Mode = Enum.OrientationAlignmentMode.OneAttachment, RigidityEnabled = false, MaxTorque = math.huge, Responsiveness = 25, CFrame = CFrame.fromOrientation(0, m._yaw, 0) }, r)
end

Module{ Name = "Fly", Category = "Movement", Desc = "Fly around with WASD, Space to go up and Shift or Ctrl to go down.",
	Settings = {
		Mode("Mode", { "Velocity", "CFrame" }, "Velocity", "Velocity flies with physics and feels smoother. CFrame moves you directly.", true),
		Slider("Speed", 5, 400, 1, 70, "Horizontal flight speed."),
		Slider("Vertical", 5, 250, 1, 55, "Up and down speed."),
		Slider("Smoothing", 1, 30, 1, 10, "How quickly you speed up and slow down. Higher is snappier."),
		Toggle("Face Camera", true, "Turns your character to face where the camera looks."),
	},
	OnEnable = function(m)
		local r, h = Root(), Hum()
		if r then
			local l = r.CFrame.LookVector
			m._yaw = math.atan2(-l.X, -l.Z)
			m._vel = r.AssemblyLinearVelocity
			FlyBuild(m, r)
		end
		if h then h.PlatformStand = true end
	end,
	OnDisable = function(m)
		FlyClear(m)
		local h, r = Hum(), Root()
		if h then h.PlatformStand = false end
		if r then r.AssemblyLinearVelocity = Vector3.zero; r.AssemblyAngularVelocity = Vector3.zero end
	end,
	OnTick = function(m, dt)
		local h, r = Hum(), Root(); if not h or not r then return end
		h.PlatformStand = true
		if not m._lv or m._lv.Parent ~= r then
			m._vel = Vector3.zero
			FlyBuild(m, r)
		end
		local V = m.Values
		local cf, dir, vert = Camera.CFrame, Vector3.zero, 0
		if Down(Enum.KeyCode.W) then dir += cf.LookVector end
		if Down(Enum.KeyCode.S) then dir -= cf.LookVector end
		if Down(Enum.KeyCode.D) then dir += cf.RightVector end
		if Down(Enum.KeyCode.A) then dir -= cf.RightVector end
		if Down(Enum.KeyCode.Space) then vert += 1 end
		if Down(Enum.KeyCode.LeftShift) or Down(Enum.KeyCode.LeftControl) then vert -= 1 end

		-- ease toward the wanted velocity instead of snapping to it
		local target = (dir.Magnitude > 0 and dir.Unit * V.Speed or Vector3.zero) + Vector3.new(0, vert * V.Vertical, 0)
		m._vel = m._vel:Lerp(target, 1 - math.exp(-V.Smoothing * dt))

		-- keep upright, face the camera (or the way you move)
		local flat = V["Face Camera"] and Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z) or Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then m._yaw = math.atan2(-flat.X, -flat.Z) end
		local rot = CFrame.fromOrientation(0, m._yaw, 0)

		if V.Mode == "CFrame" then
			m._ao.Enabled = false
			m._lv.VectorVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
			r.CFrame = CFrame.new(r.Position + m._vel * dt) * rot
		else
			m._ao.Enabled = true
			m._ao.CFrame = rot
			m._lv.VectorVelocity = m._vel
		end
	end }

local CAS = game:GetService("ContextActionService")
local function VFlyClear(m)
	for _, k in ipairs({ "_lv", "_ao", "_att" }) do
		if m[k] then m[k]:Destroy(); m[k] = nil end
	end
	m._root, m._seat = nil, nil
	CAS:UnbindAction("AerovoltVFlySink")
end
local function VFlyBuild(m, root, seat)
	VFlyClear(m)
	m._root, m._seat = root, seat
	-- steer by the seat's orientation, whatever way the vehicle's main part happens to face
	m._rel = root.CFrame.Rotation:Inverse() * seat.CFrame.Rotation
	local l = seat.CFrame.LookVector
	m._yaw = math.atan2(-l.X, -l.Z)
	m._vel = root.AssemblyLinearVelocity
	m._att = New("Attachment", { Name = "AerovoltVFly" }, root)
	m._lv = New("LinearVelocity", { Attachment0 = m._att, RelativeTo = Enum.ActuatorRelativeTo.World, VelocityConstraintMode = Enum.VelocityConstraintMode.Vector, MaxForce = math.huge, VectorVelocity = Vector3.zero }, root)
	m._ao = New("AlignOrientation", { Attachment0 = m._att, Mode = Enum.OrientationAlignmentMode.OneAttachment, RigidityEnabled = false, MaxTorque = math.huge, Responsiveness = 20, CFrame = CFrame.fromOrientation(0, m._yaw, 0) * m._rel:Inverse() }, root)
	-- Space is our "up" key here, so stop it from also making you jump out of the seat
	CAS:BindActionAtPriority("AerovoltVFlySink", function() return Enum.ContextActionResult.Sink end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space)
end

Module{ Name = "VehicleFly", Category = "Movement", Desc = "Fly the seat or vehicle you are sitting in with WASD, Space to go up and Shift or Ctrl to go down.",
	Settings = {
		Slider("Speed", 5, 500, 1, 90, "Horizontal flight speed."),
		Slider("Vertical", 5, 300, 1, 60, "Up and down speed."),
		Slider("Smoothing", 1, 30, 1, 8, "How quickly you speed up and slow down. Higher is snappier."),
		Toggle("Face Camera", true, "Turns the vehicle to face where the camera looks."),
	},
	OnEnable = function()
		local h = Hum()
		if not (h and h.SeatPart) then ui.Notify("Sit in a seat or vehicle to use VehicleFly", false) end
	end,
	OnDisable = function(m)
		local root = m._root
		VFlyClear(m)
		if root then root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end
	end,
	OnTick = function(m, dt)
		local h = Hum(); if not h then return end
		local seat = h.SeatPart
		local root = seat and seat.AssemblyRootPart
		if not root or root.Anchored then
			if m._root then VFlyClear(m) end
			return
		end
		if m._root ~= root or m._seat ~= seat or not m._lv or m._lv.Parent ~= root then
			VFlyBuild(m, root, seat)
		end
		local V = m.Values
		local cf, dir, vert = Camera.CFrame, Vector3.zero, 0
		if Down(Enum.KeyCode.W) then dir += cf.LookVector end
		if Down(Enum.KeyCode.S) then dir -= cf.LookVector end
		if Down(Enum.KeyCode.D) then dir += cf.RightVector end
		if Down(Enum.KeyCode.A) then dir -= cf.RightVector end
		if Down(Enum.KeyCode.Space) then vert += 1 end
		if Down(Enum.KeyCode.LeftShift) or Down(Enum.KeyCode.LeftControl) then vert -= 1 end

		local target = (dir.Magnitude > 0 and dir.Unit * V.Speed or Vector3.zero) + Vector3.new(0, vert * V.Vertical, 0)
		m._vel = m._vel:Lerp(target, 1 - math.exp(-V.Smoothing * dt))

		local flat = V["Face Camera"] and Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z) or Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude > 0.05 then m._yaw = math.atan2(-flat.X, -flat.Z) end
		m._ao.CFrame = CFrame.fromOrientation(0, m._yaw, 0) * m._rel:Inverse()
		m._lv.VectorVelocity = m._vel
	end }

Module{ Name = "Noclip", Category = "Movement", Desc = "Turns off collision on your character so you can walk through walls and objects. Floors still hold you up.",
	OnEnable = function(m)
		Hook(m, RunService.Stepped, function()
			local c = LP.Character
			if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end
		end)
	end }

Module{ Name = "InfiniteJump", Category = "Movement", Desc = "Lets you jump again while already in mid-air, as many times as you want.",
	Settings = {
		Mode("Mode", { "State", "Velocity" }, "State", "State re-triggers the humanoid jump. Velocity sets your upward speed directly using the Power setting."),
		Slider("Power", 30, 150, 1, 55, "Upward speed of each air jump. Only used by Velocity mode."),
	},
	OnEnable = function(m)
		Hook(m, UIS.JumpRequest, function()
			local h, r = Hum(), Root(); if not h or not r then return end
			if m.Values.Mode == "State" then h:ChangeState(Enum.HumanoidStateType.Jumping)
			else local v = r.AssemblyLinearVelocity; r.AssemblyLinearVelocity = Vector3.new(v.X, m.Values.Power, v.Z) end
		end)
	end }

Module{ Name = "HighJump", Category = "Movement", Desc = "Raises your jump power so every jump goes higher.",
	Settings = { Slider("Power", 50, 400, 1, 120, "Jump power. Roblox's default is 50.") },
	OnEnable = function(m) local h = Hum(); if h then m._u, m._p = h.UseJumpPower, h.JumpPower end end,
	OnDisable = function(m) local h = Hum(); if h then h.UseJumpPower = m._u ~= false; h.JumpPower = m._p or 50 end end,
	OnTick = function(m) local h = Hum(); if h then h.UseJumpPower = true; h.JumpPower = m.Values.Power end end }

Module{ Name = "Bhop", Category = "Movement", Desc = "Hops automatically while you move and keeps your speed up in the air.",
	Settings = { Slider("Boost", 0, 40, 1, 6, "Extra air speed on top of your walk speed.") },
	OnTick = function(m)
		local h, r = Hum(), Root(); if not h or not r then return end
		if h.Sit or h.PlatformStand then return end
		local md = h.MoveDirection
		if md.Magnitude == 0 then return end
		if h.FloorMaterial ~= Enum.Material.Air then
			-- the default controls reset Humanoid.Jump every frame, so ask for the jump state directly
			if h:GetState() ~= Enum.HumanoidStateType.Jumping then
				h:ChangeState(Enum.HumanoidStateType.Jumping)
			end
		else
			local v = r.AssemblyLinearVelocity
			local s = h.WalkSpeed + m.Values.Boost
			r.AssemblyLinearVelocity = Vector3.new(md.X * s, v.Y, md.Z * s)
		end
	end }

Module{ Name = "Glide", Category = "Movement", Desc = "Caps how fast you fall so you drift down slowly instead of dropping.",
	Settings = { Slider("Fall Speed", 1, 60, 1, 8, "Maximum downward speed in studs per second. Lower means a slower fall.") },
	OnTick = function(m)
		local h, r = Hum(), Root(); if not h or not r then return end
		local v = r.AssemblyLinearVelocity
		if h.FloorMaterial == Enum.Material.Air and v.Y < -m.Values["Fall Speed"] then
			r.AssemblyLinearVelocity = Vector3.new(v.X, -m.Values["Fall Speed"], v.Z)
		end
	end }

Module{ Name = "Spider", Category = "Movement", Desc = "Climb up walls by walking into them.",
	Settings = { Slider("Speed", 5, 80, 1, 28, "How fast you climb, in studs per second.") },
	OnTick = function(m)
		local h, r = Hum(), Root(); if not h or not r then return end
		if h.MoveDirection.Magnitude == 0 then return end
		if workspace:Raycast(r.Position, r.CFrame.LookVector * 2.5, RayParams()) then
			local v = r.AssemblyLinearVelocity
			r.AssemblyLinearVelocity = Vector3.new(v.X, m.Values.Speed, v.Z)
		end
	end }

Module{ Name = "Gravity", Category = "Movement", Desc = "Changes gravity for your own physics. Low values make you float, high values slam you down.",
	Settings = { Slider("Gravity", 0, 400, 1, 40, "Gravity in studs per second squared. Roblox's default is 196.2.") },
	OnEnable = function(m) m._orig = workspace.Gravity end,
	OnDisable = function(m) workspace.Gravity = m._orig or 196.2 end,
	OnTick = function(m) workspace.Gravity = m.Values.Gravity end }

Module{ Name = "Dash", Category = "Movement", Desc = "Launches you forward in the direction the camera is facing. Bind it to a key for an instant dash.",
	Settings = { Slider("Power", 30, 300, 1, 100, "Dash speed in studs per second.") },
	Action = function(m)
		local r = Root(); if not r then return end
		local l = Camera.CFrame.LookVector
		local flat = Vector3.new(l.X, 0, l.Z)
		if flat.Magnitude < 0.01 then return end
		r.AssemblyLinearVelocity = flat.Unit * m.Values.Power + Vector3.new(0, 20, 0)
	end }

----------------------------------------------------------------------
-- PLAYER
----------------------------------------------------------------------
Module{ Name = "Spinbot", Category = "Player", Desc = "Spins your character around quickly.",
	Settings = { Slider("Speed", 1, 60, 1, 20, "Degrees turned every frame at 60 FPS. Higher spins faster.") },
	OnEnable = function() local h = Hum(); if h then h.AutoRotate = false end end,
	OnDisable = function() local h = Hum(); if h then h.AutoRotate = true end end,
	OnTick = function(m, dt)
		local r = Root(); if r then r.CFrame = r.CFrame * CFrame.Angles(0, math.rad(m.Values.Speed) * dt * 60, 0) end
	end }

Module{ Name = "HipHeight", Category = "Player", Desc = "Hovers your character above the ground by raising its hip height.",
	Settings = { Slider("Height", 0, 40, 0.5, 6, "How high you float above the ground, in studs.") },
	OnEnable = function(m) local h = Hum(); m._orig = h and h.HipHeight or 2 end,
	OnDisable = function(m) local h = Hum(); if h then h.HipHeight = m._orig end end,
	OnTick = function(m) local h = Hum(); if h then h.HipHeight = m.Values.Height end end }

Module{ Name = "AntiSit", Category = "Player", Desc = "Stops you from sitting in seats and vehicles.",
	OnTick = function()
		local h = Hum(); if not h then return end
		h:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
		if h.Sit then h.Sit = false end
	end,
	OnDisable = function()
		local h = Hum(); if h then h:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end
	end }

Module{ Name = "NoFall", Category = "Player", Desc = "Cancels your fall speed right before you land so you take no landing impact.",
	Settings = { Slider("Threshold", 20, 120, 1, 45, "Minimum fall speed before NoFall kicks in. Lower values also catch shorter falls.") },
	OnTick = function(m)
		local r = Root(); if not r then return end
		local v = r.AssemblyLinearVelocity
		if v.Y < -m.Values.Threshold and workspace:Raycast(r.Position, Vector3.new(0, -14, 0), RayParams()) then
			r.AssemblyLinearVelocity = Vector3.new(v.X, -4, v.Z)
		end
	end }

Module{ Name = "AntiVoid", Category = "Player", Desc = "If you fall below the void height, teleports you back to the last solid ground you stood on.",
	Settings = { Slider("Height", -450, 100, 10, -100, "Y-height that counts as the void. Set it below the lowest ground of your map.") },
	OnEnable = function(m) m._safe = nil end,
	OnTick = function(m)
		local h, r = Hum(), Root(); if not h or not r then return end
		if h.FloorMaterial ~= Enum.Material.Air and r.Position.Y > m.Values.Height + 10 then m._safe = r.CFrame end
		if r.Position.Y < m.Values.Height and m._safe then
			r.AssemblyLinearVelocity = Vector3.zero
			r.CFrame = m._safe + Vector3.new(0, 4, 0)
		end
	end }

Module{ Name = "AntiFling", Category = "Player", Desc = "Cancels extreme speed and spinning so other players can't fling you across the map.",
	Settings = { Slider("Threshold", 50, 1000, 10, 250, "Speed (studs per second) above which your movement is zeroed. Raise it if it interferes with Fly or Dash.") },
	OnTick = function(m)
		local r = Root(); if not r then return end
		if r.AssemblyLinearVelocity.Magnitude > m.Values.Threshold or r.AssemblyAngularVelocity.Magnitude > 50 then
			r.AssemblyLinearVelocity = Vector3.zero
			r.AssemblyAngularVelocity = Vector3.zero
		end
	end }

Module{ Name = "RespawnHere", Category = "Player", Desc = "After you die, you respawn at the spot where you died instead of the spawn point.",
	OnEnable = function(m)
		Hook(m, RunService.Heartbeat, function()
			local r, h = Root(), Hum()
			if r and h and h.Health > 0 then m._last = r.CFrame end
		end)
		Hook(m, LP.CharacterAdded, function(c)
			local pos = m._last; if not pos then return end
			local r = c:WaitForChild("HumanoidRootPart", 5)
			if r then task.wait(0.15); r.CFrame = pos end
		end)
	end }

Module{ Name = "Reset", Category = "Player", Desc = "Kills your character so you respawn right away.",
	Action = function()
		local h, c = Hum(), LP.Character
		if h then h.Health = 0 end
		if c then c:BreakJoints() end
	end }

----------------------------------------------------------------------
-- RENDER (all local, only you see these)
----------------------------------------------------------------------
local function ColorFor(p, mode, off)
	if mode == "Team" then return p.TeamColor.Color
	elseif mode == "Rainbow" then return Color3.fromHSV((tick() * 0.3 + (off or 0)) % 1, 0.7, 1)
	elseif mode == "White" then return WHITE
	elseif mode == "Red" then return Color3.fromRGB(255, 60, 60) end
	return Accent()
end
local function Pass(m, p, root)
	if m.Values["Team Check"] and p.Team and p.Team == LP.Team then return false end
	local mr = Root()
	if mr and root and (root.Position - mr.Position).Magnitude > m.Values["Max Distance"] then return false end
	return true
end

local ESP = Module{ Name = "ESP", Category = "Render", Desc = "Draws a 2D box around every player, with an optional health bar.",
	Settings = {
		Mode("Color", ColorModes, "Accent", D_COLOR),
		Toggle("Health Bar", true, "Shows a health bar on the left side of each box."),
		Toggle("Team Check", false, D_TEAM),
		Slider("Max Distance", 100, 5000, 50, 2000, D_DIST),
	} }
local Names = Module{ Name = "NameTags", Category = "Render", Desc = "Shows each player's name above them, with optional distance and health.",
	Settings = {
		Mode("Color", ColorModes, "White", D_COLOR),
		Toggle("Show Distance", true, "Adds how far away the player is, in studs."),
		Toggle("Show Health", true, "Adds the player's current health."),
		Toggle("Team Check", false, D_TEAM),
		Slider("Max Distance", 100, 5000, 50, 2000, D_DIST),
	} }
local Tracers = Module{ Name = "Tracers", Category = "Render", Desc = "Draws a line from your screen to every player so you can always tell where they are.",
	Settings = {
		Mode("Origin", { "Bottom", "Center", "Mouse" }, "Bottom", "Where the lines start: bottom of the screen, center of the screen, or your mouse.", true),
		Slider("Thickness", 1, 5, 0.5, 1.5, "Line thickness in pixels."),
		Mode("Color", ColorModes, "Accent", D_COLOR),
		Toggle("Team Check", false, D_TEAM),
		Slider("Max Distance", 100, 5000, 50, 3000, D_DIST),
	} }

local ChamObjs = {}
local function ClearChams() for _, h in pairs(ChamObjs) do h:Destroy() end table.clear(ChamObjs) end
Module{ Name = "Chams", Category = "Render", Desc = "Highlights players with a glowing fill and outline that shows through walls.",
	Settings = {
		Mode("Color", ColorModes, "Accent", D_COLOR),
		Slider("Fill", 0, 1, 0.05, 0.6, "How strong the colored fill is. 0 shows only the outline."),
		Toggle("Outline", true, "Draws a solid outline around each player."),
		Toggle("Visible Only", false, "Only highlights parts of players that are not hidden behind walls."),
		Toggle("Team Check", false, D_TEAM),
		Slider("Max Distance", 100, 5000, 50, 3000, D_DIST),
	},
	OnDisable = ClearChams,
	OnRender = function(m)
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP then
				local ch = p.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local h = ChamObjs[p]
				if ch and root and Pass(m, p, root) then
					if not h or h.Parent ~= ch then
						if h then h:Destroy() end
						h = New("Highlight", {}, ch); ChamObjs[p] = h
					end
					local c = ColorFor(p, m.Values.Color)
					h.FillColor, h.OutlineColor = c, c
					h.FillTransparency = 1 - m.Values.Fill
					h.OutlineTransparency = m.Values.Outline and 0 or 1
					h.DepthMode = m.Values["Visible Only"] and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
				elseif h then h:Destroy(); ChamObjs[p] = nil end
			end
		end
	end }

local LightOrig = {}
Module{ Name = "Fullbright", Category = "Render", Desc = "Makes everything fully lit and removes shadows so dark areas are easy to see.",
	OnEnable = function()
		LightOrig = { Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows, Lighting.Ambient, Lighting.OutdoorAmbient }
	end,
	OnDisable = function()
		if #LightOrig > 0 then
			Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows, Lighting.Ambient, Lighting.OutdoorAmbient = table.unpack(LightOrig)
		end
	end,
	OnTick = function()
		Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows = 2, 14, false
		Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190), Color3.fromRGB(190, 190, 190)
	end }

Module{ Name = "NoFog", Category = "Render", Desc = "Removes fog and atmospheric haze for a clear view into the distance.",
	OnEnable = function(m)
		m._fog = { Lighting.FogStart, Lighting.FogEnd }
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		m._atm = a and { a.Density, a.Haze }
	end,
	OnDisable = function(m)
		Lighting.FogStart, Lighting.FogEnd = m._fog[1], m._fog[2]
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		if a and m._atm then a.Density, a.Haze = m._atm[1], m._atm[2] end
	end,
	OnTick = function()
		Lighting.FogStart, Lighting.FogEnd = 1e8, 1e9
		local a = Lighting:FindFirstChildOfClass("Atmosphere"); if a then a.Density = 0; a.Haze = 0 end
	end }

Module{ Name = "TimeChanger", Category = "Render", Desc = "Locks the time of day on your screen, no matter what the server does.",
	Settings = { Slider("Time", 0, 24, 0.25, 12, "Hour of the day from 0 to 24. 12 is noon, 0 and 24 are midnight.") },
	OnEnable = function(m) m._orig = Lighting.ClockTime end,
	OnDisable = function(m) Lighting.ClockTime = m._orig end,
	OnTick = function(m) Lighting.ClockTime = m.Values.Time end }

local Zoom
local FOVm = Module{ Name = "FOV", Category = "Render", Desc = "Changes your camera's field of view. Higher values show more of the world.",
	Settings = { Slider("FOV", 30, 120, 1, 90, "Field of view in degrees. Roblox's default is 70.") },
	OnDisable = function() Camera.FieldOfView = 70 end,
	OnRender = function(m)
		if Zoom and Zoom._active then return end
		Camera.FieldOfView = m.Values.FOV
	end }

Zoom = Module{ Name = "Zoom", Category = "Render", Desc = "Hold a key to zoom the camera in smoothly, release it to zoom back out.",
	Settings = {
		Mode("Key", { "C", "Z", "X", "V" }, "C", "The key you hold to zoom."),
		Slider("Zoom FOV", 10, 60, 1, 20, "Field of view while zoomed. Lower numbers zoom in more."),
	},
	OnDisable = function(m) m._active = false; Camera.FieldOfView = FOVm.Enabled and FOVm.Values.FOV or 70 end,
	OnRender = function(m, dt)
		local zooming = Down(Enum.KeyCode[m.Values.Key])
		local base = FOVm.Enabled and FOVm.Values.FOV or 70
		if zooming then m._active = true end
		if not m._active then return end
		local target = zooming and m.Values["Zoom FOV"] or base
		Camera.FieldOfView += (target - Camera.FieldOfView) * math.min(1, dt * 12)
		if not zooming and math.abs(Camera.FieldOfView - base) < 0.2 then Camera.FieldOfView = base; m._active = false end
	end }

local CrossFrames
Module{ Name = "Crosshair", Category = "Render", Desc = "Draws a custom crosshair in the center of your screen.",
	Settings = {
		Slider("Length", 2, 30, 1, 8, "Length of each crosshair line in pixels."),
		Slider("Gap", 0, 20, 1, 4, "Empty space in the middle of the crosshair in pixels."),
		Slider("Thickness", 1, 6, 1, 2, "Thickness of the lines in pixels."),
		Toggle("Center Dot", false, "Adds a small dot in the exact center."),
	},
	OnEnable = function()
		local holder = New("Frame", { Name = "Crosshair", BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new() }, ui.Gui)
		CrossFrames = { Holder = holder }
		for _, n in ipairs({ "Up", "Down", "Left", "Right", "Dot" }) do
			CrossFrames[n] = New("Frame", { BorderSizePixel = 0 }, holder)
		end
	end,
	OnDisable = function() if CrossFrames then CrossFrames.Holder:Destroy(); CrossFrames = nil end end,
	OnRender = function(m)
		if not CrossFrames then return end
		local L, g, t = m.Values.Length, m.Values.Gap, m.Values.Thickness
		local F, c = CrossFrames, Accent()
		F.Up.AnchorPoint, F.Up.Position, F.Up.Size = Vector2.new(0.5, 1), UDim2.fromOffset(0, -g), UDim2.fromOffset(t, L)
		F.Down.AnchorPoint, F.Down.Position, F.Down.Size = Vector2.new(0.5, 0), UDim2.fromOffset(0, g), UDim2.fromOffset(t, L)
		F.Left.AnchorPoint, F.Left.Position, F.Left.Size = Vector2.new(1, 0.5), UDim2.fromOffset(-g, 0), UDim2.fromOffset(L, t)
		F.Right.AnchorPoint, F.Right.Position, F.Right.Size = Vector2.new(0, 0.5), UDim2.fromOffset(g, 0), UDim2.fromOffset(L, t)
		F.Dot.AnchorPoint, F.Dot.Size, F.Dot.Visible = Vector2.new(0.5, 0.5), UDim2.fromOffset(t, t), m.Values["Center Dot"]
		for _, n in ipairs({ "Up", "Down", "Left", "Right", "Dot" }) do F[n].BackgroundColor3 = c end
	end }

local fpsAvg = 60
local function GetPing()
	local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
	return ok and math.floor(v) or 0
end
local HUDm
HUDm = Module{ Name = "HUD", Category = "Render", Desc = "Shows the Aerovolt title above the array list and FPS, ping and coordinates in the bottom left.",
	Settings = {
		Toggle("Watermark", true, "Shows the Aerovolt title above the array list."),
		Toggle("FPS", true, "Shows your frames per second in the bottom left."),
		Toggle("Ping", true, "Shows your ping in the bottom left."),
		Toggle("Coords", true, "Shows your X, Y and Z position in the bottom left."),
		Slider("Text Size", 11, 24, 1, 14, "Size of the bottom left text."),
		Toggle("Theme Accent", true, "Uses your theme color for the title and info bar. Picking a Watermark Color turns this off."),
		ColorSet("Watermark Color", Color3.fromRGB(160, 90, 255), "Color of the title and info bar. Only used when Theme Accent is off."),
		ColorSet("Text Color", Color3.new(1, 1, 1), "Color of the FPS, ping and coordinates text."),
		ColorSet("Background Color", Color3.new(0, 0, 0), "Color of the boxes behind the HUD text."),
		Slider("Background Opacity", 0, 1, 0.05, 0.55, "How solid the boxes behind the text are."),
	},
	OnChanged = function(m, name)
		if name == "Watermark Color" and m.Values["Theme Accent"] then
			m.Values["Theme Accent"] = false
			Repaint()
		end
	end,
	OnEnable = function(m)
		-- title: sits at the top of the same right-aligned column as the array list
		local wm = New("Frame", { Name = "Watermark", Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0, LayoutOrder = 0 }, ui.TopRight)
		local wmLabel = New("TextLabel", { Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, Font = FONT_B, TextSize = 20, RichText = true, Text = "" }, wm)
		New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 5) }, wmLabel)
		local wmLine = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0 }, wm)
		-- clicking the title opens / closes the menu
		local wmBtn = New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 5 }, wm)
		wmBtn.MouseButton1Click:Connect(function() if ui.SetMenu then ui.SetMenu(not ui.MenuOpen) end end)
		ui.AddHover(wmBtn, function() return ui.HoverText(CLIENT, "Click to open or close the menu.") end, wmBtn)

		-- info box: bottom left
		local info = New("Frame", { Name = "Info", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, ui.Gui)
		local bar = New("Frame", { Size = UDim2.new(0, 2, 1, 0), BorderSizePixel = 0 }, info)
		local label = New("TextLabel", { Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, Font = FONT, TextSize = 14, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, info)
		New("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, label)
		m._wm, m._wmLabel, m._wmLine, m._info, m._bar, m._label = wm, wmLabel, wmLine, info, bar, label
	end,
	OnDisable = function(m)
		if m._wm then m._wm:Destroy() end
		if m._info then m._info:Destroy() end
		m._wm, m._wmLabel, m._wmLine, m._info, m._bar, m._label = nil, nil, nil, nil, nil, nil
	end,
	OnRender = function(m, dt)
		if not m._info then return end
		local V = m.Values
		fpsAvg += (1 / math.max(dt, 1e-4) - fpsAvg) * 0.05
		local main = V["Theme Accent"] and Accent() or V["Watermark Color"]
		local bg, tr = V["Background Color"], 1 - V["Background Opacity"]

		m._wm.Visible = V.Watermark
		m._wm.BackgroundColor3, m._wm.BackgroundTransparency = bg, tr
		m._wmLine.BackgroundColor3 = main
		m._wmLabel.Text = ("<font color=\"%s\">%s</font> <font color=\"rgb(150,150,165)\" size=\"14\">%s</font>"):format(Rgb(main), CLIENT, VERSION)

		local lines = {}
		if V.FPS then table.insert(lines, "FPS  " .. math.floor(fpsAvg)) end
		if V.Ping then table.insert(lines, "Ping " .. GetPing() .. "ms") end
		if V.Coords then
			local r = Root()
			if r then
				local p = r.Position
				table.insert(lines, ("XYZ  %d, %d, %d"):format(math.floor(p.X), math.floor(p.Y), math.floor(p.Z)))
			end
		end
		m._info.Visible = #lines > 0
		m._info.BackgroundColor3, m._info.BackgroundTransparency = bg, tr
		m._bar.BackgroundColor3 = main
		m._label.TextSize = V["Text Size"]
		m._label.TextColor3 = V["Text Color"]
		m._label.Text = table.concat(lines, "\n")
	end }

Module{ Name = "CamDistance", Category = "Render", Desc = "Removes the limit on how far you can zoom the camera in and out.",
	Settings = {
		Slider("Max Zoom", 20, 2000, 10, 500, "Farthest the camera can zoom out, in studs."),
		Slider("Min Zoom", 0, 20, 0.5, 0.5, "Closest the camera can zoom in. 0 allows first person."),
	},
	OnEnable = function(m) m._o = { LP.CameraMaxZoomDistance, LP.CameraMinZoomDistance } end,
	OnDisable = function(m) LP.CameraMaxZoomDistance, LP.CameraMinZoomDistance = m._o[1], m._o[2] end,
	OnTick = function(m) LP.CameraMaxZoomDistance, LP.CameraMinZoomDistance = m.Values["Max Zoom"], m.Values["Min Zoom"] end }

Module{ Name = "Freecam", Category = "Render", Desc = "Detaches the camera so you can fly around and look without moving your character. WASD to move, Q and E for down and up, hold right mouse to look, Shift to go faster.",
	Settings = {
		Slider("Speed", 5, 300, 1, 50, "How fast the camera flies. Hold Shift for 3x."),
		Toggle("Freeze Character", true, "Anchors your character in place while the camera is detached. Applies when you enable Freecam."),
	},
	OnEnable = function(m)
		local x, y = Camera.CFrame:ToOrientation()
		m._pitch, m._yaw, m._pos = x, y, Camera.CFrame.Position
		Camera.CameraType = Enum.CameraType.Scriptable
		local r = Root()
		m._anch = nil
		if r and m.Values["Freeze Character"] then m._anch = r.Anchored; r.Anchored = true end
		Hook(m, UIS.InputChanged, function(i)
			if i.UserInputType == Enum.UserInputType.MouseMovement and UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
				m._yaw -= i.Delta.X * math.rad(0.25)
				m._pitch = math.clamp(m._pitch - i.Delta.Y * math.rad(0.25), -1.5, 1.5)
			end
		end)
	end,
	OnDisable = function(m)
		Camera.CameraType = Enum.CameraType.Custom
		local r, h = Root(), Hum()
		if r and m._anch ~= nil then r.Anchored = m._anch end
		if h then Camera.CameraSubject = h end
	end,
	OnRender = function(m, dt)
		local rot = CFrame.fromOrientation(m._pitch, m._yaw, 0)
		local dir = Vector3.zero
		if Down(Enum.KeyCode.W) then dir += rot.LookVector end
		if Down(Enum.KeyCode.S) then dir -= rot.LookVector end
		if Down(Enum.KeyCode.D) then dir += rot.RightVector end
		if Down(Enum.KeyCode.A) then dir -= rot.RightVector end
		if Down(Enum.KeyCode.E) then dir += Vector3.yAxis end
		if Down(Enum.KeyCode.Q) then dir -= Vector3.yAxis end
		local sp = m.Values.Speed * (Down(Enum.KeyCode.LeftShift) and 3 or 1)
		if dir.Magnitude > 0 then m._pos += dir.Unit * sp * dt end
		Camera.CameraType = Enum.CameraType.Scriptable
		Camera.CFrame = CFrame.new(m._pos) * rot
	end }

----------------------------------------------------------------------
-- COMBAT (everything here only changes your own client)
----------------------------------------------------------------------
local FOVc
local AimState = { active = 0, locked = 0 }

-- where you are aiming on screen: the screen center while the mouse is locked, otherwise your cursor
local function CenterMode(follow)
	return follow == "Center" or (follow ~= "Mouse" and UIS.MouseBehavior == Enum.MouseBehavior.LockCenter)
end

-- where you are aiming on screen, in raw screen space. While the mouse is locked this is the engine's own
-- crosshair position, otherwise it is your cursor. "Center" forces the middle of the viewport.
local function AimPoint(follow)
	if follow == "Center" then return Camera.ViewportSize / 2 end
	return UIS:GetMouseLocation()
end

-- center of the FOV circle: same as AimPoint, plus the optional Offset Y nudge (drawing and targeting only)
local function FovCenter()
	local f = FOVc.Values.Follow
	local c = AimPoint(f)
	if CenterMode(f) then c += Vector2.new(0, FOVc.Values["Offset Y"]) end
	return c
end

local function Held(mode)
	if mode == "Always" then return true end
	local b = mode == "Hold Left Mouse" and Enum.UserInputType.MouseButton1 or Enum.UserInputType.MouseButton2
	return UIS:IsMouseButtonPressed(b)
end

local function AimSettings(list)
	table.insert(list, Mode("Aim Part", { "Head", "Torso" }, "Head", "Which part of the player to aim at."))
	table.insert(list, Mode("Priority", { "Crosshair", "Distance" }, "Crosshair", "Crosshair picks the player closest to where you aim. Distance picks the nearest player."))
	table.insert(list, Toggle("Use FOV", true, "Only targets players inside the FOV Circle. Turn it off to target anyone on screen."))
	table.insert(list, Toggle("Visible Check", true, "Ignores players hidden behind walls."))
	table.insert(list, Toggle("Team Check", true, D_TEAM))
	table.insert(list, Slider("Max Distance", 50, 2000, 50, 500, D_DIST))
	table.insert(list, Slider("Prediction", 0, 0.5, 0.01, 0, "Aims ahead of moving players by this many seconds."))
	return list
end

-- best player for an aim module right now, or nil. prefer = last target (kept a little longer so it doesn't flicker)
local function FindTarget(m, prefer)
	local V = m.Values
	local origin = Camera.CFrame.Position
	local center = FovCenter()
	local radius = FOVc.Values.Radius
	local best, bestScore
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP and not (V["Team Check"] and p.Team and p.Team == LP.Team) then
			local ch = p.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local part = ch and (V["Aim Part"] == "Head" and ch:FindFirstChild("Head") or ch:FindFirstChild("HumanoidRootPart"))
			if hum and part and hum.Health > 0 then
				local dist = (part.Position - origin).Magnitude
				if dist <= V["Max Distance"] then
					local v = Camera:WorldToViewportPoint(part.Position)
					if v.Z > 0 then
						local sd = (Vector2.new(v.X, v.Y) - center).Magnitude
						if not V["Use FOV"] or sd <= radius then
							local clear = true
							if V["Visible Check"] then
								local rp = RayParams()
								rp.FilterDescendantsInstances = { LP.Character, ch }
								clear = workspace:Raycast(origin, part.Position - origin, rp) == nil
							end
							if clear then
								local score = V.Priority == "Distance" and dist or sd
								if p == prefer then score *= 0.6 end
								if not bestScore or score < bestScore then
									best, bestScore = { player = p, part = part }, score
								end
							end
						end
					end
				end
			end
		end
	end
	return best
end

local function TargetPos(t, pred)
	return t.part.Position + t.part.AssemblyLinearVelocity * pred
end

-- turns the camera toward pos by a fraction (alpha) of the remaining angle, capped at maxStep radians
local function AimCamera(pos, alpha, maxStep)
	local camCF = Camera.CFrame
	local from = camCF.Position
	local want = pos - from
	if want.Magnitude < 0.01 then return end
	want = want.Unit
	local c = AimPoint(FOVc.Values.Follow)
	local cur = Camera:ViewportPointToRay(c.X, c.Y).Direction
	local ang = math.acos(math.clamp(cur:Dot(want), -1, 1))
	if ang < 0.0005 then return end
	local axis = cur:Cross(want)
	if axis.Magnitude < 1e-6 then return end
	local step = ang * alpha
	if maxStep then step = math.min(step, maxStep) end
	Camera.CFrame = CFrame.new(from) * CFrame.fromAxisAngle(axis.Unit, step) * camCF.Rotation
end

-- hitbox visualizer -------------------------------------------------
local VizObjs = {}
local function VizClear() for _, a in pairs(VizObjs) do a:Destroy() end table.clear(VizObjs) end
Module{ Name = "Hitbox Visualizer", Category = "Combat", Desc = "Draws a box around each player's real hitbox so you can see how big it is.",
	Settings = {
		Mode("Parts", { "Root", "Head", "Both", "Full Body" }, "Root", "Which parts of each player get a box."),
		Mode("Color", ColorModes, "Red", D_COLOR),
		Slider("Transparency", 0, 1, 0.05, 0.6, "How see-through the boxes are."),
		Toggle("Through Walls", true, "Shows the boxes even when the player is behind something."),
		Toggle("Team Check", false, D_TEAM),
		Slider("Max Distance", 100, 5000, 50, 1000, D_DIST),
	},
	OnDisable = VizClear,
	OnRender = function(m)
		local V, wanted = m.Values, {}
		for _, p in ipairs(Players:GetPlayers()) do
			local ch = p ~= LP and p.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if root and Pass(m, p, root) then
				local list, mode = {}, V.Parts
				if mode == "Root" or mode == "Both" then table.insert(list, root) end
				if mode == "Head" or mode == "Both" then
					local h = ch:FindFirstChild("Head")
					if h then table.insert(list, h) end
				end
				if mode == "Full Body" then
					for _, o in ipairs(ch:GetChildren()) do if o:IsA("BasePart") then table.insert(list, o) end end
				end
				local col = ColorFor(p, V.Color)
				for _, part in ipairs(list) do
					wanted[part] = true
					local a = VizObjs[part]
					if not a or a.Parent ~= part then
						if a then a:Destroy() end
						a = New("BoxHandleAdornment", { Name = "AerovoltHitbox", Adornee = part }, part)
						VizObjs[part] = a
					end
					a.Size, a.Color3, a.Transparency = part.Size, col, V.Transparency
					a.AlwaysOnTop, a.ZIndex = V["Through Walls"], 1
				end
			end
		end
		for part, a in pairs(VizObjs) do
			if not wanted[part] then a:Destroy(); VizObjs[part] = nil end
		end
	end }

-- hitbox expander ---------------------------------------------------
local HB = {}
local function HBRestorePart(part)
	local o = HB[part]
	if o and part.Parent then
		part.Size, part.Transparency, part.CanCollide, part.Massless = o.Size, o.Transparency, o.CanCollide, o.Massless
	end
	HB[part] = nil
end
local function HBRestoreAll() for part in pairs(HB) do HBRestorePart(part) end end
Module{ Name = "Hitbox Expander", Category = "Combat", Desc = "Makes other players' hitboxes bigger on your client so they are easier to hit.",
	Settings = {
		Mode("Part", { "Root", "Head" }, "Root", "Which part of each player gets enlarged."),
		Slider("Size", 2, 40, 0.5, 8, "Width, height and depth of the enlarged hitbox in studs."),
		Slider("Transparency", 0, 1, 0.05, 0.7, "How see-through the enlarged part is."),
		Toggle("Team Check", true, D_TEAM),
	},
	OnDisable = function(m) m._part = nil; HBRestoreAll() end,
	OnTick = function(m)
		local V, wanted = m.Values, {}
		if m._part ~= V.Part then HBRestoreAll(); m._part = V.Part end
		for _, p in ipairs(Players:GetPlayers()) do
			local ch = p ~= LP and p.Character
			if ch and not (V["Team Check"] and p.Team and p.Team == LP.Team) then
				local hum = ch:FindFirstChildOfClass("Humanoid")
				local part = ch:FindFirstChild(V.Part == "Head" and "Head" or "HumanoidRootPart")
				if part and hum and hum.Health > 0 then
					wanted[part] = true
					if not HB[part] then
						HB[part] = { Size = part.Size, Transparency = part.Transparency, CanCollide = part.CanCollide, Massless = part.Massless }
					end
					part.Size = Vector3.new(V.Size, V.Size, V.Size)
					part.Transparency = V.Transparency
					part.CanCollide = false
					part.Massless = true
				end
			end
		end
		for part in pairs(HB) do
			if not wanted[part] then HBRestorePart(part) end
		end
	end }

-- fov circle --------------------------------------------------------
FOVc = Module{ Name = "FOV Circle", Category = "Combat", Desc = "Draws a circle on screen. Aim Assist and Aimbot only target players inside it.",
	Settings = {
		Slider("Radius", 20, 600, 5, 140, "Size of the circle in pixels. The aim modules use this as their targeting area."),
		Mode("Follow", { "Auto", "Center", "Mouse" }, "Auto", "Auto sits on your cursor, or the screen center while your mouse is locked."),
		Slider("Offset Y", -150, 150, 1, 0, "Moves the circle up or down in pixels if it does not line up with your crosshair. Only used when the circle sits on the screen center."),
		Slider("Thickness", 1, 6, 0.5, 1.5, "Line thickness in pixels."),
		Mode("Color", { "Accent", "White", "Red" }, "Accent", "Color of the circle."),
		Toggle("Filled", false, "Tints the inside of the circle."),
		Toggle("Highlight On Target", true, "Turns the circle red while an aim module has a target."),
		Toggle("Only When Aiming", false, "Hides the circle until an aim module is actually active."),
	},
	OnEnable = function(m)
		m._circle = New("Frame", { Name = "FOVCircle", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = WHITE, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, ui.Gui)
		New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, m._circle)
		m._stroke = New("UIStroke", { Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, m._circle)
	end,
	OnDisable = function(m)
		if m._circle then m._circle:Destroy() end
		m._circle, m._stroke = nil, nil
	end,
	OnRender = function(m)
		local c, V = m._circle, m.Values
		if not c then return end
		c.Visible = not V["Only When Aiming"] or tick() - AimState.active < 0.15
		local center, r = FovCenter(), V.Radius
		c.Position = UDim2.fromOffset(center.X, center.Y)
		c.Size = UDim2.fromOffset(r * 2, r * 2)
		c.BackgroundTransparency = V.Filled and 0.88 or 1
		local col
		if V["Highlight On Target"] and tick() - AimState.locked < 0.15 then col = Color3.fromRGB(255, 70, 80)
		elseif V.Color == "White" then col = WHITE
		elseif V.Color == "Red" then col = Color3.fromRGB(255, 60, 60)
		else col = Accent() end
		c.BackgroundColor3, m._stroke.Color, m._stroke.Thickness = col, col, V.Thickness
	end }

-- aim assist --------------------------------------------------------
Module{ Name = "Aim Assist", Category = "Combat", Desc = "Gently pulls your camera toward players near your aim. You can still overpower it with your mouse.",
	Settings = AimSettings({
		Mode("Activate", { "Always", "Hold Right Mouse", "Hold Left Mouse" }, "Always", "When the pull is active."),
		Slider("Pull Speed", 5, 240, 5, 45, "Most degrees per second the camera is pulled. Lower is subtler."),
	}),
	OnDisable = function(m) m._cur = nil end,
	OnRender = function(m, dt)
		if ui.MenuOpen or Typing() or not Held(m.Values.Activate) then m._cur = nil return end
		AimState.active = tick()
		local t = FindTarget(m, m._cur)
		m._cur = t and t.player
		if not t then return end
		AimState.locked = tick()
		AimCamera(TargetPos(t, m.Values.Prediction), 1, math.rad(m.Values["Pull Speed"]) * dt)
	end }

-- aimbot ------------------------------------------------------------
Module{ Name = "Aimbot", Category = "Combat", Desc = "Locks your camera onto the nearest player.",
	Settings = AimSettings({
		Mode("Activate", { "Always", "Hold Right Mouse", "Hold Left Mouse" }, "Hold Right Mouse", "When the lock is active."),
		Slider("Smoothness", 0, 20, 1, 3, "How slowly the camera turns onto the target. 0 snaps instantly."),
	}),
	OnDisable = function(m) m._cur = nil end,
	OnRender = function(m, dt)
		if ui.MenuOpen or Typing() or not Held(m.Values.Activate) then m._cur = nil return end
		AimState.active = tick()
		local t = FindTarget(m, m._cur)
		m._cur = t and t.player
		if not t then return end
		AimState.locked = tick()
		local sm = m.Values.Smoothness
		AimCamera(TargetPos(t, m.Values.Prediction), sm == 0 and 1 or 1 - math.exp(-(30 / sm) * dt))
	end }

-- triggerbot --------------------------------------------------------
Module{ Name = "Triggerbot", Category = "Combat", Desc = "Uses your equipped tool automatically while your aim is over a player.",
	Settings = {
		Slider("Delay", 0, 500, 10, 60, "Milliseconds your aim must stay on a player before the tool fires."),
		Slider("Cooldown", 50, 1000, 10, 150, "Minimum milliseconds between uses."),
		Slider("Max Distance", 20, 2000, 10, 300, D_DIST),
		Toggle("Team Check", true, D_TEAM),
	},
	OnDisable = function(m) m._since = nil end,
	OnTick = function(m)
		local V = m.Values
		local ch = LP.Character
		local tool = ch and ch:FindFirstChildOfClass("Tool")
		if ui.MenuOpen or Typing() or not tool then m._since = nil return end
		local c = AimPoint("Auto")
		local ray = Camera:ViewportPointToRay(c.X, c.Y)
		local hit = workspace:Raycast(ray.Origin, ray.Direction * V["Max Distance"], RayParams())
		local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
		local p = model and Players:GetPlayerFromCharacter(model)
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if p and p ~= LP and hum and hum.Health > 0 and not (V["Team Check"] and p.Team and p.Team == LP.Team) then
			m._since = m._since or tick()
			if (tick() - m._since) * 1000 >= V.Delay and (tick() - (m._last or 0)) * 1000 >= V.Cooldown then
				m._last = tick()
				tool:Activate()
			end
		else
			m._since = nil
		end
	end }

----------------------------------------------------------------------
-- UTILITY
----------------------------------------------------------------------
local Waypoint
Module{ Name = "ClickTP", Category = "Utility", Desc = "Teleports you to wherever you click in the world.",
	Settings = { Mode("Mode", { "Ctrl+Click", "Click" }, "Ctrl+Click", "Ctrl+Click needs Left Ctrl held while clicking. Click teleports on every single click.") },
	OnEnable = function(m)
		Hook(m, UIS.InputBegan, function(i, gp)
			if gp or ui.MenuOpen or i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			if m.Values.Mode == "Ctrl+Click" and not UIS:IsKeyDown(Enum.KeyCode.LeftControl) then return end
			local r = Root(); if r then r.CFrame = CFrame.new(Mouse.Hit.Position + Vector3.new(0, 3, 0)) end
		end)
	end }

Module{ Name = "TP To Player", Category = "Utility", Desc = "Teleports you right next to the selected player.",
	Settings = { Mode("Target", PlayerNames, nil, D_TARGET) },
	Action = function(m)
		local p = Target(m)
		local tr, r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart"), Root()
		if tr and r then r.CFrame = tr.CFrame * CFrame.new(0, 0, 3); ui.Notify("Teleported to " .. p.Name, true)
		else ui.Notify("No valid target", false) end
	end }

Module{ Name = "Follow", Category = "Utility", Desc = "Makes your character walk toward the selected player and keep following them.",
	Settings = {
		Mode("Target", PlayerNames, nil, D_TARGET),
		Slider("Distance", 3, 40, 1, 6, "How close to get before you stop walking, in studs."),
	},
	OnDisable = function() local h, r = Hum(), Root(); if h and r then h:MoveTo(r.Position) end end,
	OnTick = function(m)
		local p = Target(m)
		local tr = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local h, r = Hum(), Root()
		if tr and h and r and (tr.Position - r.Position).Magnitude > m.Values.Distance then h:MoveTo(tr.Position) end
	end }

Module{ Name = "Spectate", Category = "Utility", Desc = "Watch the game through another player's camera. Disable it to return to yourself.",
	Settings = { Mode("Target", PlayerNames, nil, D_TARGET) },
	OnDisable = function() local h = Hum(); if h then Camera.CameraSubject = h end end,
	OnRender = function(m)
		local p = Target(m)
		local h = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if h then Camera.CameraSubject = h end
	end }

Module{ Name = "Set Waypoint", Category = "Utility", Desc = "Saves your current position so you can teleport back to it later.",
	Action = function() local r = Root(); if r then Waypoint = r.CFrame; ui.Notify("Waypoint saved", true) end end }
Module{ Name = "Go To Waypoint", Category = "Utility", Desc = "Teleports you to the position you saved with Set Waypoint.",
	Action = function()
		local r = Root()
		if r and Waypoint then r.CFrame = Waypoint; ui.Notify("Teleported to waypoint", true) else ui.Notify("No waypoint set", false) end
	end }
Module{ Name = "TP To Spawn", Category = "Utility", Desc = "Teleports you to the first spawn point in the map.",
	Action = function()
		local s, r = workspace:FindFirstChildWhichIsA("SpawnLocation", true), Root()
		if s and r then r.CFrame = s.CFrame + Vector3.new(0, 5, 0) else ui.Notify("No spawn found", false) end
	end }

Module{ Name = "AntiAFK", Category = "Utility", Desc = "Stops Roblox from kicking you for being idle for too long.",
	OnEnable = function(m)
		Hook(m, LP.Idled, function()
			pcall(function()
				local vu = game:GetService("VirtualUser")
				vu:CaptureController(); vu:ClickButton2(Vector2.new())
			end)
		end)
	end }

Module{ Name = "PlayerAlerts", Category = "Utility", Desc = "Shows a notification whenever a player joins or leaves the server.",
	OnEnable = function(m)
		Hook(m, Players.PlayerAdded, function(p) ui.Notify(p.Name .. " joined", true) end)
		Hook(m, Players.PlayerRemoving, function(p) ui.Notify(p.Name .. " left", false) end)
	end }

Module{ Name = "Rejoin", Category = "Utility", Desc = "Rejoins the server you are in right now. Only works in a published game, not in Studio.",
	Action = function()
		local ok = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end)
		if not ok then ui.Notify("Rejoin only works in a published game", false) end
	end }

----------------------------------------------------------------------
-- SETTINGS
----------------------------------------------------------------------
local ArrayList = Module{ Name = "ArrayList", Category = "Settings", Desc = "Lists your enabled modules on the right side of the screen, starting at the top.",
	Settings = {
		Mode("Sort", { "Longest", "Shortest", "Alphabetical" }, "Longest", "Order of the list: longest names first, shortest first, or alphabetical."),
		Toggle("Show Suffix", true, "Shows a module's current mode next to its name, for example Speed WalkSpeed."),
		Toggle("Background", true, "Draws a dark box behind each entry."),
		Toggle("Side Bar", true, "Draws a colored bar on the right edge of each entry."),
		Slider("Opacity", 0, 1, 0.05, 0.45, "How solid the background boxes are."),
		Slider("Text Size", 12, 26, 1, 16, "Size of the list text in pixels."),
	} }
local Notifs = Module{ Name = "Notifications", Category = "Settings", Desc = "Shows small pop-ups in the bottom right for warnings, teleports and other events.",
	Settings = {
		Slider("Duration", 1, 8, 0.5, 3, "How many seconds each pop-up stays on screen."),
		Toggle("Module Toggles", false, "Also shows a pop-up whenever a module is turned on or off."),
	} }
Module{ Name = "Theme", Category = "Settings", Desc = "Sets the accent color of the whole client. Rainbow cycles through every color.", Passive = true,
	Settings = {
		Mode("Color", ThemeOrder, "Purple", "The accent color used across the menu, array list and visuals."),
		Slider("Rainbow Speed", 0.05, 1, 0.05, 0.25, "How fast the Rainbow theme cycles through colors."),
	},
	OnChanged = function(m)
		ThemeName, RainbowSpeed = m.Values.Color, m.Values["Rainbow Speed"]
		Repaint()
	end }
local GuiSettings = Module{ Name = "GUI", Category = "Settings", Desc = "Controls how this menu opens and what it looks like.", Passive = true,
	Settings = {
		Mode("Menu Key", { "RightShift", "Insert", "RightControl", "RightAlt", "Delete", "Home" }, "RightShift", "The key that opens and closes this menu."),
		Toggle("Background Blur", true, "Blurs the game behind the menu while it is open."),
		Toggle("Background Dim", true, "Darkens the game behind the menu while it is open."),
		Toggle("Descriptions", true, "Shows a short description of whatever you hover over. Turn off to hide them completely."),
		Mode("Description Style", { "Cursor", "Bottom Bar" }, "Cursor", "Cursor shows a small tip next to your mouse. Bottom Bar pins it to the bottom of the screen."),
		Toggle("High Slider Values", false, "Raises the maximum of speed, distance and size sliders far beyond their normal limits."),
	},
	OnChanged = function(m, name)
		if name == "High Slider Values" and ui.OnHighChanged then ui.OnHighChanged() end
		ui.ApplyInterface()
	end }
Module{ Name = "Save Settings", Category = "Settings", Desc = "Saves every module, setting, keybind and panel position. They load automatically next time.",
	Action = function() ui.SaveConfig() end }
Module{ Name = "Reset Panels", Category = "Settings", Desc = "Puts every panel back in its default position.",
	Action = function() ui.ResetPanels() end }
Module{ Name = "Panic", Category = "Settings", Desc = "Instantly turns off every module. Use it if something goes wrong.",
	Action = function()
		for _, m in ipairs(Modules) do if m.Enabled and m.Category ~= "Settings" then SetEnabled(m, false, true) end end
		ui.RebuildList(); ui.Notify("All modules disabled", false)
	end }
Module{ Name = "Unload", Category = "Settings", Desc = "Completely removes Aerovolt from your game until you run it again.", Action = function() ui.Unload() end }

----------------------------------------------------------------------
-- high slider values + config file (writefile / readfile from the executor's file library)
----------------------------------------------------------------------
do
	local FILE = "AerovoltConfig.json"
	local HttpService = game:GetService("HttpService")
	ui.ConfigFile = FILE
	ui.CanFS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
	ui.SliderRows = {}

	-- "Module.Setting" -> highest value while High Slider Values is on
	ui.HighMax = {
		["Speed.Speed"] = 900, ["Fly.Speed"] = 1500, ["Fly.Vertical"] = 900, ["VehicleFly.Speed"] = 2000, ["VehicleFly.Vertical"] = 1200,
		["InfiniteJump.Power"] = 500, ["HighJump.Power"] = 1500, ["Bhop.Boost"] = 150, ["Glide.Fall Speed"] = 200,
		["Spider.Speed"] = 300, ["Gravity.Gravity"] = 1500, ["Dash.Power"] = 1000, ["Spinbot.Speed"] = 240, ["HipHeight.Height"] = 150,
		["NoFall.Threshold"] = 400, ["AntiFling.Threshold"] = 5000, ["Follow.Distance"] = 200,
		["ESP.Max Distance"] = 20000, ["NameTags.Max Distance"] = 20000, ["Tracers.Max Distance"] = 20000, ["Chams.Max Distance"] = 20000,
		["CamDistance.Max Zoom"] = 10000, ["Freecam.Speed"] = 1000,
		["Hitbox Visualizer.Max Distance"] = 20000, ["Hitbox Expander.Size"] = 200, ["FOV Circle.Radius"] = 1500,
		["Aim Assist.Max Distance"] = 10000, ["Aim Assist.Pull Speed"] = 720, ["Aimbot.Max Distance"] = 10000, ["Triggerbot.Max Distance"] = 10000,
	}
	for _, m in ipairs(Modules) do
		for _, st in ipairs(m.Settings or {}) do
			if st.Type == "Slider" then st.High = ui.HighMax[m.Name .. "." .. st.Name] end
		end
	end

	function ui.MaxOf(st)
		return (GuiSettings.Values["High Slider Values"] and st.High) or st.Max
	end

	-- pulls any value that is above the current maximum back down; returns what it changed
	function ui.ClampSliders()
		local changedList = {}
		for _, m in ipairs(Modules) do
			for _, st in ipairs(m.Settings or {}) do
				if st.Type == "Slider" then
					local v, lim = m.Values[st.Name], ui.MaxOf(st)
					if type(v) == "number" and v > lim then
						m.Values[st.Name] = lim
						table.insert(changedList, { m, st.Name })
					end
				end
			end
		end
		return changedList
	end

	function ui.EncodeValue(v)
		if typeof(v) == "Color3" then return { t = "Color3", r = v.R, g = v.G, b = v.B } end
		return v
	end
	local function decode(v)
		if type(v) == "table" and v.t == "Color3" and type(v.r) == "number" and type(v.g) == "number" and type(v.b) == "number" then
			return Color3.new(math.clamp(v.r, 0, 1), math.clamp(v.g, 0, 1), math.clamp(v.b, 0, 1))
		end
		return v
	end

	-- returns the saved config, or nil when there is no file / it can't be read (defaults are used then)
	function ui.ReadConfig()
		if not ui.CanFS then return nil end
		local okF, exists = pcall(isfile, FILE)
		if not okF or not exists then return nil end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(FILE)) end)
		if ok and type(data) == "table" and type(data.modules) == "table" then return data end
		return nil
	end

	-- settings, keybinds and bind modes (before the menu is built so every row shows the loaded value)
	function ui.ApplyConfigValues(cfg)
		for _, m in ipairs(Modules) do
			local e = cfg.modules[m.Name]
			if type(e) == "table" then
				if type(e.values) == "table" then
					for _, st in ipairs(m.Settings or {}) do
						local v = decode(e.values[st.Name])
						if v ~= nil then
							if st.Type == "Slider" and type(v) == "number" then
								m.Values[st.Name] = math.clamp(v, st.Min, st.High or st.Max)
							elseif st.Type == "Toggle" and type(v) == "boolean" then
								m.Values[st.Name] = v
							elseif st.Type == "Mode" and type(v) == "string" then
								if type(st.Options) == "function" or table.find(st.Options, v) then m.Values[st.Name] = v end
							elseif st.Type == "Color" and typeof(v) == "Color3" then
								m.Values[st.Name] = v
							end
						end
					end
				end
				if type(e.bind) == "string" then
					local ok, key = pcall(function() return Enum.KeyCode[e.bind] end)
					if ok and key then m.Bind = key end
				end
				if e.bindMode == "Hold" or e.bindMode == "Toggle" then m.BindMode = e.bindMode end
			end
		end
		ui.ClampSliders() -- the High Slider Values toggle itself was just loaded, so settle the limits
		for _, m in ipairs(Modules) do
			if m.Name == "Theme" and m.OnChanged then Safe(m.OnChanged, m, "Color") end
		end
	end

	-- which modules were on
	function ui.ApplyConfigEnabled(cfg)
		for _, m in ipairs(Modules) do
			local e = cfg.modules[m.Name]
			if type(e) == "table" and type(e.enabled) == "boolean" and not m.Action and not m.Passive then
				SetEnabled(m, e.enabled, true)
			end
		end
	end

	ui.Config = ui.ReadConfig()
	if ui.Config then ui.ApplyConfigValues(ui.Config) end
end

----------------------------------------------------------------------
-- main loop
----------------------------------------------------------------------
Conn(RunService.Heartbeat, function(dt)
	for _, m in ipairs(Modules) do if m.Enabled and m.OnTick then Safe(m.OnTick, m, dt) end end
end)

----------------------------------------------------------------------
-- gui root
----------------------------------------------------------------------
local Gui = New("ScreenGui", { Name = "AerovoltClient", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 999999 }, PG)
ui.Gui = Gui

-- Two coordinate spaces are in play. "Raw" space is the real screen: UserInputService's mouse,
-- Camera:WorldToViewportPoint / ViewportPointToRay, and where a Position offset actually draws.
-- "Abs" space is GuiObject.AbsolutePosition, which can sit one GUI inset above raw space.
-- ui.MousePos() returns the cursor in abs space (for sliders, the color wheel, hover calibration).
-- Anything you place with Position, like the tooltip or the FOV circle, uses the raw mouse instead.
function ui.CalDY()
	local origin = ui.MenuFrame and -ui.MenuFrame.AbsolutePosition.Y or 0
	if not (ui.CalLo and ui.CalHi) then return origin end
	local inset = GuiService:GetGuiInset().Y
	for _, c in ipairs({ origin, 0, inset, -inset }) do
		if c >= ui.CalLo - 1.5 and c <= ui.CalHi + 1.5 then return c end
	end
	return (ui.CalLo + ui.CalHi) / 2
end
function ui.MousePos()
	return UIS:GetMouseLocation() - Vector2.new(0, ui.CalDY())
end

local Blur = New("BlurEffect", { Name = "AerovoltBlur", Size = 0 }, Lighting)

----------------------------------------------------------------------
-- ESP drawing
----------------------------------------------------------------------
local DrawGui = New("Frame", { Name = "ESP", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 0 }, Gui)
local Draw = {}
local function GetDraw(p)
	local d = Draw[p]; if d then return d end
	d = {}
	d.Box = New("Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, DrawGui)
	d.Stroke = New("UIStroke", { Thickness = 1.5 }, d.Box)
	d.Label = New("TextLabel", { BackgroundTransparency = 1, Font = FONT_B, TextSize = 13, TextStrokeTransparency = 0.4, Size = UDim2.fromOffset(260, 16), AnchorPoint = Vector2.new(0.5, 1), Visible = false }, DrawGui)
	d.HBg = New("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.3, BorderSizePixel = 0, Visible = false }, DrawGui)
	d.HFill = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), BorderSizePixel = 0 }, d.HBg)
	d.Tracer = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Visible = false }, DrawGui)
	Draw[p] = d
	return d
end
local function HideDraw(d) d.Box.Visible, d.Label.Visible, d.HBg.Visible, d.Tracer.Visible = false, false, false, false end
Conn(Players.PlayerRemoving, function(p)
	local d = Draw[p]
	if d then d.Box:Destroy(); d.Label:Destroy(); d.HBg:Destroy(); d.Tracer:Destroy(); Draw[p] = nil end
	if ChamObjs[p] then ChamObjs[p]:Destroy(); ChamObjs[p] = nil end
end)

local BOX = Vector3.new(2.2, 2.9, 2.2)
local function Project(root)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local c = root.Position
	for sx = -1, 1, 2 do for sy = -1, 1, 2 do for sz = -1, 1, 2 do
				local v = Camera:WorldToViewportPoint(c + Vector3.new(sx * BOX.X, sy * BOX.Y, sz * BOX.Z))
				if v.Z <= 0 then return nil end
				minX, maxX = math.min(minX, v.X), math.max(maxX, v.X)
				minY, maxY = math.min(minY, v.Y), math.max(maxY, v.Y)
			end end end
	return minX, minY, maxX, maxY
end

local function SetLine(f, a, b, thick)
	local dx, dy = b.X - a.X, b.Y - a.Y
	f.Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy), thick)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Rotation = math.deg(math.atan2(dy, dx))
	f.Visible = true
end

local function UpdateESP()
	if not (ESP.Enabled or Names.Enabled or Tracers.Enabled) then
		for _, d in pairs(Draw) do HideDraw(d) end
		return
	end
	local vp = Camera.ViewportSize
	local me = Root()
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= LP then
			local d = GetDraw(p)
			local ch = p.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				local okE = ESP.Enabled and Pass(ESP, p, root)
				local okN = Names.Enabled and Pass(Names, p, root)
				local okT = Tracers.Enabled and Pass(Tracers, p, root)
				local x1, y1, x2, y2
				if okE or okN then x1, y1, x2, y2 = Project(root) end
				if okE and x1 then
					d.Box.Visible = true
					d.Box.Position = UDim2.fromOffset(x1, y1)
					d.Box.Size = UDim2.fromOffset(x2 - x1, y2 - y1)
					d.Stroke.Color = ColorFor(p, ESP.Values.Color)
					if ESP.Values["Health Bar"] then
						local f = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
						d.HBg.Visible = true
						d.HBg.Position = UDim2.fromOffset(x1 - 6, y1)
						d.HBg.Size = UDim2.fromOffset(3, y2 - y1)
						d.HFill.Size = UDim2.fromScale(1, f)
						d.HFill.BackgroundColor3 = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(70, 255, 100), f)
					else d.HBg.Visible = false end
				else d.Box.Visible, d.HBg.Visible = false, false end
				if okN and x1 then
					local dist = me and (root.Position - me.Position).Magnitude or 0
					local txt = p.DisplayName
					if Names.Values["Show Distance"] then txt ..= (" [%dm]"):format(dist) end
					if Names.Values["Show Health"] then txt ..= (" %dhp"):format(hum.Health) end
					d.Label.Visible = true
					d.Label.Text = txt
					d.Label.TextColor3 = ColorFor(p, Names.Values.Color)
					d.Label.Position = UDim2.fromOffset((x1 + x2) / 2, y1 - 2)
				else d.Label.Visible = false end
				if okT then
					local v = Camera:WorldToViewportPoint(root.Position)
					if v.Z > 0 then
						local o = Tracers.Values.Origin
						local origin = o == "Bottom" and Vector2.new(vp.X / 2, vp.Y) or o == "Center" and vp / 2 or UIS:GetMouseLocation()
						d.Tracer.BackgroundColor3 = ColorFor(p, Tracers.Values.Color)
						SetLine(d.Tracer, origin, Vector2.new(v.X, v.Y), Tracers.Values.Thickness)
					else d.Tracer.Visible = false end
				else d.Tracer.Visible = false end
			else HideDraw(d) end
		end
	end
end

----------------------------------------------------------------------
-- notifications (bottom right)
----------------------------------------------------------------------
local NotifHolder = New("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -14), Size = UDim2.fromOffset(240, 320), BackgroundTransparency = 1, ZIndex = 50 }, Gui)
New("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, NotifHolder)
local notifCount = 0
function ui.Notify(text, good)
	if not Notifs.Enabled then return end
	notifCount += 1
	local f = New("Frame", { Size = UDim2.fromOffset(230, 26), BackgroundColor3 = C_HEAD, BackgroundTransparency = 0.1, BorderSizePixel = 0, LayoutOrder = notifCount }, NotifHolder)
	New("Frame", { Size = UDim2.new(0, 3, 1, 0), BorderSizePixel = 0, BackgroundColor3 = good == false and Color3.fromRGB(255, 80, 90) or Accent() }, f)
	local l = New("TextLabel", { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = text, Font = FONT, TextSize = 13, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left }, f)
	task.delay(Notifs.Values.Duration, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.3)
			f:Destroy()
		end
	end)
end

----------------------------------------------------------------------
-- ArrayList (right side, starting at the top)
----------------------------------------------------------------------
local TopRight = New("Frame", { Name = "TopRight", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(300, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 1 }, Gui)
New("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, TopRight)
ui.TopRight = TopRight

local ListHolder = New("Frame", { Name = "ArrayList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, TopRight)
New("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, ListHolder)

local ListEntries = {}
local TWEEN_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

local function GetSuffix(m)
	for _, s in ipairs(m.Settings or {}) do
		if s.Suffix then return tostring(m.Values[s.Name]) end
	end
end

-- entry = clipped outer frame (animates its height) holding an inner frame (slides in from the right)
local function CreateEntry(w, rowH)
	local e = { idx = 1, w = w, h = rowH }
	e.outer = New("Frame", { Size = UDim2.fromOffset(w, 0), BackgroundTransparency = 1, ClipsDescendants = true, BorderSizePixel = 0 }, ListHolder)
	e.inner = New("Frame", { Size = UDim2.new(1, 0, 0, rowH), Position = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, e.outer)
	e.lbl = New("TextLabel", { BackgroundTransparency = 1, Font = FONT, RichText = true, TextXAlignment = Enum.TextXAlignment.Left }, e.inner)
	New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, e.lbl)
	e.bar = New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0), BorderSizePixel = 0 }, e.inner)
	AddPainter(e.lbl, function() e.lbl.TextColor3 = Accent(e.idx * 0.03) end)
	AddPainter(e.bar, function() e.bar.BackgroundColor3 = Accent(e.idx * 0.03) end)
	e.tw = TweenService:Create(e.outer, TWEEN_IN, { Size = UDim2.fromOffset(w, rowH) })
	e.tw.Completed:Connect(function() e.tw = nil end)
	e.tw:Play()
	TweenService:Create(e.inner, TWEEN_IN, { Position = UDim2.fromScale(0, 0) }):Play()
	return e
end

local function UpdateEntry(e, it, V, order, rowH)
	e.idx = order
	e.outer.LayoutOrder = order
	if e.w ~= it.w or e.h ~= rowH then
		e.w, e.h = it.w, rowH
		if e.tw then e.tw:Cancel(); e.tw = nil end
		e.outer.Size = UDim2.fromOffset(it.w, rowH)
		e.inner.Size = UDim2.new(1, 0, 0, rowH)
	end
	e.inner.BackgroundTransparency = V.Background and (1 - V.Opacity) or 1
	e.lbl.Size = UDim2.new(1, V["Side Bar"] and -2 or 0, 1, 0)
	e.lbl.TextSize = V["Text Size"]
	e.lbl.TextStrokeTransparency = V.Background and 1 or 0.6
	local txt = it.name
	if it.suffix then txt ..= " <font color=\"rgb(170,170,180)\">" .. it.suffix .. "</font>" end
	e.lbl.Text = txt
	e.bar.Visible = V["Side Bar"]
end

local function RemoveEntry(e)
	if e.tw then e.tw:Cancel(); e.tw = nil end
	TweenService:Create(e.inner, TWEEN_OUT, { Position = UDim2.fromScale(1, 0) }):Play()
	local t = TweenService:Create(e.outer, TWEEN_OUT, { Size = UDim2.fromOffset(e.w, 0) })
	t.Completed:Connect(function() e.outer:Destroy() end)
	t:Play()
end

local function RebuildArrayList()
	ListHolder.Visible = ArrayList.Enabled
	local V = ArrayList.Values
	local size = V["Text Size"]
	local rowH = size + 4
	local items, wanted = {}, {}
	for _, m in ipairs(Modules) do
		if m.Enabled and not m.Action and not m.Passive and m.Category ~= "Settings" then
			local suffix = V["Show Suffix"] and GetSuffix(m) or nil
			local plain = m.Name .. (suffix and (" " .. suffix) or "")
			local w = TextService:GetTextSize(plain, size, FONT, Vector2.new(1e4, 1e4)).X + 14 + (V["Side Bar"] and 2 or 0)
			table.insert(items, { m = m, name = m.Name, suffix = suffix, w = math.ceil(w) })
			wanted[m] = true
		end
	end
	if V.Sort == "Longest" then table.sort(items, function(a, b) return a.w > b.w end)
	elseif V.Sort == "Shortest" then table.sort(items, function(a, b) return a.w < b.w end)
	else table.sort(items, function(a, b) return a.name < b.name end) end

	for m, e in pairs(ListEntries) do
		if not wanted[m] then ListEntries[m] = nil; RemoveEntry(e) end
	end
	for i, it in ipairs(items) do
		local e = ListEntries[it.m]
		if not e then e = CreateEntry(it.w, rowH); ListEntries[it.m] = e end
		UpdateEntry(e, it, V, i, rowH)
	end
end
ui.RebuildList = RebuildArrayList

----------------------------------------------------------------------
-- menu root
----------------------------------------------------------------------
local Menu = New("Frame", { Name = "Menu", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 10 }, Gui)
ui.MenuFrame = Menu
local Dim = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1 }, Menu)
local Modal = New("TextButton", { Size = UDim2.new(), BackgroundTransparency = 1, Text = "", Modal = false }, Menu)

-- hover description bar
local DescLabel = New("TextLabel", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = C_HEAD, BackgroundTransparency = 0.1, BorderSizePixel = 0, Font = FONT, TextSize = 13, TextColor3 = C_LIGHT, TextWrapped = true, RichText = true, Text = "", Visible = false, ZIndex = 300 }, Menu)
New("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, DescLabel)
New("UISizeConstraint", { MaxSize = Vector2.new(560, 1e4) }, DescLabel)
local DescStroke = New("UIStroke", { Thickness = 1, Transparency = 0.3 }, DescLabel); Reg(DescStroke, "Color")
local function SetDesc(t) DescLabel.Text = t or ""; DescLabel.Visible = (t ~= nil and t ~= "") end

-- tooltip style follows the cursor; bottom bar style stays pinned
local function PlaceDesc()
	if GuiSettings.Values["Description Style"] == "Bottom Bar" then
		DescLabel.AnchorPoint = Vector2.new(0.5, 1)
		DescLabel.Position = UDim2.new(0.5, 0, 1, -18)
		return
	end
	local mp, vp, sz = UIS:GetMouseLocation(), Gui.AbsoluteSize, DescLabel.AbsoluteSize
	local x = math.min(mp.X + 16, vp.X - sz.X - 6)
	local y = mp.Y + 22
	if y + sz.Y > vp.Y - 6 then y = mp.Y - sz.Y - 12 end
	DescLabel.AnchorPoint = Vector2.zero
	DescLabel.Position = UDim2.fromOffset(math.max(x, 6), math.max(y, 6))
end

local function Brief(str)
	if not str or str == "" then return "" end
	return str:match("^(.-%.)%s") or str
end
function ui.HoverText(title, desc)
	local d = Brief(desc)
	if d == "" then return "<b>" .. title .. "</b>" end
	return "<b>" .. title .. "</b>  -  " .. d
end

----------------------------------------------------------------------
-- hover system (checks the mouse against every target each frame,
-- so it can never get stuck like MouseEnter / MouseLeave can)
----------------------------------------------------------------------
local HoverTargets = {}
function ui.AddHover(inst, textFn, zref, cb)
	local t = { inst = inst, text = textFn, z = zref or inst, cb = cb, over = false, since = 0 }
	table.insert(HoverTargets, t)
	inst.MouseEnter:Connect(function() t.over = true; t.since = tick() end)
	inst.MouseLeave:Connect(function() t.over = false end)
end

local function Shown(inst)
	local o = inst
	while o and o ~= Gui do
		if o:IsA("GuiObject") and not o.Visible then return false end
		o = o.Parent
	end
	return o == Gui
end

local CurHover
local function SetHover(t)
	if CurHover == t then return end
	if CurHover and CurHover.cb then CurHover.cb(false) end
	CurHover = t
	if t then
		if t.cb then t.cb(true) end
		if GuiSettings.Values.Descriptions then SetDesc(t.text()) else SetDesc(nil) end
	else
		SetDesc(nil)
	end
end

local function InsideClip(inst)
	local o = inst.Parent
	while o and o ~= Gui do
		if o:IsA("GuiObject") and o.ClipsDescendants then return true end
		o = o.Parent
	end
	return false
end

-- the engine says the cursor is inside t, so its real Y lies between t's top and bottom;
-- every such sample narrows down how far the raw cursor reading is off
local function Calibrate(t)
	local inst = t.inst
	if InsideClip(inst) then return end
	local p, sz = inst.AbsolutePosition, inst.AbsoluteSize
	if sz.Y > 60 then return end
	local ry = UIS:GetMouseLocation().Y
	local lo, hi = ry - (p.Y + sz.Y), ry - p.Y
	if not ui.CalLo or lo > ui.CalHi + 3 or hi < ui.CalLo - 3 then
		ui.CalLo, ui.CalHi = lo, hi
	else
		ui.CalLo = math.max(ui.CalLo - 0.2, lo)
		ui.CalHi = math.min(ui.CalHi + 0.2, hi)
		if ui.CalLo > ui.CalHi then
			local mid = (ui.CalLo + ui.CalHi) / 2
			ui.CalLo, ui.CalHi = mid, mid
		end
	end
end

local function UpdateHover()
	if not ui.MenuOpen then
		for _, t in ipairs(HoverTargets) do t.over = false end
		SetHover(nil)
		return
	end
	local best, bestZ
	for i = #HoverTargets, 1, -1 do
		local t = HoverTargets[i]
		if not t.inst.Parent then
			table.remove(HoverTargets, i)
		elseif t.over then
			if Shown(t.inst) then
				local z = t.z.ZIndex
				if not best or z > bestZ or (z == bestZ and t.since > best.since) then best, bestZ = t, z end
			else
				t.over = false
			end
		end
	end
	SetHover(best)
	if best then Calibrate(best) end
	if CurHover and GuiSettings.Values.Descriptions then
		local txt = CurHover.text()
		if DescLabel.Text ~= txt then DescLabel.Text = txt end
		DescLabel.Visible = true
		PlaceDesc()
	else
		DescLabel.Visible = false
	end
end

local Drag, PanelDrag, Listening
local ROWH, SETH, PANEL_W, HEADER_H, GAP = 26, 24, 190, 30, 12

local function changed(m, name)
	if m.OnChanged then Safe(m.OnChanged, m, name) end
	ui.RebuildList()
end

----------------------------------------------------------------------
-- color picker (one shared popup used by every Color setting)
----------------------------------------------------------------------
local PK_W, PK_H, WR = 176, 236, 60
local Picker = New("Frame", { Name = "Picker", Size = UDim2.fromOffset(PK_W, PK_H), BackgroundColor3 = C_HEAD, BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 250 }, Menu)
local pkStroke = New("UIStroke", { Thickness = 1.5 }, Picker); Reg(pkStroke, "Color")
local pkTitle = New("TextLabel", { Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -40, 0, 18), BackgroundTransparency = 1, Font = FONT_B, TextSize = 13, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, Picker)
local pkClose = New("TextButton", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(20, 18), BackgroundTransparency = 1, Font = FONT_B, TextSize = 14, TextColor3 = C_DIM, Text = "x" }, Picker)

local Wheel = New("Frame", { Position = UDim2.fromOffset(PK_W / 2 - WR, 34), Size = UDim2.fromOffset(WR * 2, WR * 2), BackgroundTransparency = 1 }, Picker)
do
	local WL, N = WR + 4, 90
	for i = 0, N - 1 do
		local hue = i / N
		local ang = hue * 2 * math.pi
		local spoke = New("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, math.cos(ang) * WL / 2, 0.5, math.sin(ang) * WL / 2),
			Size = UDim2.fromOffset(WL, 6), Rotation = hue * 360,
			BackgroundColor3 = WHITE, BorderSizePixel = 0,
		}, Wheel)
		New("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, WHITE),
			ColorSequenceKeypoint.new(WR / WL, Color3.fromHSV(hue, 1, 1)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(hue, 1, 1)),
		}) }, spoke)
	end
end
local WheelDark = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(WR * 2, WR * 2), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0 }, Wheel)
New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, WheelDark)
local WheelRing = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(WR * 2, WR * 2), BackgroundTransparency = 1, BorderSizePixel = 0 }, Wheel)
New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, WheelRing)
New("UIStroke", { Thickness = 10, Color = C_HEAD, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, WheelRing)
local Marker = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0 }, Wheel)
New("UICorner", { CornerRadius = UDim.new(0.5, 0) }, Marker)
New("UIStroke", { Thickness = 2, Color = WHITE }, Marker)
local WheelHit = New("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, Wheel)

local Bar = New("Frame", { Position = UDim2.fromOffset(18, 34 + WR * 2 + 14), Size = UDim2.fromOffset(PK_W - 36, 14), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, Picker)
local BarGrad = New("UIGradient", { Color = ColorSequence.new(Color3.new(0, 0, 0), WHITE) }, Bar)
local Knob = New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1, 0.5), Size = UDim2.fromOffset(4, 20), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, Bar)
New("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0) }, Knob)
local BarHit = New("TextButton", { Position = UDim2.fromOffset(12, 34 + WR * 2 + 8), Size = UDim2.fromOffset(PK_W - 24, 26), BackgroundTransparency = 1, Text = "", AutoButtonColor = false }, Picker)

local Preview = New("Frame", { Position = UDim2.fromOffset(18, PK_H - 34), Size = UDim2.fromOffset(40, 22), BorderSizePixel = 0 }, Picker)
New("UIStroke", { Thickness = 1, Color = Color3.fromRGB(80, 80, 98) }, Preview)
local RgbLabel = New("TextLabel", { Position = UDim2.fromOffset(66, PK_H - 34), Size = UDim2.new(1, -74, 0, 22), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = C_LIGHT, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, Picker)

local Pk = { m = nil, s = nil, h = 0, sat = 0, v = 1 }
local function PickerApply(fromUser)
	local col = Color3.fromHSV(Pk.h, Pk.sat, Pk.v)
	local ang = Pk.h * 2 * math.pi
	Marker.Position = UDim2.new(0.5, math.cos(ang) * Pk.sat * WR, 0.5, math.sin(ang) * Pk.sat * WR)
	Marker.BackgroundColor3 = col
	WheelDark.BackgroundTransparency = Pk.v
	BarGrad.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromHSV(Pk.h, Pk.sat, 1))
	Knob.Position = UDim2.fromScale(Pk.v, 0.5)
	Preview.BackgroundColor3 = col
	RgbLabel.Text = string.format("R %d   G %d   B %d", B255(col.R), B255(col.G), B255(col.B))
	if fromUser and Pk.m then
		Pk.m.Values[Pk.s.Name] = col
		Repaint(Pk.m)
		changed(Pk.m, Pk.s.Name)
	end
end

local function WheelFromMouse(x, y)
	local c = Wheel.AbsolutePosition + Wheel.AbsoluteSize / 2
	local dx, dy = x - c.X, y - c.Y
	if Pk.v < 0.05 then Pk.v = 1 end
	Pk.sat = math.min(math.sqrt(dx * dx + dy * dy) / (Wheel.AbsoluteSize.X / 2), 1)
	Pk.h = (math.atan2(dy, dx) / (2 * math.pi)) % 1
	PickerApply(true)
end
local function BarFromMouse(x)
	Pk.v = math.clamp((x - Bar.AbsolutePosition.X) / math.max(Bar.AbsoluteSize.X, 1), 0, 1)
	PickerApply(true)
end
WheelHit.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		Drag = WheelFromMouse
		local ml = ui.MousePos(); WheelFromMouse(ml.X, ml.Y)
	end
end)
BarHit.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		Drag = function(x) BarFromMouse(x) end
		BarFromMouse(ui.MousePos().X)
	end
end)

local function ClosePicker() Picker.Visible = false; Pk.m, Pk.s = nil, nil end
pkClose.MouseButton1Click:Connect(ClosePicker)

function ui.OpenPicker(m, s, row)
	if Picker.Visible and Pk.m == m and Pk.s == s then ClosePicker() return end
	Pk.m, Pk.s = m, s
	Pk.h, Pk.sat, Pk.v = m.Values[s.Name]:ToHSV()
	pkTitle.Text = m.Name .. ": " .. s.Name
	local rp, rs = row.AbsolutePosition, row.AbsoluteSize
	local vp = Camera.ViewportSize
	local org = Menu.AbsolutePosition
	local x = rp.X - org.X + rs.X + 8
	if x + PK_W > vp.X then x = rp.X - org.X - PK_W - 8 end
	local y = math.clamp(rp.Y - org.Y - 20, 10, math.max(vp.Y - PK_H - 10, 10))
	Picker.Position = UDim2.fromOffset(math.max(x, 4), y)
	Picker.Visible = true
	PickerApply(false)
end

local function pickerText() return ui.HoverText("Color wheel", "Click or drag to pick a color. The bar sets brightness.") end
for _, o in ipairs({ Picker, WheelHit, BarHit, pkClose }) do ui.AddHover(o, pickerText, Picker) end

----------------------------------------------------------------------
-- setting rows
----------------------------------------------------------------------
local function SettingButton(parent, order)
	return New("TextButton", { Size = UDim2.new(1, 0, 0, SETH), BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = order }, parent)
end
local function SettingLabel(row, text)
	return New("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Text = text, Font = FONT, TextSize = 12, TextColor3 = C_LIGHT, TextXAlignment = Enum.TextXAlignment.Left }, row)
end
local function RightLabel(row)
	return New("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0.45, 0, 1, 0), BackgroundTransparency = 1, Font = FONT, TextSize = 12, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Right }, row)
end

local function SliderRow(m, s, parent, order)
	local row = SettingButton(parent, order)
	local fill = New("Frame", { Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, BackgroundTransparency = 0.5 }, row)
	Reg(fill, "BackgroundColor3")
	SettingLabel(row, s.Name)
	local valL = RightLabel(row)
	local function show()
		local v = m.Values[s.Name]
		fill.Size = UDim2.fromScale(math.clamp((v - s.Min) / (ui.MaxOf(s) - s.Min), 0, 1), 1)
		valL.Text = Fmt(v)
	end
	show()
	table.insert(ui.SliderRows, { row = row, show = show })
	local function setFromX(x)
		local a = math.clamp((x - row.AbsolutePosition.X) / math.max(row.AbsoluteSize.X, 1), 0, 1)
		local hi = ui.MaxOf(s)
		local v = s.Min + (hi - s.Min) * a
		v = s.Min + math.floor((v - s.Min) / s.Step + 0.5) * s.Step
		v = tonumber(string.format("%.4f", math.clamp(v, s.Min, hi)))
		m.Values[s.Name] = v
		show(); changed(m, s.Name)
	end
	row.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			Drag = function(x) setFromX(x) end
			setFromX(ui.MousePos().X)
		end
	end)
	return row
end

function ui.RefreshSliders()
	local list = ui.SliderRows
	for i = #list, 1, -1 do
		local r = list[i]
		if r.row.Parent then r.show() else table.remove(list, i) end
	end
end
function ui.OnHighChanged()
	for _, c in ipairs(ui.ClampSliders()) do
		local m = c[1]
		if m.OnChanged then Safe(m.OnChanged, m, c[2]) end
	end
	ui.RefreshSliders()
	ui.RebuildList()
end

local function ToggleRow(m, s, parent, order)
	local row = SettingButton(parent, order)
	SettingLabel(row, s.Name)
	local box = New("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0 }, row)
	New("UIStroke", { Color = Color3.fromRGB(70, 70, 88), Thickness = 1 }, box)
	local function paint() box.BackgroundColor3 = m.Values[s.Name] and Accent() or Color3.fromRGB(30, 30, 40) end
	AddPainter(box, paint)
	row.MouseButton1Click:Connect(function() m.Values[s.Name] = not m.Values[s.Name]; paint(); changed(m, s.Name) end)
	return row
end

local function ModeRow(m, s, parent, order)
	local function opts() return type(s.Options) == "function" and s.Options() or s.Options end
	if type(s.Options) == "function" then
		local o = opts()
		if not table.find(o, m.Values[s.Name]) then m.Values[s.Name] = o[1] end
	end
	local row = SettingButton(parent, order)
	SettingLabel(row, s.Name)
	local valL = RightLabel(row)
	Reg(valL, "TextColor3")
	local function refresh() valL.Text = tostring(m.Values[s.Name]) end
	refresh()
	local function step(dir)
		local o = opts()
		local idx = table.find(o, m.Values[s.Name]) or 0
		idx = ((idx - 1 + dir) % #o) + 1
		m.Values[s.Name] = o[idx]
		refresh(); changed(m, s.Name)
	end
	row.MouseButton1Click:Connect(function() step(1) end)
	row.MouseButton2Click:Connect(function() step(-1) end)
	return row
end

local function ColorRow(m, s, parent, order)
	local row = SettingButton(parent, order)
	SettingLabel(row, s.Name)
	local sw = New("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(30, 12), BorderSizePixel = 0 }, row)
	New("UIStroke", { Color = Color3.fromRGB(90, 90, 108), Thickness = 1 }, sw)
	AddPainter(sw, function() sw.BackgroundColor3 = m.Values[s.Name] end, m)
	row.MouseButton1Click:Connect(function() ui.OpenPicker(m, s, row) end)
	return row
end

local function BindRow(m, parent, order)
	local row = SettingButton(parent, order)
	SettingLabel(row, "Bind")
	local valL = RightLabel(row)
	AddPainter(valL, function()
		valL.TextColor3 = C_DIM
		valL.Text = m.Bind and ("[" .. m.Bind.Name .. "]") or "[NONE]"
	end, m)
	row.MouseButton1Click:Connect(function()
		if Listening then Repaint(Listening.m) end
		Listening = { m = m }
		valL.Text = "[ press a key ]"
	end)
	return row
end

----------------------------------------------------------------------
-- module row (used in panels and in search results)
----------------------------------------------------------------------
local function BindModeRow(m, parent, order)
	local row = SettingButton(parent, order)
	SettingLabel(row, "Bind Mode")
	local valL = RightLabel(row)
	Reg(valL, "TextColor3")
	local function refresh() valL.Text = m.BindMode end
	refresh()
	local function flip() m.BindMode = (m.BindMode == "Hold") and "Toggle" or "Hold"; refresh() end
	row.MouseButton1Click:Connect(flip)
	row.MouseButton2Click:Connect(flip)
	return row
end

local function BuildModuleRow(m, parent, showCat, idx, zref)
	local holder = New("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = idx or 0 }, parent)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, holder)

	local btn = New("TextButton", { Size = UDim2.new(1, 0, 0, ROWH), BackgroundColor3 = C_ROW, BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = 1 }, holder)
	local nameL = New("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Text = m.Name, Font = FONT, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }, btn)
	New("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 0), Size = UDim2.new(0.4, 0, 1, 0), BackgroundTransparency = 1, Text = showCat and m.Category or "", Font = FONT, TextSize = 11, TextColor3 = C_DIM, TextXAlignment = Enum.TextXAlignment.Right }, btn)
	local ind = New("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(12, ROWH), BackgroundTransparency = 1, Font = FONT_B, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center }, btn)

	-- fixed height + clipping so the settings can be tweened open and closed
	local setFrame = New("Frame", { Size = UDim2.new(1, 0, 0, 0), ClipsDescendants = true, BackgroundColor3 = C_SET, BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false, LayoutOrder = 2 }, holder)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, setFrame)

	local expanded, hover = false, false
	local function paint()
		if m.Enabled then
			btn.BackgroundColor3 = Accent((idx or 0) * 0.05):Lerp(Color3.new(0, 0, 0), 0.25)
			btn.BackgroundTransparency = 0
		else
			btn.BackgroundColor3 = hover and C_ROWHOV or C_ROW
			btn.BackgroundTransparency = 0.05
		end
		nameL.TextColor3 = (m.Enabled or hover) and WHITE or C_LIGHT
		ind.Text = expanded and "-" or "+"
		ind.TextColor3 = m.Enabled and WHITE or C_DIM
	end
	AddPainter(btn, paint, m)

	local rows = 0
	for _, s in ipairs(m.Settings or {}) do
		rows += 1
		local row
		if s.Type == "Slider" then row = SliderRow(m, s, setFrame, rows)
		elseif s.Type == "Mode" then row = ModeRow(m, s, setFrame, rows)
		elseif s.Type == "Color" then row = ColorRow(m, s, setFrame, rows)
		else row = ToggleRow(m, s, setFrame, rows) end
		ui.AddHover(row, function() return ui.HoverText(m.Name .. ": " .. s.Name, s.Desc) end, zref)
	end
	if not m.Passive then
		rows += 1
		local row = BindRow(m, setFrame, rows)
		ui.AddHover(row, function()
			return ui.HoverText(m.Name .. ": Bind", "Sets a key that " .. (m.Action and "runs" or "toggles") .. " this module.")
		end, zref)
		if not m.Action then
			rows += 1
			local mrow = BindModeRow(m, setFrame, rows)
			ui.AddHover(mrow, function()
				return ui.HoverText(m.Name .. ": Bind Mode", "Toggle switches it on and off with the key, Hold keeps it on only while the key is down.")
			end, zref)
		end
	end
	local fullH = rows * SETH

	ui.AddHover(btn, function() return ui.HoverText(m.Name, m.Desc) end, zref, function(on) hover = on; paint() end)

	local expTween
	local function toggleExpand()
		expanded = not expanded
		if expTween then expTween:Cancel() end
		if expanded then
			setFrame.Visible = true
			expTween = TweenService:Create(setFrame, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, fullH) })
		else
			if Pk.m == m then ClosePicker() end
			local t = TweenService:Create(setFrame, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = UDim2.new(1, 0, 0, 0) })
			t.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed and not expanded then setFrame.Visible = false end
			end)
			expTween = t
		end
		expTween:Play()
		paint()
	end
	btn.MouseButton1Click:Connect(function()
		if m.Passive then toggleExpand() else ToggleModule(m) end
	end)
	btn.MouseButton2Click:Connect(toggleExpand)
	return holder
end

----------------------------------------------------------------------
-- panels
----------------------------------------------------------------------
local PanelFrames, PanelContents, PanelOrder = {}, {}, {}
local function Raise(panel)
	local i = table.find(PanelOrder, panel); if i then table.remove(PanelOrder, i) end
	table.insert(PanelOrder, panel)
	for n, p in ipairs(PanelOrder) do p.ZIndex = 4 + n end
end

local function CreatePanel(cat, index)
	local panel = New("Frame", { Name = cat, Size = UDim2.fromOffset(PANEL_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false }, Menu)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	local header = New("TextButton", { Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = C_HEAD, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = 1 }, panel)
	New("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -40, 1, -2), BackgroundTransparency = 1, Text = cat, Font = FONT_B, TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left }, header)
	New("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 24, 1, -2), BackgroundTransparency = 1, Text = tostring(#ByCat[cat]), Font = FONT, TextSize = 11, TextColor3 = C_DIM, TextXAlignment = Enum.TextXAlignment.Right }, header)
	local line = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0 }, header)
	Reg(line, "BackgroundColor3", index * 0.12)

	local content = New("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, panel)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, content)
	for i, m in ipairs(ByCat[cat]) do BuildModuleRow(m, content, false, i, panel) end

	header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			ClosePicker()
			ui.BeginDrag(panel, i)
			Raise(panel)
		end
	end)
	header.MouseButton2Click:Connect(function() content.Visible = not content.Visible end)
	ui.AddHover(header, function()
		return ui.HoverText(cat, CatDesc[cat])
	end, panel)

	PanelFrames[index], PanelContents[index] = panel, content
	table.insert(PanelOrder, panel)
end
for i, cat in ipairs(Categories) do CreatePanel(cat, i) end

-- the Hub is the only tab open at first; it opens and closes every other tab
local HubPanel, HubContent
local HubPaints = {}
local function HubRefresh() for _, f in ipairs(HubPaints) do f() end end

-- panels can never leave the screen: the whole width and the header always stay visible
function ui.ClampXY(x, y)
	local vp = Vector2.new(math.min(ui.Gui.AbsoluteSize.X, Camera.ViewportSize.X), math.min(ui.Gui.AbsoluteSize.Y, Camera.ViewportSize.Y))
	return math.clamp(x, 0, math.max(vp.X - PANEL_W, 0)), math.clamp(y, 0, math.max(vp.Y - HEADER_H, 0))
end
local function ClampPanel(p)
	local x, y = ui.ClampXY(p.Position.X.Offset, p.Position.Y.Offset)
	p.Position = UDim2.fromOffset(x, y)
end
function ui.ClampPanels()
	if HubPanel then ClampPanel(HubPanel) end
	for _, p in ipairs(PanelFrames) do ClampPanel(p) end
end

local function SetTab(index, open)
	local panel = PanelFrames[index]
	if not panel or panel.Visible == open then return end
	if open then
		ClampPanel(panel)
		panel.Visible = true
		Raise(panel)
		local pos = panel.Position
		panel.Position = pos + UDim2.fromOffset(0, 12)
		TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos }):Play()
	else
		if Pk.m and Pk.m.Category == Categories[index] then ClosePicker() end
		panel.Visible = false
	end
	HubRefresh()
end
ui.SetTab = SetTab

do
	local panel = New("Frame", { Name = "Hub", Size = UDim2.fromOffset(PANEL_W, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, BorderSizePixel = 0 }, Menu)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, panel)
	local header = New("TextButton", { Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = C_HEAD, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = 1 }, panel)
	New("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -60, 1, -2), BackgroundTransparency = 1, Text = "Hub", Font = FONT_B, TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left }, header)
	New("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.new(0, 44, 1, -2), BackgroundTransparency = 1, Text = VERSION, Font = FONT, TextSize = 11, TextColor3 = C_DIM, TextXAlignment = Enum.TextXAlignment.Right }, header)
	local line = New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0 }, header)
	Reg(line, "BackgroundColor3", 0)

	local content = New("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, panel)
	New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, content)

	local function Row(order, text)
		local btn = New("TextButton", { Size = UDim2.new(1, 0, 0, ROWH), BackgroundColor3 = C_ROW, BackgroundTransparency = 0.05, BorderSizePixel = 0, AutoButtonColor = false, Text = "", LayoutOrder = order }, content)
		local nameL = New("TextLabel", { Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0.6, 0, 1, 0), BackgroundTransparency = 1, Text = text, Font = FONT, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left }, btn)
		return btn, nameL
	end

	for i, cat in ipairs(Categories) do
		local btn, nameL = Row(i, cat)
		New("TextLabel", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0.3, 0, 1, 0), BackgroundTransparency = 1, Text = tostring(#ByCat[cat]), Font = FONT, TextSize = 11, TextColor3 = C_DIM, TextXAlignment = Enum.TextXAlignment.Right }, btn)
		local hover = false
		local function paint()
			local open = PanelFrames[i].Visible
			if open then
				btn.BackgroundColor3 = Accent(i * 0.12):Lerp(Color3.new(0, 0, 0), 0.25)
				btn.BackgroundTransparency = 0
			else
				btn.BackgroundColor3 = hover and C_ROWHOV or C_ROW
				btn.BackgroundTransparency = 0.05
			end
			nameL.TextColor3 = (open or hover) and WHITE or C_LIGHT
		end
		AddPainter(btn, paint)
		table.insert(HubPaints, paint)
		btn.MouseButton1Click:Connect(function() SetTab(i, not PanelFrames[i].Visible) end)
		ui.AddHover(btn, function() return ui.HoverText(cat, CatDesc[cat]) end, panel, function(on) hover = on; paint() end)
	end

	local function ActionRow(order, text, desc, fn)
		local btn, nameL = Row(order, text)
		nameL.TextColor3 = C_DIM
		btn.MouseButton1Click:Connect(fn)
		ui.AddHover(btn, function() return ui.HoverText(text, desc) end, panel, function(on)
			btn.BackgroundColor3 = on and C_ROWHOV or C_ROW
			nameL.TextColor3 = on and WHITE or C_DIM
		end)
	end
	local n = #Categories
	ActionRow(n + 1, "Open All", "Opens every tab.", function() for i = 1, n do SetTab(i, true) end end)
	ActionRow(n + 2, "Close All", "Closes every tab and leaves only the Hub.", function() for i = 1, n do SetTab(i, false) end end)

	header.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			ClosePicker()
			ui.BeginDrag(panel, i)
			Raise(panel)
		end
	end)
	header.MouseButton2Click:Connect(function() content.Visible = not content.Visible end)
	ui.AddHover(header, function() return ui.HoverText("Hub", "Open and close the tabs you want to see.") end, panel)

	HubPanel, HubContent = panel, content
	table.insert(PanelOrder, panel)
end

function ui.ResetPanels()
	ClosePicker()
	local vp = Camera.ViewportSize
	if vp.X < 400 then vp = Vector2.new(1280, 720) end
	local cols = #PanelFrames + 1
	local step = math.min(PANEL_W + GAP, (vp.X - 20 - PANEL_W) / (cols - 1))
	local total = (cols - 1) * step + PANEL_W
	local x0 = math.max(10, (vp.X - total) / 2)
	HubPanel.Position = UDim2.fromOffset(x0, 70)
	HubContent.Visible = true
	Raise(HubPanel)
	for i, p in ipairs(PanelFrames) do
		p.Position = UDim2.fromOffset(x0 + i * step, 70)
		PanelContents[i].Visible = true
		Raise(p)
	end
end
ui.ResetPanels()
HubRefresh()

function ui.SaveConfig()
	if not ui.CanFS then
		ui.Notify("Saving needs an executor with writefile and readfile", false)
		return
	end
	local cfg = { version = VERSION, modules = {}, panels = {} }
	for _, m in ipairs(Modules) do
		local e = { values = {}, bindMode = m.BindMode }
		if m.Bind then e.bind = m.Bind.Name end
		if not m.Action and not m.Passive then e.enabled = m.Enabled end
		for _, st in ipairs(m.Settings or {}) do e.values[st.Name] = ui.EncodeValue(m.Values[st.Name]) end
		cfg.modules[m.Name] = e
	end
	cfg.panels.Hub = { x = HubPanel.Position.X.Offset, y = HubPanel.Position.Y.Offset, collapsed = not HubContent.Visible }
	for i, cat in ipairs(Categories) do
		local p = PanelFrames[i]
		cfg.panels[cat] = { x = p.Position.X.Offset, y = p.Position.Y.Offset, open = p.Visible, collapsed = not PanelContents[i].Visible }
	end
	local ok, err = pcall(function()
		writefile(ui.ConfigFile, game:GetService("HttpService"):JSONEncode(cfg))
	end)
	if ok then
		ui.Notify("Settings saved", true)
	else
		ui.Notify("Could not save settings", false)
		warn("[Aerovolt] " .. tostring(err))
	end
end

-- panel positions, which tabs are open and which are collapsed
function ui.ApplyLayout(cfg)
	local P = cfg.panels
	if type(P) ~= "table" then return end
	local function place(panel, e)
		if type(e) == "table" and type(e.x) == "number" and type(e.y) == "number" then
			panel.Position = UDim2.fromOffset(e.x, e.y)
		end
	end
	place(HubPanel, P.Hub)
	if type(P.Hub) == "table" then HubContent.Visible = P.Hub.collapsed ~= true end
	for i, cat in ipairs(Categories) do
		local e = P[cat]
		if type(e) == "table" then
			place(PanelFrames[i], e)
			if type(e.open) == "boolean" then PanelFrames[i].Visible = e.open end
			PanelContents[i].Visible = e.collapsed ~= true
		end
	end
	HubRefresh()
	ui.ClampPanels()
end

----------------------------------------------------------------------
-- search
----------------------------------------------------------------------
local SearchBar = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(340, 32), BackgroundColor3 = C_HEAD, BorderSizePixel = 0, ZIndex = 200 }, Menu)
local sStroke = New("UIStroke", { Thickness = 1.5 }, SearchBar); Reg(sStroke, "Color")
local SearchBox = New("TextBox", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1, PlaceholderText = "Search any module...  (Ctrl+F)", PlaceholderColor3 = C_DIM, Text = "", ClearTextOnFocus = false, Font = FONT, TextSize = 14, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left }, SearchBar)
local Results = New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 50), Size = UDim2.fromOffset(340, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 200 }, Menu)
New("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, Results)
local CurrentResults = {}
local function searchText() return ui.HoverText("Search", "Type to find any module from any tab.") end
ui.AddHover(SearchBar, searchText, SearchBar)
ui.AddHover(SearchBox, searchText, SearchBar)

local function RebuildSearch()
	for _, c in ipairs(Results:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
	local q = SearchBox.Text:lower()
	CurrentResults = {}
	if q == "" then return end
	for _, m in ipairs(Modules) do
		if m.Name:lower():find(q, 1, true) or (m.Desc and m.Desc:lower():find(q, 1, true)) or m.Category:lower():find(q, 1, true) then
			table.insert(CurrentResults, m)
		end
	end
	table.sort(CurrentResults, function(a, b)
		local ap, bp = a.Name:lower():sub(1, #q) == q, b.Name:lower():sub(1, #q) == q
		if ap ~= bp then return ap end
		return a.Name < b.Name
	end)
	for i = 1, math.min(#CurrentResults, 8) do BuildModuleRow(CurrentResults[i], Results, true, i, Results) end
end
SearchBox:GetPropertyChangedSignal("Text"):Connect(RebuildSearch)
SearchBox.FocusLost:Connect(function(enter)
	if enter and CurrentResults[1] then ToggleModule(CurrentResults[1]) end
end)

----------------------------------------------------------------------
-- dragging (panels, HUD, sliders, color wheel)
----------------------------------------------------------------------
function ui.BeginDrag(frame, input, onEnd, clamp)
	PanelDrag = { panel = frame, start = Vector2.new(input.Position.X, input.Position.Y), pos = frame.Position, onEnd = onEnd, clamp = clamp }
end

Conn(UIS.InputChanged, function(i)
	if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
	if Drag then
		local ml = ui.MousePos()
		Drag(ml.X, ml.Y)
	end
	if PanelDrag then
		local d = Vector2.new(i.Position.X, i.Position.Y) - PanelDrag.start
		local nx, ny = PanelDrag.pos.X.Offset + d.X, PanelDrag.pos.Y.Offset + d.Y
		nx, ny = ui.ClampXY(nx, ny)
		PanelDrag.panel.Position = UDim2.fromOffset(nx, ny)
	end
end)
Conn(UIS.InputEnded, function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
		if PanelDrag and PanelDrag.onEnd then Safe(PanelDrag.onEnd) end
		Drag, PanelDrag = nil, nil
	end
end)

----------------------------------------------------------------------
-- toggle callback, interface, open / close
----------------------------------------------------------------------
ui.OnToggle = function(m, silent)
	Repaint(m)
	RebuildArrayList()
	if not silent and Notifs.Values["Module Toggles"] and m.Category ~= "Settings" then
		ui.Notify(m.Name .. (m.Enabled and " enabled" or " disabled"), m.Enabled)
	end
end

local function MenuKey() return Enum.KeyCode[GuiSettings.Values["Menu Key"]] end

function ui.ApplyInterface()
	if ui.MenuOpen then
		TweenService:Create(Blur, TweenInfo.new(0.2), { Size = GuiSettings.Values["Background Blur"] and 14 or 0 }):Play()
		TweenService:Create(Dim, TweenInfo.new(0.2), { BackgroundTransparency = GuiSettings.Values["Background Dim"] and 0.6 or 1 }):Play()
	end
end

local function SetMenu(open)
	ui.MenuOpen = open
	Modal.Modal = open
	if open then
		Menu.Visible = true
		ui.ClampPanels()
		ui.ApplyInterface()
	else
		ClosePicker()
		SearchBox:ReleaseFocus()
		SetHover(nil)
		Drag, PanelDrag = nil, nil
		TweenService:Create(Blur, TweenInfo.new(0.2), { Size = 0 }):Play()
		TweenService:Create(Dim, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.delay(0.2, function() if not ui.MenuOpen then Menu.Visible = false end end)
	end
end

ui.SetMenu = SetMenu

----------------------------------------------------------------------
-- keybinds
----------------------------------------------------------------------
Conn(UIS.InputBegan, function(input, gp)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	local key = input.KeyCode
	if Listening then
		local m = Listening.m; Listening = nil
		if key == Enum.KeyCode.Escape or key == Enum.KeyCode.Backspace then m.Bind = nil else m.Bind = key end
		Repaint(m)
		return
	end
	if key == MenuKey() then SetMenu(not ui.MenuOpen) return end
	if ui.MenuOpen and key == Enum.KeyCode.F and UIS:IsKeyDown(Enum.KeyCode.LeftControl) then
		SearchBox:CaptureFocus() return
	end
	if gp or Typing() then return end
	for _, m in ipairs(Modules) do
		if m.Bind == key then
			if m.Action or m.BindMode ~= "Hold" then ToggleModule(m)
			elseif not m.Enabled then m._held = true; SetEnabled(m, true) end
		end
	end
end)

Conn(UIS.InputEnded, function(input)
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	for _, m in ipairs(Modules) do
		if m.Bind == input.KeyCode and m._held then
			m._held = false
			if m.Enabled then SetEnabled(m, false) end
		end
	end
end)

----------------------------------------------------------------------
-- render step (runs right after Roblox's camera so FOV / Freecam stick)
----------------------------------------------------------------------
RunService:BindToRenderStep("AerovoltRender", Enum.RenderPriority.Camera.Value + 1, function(dt)
	Camera = workspace.CurrentCamera
	for _, m in ipairs(Modules) do if m.Enabled and m.OnRender then Safe(m.OnRender, m, dt) end end
	Safe(UpdateESP)
	Safe(UpdateHover)
	if ThemeName == "Rainbow" then Repaint() end
end)

----------------------------------------------------------------------
-- unload
----------------------------------------------------------------------
function ui.Unload()
	for _, m in ipairs(Modules) do if m.Enabled then SetEnabled(m, false, true) end end
	for _, c in ipairs(Conns) do c:Disconnect() end
	pcall(function() RunService:UnbindFromRenderStep("AerovoltRender") end)
	Modal.Modal = false
	Blur:Destroy()
	Gui:Destroy()
end

----------------------------------------------------------------------
-- start
----------------------------------------------------------------------
SetEnabled(ArrayList, true, true)
SetEnabled(Notifs, true, true)
SetEnabled(HUDm, true, true)
-- a saved config overrides the defaults above; with no file (or no file functions) the defaults stay
if ui.Config then
	ui.ApplyConfigEnabled(ui.Config)
	ui.ApplyLayout(ui.Config)
end
ui.Notify("Aerovolt loaded" .. (ui.Config and " (config loaded)" or "") .. " - press " .. GuiSettings.Values["Menu Key"] .. " to open the menu", true)