if not game:IsLoaded() then game.Loaded:Wait() end

-- Executor and device support. A function the executor lacks falls back instead of erroring, and on a touch
-- screen the aim code measures from the middle of the screen, where the crosshair sits.
local cloneref = cloneref or function(instance) return instance end
local compat = { on = false, touch = false, setting = "Auto" }

local Drawing = Drawing or (function()
	local methods = { Remove = function() end, Destroy = function() end }
	local meta = { __index = methods, __newindex = function() end }
	compat.noDrawing = true
	return { new = function() return setmetatable({}, meta) end }
end)()

do
	local real, manager

	local function virtual()
		if manager == nil then
			local ok, service = pcall(function() return cloneref(game:GetService("VirtualInputManager")) end)
			manager = ok and service or false
		end
		return manager or nil
	end

	local function pointer()
		if compat.on then
			local camera = workspace.CurrentCamera
			if camera then return camera.ViewportSize / 2 end
		end
		return real:GetMouseLocation()
	end

	---"Auto" follows the device, "On" and "Off" force touch mode.
	function compat.mode(setting)
		compat.setting = setting
		compat.on = setting == "On" or (setting ~= "Off" and compat.touch)
	end

	---Stands in for UserInputService. Everything passes straight through except where the cursor is.
	function compat.wrap(service)
		real = service
		local ok, touch = pcall(function()
			return service.TouchEnabled and not service.KeyboardEnabled and not service.MouseEnabled
		end)
		compat.touch = ok and touch == true
		compat.mode("Auto")

		local wrapped = {}
		return setmetatable({}, {
			__index = function(_, key)
				if key == "GetMouseLocation" then return pointer end
				local value = service[key]
				if type(value) ~= "function" then return value end
				local entry = wrapped[key]
				if not entry or entry[1] ~= value then
					entry = { value, function(_, ...) return value(service, ...) end }
					wrapped[key] = entry
				end
				return entry[2]
			end,
			__newindex = function(_, key, value) service[key] = value end,
		})
	end

	local DIGITS = { [0] = "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" }
	local NAMED = {
		[0x20] = "Space", [0x10] = "LeftShift", [0xA1] = "RightShift", [0x11] = "LeftControl", [0xA3] = "RightControl",
		[0x25] = "Left", [0x26] = "Up", [0x27] = "Right", [0x28] = "Down",
	}

	---Windows virtual-key code to the key the virtual input manager takes.
	local function keyFor(code)
		local name = NAMED[code]
		if not name and code >= 0x30 and code <= 0x39 then name = DIGITS[code - 0x30] end
		if not name and code >= 0x41 and code <= 0x5A then name = string.char(code) end
		local ok, key = pcall(function() return Enum.KeyCode[name] end)
		return ok and key or nil
	end

	---Whether Roblox has the focus. Not asked on a touch screen, where there is nothing to ask.
	function compat.active()
		if compat.on or type(isrbxactive) ~= "function" then return true end
		local ok, active = pcall(isrbxactive)
		return not ok or active
	end

	---One click: the executor's own, otherwise a virtual one at the cursor (the screen centre on touch).
	function compat.click()
		if type(mouse1click) == "function" then return (pcall(mouse1click)) end
		local input = virtual()
		if not input then return false end
		local at = pointer()
		pcall(input.SendMouseButtonEvent, input, at.X, at.Y, 0, true, game, 1)
		pcall(input.SendMouseButtonEvent, input, at.X, at.Y, 0, false, game, 1)
		return true
	end

	---A click at a place on the screen, which is how the farm presses the game's own buttons.
	function compat.clickAt(x, y)
		local input = virtual()
		if not input then return false end
		pcall(input.SendMouseMoveEvent, input, x, y, game)
		pcall(input.SendMouseButtonEvent, input, x, y, 0, true, game, 1)
		task.delay(0.05, function() pcall(input.SendMouseButtonEvent, input, x, y, 0, false, game, 1) end)
		return true
	end

	---Moving the real cursor needs a mouse, so a touch screen aims by turning the camera instead.
	function compat.canMove()
		return not compat.on and type(mousemoverel) == "function"
	end

	function compat.move(x, y)
		return pcall(mousemoverel, x, y)
	end

	---Taps a key given as a Windows virtual-key code.
	function compat.keytap(code)
		if type(keytap) == "function" then return (pcall(keytap, code)) end
		if type(keypress) == "function" and type(keyrelease) == "function" then
			pcall(keypress, code)
			task.delay(0.04, function() pcall(keyrelease, code) end)
			return true
		end
		local input, key = virtual(), keyFor(code)
		if not (input and key) then return false end
		pcall(input.SendKeyEvent, input, true, key, false, game)
		task.delay(0.04, function() pcall(input.SendKeyEvent, input, false, key, false, game) end)
		return true
	end

	function compat.fps(cap)
		if type(setfpscap) == "function" then pcall(setfpscap, cap) end
	end

	-- Files live on disk when the executor can read and write them, otherwise in memory for this session.
	local memory = {}

	local function disk()
		return type(isfile) == "function" and type(readfile) == "function" and type(writefile) == "function"
	end

	function compat.isfile(path)
		if disk() then return isfile(path) end
		return memory[path] ~= nil
	end

	function compat.readfile(path)
		if disk() then return readfile(path) end
		local text = memory[path]
		if text == nil then error("missing file " .. tostring(path), 2) end
		return text
	end

	function compat.writefile(path, text)
		if disk() then return writefile(path, text) end
		memory[path] = tostring(text)
	end

	function compat.isfolder(path)
		if type(isfolder) == "function" then return isfolder(path) end
		return true
	end

	function compat.makefolder(path)
		if type(makefolder) == "function" then return makefolder(path) end
	end

	function compat.delfile(path)
		if type(delfile) == "function" and disk() then return delfile(path) end
		memory[path] = nil
	end

	function compat.listfiles(folder)
		if type(listfiles) == "function" and disk() then return listfiles(folder) end
		local list = {}
		for path in pairs(memory) do
			if string.sub(path, 1, #folder + 1) == folder .. "/" then table.insert(list, path) end
		end
		table.sort(list)
		return list
	end

	---The metatable hook and its helpers for soft aim. Without them the hook is simply not installed.
	function compat.hooks()
		local ready = type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" and type(checkcaller) == "function"
		compat.hooked = ready
		if not ready then
			return function() end, function(fn) return fn end, function() return false end, function() return "" end
		end

		local function hook(object, method, fn)
			local ok, original = pcall(hookmetamethod, object, method, fn)
			if ok then return original end
			compat.hooked = false
		end
		return hook, type(newcclosure) == "function" and newcclosure or function(fn) return fn end, checkcaller, getnamecallmethod
	end

	---One short line per capability, shown in the Interface tab.
	function compat.report()
		local fire = type(mouse1click) == "function" and "executor" or (virtual() and "virtual input" or "none")
		local saved = disk() and "saved on disk" or "memory only"
		return {
			"Screen: " .. (compat.on and "touch, aims from centre" or "keyboard and mouse"),
			"Drawing: " .. (compat.noDrawing and "missing, ESP off" or "ok"),
			"Soft aim hook: " .. (compat.hooked and "ok" or "unavailable"),
			"Auto fire: " .. fire,
			"Configs: " .. saved,
		}
	end
end

-- Services.
local playersService = cloneref(game:GetService("Players"))
local runService = cloneref(game:GetService("RunService"))
local userInputService = compat.wrap(cloneref(game:GetService("UserInputService")))
local coreGui = cloneref(game:GetService("CoreGui"))
local tweenService = cloneref(game:GetService("TweenService"))
local httpService = cloneref(game:GetService("HttpService"))
local statsService = cloneref(game:GetService("Stats"))
local virtualUser = cloneref(game:GetService("VirtualUser"))
local lightingService = cloneref(game:GetService("Lighting"))
local guiService = cloneref(game:GetService("GuiService"))

local localPlayer = playersService.LocalPlayer
local currentCamera = workspace.CurrentCamera

local INSTANCE_KEY = "__sprite_rivals"
local globalTable = (getgenv and getgenv()) or shared

-- Unload any previous copy, including ones from older versions of this script.
for _, store in ipairs({ globalTable, shared }) do
	for _, key in ipairs({ INSTANCE_KEY, "SpriteRivals" }) do
		local previous = store[key]
		if type(previous) == "table" and previous.detach then
			pcall(previous.detach)
		end
		store[key] = nil
	end
end

local function randomName(length)
	local letters = table.create(length)
	for index = 1, length do
		letters[index] = string.char(math.random(97, 122))
	end
	return table.concat(letters)
end

local RENDER_NAME = randomName(12)

-- UI.
local THEME_NAMES, THEMES, ACCENT, UI, createWatermark, keyName

do
	THEME_NAMES = { "Aqua", "Violet", "Rose", "Mint", "Amber", "Crimson", "Blaze" }
	THEMES = {
		Aqua = { accent = Color3.fromRGB(80, 220, 255), soft = Color3.fromRGB(120, 170, 255), deep = Color3.fromRGB(10, 40, 70) },
		Violet = { accent = Color3.fromRGB(185, 125, 255), soft = Color3.fromRGB(150, 150, 255), deep = Color3.fromRGB(32, 14, 62) },
		Rose = { accent = Color3.fromRGB(255, 120, 175), soft = Color3.fromRGB(255, 170, 205), deep = Color3.fromRGB(62, 14, 38) },
		Mint = { accent = Color3.fromRGB(90, 255, 175), soft = Color3.fromRGB(140, 235, 205), deep = Color3.fromRGB(10, 52, 42) },
		Amber = { accent = Color3.fromRGB(255, 192, 72), soft = Color3.fromRGB(255, 218, 145), deep = Color3.fromRGB(62, 40, 10) },
		Crimson = { accent = Color3.fromRGB(255, 82, 92), soft = Color3.fromRGB(255, 145, 145), deep = Color3.fromRGB(56, 10, 16) },
		Blaze = { accent = Color3.fromRGB(255, 122, 48), soft = Color3.fromRGB(255, 176, 112), deep = Color3.fromRGB(58, 24, 8) },
	}
	for _, theme in pairs(THEMES) do
		theme.ink = Color3.new(theme.deep.R * 0.6, theme.deep.G * 0.6, theme.deep.B * 0.6)
	end
	ACCENT = THEMES.Aqua.accent

	local WHITE = Color3.new(1, 1, 1)
	local MUTED = Color3.fromRGB(186, 208, 228)
	local DOT_GOOD, DOT_WARN, DOT_BAD = Color3.fromRGB(90, 235, 140), Color3.fromRGB(255, 190, 50), Color3.fromRGB(255, 80, 80)

	local FONT_MAIN = Enum.Font.GothamMedium
	local FONT_BOLD = Enum.Font.GothamBold
	local FONT_BRAND = Enum.Font.GothamBlack

	local WINDOW_W, WINDOW_H = 760, 470
	local RADIUS, HEADER_H, EDGE = 22, 56, 14
	local SIDE_W, TAB_H, TAB_GAP = 136, 32, 4
	local PAGE_PAD, GROUP_GAP = 8, 10
	local TITLE_H, GROUP_PAD, ROW_GAP = 30, 8, 2
	local ROW_H, SLIDER_H, BUTTON_H, LABEL_H = 28, 40, 32, 18
	local ROW_W = (WINDOW_W - (EDGE * 2 + SIDE_W + 10)) / 2 - (PAGE_PAD + GROUP_GAP / 2) - 16

	UI = {}
	UI.__index = UI
	UI.own = setmetatable({}, { __mode = "k" })

	local Window = {}
	Window.__index = Window

	local Tab = {}
	Tab.__index = Tab

	local function assign(instance, key, value)
		instance[key] = value
	end

	---Create an instance with properties and children. Parent is set last and unknown properties are skipped.
	local function create(className, properties, children)
		local instance = Instance.new(className)
		if className == "ScreenGui" then UI.own[instance] = true end
		local parent
		for key, value in pairs(properties or {}) do
			if key == "Parent" then
				parent = value
			else
				pcall(assign, instance, key, value)
			end
		end
		for _, child in ipairs(children or {}) do
			child.Parent = instance
		end
		if parent then instance.Parent = parent end
		return instance
	end

	local function corner(radius)
		return create("UICorner", { CornerRadius = UDim.new(0, radius) })
	end

	local function pill()
		return create("UICorner", { CornerRadius = UDim.new(0.5, 0) })
	end

	local function stroke(color, transparency, thickness)
		return create("UIStroke", {
			Color = color,
			Transparency = transparency or 0,
			Thickness = thickness or 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		})
	end

	local function gradient(properties)
		return create("UIGradient", properties)
	end

	---Transparency curve from { time, value } pairs.
	local function numbers(...)
		local points = {}
		for index, pair in ipairs({ ... }) do
			points[index] = NumberSequenceKeypoint.new(pair[1], pair[2])
		end
		return NumberSequence.new(points)
	end

	---Color curve from { time, color } pairs.
	local function colors(...)
		local points = {}
		for index, pair in ipairs({ ... }) do
			points[index] = ColorSequenceKeypoint.new(pair[1], pair[2])
		end
		return ColorSequence.new(points)
	end

	local function mix(first, second, amount)
		return Color3.new(
			first.R + (second.R - first.R) * amount,
			first.G + (second.G - first.G) * amount,
			first.B + (second.B - first.B) * amount
		)
	end

	---Gradients that follow the theme. A role is either a theme color name or one of these.
	local ROLES = {
		body = function(theme)
			return ColorSequence.new(mix(theme.deep, theme.soft, 0.26), theme.deep)
		end,
		rim = function(theme)
			return colors({ 0, WHITE }, { 0.3, theme.accent }, { 0.62, theme.soft }, { 1, WHITE })
		end,
		fill = function(theme)
			return ColorSequence.new(theme.soft, theme.accent)
		end,
	}

	local function resolve(theme, role)
		local make = ROLES[role]
		if make then return make(theme) end
		return theme[role]
	end

	local function textLabel(properties)
		local merged = {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = FONT_MAIN,
			TextSize = 13,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}
		for key, value in pairs(properties) do merged[key] = value end
		return create("TextLabel", merged)
	end

	---Readable name for a bind, "None" when it was cleared.
	function keyName(key)
		return key == Enum.KeyCode.Unknown and "None" or key.Name
	end

	---Shrink the text size a little when a label would not fit its space on one line.
	local function fitSize(text, width, size)
		while size > 11 and #text * size * 0.56 > width do
			size -= 1
		end
		return size
	end

	local function guiParent()
		return (gethui and gethui()) or localPlayer:WaitForChild("PlayerGui")
	end

	---Glossy bubble used as the logo. Returns the bubble and the stroke that pulses around it.
	local function logoBubble(parent, size, position, paint)
		local ring = create("Frame", {
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = parent,
		}, { pill() })
		local glow = stroke(WHITE, 0.5, 2)
		glow.Parent = ring
		paint(glow, "Color", "accent")

		local bubble = create("Frame", {
			Position = position,
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Parent = parent,
		}, {
			pill(),
			stroke(WHITE, 0.3, 1.5),
		})
		local shade = gradient({ Rotation = 50, Transparency = numbers({ 0, 0.1 }, { 1, 0.7 }) })
		shade.Parent = bubble
		paint(shade, "Color", "fill")

		create("Frame", {
			Position = UDim2.fromOffset(size * 0.2, size * 0.14),
			Size = UDim2.fromOffset(size * 0.36, size * 0.2),
			Rotation = -32,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Parent = bubble,
		}, { pill() })
		create("Frame", {
			Position = UDim2.fromOffset(size * 0.62, size * 0.66),
			Size = UDim2.fromOffset(math.max(2, size * 0.1), math.max(2, size * 0.1)),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Parent = bubble,
		}, { pill() })
		return bubble, glow
	end

	---Tween that falls back to setting the properties when animations are off.
	function Window:tween(instance, duration, goal, style)
		if duration <= 0 or not self.animate or self.destroyed then
			for key, value in pairs(goal) do instance[key] = value end
			return nil
		end
		local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		local playing = tweenService:Create(instance, info, goal)
		playing:Play()
		return playing
	end

	---Color an instance property from the active theme now and after every theme change.
	function Window:paint(instance, property, role)
		instance[property] = resolve(self.theme, role)
		table.insert(self.painted, { instance, property, role })
	end

	function Window:hover(object, onEnter, onLeave)
		object.MouseEnter:Connect(onEnter)
		object.MouseLeave:Connect(onLeave)
		object.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then task.delay(0.12, onLeave) end
		end)
	end

	---Little bubbles that rise off a control when it switches on.
	function Window:fizz(origin)
		if not self.animate or not self.fizzOn or self.destroyed or self.fizzing >= 24 then return end
		for _ = 1, 4 do
			local size = math.random(3, 6)
			local x = 0.15 + math.random() * 0.7
			local particle = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(x, 0, 0.5, 0),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.3,
				BorderSizePixel = 0,
				ZIndex = 20,
				Parent = origin,
			}, { pill(), stroke(self.theme.accent, 0.35, 1) })
			self.fizzing += 1
			local life = 0.55 + math.random() * 0.4
			self:tween(particle, life, {
				Position = UDim2.new(x + (math.random() - 0.5) * 0.3, 0, 0.5, -(16 + math.random(0, 14))),
				BackgroundTransparency = 1,
			})
			local edge = particle:FindFirstChildOfClass("UIStroke")
			if edge then self:tween(edge, life, { Transparency = 1 }) end
			task.delay(life + 0.05, function()
				self.fizzing -= 1
				particle:Destroy()
			end)
		end
	end

	---Rising carbonation behind the glass.
	function Window:buildBubbles(layer)
		local classes = {
			{ count = 6, size = { 30, 50 }, speed = { 0.016, 0.032 }, alpha = 0.93, ring = 0.72 },
			{ count = 10, size = { 14, 26 }, speed = { 0.04, 0.075 }, alpha = 0.9, ring = 0.62 },
			{ count = 12, size = { 5, 11 }, speed = { 0.08, 0.14 }, alpha = 0.82, ring = 0.5 },
		}
		for _, class in ipairs(classes) do
			for _ = 1, class.count do
				local size = math.random(class.size[1], class.size[2])
				local edge = stroke(WHITE, class.ring, 1)
				local frame = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(size, size),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = class.alpha,
					BorderSizePixel = 0,
					ZIndex = 3,
					Parent = layer,
				}, {
					pill(),
					edge,
					gradient({ Rotation = 45, Transparency = numbers({ 0, 0 }, { 1, 0.8 }) }),
				})
				self:paint(edge, "Color", "accent")
				table.insert(self.bubbles, {
					frame = frame,
					edge = edge,
					x = math.random(),
					y = math.random() * 1.16 - 0.08,
					speed = class.speed[1] + math.random() * (class.speed[2] - class.speed[1]),
					sway = 0.006 + math.random() * 0.014,
					freq = 0.8 + math.random() * 1.6,
					phase = math.random() * 6.28,
					alpha = class.alpha,
					ring = class.ring,
					shown = -1,
					rank = math.random(),
					hidden = false,
				})
			end
		end
	end

	---Show only a share of the bubbles (0 to 1). Each bubble has a fixed rank, so the same ones stay.
	function Window:setBubbles(share)
		self.bubbleShare = math.clamp(share, 0, 1)
		for _, bubble in ipairs(self.bubbles) do
			bubble.hidden = bubble.rank > self.bubbleShare
			bubble.frame.Visible = not bubble.hidden
		end
	end

	---Move the bubbles, turn the rim light and pulse the logo. Skipped while the menu is closed.
	function Window:animateFrame(dt, now)
		local pace = self.bubbleSpeed
		for _, bubble in ipairs(self.bubbles) do
			if bubble.hidden then continue end
			bubble.y -= bubble.speed * dt * pace
			if bubble.y < -0.08 then
				bubble.y = 1.08
				bubble.x = math.random()
			end
			local sway = math.sin(now * bubble.freq + bubble.phase) * bubble.sway
			bubble.frame.Position = UDim2.fromScale(bubble.x + sway, bubble.y)

			local shown = math.clamp(math.min(bubble.y + 0.08, 1.08 - bubble.y) / 0.2, 0, 1)
			if shown ~= bubble.shown and (shown < 1 or bubble.shown < 1) then
				bubble.shown = shown
				bubble.frame.BackgroundTransparency = 1 - (1 - bubble.alpha) * shown
				bubble.edge.Transparency = 1 - (1 - bubble.ring) * shown
			end
		end
		if self.rimSpin then self.rim.Rotation = (now * 22) % 360 end
		self.logoGlow.Transparency = 0.45 + 0.25 * math.sin(now * 2.4)
	end

	---Create the main window.
	---@param title string
	---@param subtitle string?
	function UI.new(title, subtitle)
		local self = setmetatable({
			tabs = {}, activeTab = nil, connections = {}, listening = false,
			animate = true, destroyed = false, theme = THEMES.Aqua, blurOn = true,
			painted = {}, refreshers = {}, bubbles = {}, fizzing = 0, notifyCount = 0,
			bubbleShare = 1, bubbleSpeed = 1, rimSpin = true, fizzOn = true, tabFade = true,
			notifyOn = true, notifyScale = 1, notifySide = "Right", locked = false, blurSize = 14,
			userScale = 1, fitOn = true,
		}, Window)

		-- A short screen, such as a phone held sideways, gets a lower window with a tighter header and tabs.
		local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
		local compact = view ~= nil and view.Y > 0 and view.Y < 520
		WINDOW_H, HEADER_H = compact and 368 or 470, compact and 46 or 56
		TAB_H, TAB_GAP = compact and 26 or 32, compact and 3 or 4
		local lift = (HEADER_H - 56) / 2
		self.height = WINDOW_H

		self.gui = create("ScreenGui", {
			Name = randomName(10),
			Enabled = true,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 20,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = guiParent(),
		})

		-- root moves and takes the menu scale, pivot takes the opening pop.
		self.root = create("Frame", {
			Active = true,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(WINDOW_W, WINDOW_H),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = self.gui,
		})
		self.scale = create("UIScale", { Scale = 1, Parent = self.root })
		self.pivot = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = self.root,
		})
		self.pop = create("UIScale", { Scale = 1, Parent = self.pivot })

		-- Soft glow around the glass.
		for _, ring in ipairs({ { 0, 4, 0.86 }, { 4, 5, 0.93 }, { 9, 6, 0.965 } }) do
			local halo = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, ring[1] * 2, 1, ring[1] * 2),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = self.pivot,
			}, { corner(RADIUS + ring[1]) })
			local edge = stroke(WHITE, ring[3], ring[2])
			edge.Parent = halo
			self:paint(edge, "Color", "accent")
		end

		self.main = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.26,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			ZIndex = 2,
			Parent = self.pivot,
		}, { corner(RADIUS) })
		local body = gradient({ Rotation = 125, Transparency = numbers({ 0, 0 }, { 1, 0.3 }), Parent = self.main })
		self:paint(body, "Color", "body")

		local rimStroke = stroke(WHITE, 0.2, 1.5)
		rimStroke.Parent = self.main
		self.rim = gradient({
			Transparency = numbers({ 0, 0.05 }, { 0.3, 0.35 }, { 0.62, 0.62 }, { 1, 0.05 }),
			Parent = rimStroke,
		})
		self:paint(self.rim, "Color", "rim")

		-- Light falling on the glass: a soft top sheen and two diagonal reflections.
		create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = self.main,
		}, {
			corner(RADIUS),
			gradient({ Rotation = 90, Transparency = numbers({ 0, 0.9 }, { 0.2, 0.96 }, { 1, 1 }) }),
		})
		create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = self.main,
		}, {
			corner(RADIUS),
			gradient({
				Rotation = 28,
				Transparency = numbers(
					{ 0, 1 }, { 0.2, 1 }, { 0.27, 0.93 }, { 0.31, 1 }, { 0.34, 0.965 }, { 0.4, 1 }, { 1, 1 }
				),
			}),
		})
		create("Frame", {
			Position = UDim2.fromOffset(RADIUS, 1),
			Size = UDim2.new(1, -RADIUS * 2, 0, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 4,
			Parent = self.main,
		}, { gradient({ Transparency = numbers({ 0, 1 }, { 0.5, 0.45 }, { 1, 1 }) }) })

		self.bubbleLayer = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = self.main,
		})
		self:buildBubbles(self.bubbleLayer)

		-- Toast notifications stack in the bottom right corner.
		self.notifyLayout = create("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
		})
		self.toastGui = create("ScreenGui", {
			Name = randomName(10),
			Enabled = true,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 21,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = guiParent(),
		})
		self.notifyHolder = create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -18, 1, -18),
			Size = UDim2.fromOffset(260, 320),
			BackgroundTransparency = 1,
			ZIndex = 50,
			Parent = self.toastGui,
		}, { self.notifyLayout })

		-- Header: logo bubble, name, page title. The whole strip drags the window.
		local header = create("Frame", {
			Size = UDim2.new(1, 0, 0, HEADER_H),
			BackgroundTransparency = 1,
			ZIndex = 6,
			Parent = self.main,
		})
		local paint = function(instance, property, role) self:paint(instance, property, role) end
		local _, glow = logoBubble(header, 32, UDim2.fromOffset(EDGE + 2, (HEADER_H - 32) / 2), paint)
		self.logoGlow = glow

		textLabel({
			Position = UDim2.fromOffset(EDGE + 44, 7 + lift),
			Size = UDim2.fromOffset(110, 26),
			Text = title,
			Font = FONT_BRAND,
			TextSize = 21,
			Parent = header,
		})
		local tag = textLabel({
			Position = UDim2.fromOffset(EDGE + 45, 30 + lift),
			Size = UDim2.fromOffset(100, 14),
			Text = subtitle or "",
			TextSize = 11,
			Parent = header,
		})
		self:paint(tag, "TextColor3", "accent")

		self.pageTitle = textLabel({
			Position = UDim2.fromOffset(EDGE + SIDE_W + 10 + PAGE_PAD, 0),
			Size = UDim2.fromOffset(200, HEADER_H),
			Text = "",
			Font = FONT_BOLD,
			TextSize = 18,
			Parent = header,
		})
		textLabel({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -(EDGE + 40), 0, 0),
			Size = UDim2.fromOffset(190, HEADER_H),
			Text = "crisp. clear. refreshing.",
			TextSize = 11,
			TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = header,
		})

		local close = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -EDGE, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = header,
		}, { pill(), stroke(WHITE, 0.78, 1) })
		for _, rotation in ipairs({ 45, -45 }) do
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(11, 2),
				Rotation = rotation,
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Parent = close,
			}, { pill() })
		end
		self:hover(close, function()
			close.BackgroundColor3 = self.theme.accent
			close.BackgroundTransparency = 0.6
		end, function()
			close.BackgroundColor3 = WHITE
			close.BackgroundTransparency = 0.88
		end)
		close.MouseButton1Click:Connect(function()
			self.gui.Enabled = false
		end)

		-- Sidebar and content.
		local bodyTop = HEADER_H + 6
		self.sidebar = create("Frame", {
			Position = UDim2.fromOffset(EDGE, bodyTop),
			Size = UDim2.new(0, SIDE_W, 1, -bodyTop - EDGE),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			ZIndex = 6,
			Parent = self.main,
		}, {
			corner(16),
			gradient({ Rotation = 90, Transparency = numbers({ 0, 0 }, { 1, 0.5 }) }),
		})
		self:paint(self.sidebar, "BackgroundColor3", "deep")
		local sideEdge = stroke(WHITE, 0.74, 1)
		sideEdge.Parent = self.sidebar
		gradient({ Rotation = 90, Transparency = numbers({ 0, 0 }, { 0.6, 0.5 }, { 1, 0.85 }), Parent = sideEdge })

		self.indicator = create("Frame", {
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, TAB_H),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = self.sidebar,
		}, { corner(11) })
		self:paint(self.indicator, "BackgroundColor3", "accent")
		local indicatorEdge = stroke(WHITE, 0.4, 1)
		indicatorEdge.Parent = self.indicator
		self:paint(indicatorEdge, "Color", "accent")
		local indicatorDot = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 11, 0.5, 0),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = self.indicator,
		}, { pill() })
		self:paint(indicatorDot, "BackgroundColor3", "accent")

		self.tabList = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 8,
			Parent = self.sidebar,
		}, {
			create("UIListLayout", { Padding = UDim.new(0, TAB_GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
			create("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),
		})

		self.content = create("Frame", {
			Position = UDim2.fromOffset(EDGE + SIDE_W + 10, bodyTop),
			Size = UDim2.new(1, -(EDGE + SIDE_W + 10 + EDGE), 1, -bodyTop - EDGE),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 6,
			Parent = self.main,
		})

		-- Dragging.
		local dragging, dragStart, startPosition
		header.InputBegan:Connect(function(input)
			if self.locked then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = input.Position
				startPosition = self.root.Position
			end
		end)
		table.insert(self.connections, userInputService.InputChanged:Connect(function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local delta = input.Position - dragStart
				self.root.Position = UDim2.new(
					startPosition.X.Scale, startPosition.X.Offset + delta.X,
					startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
				)
			end
		end))
		table.insert(self.connections, userInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end))

		table.insert(self.connections, runService.Heartbeat:Connect(function(dt)
			if self.destroyed or not self.animate or not self.gui.Enabled then return end
			self:animateFrame(dt, os.clock())
		end))

		-- The window pops open every time the menu is shown.
		self.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if self.gui.Enabled then self:popIn() end
			self:updateBlur()
		end)
		self:popIn()
		self:updateBlur()
		self:fit()

		return self
	end

	function Window:popIn()
		if not self.animate or self.destroyed then return end
		self.pop.Scale = 0.9
		self:tween(self.pop, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	end

	---Frost the world behind the glass while the menu is open.
	function Window:setBlur(state)
		self.blurOn = state and true or false
		self:updateBlur()
	end

	function Window:updateBlur()
		if self.destroyed then return end
		local wanted = self.blurOn and self.gui.Enabled
		if not self.blur then
			if not wanted then return end
			self.blur = create("BlurEffect", { Name = randomName(8), Size = 0, Parent = lightingService })
		end
		self:tween(self.blur, 0.3, { Size = wanted and self.blurSize or 0 })
	end

	function Window:setBlurSize(size)
		self.blurSize = size
		self:updateBlur()
	end

	---Glass transparency, 0 is the default look and 100 is almost clear.
	function Window:setOpacity(percent)
		self.main.BackgroundTransparency = 0.26 + math.clamp(percent, 0, 100) / 100 * 0.7
	end

	function Window:resetPosition()
		self.root.Position = UDim2.fromScale(0.5, 0.5)
	end

	---Toasts: on or off, how long they stay (seconds) and which bottom corner they use.
	function Window:setNotify(on, seconds, side)
		self.notifyOn = on and true or false
		self.notifyScale = math.clamp(seconds, 0.5, 20) / 3
		local left = side == "Left"
		self.notifySide = left and "Left" or "Right"
		self.notifyHolder.AnchorPoint = Vector2.new(left and 0 or 1, 1)
		self.notifyHolder.Position = UDim2.new(left and 0 or 1, left and 18 or -18, 1, -18)
		self.notifyLayout.HorizontalAlignment = left and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Right
	end

	---Switch tabs. The highlight glides to the new tab and the page fades in.
	function Window:selectTab(tab)
		if self.activeTab == tab then return end
		local previous = self.activeTab
		self.activeTab = tab

		if previous then
			previous.canvas.Visible = false
			previous.page.Visible = false
			previous.button.TextColor3 = MUTED
		end

		tab.page.CanvasPosition = Vector2.zero
		tab.canvas.Visible = true
		tab.page.Visible = true
		tab.button.TextColor3 = WHITE
		self.pageTitle.Text = tab.name
		self:tween(self.indicator, previous and 0.3 or 0, { Position = UDim2.fromOffset(8, tab.top) }, Enum.EasingStyle.Back)

		if previous and tab.fades and self.tabFade then
			tab.canvas.GroupTransparency = 1
			tab.canvas.Position = UDim2.fromOffset(0, 14)
			self:tween(tab.canvas, 0.28, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
		end
	end

	---Turn the bubbles and menu motion on or off.
	function Window:setAnimated(state)
		self.animate = state
		self.bubbleLayer.Visible = state
	end

	---A full theme built from one accent color.
	function UI.customTheme(accent)
		local high, low = math.max(accent.R, accent.G, accent.B), math.min(accent.R, accent.G, accent.B)
		local range = high - low
		local hue = 0
		if range > 0 then
			if high == accent.R then
				hue = ((accent.G - accent.B) / range) % 6
			elseif high == accent.G then
				hue = (accent.B - accent.R) / range + 2
			else
				hue = (accent.R - accent.G) / range + 4
			end
			hue /= 6
		end
		local saturation = high > 0 and range / high or 0

		local theme = {
			accent = accent,
			soft = Color3.fromHSV(hue, math.clamp(saturation * 0.5, 0, 1), 1),
			deep = Color3.fromHSV(hue, math.clamp(saturation * 0.9 + 0.1, 0, 1), 0.27),
		}
		theme.ink = Color3.new(theme.deep.R * 0.6, theme.deep.G * 0.6, theme.deep.B * 0.6)
		return theme
	end

	---Recolor the window with a theme table { accent, soft, deep, ink }.
	function Window:applyTheme(theme)
		self.theme = theme
		for _, entry in ipairs(self.painted) do
			entry[1][entry[2]] = resolve(theme, entry[3])
		end
		for _, refresh in ipairs(self.refreshers) do refresh() end
	end

	---Show a short toast message.
	---@param text string
	---@param duration number?
	function Window:Notify(text, duration)
		if self.destroyed or not self.notifyOn then return end

		local lines = math.max(1, math.ceil(#text / 24))
		local height = 18 + lines * 16
		local offscreen = self.notifySide == "Left" and -270 or 270
		self.notifyCount += 1
		local slot = create("Frame", {
			Size = UDim2.fromOffset(250, height),
			BackgroundTransparency = 1,
			LayoutOrder = self.notifyCount,
			Parent = self.notifyHolder,
		})
		local card = create("Frame", {
			Position = UDim2.fromOffset(offscreen, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Parent = slot,
		}, {
			corner(14),
			stroke(self.theme.accent, 0.4, 1),
			gradient({ Rotation = 115, Color = ColorSequence.new(mix(self.theme.deep, self.theme.soft, 0.2), self.theme.deep) }),
		})
		create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = self.theme.accent,
			BorderSizePixel = 0,
			Parent = card,
		}, { pill() })
		textLabel({
			Position = UDim2.fromOffset(32, 0),
			Size = UDim2.new(1, -42, 1, 0),
			Text = text,
			TextWrapped = true,
			Parent = card,
		})

		self:tween(card, 0.34, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back)
		task.delay((duration or 2.5) * self.notifyScale, function()
			if self.destroyed then return end
			local leaving = self:tween(card, 0.22, { Position = UDim2.fromOffset(offscreen, 0) })
			if leaving then leaving.Completed:Wait() end
			slot:Destroy()
		end)
	end

	---Add a tab to the sidebar.
	---@param name string
	function Window:Tab(name)
		local tab = setmetatable({ window = self, name = name, group = nil }, Tab)
		local index = #self.tabs
		tab.top = 8 + index * (TAB_H + TAB_GAP)

		tab.button = create("TextButton", {
			Size = UDim2.new(1, 0, 0, TAB_H),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = name,
			Font = FONT_MAIN,
			TextSize = 14,
			TextColor3 = MUTED,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
			LayoutOrder = index,
			Parent = self.tabList,
		}, {
			corner(11),
			create("UIPadding", { PaddingLeft = UDim.new(0, 28) }),
		})

		local fades, canvas = pcall(Instance.new, "CanvasGroup")
		if not fades then canvas = Instance.new("Frame") end
		canvas.Size = UDim2.fromScale(1, 1)
		canvas.BackgroundTransparency = 1
		canvas.BorderSizePixel = 0
		canvas.Visible = false
		canvas.Parent = self.content
		tab.canvas, tab.fades = canvas, fades

		tab.page = create("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageTransparency = 0.25,
			CanvasSize = UDim2.new(),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			VerticalScrollBarInset = Enum.ScrollBarInset.None,
			Visible = false,
			Parent = tab.canvas,
		})
		self:paint(tab.page, "ScrollBarImageColor3", "accent")

		tab.columns = {}
		for side = 0, 1 do
			local frame = create("Frame", {
				Position = UDim2.new(side * 0.5, side == 0 and PAGE_PAD or GROUP_GAP / 2, 0, PAGE_PAD),
				Size = UDim2.new(0.5, -(PAGE_PAD + GROUP_GAP / 2), 0, 0),
				BackgroundTransparency = 1,
				Parent = tab.page,
			}, {
				create("UIListLayout", { Padding = UDim.new(0, GROUP_GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			table.insert(tab.columns, { frame = frame, height = 0, count = 0 })
		end

		self:hover(tab.button, function()
			if self.activeTab ~= tab then tab.button.BackgroundTransparency = 0.92 end
		end, function()
			tab.button.BackgroundTransparency = 1
		end)
		tab.button.MouseButton1Click:Connect(function()
			self:selectTab(tab)
		end)

		table.insert(self.tabs, tab)
		if #self.tabs == 1 then
			self:selectTab(tab)
		end
		return tab
	end

	---Start a titled glass card. Everything added after it lands inside, in the shorter column.
	---@param text string?
	function Tab:Section(text)
		local window = self.window
		local first, second = self.columns[1], self.columns[2]
		local column = first.height <= second.height and first or second
		local top = text and TITLE_H or 6
		local height = top + GROUP_PAD

		local frame = create("Frame", {
			Size = UDim2.new(1, 0, 0, height),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			LayoutOrder = column.count,
			Parent = column.frame,
		}, {
			corner(15),
			gradient({ Rotation = 90, Transparency = numbers({ 0, 0 }, { 1, 0.55 }) }),
		})
		local edge = stroke(WHITE, 0.78, 1)
		edge.Parent = frame
		gradient({ Rotation = 90, Transparency = numbers({ 0, 0 }, { 0.5, 0.4 }, { 1, 0.8 }), Parent = edge })

		if text then
			local dot = create("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromOffset(14, (TITLE_H - 1) / 2),
				Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Parent = frame,
			}, { pill() })
			window:paint(dot, "BackgroundColor3", "accent")
			textLabel({
				Position = UDim2.fromOffset(28, 0),
				Size = UDim2.new(1, -36, 0, TITLE_H - 1),
				Text = text,
				Font = FONT_BOLD,
				TextSize = 14,
				Parent = frame,
			})
			local rule = create("Frame", {
				Position = UDim2.fromOffset(12, TITLE_H - 1),
				Size = UDim2.new(1, -24, 0, 1),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Parent = frame,
			}, { gradient({ Transparency = numbers({ 0, 0.35 }, { 1, 1 }) }) })
			window:paint(rule, "BackgroundColor3", "accent")
		end

		local body = create("Frame", {
			Position = UDim2.fromOffset(0, top),
			Size = UDim2.new(1, 0, 1, -top - GROUP_PAD),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = frame,
		}, {
			create("UIListLayout", { Padding = UDim.new(0, ROW_GAP), SortOrder = Enum.SortOrder.LayoutOrder }),
			create("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})

		column.height += (column.count > 0 and GROUP_GAP or 0) + height
		column.count += 1
		self.group = { frame = frame, body = body, height = height, rows = 0, column = column }
		self:resize()
		return self.group
	end

	function Tab:resize()
		local tallest = math.max(self.columns[1].height, self.columns[2].height)
		self.page.CanvasSize = UDim2.fromOffset(0, tallest + PAGE_PAD * 2)
	end

	---Add a row of the given height to the current card.
	function Tab:place(height, className, properties, children)
		local group = self.group or self:Section(nil)
		local delta = height + (group.rows > 0 and ROW_GAP or 0)
		group.rows += 1
		group.height += delta
		group.column.height += delta
		group.frame.Size = UDim2.new(1, 0, 0, group.height)
		self:resize()

		local merged = {
			Size = UDim2.new(1, 0, 0, height),
			LayoutOrder = group.rows,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = group.body,
		}
		for key, value in pairs(properties or {}) do merged[key] = value end
		return create(className or "Frame", merged, children)
	end

	---Add a toggle. Returns a handle with :set(state).
	function Tab:Toggle(text, default, callback)
		local window = self.window
		local row = self:place(ROW_H, "TextButton", { Text = "", AutoButtonColor = false }, { corner(9) })
		textLabel({
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -56, 1, 0),
			Text = text,
			TextSize = fitSize(text, ROW_W - 56, 13),
			Parent = row,
		})

		local trackEdge = stroke(WHITE, 0.7, 1)
		local track = create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(36, 18),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.84,
			BorderSizePixel = 0,
			Parent = row,
		}, { pill(), trackEdge })
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 3, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = track,
		}, {
			pill(),
			gradient({ Rotation = 45, Color = ColorSequence.new(WHITE, Color3.fromRGB(180, 208, 232)) }),
		})

		local state = default or false
		local function render(animate)
			local theme = window.theme
			local duration = animate and 0.22 or 0
			trackEdge.Color = state and theme.accent or WHITE
			window:tween(trackEdge, duration, { Transparency = state and 0.1 or 0.7 })
			window:tween(track, duration, {
				BackgroundColor3 = state and theme.accent or WHITE,
				BackgroundTransparency = state and 0.2 or 0.84,
			})
			window:tween(knob, duration, {
				Position = state and UDim2.new(1, -15, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
			}, Enum.EasingStyle.Back)
		end
		render(false)
		table.insert(window.refreshers, function() render(false) end)

		window:hover(row, function()
			row.BackgroundTransparency = 0.93
		end, function()
			row.BackgroundTransparency = 1
		end)
		row.MouseButton1Click:Connect(function()
			state = not state
			render(true)
			if state then window:fizz(track) end
			if callback then
				task.spawn(callback, state)
			end
		end)

		return {
			set = function(_, newState)
				state = newState and true or false
				render(true)
			end,
		}
	end

	---Add a slider. Returns a handle with :set(value).
	function Tab:Slider(text, minimum, maximum, default, callback)
		local window = self.window
		local row = self:place(SLIDER_H, "Frame")
		textLabel({
			Position = UDim2.fromOffset(8, 2),
			Size = UDim2.new(1, -64, 0, 18),
			Text = text,
			TextSize = fitSize(text, ROW_W - 64, 13),
			Parent = row,
		})
		local valueLabel = textLabel({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 2),
			Size = UDim2.fromOffset(48, 18),
			Font = FONT_BOLD,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = row,
		})
		window:paint(valueLabel, "TextColor3", "accent")

		local bar = create("Frame", {
			Position = UDim2.fromOffset(8, 26),
			Size = UDim2.new(1, -16, 0, 6),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = row,
		}, { pill() })
		local fill = create("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = bar,
		}, { pill() })
		local fillColor = gradient({ Parent = fill })
		window:paint(fillColor, "Color", "fill")
		local knobEdge = stroke(WHITE, 0.1, 2)
		local knob = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = fill,
		}, { pill(), knobEdge })
		window:paint(knobEdge, "Color", "accent")

		local value = default or minimum
		local function setValue(newValue)
			value = math.clamp(math.floor(newValue + 0.5), minimum, maximum)
			fill.Size = UDim2.fromScale((value - minimum) / math.max(maximum - minimum, 1), 1)
			valueLabel.Text = tostring(value)
			if callback then
				task.spawn(callback, value)
			end
		end
		setValue(value)

		local hit = create("TextButton", {
			Position = UDim2.fromOffset(0, 18),
			Size = UDim2.new(1, 0, 1, -18),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = row,
		})

		local sliding, hovering = false, false
		local function grow()
			local size = (sliding and 18) or (hovering and 16) or 14
			window:tween(knob, 0.12, { Size = UDim2.fromOffset(size, size) })
		end
		window:hover(hit, function()
			hovering = true
			grow()
		end, function()
			hovering = false
			grow()
		end)

		local function update(input)
			local width = bar.AbsoluteSize.X
			if width <= 0 then return end
			local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / width, 0, 1)
			setValue(minimum + (maximum - minimum) * alpha)
		end
		hit.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				sliding = true
				self.page.ScrollingEnabled = false
				grow()
				update(input)
			end
		end)
		table.insert(window.connections, userInputService.InputChanged:Connect(function(input)
			if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				update(input)
			end
		end))
		table.insert(window.connections, userInputService.InputEnded:Connect(function(input)
			if sliding and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
				sliding = false
				self.page.ScrollingEnabled = true
				grow()
			end
		end))

		return {
			set = function(_, newValue)
				setValue(newValue)
			end,
		}
	end

	---Left side label of a row whose control sits on the right.
	local function rowLabel(row, text, controlWidth)
		textLabel({
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -controlWidth - 18, 1, 0),
			Text = text,
			TextSize = fitSize(text, ROW_W - controlWidth - 18, 13),
			Parent = row,
		})
	end

	---Glass capsule that holds a row's control on the right.
	local function capsule(row, className, width, properties)
		local edge = stroke(WHITE, 0.74, 1)
		local merged = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(width, 22),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			Parent = row,
		}
		for key, value in pairs(properties or {}) do merged[key] = value end
		return create(className, merged, { pill(), edge }), edge
	end

	---Add a dropdown. The arrows step through the options. Returns a handle with :set(option).
	function Tab:Dropdown(text, options, default, callback)
		local window = self.window
		local row = self:place(ROW_H, "Frame")
		rowLabel(row, text, 136)

		local index = table.find(options, default) or 1
		local box = capsule(row, "Frame", 136)
		local valueLabel = create("TextButton", {
			Position = UDim2.fromOffset(18, 0),
			Size = UDim2.new(1, -36, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = options[index],
			Font = FONT_BOLD,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutoButtonColor = false,
			Parent = box,
		})
		window:paint(valueLabel, "TextColor3", "accent")

		local function step(direction)
			index = (index - 1 + direction) % #options + 1
			valueLabel.Text = options[index]
			if callback then
				task.spawn(callback, options[index])
			end
		end

		valueLabel.MouseButton1Click:Connect(function()
			step(1)
		end)
		valueLabel.MouseButton2Click:Connect(function()
			step(-1)
		end)

		for side = 0, 1 do
			local arrow = create("TextButton", {
				AnchorPoint = Vector2.new(side, 0),
				Position = UDim2.fromScale(side, 0),
				Size = UDim2.new(0, 18, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = side == 0 and "<" or ">",
				Font = FONT_BOLD,
				TextSize = 12,
				TextColor3 = MUTED,
				AutoButtonColor = false,
				Parent = box,
			})
			window:hover(arrow, function()
				arrow.TextColor3 = window.theme.accent
			end, function()
				arrow.TextColor3 = MUTED
			end)
			arrow.MouseButton1Click:Connect(function()
				step(side == 0 and -1 or 1)
			end)
		end

		return {
			set = function(_, option)
				local found = table.find(options, option)
				if not found then return end
				index = found
				valueLabel.Text = options[index]
			end,
		}
	end

	---Add a keybind picker. Click, then press a key (Escape keeps the current one).
	---Returns a handle with :set(key).
	function Tab:Bind(text, default, callback)
		local window = self.window
		local row = self:place(ROW_H, "Frame")
		rowLabel(row, text, 100)

		local current = default
		local listening = false
		local chip, chipEdge = capsule(row, "TextButton", 100, {
			Text = keyName(current),
			Font = FONT_BOLD,
			TextSize = 12,
			AutoButtonColor = false,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		window:paint(chip, "TextColor3", "accent")

		local function look(lit)
			chipEdge.Color = lit and window.theme.accent or WHITE
			chipEdge.Transparency = lit and 0.15 or 0.74
		end
		window:hover(chip, function()
			look(true)
		end, function()
			if not listening then look(false) end
		end)
		chip.MouseButton1Click:Connect(function()
			if compat.on then
				window:Notify("Binds need a keyboard, use the quick buttons", 3)
				return
			end
			listening = true
			window.listening = true
			chip.Text = "press key"
			look(true)
		end)

		table.insert(window.connections, userInputService.InputBegan:Connect(function(input)
			if not listening then return end

			local pick
			if input.KeyCode == Enum.KeyCode.Escape then
				pick = current
			elseif input.KeyCode == Enum.KeyCode.Backspace then
				pick = Enum.KeyCode.Unknown
			elseif input.KeyCode ~= Enum.KeyCode.Unknown then
				pick = input.KeyCode
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
				pick = input.UserInputType
			end
			if not pick then return end

			listening = false
			current = pick
			chip.Text = keyName(pick)
			look(false)
			if callback then callback(pick) end

			-- Clear after other handlers see this press so it doesn't trigger the new bind.
			task.defer(function() window.listening = false end)
		end))

		table.insert(window.refreshers, function() look(listening) end)

		return {
			set = function(_, key)
				current = key
				chip.Text = keyName(key)
			end,
		}
	end

	---Add a text box. Returns a handle with :get() and :set(text).
	function Tab:Input(text, default, callback, placeholder)
		local window = self.window
		local row = self:place(ROW_H, "Frame")
		rowLabel(row, text, 136)

		local box, boxEdge = capsule(row, "TextBox", 136, {
			Text = default or "",
			PlaceholderText = placeholder or "name",
			PlaceholderColor3 = MUTED,
			ClearTextOnFocus = false,
			Font = FONT_MAIN,
			TextSize = 12,
			TextColor3 = WHITE,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = box })

		box.Focused:Connect(function()
			boxEdge.Color = window.theme.accent
			boxEdge.Transparency = 0.15
		end)
		box.FocusLost:Connect(function()
			boxEdge.Color = WHITE
			boxEdge.Transparency = 0.74
			if callback then
				task.spawn(callback, box.Text)
			end
		end)

		return {
			get = function()
				return box.Text
			end,
			set = function(_, newText)
				box.Text = newText
			end,
		}
	end

	---Add a button.
	function Tab:Button(text, callback)
		local window = self.window
		local row = self:place(BUTTON_H, "Frame")
		local edge = stroke(WHITE, 0.74, 1)
		local button = create("TextButton", {
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.new(1, 0, 1, -4),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			Text = text,
			Font = FONT_BOLD,
			TextSize = 13,
			TextColor3 = WHITE,
			AutoButtonColor = false,
			Parent = row,
		}, {
			corner(11),
			edge,
			gradient({ Rotation = 90, Transparency = numbers({ 0, 0 }, { 1, 0.55 }) }),
		})

		local hovering = false
		local function rest()
			button.BackgroundColor3 = hovering and window.theme.accent or WHITE
			button.BackgroundTransparency = hovering and 0.8 or 0.88
			button.TextColor3 = WHITE
			edge.Color = hovering and window.theme.accent or WHITE
			edge.Transparency = hovering and 0.2 or 0.74
		end
		window:hover(button, function()
			hovering = true
			rest()
		end, function()
			hovering = false
			rest()
		end)
		button.MouseButton1Down:Connect(function()
			button.BackgroundColor3 = window.theme.accent
			button.BackgroundTransparency = 0.15
			button.TextColor3 = window.theme.ink
		end)
		button.MouseButton1Up:Connect(rest)
		button.MouseButton1Click:Connect(function()
			if callback then
				task.spawn(callback)
			end
		end)
		table.insert(window.refreshers, rest)
	end

	---Add a line of small text. Returns the TextLabel so the script can change .Text.
	---@param text string
	---@param lines number?
	function Tab:Label(text, lines)
		lines = math.max(lines or 1, math.ceil(#text * 12 * 0.56 / (ROW_W - 16)))
		local row = self:place(lines == 1 and LABEL_H or 6 + lines * 14, "Frame")
		return textLabel({
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -16, 1, 0),
			Text = text,
			TextSize = 12,
			TextColor3 = MUTED,
			TextWrapped = lines > 1,
			TextYAlignment = lines > 1 and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
			Parent = row,
		})
	end

	---Menu scale in percent. With fit on, the window also shrinks to stay inside a small screen.
	function Window:setScale(percent, fit)
		self.userScale, self.fitOn = percent / 100, fit ~= false
		self:fit()
	end

	function Window:fit()
		local factor = 1
		local camera = workspace.CurrentCamera
		if self.fitOn and camera then
			local view = camera.ViewportSize
			if view.X > 0 and view.Y > 0 then
				factor = math.clamp(math.min((view.X - 16) / WINDOW_W, (view.Y - 16) / self.height), 0.4, 1)
			end
		end
		self.scale.Scale = self.userScale * factor
	end

	---Round menu button and quick buttons for touch screens. They have their own gui, so they stay up while the
	---menu is closed. An item is { text, visible = fn, active = fn, press = fn, release = fn }.
	function Window:Dock(items)
		local dock = { window = self, entries = {}, size = 44, gap = 6, wide = 50 }
		self.dock = dock

		dock.gui = create("ScreenGui", {
			Name = randomName(10),
			Enabled = false,
			ResetOnSpawn = false,
			IgnoreGuiInset = true,
			DisplayOrder = 22,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			Parent = guiParent(),
		})
		dock.scale = create("UIScale", { Scale = 1 })
		dock.root = create("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -14, 0, 74),
			Size = UDim2.fromOffset(dock.size, dock.size),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = dock.gui,
		}, { dock.scale })

		local launcher = create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromOffset(dock.size, dock.size),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 5,
			Parent = dock.root,
		})
		logoBubble(launcher, dock.size, UDim2.fromOffset(0, 0), function(instance, property, role)
			self:paint(instance, property, role)
		end)
		for line = -1, 1 do
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, line * 6),
				Size = UDim2.fromOffset(16, 2),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = launcher,
			}, { pill() })
		end

		-- A tap opens or closes the menu, a drag moves the buttons.
		local drag, origin, start, moved
		launcher.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				drag, origin, start, moved = input, input.Position, dock.root.Position, false
			end
		end)
		table.insert(self.connections, userInputService.InputChanged:Connect(function(input)
			if not drag then return end
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			local delta = input.Position - origin
			if delta.Magnitude > 10 then moved = true end
			if moved then
				dock.root.Position = UDim2.new(start.X.Scale, start.X.Offset + delta.X, start.Y.Scale, start.Y.Offset + delta.Y)
			end
		end))
		table.insert(self.connections, userInputService.InputEnded:Connect(function(input)
			if drag and input == drag then
				drag = nil
				if not moved then self.gui.Enabled = not self.gui.Enabled end
			end
		end))

		for _, item in ipairs(items) do
			local edge = stroke(WHITE, 0.4, 1)
			local button = create("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -(dock.size + dock.gap), 0, 5),
				Size = UDim2.fromOffset(dock.wide, dock.size - 10),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.4,
				BorderSizePixel = 0,
				Text = item.text,
				Font = FONT_BOLD,
				TextSize = 12,
				TextColor3 = WHITE,
				AutoButtonColor = false,
				Visible = false,
				ZIndex = 5,
				Parent = dock.root,
			}, { corner(12), edge })
			local entry = { item = item, button = button, edge = edge, visible = false }
			table.insert(dock.entries, entry)

			button.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
				entry.held = input
				if item.press then item.press() end
			end)
			table.insert(self.connections, userInputService.InputEnded:Connect(function(input)
				if entry.held and input == entry.held then
					entry.held = nil
					if item.release then item.release() end
				end
			end))
		end

		local function letGo(entry)
			if not entry.held then return end
			entry.held = nil
			if entry.item.release then entry.item.release() end
		end

		---Called every frame. Shows only the buttons that apply right now and lights the ones that are on. They step
		---aside while the menu is open, since both would sit on the same part of a small screen.
		function dock:refresh(show)
			if self.gui.Enabled ~= show then self.gui.Enabled = show end
			if not show then
				for _, entry in ipairs(self.entries) do letGo(entry) end
				return
			end

			local theme, relayout = self.window.theme, false
			local menuOpen = self.window.gui.Enabled
			for _, entry in ipairs(self.entries) do
				local visible = not menuOpen and entry.item.visible() and true or false
				if visible ~= entry.visible then
					entry.visible, relayout = visible, true
					entry.button.Visible = visible
					if not visible then letGo(entry) end
				end

				if visible then
					local active = entry.item.active() and true or false
					if active ~= entry.active or theme ~= entry.theme then
						entry.active, entry.theme = active, theme
						entry.button.BackgroundColor3 = active and theme.accent or theme.deep
						entry.button.BackgroundTransparency = active and 0.12 or 0.3
						entry.button.TextColor3 = active and theme.ink or WHITE
						entry.edge.Color = active and WHITE or theme.accent
					end
				end
			end

			if relayout then
				local x = self.size + self.gap
				for _, entry in ipairs(self.entries) do
					if entry.visible then
						entry.button.Position = UDim2.new(1, -x, 0, 5)
						x += self.wide + self.gap
					end
				end
			end
		end

		return dock
	end

	do
		-- Opening cutscene: a shaken bottle cracks, pops its cap and bursts into the logo. Every frame is worked out from the
		-- time alone, so a late or skipped frame never leaves anything behind and any moment can be drawn on its own.
		local TIMES = {
			settle = 0.52, rise = 0.55, crack1 = 1.55, crack2 = 1.95, crack3 = 2.3, cap = 2.65, boom = 3.12,
			logo = 3.95, title = 4.25, gap = 0.075, shine = 5.1, fade = 5.8, finish = 6.3,
		}
		local CX, CY = 640, 365
		local LOGO_Y, TITLE_Y, LINE_Y, TAG_Y = 296, 434, 498, 534
		local BAR = 0.085
		local WORD = { { "s", 70 }, { "p", 78 }, { "r", 58 }, { "i", 46 }, { "t", 56 }, { "e", 74 } }
		local TAGLINE = "crisp. clear. refreshing."

		local function span(t, from, to)
			if t <= from then return 0 end
			if t >= to then return 1 end
			return (t - from) / (to - from)
		end

		local function lerp(a, b, x)
			return a + (b - a) * x
		end

		local function outCubic(x)
			return 1 - (1 - x) ^ 3
		end

		local function outBack(x)
			return 1 + 2.70158 * (x - 1) ^ 3 + 1.70158 * (x - 1) ^ 2
		end

		---Small repeatable random numbers, so the burst looks the same every time.
		local function sequence(seed)
			local state = seed
			return function()
				state = (state * 16807) % 2147483647
				return state / 2147483647
			end
		end

		---Where the bottle is at time t: x, y, tilt in degrees and scale. It slides in, wobbles harder and harder, kicks back
		---when the cap goes and squeezes in just before it bursts.
		local function pose(t)
			local lift = (1 - outCubic(span(t, 0, TIMES.settle))) * 640
			local scale = 1
			local land = t - TIMES.settle
			if land > 0 then scale = 1 + 0.04 * math.exp(-land * 9) * math.cos(land * 36) end

			local length = TIMES.cap - TIMES.rise
			local u = span(t, TIMES.rise, TIMES.cap)
			local into = math.max(0, math.min(t, TIMES.cap) - TIMES.rise)
			local phase = 2 * math.pi * (7 * into + 17 * into * into / (2 * length))
			if t > TIMES.cap then phase += 2 * math.pi * 24 * (t - TIMES.cap) end

			local amp = 0
			if t >= TIMES.rise then amp = 1.5 + 14 * u ^ 1.5 + 4 * span(t, TIMES.cap, TIMES.boom) end
			local x = amp * math.sin(phase)
			local y = amp * 0.45 * math.sin(phase * 1.31 + 1.1)
			if t >= TIMES.cap then y += 18 * math.exp(-(t - TIMES.cap) * 12) end

			scale = scale * (1 + 0.03 * u) * (1 - 0.08 * span(t, TIMES.boom - 0.1, TIMES.boom))
			return CX + x, CY + lift + y, amp * 0.2 * math.sin(phase * 0.5 + 0.7), scale
		end

		---Where the top of the neck is in stage space at time t.
		local function neck(t)
			local x, y, tilt = pose(t)
			local radians = math.rad(tilt)
			return x + 212 * math.sin(radians), y - 212 * math.cos(radians)
		end

		---Fizz clock: runs faster the harder the bottle is shaken, so bubbles inside speed up with the pressure.
		local function agitation(t)
			local u = span(t, TIMES.rise, TIMES.cap)
			local clock = t + 4.2 * u ^ 2.5
			if t > TIMES.cap then clock += 5 * (t - TIMES.cap) end
			return clock
		end

		---Plays the cutscene. Pass what to use: light (fewer pieces on weak devices), touch (hint wording), track (a Sound
		---that matches the timeline) and cues ({ at, sound } sounds to start at a given second when there is no track).
		---Returns the intro; call intro.start(onDone) to run it, or intro.update(t) to draw one moment.
		function Window:Intro(options)
			options = options or {}
			local theme = self.theme
			local accent, soft, deep = theme.accent, theme.soft, theme.deep
			local light = options.light and true or false
			local rand = sequence(20261107)

			local function range(low, high)
				return low + (high - low) * rand()
			end

			local function paint(instance, property, role)
				instance[property] = resolve(theme, role)
			end

			local liquid = mix(accent, deep, 0.2)
			local foamColor = mix(accent, WHITE, 0.72)
			local capColor = mix(soft, deep, 0.4)
			local titleColor = mix(accent, WHITE, 0.62)

			local intro = {
				window = self, times = TIMES, light = light, track = options.track, cues = options.cues or {},
				playing = false, finished = false, time = 0, fitScale = 1,
			}

			local gui = create("ScreenGui", {
				Name = randomName(10),
				Enabled = true,
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = 150,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Parent = guiParent(),
			})
			intro.gui = gui

			local parts, alpha = {}, 1
			local function add(step)
				table.insert(parts, step)
			end

			---A piece that only exists between two moments.
			local function timed(frame, from, to, step)
				frame.Visible = false
				add(function(t)
					if t < from or t > to then
						if frame.Visible then frame.Visible = false end
						return
					end
					if not frame.Visible then frame.Visible = true end
					step(t)
				end)
			end

			-- Backdrop, bars, flash. These stay put while the stage shakes.
			local backdrop = create("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = gui,
			}, { gradient({ Rotation = 90, Color = ColorSequence.new(mix(deep, Color3.new(0, 0, 0), 0.35), Color3.fromRGB(2, 7, 12)) }) })

			local shades = {}
			for _, side in ipairs({ { 0, 90 }, { 1, -90 } }) do
				table.insert(shades, create("Frame", {
					AnchorPoint = Vector2.new(0, side[1]),
					Position = UDim2.fromScale(0, side[1]),
					Size = UDim2.fromScale(1, 0.34),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = gui,
				}, { gradient({ Rotation = side[2], Transparency = numbers({ 0, 0.3 }, { 1, 1 }) }) }))
			end

			local stage = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(1280, 720),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 10,
				Parent = gui,
			})
			local fit = create("UIScale", { Scale = 1, Parent = stage })

			local function layer(order, parent)
				return create("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = order,
					Parent = parent or stage,
				})
			end
			local raysLayer, glowLayer, bokehLayer = layer(1), layer(2), layer(3)
			local bottleLayer, fx = layer(5), layer(6)

			local bars = {}
			for _, side in ipairs({ 0, 1 }) do
				table.insert(bars, create("Frame", {
					AnchorPoint = Vector2.new(0, side),
					Position = UDim2.fromScale(0, side),
					Size = UDim2.fromScale(1, 0),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BorderSizePixel = 0,
					ZIndex = 30,
					Parent = gui,
				}))
			end

			local flash = create("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 40,
				Parent = gui,
			})
			local tint = create("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = accent,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 38,
				Parent = gui,
			})

			local hint = textLabel({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 1 - BAR / 2, 0),
				Size = UDim2.fromOffset(360, 24),
				Text = options.touch and "tap to skip" or "click or press space to skip",
				TextSize = 13,
				TextColor3 = MUTED,
				TextTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.None,
				ZIndex = 32,
				Parent = gui,
			})

			add(function(t)
				backdrop.BackgroundTransparency = 1 - alpha
				for _, shade in ipairs(shades) do shade.BackgroundTransparency = 1 - alpha end
				local k = outCubic(span(t, 0, 0.45)) * (1 - outCubic(span(t, TIMES.fade, TIMES.finish)))
				for _, bar in ipairs(bars) do bar.Size = UDim2.fromScale(1, BAR * k) end
				hint.TextTransparency = 1 - 0.55 * span(t, 0.9, 1.4) * (1 - span(t, TIMES.fade - 0.4, TIMES.fade))
				local tau = t - TIMES.boom
				flash.BackgroundTransparency = tau < 0 and 1 or 1 - math.exp(-tau / 0.08)
				tint.BackgroundTransparency = tau < 0 and 1 or 0.5 + 0.5 * span(tau, 0, 0.9)

				local dx, dy, punch = 0, 0, 0
				if tau >= 0 then
					local amp = 30 * math.exp(-tau / 0.22)
					dx, dy, punch = amp * math.sin(tau * 83 + 1.3), amp * math.cos(tau * 71), 0.07 * math.exp(-tau / 0.18)
				else
					local u = span(t, TIMES.cap, TIMES.boom)
					dx, dy = 3 * u * math.sin(t * 90), 3 * u * math.cos(t * 77)
				end
				stage.Position = UDim2.new(0.5, dx, 0.5, dy)
				fit.Scale = intro.fitScale * (1 + punch + 0.06 * span(t, 0.5, TIMES.boom))
			end)

			-- God rays and glow behind everything.
			local rays = {}
			local rayCount = light and 5 or 8
			for index = 1, rayCount do
				local ray = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(CX, CY),
					Size = UDim2.fromOffset(range(70, 170), 1700),
					BackgroundColor3 = accent,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 1,
					Parent = raysLayer,
				}, { gradient({ Rotation = 0, Transparency = numbers({ 0, 1 }, { 0.5, 0 }, { 1, 1 }) }) })
				rays[index] = { frame = ray, base = (index - 1) * 180 / rayCount + range(-8, 8), speed = range(-7, 7), weight = range(0.55, 1) }
			end

			local glows = {}
			for _, size in ipairs({ 1100, 900, 740, 610, 500, 410, 330, 260, 200, 150 }) do
				local spec = { size, 0.978 }
				table.insert(glows, {
					frame = create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(CX, CY),
						Size = UDim2.fromOffset(spec[1], spec[1]),
						BackgroundColor3 = accent,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Parent = glowLayer,
					}, { pill() }),
					size = spec[1], base = spec[2],
				})
			end

			add(function(t)
				local tau = t - TIMES.boom
				local level = 0.3 + 0.7 * span(t, 0.5, TIMES.boom) ^ 1.4
				if tau >= 0 then level = 0.8 + 1.3 * math.exp(-tau / 0.35) end
				local ray = 0.07 + 0.1 * span(t, 0.8, TIMES.boom)
				if tau >= 0 then ray = 0.1 + 0.4 * math.exp(-tau / 0.5) end
				local turn = tau >= 0 and 25 * (1 - math.exp(-tau * 3)) or 0
				for _, entry in ipairs(rays) do
					entry.frame.Rotation = entry.base + t * entry.speed + turn
					entry.frame.BackgroundTransparency = 1 - math.min(1, ray * entry.weight * alpha)
				end
				local pulse = 1 + 0.03 * math.sin(t * 3)
				for _, entry in ipairs(glows) do
					entry.frame.BackgroundTransparency = 1 - (1 - entry.base) * math.min(level, 2.2) * alpha
					entry.frame.Size = UDim2.fromOffset(entry.size * pulse, entry.size * pulse)
				end
			end)

			-- Drifting bubbles. They speed up when the bottle bursts.
			local drifters = {}
			for index = 1, light and 10 or 20 do
				local size = range(10, 46)
				local edge = stroke(WHITE, 0.7, 1)
				drifters[index] = {
					frame = create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(size, size),
						BackgroundColor3 = WHITE,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Parent = bokehLayer,
					}, { pill(), edge }),
					edge = edge, x = range(0, 1280), offset = range(0, 840), speed = range(22, 60),
					sway = range(8, 22), phase = range(0, 6.28), strength = range(0.1, 0.3),
				}
			end

			add(function(t)
				local tau = t - TIMES.boom
				local travel = t
				if tau >= 0 then travel += 1.1 * (1 - math.exp(-tau / 0.5)) * 2.2 end
				for _, bubble in ipairs(drifters) do
					local y = 760 - (bubble.offset + travel * bubble.speed) % 840
					bubble.frame.Position = UDim2.fromOffset(bubble.x + bubble.sway * math.sin(t * 1.3 + bubble.phase), y)
					local edge = 0.35 + 0.65 * (1 - math.min(1, alpha * (1 - span(y, 700, 760)) * span(y, -40, 60)))
					bubble.frame.BackgroundTransparency = 1 - math.min(1, bubble.strength * 0.25 * alpha) * (1 - edge * 0)
					bubble.edge.Transparency = 1 - (1 - 0.7) * (1 - edge)
				end
			end)

			-- The bottle: a plain glass bottle filled with fizz, wearing the script's own bubble logo.
			local bottle = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(CX, CY + 640),
				Size = UDim2.fromOffset(170, 440),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = bottleLayer,
			})
			local bottleScale = create("UIScale", { Scale = 1, Parent = bottle })

			local SHAPES = {
				{ 10, 128, 150, 306, 44, 2 },
				{ 25, 80, 120, 110, 52, 3 },
				{ 60, 18, 50, 80, 8, 4 },
			}
			local rims = {}
			for _, s in ipairs(SHAPES) do
				table.insert(rims, create("Frame", {
					Position = UDim2.fromOffset(s[1] - 3, s[2] - 3),
					Size = UDim2.fromOffset(s[3] + 6, s[4] + 6),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.2,
					BorderSizePixel = 0,
					ZIndex = 1,
					Parent = bottle,
				}, { corner(s[5] + 3) }))
			end
			table.insert(rims, create("Frame", {
				Position = UDim2.fromOffset(50, 5),
				Size = UDim2.fromOffset(70, 20),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = bottle,
			}, { corner(10) }))

			for _, s in ipairs(SHAPES) do
				create("Frame", {
					Position = UDim2.fromOffset(s[1], s[2]),
					Size = UDim2.fromOffset(s[3], s[4]),
					BackgroundColor3 = liquid,
					BorderSizePixel = 0,
					ZIndex = s[6],
					Parent = bottle,
				}, {
					corner(s[5]),
					create("Frame", {
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Color3.new(0, 0, 0),
						BorderSizePixel = 0,
					}, {
						corner(s[5]),
						gradient({ Rotation = 0, Transparency = numbers({ 0, 0.4 }, { 0.2, 0.82 }, { 0.5, 1 }, { 0.8, 0.82 }, { 1, 0.4 }) }),
					}),
				})
			end

			-- The shoulder's lower half is square, so no rounded edge shows through the body.
			create("Frame", {
				Position = UDim2.fromOffset(25, 134),
				Size = UDim2.fromOffset(120, 56),
				BackgroundColor3 = liquid,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = bottle,
			}, {
				create("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BorderSizePixel = 0,
				}, {
					gradient({ Rotation = 0, Transparency = numbers({ 0, 0.4 }, { 0.2, 0.82 }, { 0.5, 1 }, { 0.8, 0.82 }, { 1, 0.4 }) }),
				}),
			})

			local foam = create("Frame", {
				Position = UDim2.fromOffset(63, 80),
				Size = UDim2.fromOffset(44, 18),
				BackgroundColor3 = foamColor,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = bottle,
			}, { corner(8) })

			create("Frame", {
				Position = UDim2.fromOffset(52, 8),
				Size = UDim2.fromOffset(66, 14),
				BackgroundColor3 = mix(accent, WHITE, 0.6),
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = bottle,
			}, { corner(7) })

			local label = create("Frame", {
				Position = UDim2.fromOffset(10, 232),
				Size = UDim2.fromOffset(150, 108),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 6,
				Parent = bottle,
			}, {
				gradient({ Rotation = 90, Color = ColorSequence.new(mix(deep, soft, 0.12), mix(deep, Color3.new(0, 0, 0), 0.35)) }),
			})
			for _, y in ipairs({ 0, 103 }) do
				create("Frame", {
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.fromOffset(150, 5),
					BackgroundColor3 = accent,
					BorderSizePixel = 0,
					Parent = label,
				})
			end
			for _, y in ipairs({ 11, 94 }) do
				create("Frame", {
					Position = UDim2.fromOffset(0, y),
					Size = UDim2.fromOffset(150, 1),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.7,
					BorderSizePixel = 0,
					Parent = label,
				})
			end
			logoBubble(label, 62, UDim2.fromOffset(44, 23), paint)
			for _, dot in ipairs({ { 14, 30, 9 }, { 122, 24, 7 }, { 126, 66, 11 }, { 18, 72, 6 }, { 112, 82, 5 } }) do
				create("Frame", {
					Position = UDim2.fromOffset(dot[1], dot[2]),
					Size = UDim2.fromOffset(dot[3], dot[3]),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Parent = label,
				}, { pill(), stroke(WHITE, 0.55, 1) })
			end

			local function gloss(x, y, width, height, transparency, rotation)
				create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(x, y),
					Size = UDim2.fromOffset(width, height),
					Rotation = rotation or 0,
					BackgroundColor3 = WHITE,
					BackgroundTransparency = transparency,
					BorderSizePixel = 0,
					ZIndex = 8,
					Parent = bottle,
				}, { pill(), gradient({ Rotation = 90, Transparency = numbers({ 0, 1 }, { 0.18, 0 }, { 0.82, 0 }, { 1, 1 }) }) })
			end
			gloss(30, 255, 12, 236, 0.35)
			gloss(150, 262, 5, 200, 0.55)
			gloss(44, 120, 9, 56, 0.4, 24)

			local bubbles = {}
			for index = 1, light and 7 or 14 do
				local size = range(4, 11)
				bubbles[index] = {
					frame = create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Size = UDim2.fromOffset(size, size),
						BackgroundColor3 = WHITE,
						BackgroundTransparency = 0.6,
						BorderSizePixel = 0,
						ZIndex = 5,
						Parent = bottle,
					}, { pill() }),
					x = range(26, 144), phase = range(0, 230), speed = range(26, 62), wobble = range(2, 5),
				}
			end

			local capAttached = create("Frame", {
				Position = UDim2.fromOffset(49, -10),
				Size = UDim2.fromOffset(72, 30),
				BackgroundColor3 = capColor,
				BorderSizePixel = 0,
				ZIndex = 7,
				Parent = bottle,
			}, { corner(7), stroke(WHITE, 0.6, 1) })
			for index = 0, 7 do
				create("Frame", {
					Position = UDim2.fromOffset(8 + index * 8, 6),
					Size = UDim2.fromOffset(2, 18),
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = 0.6,
					BorderSizePixel = 0,
					Parent = capAttached,
				})
			end
			create("Frame", {
				Position = UDim2.fromOffset(6, 3),
				Size = UDim2.fromOffset(60, 3),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				Parent = capAttached,
			}, { pill() })

			-- The spray out of the neck: a fan of streams that start bright and thin out at the tip.
			local streams = {}
			for _, spec in ipairs({ { -16, 66, 7 }, { -8, 92, 9 }, { 0, 118, 15 }, { 8, 92, 9 }, { 16, 66, 7 } }) do
				if not light or spec[1] % 16 == 0 then
					local core = spec[1] == 0
					table.insert(streams, {
						angle = spec[1], length = spec[2], width = spec[3],
						frame = create("Frame", {
							AnchorPoint = Vector2.new(0.5, 0.5),
							Rotation = spec[1],
							Size = UDim2.fromOffset(spec[3], 0),
							BackgroundColor3 = core and WHITE or mix(accent, WHITE, 0.75),
							BorderSizePixel = 0,
							Visible = false,
							ZIndex = 4,
							Parent = bottle,
						}, { corner(spec[3] / 2), gradient({ Rotation = 90, Transparency = numbers({ 0, 1 }, { 0.45, 0.35 }, { 1, 0 }) }) }),
					})
				end
			end

			-- Cracks, drawn bit by bit once their moment comes.
			local CRACKS = {
				{ TIMES.crack1, { { 22, 280 }, { 48, 302 }, { 40, 328 }, { 66, 348 }, { 60, 374 } } },
				{ TIMES.crack2, { { 134, 112 }, { 118, 146 }, { 138, 172 }, { 124, 206 }, { 142, 238 } } },
				{ TIMES.crack3, { { 86, 246 }, { 72, 282 }, { 96, 312 }, { 80, 350 }, { 104, 388 }, { 92, 428 } } },
				{ TIMES.crack3 + 0.05, { { 96, 312 }, { 128, 322 }, { 148, 346 } } },
			}
			local segments = {}
			for _, crack in ipairs(CRACKS) do
				local points = crack[2]
				for index = 1, #points - 1 do
					local a, b = points[index], points[index + 1]
					local dx, dy = b[1] - a[1], b[2] - a[2]
					local common = {
						AnchorPoint = Vector2.new(0.5, 0.5),
						BorderSizePixel = 0,
						Rotation = math.deg(math.atan2(dy, dx)),
						Visible = false,
						Parent = bottle,
					}
					local halo = create("Frame", {
						AnchorPoint = common.AnchorPoint, BorderSizePixel = 0, Rotation = common.Rotation, Visible = false,
						BackgroundColor3 = accent, BackgroundTransparency = 0.6, ZIndex = 9, Parent = bottle,
					}, { pill() })
					local line = create("Frame", {
						AnchorPoint = common.AnchorPoint, BorderSizePixel = 0, Rotation = common.Rotation, Visible = false,
						BackgroundColor3 = WHITE, BackgroundTransparency = 0.05, ZIndex = 10, Parent = bottle,
					}, { pill() })
					table.insert(segments, {
						a = a, dx = dx, dy = dy, length = math.sqrt(dx * dx + dy * dy),
						at = crack[1] + (index - 1) * 0.05, halo = halo, line = line,
					})
				end
			end

			add(function(t)
				if t >= TIMES.boom then
					if bottle.Visible then bottle.Visible = false end
					return
				end
				if not bottle.Visible then bottle.Visible = true end
				local x, y, tilt, scale = pose(t)
				bottle.Position = UDim2.fromOffset(x, y)
				bottle.Rotation = tilt
				bottleScale.Scale = scale

				local pressure = span(t, TIMES.rise, TIMES.cap)
				local top = lerp(80, 22, pressure ^ 1.2)
				foam.Position = UDim2.fromOffset(63, top)
				foam.Size = UDim2.fromOffset(44, 98 - top)
				local rim = mix(WHITE, accent, pressure * 0.8)
				for _, entry in ipairs(rims) do entry.BackgroundColor3 = rim end

				local clock = agitation(t)
				for _, bubble in ipairs(bubbles) do
					local rise = (bubble.phase + clock * bubble.speed) % 230
					bubble.frame.Position = UDim2.fromOffset(bubble.x + bubble.wobble * math.sin(clock * 3 + bubble.phase), 420 - rise)
				end

				local attached = t < TIMES.cap
				if capAttached.Visible ~= attached then capAttached.Visible = attached end

				local sprayed = t >= TIMES.cap
				local grow = outCubic(span(t, TIMES.cap, TIMES.cap + 0.16))
				local swell = 1 + 0.3 * span(t, TIMES.cap, TIMES.boom)
				for index, stream in ipairs(streams) do
					if stream.frame.Visible ~= sprayed then stream.frame.Visible = sprayed end
					if sprayed then
						local length = stream.length * swell * grow * (0.86 + 0.14 * math.sin(t * 57 + index * 2.1))
						local radians = math.rad(stream.angle)
						stream.frame.Size = UDim2.fromOffset(stream.width * (0.9 + 0.1 * math.sin(t * 43 + index)), length)
						stream.frame.Position = UDim2.fromOffset(85 + math.sin(radians) * length / 2, 8 - math.cos(radians) * length / 2)
					end
				end

				for _, segment in ipairs(segments) do
					local g = span(t, segment.at, segment.at + 0.07)
					if g <= 0 then
						if segment.line.Visible then
							segment.line.Visible = false
							segment.halo.Visible = false
						end
					else
						if not segment.line.Visible then
							segment.line.Visible = true
							segment.halo.Visible = true
						end
						local mx, my = segment.a[1] + segment.dx * g / 2, segment.a[2] + segment.dy * g / 2
						local width = segment.length * g
						local heat = math.min(1, 0.35 + 0.65 * span(t, segment.at, TIMES.boom))
						segment.line.Position = UDim2.fromOffset(mx, my)
						segment.line.Size = UDim2.fromOffset(width, 2.5)
						segment.halo.Position = UDim2.fromOffset(mx, my)
						segment.halo.Size = UDim2.fromOffset(width, 3 + 7 * heat)
						segment.halo.BackgroundTransparency = 1 - 0.7 * heat
					end
				end
			end)

			-- The cap and the spray at the moment it goes.
			local capX, capY = neck(TIMES.cap)
			local capFlying = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(72, 30),
				BackgroundColor3 = capColor,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = fx,
			}, { corner(7), stroke(WHITE, 0.6, 1) })
			timed(capFlying, TIMES.cap, TIMES.cap + 0.7, function(t)
				local tau = t - TIMES.cap
				capFlying.Position = UDim2.fromOffset(capX + 70 * tau, capY - 880 * tau + 900 * tau * tau)
				capFlying.Rotation = -24 + 980 * tau
			end)

			local popRing = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(capX, capY),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = fx,
			}, { pill() })
			local popEdge = stroke(WHITE, 0.2, 5)
			popEdge.Parent = popRing
			timed(popRing, TIMES.cap, TIMES.cap + 0.26, function(t)
				local x = outCubic(span(t, TIMES.cap, TIMES.cap + 0.24))
				local size = lerp(18, 190, x)
				popRing.Size = UDim2.fromOffset(size, size)
				popEdge.Thickness = lerp(6, 1, x)
				popEdge.Transparency = lerp(0.1, 1, x)
			end)

			local puffs = light and 6 or 11
			for index = 1, puffs do
				local from = TIMES.cap + 0.02 + (index - 1) / puffs * 0.45
				local life = range(0.35, 0.6)
				local size = range(26, 56)
				local drift = range(-40, 40)
				local startX, startY = neck(from)
				local edge = stroke(WHITE, 0.5, 1)
				local puff = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = WHITE,
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = fx,
				}, { pill(), edge })
				timed(puff, from, from + life, function(t)
					local x = outCubic(span(t, from, from + life))
					puff.Position = UDim2.fromOffset(startX + drift * x, startY - 330 * x)
					local grown = size * (0.5 + 0.8 * x)
					puff.Size = UDim2.fromOffset(grown, grown)
					local gone = span(t, from + life * 0.4, from + life)
					puff.BackgroundTransparency = lerp(0.4, 1, gone)
					edge.Transparency = lerp(0.5, 1, gone)
				end)
			end

			local sprayCount = light and 10 or 20
			for index = 1, sprayCount do
				local from = TIMES.cap + 0.03 + (index - 1) / sprayCount * 0.42
				local life = range(0.5, 0.8)
				local angle = math.rad(-90 + range(-30, 30))
				local speed = range(520, 980)
				local size = range(6, 14)
				local startX, startY = neck(from)
				startX += range(-8, 8)
				local drop = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(size, size),
					BackgroundColor3 = mix(accent, WHITE, range(0.4, 0.95)),
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = fx,
				}, { pill() })
				timed(drop, from, from + life, function(t)
					local tau = t - from
					drop.Position = UDim2.fromOffset(
						startX + math.cos(angle) * speed * tau,
						startY + math.sin(angle) * speed * tau + 0.5 * 1500 * tau * tau
					)
					drop.BackgroundTransparency = lerp(0.05, 1, span(tau, life - 0.25, life))
				end)
			end

			-- The burst.
			local boom = TIMES.boom

			local disk = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(CX, CY),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				ZIndex = 1,
				Parent = fx,
			}, { pill() })
			timed(disk, boom, boom + 0.4, function(t)
				local x = outCubic(span(t, boom, boom + 0.36))
				local size = lerp(90, 1900, x)
				disk.Size = UDim2.fromOffset(size, size)
				disk.BackgroundTransparency = lerp(0.05, 1, x ^ 0.7)
			end)

			for index = 1, 3 do
				local from = boom + (index - 1) * 0.07
				local ring = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(CX, CY),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 1 + index,
					Parent = fx,
				}, { pill() })
				local edge = stroke(index == 1 and WHITE or accent, 0.1, 22)
				edge.Parent = ring
				timed(ring, from, from + 0.95, function(t)
					local x = outCubic(span(t, from, from + 0.9))
					local size = 60 + x * (index == 1 and 2100 or 1700)
					ring.Size = UDim2.fromOffset(size, size)
					edge.Thickness = lerp(24, 1, x)
					edge.Transparency = lerp(0.05, 1, x ^ 0.8)
				end)
			end

			local lineCount = light and 16 or 30
			for index = 1, lineCount do
				local angle = index / lineCount * math.pi * 2 + range(-0.08, 0.08)
				local near, far = range(70, 170), range(750, 1100)
				local life = range(0.28, 0.5)
				local from = boom + range(0, 0.04)
				local bar = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(range(110, 300), range(2, 5)),
					Rotation = math.deg(angle),
					BackgroundColor3 = index % 3 == 0 and accent or WHITE,
					BorderSizePixel = 0,
					ZIndex = 2,
					Parent = fx,
				}, { pill() })
				timed(bar, from, from + life, function(t)
					local x = outCubic(span(t, from, from + life))
					local radius = lerp(near, far, x)
					bar.Position = UDim2.fromOffset(CX + math.cos(angle) * radius, CY + math.sin(angle) * radius)
					bar.BackgroundTransparency = lerp(0.1, 1, x ^ 1.5)
				end)
			end

			for index = 1, light and 20 or 34 do
				local big = index <= 7
				local width = big and range(46, 84) or range(14, 42)
				local height = big and range(24, 46) or range(8, 22)
				local angle = range(0, math.pi * 2)
				local speed = range(380, 1250) * (big and 0.7 or 1)
				local startX, startY = range(-60, 60), range(-170, 170)
				local vx, vy = math.cos(angle) * speed, math.sin(angle) * speed - 120
				local spin, turn = range(-900, 900), range(0, 360)
				local life = range(1, 1.7)
				local edge = stroke(WHITE, 0.35, 1)
				local shard = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(width, height),
					BackgroundColor3 = mix(accent, WHITE, range(0.05, 0.7)),
					BorderSizePixel = 0,
					ZIndex = 3,
					Parent = fx,
				}, { edge, gradient({ Rotation = range(0, 180), Transparency = numbers({ 0, 0.05 }, { 0.5, 0.35 }, { 1, 0.75 }) }) })
				timed(shard, boom, boom + life, function(t)
					local tau = t - boom
					local travel = (1 - math.exp(-1.1 * tau)) / 1.1
					shard.Position = UDim2.fromOffset(CX + startX + vx * travel, CY + startY + vy * travel + 450 * tau * tau)
					shard.Rotation = turn + spin * tau
					local gone = span(tau, life - 0.4, life)
					shard.BackgroundTransparency = lerp(0.3, 1, gone)
					edge.Transparency = lerp(0.35, 1, gone)
				end)
			end

			for index = 1, light and 20 or 38 do
				local angle = range(0, math.pi * 2)
				local speed = range(250, 1100)
				local size = range(4, 13)
				local startX, startY = range(-50, 50), range(-150, 150)
				local vx, vy = math.cos(angle) * speed, math.sin(angle) * speed - 200
				local life = range(0.7, 1.4)
				local drop = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Size = UDim2.fromOffset(size, size),
					BackgroundColor3 = mix(accent, WHITE, range(0.2, 0.9)),
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = fx,
				}, { pill() })
				timed(drop, boom, boom + life, function(t)
					local tau = t - boom
					local slow = math.exp(-0.9 * tau)
					local travel = (1 - slow) / 0.9
					local ux, uy = vx * slow, vy * slow + 1100 * tau
					drop.Position = UDim2.fromOffset(CX + startX + vx * travel, CY + startY + vy * travel + 550 * tau * tau)
					drop.Rotation = math.deg(math.atan2(uy, ux))
					drop.Size = UDim2.fromOffset(size * (1 + math.min(math.sqrt(ux * ux + uy * uy) / 260, 3.5)), size)
					drop.BackgroundTransparency = lerp(0.1, 1, span(tau, life - 0.35, life))
				end)
			end

			for index = 1, light and 12 or 24 do
				local angle = range(0, math.pi * 2)
				local speed = range(120, 520)
				local size = range(12, 52)
				local life = range(0.9, 2.2)
				local startX, startY = range(-40, 40), range(-120, 120)
				local edge = stroke(WHITE, 0.35, 1.5)
				local bubble = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = WHITE,
					BorderSizePixel = 0,
					ZIndex = 4,
					Parent = fx,
				}, { pill(), edge })
				timed(bubble, boom, boom + life, function(t)
					local tau = t - boom
					local travel = (1 - math.exp(-3.2 * tau)) / 3.2
					bubble.Position = UDim2.fromOffset(
						CX + startX + math.cos(angle) * speed * travel,
						CY + startY + math.sin(angle) * speed * travel - 45 * tau
					)
					local grown = size * (0.5 + 0.5 * outCubic(span(tau, 0, 0.25))) * (1 + 0.25 * span(tau, life - 0.1, life))
					bubble.Size = UDim2.fromOffset(grown, grown)
					local gone = span(tau, life * 0.6, life)
					bubble.BackgroundTransparency = lerp(0.78, 1, gone)
					edge.Transparency = lerp(0.3, 1, gone)
				end)
			end

			-- Logo and name. A canvas group lets the whole thing fade out at the end.
			local made, logoGroup = pcall(Instance.new, "CanvasGroup")
			if not made then logoGroup = Instance.new("Frame") end
			logoGroup.Size = UDim2.fromOffset(1280, 720)
			logoGroup.BackgroundTransparency = 1
			logoGroup.BorderSizePixel = 0
			logoGroup.ZIndex = 8
			logoGroup.Visible = false
			logoGroup.Parent = stage

			local holder = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(CX, LOGO_Y),
				Size = UDim2.fromOffset(132, 132),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = 3,
				Parent = logoGroup,
			})
			local holderScale = create("UIScale", { Scale = 0, Parent = holder })
			local _, glow = logoBubble(holder, 132, UDim2.fromOffset(0, 0), paint)

			for index = 1, 2 do
				local from = TIMES.logo + (index - 1) * 0.14
				local ring = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(CX, LOGO_Y),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ZIndex = 1,
					Parent = logoGroup,
				}, { pill() })
				local edge = stroke(accent, 0.2, 3)
				edge.Parent = ring
				timed(ring, from, from + 0.85, function(t)
					local x = outCubic(span(t, from, from + 0.8))
					local size = lerp(132, 560, x)
					ring.Size = UDim2.fromOffset(size, size)
					edge.Transparency = lerp(0.2, 1, x)
					edge.Thickness = lerp(4, 1, x)
				end)
			end

			local total = 0
			for _, letter in ipairs(WORD) do total += letter[2] end
			local letters, left = {}, CX - total / 2
			for index, letter in ipairs(WORD) do
				local cell = letter[2]
				local labelText = textLabel({
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(left + cell / 2, TITLE_Y),
					Size = UDim2.fromOffset(cell, 130),
					Text = letter[1],
					Font = FONT_BRAND,
					TextSize = 104,
					TextColor3 = WHITE,
					TextTransparency = 1,
					TextStrokeColor3 = accent,
					TextStrokeTransparency = 1,
					TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.None,
					Visible = false,
					ZIndex = 4,
					Parent = logoGroup,
				})
				local scale = create("UIScale", { Scale = 1, Parent = labelText })
				local shade = gradient({
					Rotation = 20,
					Offset = Vector2.new(-1, 0),
					Color = colors({ 0, titleColor }, { 0.36, titleColor }, { 0.5, WHITE }, { 0.64, titleColor }, { 1, titleColor }),
					Parent = labelText,
				})
				letters[index] = { label = labelText, scale = scale, shade = shade, left = left, cell = cell, x = left + cell / 2, start = TIMES.title + (index - 1) * TIMES.gap }
				left += cell
			end

			local underline = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(CX, LINE_Y),
				Size = UDim2.fromOffset(0, 3),
				BackgroundColor3 = accent,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 4,
				Parent = logoGroup,
			}, { pill(), gradient({ Transparency = numbers({ 0, 1 }, { 0.2, 0 }, { 0.8, 0 }, { 1, 1 }) }) })

			local tagline = textLabel({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(CX, TAG_Y),
				Size = UDim2.fromOffset(640, 34),
				Text = TAGLINE,
				TextSize = 22,
				TextColor3 = mix(accent, WHITE, 0.5),
				TextTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextTruncate = Enum.TextTruncate.None,
				Visible = false,
				ZIndex = 4,
				Parent = logoGroup,
			})

			local sparkles = {}
			for index = 1, light and 5 or 9 do
				local angle = range(0, math.pi * 2)
				local radius = range(95, 175)
				local size = range(22, 40)
				local star = create("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(CX + math.cos(angle) * radius * 1.3, LOGO_Y + math.sin(angle) * radius * 0.9),
					Size = UDim2.fromOffset(size, size),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Visible = false,
					ZIndex = 5,
					Parent = logoGroup,
				}, {
					create("UIScale", { Scale = 0 }),
					create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(size, 3), BackgroundColor3 = WHITE, BorderSizePixel = 0,
					}, { pill() }),
					create("Frame", {
						AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
						Size = UDim2.fromOffset(3, size), BackgroundColor3 = WHITE, BorderSizePixel = 0,
					}, { pill() }),
				})
				sparkles[index] = { frame = star, scale = star:FindFirstChildOfClass("UIScale"), start = TIMES.logo + 0.12 + (index - 1) * 0.09 }
			end

			add(function(t)
				local show = t >= TIMES.logo - 0.02
				if logoGroup.Visible ~= show then logoGroup.Visible = show end
				if not show then return end

				if made then logoGroup.GroupTransparency = 1 - alpha end

				local x = span(t, TIMES.logo, TIMES.logo + 0.55)
				holderScale.Scale = x > 0 and outBack(x) or 0
				holder.Position = UDim2.fromOffset(CX, LOGO_Y - 6 * math.sin(t * 1.6))
				glow.Transparency = 0.45 + 0.25 * math.sin(t * 2.4)

				local word = total
				local sweep = span(t, TIMES.shine, TIMES.shine + 0.55)
				local reach = lerp(CX - word / 2 - 120, CX + word / 2 + 120, sweep)
				for _, letter in ipairs(letters) do
					local grow = span(t, letter.start, letter.start + 0.38)
					if grow <= 0 then
						if letter.label.Visible then letter.label.Visible = false end
					else
						if not letter.label.Visible then letter.label.Visible = true end
						letter.scale.Scale = 0.55 + 0.45 * outBack(grow)
						letter.label.Position = UDim2.fromOffset(letter.x, TITLE_Y + (1 - outCubic(grow)) * 50)
						local seen = 1 - span(t, letter.start, letter.start + 0.16)
						letter.label.TextTransparency = seen
						letter.label.TextStrokeTransparency = math.max(seen, lerp(0.1, 0.8, span(t, letter.start + 0.1, letter.start + 0.9)))
						local offset = sweep <= 0 and -1 or (sweep >= 1 and 1 or math.clamp((reach - letter.left) / letter.cell - 0.5, -1, 1))
						letter.shade.Offset = Vector2.new(offset, 0)
					end
				end

				local lineAt = TIMES.title + 0.5
				local drawn = outCubic(span(t, lineAt, lineAt + 0.4))
				if underline.Visible ~= (drawn > 0) then underline.Visible = drawn > 0 end
				underline.Size = UDim2.fromOffset(440 * drawn, 3)

				local tagAt = TIMES.title + 0.72
				local said = span(t, tagAt, tagAt + 0.35)
				if tagline.Visible ~= (said > 0) then tagline.Visible = said > 0 end
				tagline.TextTransparency = 1 - 0.9 * said
				tagline.Position = UDim2.fromOffset(CX, TAG_Y + 10 * (1 - outCubic(said)))

				for _, star in ipairs(sparkles) do
					local life = span(t, star.start, star.start + 0.55)
					local on = life > 0 and life < 1
					if star.frame.Visible ~= on then star.frame.Visible = on end
					if on then
						star.scale.Scale = math.sin(life * math.pi)
						star.frame.Rotation = 45 * life
					end
				end
			end)

			intro.parts = {
				stage = stage, fit = fit, bottle = bottle, flash = flash, backdrop = backdrop, bars = bars, hint = hint,
				logo = logoGroup, letters = letters, underline = underline, tagline = tagline, streams = streams,
				cap = capAttached, segments = segments,
			}

			---Work out the stage size from the screen.
			function intro.layout()
				local camera = workspace.CurrentCamera
				local view = camera and camera.ViewportSize
				if view and view.X > 0 and view.Y > 0 then
					intro.fitScale = math.min(view.X / 1280, view.Y / 720)
				end
			end

			---Draw the cutscene as it looks t seconds in.
			function intro.update(t)
				alpha = math.min(span(t, 0, 0.35), 1 - span(t, TIMES.fade, TIMES.finish))
				for _, step in ipairs(parts) do step(t) end
			end

			function intro.finish(reason)
				if intro.finished then return end
				intro.finished, intro.playing = true, false
				for _, name in ipairs({ "connection", "input" }) do
					if intro[name] then pcall(intro[name].Disconnect, intro[name]) end
				end
				if intro.track then
					pcall(function() intro.track:Stop() end)
					pcall(function() intro.track:Destroy() end)
				end
				for _, cue in ipairs(intro.cues) do
					pcall(function() cue.sound:Destroy() end)
				end
				pcall(function() gui:Destroy() end)
				local done = intro.onDone
				intro.onDone = nil
				if done then done(reason) end
			end

			---Stop without calling back, for when the script is unloading.
			function intro.destroy()
				intro.onDone = nil
				intro.finish("closed")
			end

			---Called every frame. The clock follows the sound when there is one, so picture and sound stay together.
			function intro.step()
				if not intro.playing then return end
				local now = os.clock()
				local t = now - intro.startedAt
				local track = intro.track
				if track then
					local ok, position, playing = pcall(function() return track.TimePosition, track.IsPlaying end)
					if ok and playing and position > 0.05 and math.abs(position - t) > 0.06 and math.abs(position - t) < 0.6 then
						intro.startedAt = now - position
						t = position
					end
				end
				intro.time = t

				local ok, problem = pcall(function()
					intro.layout()
					intro.update(t)
					for _, cue in ipairs(intro.cues) do
						if not cue.played and t >= cue.at then
							cue.played = true
							pcall(function() cue.sound:Play() end)
						end
					end
				end)
				if not ok then
					warn("sprite intro stopped: " .. tostring(problem))
					intro.finish("error")
				elseif t >= TIMES.finish then
					intro.finish("done")
				end
			end

			---Press play. onDone gets "done", "skipped", "error" or "closed".
			function intro.start(onDone)
				if intro.playing or intro.finished then return end
				intro.playing, intro.onDone = true, onDone
				intro.startedAt = os.clock()
				if intro.track then
					pcall(function()
						intro.track.TimePosition = 0
						intro.track:Play()
					end)
				end
				intro.connection = runService.Heartbeat:Connect(intro.step)
				intro.input = userInputService.InputBegan:Connect(function(input)
					local pressed = input.UserInputType == Enum.UserInputType.MouseButton1
						or input.UserInputType == Enum.UserInputType.Touch
						or input.KeyCode == Enum.KeyCode.Space
						or input.KeyCode == Enum.KeyCode.Return
						or input.KeyCode == Enum.KeyCode.Escape
					if pressed and intro.time > 0.35 then intro.finish("skipped") end
				end)
				intro.step()
			end

			intro.layout()
			intro.update(0)
			return intro
		end
	end

	-- Skin browser: a strip of tiles along the bottom of the screen, laid out like the game's own skin screen. It shows what it is
	-- given and reports clicks, the caller keeps the data.
	do
		local TILE_GAP = 10
		local GOOD = Color3.fromRGB(72, 232, 84)
		local GOLD = Color3.fromRGB(255, 208, 72)
		local STEEL = Color3.fromRGB(96, 120, 148)
		local BLACK = Color3.new(0, 0, 0)
		local KINDS = { { "Skin", "Skins" }, { "Wrap", "Wraps" }, { "Charm", "Charms" } }

		---A thick tick made of two bars.
		local function tick(parent, size, zindex)
			local holder = create("Frame", {
				Size = UDim2.fromOffset(size, size),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ZIndex = zindex,
				Parent = parent,
			})
			local outline = Color3.fromRGB(8, 40, 12)
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.32, 0.62),
				Size = UDim2.fromOffset(size * 0.42, size * 0.2),
				Rotation = 45,
				BackgroundColor3 = GOOD,
				BorderSizePixel = 0,
				ZIndex = zindex,
				Parent = holder,
			}, { corner(size * 0.1), stroke(outline, 0.1, 1.5) })
			create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.6, 0.5),
				Size = UDim2.fromOffset(size * 0.84, size * 0.2),
				Rotation = -52,
				BackgroundColor3 = GOOD,
				BorderSizePixel = 0,
				ZIndex = zindex,
				Parent = holder,
			}, { corner(size * 0.1), stroke(outline, 0.1, 1.5) })
			return holder
		end

		---Opens the browser. options: onPick(kind, name), onFavorite(kind, name, on), onWeapon(name), onOpen(), onClose(),
		---hideMenu (default true: the menu steps aside while the strip is open).
		---Give it weapons with setWeapons, tiles with setItems(kind, list) and what is picked with setPicks. A tile is
		---{ name, color, tooltip, favorite, plain, icon }.
		function Window:SkinBrowser(options)
			options = options or {}
			local window = self
			local view = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
			local compact = view.Y < 520 or view.X < 760
			local tileSize = compact and 88 or 118
			local rowH = compact and 28 or 34
			local barH = compact and 38 or 46
			local textSize = compact and 15 or 19
			local stripY = rowH + 6 + barH + 8
			local panelH = stripY + tileSize + 18
			local restY = -14

			local browser = {
				window = window, isOpen = false, kind = "Skin", weapon = nil, weapons = {}, destroyed = false, hidMenu = false,
				items = { Skin = {}, Wrap = {}, Charm = {} }, picked = {}, search = "", onlyFavorites = false,
				tiles = {}, shown = 0, tileSize = tileSize, compact = compact, listOpen = false,
			}
			window.browser = browser

			local gui = create("ScreenGui", {
				Name = randomName(10),
				Enabled = false,
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = 18,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Parent = guiParent(),
			})
			browser.gui = gui

			local panel = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, restY),
				Size = UDim2.new(1, -28, 0, panelH),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Parent = gui,
			}, { create("UISizeConstraint", { MaxSize = Vector2.new(1180, panelH) }) })
			browser.panel = panel

			local function glass(properties, radius)
				local merged = { BackgroundColor3 = BLACK, BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2 }
				for key, value in pairs(properties) do merged[key] = value end
				return merged, { corner(radius or 8) }
			end

			-- Top row: weapon, kind of item, favorites only.
			local stepperW = compact and 196 or 256
			local stepper = create("Frame", glass({
				Size = UDim2.fromOffset(stepperW, rowH),
				Parent = panel,
			}))
			local weaponButton = create("TextButton", {
				Position = UDim2.fromOffset(rowH, 0),
				Size = UDim2.new(1, -rowH * 2, 1, 0),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "No weapon",
				Font = FONT_BRAND,
				TextSize = textSize - 3,
				TextColor3 = WHITE,
				TextTruncate = Enum.TextTruncate.AtEnd,
				AutoButtonColor = false,
				ZIndex = 3,
				Parent = stepper,
			})
			local arrows = {}
			for side = 0, 1 do
				arrows[side] = create("TextButton", {
					AnchorPoint = Vector2.new(side, 0),
					Position = UDim2.fromScale(side, 0),
					Size = UDim2.fromOffset(rowH, rowH),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = side == 0 and "<" or ">",
					Font = FONT_BRAND,
					TextSize = textSize,
					TextColor3 = MUTED,
					AutoButtonColor = false,
					ZIndex = 3,
					Parent = stepper,
				})
				window:hover(arrows[side], function()
					arrows[side].TextColor3 = window.theme.accent
				end, function()
					arrows[side].TextColor3 = MUTED
				end)
			end

			local tabW = compact and 62 or 84
			local tabs = {}
			for index, pair in ipairs(KINDS) do
				local button = create("TextButton", {
					Position = UDim2.fromOffset(stepperW + 8 + (index - 1) * (tabW + 6), 0),
					Size = UDim2.fromOffset(tabW, rowH),
					BackgroundColor3 = BLACK,
					BackgroundTransparency = 0.45,
					BorderSizePixel = 0,
					Text = pair[2],
					Font = FONT_BOLD,
					TextSize = textSize - 4,
					TextColor3 = WHITE,
					AutoButtonColor = false,
					ZIndex = 2,
					Parent = panel,
				}, { corner(8) })
				tabs[pair[1]] = button
			end

			local boxSize = rowH - 4
			local favoriteBox = create("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -2, 0, rowH / 2),
				Size = UDim2.fromOffset(boxSize, boxSize),
				BackgroundColor3 = BLACK,
				BackgroundTransparency = 0.5,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 2,
				Parent = panel,
			}, { corner(6), stroke(WHITE, 0, 2.5) })
			local favoriteTick = tick(favoriteBox, boxSize, 4)
			favoriteTick.Visible = false
			local favoriteText = create("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -(boxSize + 14), 0, rowH / 2),
				Size = UDim2.fromOffset(textSize * 6, rowH),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "Favorited",
				Font = FONT_BRAND,
				TextSize = textSize + 4,
				TextColor3 = WHITE,
				TextStrokeTransparency = 0.35,
				TextStrokeColor3 = BLACK,
				TextXAlignment = Enum.TextXAlignment.Right,
				AutoButtonColor = false,
				ZIndex = 2,
				Parent = panel,
			})

			-- Second row: the red Back button and the search box.
			local barY = rowH + 6
			local backW = compact and 74 or 98
			local back = create("TextButton", {
				Position = UDim2.fromOffset(0, barY),
				Size = UDim2.fromOffset(backW, barH),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				ZIndex = 2,
				Parent = panel,
			}, {
				corner(8),
				gradient({ Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 96, 96), Color3.fromRGB(182, 20, 38)) }),
				stroke(Color3.fromRGB(110, 8, 22), 0.15, 1.5),
			})
			local backText = create("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "Back",
				Font = FONT_BRAND,
				TextSize = textSize + 4,
				TextColor3 = WHITE,
				TextStrokeTransparency = 0.4,
				TextStrokeColor3 = Color3.fromRGB(90, 0, 12),
				ZIndex = 3,
				Parent = back,
			})
			local search = create("TextBox", glass({
				Position = UDim2.fromOffset(backW + 8, barY),
				Size = UDim2.new(1, -(backW + 8), 0, barH),
				BackgroundTransparency = 0.5,
				Text = "",
				PlaceholderText = "Search by name or tooltip",
				PlaceholderColor3 = Color3.fromRGB(150, 150, 156),
				ClearTextOnFocus = false,
				Font = FONT_BRAND,
				TextSize = textSize + 2,
				TextColor3 = WHITE,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = panel,
			}))
			create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = search })

			-- The strip of tiles.
			local strip = create("ScrollingFrame", {
				Position = UDim2.fromOffset(0, stripY),
				Size = UDim2.new(1, 0, 0, tileSize + 14),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollingDirection = Enum.ScrollingDirection.X,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = WHITE,
				ScrollBarImageTransparency = 0.4,
				CanvasSize = UDim2.fromOffset(0, 0),
				ClipsDescendants = true,
				ZIndex = 2,
				Parent = panel,
			})
			local note = create("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0, tileSize / 2),
				Size = UDim2.new(1, -40, 0, 30),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Text = "",
				Font = FONT_BRAND,
				TextSize = textSize + 2,
				TextColor3 = WHITE,
				TextStrokeTransparency = 0.4,
				TextStrokeColor3 = BLACK,
				Visible = false,
				ZIndex = 3,
				Parent = strip,
			})

			-- The weapon list that drops over the strip.
			local list = create("ScrollingFrame", {
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 0, -6),
				Size = UDim2.fromOffset(stepperW, 200),
				BackgroundColor3 = Color3.fromRGB(8, 10, 14),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.fromOffset(0, 0),
				Visible = false,
				ZIndex = 20,
				Parent = panel,
			}, { corner(8), stroke(WHITE, 0.75, 1) })
			local listRows = {}

			-- Looks -------------------------------------------------------------------------------------------
			local function press(button, rest)
				window:hover(button, function() button.BackgroundTransparency = rest - 0.18 end, function() button.BackgroundTransparency = rest end)
			end
			press(favoriteBox, 0.5)
			for _, button in pairs(tabs) do press(button, 0.45) end
			window:hover(back, function() backText.TextColor3 = Color3.fromRGB(255, 226, 226) end, function() backText.TextColor3 = WHITE end)

			local function paintTabs()
				for kind, button in pairs(tabs) do
					local active = kind == browser.kind
					if active then
						button.BackgroundColor3 = window.theme.accent
						button.BackgroundTransparency = 0.12
						button.TextColor3 = window.theme.ink
					else
						button.BackgroundColor3 = BLACK
						button.BackgroundTransparency = 0.45
						button.TextColor3 = WHITE
					end
				end
			end

			local function mark(entry)
				local picked = browser.picked[browser.kind] == entry.item.name
				entry.check.Visible = picked
				entry.edge.Color = picked and WHITE or entry.color
				entry.edge.Thickness = picked and 3.5 or 2
				entry.star.Text = entry.item.favorite and "\u{2605}" or "\u{2606}"
				entry.star.TextColor3 = entry.item.favorite and GOLD or Color3.fromRGB(235, 235, 240)
				entry.star.TextTransparency = entry.item.favorite and 0 or 0.4
			end

			local function buildTile(item, index)
				local color = item.color or STEEL
				local top = mix(color, BLACK, item.plain and 0.5 or 0.8)
				local entry = { item = item, color = color }

				entry.button = create("TextButton", {
					Position = UDim2.fromOffset((index - 1) * (tileSize + TILE_GAP), 2),
					Size = UDim2.fromOffset(tileSize, tileSize),
					BackgroundColor3 = WHITE,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 3,
					Parent = strip,
				}, { corner(10), gradient({ Rotation = 90, Color = ColorSequence.new(top, color) }) })
				entry.edge = stroke(color, 0, 2)
				entry.edge.Parent = entry.button

				if type(item.icon) == "string" and item.icon ~= "" then
					create("ImageLabel", {
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromScale(0.5, 0.42),
						Size = UDim2.fromScale(0.74, 0.62),
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Image = item.icon,
						ImageTransparency = 0.12,
						ZIndex = 4,
						Parent = entry.button,
					})
				end

				create("TextLabel", {
					Position = UDim2.new(0, 4, 0.58, 0),
					Size = UDim2.new(1, -8, 0.4, -2),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = item.name,
					Font = FONT_BRAND,
					TextSize = compact and 12 or 15,
					TextScaled = true,
					TextColor3 = mix(color, WHITE, item.plain and 0.8 or 0.62),
					TextStrokeTransparency = 0.25,
					TextStrokeColor3 = BLACK,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Bottom,
					ZIndex = 5,
					Parent = entry.button,
				}, { create("UITextSizeConstraint", { MaxTextSize = compact and 13 or 16, MinTextSize = 7 }) })

				entry.star = create("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.new(1, -3, 0, 2),
					Size = UDim2.fromOffset(24, 24),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Text = "\u{2606}",
					Font = FONT_BOLD,
					TextSize = 18,
					TextColor3 = WHITE,
					TextStrokeTransparency = 0.5,
					AutoButtonColor = false,
					Visible = not item.plain,
					ZIndex = 7,
					Parent = entry.button,
				})
				entry.check = tick(entry.button, compact and 30 or 40, 8)
				entry.check.Position = UDim2.fromOffset(3, tileSize - (compact and 56 or 74))

				window:hover(entry.button, function()
					if browser.picked[browser.kind] ~= item.name then entry.edge.Thickness = 3.5 end
				end, function()
					mark(entry)
				end)
				entry.button.MouseButton1Click:Connect(function()
					browser.pick(item.name)
				end)
				entry.star.MouseButton1Click:Connect(function()
					browser.favorite(item.name)
				end)
				mark(entry)
				return entry
			end

			local function say(text)
				note.Text = text or ""
				note.Visible = text ~= nil
			end

			local function rebuild()
				for _, entry in ipairs(browser.tiles) do entry.button:Destroy() end
				table.clear(browser.tiles)

				local wanted = string.lower(browser.search)
				local count = 0
				for _, item in ipairs(browser.items[browser.kind]) do
					local text = string.lower(item.name .. " " .. (item.tooltip or ""))
					if (not browser.onlyFavorites or item.favorite) and (wanted == "" or string.find(text, wanted, 1, true)) then
						count += 1
						browser.tiles[count] = buildTile(item, count)
					end
				end
				browser.shown = count
				strip.CanvasSize = UDim2.fromOffset(math.max(0, count * (tileSize + TILE_GAP) - TILE_GAP), 0)
				strip.CanvasPosition = Vector2.new(0, 0)

				if count > 0 then
					say(nil)
				elseif #browser.items[browser.kind] == 0 then
					say(browser.weapon and "Nothing to show yet" or "Pick a weapon first")
				elseif browser.onlyFavorites and wanted == "" then
					say("No favorites yet. Tap the star on a tile.")
				else
					say("Nothing matches")
				end
			end

			-- Calls ----------------------------------------------------------------------------------------------
			---The names on show, in order.
			function browser.names()
				local names = {}
				for index, entry in ipairs(browser.tiles) do names[index] = entry.item.name end
				return names
			end

			---Sets the tiles for one kind: "Skin", "Wrap" or "Charm".
			function browser.setItems(kind, items)
				browser.items[kind] = items or {}
				if kind == browser.kind then rebuild() end
			end

			---What is picked now: { Skin = name, Wrap = name, Charm = name }. Only the marks change.
			function browser.setPicks(picks)
				browser.picked = picks or {}
				for _, entry in ipairs(browser.tiles) do mark(entry) end
			end

			function browser.selectKind(kind)
				if not tabs[kind] or kind == browser.kind then return end
				browser.kind = kind
				paintTabs()
				rebuild()
			end

			function browser.setSearch(text)
				search.Text = text or ""
			end

			function browser.setFavoritesOnly(on)
				browser.onlyFavorites = on and true or false
				favoriteTick.Visible = browser.onlyFavorites
				rebuild()
			end

			function browser.pick(name)
				browser.picked[browser.kind] = name
				for _, entry in ipairs(browser.tiles) do mark(entry) end
				if options.onPick then task.spawn(options.onPick, browser.kind, name) end
			end

			function browser.favorite(name)
				for _, item in ipairs(browser.items[browser.kind]) do
					if item.name == name then
						item.favorite = not item.favorite
						if options.onFavorite then task.spawn(options.onFavorite, browser.kind, name, item.favorite) end
						if browser.onlyFavorites and not item.favorite then
							rebuild()
						else
							for _, entry in ipairs(browser.tiles) do mark(entry) end
						end
						return item.favorite
					end
				end
				return nil
			end

			local function closeList()
				browser.listOpen = false
				list.Visible = false
			end

			function browser.setWeapon(name)
				browser.weapon = name
				weaponButton.Text = name or "No weapon"
			end

			function browser.chooseWeapon(name)
				closeList()
				if name == browser.weapon or not table.find(browser.weapons, name) then return end
				browser.setWeapon(name)
				if options.onWeapon then task.spawn(options.onWeapon, name) end
			end

			function browser.stepWeapon(direction)
				local count = #browser.weapons
				if count == 0 then return end
				local at = table.find(browser.weapons, browser.weapon) or 0
				browser.chooseWeapon(browser.weapons[(at - 1 + direction) % count + 1])
			end

			function browser.setWeapons(names, current)
				browser.weapons = names or {}
				for _, row in ipairs(listRows) do row:Destroy() end
				table.clear(listRows)
				for index, name in ipairs(browser.weapons) do
					local row = create("TextButton", {
						Position = UDim2.fromOffset(4, 4 + (index - 1) * 30),
						Size = UDim2.new(1, -12, 0, 28),
						BackgroundColor3 = WHITE,
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						Text = name,
						Font = FONT_BOLD,
						TextSize = 14,
						TextColor3 = WHITE,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						AutoButtonColor = false,
						ZIndex = 21,
						Parent = list,
					}, { create("UIPadding", { PaddingLeft = UDim.new(0, 10) }), corner(6) })
					window:hover(row, function()
						row.BackgroundTransparency = 0.85
					end, function()
						row.BackgroundTransparency = 1
					end)
					row.MouseButton1Click:Connect(function()
						browser.chooseWeapon(name)
					end)
					listRows[index] = row
				end
				local room = math.max(120, view.Y - panelH - 70)
				list.Size = UDim2.fromOffset(stepperW, math.min(#browser.weapons * 30 + 8, room))
				list.CanvasSize = UDim2.fromOffset(0, #browser.weapons * 30 + 8)
				browser.setWeapon(current or browser.weapons[1])
			end

			function browser.open()
				if browser.destroyed or browser.isOpen then return end
				browser.isOpen = true
				if options.hideMenu ~= false and window.gui.Enabled then
					window.gui.Enabled = false
					browser.hidMenu = true
				end
				gui.Enabled = true
				panel.Position = UDim2.new(0.5, 0, 1, panelH + 24)
				window:tween(panel, 0.3, { Position = UDim2.new(0.5, 0, 1, restY) })
				if options.onOpen then task.spawn(options.onOpen) end
			end

			function browser.close()
				if browser.destroyed or not browser.isOpen then return end
				browser.isOpen = false
				closeList()
				if browser.hidMenu then
					window.gui.Enabled = true
					browser.hidMenu = false
				end
				window:tween(panel, 0.22, { Position = UDim2.new(0.5, 0, 1, panelH + 24) })
				task.delay(0.25, function()
					if not browser.isOpen and not browser.destroyed then gui.Enabled = false end
				end)
				if options.onClose then task.spawn(options.onClose) end
			end

			function browser.toggle()
				if browser.isOpen then browser.close() else browser.open() end
			end

			function browser.destroy()
				if browser.destroyed then return end
				browser.destroyed, browser.isOpen, browser.listOpen = true, false, false
				if browser.hidMenu and not window.destroyed then window.gui.Enabled = true end
				browser.hidMenu = false
				gui:Destroy()
				if window.browser == browser then window.browser = nil end
			end

			-- Clicks ---------------------------------------------------------------------------------------------
			back.MouseButton1Click:Connect(browser.close)
			arrows[0].MouseButton1Click:Connect(function() browser.stepWeapon(-1) end)
			arrows[1].MouseButton1Click:Connect(function() browser.stepWeapon(1) end)
			weaponButton.MouseButton1Click:Connect(function()
				if #browser.weapons == 0 then return end
				browser.listOpen = not browser.listOpen
				list.Visible = browser.listOpen
			end)
			for kind, button in pairs(tabs) do
				button.MouseButton1Click:Connect(function() browser.selectKind(kind) end)
			end
			favoriteBox.MouseButton1Click:Connect(function() browser.setFavoritesOnly(not browser.onlyFavorites) end)
			favoriteText.MouseButton1Click:Connect(function() browser.setFavoritesOnly(not browser.onlyFavorites) end)
			search:GetPropertyChangedSignal("Text"):Connect(function()
				local text = string.gsub(string.gsub(search.Text, "^%s+", ""), "%s+$", "")
				if text == browser.search then return end
				browser.search = text
				rebuild()
			end)

			paintTabs()
			table.insert(window.refreshers, paintTabs)
			rebuild()
			return browser
		end

		UI.create, UI.tick = create, tick
	end

	---Destroy the window.
	function Window:destroy()
		self.destroyed = true
		if self.browser then self.browser.destroy() end
		if self.blur then self.blur:Destroy() end
		for _, connection in ipairs(self.connections) do
			connection:Disconnect()
		end
		self.gui:Destroy()
		self.toastGui:Destroy()
		if self.dock then self.dock.gui:Destroy() end
	end

	---Glass pill at the top center of the screen. It has no switch, saved settings never touch it and it rebuilds itself
	---if anything removes or hides it, only unloading the script takes it away.
	function createWatermark()
		local mark = { theme = THEMES.Aqua, dead = false, checkAt = 0 }
		local WIDTH, HEIGHT, TOP = 262, 34, 12

		local function build()
			mark.painted = {}
			local function paint(instance, property, role)
				instance[property] = resolve(mark.theme, role)
				table.insert(mark.painted, { instance, property, role })
			end

			mark.gui = create("ScreenGui", {
				Name = randomName(11),
				Enabled = true,
				ResetOnSpawn = false,
				IgnoreGuiInset = true,
				DisplayOrder = 100,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
				Parent = guiParent(),
			})

			local halo = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, TOP),
				Size = UDim2.fromOffset(WIDTH, HEIGHT),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Parent = mark.gui,
			}, { pill() })
			local haloEdge = stroke(WHITE, 0.88, 5)
			haloEdge.Parent = halo
			paint(haloEdge, "Color", "accent")

			mark.bar = create("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, TOP),
				Size = UDim2.fromOffset(WIDTH, HEIGHT),
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Visible = true,
				ZIndex = 2,
				Parent = mark.gui,
			}, { pill() })
			mark.size, mark.position = mark.bar.Size, mark.bar.Position
			local bodyGradient = gradient({ Rotation = 0, Transparency = numbers({ 0, 0 }, { 1, 0.28 }), Parent = mark.bar })
			paint(bodyGradient, "Color", "body")

			local rimEdge = stroke(WHITE, 0.15, 1.25)
			rimEdge.Parent = mark.bar
			mark.rim = gradient({
				Transparency = numbers({ 0, 0.05 }, { 0.3, 0.35 }, { 0.62, 0.62 }, { 1, 0.05 }),
				Parent = rimEdge,
			})
			paint(mark.rim, "Color", "rim")

			create("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Parent = mark.bar,
			}, { pill(), gradient({ Rotation = 90, Transparency = numbers({ 0, 0.8 }, { 0.5, 0.94 }, { 1, 1 }) }) })

			mark.sweep = gradient({
				Rotation = 20,
				Offset = Vector2.new(-1.3, 0),
				Transparency = numbers({ 0, 1 }, { 0.4, 1 }, { 0.5, 0.8 }, { 0.6, 1 }, { 1, 1 }),
			})
			create("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				Parent = mark.bar,
			}, { pill(), mark.sweep })

			local _, glow = logoBubble(mark.bar, 22, UDim2.fromOffset(6, 6), paint)
			mark.glow = glow

			textLabel({
				Position = UDim2.fromOffset(36, 0),
				Size = UDim2.fromOffset(54, HEIGHT),
				Text = "sprite",
				Font = FONT_BRAND,
				TextSize = 15,
				Parent = mark.bar,
			})
			for _, x in ipairs({ 96, 168 }) do
				create("Frame", {
					Position = UDim2.fromOffset(x, 9),
					Size = UDim2.fromOffset(1, HEIGHT - 18),
					BackgroundColor3 = WHITE,
					BackgroundTransparency = 0.8,
					BorderSizePixel = 0,
					Parent = mark.bar,
				})
			end

			local function readout(x, unit)
				local value = textLabel({
					Position = UDim2.fromOffset(x, 0),
					Size = UDim2.fromOffset(32, HEIGHT),
					Font = FONT_BOLD,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Right,
					Text = "0",
					Parent = mark.bar,
				})
				textLabel({
					Position = UDim2.fromOffset(x + 36, 0),
					Size = UDim2.fromOffset(24, HEIGHT),
					TextSize = 11,
					TextColor3 = MUTED,
					Text = unit,
					Parent = mark.bar,
				})
				return value
			end
			mark.fps = readout(102, "fps")
			mark.ping = readout(190, "ms")

			mark.pulseGlow = stroke(DOT_GOOD, 0.6, 3)
			mark.pulse = create("Frame", {
				Position = UDim2.fromOffset(177, 13),
				Size = UDim2.fromOffset(8, 8),
				BackgroundColor3 = DOT_GOOD,
				BorderSizePixel = 0,
				Parent = mark.bar,
			}, { pill(), mark.pulseGlow })
			mark.parts = { mark.gui, mark.bar, halo, mark.fps, mark.ping, mark.pulse }
		end

		---Show fps and ping. The dot goes amber, then red, as the ping climbs.
		function mark.set(fps, ping)
			if mark.dead then return end
			local fpsText, pingText = tostring(fps), tostring(ping)
			if mark.fps.Text ~= fpsText then mark.fps.Text = fpsText end
			if mark.ping.Text ~= pingText then
				mark.ping.Text = pingText
				local color = ping <= 80 and DOT_GOOD or (ping <= 150 and DOT_WARN or DOT_BAD)
				mark.pulse.BackgroundColor3 = color
				mark.pulseGlow.Color = color
			end
		end

		---Turn the rim light and sweep a glint across the glass.
		function mark.step(now)
			if mark.dead then return end
			mark.rim.Rotation = (now * 40) % 360
			mark.sweep.Offset = Vector2.new((now * 0.35) % 2.6 - 1.3, 0)
			mark.glow.Transparency = 0.45 + 0.25 * math.sin(now * 2.4)
		end

		function mark.applyTheme(theme)
			mark.theme = theme
			for _, entry in ipairs(mark.painted) do
				entry[1][entry[2]] = resolve(theme, entry[3])
			end
		end

		---Called every frame, checks twice a second that everything is still there and rebuilds when it is not.
		function mark.ensure(now)
			if mark.dead or now < mark.checkAt then return end
			mark.checkAt = now + 0.5

			local ok, healthy = pcall(function()
				if not mark.gui.Parent or mark.gui.Enabled ~= true or mark.bar.Visible ~= true then return false end
				if mark.bar.BackgroundTransparency > 0.5 or mark.bar.Parent ~= mark.gui then return false end
				if mark.bar.Size ~= mark.size or mark.bar.Position ~= mark.position then return false end
				for _, part in ipairs(mark.parts) do
					if part ~= mark.gui and not part:IsDescendantOf(mark.gui) then return false end
				end
				return true
			end)
			if ok and healthy then return end

			local fps, ping = mark.fps and mark.fps.Text, mark.ping and mark.ping.Text
			pcall(function() mark.gui:Destroy() end)
			build()
			if fps then mark.fps.Text = fps end
			if ping then mark.ping.Text = ping end
		end

		function mark.destroy()
			mark.dead = true
			pcall(function() mark.gui:Destroy() end)
		end

		build()
		return mark
	end
end

-- Script state.
local Config = {
	espBox = false, espName = false, espHealth = false, espDistance = false,
	espTracer = false, espSkeleton = false, espHeadDot = false, espChams = false,
	espMaxDist = 2000, teamCheck = true,
	espBoxStyle = "Full", espVisColors = true, espArrows = false, espArrowRadius = 140,
	espHealthText = false, espTracerOrigin = "Bottom",
	espEnabled = true, espPalette = "Classic", espLookLine = false, chamsOpacity = 50,
	espBoxFill = false, espFillOpacity = 25, espThickness = 1, espTextSize = 13, espWeapon = false,
	espColorMode = "Palette", espVisibleOnly = false, espHpFilter = 0, espTargetHighlight = false,
	espNameMode = "Display", espHeadDotSize = 100, espLookLength = 8, chamsOutline = true,
	chamsWalls = true, espArrowSize = 16,

	aimEnabled = false, aimActive = false, aimHold = false, aimFov = 150, aimShowFov = true,
	aimSmoothOn = true, aimSmooth = 60, aimPart = "Head", aimMethod = "Camera", aimPrediction = 0,
	wallCheck = true,
	aimTargetMode = "Cursor", aimBoneFallback = true, aimOnFire = false,
	aimDeadzone = 2, aimJitter = 0, aimMaxSpeed = 0, aimTargetLine = false,
	aimVelocityEst = true, aimAutoPing = false, aimDynamic = false, aimReaction = 0, aimSticky = true,
	aimMaxDist = 0, aimHeight = 0, aimBulletSpeed = 0, aimDrop = 0, aimCurve = "Exponential",
	aimSnap = 0, aimVertical = 100, aimNeedRmb = false, aimIgnoreFriends = false,
	aimAutoFire = false, aimAutoFireDelay = 80, aimRecoil = 0, aimTargetInfo = false,
	aimFovThickness = 1, aimFovColor = "White",

	silentEnabled = false, silentFov = 200, silentShowFov = true, silentHitChance = 100,

	rageEnabled = false, rageAutoShoot = true, rageIgnoreWalls = true, rageDelay = 50,
	triggerEnabled = false, triggerDelay = 50, triggerHeadOnly = false,
	farmEnabled = false, farmMode = "Nearest", farmMethod = "Void", farmDistance = 4, farmHeight = 0,
	farmQueueHow = "Auto", farmQueueMode = "Any", farmIdle = 10, farmVoidTries = 2, farmResume = true,
	skinsEnabled = false, skinsScreen = true,
	farmUrl = "https://raw.githubusercontent.com/SpriteStudiosRB/SpriteRivalsCheat/main/sprite_rivals.lua",
	spinEnabled = false, spinSpeed = 30,
	rapidFire = false, rapidRate = 12, antiAim = false, antiAimMode = "Jitter", antiAimAngle = 90,
	hitboxEnabled = false, hitboxSize = 8, hitboxPart = "Head", hitboxAlpha = 70,
	swapEnabled = false, swapDist = 12, swapGun = "1", swapKnife = "3", dodgeJump = false, dodgeInterval = 1200,

	aiLearn = false, aiPlay = false, aiSource = "Top killers", aiSelfLearn = true, aiExplore = 10,
	aiMove = true, aiAim = true, aiAimMode = "Camera", aiAimSpeed = 100, aiShoot = true, aiShootDelay = 60,
	aiWalls = false, aiSlot = "1", aiAutoSave = true, aiAutoload = true,
	aiKeys = true, aiMouse = true, aiKeyLearn = true, aiKeyRate = 100,
	aiLook = true, aiLookSpeed = 100,
	aiAvoid = true, aiHunt = true, aiHold = 100, aiAimPart = "Auto",
	aiReaction = 0, aiWobble = 0, aiCone = 0, aiRange = 0, aiShootVariance = 0, aiJumpRate = 100,
	aiDistance = 0, aiRetreat = 0, aiStyle = "Learned", aiYield = true, aiPros = 3, aiWatchRange = 160,
	aiLearnRate = 100,

	walkEnabled = false, walkSpeed = 22, walkResponse = 14,
	slideEnabled = false, slideSpeed = 60, slideDecay = 12, slideSteer = 4, slideJumpBoost = 125,
	bhop = false, airStrafe = false, airAccel = 30, airWish = 8,
	infJump = false, airJumps = 0, airJumpPower = 50,
	jumpEnabled = false, jumpPower = 50,
	moveAssist = true,
	speedLimit = true, speedLimitValue = 90,
	flyEnabled = false, flyMode = "Linear", flySpeed = 60,
	noclip = false, antiAfk = true,
	sprintEnabled = false, sprintSpeed = 34, gravityEnabled = false, gravityValue = 80,
	fallLimit = 0, glideEnabled = false, glideSpeed = 12, noRagdoll = false, antiVoid = false,
	clickTp = false, flyNoclip = false, flyVertical = 100,

	fovOffset = 0, thirdPerson = false,
	fpsEnabled = false, fpsCap = 240,
	thirdPersonDistance = 12, zoomEnabled = false, zoomFov = 25, mouseSens = 100,
	hideCoreUi = false, lowGraphics = false, autoRejoin = false, hitSound = false, hitVolume = 50,
	gotoName = "",

	radarEnabled = false, radarSize = 150, radarRange = 150,
	crosshairEnabled = false, crosshairDot = true, crosshairSize = 8, crosshairGap = 4, crosshairThickness = 1,
	hudList = false,
	fullbright = false, noFog = false, noPost = false, clockOverride = false, clockTime = 14,
	crosshairColor = "Palette", crosshairAlpha = 100, crosshairOutline = false, crosshairT = false,
	crosshairDynamic = false, radarCorner = "Top left", radarRotate = true, radarAlpha = 50,
	hitMarker = false, hudSpeed = false, hudEnemies = false, noShadows = false,
	colorGrade = false, gradeSaturation = 20, gradeContrast = 10,

	cfgSaveOnExit = false, cfgBackup = true, cfgAutoMinutes = 0,

	theme = "Aqua", menuScale = 100, menuAnimations = true, menuBlur = true,
	menuOpacity = 0, menuBubbles = 100, menuBubbleSpeed = 100, menuBlurSize = 14, menuRimSpin = true,
	menuFizz = true, menuFade = true, notifyEnabled = true, notifySeconds = 3, notifySide = "Right",
	menuLock = false, customAccent = "", rainbowAccent = false, menuStartHidden = false,
	menuFit = true, mobileMode = "Auto", touchButtons = true, touchScale = 100,
	introEnabled = true, introVolume = 60,
}

-- The glass effects cost more on a phone, so they start lighter there.
if compat.on then
	Config.menuBlur, Config.menuBubbles, Config.menuFizz = false, 40, false
end

local binds = {
	aim = Enum.KeyCode.Q,
	fly = Enum.KeyCode.P,
	menu = Enum.KeyCode.RightShift,
	espToggle = Enum.KeyCode.Unknown,
	panic = Enum.KeyCode.End,
	slide = Enum.KeyCode.Unknown,
	ai = Enum.KeyCode.Unknown,
	sprint = Enum.KeyCode.LeftShift,
	zoom = Enum.KeyCode.Z,
	clickTp = Enum.KeyCode.T,
	noclip = Enum.KeyCode.Unknown,
	rapid = Enum.KeyCode.Unknown,
}

local BASE_FOV = 70
local SLIDE_KEYS = { [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.C] = true }
local SLOT_KEYS = { ["1"] = 0x31, ["2"] = 0x32, ["3"] = 0x33, ["4"] = 0x34 }

local ESP_COLOR = Color3.fromRGB(255, 255, 255)
local VISIBLE_COLOR = Color3.fromRGB(90, 255, 140)
local HIDDEN_COLOR = Color3.fromRGB(255, 80, 80)

local CLOSEST_PARTS = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" }
local AIM_PRIORITY = {
	Head = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
	Torso = { "UpperTorso", "Torso", "HumanoidRootPart", "Head" },
}
local CROSSHAIR_DIRECTIONS = { Vector2.new(-1, 0), Vector2.new(1, 0), Vector2.new(0, -1), Vector2.new(0, 1) }

local R15_BONES = {
	{ "Head", "UpperTorso" }, { "UpperTorso", "LowerTorso" },
	{ "UpperTorso", "LeftUpperArm" }, { "LeftUpperArm", "LeftLowerArm" }, { "LeftLowerArm", "LeftHand" },
	{ "UpperTorso", "RightUpperArm" }, { "RightUpperArm", "RightLowerArm" }, { "RightLowerArm", "RightHand" },
	{ "LowerTorso", "LeftUpperLeg" }, { "LeftUpperLeg", "LeftLowerLeg" }, { "LeftLowerLeg", "LeftFoot" },
	{ "LowerTorso", "RightUpperLeg" }, { "RightUpperLeg", "RightLowerLeg" }, { "RightLowerLeg", "RightFoot" },
}

local R6_BONES = {
	{ "Head", "Torso" }, { "Torso", "Left Arm" }, { "Torso", "Right Arm" },
	{ "Torso", "Left Leg" }, { "Torso", "Right Leg" },
}

local espObjects = {}
local connections = {}
local heldKeys = {}
local silentPoint = nil
local silentChance = 100
local silentCharacter = nil
local aimLocked = nil
local aimTargetPart = nil
local silentLocked = nil
local rageLocked = nil
local farmTarget = nil
local espCleared = false
local radarCleared = true
local lastShot = 0
local aimAcquiredAt = 0
local trackers = {}
local lastFpsCap = 240
local fpsStatus = nil
local window = nil
local fovApplied = false
local fpsSmooth = 60
local pingValue = 0
local lastPingCheck = 0
local sliding = false
local slideMomentum = 0
local lastSlideTime = 0
local lastJump = 0
local mouseRemainder = Vector2.zero
local crosshairShown = false
local originalMinZoom, originalMaxZoom = localPlayer.CameraMinZoomDistance, localPlayer.CameraMaxZoomDistance
local detach

-- Extra feature modules register here: render and physics step callbacks, cleanup, and menu refresh callbacks.
local hooks = { render = {}, step = {}, clean = {}, refresh = {} }
hooks.touch = { up = false, down = false, slide = false, sprint = false, zoom = false, rapid = false, jump = false }

---Whether a bound key or mouse button is held right now.
function hooks.held(key)
	if key == Enum.KeyCode.Unknown then return false end
	if key.EnumType == Enum.UserInputType then
		local ok, down = pcall(userInputService.IsMouseButtonPressed, userInputService, key)
		return ok and down == true
	end
	return heldKeys[key] == true
end

---Whether an input event is the given bound key or mouse button.
function hooks.pressed(input, key)
	if key == Enum.KeyCode.Unknown then return false end
	return input.KeyCode == key or input.UserInputType == key
end

hooks.tabKeys = {}

---Remember which settings belong to which tab, for the per-tab reset buttons.
function hooks.track(tab, key)
	local bucket = hooks.tabKeys[tab.name]
	if not bucket then
		bucket = {}
		hooks.tabKeys[tab.name] = bucket
	end
	bucket[key] = true
end

do
	local cache = setmetatable({}, { __mode = "k" })

	---Friend lookups wait on the web, so the answer arrives a moment later and is remembered.
	function hooks.friend(player)
		local known = cache[player]
		if known ~= nil then return known end

		cache[player] = false
		task.spawn(function()
			local ok, result = pcall(localPlayer.IsFriendsWith, localPlayer, player.UserId)
			cache[player] = ok and result == true
		end)
		return false
	end
end

local ai = {
	wish = nil, jumpNow = false, speed = 16, playing = false, dead = false,
	dirty = false, lastSave = os.clock(), brain = nil, labels = nil, labelSets = nil, keyLabels = nil,
	history = {}, seen = {}, pros = {}, names = {}, foeHealth = {},
	prosUntil = 0, prev = 5, health = nil, locked = nil,
	nextDecision = 0, nextObserve = 0, nextLabels = 0,
	forcedUntil = 0, forcedAction = 3, checkTime = 0, travel = 0, wished = 0, lastPosition = Vector3.zero,
}

-- Menu widget registries, used by the config system to push loaded values into the UI.
local widgets = {}
local bindWidgets = {}
local dropdownOptions = {}

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

-- Shared per-frame values, so render modules don't ask the engine for the same thing twice.
local perFrame = {
	index = 0, time = 0, mouse = Vector2.zero, viewport = Vector2.zero, origin = Vector3.zero,
	players = {}, playersStamp = -1, filterStamp = -1,
}

local fastParams = RaycastParams.new()
fastParams.FilterType = Enum.RaycastFilterType.Exclude

local function getPlayers()
	if perFrame.playersStamp ~= perFrame.index then
		perFrame.playersStamp = perFrame.index
		perFrame.players = playersService:GetPlayers()
	end
	return perFrame.players
end

-- Error isolation: a broken module is skipped (and disabled if it keeps failing) instead of killing the render loop.
local moduleState, moduleCleanup = {}, {}

local function runModule(name, callback, ...)
	local state = moduleState[name]
	if not state then
		state = { failures = 0, disabled = false }
		moduleState[name] = state
	end
	if state.disabled then return end

	local ok, err = pcall(callback, ...)
	if ok then
		state.failures = 0
		return
	end

	state.failures += 1
	err = tostring(err)
	if err ~= state.lastError then
		state.lastError = err
		warn("[sprite] " .. name .. ": " .. err)
	end

	if state.failures >= 8 then
		state.disabled = true
		warn("[sprite] " .. name .. " disabled after repeated errors")
		local cleanup = moduleCleanup[name]
		if cleanup then pcall(cleanup) end
		if window then pcall(window.Notify, window, name .. " module disabled", 4) end
	end
end

local function resetModules()
	for _, state in pairs(moduleState) do
		state.failures, state.disabled, state.lastError = 0, false, nil
	end
end

moduleCleanup.combat = function() silentPoint = nil end

local function newDrawing(class, props)
	local object = Drawing.new(class)
	for key, value in pairs(props) do object[key] = value end
	return object
end

local aimCircle = Drawing.new("Circle")
aimCircle.Thickness = 1
aimCircle.NumSides = 64
aimCircle.Color = Color3.fromRGB(255, 255, 255)

local silentCircle = Drawing.new("Circle")
silentCircle.Thickness = 1
silentCircle.NumSides = 64
silentCircle.Color = Color3.fromRGB(255, 80, 80)

local targetLine = newDrawing("Line", { Thickness = 1, Color = Color3.fromRGB(255, 80, 80) })
local watermark = createWatermark()

local radarBack = newDrawing("Square", { Filled = true, Color = Color3.fromRGB(10, 25, 45), Transparency = 0.5 })
local radarBorder = newDrawing("Square", { Filled = false, Thickness = 1, Color = ACCENT })
local radarSelf = newDrawing("Triangle", { Filled = true, Color = ESP_COLOR })

-- The outline shapes are made first so they sit behind the crosshair.
local crosshairLines = {
	shadow = {}, spread = 0,
	colors = {
		White = Color3.fromRGB(255, 255, 255), Red = Color3.fromRGB(255, 70, 70), Green = Color3.fromRGB(80, 255, 120),
		Cyan = Color3.fromRGB(80, 230, 255), Pink = Color3.fromRGB(255, 110, 200),
	},
}
for i = 1, 4 do
	crosshairLines.shadow[i] = newDrawing("Line", { Thickness = 3, Color = Color3.new(0, 0, 0) })
end
crosshairLines.shadowDot = newDrawing("Circle", { Radius = 2.5, NumSides = 12, Filled = true, Color = Color3.new(0, 0, 0) })
for i = 1, 4 do
	crosshairLines[i] = newDrawing("Line", { Thickness = 1, Color = ESP_COLOR })
end
local crosshairDot = newDrawing("Circle", { Radius = 1.5, NumSides = 12, Filled = true, Color = ESP_COLOR })
local featureList = newDrawing("Text", { Size = 13, Outline = true, Center = true, Color = ACCENT })

local PALETTES = {
	Classic = { base = Color3.fromRGB(255, 255, 255), visible = Color3.fromRGB(90, 255, 140), hidden = Color3.fromRGB(255, 80, 80) },
	Neon = { base = Color3.fromRGB(255, 255, 255), visible = Color3.fromRGB(0, 255, 200), hidden = Color3.fromRGB(255, 0, 170) },
	Sunset = { base = Color3.fromRGB(255, 240, 220), visible = Color3.fromRGB(255, 205, 80), hidden = Color3.fromRGB(255, 90, 60) },
	Ice = { base = Color3.fromRGB(235, 250, 255), visible = Color3.fromRGB(120, 220, 255), hidden = Color3.fromRGB(160, 130, 255) },
}
local PALETTE_NAMES = { "Classic", "Neon", "Sunset", "Ice" }

local function applyPalette(name)
	local palette = PALETTES[name] or PALETTES.Classic
	ESP_COLOR, VISIBLE_COLOR, HIDDEN_COLOR = palette.base, palette.visible, palette.hidden

	radarSelf.Color = ESP_COLOR
	crosshairDot.Color = ESP_COLOR
	for _, line in ipairs(crosshairLines) do line.Color = ESP_COLOR end
	crosshairLines.color = nil
	for _, esp in pairs(espObjects) do
		esp.color = nil
		esp.radarDot.Color = HIDDEN_COLOR
	end
end

local function isEnemy(player)
	if player == localPlayer then return false end
	if Config.teamCheck and player.Team ~= nil and player.Team == localPlayer.Team then return false end
	return true
end

local function getCharacterParts(player)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and humanoid.Health > 0) then return end
	return character, humanoid, root
end

local function setFilter(extra)
	local filter = { currentCamera }
	if localPlayer.Character then table.insert(filter, localPlayer.Character) end
	if extra then table.insert(filter, extra) end
	aimParams.FilterDescendantsInstances = filter
end

local function isVisible(part, character)
	setFilter(character)
	local origin = currentCamera.CFrame.Position
	return workspace:Raycast(origin, part.Position - origin, aimParams) == nil
end

-- Fast line of sight check: the filter is built once per frame and the target itself may be the first hit.
local function isVisibleFast(part, character)
	if perFrame.filterStamp ~= perFrame.index then
		perFrame.filterStamp = perFrame.index
		local own = localPlayer.Character
		fastParams.FilterDescendantsInstances = own and { currentCamera, own } or { currentCamera }
	end

	local origin = currentCamera.CFrame.Position
	local result = workspace:Raycast(origin, part.Position - origin, fastParams)
	return result == nil or result.Instance:IsDescendantOf(character)
end

-- Short lived visibility cache so ESP colors and bone fallback don't raycast every frame.
local visibilityCache = setmetatable({}, { __mode = "k" })

local function isVisibleCached(part, character)
	local now = os.clock()
	local entry = visibilityCache[part]
	if entry and now - entry.time < 0.06 then return entry.visible end

	local visible = isVisibleFast(part, character)
	if entry then
		entry.time, entry.visible = now, visible
	else
		visibilityCache[part] = { time = now, visible = visible }
	end
	return visible
end

-- Caches one chosen part per player so the aim target doesn't flicker.
local partCache = {}

local function resolvePart(player, character)
	if Config.aimPart == "Head" then
		return character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	end
	if Config.aimPart == "Torso" then
		return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")
	end

	local cached = partCache[player]
	if cached and cached.Parent == character then return cached end

	local mouse = userInputService:GetMouseLocation()
	local best, bestDist = nil, math.huge
	for _, part in ipairs({
		character:FindFirstChild("Head"),
		character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"),
		character:FindFirstChild("HumanoidRootPart"),
	}) do
		if not part then continue end
		local screenPos, onScreen = currentCamera:WorldToViewportPoint(part.Position)
		if not onScreen then continue end
		local dist = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
		if dist < bestDist then best, bestDist = part, dist end
	end

	partCache[player] = best
	return best
end

local function aimPoint(part)
	return part.Position + part.AssemblyLinearVelocity * (Config.aimPrediction / 1000)
end

-- FOV-circle target pick for Aim / Soft Aim (distance measured on screen, from the cursor).
local function evaluate(player, fov, ignoreWalls, mouse)
	local character = getCharacterParts(player)
	if not character then return end

	local part = resolvePart(player, character)
	if not part then return end

	local screenPos, onScreen = currentCamera:WorldToViewportPoint(part.Position)
	if not onScreen then return end

	local dist = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
	if dist >= fov then return end
	if Config.wallCheck and not ignoreWalls and not isVisible(part, character) then return end

	return part, dist
end

local function getTarget(fov, ignoreWalls, stickyPlayer)
	local mouse = userInputService:GetMouseLocation()

	if stickyPlayer and isEnemy(stickyPlayer) then
		local part = evaluate(stickyPlayer, fov * 1.3, ignoreWalls, mouse)
		if part then return part, stickyPlayer end
	end

	local best, bestPlayer, bestDist = nil, nil, fov
	for _, player in ipairs(playersService:GetPlayers()) do
		if not isEnemy(player) then continue end
		local part, dist = evaluate(player, bestDist, ignoreWalls, mouse)
		if part then best, bestPlayer, bestDist = part, player, dist end
	end

	return best, bestPlayer
end

-- World-distance target pick for Rage: engages without needing the enemy on screen.
local function getWorldTarget(stickyPlayer, ignoreWalls)
	local origin = currentCamera.CFrame.Position

	if stickyPlayer and isEnemy(stickyPlayer) then
		local character = getCharacterParts(stickyPlayer)
		if character then
			local part = resolvePart(stickyPlayer, character)
			if part and (ignoreWalls or not Config.wallCheck or isVisible(part, character)) then
				return part, stickyPlayer
			end
		end
	end

	local best, bestPlayer, bestDist = nil, nil, math.huge
	for _, player in ipairs(playersService:GetPlayers()) do
		if not isEnemy(player) then continue end
		local character = getCharacterParts(player)
		if not character then continue end
		local part = resolvePart(player, character)
		if not part then continue end
		if Config.wallCheck and not ignoreWalls and not isVisible(part, character) then continue end

		local dist = (origin - part.Position).Magnitude
		if dist < bestDist then best, bestPlayer, bestDist = part, player, dist end
	end

	return best, bestPlayer
end

-- Aimbot only: ordered bone list for the selected aim part.
local function orderedParts(character, mouse)
	local names = AIM_PRIORITY[Config.aimPart]
	local list = {}

	if names then
		for _, name in ipairs(names) do
			local part = character:FindFirstChild(name)
			if part then table.insert(list, part) end
		end
		return list
	end

	for _, name in ipairs(CLOSEST_PARTS) do
		local part = character:FindFirstChild(name)
		if part then
			local screenPos = currentCamera:WorldToViewportPoint(part.Position)
			table.insert(list, { part = part, dist = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude })
		end
	end
	table.sort(list, function(a, b) return a.dist < b.dist end)
	for index, entry in ipairs(list) do list[index] = entry.part end
	return list
end

-- Aimbot only: pick the preferred bone, falling back to any visible bone when it is covered.
local function resolveAimPart(character, mouse)
	local parts = orderedParts(character, mouse)
	local first = parts[1]
	if not first then return end

	if not Config.wallCheck then return first end
	if isVisibleCached(first, character) then return first end
	if not Config.aimBoneFallback then return end

	for index = 2, #parts do
		if isVisibleCached(parts[index], character) then return parts[index] end
	end
end

local function evaluateAimbot(player, fov, mouse)
	local character, humanoid, root = getCharacterParts(player)
	if not character then return end

	if Config.aimIgnoreFriends and hooks.friend(player) then return end
	if Config.aimMaxDist > 0 and (currentCamera.CFrame.Position - root.Position).Magnitude > Config.aimMaxDist then return end

	local part = resolveAimPart(character, mouse)
	if not part then return end

	local screenPos, onScreen = currentCamera:WorldToViewportPoint(part.Position)
	if not onScreen then return end

	local cursorDist = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
	if cursorDist >= fov then return end

	local score = cursorDist
	if Config.aimTargetMode == "Distance" then
		score = (currentCamera.CFrame.Position - root.Position).Magnitude
	elseif Config.aimTargetMode == "Lowest HP" then
		score = humanoid.Health
	end

	return part, score
end

local function getAimbotTarget(stickyPlayer)
	if Config.aimNeedRmb and not compat.on and not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end

	local mouse = userInputService:GetMouseLocation()
	local fov = Config.aimFov

	if stickyPlayer and isEnemy(stickyPlayer) then
		local part = evaluateAimbot(stickyPlayer, fov * 1.3, mouse)
		if part then return part, stickyPlayer end
	end

	local best, bestPlayer, bestScore = nil, nil, math.huge
	for _, player in ipairs(playersService:GetPlayers()) do
		if not isEnemy(player) then continue end
		local part, score = evaluateAimbot(player, fov, mouse)
		if part and score < bestScore then best, bestPlayer, bestScore = part, player, score end
	end

	return best, bestPlayer
end

-- Velocity estimated from position changes, since replicated velocity is unreliable on custom controllers.
local function updateTrackers(now)
	for _, player in ipairs(getPlayers()) do
		if player == localPlayer then continue end

		local _, _, root = getCharacterParts(player)
		if not root then
			trackers[player] = nil
			continue
		end

		local position = root.Position
		local tracker = trackers[player]
		if not tracker then
			trackers[player] = { position = position, time = now, velocity = Vector3.zero }
			continue
		end

		local elapsed = now - tracker.time
		if elapsed < 0.001 then continue end

		local raw = (position - tracker.position) / elapsed
		if raw.Magnitude > 250 then
			tracker.velocity = Vector3.zero
		else
			tracker.velocity = tracker.velocity:Lerp(raw, 1 - math.exp(-elapsed * 22))
		end
		tracker.position, tracker.time = position, now
	end
end

---Aim point for the aimbot only: leads by the configured prediction plus half the ping.
local function aimbotPoint(part, player)
	local tracker = Config.aimVelocityEst and trackers[player]
	local velocity = tracker and tracker.velocity or part.AssemblyLinearVelocity

	local lead = Config.aimPrediction / 1000
	if Config.aimAutoPing then lead += pingValue / 2000 end
	local point = part.Position + velocity * lead

	-- Projectile weapons: lead by the flight time and aim above the target to make up for the drop.
	local speed = Config.aimBulletSpeed
	if speed > 0 then
		local travel = (point - currentCamera.CFrame.Position).Magnitude / speed
		point += velocity * travel + Vector3.new(0, 0.5 * Config.aimDrop * travel * travel, 0)
	end

	return point + Vector3.new(0, Config.aimHeight / 10, 0)
end

local function aimAt(point, dt)
	local retain = Config.aimSmoothOn and math.clamp(Config.aimSmooth / 100, 0, 0.99) or 0
	local alpha = 1 - retain ^ (dt * 60)

	local screenPos, onScreen = currentCamera:WorldToViewportPoint(point)
	local mouse = userInputService:GetMouseLocation()
	local distance = (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude
	if onScreen and distance <= Config.aimDeadzone then
		return
	end

	-- Ease out near the target so the aim settles instead of oscillating around it.
	if Config.aimDynamic and onScreen then
		alpha *= 0.45 + 0.55 * math.sqrt(math.clamp(distance / math.max(Config.aimFov, 1), 0, 1))
	end

	local held = os.clock() - aimAcquiredAt - Config.aimReaction / 1000
	if Config.aimCurve == "Linear" and onScreen then
		-- A steady pull instead of a fraction of the gap, so far targets are not rushed.
		alpha = math.clamp((1 - retain) * 40 * dt * 60 / math.max(distance, 1), 0, 1)
	elseif Config.aimCurve == "Ramp up" then
		alpha *= 0.35 + 0.65 * math.clamp(held / 0.25, 0, 1)
	end
	if Config.aimSnap > 0 and held < Config.aimSnap / 1000 then alpha = 1 end
	local vertical = Config.aimVertical / 100

	local jitter = Config.aimJitter

	if Config.aimMethod == "Mouse" and compat.canMove() then
		if not onScreen or not compat.active() then return end

		local delta = (Vector2.new(screenPos.X, screenPos.Y) - mouse) * alpha
		delta = Vector2.new(delta.X, delta.Y * vertical)
		if jitter > 0 then
			delta += Vector2.new(math.random() - 0.5, math.random() - 0.5) * jitter
		end

		local cap = Config.aimMaxSpeed
		if cap > 0 and delta.Magnitude > cap then
			delta = delta.Unit * cap
		end

		-- Carry the fractional part forward so small corrections still land.
		local total = delta + mouseRemainder
		local moveX, moveY = math.round(total.X), math.round(total.Y)
		mouseRemainder = total - Vector2.new(moveX, moveY)
		if moveX ~= 0 or moveY ~= 0 then
			compat.move(moveX, moveY)
		end
		return
	end

	if jitter > 0 then
		point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * jitter * 0.05
	end
	local origin = currentCamera.CFrame.Position
	local goal = CFrame.lookAt(origin, point)
	if vertical < 1 then
		-- Keep part of the current pitch, so only the sideways turn follows the target.
		local look, wanted = currentCamera.CFrame.LookVector, (point - origin).Unit
		local pitch = math.asin(math.clamp(look.Y, -1, 1))
		pitch += (math.asin(math.clamp(wanted.Y, -1, 1)) - pitch) * vertical
		local yaw = math.atan2(wanted.X, -wanted.Z)
		local flat = math.cos(pitch)
		goal = CFrame.lookAt(origin, origin + Vector3.new(flat * math.sin(yaw), math.sin(pitch), -flat * math.cos(yaw)))
	end
	currentCamera.CFrame = currentCamera.CFrame:Lerp(goal, alpha)
end

local function fireClick(delayMs)
	if os.clock() - lastShot < delayMs / 1000 or not compat.active() then return end
	lastShot = os.clock()
	compat.click()
end

local function pickFarmTarget(root)
	if farmTarget and isEnemy(farmTarget) and getCharacterParts(farmTarget) then
		return farmTarget
	end

	local candidates = {}
	for _, player in ipairs(playersService:GetPlayers()) do
		if not isEnemy(player) then continue end
		local _, humanoid, targetRoot = getCharacterParts(player)
		if targetRoot then
			table.insert(candidates, {
				player = player, health = humanoid.Health,
				dist = (targetRoot.Position - root.Position).Magnitude,
			})
		end
	end
	if #candidates == 0 then return nil end

	if Config.farmMode == "Random" then
		return candidates[math.random(1, #candidates)].player
	end

	table.sort(candidates, function(a, b)
		if Config.farmMode == "Lowest HP" then return a.health < b.health end
		return a.dist < b.dist
	end)
	return candidates[1].player
end

-- Auto farm: one switch. It joins a queue, fights the match and joins again when the match ends. It queues through the game's
-- own Play menu when those buttons are on screen, otherwise by standing on a queue pad. It fights with the gun, or by spinning
-- inside the enemy so a collision throws them off the map.
do
	local RESUME_FILE = "sprite_rivals_resume.txt"
	local REPORT_FILE = "SpriteRivals/farm_report.txt"
	local PAD_WORDS = { "queue", "pad", "matchmak", "portal", "duel", "ranked", "1v1", "2v2", "3v3", "4v4", "5v5" }
	local PAD_SKIP = { "jump", "spawn", "shard", "bounce", "launch", "boost", "speed", "trampoline" }
	local MODES = { "1v1", "2v2", "3v3", "4v4", "5v5" }
	-- Words on the game's own buttons, best match first. A button with a DENY word is never pressed.
	local GO_WORDS = {
		"play again", "queue again", "requeue", "join queue", "find match", "find a match", "find game", "quick play",
		"queue", "start", "play", "ready", "confirm",
	}
	local AFTER_WORDS = { "continue", "next", "claim", "collect", "okay", "ok", "done", "skip", "proceed", "got it", "close" }
	local QUEUED_WORDS = {
		"cancel queue", "leave queue", "in queue", "queueing", "queuing", "searching for", "finding match", "finding a match",
		"looking for match", "looking for a match", "waiting for players", "waiting for match",
	}
	local DENY_WORDS = {
		"buy", "purchase", "robux", "shop", "store", "gift", "trade", "report", "leave", "quit", "forfeit", "surrender", "exit",
		"reset", "settings", "cancel", "back", "decline", "block", "friend", "friends", "invite", "party", "spectate", "premium",
		"gamepass", "vip", "redeem", "sell", "delete", "unequip", "rejoin", "lobby", "tutorial", "practice", "bots", "private",
		"custom", "create", "mute", "kick", "ban",
	}
	local PAD_NEAR, MOVED_OFF, TELEPORTED, BURST_TIME, BURST_GAP, FLING_SPIN = 70, 25, 60, 0.5, 1.2, 5e4
	local HOLD_MIN, LOBBY_BACK, LOBBY_GONE, QUEUE_STALE, SMALL_SERVER = 1.5, 2, 1.2, 150, 12
	local PRESS_GAP, PRESS_AGAIN, UI_FAST, UI_SLOW, MENU_PATIENCE = 1.4, 7, 0.5, 2.5, 25

	local farm = {
		pads = {}, scanAt = -100, state = "free", via = nil, held = nil, queuedAt = 0, matchAt = 0, enemySeen = os.clock(),
		tries = 0, bursting = false, burstUntil = 0, gapUntil = 0, burstFrom = nil, burstTarget = nil, voidFailed = false,
		dropped = setmetatable({}, { __mode = "k" }), floorY = -math.huge, remembered = nil, warned = {},
		padName = nil, status = "Off", watching = false, reloadQueued = false, modeSeen = nil,
		ui = nil, uiAt = -100, sense = nil, pressed = setmetatable({}, { __mode = "k" }), pressAt = 0, attempt = 1, scanGap = 5,
		freeSince = os.clock(), padFirst = 0, queueSeen = 0, lobbyFor = nil, written = nil, matches = 0,
		voidMisses = 0, voidOff = false, threw = false, events = {}, born = os.clock(), lastPress = nil,
	}
	hooks.farm = farm

	local function log(text)
		local events = farm.events
		events[#events + 1] = string.format("%7.1f  %s", os.clock() - farm.born, text)
		if #events > 40 then table.remove(events, 1) end
	end

	local function say(text, once)
		if once then
			if farm.warned[once] then return end
			farm.warned[once] = true
		end
		log(text)
		if window then pcall(window.Notify, window, text, 3) end
	end

	local function hasPart(text, words)
		for _, word in ipairs(words) do
			if string.find(text, word, 1, true) then return word end
		end
		return nil
	end

	-- The game's buttons ---------------------------------------------------------------------------------------

	---Lower case words only, so "Play!" and " PLAY " read the same.
	local function plain(text)
		text = string.lower(tostring(text or ""))
		text = string.gsub(text, "<[^>]*>", " ")
		text = string.gsub(text, "[^%w]+", " ")
		text = string.gsub(text, "^ +", "")
		text = string.gsub(text, " +$", "")
		return text
	end

	local function hasWord(text, word)
		return string.find(" " .. text .. " ", " " .. word .. " ", 1, true) ~= nil
	end

	---Position in the list of the first word that appears in the text.
	local function firstWord(text, list)
		for index, word in ipairs(list) do
			if hasWord(text, word) then return index end
		end
		return nil
	end

	local function wantedModes()
		local mode = Config.farmQueueMode
		if mode == "Any" then return MODES end
		return { mode }
	end

	function farm.guiRoot()
		local ok, root = pcall(function() return localPlayer:FindFirstChildOfClass("PlayerGui") end)
		if ok then return root end
		return nil
	end

	---Whether the item and everything above it is switched on.
	local function shown(item, gui)
		local node = item
		while node and node ~= gui do
			if node:IsA("GuiObject") and not node.Visible then return false end
			node = node.Parent
		end
		return true
	end

	---The button a text sits on, or nil when it is only a label.
	local function clickable(item)
		if item.ClassName == "TextButton" then return item end
		return item:FindFirstAncestorWhichIsA("GuiButton")
	end

	local function onScreen(item)
		local size, position = item.AbsoluteSize, item.AbsolutePosition
		if size.X <= 0 or size.Y <= 0 then return false end
		local view = currentCamera.ViewportSize
		local x, y = position.X + size.X / 2, position.Y + size.Y / 2
		return x >= 0 and y >= 0 and x <= view.X and y <= view.Y
	end

	---Sorts what a piece of text on screen means for the queue.
	local function classify(found, item, gui, raw, text, modes, seen)
		if not found.queued then
			local timer = (hasWord(text, "queue") or hasWord(text, "queued")) and string.find(raw, "%d+:%d%d") ~= nil
			if timer or firstWord(text, QUEUED_WORDS) then
				if shown(item, gui) then found.queued = text end
				return
			end
		end
		if #text > 24 or firstWord(text, DENY_WORDS) then return end

		local kind, rank
		for index, mode in ipairs(modes) do
			if hasWord(text, mode) then
				kind, rank = "mode", index
				break
			end
		end
		if not kind then
			local index = firstWord(text, GO_WORDS)
			if index then
				kind, rank = "go", index
			else
				index = firstWord(text, AFTER_WORDS)
				if index then kind, rank = "after", index end
			end
		end
		if not kind then return end

		local button = clickable(item)
		if button and not seen[button] and shown(item, gui) and onScreen(button) then
			seen[button] = true
			table.insert(found[kind], { item = button, text = text, rank = rank })
		end
	end

	---Everything on screen that matters for queueing: the queue text, mode buttons, play buttons and after-match buttons.
	---With full set it also lists the other buttons, for the report.
	local function readUi(full)
		local found = { go = {}, mode = {}, after = {}, queued = nil, count = 0, texts = full and {} or nil }
		local root = farm.guiRoot()
		if not root then return found end

		local modes, seen, listed = wantedModes(), {}, {}
		for _, gui in ipairs(root:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Enabled and not UI.own[gui] then
				for _, item in ipairs(gui:GetDescendants()) do
					local class = item.ClassName
					if class == "TextButton" or class == "TextLabel" then
						found.count += 1
						local raw = item.Text
						if type(raw) == "string" and raw ~= "" and #raw <= 60 then
							local text = plain(raw)
							if text ~= "" then
								classify(found, item, gui, raw, text, modes, seen)
								if full and #found.texts < 60 and not listed[text] and clickable(item) and shown(item, gui) then
									listed[text] = true
									found.texts[#found.texts + 1] = text
								end
							end
						end
					end
				end
			end
		end
		return found
	end

	---Presses a button of the game: a real click on its middle, or its own signals when there is no way to click.
	function farm.press(button)
		local position, size = button.AbsolutePosition, button.AbsoluteSize
		local x, y = position.X + size.X / 2, position.Y + size.Y / 2
		local gui = button:FindFirstAncestorOfClass("ScreenGui")
		if not (gui and gui.IgnoreGuiInset) then
			local ok, inset = pcall(guiService.GetGuiInset, guiService)
			if ok and inset then x, y = x + inset.X, y + inset.Y end
		end
		if compat.clickAt(x, y) then return "click" end

		if type(firesignal) == "function" then
			local fired = false
			for _, name in ipairs({ "MouseButton1Down", "MouseButton1Click", "Activated", "MouseButton1Up" }) do
				local ok = pcall(function() firesignal(button[name]) end)
				fired = fired or ok
			end
			if fired then return "signal" end
		end
		return nil
	end

	---The next button to press: a mode first, then a play button, then whatever closes the results.
	local function choosePress(ui, now)
		local function best(list, once)
			local pick
			for _, entry in ipairs(list) do
				local last = farm.pressed[entry.item]
				local ready = not last or (once and last.attempt ~= farm.attempt) or (not once and now - last.at >= PRESS_AGAIN)
				if ready and (not pick or entry.rank < pick.rank) then pick = entry end
			end
			return pick
		end
		return best(ui.mode, true) or best(ui.go, false) or best(ui.after, false)
	end

	-- Pads --------------------------------------------------------------------------------------------------------

	---Text on the signs around a part, used to tell the 1v1 pad from the 5v5 one.
	local function nearbyText(part)
		local found, seen = {}, 0
		for _, holder in ipairs({ part, part.Parent }) do
			if holder and holder ~= workspace then
				for _, item in ipairs(holder:GetDescendants()) do
					seen += 1
					if seen > 300 or #found >= 12 then break end
					if item:IsA("TextLabel") or item:IsA("TextButton") then
						found[#found + 1] = string.lower(item.Text)
					end
				end
			end
		end
		return table.concat(found, " ")
	end

	---Flat anchored parts that look like a queue pad, best first.
	local function scanPads()
		local wanted = tostring(Config.farmQueueMode)
		local list = {}
		for _, item in ipairs(workspace:GetDescendants()) do
			if not item:IsA("BasePart") or not item.Anchored then continue end
			local size = item.Size
			if size.Y > 8 or math.max(size.X, size.Z) < 4 then continue end

			local parent = item.Parent
			local grand = parent and parent.Parent
			local label = string.lower(item.Name .. " " .. (parent and parent.Name or "") .. " " .. (grand and grand.Name or ""))
			local named = hasPart(label, PAD_WORDS) ~= nil
			local touch = item:FindFirstChildOfClass("TouchInterest") ~= nil
			if not (named or touch) then continue end

			local score = (named and 3 or 0) + (touch and 2 or 0)
			if hasPart(label, PAD_SKIP) then score -= 10 end
			local text = nearbyText(item)
			if string.find(text, "%dv%d") or string.find(text, "queue", 1, true) then score += 3 end
			if wanted ~= "Any" then
				if string.find(label .. " " .. text, wanted, 1, true) then
					score += 6
				elseif string.find(label .. " " .. text, "%dv%d") then
					score -= 4
				end
			end
			if score >= 4 then list[#list + 1] = { part = item, score = score } end
		end
		return list
	end

	local function bestPad(root)
		local best, bestScore, bestDist
		for _, entry in ipairs(farm.pads) do
			local part = entry.part
			if not part.Parent then continue end
			local dist = (part.Position - root.CFrame.Position).Magnitude
			if not best or entry.score > bestScore or (entry.score == bestScore and dist < bestDist) then
				best, bestScore, bestDist = part, entry.score, dist
			end
		end
		return best
	end

	---Where to stand to be on the pad, or nil when no pad is known.
	local function padSpot(root, now, rememberedOnly)
		if farm.modeSeen ~= Config.farmQueueMode then
			farm.modeSeen = Config.farmQueueMode
			farm.scanAt, farm.scanGap = -100, 5
		end
		if not rememberedOnly then
			-- Looking through the whole map is slow, so a map with no pad is looked at less and less often.
			local gap = #farm.pads > 0 and 20 or farm.scanGap
			if farm.state == "match" then gap = math.max(gap, 60) end
			if now - farm.scanAt > gap then
				farm.scanAt = now
				local ok, list = pcall(scanPads)
				if ok then
					farm.pads = list
					farm.scanGap = #list > 0 and 5 or math.min(farm.scanGap * 2, 60)
				end
			end
			local part = bestPad(root)
			if part then
				farm.padName = part.Name
				return part.Position + Vector3.new(0, part.Size.Y / 2 + 3.2, 0)
			end
		end
		farm.padName = farm.remembered and "remembered spot" or nil
		return farm.remembered
	end

	local function padFile()
		return "sprite_rivals_pad_" .. tostring(game.PlaceId) .. ".txt"
	end

	function farm.remember()
		local _, _, root = getCharacterParts(localPlayer)
		if not root then return false end
		farm.remembered = root.CFrame.Position
		pcall(function()
			compat.writefile(padFile(), string.format("%.2f,%.2f,%.2f", root.CFrame.Position.X, root.CFrame.Position.Y, root.CFrame.Position.Z))
		end)
		return true
	end

	function farm.forget()
		farm.remembered = nil
		pcall(function() compat.delfile(padFile()) end)
	end

	---Look for pads right now and report what was found.
	function farm.find()
		local _, _, root = getCharacterParts(localPlayer)
		if not root then return nil end
		local ok, list = pcall(scanPads)
		farm.pads = ok and list or {}
		farm.scanAt = os.clock()
		local part = bestPad(root)
		return part, #farm.pads
	end

	pcall(function()
		if not compat.isfile(padFile()) then return end
		local x, y, z = string.match(compat.readfile(padFile()), "^(%-?%d+%.?%d*),(%-?%d+%.?%d*),(%-?%d+%.?%d*)$")
		if x then farm.remembered = Vector3.new(tonumber(x), tonumber(y), tonumber(z)) end
	end)

	local function standOn(root, spot)
		root.CFrame = CFrame.lookAt(spot, spot + root.CFrame.LookVector)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	local function settle(root)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	local function flat(a, b)
		return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
	end

	-- Fighting ----------------------------------------------------------------------------------------------------

	local function fallen(targetRoot)
		return farm.floorY > -math.huge and targetRoot.Position.Y < farm.floorY - 60
	end

	local function beginMatch(now, root)
		farm.state, farm.matchAt, farm.held = "match", now, nil
		farm.tries, farm.bursting, farm.voidFailed, farm.gapUntil = 0, false, false, 0
		farm.burstFrom, farm.floorY, farm.lobbyFor, farm.enemySeen, farm.threw = nil, root.CFrame.Position.Y, nil, now, false
		farm.matches += 1
		table.clear(farm.dropped)
		say("Match started")
	end

	---A void drop that never moved anyone twice in a row is given up for the rest of the session.
	local function endMatch(now, root)
		if farm.voidFailed then
			farm.voidMisses += 1
			if farm.voidMisses >= 2 and not farm.voidOff then
				farm.voidOff = true
				say("The enemy never moved in 2 matches, so the farm uses the gun now", "voidoff")
			end
		elseif farm.threw then
			farm.voidMisses = 0
		end
		farm.state, farm.via, farm.bursting, farm.burstFrom, farm.floorY = "free", nil, false, nil, -math.huge
		farm.attempt += 1
		farm.freeSince, farm.lobbyFor = now, nil
		settle(root)
		say("Match over")
	end

	---Spins inside the enemy so a collision throws them off the map. Returns true while it is busy with that.
	local function voidStep(root, target, targetRoot, now)
		local dropAt = farm.dropped[target]
		if dropAt then
			if now - dropAt < 8 then
				farm.status = "Enemy thrown, waiting for the fall"
				return true
			end
			farm.dropped[target] = nil
		end
		if farm.voidFailed then return false end
		if farm.burstTarget ~= target then
			farm.burstTarget, farm.burstFrom, farm.bursting, farm.gapUntil = target, nil, false, 0
		end

		if farm.bursting then
			if now < farm.burstUntil then
				root.CFrame = targetRoot.CFrame
				root.AssemblyAngularVelocity = Vector3.new(0, FLING_SPIN, 0)
				root.AssemblyLinearVelocity = Vector3.zero
				farm.status = "Void drop " .. farm.tries .. "/" .. Config.farmVoidTries
				return true
			end
			farm.bursting, farm.gapUntil = false, now + BURST_GAP
			settle(root)
		end

		local moved = farm.burstFrom and (targetRoot.Position - farm.burstFrom).Magnitude or 0
		if fallen(targetRoot) or moved > 80 then
			farm.dropped[target], farm.burstFrom, farm.threw = now, nil, true
			return true
		end

		if now < farm.gapUntil then
			local goal = targetRoot.CFrame * CFrame.new(0, Config.farmHeight, Config.farmDistance)
			root.CFrame = CFrame.lookAt(goal.Position, targetRoot.Position)
			settle(root)
			farm.status = "Checking the drop"
			return true
		end

		if farm.tries >= Config.farmVoidTries then
			farm.voidFailed = true
			say("The enemy did not move, so the farm is using the gun", "voidfail")
			return false
		end

		farm.tries += 1
		farm.bursting, farm.burstUntil, farm.burstFrom = true, now + BURST_TIME, targetRoot.Position
		return true
	end

	local function voidAllowed(sense)
		if farm.state == "match" then return true end
		-- Without a queue the farm cannot tell a match from the lobby, so only small servers count as a match.
		return sense.via == nil and #playersService:GetPlayers() <= SMALL_SERVER
	end

	local function killStep(root, target, now, sense)
		local character, _, targetRoot = getCharacterParts(target)
		if not targetRoot then return false end

		if fallen(targetRoot) then
			-- An enemy that falls after we tried to throw them counts as a throw that worked.
			if farm.tries > 0 then farm.threw = true end
			farm.status = "Enemy fell off the map"
			return true
		end
		if farm.floorY > -math.huge then
			farm.floorY = math.min(farm.floorY, root.CFrame.Position.Y, targetRoot.Position.Y)
		else
			farm.floorY = root.CFrame.Position.Y
		end

		if Config.farmMethod == "Void" and not farm.voidOff and voidAllowed(sense) and voidStep(root, target, targetRoot, now) then
			return true
		end

		local goal = targetRoot.CFrame * CFrame.new(0, Config.farmHeight, Config.farmDistance)
		root.CFrame = CFrame.lookAt(goal.Position, targetRoot.Position)
		root.AssemblyLinearVelocity = Vector3.zero
		local point = aimPoint(character:FindFirstChild("Head") or targetRoot)
		currentCamera.CFrame = CFrame.lookAt(currentCamera.CFrame.Position, point)
		fireClick(Config.rageDelay)
		farm.status = "In match: shooting " .. target.Name
		return true, point, character
	end

	-- Queueing ----------------------------------------------------------------------------------------------------

	---What the farm can see now: the game's buttons, a pad, and whether we are standing in the lobby.
	local function look(root, now, position)
		local how = Config.farmQueueHow
		local menuOn = how == "Auto" or how == "Play menu"
		local padOn = how == "Auto" or how == "Pad" or how == "Remembered spot"

		if menuOn then
			if now - farm.uiAt >= (farm.state == "match" and UI_SLOW or UI_FAST) then
				farm.uiAt = now
				local ok, result = pcall(readUi, false)
				if ok then farm.ui = result end
			end
		else
			farm.ui = nil
		end

		local ui = farm.ui
		local menuHere = ui ~= nil and (ui.queued ~= nil or #ui.mode > 0 or #ui.go > 0 or #ui.after > 0)
		local menuUsable = ui ~= nil and (ui.queued ~= nil or #ui.mode > 0 or #ui.go > 0) and now >= farm.padFirst

		local spot
		if padOn and not (how == "Auto" and menuUsable) then
			spot = padSpot(root, now, how == "Remembered spot")
		end
		local atPad = spot ~= nil and flat(position, spot) <= PAD_NEAR

		local via
		if menuOn and menuUsable then via = "menu" elseif spot then via = "pad" end
		return { ui = ui, menuHere = menuHere, spot = spot, atPad = atPad, lobby = menuHere or atPad, via = via }
	end

	local function nearTarget(target, position, reach)
		local _, _, targetRoot = getCharacterParts(target)
		return targetRoot ~= nil and (targetRoot.Position - position).Magnitude <= reach
	end

	local function stepQueued(root, now, sense, teleported)
		local held = now - farm.queuedAt
		local how = Config.farmQueueHow
		local allowed = (farm.via == "menu" and (how == "Auto" or how == "Play menu"))
			or (farm.via == "pad" and (how == "Auto" or how == "Pad" or how == "Remembered spot"))
		if not allowed then
			-- The way to queue was changed while waiting: let go of the pad and start over with the new way.
			farm.state, farm.via, farm.held = "free", nil, nil
			farm.attempt += 1
			farm.freeSince = now
			log("queue way changed")
			return false
		end
		if farm.via == "pad" then
			local off = (root.CFrame.Position - farm.held).Magnitude
			if held > HOLD_MIN and (off > MOVED_OFF or teleported) then
				beginMatch(now, root)
				return false
			end
			if held > QUEUE_STALE then
				farm.state, farm.via = "free", nil
				farm.attempt += 1
				farm.freeSince = now
				log("queue timed out, trying again")
				return false
			end
			if sense.spot and (sense.spot - farm.held).Magnitude > 2 then farm.held = sense.spot end
			standOn(root, farm.held)
			farm.status = "Queued on " .. tostring(farm.padName)
			return true
		end

		local ui = sense.ui
		if ui and ui.queued then
			farm.queueSeen = now
			farm.status = "In the game's queue (" .. ui.queued .. ")"
			return true
		end
		if held > HOLD_MIN and (teleported or not sense.menuHere) then
			-- The queue text is gone and so are the lobby buttons: the game has moved us into a match.
			if now - farm.queueSeen >= LOBBY_GONE then
				beginMatch(now, root)
				return false
			end
			return true
		end
		if now - farm.queueSeen >= 3 then
			farm.state, farm.via = "free", nil
			farm.attempt += 1
			farm.freeSince = now
			log("left the queue, trying again")
			return false
		end
		return true
	end

	---Whether the match has ended: the lobby is back, the game sent us there, or no enemy has been around for a while.
	local function matchOver(now, sense, teleported)
		if sense.lobby then
			farm.lobbyFor = farm.lobbyFor or now
		else
			farm.lobbyFor = nil
		end
		local settled = now - farm.matchAt > 3
		local back = settled and farm.lobbyFor ~= nil and now - farm.lobbyFor >= LOBBY_BACK
		local sent = settled and teleported and sense.lobby
		local idle = settled and sense.via ~= nil and now - farm.enemySeen >= Config.farmIdle
		return back or sent or idle
	end

	local function stepFree(root, now, sense, target, teleported)
		local how = Config.farmQueueHow
		local position = root.CFrame.Position

		-- Switched on in the middle of a fight, or the game started one for us.
		if target and not sense.lobby and nearTarget(target, position, 150)
			and (teleported or (sense.via ~= "pad" and #playersService:GetPlayers() <= SMALL_SERVER)) then
			beginMatch(now, root)
			return killStep(root, target, now, sense)
		end

		if sense.via == "pad" then
			farm.state, farm.via, farm.held, farm.queuedAt = "queued", "pad", sense.spot, now
			standOn(root, sense.spot)
			farm.status = "Queued on " .. tostring(farm.padName)
			say("Queueing on " .. tostring(farm.padName))
			return true
		end

		if sense.via == "menu" then
			local ui = sense.ui
			if ui.queued then
				farm.state, farm.via, farm.queuedAt, farm.queueSeen = "queued", "menu", now, now
				farm.status = "In the game's queue"
				say("In the game's queue")
				return true
			end

			local pick = now >= farm.pressAt and choosePress(ui, now) or nil
			if pick then
				local result = farm.press(pick.item)
				farm.pressed[pick.item] = { at = now, attempt = farm.attempt }
				farm.pressAt = now + PRESS_GAP
				farm.lastPress = pick.text
				farm.status = "Pressed " .. pick.text
				log(string.format("pressed '%s' (%s)", pick.text, tostring(result)))
			elseif farm.lastPress == nil then
				farm.status = "Waiting on the Play menu"
			end

			-- A menu that does not start a queue is given up on for a while when there is a pad to use instead.
			if how == "Auto" and now - farm.freeSince > MENU_PATIENCE then
				farm.freeSince, farm.scanAt = now, -100
				if padSpot(root, now, false) then
					farm.padFirst = now + 60
					say("The Play menu did not start a queue, trying the pad", "menufail")
				end
			end
			return true
		end

		-- No way to queue was found. Small servers and the Off setting still fight whoever is there.
		if how ~= "Off" then
			if how == "Remembered spot" then
				say("No remembered spot. Stand on a pad and press Remember this spot", "nopad")
			else
				say("No Play menu or pad found. Press Remember this spot on a pad, or set Queue with to Off", "nopad")
			end
			if #playersService:GetPlayers() > SMALL_SERVER then
				farm.status = "No queue found"
				return false
			end
		end
		if not target then
			farm.status = "Waiting for an enemy"
			return false
		end
		return killStep(root, target, now, sense)
	end

	---Called every frame while the farm is on. Returns handled, silent aim point, silent aim character.
	function hooks.farmStep(root, dt)
		local now = os.clock()
		local position = root.CFrame.Position
		local teleported = farm.written ~= nil and (position - farm.written).Magnitude > TELEPORTED
		if teleported then log(string.format("the game moved us %.0f studs", (position - farm.written).Magnitude)) end

		local target = pickFarmTarget(root)
		farmTarget = target
		if target then
			local _, _, targetRoot = getCharacterParts(target)
			if targetRoot and (targetRoot.Position - position).Magnitude <= 250 then farm.enemySeen = now end
		end

		local sense = look(root, now, position)
		farm.sense = sense

		local handled, point, character = false, nil, nil
		if farm.state == "queued" then
			handled = stepQueued(root, now, sense, teleported)
		end
		if farm.state == "match" then
			if matchOver(now, sense, teleported) then
				endMatch(now, root)
			elseif target then
				handled, point, character = killStep(root, target, now, sense)
			else
				farm.status = "In match: waiting for an enemy"
			end
		end
		if farm.state == "free" then
			handled, point, character = stepFree(root, now, sense, target, teleported)
		end

		farm.written = root.CFrame.Position
		return handled, point, character
	end

	---Runs one frame inside the error guard. The result is read back from the farm table.
	function hooks.farmRun(root, dt)
		farm.handled, farm.point, farm.character = hooks.farmStep(root, dt)
	end

	function farm.reset()
		farm.state, farm.via, farm.held, farm.bursting, farm.tries, farm.voidFailed = "free", nil, nil, false, 0, false
		farm.burstFrom, farm.burstTarget, farm.gapUntil, farm.floorY = nil, nil, 0, -math.huge
		farm.status = "Off"
		farm.written, farm.lobbyFor, farm.ui, farm.sense, farm.uiAt = nil, nil, nil, nil, -100
		farm.padFirst, farm.pressAt, farm.lastPress, farm.freeSince = 0, 0, nil, os.clock()
		farm.voidMisses, farm.voidOff, farm.threw = 0, false, false
		farm.attempt += 1
		table.clear(farm.dropped)
		table.clear(farm.pressed)
		farmTarget = nil
		local _, _, root = getCharacterParts(localPlayer)
		if root then settle(root) end
	end

	-- Report --------------------------------------------------------------------------------------------------------

	---Everything the farm can see, as text, so a farm that does nothing can be looked at from the outside.
	function farm.report()
		local lines = {}
		local function add(text) lines[#lines + 1] = text end

		add("sprite farm report")
		add(string.format("place %s, %d players, farm %s, %d matches", tostring(game.PlaceId), #playersService:GetPlayers(),
			Config.farmEnabled and "on" or "off", farm.matches))
		add(string.format("state %s via %s | queue with %s | match type %s | kill method %s%s", farm.state, tostring(farm.via),
			tostring(Config.farmQueueHow), tostring(Config.farmQueueMode), tostring(Config.farmMethod), farm.voidOff and " (void given up)" or ""))
		add("status: " .. tostring(farm.status))

		local sense = farm.sense
		if sense then
			add(string.format("lobby %s | menu buttons %s | at pad %s | route %s", tostring(sense.lobby), tostring(sense.menuHere),
				tostring(sense.atPad), tostring(sense.via)))
		end

		local ok, ui = pcall(readUi, true)
		if ok then
			add(string.format("text objects on screen: %d, queue text: %s", ui.count, tostring(ui.queued)))
			for _, kind in ipairs({ "mode", "go", "after" }) do
				local names = {}
				for _, entry in ipairs(ui[kind]) do names[#names + 1] = entry.text end
				add(kind .. " buttons: " .. (#names > 0 and table.concat(names, ", ") or "none"))
			end
			add("other buttons: " .. (#ui.texts > 0 and table.concat(ui.texts, " | ") or "none"))
		else
			add("could not read the screen: " .. tostring(ui))
		end

		local count = 0
		for _, entry in ipairs(farm.pads) do
			if count >= 5 then break end
			count += 1
			local named, path = pcall(function() return entry.part:GetFullName() end)
			add(string.format("pad %d: %s (score %d)", count, named and path or entry.part.Name, entry.score))
		end
		add(string.format("pads found %d, remembered spot %s", #farm.pads, tostring(farm.remembered)))

		local _, _, root = getCharacterParts(localPlayer)
		local enemies, nearest = 0, math.huge
		for _, player in ipairs(playersService:GetPlayers()) do
			if isEnemy(player) then
				local _, _, targetRoot = getCharacterParts(player)
				if targetRoot then
					enemies += 1
					if root then nearest = math.min(nearest, (targetRoot.Position - root.Position).Magnitude) end
				end
			end
		end
		add(string.format("enemies alive %d, nearest %s", enemies, nearest < math.huge and string.format("%d studs", nearest) or "none"))

		add("events:")
		for _, text in ipairs(farm.events) do add("  " .. text) end
		return table.concat(lines, "\n")
	end

	---Writes the report to a file and puts it on the clipboard when the executor can.
	function farm.copyReport()
		local text = farm.report()
		local copied = type(setclipboard) == "function" and pcall(setclipboard, text)
		pcall(function()
			if not compat.isfolder("SpriteRivals") then compat.makefolder("SpriteRivals") end
			compat.writefile(REPORT_FILE, text)
		end)
		return copied == true, text
	end

	-- Staying on across teleports -----------------------------------------------------------------------------------

	local function saveResume(on)
		pcall(function()
			compat.writefile(RESUME_FILE, on and ("1|" .. os.time()) or "0")
		end)
	end

	---Runs the script again in the next server, so the farm carries on after each teleport.
	local function queueReload()
		if farm.reloadQueued or type(queue_on_teleport) ~= "function" then return end
		local url = Config.farmUrl
		if type(url) ~= "string" or url == "" then return end

		farm.reloadQueued = true
		local code = string.format(
			'local ok, text = pcall(function() return isfile and isfile(%q) and readfile(%q) end) '
				.. 'if ok and type(text) == "string" and string.sub(text, 1, 2) == "1|" then '
				.. 'local get = request or http_request '
				.. 'loadstring(get and get({ Url = %q, Method = "GET" }).Body or game:HttpGet(%q))() end',
			RESUME_FILE, RESUME_FILE, url, url
		)
		pcall(queue_on_teleport, code)
	end

	---Turns the farm back on when the last server ended with it running.
	function farm.resume()
		if not Config.farmResume or Config.farmEnabled then return end
		local ok, text = pcall(function() return compat.isfile(RESUME_FILE) and compat.readfile(RESUME_FILE) end)
		if not ok or type(text) ~= "string" then return end

		local stamp = tonumber(string.match(text, "^1|(%d+)$"))
		if not stamp or os.time() - stamp > 240 then return end

		Config.farmEnabled = true
		if widgets.farmEnabled then widgets.farmEnabled:set(true) end
		say("Farm resumed after the teleport")
	end

	-- A farm that keeps failing switches itself off instead of taking the rest of the combat code down with it.
	moduleCleanup["auto farm"] = function()
		Config.farmEnabled = false
		if widgets.farmEnabled then widgets.farmEnabled:set(false) end
		farm.reset()
	end

	table.insert(hooks.step, { "farm watch", function()
		local on = Config.farmEnabled
		if on == farm.watching then return end
		farm.watching = on
		if on then
			farm.freeSince = os.clock()
			saveResume(Config.farmResume)
			if Config.farmResume then queueReload() end
		else
			saveResume(false)
			farm.reset()
		end
	end })

	table.insert(hooks.clean, function()
		saveResume(false)
		farm.reset()
	end)

	-- The status line under the farm switch.
	local statusAt = 0
	table.insert(hooks.render, { "farm status", function(dt, now)
		if now < statusAt or not farm.label then return end
		statusAt = now + 0.25
		local text = "Farm: " .. (Config.farmEnabled and farm.status or "off")
		if Config.farmEnabled and farm.matches > 0 then text ..= string.format(" (%d matches)", farm.matches) end
		if farm.label.Text ~= text then farm.label.Text = text end
	end })
end

local function updateCombat(dt)
	silentPoint = nil
	silentCharacter = nil
	silentChance = Config.silentHitChance

	local _, _, root = getCharacterParts(localPlayer)

	if Config.aiPlay and root and ai.step then
		runModule("ai play", ai.step, dt, root)
		return
	end

	-- Auto farm.
	if Config.farmEnabled and root then
		local run = hooks.farm
		run.handled, run.point, run.character = false, nil, nil
		runModule("auto farm", hooks.farmRun, root, dt)
		if run.handled then
			if run.point then silentPoint, silentChance, silentCharacter = run.point, 100, run.character end
			return
		end
	else
		farmTarget = nil
	end

	-- Spinbot.
	if Config.spinEnabled and root then
		root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(Config.spinSpeed), 0)
	end

	-- Rage aimbot.
	if Config.rageEnabled then
		local part, player = getWorldTarget(rageLocked, Config.rageIgnoreWalls)
		rageLocked = player
		if part then
			local point = aimPoint(part)
			currentCamera.CFrame = CFrame.lookAt(currentCamera.CFrame.Position, point)
			silentPoint, silentChance, silentCharacter = point, 100, part.Parent
			if Config.rageAutoShoot then fireClick(Config.rageDelay) end
		end
		return
	end
	rageLocked = nil

	-- Triggerbot.
	if Config.triggerEnabled then
		local mouse = userInputService:GetMouseLocation()
		local ray = currentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		setFilter()
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, aimParams)
		local model = result and result.Instance:FindFirstAncestorOfClass("Model")
		local target = model and playersService:GetPlayerFromCharacter(model)
		if target and isEnemy(target) and (not Config.triggerHeadOnly or result.Instance.Name == "Head") then
				fireClick(Config.triggerDelay)
			end
	end

	-- Soft aim.
	if Config.silentEnabled then
		local part, player = getTarget(Config.silentFov, false, silentLocked)
		silentLocked = player
		if part then
			silentPoint = aimPoint(part)
			silentCharacter = part.Parent
		end
	else
		silentLocked = nil
	end

	-- Aimbot.
	if Config.aimEnabled and Config.aimVelocityEst and (Config.aimPrediction > 0 or Config.aimAutoPing) then
		updateTrackers(os.clock())
	elseif next(trackers) ~= nil then
		table.clear(trackers)
	end

	local aimHeld = Config.aimActive
		and (not Config.aimOnFire or compat.on or userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
	if Config.aimEnabled and aimHeld then
		local part, player = getAimbotTarget(Config.aimSticky and aimLocked or nil)
		if player ~= aimLocked then aimAcquiredAt = os.clock() end
		aimLocked = player
		aimTargetPart = part
		if part then
			if os.clock() - aimAcquiredAt >= Config.aimReaction / 1000 then
				aimAt(aimbotPoint(part, player), dt)
			end
		else
			mouseRemainder = Vector2.zero
		end
	else
		aimLocked = nil
		aimTargetPart = nil
		mouseRemainder = Vector2.zero
	end
end

local ESP_KEYS = {
	"fill", "box", "boxOutline", "name", "distance", "weapon", "healthText", "healthBar", "healthBack",
	"tracer", "lookLine", "headDot",
}

local function createEsp(player)
	if espObjects[player] then return end

	-- Backing shapes are created first so they render underneath.
	local esp = {
		fill = newDrawing("Square", { Thickness = 1, Filled = true, Color = ESP_COLOR, Transparency = 0.25 }),
		boxOutline = newDrawing("Square", { Thickness = 3, Filled = false, Color = Color3.new(0, 0, 0) }),
		box = newDrawing("Square", { Thickness = 1, Filled = false, Color = ESP_COLOR }),
		healthBack = newDrawing("Line", { Thickness = 4, Color = Color3.new(0, 0, 0) }),
		healthBar = newDrawing("Line", { Thickness = 2, Color = Color3.fromRGB(0, 255, 0) }),
		name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = ESP_COLOR }),
		distance = newDrawing("Text", { Size = 12, Center = true, Outline = true, Color = Color3.fromRGB(200, 200, 200) }),
		weapon = newDrawing("Text", { Size = 12, Center = true, Outline = true, Color = Color3.fromRGB(255, 222, 150) }),
		healthText = newDrawing("Text", { Size = 11, Center = true, Outline = true, Color = ESP_COLOR }),
		tracer = newDrawing("Line", { Thickness = 1, Color = ESP_COLOR }),
		lookLine = newDrawing("Line", { Thickness = 1, Color = ESP_COLOR }),
		headDot = newDrawing("Circle", { Thickness = 1, NumSides = 20, Filled = false, Color = Color3.fromRGB(255, 60, 60) }),
		arrow = newDrawing("Triangle", { Thickness = 1, Filled = true, Color = ESP_COLOR }),
		radarDot = newDrawing("Circle", { Radius = 3, NumSides = 12, Filled = true, Color = HIDDEN_COLOR }),
		corners = {}, bones = {}, boneParts = {}, boneOn = {}, shown = {},
		color = ESP_COLOR, nameText = "", distanceValue = -1, healthValue = -1, ratioValue = -1,
		boneTime = 0, fillOpacity = -1, chamsOn = false, cornersShown = false,
		fillAlpha = -1, thickness = 0, textSize = 0, weaponTime = -1, weaponLabel = "", weaponText = "",
	}
	for index = 1, 8 do
		esp.corners[index] = newDrawing("Line", { Thickness = 1, Color = ESP_COLOR })
	end
	for index = 1, #R15_BONES do
		esp.bones[index] = newDrawing("Line", { Thickness = 1, Color = ESP_COLOR })
	end
	espObjects[player] = esp
end

---Only writes Visible when the state actually changes.
local function setShown(esp, key, flag)
	if esp.shown[key] == flag then return end
	esp.shown[key] = flag
	esp[key].Visible = flag
end

local function hideBody(esp)
	for _, key in ipairs(ESP_KEYS) do
		if esp.shown[key] then
			esp.shown[key] = false
			esp[key].Visible = false
		end
	end
	if esp.cornersShown then
		esp.cornersShown = false
		for _, line in ipairs(esp.corners) do line.Visible = false end
	end
	local boneOn = esp.boneOn
	for index, line in ipairs(esp.bones) do
		if boneOn[index] then
			boneOn[index] = false
			line.Visible = false
		end
	end
	if esp.chamsOn then
		esp.chamsOn = false
		esp.highlight.Enabled = false
	end
end

local function hideEsp(esp)
	hideBody(esp)
	setShown(esp, "arrow", false)
end

local function removeEsp(player)
	local esp = espObjects[player]
	if not esp then return end

	for _, key in ipairs(ESP_KEYS) do esp[key]:Remove() end
	esp.arrow:Remove()
	esp.radarDot:Remove()
	for _, line in ipairs(esp.corners) do line:Remove() end
	for _, line in ipairs(esp.bones) do line:Remove() end
	if esp.highlight then esp.highlight:Destroy() end

	espObjects[player] = nil
	trackers[player] = nil
end

---Apply the visibility color to every element that follows it. Runs only when the color changes.
local function applyEspColor(esp, color)
	esp.color = color
	esp.box.Color = color
	esp.fill.Color = color
	esp.name.Color = color
	esp.tracer.Color = color
	esp.lookLine.Color = color
	esp.arrow.Color = color
	for _, line in ipairs(esp.corners) do line.Color = color end
	for _, line in ipairs(esp.bones) do line.Color = color end
end

---Cache the bone part pairs so the skeleton doesn't search the character every frame.
local function refreshBones(esp, character, humanoid, now)
	if esp.boneCharacter == character and now - esp.boneTime < 2 then return end
	esp.boneCharacter, esp.boneTime = character, now

	local layout = humanoid.RigType == Enum.HumanoidRigType.R15 and R15_BONES or R6_BONES
	local parts = esp.boneParts
	table.clear(parts)
	for index, pair in ipairs(layout) do
		local first, second = character:FindFirstChild(pair[1]), character:FindFirstChild(pair[2])
		parts[index] = (first and second) and { first, second } or false
	end
end

local function putLine(line, fromX, fromY, toX, toY)
	line.From = Vector2.new(fromX, fromY)
	line.To = Vector2.new(toX, toY)
end

---Corner style box made of eight short lines.
local function drawCorners(lines, x, y, width, height)
	local lengthX, lengthY = width * 0.3, height * 0.2
	local right, bottom = x + width, y + height
	putLine(lines[1], x, y, x + lengthX, y)
	putLine(lines[2], x, y, x, y + lengthY)
	putLine(lines[3], right, y, right - lengthX, y)
	putLine(lines[4], right, y, right, y + lengthY)
	putLine(lines[5], x, bottom, x + lengthX, bottom)
	putLine(lines[6], x, bottom, x, bottom - lengthY)
	putLine(lines[7], right, bottom, right - lengthX, bottom)
	putLine(lines[8], right, bottom, right, bottom - lengthY)
end

---Arrow on a circle around the screen center pointing at an off-screen enemy.
local function drawArrow(esp, position)
	local relative = currentCamera.CFrame:PointToObjectSpace(position)
	local direction = Vector2.new(relative.X, relative.Z)
	if direction.Magnitude < 0.001 then return setShown(esp, "arrow", false) end
	direction = direction.Unit

	local center = perFrame.viewport / 2
	local radius = Config.espArrowRadius
	local size = Config.espArrowSize
	local tip = center + direction * radius
	local base = center + direction * (radius - size)
	local side = Vector2.new(-direction.Y, direction.X) * (size * 0.56)

	esp.arrow.PointA = tip
	esp.arrow.PointB = base + side
	esp.arrow.PointC = base - side
	setShown(esp, "arrow", true)
end

local function updateEsp(player, esp, now)
	local character, humanoid, root = getCharacterParts(player)
	if not character or not isEnemy(player) then return hideEsp(esp) end

	local distance = (perFrame.origin - root.Position).Magnitude
	if distance > Config.espMaxDist then return hideEsp(esp) end

	local ratio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)
	if Config.espHpFilter > 0 and ratio * 100 > Config.espHpFilter then return hideEsp(esp) end

	if esp.character ~= character then
		esp.character = character
		esp.head = character:FindFirstChild("Head")
		esp.chamsCharacter = nil
		esp.boneTime = 0
	end
	local head = esp.head

	local visible = true
	if Config.espVisColors or Config.espVisibleOnly then
		visible = isVisibleCached(head or root, character)
		if Config.espVisibleOnly and not visible then return hideEsp(esp) end
	end

	local color = ESP_COLOR
	if Config.espVisColors then
		color = visible and VISIBLE_COLOR or HIDDEN_COLOR
	end

	local mode = Config.espColorMode
	if mode == "Team" then
		local team = player.Team
		if team then color = team.TeamColor.Color end
	elseif mode == "Rainbow" then
		color = Color3.fromHSV((math.floor(now * 12) % 60) / 60, 0.8, 1)
	elseif mode == "Distance" then
		local near = 1 - math.clamp(distance / math.max(Config.espMaxDist, 1), 0, 1)
		color = Color3.fromHSV(math.floor(near * 20) / 20 * 0.33, 0.9, 1)
	elseif mode == "Health" then
		color = Color3.fromHSV(math.floor(ratio * 20) / 20 * 0.33, 0.9, 1)
	end

	if Config.espTargetHighlight
		and (player == aimLocked or player == rageLocked or player == farmTarget or (Config.aiPlay and player == ai.locked)) then
		color = Color3.fromRGB(255, 215, 0)
	end
	if esp.color ~= color then applyEspColor(esp, color) end

	-- Line and text sizes, written only when the setting changes.
	local thickness = Config.espThickness
	if esp.thickness ~= thickness then
		esp.thickness = thickness
		esp.box.Thickness = thickness
		esp.boxOutline.Thickness = thickness + 2
		esp.tracer.Thickness = thickness
		esp.lookLine.Thickness = thickness
		esp.headDot.Thickness = thickness
		for _, line in ipairs(esp.corners) do line.Thickness = thickness end
		for _, line in ipairs(esp.bones) do line.Thickness = thickness end
	end
	local textSize = Config.espTextSize
	if esp.textSize ~= textSize then
		esp.textSize = textSize
		esp.name.Size = textSize
		esp.distance.Size = textSize - 1
		esp.weapon.Size = textSize - 1
		esp.healthText.Size = textSize - 2
	end

	local rootPos, onScreen = currentCamera:WorldToViewportPoint(root.Position)
	if not onScreen then
		hideBody(esp)
		if Config.espArrows then
			drawArrow(esp, root.Position)
		else
			setShown(esp, "arrow", false)
		end
		return
	end
	setShown(esp, "arrow", false)

	local top = currentCamera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
	local bottom = currentCamera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))
	local height = math.abs(bottom.Y - top.Y)
	local width = height / 1.8
	local x, y = rootPos.X - width / 2, top.Y

	-- Box.
	local fullBox = Config.espBox and Config.espBoxStyle == "Full"
	setShown(esp, "box", fullBox)
	setShown(esp, "boxOutline", fullBox)
	if fullBox then
		local position, size = Vector2.new(x, y), Vector2.new(width, height)
		esp.box.Position, esp.box.Size = position, size
		esp.boxOutline.Position, esp.boxOutline.Size = position, size
	end

	setShown(esp, "fill", Config.espBoxFill)
	if Config.espBoxFill then
		esp.fill.Position, esp.fill.Size = Vector2.new(x, y), Vector2.new(width, height)
		if esp.fillAlpha ~= Config.espFillOpacity then
			esp.fillAlpha = Config.espFillOpacity
			esp.fill.Transparency = Config.espFillOpacity / 100
		end
	end

	if Config.espBox and Config.espBoxStyle == "Corner" then
		if not esp.cornersShown then
			esp.cornersShown = true
			for _, line in ipairs(esp.corners) do line.Visible = true end
		end
		drawCorners(esp.corners, x, y, width, height)
	elseif esp.cornersShown then
		esp.cornersShown = false
		for _, line in ipairs(esp.corners) do line.Visible = false end
	end

	-- Name and distance (text is only rewritten when it changes).
	setShown(esp, "name", Config.espName)
	if Config.espName then
		local displayName = player.DisplayName
		local nameMode = Config.espNameMode
		if nameMode == "Username" then
			displayName = player.Name
		elseif nameMode == "Both" and player.Name ~= displayName then
			displayName = displayName .. " (@" .. player.Name .. ")"
		end
		if esp.nameText ~= displayName then
			esp.nameText = displayName
			esp.name.Text = displayName
		end
		esp.name.Position = Vector2.new(rootPos.X, y - 16)
	end

	setShown(esp, "distance", Config.espDistance)
	if Config.espDistance then
		local meters = math.floor(distance)
		if esp.distanceValue ~= meters then
			esp.distanceValue = meters
			esp.distance.Text = "[" .. meters .. "m]"
		end
		esp.distance.Position = Vector2.new(rootPos.X, bottom.Y + 2)
	end

	-- Held item: the equipped tool, or a weapon attribute when the game keeps it there.
	local weaponOn = false
	if Config.espWeapon then
		if now - esp.weaponTime > 0.4 then
			esp.weaponTime = now
			local tool = character:FindFirstChildOfClass("Tool")
			local label = tool and tool.Name or character:GetAttribute("EquippedWeapon") or player:GetAttribute("EquippedWeapon")
			esp.weaponLabel = type(label) == "string" and label or ""
		end
		if esp.weaponLabel ~= "" then
			weaponOn = true
			if esp.weaponText ~= esp.weaponLabel then
				esp.weaponText = esp.weaponLabel
				esp.weapon.Text = esp.weaponLabel
			end
			esp.weapon.Position = Vector2.new(rootPos.X, bottom.Y + (Config.espDistance and 15 or 2))
		end
	end
	setShown(esp, "weapon", weaponOn)

	-- Health.

	setShown(esp, "healthBar", Config.espHealth)
	setShown(esp, "healthBack", Config.espHealth)
	if Config.espHealth then
		local barX, barBottom = x - 5, y + height
		esp.healthBack.From, esp.healthBack.To = Vector2.new(barX, barBottom), Vector2.new(barX, y)
		esp.healthBar.From = Vector2.new(barX, barBottom)
		esp.healthBar.To = Vector2.new(barX, barBottom - height * ratio)
		if esp.ratioValue ~= ratio then
			esp.ratioValue = ratio
			esp.healthBar.Color = Color3.fromRGB(255 * (1 - ratio), 255 * ratio, 0)
		end
	end

	setShown(esp, "healthText", Config.espHealthText)
	if Config.espHealthText then
		local health = math.floor(humanoid.Health)
		if esp.healthValue ~= health then
			esp.healthValue = health
			esp.healthText.Text = tostring(health)
		end
		esp.healthText.Position = Vector2.new(x - 22, y + height - height * ratio - 6)
	end

	-- Tracer.
	setShown(esp, "tracer", Config.espTracer)
	if Config.espTracer then
		local viewport = perFrame.viewport
		local origin = Vector2.new(viewport.X / 2, viewport.Y)
		if Config.espTracerOrigin == "Center" then
			origin = viewport / 2
		elseif Config.espTracerOrigin == "Cursor" then
			origin = perFrame.mouse
		end
		esp.tracer.From, esp.tracer.To = origin, Vector2.new(rootPos.X, bottom.Y)
	end

	-- Head dot.
	local headDotOn = false
	if Config.espHeadDot and head then
		local headPos, headOn = currentCamera:WorldToViewportPoint(head.Position)
		if headOn then
			headDotOn = true
			esp.headDot.Position = Vector2.new(headPos.X, headPos.Y)
			esp.headDot.Radius = math.max(height / 12 * Config.espHeadDotSize / 100, 2)
		end
	end
	setShown(esp, "headDot", headDotOn)

	-- Look direction.
	local lookOn = false
	if Config.espLookLine then
		local source = head or root
		local sourcePos = source.Position
		local fromPos, fromOn = currentCamera:WorldToViewportPoint(sourcePos)
		local toPos, toOn = currentCamera:WorldToViewportPoint(sourcePos + source.CFrame.LookVector * Config.espLookLength)
		if fromOn and toOn then
			lookOn = true
			esp.lookLine.From, esp.lookLine.To = Vector2.new(fromPos.X, fromPos.Y), Vector2.new(toPos.X, toPos.Y)
		end
	end
	setShown(esp, "lookLine", lookOn)

	-- Skeleton.
	local boneOn = esp.boneOn
	if Config.espSkeleton then
		refreshBones(esp, character, humanoid, now)
		local parts = esp.boneParts
		for index, line in ipairs(esp.bones) do
			local pair = parts[index]
			local visible = false
			if pair then
				local firstPos, firstOn = currentCamera:WorldToViewportPoint(pair[1].Position)
				local secondPos, secondOn = currentCamera:WorldToViewportPoint(pair[2].Position)
				if firstOn and secondOn then
					visible = true
					line.From, line.To = Vector2.new(firstPos.X, firstPos.Y), Vector2.new(secondPos.X, secondPos.Y)
				end
			end
			if boneOn[index] ~= visible then
				boneOn[index] = visible
				line.Visible = visible
			end
		end
	else
		for index, line in ipairs(esp.bones) do
			if boneOn[index] then
				boneOn[index] = false
				line.Visible = false
			end
		end
	end

	-- Chams.
	if Config.espChams then
		local highlight = esp.highlight
		if not highlight then
			highlight = Instance.new("Highlight")
			highlight.FillColor = Color3.fromRGB(255, 60, 60)
			highlight.OutlineColor = Color3.new(1, 1, 1)
			highlight.Parent = gethui and gethui() or coreGui
			esp.highlight = highlight
		end

		local fill = (Config.espVisColors or Config.espColorMode ~= "Palette") and color or Color3.fromRGB(255, 60, 60)
		if esp.chamsColor ~= fill then
			esp.chamsColor = fill
			highlight.FillColor = fill
		end
		if esp.fillOpacity ~= Config.chamsOpacity then
			esp.fillOpacity = Config.chamsOpacity
			highlight.FillTransparency = 1 - Config.chamsOpacity / 100
		end
		if esp.outlineOn ~= Config.chamsOutline then
			esp.outlineOn = Config.chamsOutline
			highlight.OutlineTransparency = Config.chamsOutline and 0 or 1
		end
		if esp.wallsOn ~= Config.chamsWalls then
			esp.wallsOn = Config.chamsWalls
			highlight.DepthMode = Config.chamsWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
		end
		if esp.chamsCharacter ~= character then
			esp.chamsCharacter = character
			highlight.Adornee = character
		end
		if not esp.chamsOn then
			esp.chamsOn = true
			highlight.Enabled = true
		end
	elseif esp.chamsOn then
		esp.chamsOn = false
		esp.highlight.Enabled = false
	end
end

---Runs every player through updateEsp. A failure on one player hides that player and is reported to runModule.
local function updateAllEsp(now)
	local failed, lastError
	for player, esp in pairs(espObjects) do
		local ok, err = pcall(updateEsp, player, esp, now)
		if not ok then
			failed, lastError = true, err
			pcall(hideEsp, esp)
		end
	end
	if failed then error(lastError, 0) end
end

local function espFeaturesOn()
	return Config.espBox or Config.espName or Config.espHealth or Config.espDistance
		or Config.espTracer or Config.espSkeleton or Config.espHeadDot or Config.espChams
		or Config.espArrows or Config.espHealthText or Config.espLookLine or Config.espBoxFill or Config.espWeapon
end

moduleCleanup.esp = function()
	for _, esp in pairs(espObjects) do hideEsp(esp) end
end

---Top-down radar that rotates with the camera.
local function updateRadar()
	local enabled = Config.radarEnabled
	radarBack.Visible, radarBorder.Visible, radarSelf.Visible = enabled, enabled, enabled

	if not enabled then
		if not radarCleared then
			radarCleared = true
			for _, esp in pairs(espObjects) do esp.radarDot.Visible = false end
		end
		return
	end
	radarCleared = false

	local size = Config.radarSize
	local viewport = perFrame.viewport
	local corner = Config.radarCorner
	local origin = Vector2.new(20, 80)
	if corner == "Top right" then
		origin = Vector2.new(viewport.X - size - 20, 240)
	elseif corner == "Bottom left" then
		origin = Vector2.new(20, viewport.Y - size - 20)
	elseif corner == "Bottom right" then
		origin = Vector2.new(viewport.X - size - 20, viewport.Y - size - 20)
	end
	local center = origin + Vector2.new(size / 2, size / 2)

	if radarBack.Transparency ~= Config.radarAlpha / 100 then radarBack.Transparency = Config.radarAlpha / 100 end
	radarBack.Position, radarBack.Size = origin, Vector2.new(size, size)
	radarBorder.Position, radarBorder.Size = origin, Vector2.new(size, size)

	-- Yaw only, so looking up or down doesn't skew the dots.
	local cameraCFrame = currentCamera.CFrame
	local look = cameraCFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then return end

	-- The marker for the local player points where the camera looks, straight up when the radar turns with the view.
	local facing = Config.radarRotate and Vector2.new(0, -1) or Vector2.new(flat.X, flat.Z).Unit
	local side = Vector2.new(-facing.Y, facing.X)
	radarSelf.PointA = center + facing * 6
	radarSelf.PointB = center - facing * 4 - side * 4
	radarSelf.PointC = center - facing * 4 + side * 4

	local yawFrame = Config.radarRotate and CFrame.lookAt(cameraCFrame.Position, cameraCFrame.Position + flat)
		or CFrame.new(cameraCFrame.Position)

	local scale = (size / 2) / Config.radarRange
	local half = size / 2 - 4

	for player, esp in pairs(espObjects) do
		local dot = esp.radarDot
		dot.Visible = false

		local character, _, root = getCharacterParts(player)
		if not (character and isEnemy(player)) then continue end

		local relative = yawFrame:PointToObjectSpace(root.Position)
		local offset = Vector2.new(relative.X, relative.Z) * scale
		offset = Vector2.new(math.clamp(offset.X, -half, half), math.clamp(offset.Y, -half, half))

		dot.Position = center + offset
		dot.Visible = true
	end
end

moduleCleanup.radar = function()
	radarBack.Visible, radarBorder.Visible, radarSelf.Visible = false, false, false
	for _, esp in pairs(espObjects) do esp.radarDot.Visible = false end
end

local function updateCrosshair()
	local shadow, shadowDot = crosshairLines.shadow, crosshairLines.shadowDot
	if not Config.crosshairEnabled then
		if crosshairShown then
			crosshairShown = false
			for _, line in ipairs(crosshairLines) do line.Visible = false end
			for _, line in ipairs(shadow) do line.Visible = false end
			crosshairDot.Visible = false
			shadowDot.Visible = false
		end
		return
	end
	crosshairShown = true

	local center = currentCamera.ViewportSize / 2
	local gap, length = Config.crosshairGap, Config.crosshairSize

	-- Opens up with the speed of the local character.
	if Config.crosshairDynamic then
		local _, _, root = getCharacterParts(localPlayer)
		local velocity = root and root.AssemblyLinearVelocity or Vector3.zero
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		crosshairLines.spread += (math.clamp(speed / 4, 0, 14) - crosshairLines.spread) * 0.2
		gap += crosshairLines.spread
	end

	local mode = Config.crosshairColor
	local color = ESP_COLOR
	if mode == "Rainbow" then
		color = Color3.fromHSV((os.clock() * 0.4) % 1, 0.8, 1)
	elseif mode == "Accent" then
		color = ACCENT
	elseif mode ~= "Palette" then
		color = crosshairLines.colors[mode] or ESP_COLOR
	end
	local alpha = Config.crosshairAlpha / 100
	local thickness = Config.crosshairThickness
	local outline = Config.crosshairOutline
	local restyle = crosshairLines.color ~= color or crosshairLines.alpha ~= alpha
	if restyle then
		crosshairLines.color, crosshairLines.alpha = color, alpha
		crosshairDot.Color, crosshairDot.Transparency = color, alpha
		for _, line in ipairs(crosshairLines) do line.Color, line.Transparency = color, alpha end
		for _, line in ipairs(shadow) do line.Transparency = alpha end
		shadowDot.Transparency = alpha
	end

	for index, direction in ipairs(CROSSHAIR_DIRECTIONS) do
		local line, back = crosshairLines[index], shadow[index]
		local on = not (Config.crosshairT and index == 3)
		line.Visible = on
		back.Visible = on and outline
		if on then
			local from, to = center + direction * gap, center + direction * (gap + length)
			line.From, line.To, line.Thickness = from, to, thickness
			if outline then back.From, back.To, back.Thickness = from, to, thickness + 2 end
		end
	end

	crosshairDot.Position = center
	crosshairDot.Visible = Config.crosshairDot
	shadowDot.Position = center
	shadowDot.Visible = Config.crosshairDot and outline
end

local function getPing()
	local ok, value = pcall(function()
		return statsService.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	return ok and value or 0
end

local function updatePing(now)
	if now - lastPingCheck < 0.5 then return end
	lastPingCheck = now
	pingValue = getPing()
end

local function updateWatermark(dt)
	fpsSmooth += (1 / math.max(dt, 0.0001) - fpsSmooth) * 0.05
	local now = os.clock()
	watermark.ensure(now)
	watermark.step(now)
	watermark.set(math.floor(fpsSmooth), math.floor(pingValue))
end

-- Runs on its own so a stopped module never takes the watermark with it.
table.insert(connections, runService.Heartbeat:Connect(function(dt)
	pcall(updateWatermark, dt)
end))

local FEATURE_FLAGS = {
	{ "Soft aim", "silentEnabled" }, { "Rage", "rageEnabled" }, { "Trigger", "triggerEnabled" },
	{ "Farm", "farmEnabled" }, { "Spin", "spinEnabled" },
	{ "AI", "aiPlay" }, { "Learning", "aiLearn" },
	{ "Rapid fire", "rapidFire" }, { "Anti aim", "antiAim" }, { "Hitbox", "hitboxEnabled" },
	{ "Fly", "flyEnabled" }, { "Noclip", "noclip" }, { "Slide", "slideEnabled" }, { "Glide", "glideEnabled" },
	{ "Air jump", "infJump" }, { "Bhop", "bhop" }, { "Air strafe", "airStrafe" }, { "Fullbright", "fullbright" },
}

local featureListShown, featureNext = false, 0

---Small list of the features that are currently on, top right.
local function updateFeatureList(now)
	if not Config.hudList then
		if featureListShown then
			featureListShown = false
			featureList.Visible = false
		end
		return
	end
	if now < featureNext then return end
	featureNext = now + 0.2

	local lines = {}
	if Config.aimEnabled and Config.aimActive then table.insert(lines, "Aimbot") end
	if Config.espEnabled and espFeaturesOn() then table.insert(lines, "ESP") end
	for _, entry in ipairs(FEATURE_FLAGS) do
		if Config[entry[2]] then table.insert(lines, entry[1]) end
	end

	featureListShown = #lines > 0
	featureList.Text = table.concat(lines, "\n")
	featureList.Position = Vector2.new(perFrame.viewport.X - 80, 20)
	featureList.Visible = featureListShown
end

local function updateTargetLine(mouse)
	local part = aimTargetPart
	if Config.aimTargetLine and part and part.Parent then
		local screenPos, onScreen = currentCamera:WorldToViewportPoint(part.Position)
		if onScreen then
			targetLine.From, targetLine.To, targetLine.Visible = mouse, Vector2.new(screenPos.X, screenPos.Y), true
			return
		end
	end
	targetLine.Visible = false
end

-- World visuals. Original values are saved on first touch and restored when a feature is turned off.
local world = { saved = {}, key = 0, nextTick = 0 }

local function worldSet(instance, property, value)
	local bucket = world.saved[instance]
	if not bucket then
		bucket = {}
		world.saved[instance] = bucket
	end
	if bucket[property] == nil then bucket[property] = instance[property] end
	if instance[property] ~= value then instance[property] = value end
end

local function worldRestore()
	for instance, bucket in pairs(world.saved) do
		for property, value in pairs(bucket) do
			pcall(function() instance[property] = value end)
		end
	end
	table.clear(world.saved)
	world.key = 0
end

local function updateWorld(now)
	local key = (Config.fullbright and 1 or 0) + (Config.noFog and 2 or 0)
		+ (Config.noPost and 4 or 0) + (Config.clockOverride and 8 or 0) + (Config.noShadows and 16 or 0)

	-- Feature set changed: put everything back, then re-apply what is still on.
	if key ~= world.key then
		worldRestore()
		world.key = key
		world.nextTick = 0
	end
	if key == 0 or now < world.nextTick then return end
	world.nextTick = now + 0.25

	if Config.fullbright then
		worldSet(lightingService, "Brightness", 2)
		worldSet(lightingService, "GlobalShadows", false)
		worldSet(lightingService, "Ambient", Color3.fromRGB(178, 178, 178))
		worldSet(lightingService, "OutdoorAmbient", Color3.fromRGB(178, 178, 178))
	end

	if Config.noFog then
		worldSet(lightingService, "FogEnd", 1e6)
		local atmosphere = lightingService:FindFirstChildOfClass("Atmosphere")
		if atmosphere then
			worldSet(atmosphere, "Density", 0)
			worldSet(atmosphere, "Haze", 0)
		end
	end

	if Config.noPost then
		for _, parent in ipairs({ lightingService, currentCamera }) do
			for _, child in ipairs(parent:GetChildren()) do
				if child:IsA("PostEffect") and child ~= hooks.grade then worldSet(child, "Enabled", false) end
			end
		end
	end

	if Config.clockOverride then
		worldSet(lightingService, "ClockTime", Config.clockTime)
	end

	if Config.noShadows then
		worldSet(lightingService, "GlobalShadows", false)
	end
end

-- Rivals movement. Velocity is written right before physics. If the game's own controller throws it away,
-- the missing distance is added as a small displacement that is checked against walls.
local JUMP_COOLDOWN = 0.1
local JUMP_REPEAT = 0.12
local GROUND_RAY_PADDING = 0.8
local SLIDE_JUMP_WINDOW = 0.25
local SLIDE_RAMP = 500
local GROUND_BLEED = 30
local ARC_TIME = 0.8
local CARRY_TIME = 1.5
local MEASURE_WINDOW = 0.08
local BODY_RADIUS = 1.6
local HEAD_CLEARANCE = 3.2
local MAX_NUDGE = 4

local moveParams = RaycastParams.new()
moveParams.FilterType = Enum.RaycastFilterType.Exclude

-- got/want/extra/span: how far the character moved along what was written, over a short running window.
local drive = {
	root = nil, clock = 0, position = Vector3.zero, nudge = Vector3.zero,
	expectFlat = nil, expectUp = nil,
	got = 0, want = 0, extra = 0, span = 0, gotUp = 0, wantUp = 0, spanUp = 0,
	arc = nil, carry = nil, airJumps = 0,
	jumpQueued = 0, lastPress = 0,
	slideArmed = false, slideWasHeld = false, slideHeading = Vector3.zero, slideNow = 0,
}

---Drop the vertical component of a vector.
local function flatten(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

---Unit vector that never produces NaN.
local function safeUnit(vector)
	local magnitude = vector.Magnitude
	return magnitude > 0.001 and vector / magnitude or Vector3.zero
end

---Movement direction from held keys relative to the camera yaw, falling back to the humanoid.
local function getWishDirection(humanoid)
	if ai.wish and Config.aiPlay and not ai.viaKeys then return ai.wish end
	if userInputService:GetFocusedTextBox() then return Vector3.zero end

	local right = safeUnit(flatten(currentCamera.CFrame.RightVector))
	if right == Vector3.zero then return Vector3.zero end
	local forward = Vector3.yAxis:Cross(right)

	local move = Vector3.zero
	if heldKeys[Enum.KeyCode.W] then move += forward end
	if heldKeys[Enum.KeyCode.S] then move -= forward end
	if heldKeys[Enum.KeyCode.D] then move += right end
	if heldKeys[Enum.KeyCode.A] then move -= right end

	if move.Magnitude < 0.001 then
		return safeUnit(flatten(humanoid.MoveDirection))
	end
	return move.Unit
end

---Grounded check that doesn't rely on FloorMaterial alone, since Rivals uses its own controller.
local function isGrounded(character, humanoid, root, velocity)
	if velocity.Y > 10 then return false end
	if humanoid.FloorMaterial ~= Enum.Material.Air then return true end

	moveParams.FilterDescendantsInstances = { character }
	local reach = root.Size.Y / 2 + math.max(humanoid.HipHeight, 2) + GROUND_RAY_PADDING
	return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), moveParams) ~= nil
end

---Source-style acceleration: only adds speed along the wish direction, up to wishSpeed.
local function accelerate(horizontal, wish, wishSpeed, accel, dt)
	local addSpeed = wishSpeed - horizontal:Dot(wish)
	if addSpeed <= 0 then return horizontal end
	return horizontal + wish * math.min(accel * wishSpeed * dt, addSpeed)
end

---Remember a jump press. The space key and JumpRequest both end up here, and a held key only counts once.
local function queueJump()
	local now = os.clock()
	local fresh = now - drive.lastPress > JUMP_REPEAT
	drive.lastPress = now
	if fresh then drive.jumpQueued = now end
end

local function slideKeyHeld()
	for key in pairs(SLIDE_KEYS) do
		if heldKeys[key] then return true end
	end
	return hooks.touch.slide or (binds.slide ~= Enum.KeyCode.Unknown and heldKeys[binds.slide] == true)
end

---The jump speed the character would get from the game itself.
local function naturalJumpPower(humanoid)
	local power = humanoid.UseJumpPower and humanoid.JumpPower or math.sqrt(2 * workspace.Gravity * humanoid.JumpHeight)
	return power > 20 and power or 50
end

local function forgetMeasurement()
	drive.got, drive.want, drive.extra, drive.span = 0, 0, 0, 0
	drive.gotUp, drive.wantUp, drive.spanUp = 0, 0, 0
end

---Extra displacement on top of whatever the game did. Walls shorten it, normal physics is untouched.
local function displace(root, wanted)
	local length = wanted.Magnitude
	if length < 0.005 then return Vector3.zero end

	local direction = wanted / length
	length = math.min(length, MAX_NUDGE)
	local clearance = BODY_RADIUS + (HEAD_CLEARANCE - BODY_RADIUS) * math.abs(direction.Y)

	moveParams.FilterDescendantsInstances = { root.Parent }
	local hit = workspace:Raycast(root.Position, direction * (length + clearance), moveParams)
	if hit then
		length = math.min(length, math.max(hit.Distance - clearance, 0))
	end
	if length < 0.005 then return Vector3.zero end

	local step = direction * length
	root.CFrame = root.CFrame + step
	return step
end

local function startArc(power, now)
	drive.arc = { start = now, power = power }
	lastJump = now
end

---Keep the speed of a slide through the jump that ends it.
local function startCarry(now, speed)
	local multiplier = Config.slideJumpBoost / 100
	if multiplier <= 1 then return end

	local carried = math.max(slideMomentum, speed) * multiplier
	if Config.speedLimit then carried = math.min(carried, Config.speedLimitValue) end
	drive.carry = { start = now, speed = carried, heading = drive.slideHeading }
end

---What a jump press does. Normal ground jumps stay with the game unless jump power or bhop is on.
local function handleJump(humanoid, grounded, now, auto, speed)
	if grounded then
		drive.airJumps = 0
		lastJump = now

		if Config.slideEnabled and (sliding or now - lastSlideTime < SLIDE_JUMP_WINDOW) then
			startCarry(now, speed)
			sliding = false
			lastSlideTime = 0
			drive.slideArmed = false
		end

		if auto or Config.jumpEnabled then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			startArc(Config.jumpEnabled and Config.jumpPower or naturalJumpPower(humanoid), now)
		end
		return
	end

	if not Config.infJump then return end
	if Config.airJumps > 0 and drive.airJumps >= Config.airJumps then return end

	drive.airJumps += 1
	sliding = false
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	startArc(Config.airJumpPower, now)
end

local function updateMovement(dt, now)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) or humanoid.Health <= 0 then
		sliding = false
		drive.root, drive.arc, drive.carry, drive.sprintBase = nil, nil, nil, nil
		return
	end

	-- Holding the sprint key swaps in the sprint speed, and puts the game's own speed back afterwards.
	local walkOn, walkSpeed = Config.walkEnabled, Config.walkSpeed
	if Config.sprintEnabled and (hooks.held(binds.sprint) or hooks.touch.sprint) and not userInputService:GetFocusedTextBox() then
		if not drive.sprintBase then drive.sprintBase = humanoid.WalkSpeed end
		walkOn, walkSpeed = true, Config.sprintSpeed
	elseif drive.sprintBase then
		if not Config.walkEnabled then humanoid.WalkSpeed = drive.sprintBase end
		drive.sprintBase = nil
	end

	if walkOn then
		humanoid.WalkSpeed = walkSpeed
	end

	if Config.jumpEnabled then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.jumpPower
	end

	local velocity = root.AssemblyLinearVelocity

	if Config.flyEnabled then
		sliding = false
		drive.root, drive.arc, drive.carry = nil, nil, nil

		local view = currentCamera.CFrame
		local move = Vector3.zero
		if heldKeys[Enum.KeyCode.W] then move += view.LookVector end
		if heldKeys[Enum.KeyCode.S] then move -= view.LookVector end
		if heldKeys[Enum.KeyCode.D] then move += view.RightVector end
		if heldKeys[Enum.KeyCode.A] then move -= view.RightVector end

		-- No movement keys: follow the thumbstick, forward goes where the camera looks.
		if move.Magnitude < 0.001 then
			local push = flatten(humanoid.MoveDirection)
			local right = safeUnit(flatten(view.RightVector))
			if push.Magnitude > 0.05 and right ~= Vector3.zero then
				move += view.LookVector * push:Dot(Vector3.yAxis:Cross(right)) + view.RightVector * push:Dot(right)
			end
		end

		if heldKeys[Enum.KeyCode.Space] or hooks.touch.up then move += Vector3.yAxis end
		if heldKeys[Enum.KeyCode.LeftShift] or hooks.touch.down then move -= Vector3.yAxis end

		local target = move.Magnitude > 0 and move.Unit * Config.flySpeed or Vector3.zero
		if Config.flyVertical ~= 100 then
			target = Vector3.new(target.X, target.Y * Config.flyVertical / 100, target.Z)
		end
		local alpha = Config.flyMode == "Smooth" and (1 - math.exp(-10 * dt)) or 1
		root.AssemblyLinearVelocity = velocity:Lerp(target, alpha)
		return
	end

	-- How well the last steps followed what was written. The engine simulates in small fixed steps, so one
	-- frame can hold a different number of them, a short running average keeps that from looking like a problem.
	if drive.root ~= root then
		drive.arc, drive.carry, drive.airJumps = nil, nil, 0
	end
	local elapsed = now - drive.clock
	local measured = drive.root == root and elapsed > 0.001 and elapsed < 0.25
	local moved = Vector3.zero
	if measured then
		moved = root.Position - drive.position
		if moved.Magnitude > elapsed * 400 then measured = false end
	end

	if measured then
		local keep = math.exp(-elapsed / MEASURE_WINDOW)
		drive.got, drive.want, drive.extra, drive.span = drive.got * keep, drive.want * keep, drive.extra * keep, drive.span * keep
		drive.gotUp, drive.wantUp, drive.spanUp = drive.gotUp * keep, drive.wantUp * keep, drive.spanUp * keep

		local expected = drive.expectFlat
		if expected then
			local direction = safeUnit(expected)
			drive.got += flatten(moved):Dot(direction)
			drive.extra += drive.nudge:Dot(direction)
			drive.want += expected.Magnitude * elapsed
			drive.span += elapsed
		end

		local expectedUp = drive.expectUp
		if expectedUp then
			drive.gotUp += moved.Y
			drive.wantUp += (expectedUp - workspace.Gravity * elapsed / 2) * elapsed
			drive.spanUp += elapsed
		end
	else
		forgetMeasurement()
	end

	-- A write is being ignored when the character keeps moving clearly slower than what was written.
	local ignoredFlat = drive.expectFlat ~= nil and drive.span > 0.01 and drive.got < drive.want * 0.85 - drive.span
	local ignoredUp = drive.expectUp ~= nil and drive.spanUp > 0.01 and drive.gotUp < drive.wantUp * 0.7 - 3 * drive.spanUp

	local typing = userInputService:GetFocusedTextBox() ~= nil
	local wish = getWishDirection(humanoid)
	local grounded = isGrounded(character, humanoid, root, velocity)
	if grounded then drive.airJumps = 0 end

	-- While writes are ignored the part's velocity says nothing about our speed, the last target does,
	-- unless something is blocking the character.
	local horizontal = flatten(velocity)
	if ignoredFlat and drive.got + drive.extra >= drive.want * 0.5 then
		horizontal = drive.expectFlat
	end
	local speed = horizontal.Magnitude

	-- Jumps: presses are queued by the input handlers, bunny hop re-jumps on the first grounded frame.
	local queued = not typing and drive.jumpQueued > 0 and now - drive.jumpQueued < 0.2
	local auto = false
	drive.jumpQueued = 0
	if not queued and Config.bhop and not typing and grounded and (heldKeys[Enum.KeyCode.Space] or hooks.touch.jump) then
		queued, auto = true, true
	end
	if not queued and ai.jumpNow and grounded then
		queued, auto = true, true
	end
	ai.jumpNow = false
	if queued and now - lastJump > JUMP_COOLDOWN then
		handleJump(humanoid, grounded, now, auto, speed)
	end

	-- Slide: starts on a fresh press of the slide key, ramps up, decays, and steers toward the move keys.
	local slideHeld = Config.slideEnabled and not typing and slideKeyHeld()
	if slideHeld and not drive.slideWasHeld then drive.slideArmed = true end
	if not slideHeld then drive.slideArmed = false end
	drive.slideWasHeld = slideHeld

	local boost = nil
	if drive.slideArmed and grounded and wish ~= Vector3.zero then
		local floorSpeed = walkOn and walkSpeed or 16
		if not sliding then
			sliding = true
			slideMomentum = math.max(speed, Config.slideSpeed)
			drive.slideNow = speed
		end
		lastSlideTime = now

		slideMomentum = math.max(slideMomentum - Config.slideDecay * dt, floorSpeed)
		drive.slideNow = math.min(drive.slideNow + SLIDE_RAMP * dt, slideMomentum)

		if slideMomentum > floorSpeed + 0.5 then
			local heading = speed > 1 and horizontal / speed or wish
			heading = safeUnit(heading:Lerp(wish, 1 - math.exp(-Config.slideSteer * dt)))
			if heading == Vector3.zero then heading = wish end

			drive.slideHeading = heading
			boost = heading * drive.slideNow
		else
			sliding = false
			drive.slideArmed = false
		end
	else
		sliding = false
	end

	-- Slide jump: hold the slide's speed in the air, in whatever direction the character is moving.
	local carry = drive.carry
	if carry then
		local age = now - carry.start
		if age > CARRY_TIME or (grounded and age > 0.2) or (age > 0.15 and speed < carry.speed * 0.4) then
			drive.carry = nil
		else
			carry.speed = math.max(carry.speed - 3 * dt, 0)
			local base = boost or horizontal
			if base.Magnitude < carry.speed then
				local direction = safeUnit(base)
				if direction == Vector3.zero then
					direction = wish ~= Vector3.zero and wish or carry.heading
				end
				base = direction * carry.speed
			end
			boost = base
		end
	end

	-- Ground speed only ever adds speed along the move direction, so slide hop momentum survives landing.
	-- Speed the game doesn't keep by itself bleeds off here, otherwise it would never slow down again.
	if not boost and grounded and walkOn and wish ~= Vector3.zero then
		local current = horizontal
		if ignoredFlat and speed > walkSpeed then
			current = horizontal * (math.max(speed - GROUND_BLEED * dt, walkSpeed) / speed)
		end
		boost = accelerate(current, wish, walkSpeed, Config.walkResponse, dt)
	end

	if not boost and grounded and ai.wish and Config.aiPlay and not ai.viaKeys then
		boost = accelerate(horizontal, ai.wish, ai.speed, Config.walkResponse, dt)
	end

	-- Air strafe: Source-style air acceleration, turn your camera while holding A or D to gain speed.
	if not grounded and Config.airStrafe and wish ~= Vector3.zero then
		boost = accelerate(boost or horizontal, wish, Config.airWish, Config.airAccel, dt)
	end

	if boost and Config.speedLimit and boost.Magnitude > Config.speedLimitValue then
		boost = boost.Unit * Config.speedLimitValue
	end

	local limited = nil
	if not boost and Config.speedLimit and speed > Config.speedLimitValue then
		limited = horizontal.Unit * Config.speedLimitValue
	end

	-- Jump arc: hold the upward speed a normal jump would have, for as long as it would last.
	local wantedUp, writeY = nil, velocity.Y
	local arc = drive.arc
	if arc then
		local rising = arc.power - workspace.Gravity * (now - arc.start)
		if rising <= 0 or now - arc.start > ARC_TIME then
			drive.arc = nil
		else
			wantedUp = rising
			if rising > writeY then writeY = rising end
		end
	end

	local flat = boost or limited
	if flat or wantedUp then
		local keep = flat or flatten(velocity)
		root.AssemblyLinearVelocity = Vector3.new(keep.X, writeY, keep.Z)
	end

	-- When the writes did not turn into movement, add the missing distance as a displacement.
	-- The amount comes from the last step, the running average above only decides whether to do it.
	local nudge = Vector3.zero
	if Config.moveAssist and measured then
		if ignoredFlat and boost then
			local direction = safeUnit(boost)
			local missing = boost.Magnitude - flatten(moved):Dot(direction) / elapsed
			if missing > 1 then nudge += direction * (missing * dt) end
		end

		if ignoredUp and wantedUp then
			local missing = wantedUp - moved.Y / elapsed
			if missing > 1 then nudge += Vector3.new(0, missing * dt, 0) end
		end

		nudge = displace(root, nudge)
	end

	drive.expectFlat = boost
	drive.expectUp = wantedUp and writeY or nil
	drive.nudge = nudge
	drive.root, drive.clock, drive.position = root, now, root.Position
end

moduleCleanup.movement = function()
	sliding = false
	drive.arc, drive.carry, drive.root = nil, nil, nil
	drive.sprintBase = nil
end

-- AI. Learns movement and aim habits from other players, adjusts from its own results, and keeps its brain on disk.
;(function()
	local FOLDER = "SpriteRivalsAI"
	local AUTOLOAD = FOLDER .. "/autoload.txt"
	local MAX_TEXT = 600000
	local ACTIONS = 5
	local MAX_KEYS = 40

	local function newBrain(name)
		return {
			version = 1, name = name,
			policy = {}, jump = {}, q = {}, keys = {}, occ = {},
			aim = { rate = 0, error = 0, n = 0, m = 0 },
			stats = { samples = 0, watched = 0, played = 0, kills = 0, deaths = 0, dealt = 0, taken = 0 },
		}
	end
	ai.brain = newBrain("default")

	local function cleanName(name)
		local clean = string.gsub(name or "", "[^%w_%-]", "")
		clean = string.sub(clean, 1, 32)
		return clean ~= "" and clean or "default"
	end

	local function cleanList(list, size, low, high)
		if type(list) ~= "table" then return nil end
		local out = {}
		for index = 1, size do
			local value = tonumber(list[index])
			if not value or value ~= value or value < low or value > high then return nil end
			out[index] = value
		end
		return out
	end

	local function clampStat(value, high)
		local number = tonumber(value) or 0
		if number ~= number then number = 0 end
		return math.clamp(number, 0, high)
	end

	-- Press counts or time spent per situation: "c<distance>_<air>" rows, plus "g" for everything.
	local function cleanStates(source)
		local out = {}
		if type(source) ~= "table" then return out end

		local count = 0
		for state, value in pairs(source) do
			if type(state) == "string" and count < 14 and (state == "g" or string.match(state, "^c%d_%d$")) then
				out[state] = clampStat(value, 1e6)
				count += 1
			end
		end
		return out
	end

	-- Imported text is untrusted, so only known shapes with sane numbers get through.
	local function sanitize(data)
		if type(data) ~= "table" or type(data.policy) ~= "table" then return nil end
		local clean = newBrain(cleanName(data.name))

		local entries = 0
		for key, list in pairs(data.policy) do
			if type(key) == "string" and #key <= 10 and entries < 400 then
				local counts = cleanList(list, ACTIONS, 0, 1e6)
				if counts then
					clean.policy[key] = counts
					entries += 1
				end
			end
		end

		if type(data.jump) == "table" then
			for key, list in pairs(data.jump) do
				local counts = type(key) == "string" and #key <= 10 and cleanList(list, 2, 0, 1e6)
				if counts then clean.jump[key] = counts end
			end
		end

		if type(data.q) == "table" then
			for key, list in pairs(data.q) do
				local values = type(key) == "string" and #key <= 10 and cleanList(list, ACTIONS, -3, 3)
				if values then clean.q[key] = values end
			end
		end

		if type(data.aim) == "table" then
			for field in pairs(clean.aim) do
				clean.aim[field] = clampStat(data.aim[field], 5000)
			end
		end
		if type(data.stats) == "table" then
			for field in pairs(clean.stats) do
				clean.stats[field] = clampStat(data.stats[field], 1e9)
			end
		end

		clean.occ = cleanStates(data.occ)
		if type(data.keys) == "table" then
			local known = 0
			for name, entry in pairs(data.keys) do
				if known < MAX_KEYS and type(name) == "string" and type(entry) == "table" and ai.keyOk(name) then
					local hold = tonumber(entry.hold) or 0.1
					clean.keys[name] = {
						n = clampStat(entry.n, 1e9), h = clampStat(entry.h, 1e6),
						hold = math.clamp(hold == hold and hold or 0.1, 0.02, 6),
						p = cleanStates(entry.p), o = cleanStates(entry.o),
					}
					known += 1
				end
			end
		end
		return clean
	end

	local function merge(into, from)
		for key, counts in pairs(from.policy) do
			local list = into.policy[key]
			if list then
				for index = 1, ACTIONS do list[index] += counts[index] end
			else
				into.policy[key] = table.clone(counts)
			end
		end

		for key, counts in pairs(from.jump) do
			local list = into.jump[key]
			if list then
				list[1] += counts[1]
				list[2] += counts[2]
			else
				into.jump[key] = table.clone(counts)
			end
		end

		for key, values in pairs(from.q) do
			local list = into.q[key]
			if list then
				for index = 1, ACTIONS do list[index] = (list[index] + values[index]) / 2 end
			else
				into.q[key] = table.clone(values)
			end
		end

		for state, value in pairs(from.occ) do
			into.occ[state] = (into.occ[state] or 0) + value
		end
		local known = 0
		for _ in pairs(into.keys) do known += 1 end
		for name, entry in pairs(from.keys) do
			local mine = into.keys[name]
			if mine then
				local weight = mine.h + entry.h
				if weight > 0 then mine.hold = (mine.hold * mine.h + entry.hold * entry.h) / weight end
				mine.h, mine.n = weight, mine.n + entry.n
				for state, value in pairs(entry.p) do mine.p[state] = (mine.p[state] or 0) + value end
				for state, value in pairs(entry.o) do mine.o[state] = (mine.o[state] or 0) + value end
			elseif known < MAX_KEYS then
				into.keys[name] = {
					n = entry.n, h = entry.h, hold = entry.hold,
					p = table.clone(entry.p), o = table.clone(entry.o),
				}
				known += 1
			end
		end

		local a, b = into.aim, from.aim
		local n, m = a.n + b.n, a.m + b.m
		if n > 0 then a.error = (a.error * a.n + b.error * b.n) / n end
		if m > 0 then a.rate = (a.rate * a.m + b.rate * b.m) / m end
		a.n, a.m = n, m

		for field, value in pairs(from.stats) do
			into.stats[field] += value
		end
	end

	local function brainPath(name)
		return FOLDER .. "/" .. name .. ".json"
	end

	function ai.saveBrain(name, keepAutoload)
		name = cleanName(name or ai.brain.name)
		local brain = ai.brain
		local ok = pcall(function()
			if not compat.isfolder(FOLDER) then compat.makefolder(FOLDER) end
			compat.writefile(brainPath(name), httpService:JSONEncode(brain))
			if not keepAutoload then compat.writefile(AUTOLOAD, name) end
		end)
		if not keepAutoload then
			-- A failed save waits for the next interval too, instead of retrying every frame.
			ai.lastSave = os.clock()
			if ok then
				brain.name = name
				ai.dirty = false
			end
		end
		return ok, name
	end

	function ai.loadBrain(name)
		name = cleanName(name)
		local clean
		pcall(function()
			local path = brainPath(name)
			if not compat.isfile(path) then return end
			local text = compat.readfile(path)
			if #text > MAX_TEXT then return end
			clean = sanitize(httpService:JSONDecode(text))
		end)
		if not clean then return false end

		clean.name = name
		ai.brain, ai.dirty, ai.lastSave = clean, false, os.clock()
		pcall(compat.writefile, AUTOLOAD, name)
		return true
	end

	function ai.listBrains()
		local names = {}
		pcall(function()
			if not compat.isfolder(FOLDER) then return end
			for _, path in ipairs(compat.listfiles(FOLDER)) do
				local name = string.match(path, "([^/\\]+)%.json$")
				if name then table.insert(names, name) end
			end
		end)
		table.sort(names)
		return names
	end

	function ai.exportBrain()
		return httpService:JSONEncode(ai.brain)
	end

	-- Imported data is added to the current brain, so several pro packs can be combined.
	function ai.importBrain(text)
		if type(text) ~= "string" or text == "" or #text > MAX_TEXT then return false end
		local ok, data = pcall(function() return httpService:JSONDecode(text) end)
		local clean = ok and sanitize(data)
		if not clean then return false end
		if next(clean.policy) == nil and next(clean.jump) == nil and next(clean.q) == nil and next(clean.keys) == nil then
			return false
		end

		merge(ai.brain, clean)
		ai.dirty = true
		return true
	end

	function ai.fetchBrain(url)
		if type(url) ~= "string" or string.sub(url, 1, 8) ~= "https://" then return false end
		local ok, response = pcall(request, { Url = url, Method = "GET" })
		if not ok or type(response) ~= "table" or response.StatusCode ~= 200 then return false end
		return ai.importBrain(response.Body)
	end

	-- The old brain is written next to the new one first, so a stray click never loses progress.
	function ai.resetBrain()
		if ai.dirty or next(ai.brain.policy) ~= nil then
			ai.saveBrain(ai.brain.name .. "_backup", true)
		end
		ai.brain = newBrain(ai.brain.name)
		ai.dirty = false
		table.clear(ai.history)
	end

	-- Clears the counters only, what was learned stays.
	function ai.resetStats()
		ai.brain.stats = { samples = 0, watched = 0, played = 0, kills = 0, deaths = 0, dealt = 0, taken = 0 }
		ai.dirty = true
	end

	-- Removes a saved brain file. The brain in memory is untouched.
	function ai.deleteBrain(name)
		name = cleanName(name)
		local path = brainPath(name)
		local ok, removed = pcall(function()
			if not compat.isfile(path) then return false end
			compat.delfile(path)
			return true
		end)
		return ok and removed == true, name
	end

	function ai.autoload()
		local ok, name = pcall(function()
			if compat.isfile(AUTOLOAD) then return cleanName(compat.readfile(AUTOLOAD)) end
			return nil
		end)
		return ok and name ~= nil and ai.loadBrain(name)
	end

	function ai.setNames(text)
		table.clear(ai.names)
		for entry in string.gmatch(string.lower(text or ""), "[^,;%s]+") do
			table.insert(ai.names, entry)
		end
		ai.prosUntil = 0
	end

	-- Actions are relative to the nearest enemy: 1 forward, 2 back, 3 left, 4 right, 5 stand still.
	local AI_TICK = 0.1
	local HISTORY = 12
	local DEFAULT_PRIOR = { 0.25, 0.10, 0.28, 0.28, 0.09 }
	local EMPTY = { 0, 0, 0, 0, 0 }
	local DIST_EDGES = { 8, 20, 40, 80 }
	local STAT_NAMES = { "kills", "eliminations", "elims", "wins", "score", "points" }

	local function sumList(list)
		return list[1] + list[2] + list[3] + list[4] + list[5]
	end

	-- Full state, a coarser fallback state, and the distance bucket.
	local function stateKeys(distance, airborne, health, previous)
		local bin = #DIST_EDGES + 1
		for index, edge in ipairs(DIST_EDGES) do
			if distance < edge then
				bin = index
				break
			end
		end

		local air = airborne and 1 or 0
		local hp = health > 0.66 and 1 or (health > 0.33 and 2 or 3)
		return bin .. "_" .. air .. "_" .. hp .. "_" .. previous, "c" .. bin .. "_" .. air, bin
	end

	local function bump(policy, key, action)
		local list = policy[key]
		if not list then
			list = { 0, 0, 0, 0, 0 }
			policy[key] = list
		end
		list[action] += 1
		if sumList(list) > 4000 then
			for index = 1, 5 do list[index] *= 0.5 end
		end
	end

	local function classify(velocity, toFoe)
		local flat = flatten(velocity)
		if flat.Magnitude < 2.5 then return 5 end

		local radial = flat:Dot(toFoe)
		local side = flat:Dot(Vector3.new(-toFoe.Z, 0, toFoe.X))
		if math.abs(radial) >= math.abs(side) then return radial > 0 and 1 or 2 end
		return side > 0 and 4 or 3
	end

	-- Replicated floor data is unreliable for other players, so vertical speed and a short ray back it up.
	local function isAirborne(character, humanoid, root, vertical)
		if math.abs(vertical) > 8 then return true end
		if humanoid.FloorMaterial ~= Enum.Material.Air then return false end

		moveParams.FilterDescendantsInstances = { character }
		local reach = root.Size.Y / 2 + math.max(humanoid.HipHeight, 2) + 1.2
		return workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), moveParams) == nil
	end

	-- The closest enemy, its distance and who it is. `skip` maps players to a time until which they do not count.
	local function foeFor(player, root, skip)
		local best, bestDist, bestPlayer
		local now = skip and os.clock() or 0
		for _, other in ipairs(getPlayers()) do
			if other == player then continue end
			if Config.teamCheck and player.Team ~= nil and player.Team == other.Team then continue end
			if skip and (skip[other] or 0) > now then continue end

			local _, _, otherRoot = getCharacterParts(other)
			if not otherRoot then continue end

			local distance = (otherRoot.Position - root.Position).Magnitude
			if not bestDist or distance < bestDist then best, bestDist, bestPlayer = otherRoot, distance, other end
		end
		return best, bestDist, bestPlayer
	end

	local function statOf(player)
		local folder = player:FindFirstChild("leaderstats")
		if not folder then return nil end
		for _, wanted in ipairs(STAT_NAMES) do
			for _, child in ipairs(folder:GetChildren()) do
				if string.lower(child.Name) == wanted and type(child.Value) == "number" then return child.Value end
			end
		end
		return nil
	end

	local function nameMatches(player)
		local name, display = string.lower(player.Name), string.lower(player.DisplayName or "")
		for _, entry in ipairs(ai.names) do
			if string.sub(name, 1, #entry) == entry or string.sub(display, 1, #entry) == entry then return true end
		end
		return false
	end

	local function pickPros(now)
		if now < ai.prosUntil then return ai.pros end
		ai.prosUntil = now + 3

		local list = {}
		local source = Config.aiSource
		if source == "Me" then
			list[1] = localPlayer
		elseif source == "Named players" then
			for _, player in ipairs(getPlayers()) do
				if player ~= localPlayer and nameMatches(player) then table.insert(list, player) end
			end
		else
			local ranked = {}
			for _, player in ipairs(getPlayers()) do
				if player == localPlayer then continue end
				if source == "Everyone" then
					table.insert(list, player)
				else
					local value = statOf(player)
					if value then table.insert(ranked, { player = player, value = value }) end
				end
			end

			if source ~= "Everyone" then
				table.sort(ranked, function(a, b) return a.value > b.value end)
				for index = 1, math.min(Config.aiPros, #ranked) do table.insert(list, ranked[index].player) end
				-- Without any kill stat there is nobody to rank, so everyone counts.
				if #ranked == 0 then
					for _, player in ipairs(getPlayers()) do
						if player ~= localPlayer then table.insert(list, player) end
					end
				end
			end
		end

		ai.pros = list
		return list
	end

	local function learnAim(memory, root, toFoe, elapsed)
		local look = safeUnit(flatten(root.CFrame.LookVector))
		if look == Vector3.zero then return end

		local sign = look:Cross(toFoe).Y >= 0 and 1 or -1
		local error = math.deg(math.acos(math.clamp(look:Dot(toFoe), -1, 1))) * sign
		if math.abs(error) > 100 then
			memory.error = nil
			return
		end

		local aim = ai.brain.aim
		aim.n += 1
		aim.error += (math.abs(error) - aim.error) / math.min(aim.n, 200)

		local previous = memory.error
		memory.error = error
		if previous and elapsed < 0.3 and math.abs(error) > 5 then
			local speed = math.abs(error - previous) / elapsed
			if speed < 1500 then
				aim.m += 1
				aim.rate += (speed - aim.rate) / math.min(aim.m, 200)
			end
		end
	end

	local function sampleOne(player, now)
		local character, humanoid, root = getCharacterParts(player)
		if not root then
			ai.seen[player] = nil
			return
		end

		local position = root.Position
		local memory = ai.seen[player]
		if not memory or memory.root ~= root then
			ai.seen[player] = { root = root, position = position, time = now, prev = 5, grounded = true }
			return
		end

		local elapsed = now - memory.time
		if elapsed < AI_TICK * 0.5 then return end

		local velocity = (position - memory.position) / elapsed
		memory.position, memory.time = position, now
		if elapsed > 0.6 or velocity.Magnitude > 120 then
			memory.prev, memory.error = 5, nil
			return
		end

		local foe, distance = foeFor(player, root)
		if not foe or distance > Config.aiWatchRange then
			memory.prev, memory.error = 5, nil
			return
		end

		local toFoe = safeUnit(flatten(foe.Position - position))
		if toFoe == Vector3.zero then return end

		local air = isAirborne(character, humanoid, root, velocity.Y)
		local action = classify(velocity, toFoe)
		local health = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
		local full, coarse, bin = stateKeys(distance, air, health, memory.prev)

		local brain = ai.brain
		bump(brain.policy, full, action)
		bump(brain.policy, coarse, action)
		bump(brain.policy, "g", action)

		if memory.grounded then
			local key = bin .. "_" .. memory.prev
			local entry = brain.jump[key]
			if not entry then
				entry = { 0, 0 }
				brain.jump[key] = entry
			end
			entry[2] += 1
			if air and velocity.Y > 12 then entry[1] += 1 end
		end

		learnAim(memory, root, toFoe, elapsed)
		memory.grounded, memory.prev = not air, action

		brain.stats.samples += 1
		brain.stats.watched += elapsed
		ai.dirty = true
	end

	local function observe(now)
		for _, player in ipairs(pickPros(now)) do
			sampleOne(player, now)
		end
		for player in pairs(ai.seen) do
			if player.Parent == nil then ai.seen[player] = nil end
		end
	end

	-- Hierarchical smoothing: the exact state, backed by the distance state, backed by everything seen.
	local function distribution(full, coarse)
		local policy = ai.brain.policy
		local global, near, exact = policy.g or EMPTY, policy[coarse] or EMPTY, policy[full] or EMPTY
		local globalTotal, nearTotal, exactTotal = sumList(global), sumList(near), sumList(exact)

		local result = {}
		for index = 1, 5 do
			local pg = (global[index] + 10 * DEFAULT_PRIOR[index]) / (globalTotal + 10)
			local pc = (near[index] + 8 * pg) / (nearTotal + 8)
			result[index] = (exact[index] + 8 * pc) / (exactTotal + 8)
		end
		return result
	end

	local function choose(full, coarse)
		if math.random() * 100 < Config.aiExplore then return math.random(1, 5) end

		local weights = distribution(full, coarse)
		local exact, near = ai.brain.q[full] or EMPTY, ai.brain.q[coarse] or EMPTY
		local total = 0
		for index = 1, 5 do
			-- Results only tilt the learned habits (between a quarter and four times), they never override them.
			weights[index] *= math.exp(0.7 * math.clamp(exact[index] + 0.7 * near[index], -2, 2))
			total += weights[index]
		end

		local roll = math.random() * total
		for index = 1, 5 do
			roll -= weights[index]
			if roll <= 0 then return index end
		end
		return 5
	end

	local function nudge(key, action, amount)
		local values = ai.brain.q[key]
		if not values then
			values = { 0, 0, 0, 0, 0 }
			ai.brain.q[key] = values
		end
		values[action] = math.clamp(values[action] + amount, -3, 3)
	end

	-- Spread a reward over the last few decisions, newest first, on the exact state and the distance state.
	local function credit(reward)
		reward *= Config.aiLearnRate / 100
		local weight = 1
		for index = #ai.history, 1, -1 do
			local entry = ai.history[index]
			nudge(entry[1], entry[2], 0.5 * reward * weight)
			nudge(entry[3], entry[2], 0.3 * reward * weight)

			weight *= 0.82
			if weight < 0.1 then break end
		end
		ai.dirty = true
	end

	-- Real keyboard and mouse. Keys are Windows virtual-key codes, the same kind the weapon slots use.
	local KEY_CODES = {
		Space = 0x20, LeftShift = 0x10, RightShift = 0xA1, LeftControl = 0x11, RightControl = 0xA3,
		Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28,
		Semicolon = 0xBA, Equals = 0xBB, Comma = 0xBC, Minus = 0xBD, Period = 0xBE,
		LeftBracket = 0xDB, BackSlash = 0xDC, RightBracket = 0xDD, Quote = 0xDE,
		Zero = 0x30, One = 0x31, Two = 0x32, Three = 0x33, Four = 0x34,
		Five = 0x35, Six = 0x36, Seven = 0x37, Eight = 0x38, Nine = 0x39,
		KeypadZero = 0x60, KeypadOne = 0x61, KeypadTwo = 0x62, KeypadThree = 0x63, KeypadFour = 0x64,
		KeypadFive = 0x65, KeypadSix = 0x66, KeypadSeven = 0x67, KeypadEight = 0x68, KeypadNine = 0x69,
		KeypadMultiply = 0x6A, KeypadPlus = 0x6B, KeypadMinus = 0x6D, KeypadPeriod = 0x6E, KeypadDivide = 0x6F,
	}
	for code = 0x41, 0x5A do KEY_CODES[string.char(code)] = code end

	local BUTTONS = { MouseButton2 = true }
	-- Handled by the movement and shooting code, so the key policy never touches them.
	local MOVEMENT = { W = true, A = true, S = true, D = true, Space = true, MouseButton1 = true }
	local MOVE_KEYS = { "W", "A", "S", "D" }
	local SHORT_NAMES = {
		MouseButton2 = "MOUSE2", LeftShift = "LSHIFT", RightShift = "RSHIFT", LeftControl = "LCTRL", RightControl = "RCTRL",
		Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	}

	ai.held, ai.grace, ai.cool, ai.downAt = {}, {}, {}, {}
	ai.keysDead, ai.mouseDead, ai.keysWork, ai.misses, ai.silent = false, false, false, 0, 0
	ai.nextKeyTick, ai.state, ai.stateTime = 0, nil, 0
	ai.gain, ai.remainder, ai.sent, ai.sentFrame, ai.sentTime = 2, Vector2.zero, nil, nil, 0
	ai.viaKeys = false

	-- Keys the AI may learn and press: the ones the game uses, never the menu or panic keys of this script.
	function ai.keyOk(name)
		return (KEY_CODES[name] ~= nil or BUTTONS[name] == true) and not MOVEMENT[name]
	end

	local function scriptBind(name)
		for bindName, key in pairs(binds) do
			if bindName ~= "slide" and key.Name == name then return true end
		end
		return false
	end

	local function canHold(name)
		if BUTTONS[name] then return type(mouse2press) == "function" and type(mouse2release) == "function" end
		return type(keypress) == "function" and type(keyrelease) == "function"
	end

	local function canTap(name)
		if BUTTONS[name] then return canHold(name) or type(mouse2click) == "function" end
		return canHold(name) or type(keytap) == "function"
	end

	function ai.canPress(name)
		return ai.keyOk(name) and not scriptBind(name) and canTap(name)
	end

	function ai.holdOk()
		return canHold("W")
	end

	function ai.shortName(name)
		return SHORT_NAMES[name] or string.upper(name)
	end

	-- Only while Roblox is the active window, the menu is closed and nobody is typing.
	function ai.real()
		if window.gui.Enabled == true or userInputService:GetFocusedTextBox() then return false end
		local ok, active = pcall(isrbxactive)
		return ok and active == true
	end

	local function sendKey(name, down)
		local fn
		if BUTTONS[name] then
			if down then fn = mouse2press else fn = mouse2release end
			return type(fn) == "function" and pcall(fn)
		end
		if down then fn = keypress else fn = keyrelease end
		return type(fn) == "function" and pcall(fn, KEY_CODES[name])
	end

	function ai.down(name)
		if ai.held[name] then return true end
		if not (KEY_CODES[name] or BUTTONS[name]) or not sendKey(name, true) then return false end

		local now = os.clock()
		ai.held[name] = { since = now }
		ai.grace[name] = now + 0.6
		return true
	end

	function ai.up(name)
		if not ai.held[name] then return end
		ai.held[name] = nil
		ai.grace[name] = os.clock() + 0.4
		sendKey(name, false)
	end

	local lean = { 0, 0 }

	function ai.releaseAll()
		for name in pairs(ai.held) do ai.up(name) end
		lean[1], lean[2] = 0, 0
	end

	-- Press and let go after `hold` seconds. Without a way to hold a key it is a single tap.
	function ai.tap(name, hold)
		if not (KEY_CODES[name] or BUTTONS[name]) then return false end
		if canHold(name) then
			if not ai.down(name) then return false end
			ai.held[name].release = os.clock() + math.clamp(hold or 0.08, 0.02, 6)
			return true
		end

		ai.grace[name] = os.clock() + 0.6
		if BUTTONS[name] then
			return type(mouse2click) == "function" and pcall(mouse2click)
		end
		return type(keytap) == "function" and pcall(keytap, KEY_CODES[name])
	end

	-- Called every frame: lets go of timed presses and checks that the game really sees the keys being held.
	function ai.service(now)
		for name, entry in pairs(ai.held) do
			if (entry.release and now >= entry.release) or now - entry.since > 30 then
				ai.up(name)
			elseif not entry.seen and not BUTTONS[name] and now - entry.since > 0.4 then
				if heldKeys[Enum.KeyCode[name]] then
					entry.seen = true
					ai.keysWork, ai.misses = true, 0
				else
					ai.up(name)
					ai.misses += 1
					if ai.misses >= 4 and not ai.keysWork and not ai.keysDead then
						ai.keysDead = true
						ai.releaseAll()
						window:Notify("AI: the game ignored the key presses, using normal movement", 4)
					end
				end
			end
		end
	end

	-- A movement key held down by the user, not by the AI.
	function ai.userMoving(now)
		for _, name in ipairs(MOVE_KEYS) do
			if heldKeys[Enum.KeyCode[name]] and not ai.held[name] and now > (ai.grace[name] or 0) then return true end
		end
		return false
	end

	-- A little slack on release so the direction doesn't flicker at the edge of a key.
	local function lane(value, current)
		if current ~= 0 and current * value > 0.25 then return current end
		if value > 0.4 then return 1 end
		if value < -0.4 then return -1 end
		return 0
	end

	-- Holds W, A, S and D to walk toward a world direction from where the camera looks.
	function ai.steer(wish)
		local right = safeUnit(flatten(currentCamera.CFrame.RightVector))
		if not wish or right == Vector3.zero then
			lean[1], lean[2] = 0, 0
		else
			local forward = Vector3.yAxis:Cross(right)
			lean[1] = lane(wish:Dot(forward), lean[1])
			lean[2] = lane(wish:Dot(right), lean[2])
		end

		if lean[1] > 0 then ai.down("W") else ai.up("W") end
		if lean[1] < 0 then ai.down("S") else ai.up("S") end
		if lean[2] > 0 then ai.down("D") else ai.up("D") end
		if lean[2] < 0 then ai.down("A") else ai.up("A") end
	end

	-- Mouse aim -------------------------------------------------------------------------------------------------------
	-- Degrees per second. What was measured on the watched players is mostly slow tracking, so it only nudges a quick base.
	local function aimSpeed()
		local aim = ai.brain.aim
		local base = aim.m >= 20 and math.clamp(aim.rate * 3, 350, 1200) or 700
		return math.clamp(base * Config.aiAimSpeed / 100, 100, 3000)
	end

	-- Yaw and pitch, in radians, from a camera frame to a direction.
	local function anglesTo(frame, direction)
		local relative = frame:PointToObjectSpace(frame.Position + direction)
		return math.atan2(relative.X, -relative.Z), math.asin(math.clamp(relative.Y / math.max(relative.Magnitude, 1e-6), -1, 1))
	end

	ai.damp, ai.lastError, ai.lastErrorTime = 1, nil, 0

	-- Turns the view with the real mouse. Angles become screen pixels through the lens, and the camera's answer to the
	-- last movement tells how many screen pixels one mouse pixel is worth in this game. Returns the angle that will be left
	-- after this move and the angle there is right now.
	function ai.mouseTurn(point, dt, speed)
		local frame = currentCamera.CFrame
		local want = safeUnit(point - frame.Position)
		if want == Vector3.zero then return 0, 0 end

		local angle = math.deg(math.acos(math.clamp(frame.LookVector:Dot(want), -1, 1)))
		local size = currentCamera.ViewportSize
		local focal = (size.Y / 2) / math.tan(math.rad(currentCamera.FieldOfView) / 2)
		local now = os.clock()

		local sent = ai.sent
		ai.sent = nil
		if sent and now - ai.sentTime < 0.12 then
			local yaw, pitch = anglesTo(ai.sentFrame, frame.LookVector)
			local along = Vector2.new(yaw, -pitch):Dot(sent.Unit) * focal
			if along > 0.02 * sent.Magnitude then
				ai.silent = 0
				-- One odd answer (the game snapping the camera, say) can only move the estimate so far.
				local ratio = math.clamp(along / sent.Magnitude, ai.gain / 2, ai.gain * 2)
				ai.gain = math.clamp(ai.gain + 0.3 * (ratio - ai.gain), 0.05, 20)
			elseif sent.Magnitude >= 3 then
				ai.silent += 1
				if ai.silent >= 45 and not ai.mouseDead then
					ai.mouseDead = true
					window:Notify("AI: the mouse did not turn the camera, using camera aim", 4)
				end
			end
		end

		if angle < 0.05 then return 0, angle end

		local yaw, pitch = anglesTo(frame, want)
		-- Never the whole way in one move: the view answers a frame late on some setups and a full correction would swing.
		-- When the view still swings past the target, as it does when the answer comes several frames late, the moves shrink.
		local offset = Vector2.new(yaw, -pitch)
		local before = ai.lastError
		if before and now - ai.lastErrorTime < 0.15 then
			if offset.Magnitude > 0.007 and before.Magnitude > 0.007 and offset:Dot(before) < 0 then
				ai.damp = math.max(0.08, ai.damp * 0.5)
			else
				ai.damp = math.min(1, ai.damp + 0.002)
			end
		end
		ai.lastError, ai.lastErrorTime = offset, now
		local alpha = math.min(0.85 * ai.damp, (speed or aimSpeed()) * dt / angle)

		local delta = Vector2.new(yaw, -pitch) * (focal * alpha / ai.gain)
		if delta.Magnitude > 220 then delta = delta.Unit * 220 end

		delta += ai.remainder
		local moveX, moveY = math.round(delta.X), math.round(delta.Y)
		ai.remainder = delta - Vector2.new(moveX, moveY)
		if (moveX ~= 0 or moveY ~= 0) and pcall(mousemoverel, moveX, moveY) then
			ai.sent, ai.sentFrame, ai.sentTime = Vector2.new(moveX, moveY), frame, now
		end
		return angle * (1 - alpha), angle
	end

	-- Learning the user's own keys ----------------------------------------------------------------------------------
	local function inputName(input)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Keyboard then
			local name = input.KeyCode.Name
			if name ~= "Unknown" then return name end
		elseif kind == Enum.UserInputType.MouseButton2 then
			return "MouseButton2"
		end
		return nil
	end

	function ai.notePress(name, now)
		if not ai.state or now - ai.stateTime > 0.4 then return end

		local brain = ai.brain
		local entry = brain.keys[name]
		if not entry then
			local known = 0
			for _ in pairs(brain.keys) do known += 1 end
			if known >= MAX_KEYS then return end

			entry = { n = 0, h = 0, hold = 0.1, p = {}, o = table.clone(brain.occ) }
			brain.keys[name] = entry
		end

		entry.n += 1
		entry.p[ai.state] = (entry.p[ai.state] or 0) + 1
		entry.p.g = (entry.p.g or 0) + 1
		ai.downAt[name] = now
		ai.dirty = true
	end

	function ai.noteRelease(name, now)
		local started = ai.downAt[name]
		if not started then return end
		ai.downAt[name] = nil

		local entry = ai.brain.keys[name]
		if not entry then return end
		entry.h += 1
		entry.hold += (math.clamp(now - started, 0.02, 6) - entry.hold) / math.min(entry.h, 30)
		ai.dirty = true
	end

	function ai.noteInput(input, pressed)
		local name = inputName(input)
		if not name then return end

		local now = os.clock()
		if not pressed then
			ai.noteRelease(name, now)
			return
		end

		if not Config.aiKeyLearn or Config.aiPlay or window.gui.Enabled == true or userInputService:GetFocusedTextBox() then return end
		if ai.held[name] or now < (ai.grace[name] or 0) then return end
		if ai.keyOk(name) and not scriptBind(name) then ai.notePress(name, now) end
	end

	table.insert(connections, userInputService.InputBegan:Connect(function(input)
		pcall(ai.noteInput, input, true)
	end))
	table.insert(connections, userInputService.InputEnded:Connect(function(input)
		pcall(ai.noteInput, input, false)
	end))

	local function halve(counts)
		for state, value in pairs(counts) do counts[state] = value / 2 end
	end

	-- One tick spent in a situation, for the brain and for every key it knows.
	function ai.countTick(state)
		local brain = ai.brain
		brain.occ[state] = (brain.occ[state] or 0) + 1
		brain.occ.g = (brain.occ.g or 0) + 1
		for _, entry in pairs(brain.keys) do
			entry.o[state] = (entry.o[state] or 0) + 1
			entry.o.g = (entry.o.g or 0) + 1
		end

		if brain.occ.g > 200000 then
			halve(brain.occ)
			for _, entry in pairs(brain.keys) do
				halve(entry.p)
				halve(entry.o)
			end
		end
	end

	-- Presses a learned key now and then: how often it was pressed here, backed by how often it was pressed anywhere.
	function ai.replay(now, state)
		local rate = Config.aiKeyRate / 100
		if rate <= 0 then return end

		for name, entry in pairs(ai.brain.keys) do
			if now >= (ai.cool[name] or 0) and not ai.held[name] and ai.canPress(name) then
				local anywhere = (entry.p.g or 0) / ((entry.o.g or 0) + 30)
				local chance = ((entry.p[state] or 0) + 12 * anywhere) / ((entry.o[state] or 0) + 12) * rate
				if math.random() < chance then
					local hold = math.clamp(entry.hold, 0.03, 6)
					if ai.tap(name, hold) then ai.cool[name] = now + hold + 0.15 end
				end
			end
		end
	end

	-- The situation the local player is in, once per decision tick. Learns while the user plays, replays while the AI does.
	function ai.keyTick(now)
		ai.state = nil
		local character, humanoid, root = getCharacterParts(localPlayer)
		if not root or not humanoid or humanoid.Health <= 0 then return end

		local foe, distance = foeFor(localPlayer, root)
		if not foe or distance > 400 then return end

		local air = not isGrounded(character, humanoid, root, root.AssemblyLinearVelocity)
		local _, coarse = stateKeys(distance, air, 1, 5)
		ai.state, ai.stateTime = coarse, now

		if Config.aiPlay then
			if Config.aiKeys and not ai.keysDead and ai.real() then ai.replay(now, coarse) end
		elseif Config.aiKeyLearn then
			ai.countTick(coarse)
		end
	end

	function ai.forgetKeys()
		ai.brain.keys, ai.brain.occ = {}, {}
		table.clear(ai.downAt)
		ai.dirty = true
	end

	function ai.keySummary()
		local list = {}
		for name, entry in pairs(ai.brain.keys) do table.insert(list, { name = name, n = entry.n }) end
		if #list == 0 then return "Keys: none learned yet" end

		table.sort(list, function(a, b)
			if a.n ~= b.n then return a.n > b.n end
			return a.name < b.name
		end)
		local parts = {}
		for index = 1, math.min(#list, 6) do
			parts[index] = ai.shortName(list[index].name) .. " " .. math.floor(list[index].n)
		end
		return "Keys: " .. table.concat(parts, "  ") .. (#list > 6 and ("  +" .. (#list - 6)) or "")
	end

	function ai.inputSummary()
		local keys = canHold("W") and "HOLD" or (type(keytap) == "function" and "TAP" or "NO")
		local mouse = type(mousemoverel) == "function" and "OK" or "NO"
		local text = string.format("Input: keys %s, mouse %s, right click %s", string.lower(keys), string.lower(mouse), string.lower(canTap("MouseButton2") and "OK" or "NO"))
		if ai.keysDead then text ..= ", keys ignored" end
		if ai.mouseDead then text ..= ", mouse ignored" end
		return text
	end

	-- Getting around. Feelers look for walls, ledges and low obstacles, and a route to an enemy out of sight comes from the
	-- pathfinder. These rays skip every character and anything that cannot be walked into.
	local pathfindingService = cloneref(game:GetService("PathfindingService"))

	local navParams = RaycastParams.new()
	navParams.FilterType = Enum.RaycastFilterType.Exclude
	navParams.RespectCanCollide = true
	navParams.IgnoreWater = true

	local FEELERS = { 28, -28, 56, -56, 90, -90, 135, -135, 180 }
	local KNEE, HEAD, OVER, BODY = -1.8, 1.6, 2.4, 1.1
	local LEDGE_DROP = 17
	local NAV_AGENT = { AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 }

	ai.unreachable = setmetatable({}, { __mode = "k" })
	ai.route, ai.routeBusy, ai.routeNext, ai.routeStarted = nil, false, 0, 0
	ai.pathErrors, ai.pathOffUntil = 0, 0
	ai.hunting, ai.seenAt, ai.avoidSide, ai.avoidUntil = false, 0, 0, 0
	ai.stuckCount, ai.stuckAt, ai.escapeDir, ai.holdUntil = 0, 0, nil, 0

	local filterTime = -1

	function ai.refreshFilter(now)
		if now - filterTime < 0.1 then return end
		filterTime = now

		local list = { currentCamera }
		for _, player in ipairs(getPlayers()) do
			if player.Character then table.insert(list, player.Character) end
		end
		navParams.FilterDescendantsInstances = list
	end

	local function cast(origin, vector)
		return workspace:Raycast(origin, vector, navParams)
	end

	-- Nothing solid between two points, for walking.
	function ai.lineClear(from, to)
		return cast(from, to - from) == nil
	end

	-- How far a direction stays open and what ends it. Low and mid obstacles can be hopped, tall ones cannot. Chest height is
	-- also checked a body width to each side, so corners that a single ray slips past still count.
	local function feel(position, direction, length, full)
		local reach = direction * length
		local side = Vector3.new(-direction.Z, 0, direction.X) * BODY
		local chest = cast(position, reach)
		local left = cast(position + side, reach)
		local right = cast(position - side, reach)
		local head = cast(position + Vector3.new(0, HEAD, 0), reach)
		local knee = full and cast(position + Vector3.new(0, KNEE, 0), reach)

		local free = length
		for _, hit in ipairs({ chest or false, left or false, right or false, head or false, knee or false }) do
			if hit and hit.Distance < free then free = hit.Distance end
		end
		if free >= length then return length, "none" end
		if not full then return free, "tall" end

		local over = cast(position + Vector3.new(0, OVER, 0), reach)
		if over and over.Distance < free + 1.2 then return free, "tall" end
		return free, (chest or left or right or head) and "mid" or "low"
	end

	-- Ground under the feet but none a few steps ahead, or beside that spot. Without ground under the feet to compare with,
	-- nothing counts as a drop.
	local function ledge(position, direction)
		local down = Vector3.new(0, -LEDGE_DROP, 0)
		if not cast(position, down) then return false end

		local ahead = position + direction * 3.2
		local side = Vector3.new(-direction.Z, 0, direction.X) * BODY
		return cast(ahead, down) == nil or cast(ahead + side, down) == nil or cast(ahead - side, down) == nil
	end

	local function turned(direction, degrees)
		local angle = math.rad(degrees)
		local cos, sin = math.cos(angle), math.sin(angle)
		return Vector3.new(direction.X * cos - direction.Z * sin, 0, direction.X * sin + direction.Z * cos)
	end

	-- Bends a wished direction around what is in the way: sideways along a wall, over something low, never off a ledge.
	-- Returns the direction to walk and whether to hop.
	function ai.avoid(root, wish, now, grounded)
		ai.refreshFilter(now)
		local position = root.Position
		local length = math.clamp(ai.speed * 0.32, 4, 7)

		local free, kind = feel(position, wish, length, true)
		local hop = false
		if kind == "mid" or kind == "low" then
			hop = free < 3.5
			kind = "none"
		end
		if kind == "none" and not (grounded and ledge(position, wish)) then
			if now > ai.avoidUntil then ai.avoidSide = 0 end
			return wish, hop
		end

		local options = {}
		for _, degrees in ipairs(FEELERS) do
			local direction = turned(wish, degrees)
			local reach, label = feel(position, direction, length, math.abs(degrees) <= 100)
			local open = (label == "mid" or label == "low") and 0.75 or reach / length
			local score = open - math.abs(degrees) / 360
			if now < ai.avoidUntil and degrees * ai.avoidSide > 0 then score += 0.2 end
			table.insert(options, { score = score, direction = direction, degrees = degrees })
		end
		table.sort(options, function(a, b) return a.score > b.score end)

		for _, option in ipairs(options) do
			if not grounded or not ledge(position, option.direction) then
				ai.avoidSide = option.degrees > 0 and 1 or -1
				ai.avoidUntil = now + 0.7
				return option.direction, false
			end
		end
		-- Edges all around: better to stand still than to step off one.
		return nil, false
	end

	-- The most open way to go in any direction, leaving out the way that was just tried.
	function ai.openDirection(root, now, avoid)
		ai.refreshFilter(now)
		local position = root.Position
		local best, bestScore
		for degrees = 0, 315, 45 do
			local direction = turned(Vector3.new(0, 0, -1), degrees)
			local reach, label = feel(position, direction, 8, true)
			local score = (label == "mid" or label == "low") and 6 or reach
			if ledge(position, direction) then score = -1 end
			if avoid and direction:Dot(avoid) > 0.7 then score -= 4 end
			score += math.random() * 0.5
			if not bestScore or score > bestScore then best, bestScore = direction, score end
		end
		return best
	end

	-- Wanting to move without getting anywhere: sidestep first, then try whatever is open, and ask for a new route.
	function ai.unstick(now, root, wish)
		ai.stuckCount = now - ai.stuckAt < 4 and ai.stuckCount + 1 or 1
		ai.stuckAt = now
		ai.refreshFilter(now)

		local direction
		if ai.stuckCount == 1 and wish then
			local right = Vector3.new(-wish.Z, 0, wish.X)
			local a = feel(root.Position, right, 5, true)
			local b = feel(root.Position, -right, 5, true)
			if a == b then direction = math.random() < 0.5 and right or -right else direction = a > b and right or -right end
		else
			direction = ai.openDirection(root, now, wish)
		end

		ai.escapeDir, ai.forcedUntil, ai.holdUntil = direction, now + 0.5 + 0.2 * math.min(ai.stuckCount, 3), 0
		ai.jumpNow = true
		if ai.stuckCount >= 2 then ai.route, ai.routeNext = nil, 0 end
	end

	-- Routes ----------------------------------------------------------------------------------------------------------
	local function pathReady(now)
		return Config.aiHunt and type(pathfindingService.CreatePath) == "function" and now >= ai.pathOffUntil
	end

	-- Asking the pathfinder takes a while, so it happens on its own thread and the answer is picked up later.
	local function requestRoute(now, from, to, player)
		ai.routeBusy, ai.routeStarted, ai.routeNext = true, now, now + 0.7
		task.spawn(function()
			local ok, points = pcall(function()
				local path = pathfindingService:CreatePath(NAV_AGENT)
				path:ComputeAsync(from, to)
				if path.Status ~= Enum.PathStatus.Success then return nil end
				return path:GetWaypoints()
			end)
			ai.routeBusy = false
			if not Config.aiPlay then return end

			if not ok then
				ai.pathErrors += 1
				if ai.pathErrors >= 4 then ai.pathOffUntil, ai.pathErrors = os.clock() + 30, 0 end
			elseif points and #points > 1 then
				ai.pathErrors = 0
				ai.route = { points = points, index = 2, goal = to, time = os.clock(), player = player }
			else
				-- A clean "no way there" is an answer, not an error: look for someone else for a while.
				ai.pathErrors = 0
				ai.unreachable[player] = os.clock() + 6
			end
		end)
	end

	-- The direction toward an enemy that is far away or out of sight: along the route when there is one, else straight.
	function ai.hunt(now, root, foeRoot, player)
		local position, goal = root.Position, foeRoot.Position

		if ai.routeBusy and now - ai.routeStarted > 6 then ai.routeBusy = false end
		local route = ai.route
		if route and (route.player ~= player or now - route.time > 6) then
			route, ai.route = nil, nil
		end
		local lost = (ai.unreachable[player] or 0) > now
		if pathReady(now) and not lost and not ai.routeBusy and now >= ai.routeNext then
			if not route or (goal - route.goal).Magnitude > 12 or now - route.time > 2 then
				requestRoute(now, position, goal, player)
			end
		end

		route = ai.route
		if route then
			local points, index = route.points, route.index
			while index <= #points and flatten(points[index].Position - position).Magnitude < 3 do index += 1 end
			route.index = index

			local waypoint = points[index]
			if waypoint then
				local offset = flatten(waypoint.Position - position)
				if waypoint.Action == Enum.PathWaypointAction.Jump and offset.Magnitude < 6 then ai.jumpNow = true end
				return safeUnit(offset)
			end
			ai.route = nil
		end
		return safeUnit(flatten(goal - position))
	end

	-- Who to shoot and where. Sight is checked here, with rays that skip anything uncollidable, whatever the soft aim's wall
	-- check says. The nearest enemy that can be hit wins, the one already aimed at gets some loyalty.
	local losParams = RaycastParams.new()
	losParams.FilterType = Enum.RaycastFilterType.Exclude
	losParams.RespectCanCollide = true
	losParams.IgnoreWater = true

	local sights = setmetatable({}, { __mode = "k" })

	local function canSee(part, character, now)
		local entry = sights[part]
		if entry and now - entry.time < 0.06 then return entry.visible end

		local filter = { currentCamera, character }
		if localPlayer.Character then table.insert(filter, localPlayer.Character) end
		losParams.FilterDescendantsInstances = filter
		local origin = currentCamera.CFrame.Position
		local visible = workspace:Raycast(origin, part.Position - origin, losParams) == nil

		if entry then
			entry.time, entry.visible = now, visible
		else
			sights[part] = { time = now, visible = visible }
		end
		return visible
	end

	-- The head when the target is close or standing still, the chest otherwise, whichever of the two can be hit.
	local function targetPart(character, root, distance, now)
		local head = character:FindFirstChild("Head")
		local chest = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso") or character:FindFirstChild("HumanoidRootPart")

		local mode = Config.aiAimPart
		local still = flatten(root.AssemblyLinearVelocity).Magnitude < 5
		local first, second = chest, head
		if mode == "Head" or (mode ~= "Chest" and (distance < 22 or still)) then first, second = head, chest end

		if first and (Config.aiWalls or canSee(first, character, now)) then return first end
		if second and second ~= first and (Config.aiWalls or canSee(second, character, now)) then return second end
		return nil
	end

	function ai.pickTarget(now)
		local frame = currentCamera.CFrame
		local origin, look = frame.Position, frame.LookVector

		local best, bestPlayer, bestScore, bestDistance
		for _, player in ipairs(getPlayers()) do
			if not isEnemy(player) then continue end

			local character, _, root = getCharacterParts(player)
			if not character then continue end

			local distance = (root.Position - origin).Magnitude
			if Config.aiRange > 0 and distance > Config.aiRange then continue end
			if Config.aiCone > 0 then
				local off = math.deg(math.acos(math.clamp(look:Dot(safeUnit(root.Position - origin)), -1, 1)))
				if off > Config.aiCone then continue end
			end
			local part = targetPart(character, root, distance, now)
			if not part then continue end

			local angle = math.deg(math.acos(math.clamp(look:Dot(safeUnit(part.Position - origin)), -1, 1)))
			local score = distance * (1 + angle / 90)
			if player == ai.locked then score *= 0.6 end
			if not bestScore or score < bestScore then best, bestPlayer, bestScore, bestDistance = part, player, score, distance end
		end
		return best, bestPlayer, bestDistance
	end

	-- Damage taken and dealt, kills and deaths. Shots count as ours when one was fired a moment ago.
	local function watchResults(now, humanoid)
		local stats = ai.brain.stats
		local health = humanoid.Health
		if ai.health and health < ai.health - 0.5 then
			local lost = ai.health - health
			stats.taken += lost
			credit(-2 * lost / math.max(humanoid.MaxHealth, 1))
		end
		ai.health = health

		local recent = now - lastShot < 0.7
		for _, player in ipairs(getPlayers()) do
			if not isEnemy(player) then continue end

			local character = player.Character
			local foeHumanoid = character and character:FindFirstChildOfClass("Humanoid")
			local value = foeHumanoid and foeHumanoid.Health or 0
			local before = ai.foeHealth[player]
			if before and recent and value < before - 0.5 then
				stats.dealt += before - value
				credit(2 * (before - value) / 100)
				if value <= 0 then
					stats.kills += 1
					credit(1)
				end
			end
			ai.foeHealth[player] = value
		end
	end

	local function realize(action, toFoe)
		local right = Vector3.new(-toFoe.Z, 0, toFoe.X)
		if action == 1 then return toFoe, right end
		if action == 2 then return -toFoe, right end
		if action == 3 then return -right, right end
		if action == 4 then return right, right end
		return nil, right
	end

	-- A chosen move is kept for a moment, the way a hand holds a key: forward, back, left, right, still.
	local HOLDS = { { 0.45, 1.1 }, { 0.3, 0.7 }, { 0.35, 0.9 }, { 0.35, 0.9 }, { 0.15, 0.4 } }
	-- Enemies farther than this are walked up to, then fought from the nearer distance.
	local HUNT_START, HUNT_STOP = 75, 55

	local function holdFor(action)
		local range = HOLDS[action]
		return (range[1] + math.random() * (range[2] - range[1])) * Config.aiHold / 100
	end

	-- Who the movement is about: whoever is being shot at, otherwise the closest enemy.
	local function engage(root)
		local locked = ai.locked
		if locked and isEnemy(locked) then
			local _, _, lockedRoot = getCharacterParts(locked)
			if lockedRoot then
				return lockedRoot, (lockedRoot.Position - root.Position).Magnitude, locked, true
			end
		end

		local foe, distance, player = foeFor(localPlayer, root, ai.unreachable)
		if not foe then foe, distance, player = foeFor(localPlayer, root) end
		return foe, distance, player, false
	end

	-- Retreating when hurt, holding a preferred distance and the play style bend what the learned habits chose.
	local function bend(action, distance, health)
		if Config.aiRetreat > 0 and health * 100 < Config.aiRetreat then return 2 end

		local wanted = Config.aiDistance
		if wanted > 0 then
			if distance > wanted * 1.25 then return 1 end
			if distance < wanted * 0.75 then return 2 end
			if action == 1 or action == 2 then return math.random() < 0.5 and 3 or 4 end
		end

		local mode = Config.aiStyle
		if mode == "Aggressive" and math.random() < 0.4 then return 1 end
		if mode == "Defensive" and math.random() < 0.4 then return 2 end
		if mode == "Strafer" and (action == 1 or action == 2 or action == 5) then return math.random() < 0.5 and 3 or 4 end
		return action
	end

	local function decide(now, character, humanoid, root)
		local foe, distance, foePlayer, shot = engage(root)
		if not foe or distance > 400 then
			ai.wish, ai.prev, ai.hunting, ai.route, ai.holdUntil = nil, 5, false, nil, 0
			return
		end

		local toFoe = safeUnit(flatten(foe.Position - root.Position))
		if toFoe == Vector3.zero then
			ai.wish = nil
			return
		end

		-- Out of sight or far away means going to them instead of circling in place.
		ai.refreshFilter(now)
		local seen = shot or ai.lineClear(root.Position, foe.Position)
		if seen then ai.seenAt = now end

		local hunting = false
		if Config.aiHunt then
			if ai.hunting then
				hunting = not (seen and distance < HUNT_STOP)
			else
				hunting = (not seen and now - ai.seenAt > 0.35) or distance > HUNT_START
			end
		end
		if hunting ~= ai.hunting then
			ai.hunting, ai.holdUntil, ai.route = hunting, 0, nil
		end

		local previous = ai.prev
		local grounded = isGrounded(character, humanoid, root, root.AssemblyLinearVelocity)
		local health = humanoid.MaxHealth > 0 and humanoid.Health / humanoid.MaxHealth or 1
		local full, coarse, bin = stateKeys(distance, not grounded, health, previous)

		local wish
		local escaping = ai.escapeDir ~= nil and now < ai.forcedUntil
		if escaping then
			wish = ai.escapeDir
		elseif hunting then
			wish = ai.hunt(now, root, foe, foePlayer)
			ai.prev = 1
		else
			local action = previous
			if now >= ai.holdUntil then
				action = bend(choose(full, coarse), distance, health)
				ai.holdUntil = now + holdFor(action)
			end
			table.insert(ai.history, { full, action, coarse })
			if #ai.history > HISTORY then table.remove(ai.history, 1) end

			wish = realize(action, toFoe)
			ai.prev = action
		end
		if wish == Vector3.zero then wish = nil end

		local hop = false
		if wish and Config.aiAvoid and not escaping then
			wish, hop = ai.avoid(root, wish, now, grounded)
		end

		-- Wanting to move for most of a second without getting anywhere means it is stuck.
		local flatPosition = flatten(root.Position)
		ai.travel += (flatPosition - ai.lastPosition).Magnitude
		ai.lastPosition = flatPosition
		if wish then ai.wished += 1 end
		if now - ai.checkTime >= 0.8 then
			if ai.wished >= 5 and ai.travel < 1.6 then ai.unstick(now, root, wish) end
			ai.checkTime, ai.travel, ai.wished = now, 0, 0
		end

		if grounded then
			if hop then
				ai.jumpNow = true
			elseif not hunting and not escaping then
				local entry = ai.brain.jump[bin .. "_" .. previous]
				local chance = ((entry and entry[1] or 0) + 1) / ((entry and entry[2] or 0) + 25)
				if math.random() < chance * Config.aiJumpRate / 100 then ai.jumpNow = true end
			end
		end

		ai.wish = wish
	end

	local guiService = cloneref(game:GetService("GuiService"))

	-- A click lands on the menu instead of the game while the cursor is over it.
	local function overMenu()
		if window.gui.Enabled ~= true then return false end

		local mouse = userInputService:GetMouseLocation() - guiService:GetGuiInset()
		local position, size = window.main.AbsolutePosition, window.main.AbsoluteSize
		return mouse.X >= position.X and mouse.X <= position.X + size.X and mouse.Y >= position.Y and mouse.Y <= position.Y + size.Y
	end

	local function yawOf(direction)
		return math.atan2(direction.X, -direction.Z)
	end

	local function directionOf(yaw, pitch)
		local flat = math.cos(pitch)
		return Vector3.new(flat * math.sin(yaw), math.sin(pitch), -flat * math.cos(yaw))
	end

	-- Turns the camera at the speed the watched players turned at, the way a mouse would: yaw and pitch each move straight
	-- toward the target, so the horizon stays level. Returns the angle left after this turn and the angle there was before.
	local function turnTo(point, dt, speed)
		local frame = currentCamera.CFrame
		local origin = frame.Position
		local want = safeUnit(point - origin)
		if want == Vector3.zero then return 0, 0 end

		local look = frame.LookVector
		local angle = math.deg(math.acos(math.clamp(look:Dot(want), -1, 1)))

		local yaw, pitch = yawOf(look), math.asin(math.clamp(look.Y, -1, 1))
		local gap = (yawOf(want) - yaw + math.pi) % (2 * math.pi) - math.pi
		local rise = math.asin(math.clamp(want.Y, -1, 1)) - pitch
		-- Length of the path on the screen, so the speed holds up even when looking steeply up or down.
		local reach = math.deg(math.sqrt((gap * math.cos(pitch + rise / 2)) ^ 2 + rise ^ 2))
		local alpha = reach < 0.05 and 1 or math.min(1, (speed or aimSpeed()) * dt / reach)

		currentCamera.CFrame = CFrame.lookAt(origin, origin + directionOf(yaw + gap * alpha, pitch + rise * alpha))
		return angle * (1 - alpha), angle
	end

	-- Looking around. With nobody to shoot at the view wanders: it glances where it is heading, toward the nearest enemy,
	-- behind itself and off to the sides, with pauses in between. It uses the mouse or the camera like the aim does.
	local function lookSpeed()
		return math.clamp(150 * Config.aiLookSpeed / 100, 30, 600)
	end

	local function pickLook(state, root)
		local yaw = yawOf(currentCamera.CFrame.LookVector)
		local pitch = math.rad(math.random(-8, 12))
		local roll = math.random()
		local foe = foeFor(localPlayer, root)
		state.dwell = 0.4 + math.random() * 0.9

		-- On the way somewhere the eyes mostly stay on the road.
		local ahead = ai.hunting and 0.55 or 0.3
		if state.chase then
			-- Just lost sight of someone: check where they were first.
			yaw = yawOf(state.chase) + math.rad(math.random(-15, 15))
			pitch = math.rad(math.random(-4, 8))
			state.dwell = 0.6 + math.random() * 0.6
			state.chase = nil
		elseif ai.wish and roll < ahead then
			yaw = yawOf(ai.wish) + math.rad(math.random(-14, 14))
		elseif foe and roll < ahead + 0.2 then
			yaw = yawOf(foe.Position - root.Position) + math.rad(math.random(-30, 30))
		elseif roll < ahead + 0.3 then
			yaw += math.pi + math.rad(math.random(-40, 40))
		else
			local turn = math.rad(math.random(35, 140))
			yaw += math.random() < 0.5 and turn or -turn
		end

		if math.random() < 0.15 then pitch = math.rad(math.random(-35, 40)) end
		state.target = directionOf(yaw, pitch)
		state.limit = 1.5 + 200 / lookSpeed()
	end

	function ai.look(dt, root, useMouse)
		local state = ai.lookState
		if not state then
			state = { chase = ai.lastAim }
			ai.lookState, ai.lastAim = state, nil
			pickLook(state, root)
		end

		local frame = currentCamera.CFrame
		local want = state.target
		local angle = math.deg(math.acos(math.clamp(frame.LookVector:Dot(want), -1, 1)))
		-- Slows down on arrival, so the view settles the way a hand would.
		local speed = lookSpeed() * math.clamp(angle / 20, 0.15, 1)
		local point = frame.Position + want * 100

		local remaining
		if useMouse then
			remaining = ai.mouseTurn(point, dt, speed)
		else
			ai.sent = nil
			remaining = turnTo(point, dt, speed)
		end

		state.limit -= dt
		if remaining < 2 then state.dwell -= dt end
		if state.dwell <= 0 or state.limit <= 0 then pickLook(state, root) end
	end

	function ai.step(dt, root)
		-- The first frame of playing only sets things up, in ai.tick.
		if not ai.playing then return end

		local character, humanoid = getCharacterParts(localPlayer)
		if not humanoid then
			ai.releaseAll()
			return
		end
		local now = os.clock()

		-- Real keys and mouse only while Roblox is in front and the menu is closed.
		local real = ai.real()
		if not real then ai.releaseAll() end
		local useKeys = real and Config.aiKeys and ai.holdOk() and not ai.keysDead
		local useMouse = real and Config.aiMouse and type(mousemoverel) == "function" and not ai.mouseDead
		ai.viaKeys = useKeys

		if now >= ai.nextDecision then
			ai.nextDecision = now + AI_TICK
			if Config.aiSelfLearn then watchResults(now, humanoid) end
			if Config.aiMove then
				decide(now, character, humanoid, root)
			else
				ai.wish = nil
			end
		end

		-- Pressing a move key hands the movement back.
		if Config.aiYield and ai.userMoving(now) then ai.wish = nil end

		ai.speed = Config.walkEnabled and Config.walkSpeed or humanoid.WalkSpeed
		if useKeys then
			ai.steer(ai.wish)
			if ai.jumpNow then
				ai.jumpNow = false
				if isGrounded(character, humanoid, root, root.AssemblyLinearVelocity) then ai.tap("Space", 0.07) end
			end
		else
			ai.steer(nil)
			if ai.wish then humanoid:Move(ai.wish, false) end
		end

		local part, player, distance
		if Config.aiAim then
			part, player, distance = ai.pickTarget(now)
		end
		if player ~= ai.locked then ai.targetSince = now end
		ai.locked = player

		-- Nobody to shoot at: look around instead.
		if not part then
			if Config.aiLook then
				ai.look(dt, root, useMouse)
			else
				ai.sent, ai.lookState = nil, nil
			end
			return
		end

		local point = aimPoint(part)
		if Config.aiWobble > 0 then
			local spread = Config.aiWobble * 0.1 * (0.5 + distance / 60)
			point += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * spread
		end
		local toTarget = safeUnit(point - currentCamera.CFrame.Position)
		ai.lastAim, ai.lookState = toTarget ~= Vector3.zero and toTarget or nil, nil
		local silent = Config.aiAimMode == "Silent"
		local remaining, angle
		if useMouse then
			remaining, angle = ai.mouseTurn(point, dt)
		else
			ai.sent = nil
			remaining, angle = turnTo(point, dt)
		end
		if silent then
			silentPoint, silentChance, silentCharacter = point, 100, part.Parent
		end

		-- A shot has to land inside the target, and a head from afar is a small mark. With the mouse the view only answers on
		-- the next frame, so what counts is where it points now; with the camera it is where this turn ends.
		local half = part.Name == "Head" and 0.55 or 0.9
		local tolerance = math.clamp(math.deg(math.atan(half / math.max(distance, 4))), 0.7, 7)
		local aimed = silent or (useMouse and angle or remaining) < tolerance
		if Config.aiShoot and aimed and now - (ai.targetSince or 0) >= Config.aiReaction / 1000 and not overMenu() then
			fireClick(Config.aiShootDelay * (1 + (math.random() * 2 - 1) * Config.aiShootVariance / 100))
		end
	end

	function ai.stop()
		ai.releaseAll()
		ai.wish, ai.jumpNow, ai.playing, ai.locked, ai.viaKeys, ai.sent = nil, false, false, nil, false, nil
		ai.lookState, ai.lastAim = nil, nil
		ai.route, ai.hunting, ai.escapeDir, ai.holdUntil, ai.forcedUntil = nil, false, nil, 0, 0
		table.clear(ai.history)
	end

	local function compact(value)
		if value >= 1e6 then return string.format("%.1fm", value / 1e6) end
		if value >= 1e3 then return string.format("%.1fk", value / 1e3) end
		return tostring(math.floor(value))
	end

	function ai.refreshLabels()
		local sets = ai.labelSets
		if not sets then return end

		local brain = ai.brain
		local stats = brain.stats
		local states = 0
		for key in pairs(brain.policy) do
			if string.match(key, "^%d_%d_%d_%d$") then states += 1 end
		end

		local lines = {
			string.format("%s: %d states, %s samples", brain.name, states, compact(stats.samples)),
			string.format("Watched %.1fm, played %.1fm, %d pros", stats.watched / 60, stats.played / 60, #ai.pros),
			string.format(
				"Kills %d, deaths %d, dealt %d, taken %d",
				math.floor(stats.kills), math.floor(stats.deaths), math.floor(stats.dealt), math.floor(stats.taken)
			),
		}
		for _, set in ipairs(sets) do
			for index, line in ipairs(lines) do
				if set[index].Text ~= line then set[index].Text = line end
			end
		end

		local labels = ai.keyLabels
		if labels then
			local text = ai.keySummary()
			if labels.keys.Text ~= text then labels.keys.Text = text end
			text = ai.inputSummary()
			if labels.input.Text ~= text then labels.input.Text = text end
		end
	end

	function ai.tick(now, dt)
		ai.service(now)

		if Config.aiPlay then
			if not ai.playing then
				ai.playing, ai.health, ai.nextDecision = true, nil, 0
				ai.keysDead, ai.mouseDead, ai.keysWork, ai.misses, ai.silent = false, false, false, 0, 0
				ai.holdUntil, ai.forcedUntil, ai.escapeDir, ai.stuckCount, ai.seenAt = 0, 0, nil, 0, 0
				ai.hunting, ai.route, ai.routeBusy, ai.routeNext = false, nil, false, 0
				ai.damp, ai.lastError = 1, nil
				table.clear(ai.history)
				table.clear(ai.foeHealth)
				table.clear(ai.unreachable)
				local slot = SLOT_KEYS[Config.aiSlot]
				if slot and type(keytap) == "function" and isrbxactive() then pcall(keytap, slot) end
			end

			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				if humanoid.Health <= 0 then
					if not ai.dead then
						ai.dead = true
						ai.releaseAll()
						ai.wish, ai.jumpNow, ai.health = nil, false, nil
						ai.route, ai.hunting, ai.escapeDir, ai.holdUntil, ai.forcedUntil = nil, false, nil, 0, 0
						ai.brain.stats.deaths += 1
						if Config.aiSelfLearn then credit(-1) end
					end
				else
					ai.dead = false
					ai.brain.stats.played += dt
					ai.dirty = true
				end
			else
				ai.releaseAll()
			end
		elseif ai.playing then
			ai.stop()
		end

		if Config.aiLearn and now >= ai.nextObserve and not (ai.playing and Config.aiSource == "Me") then
			ai.nextObserve = now + AI_TICK
			observe(now)
		end

		if now >= ai.nextKeyTick then
			ai.nextKeyTick = now + AI_TICK
			ai.keyTick(now)
		end

		if Config.aiAutoSave and ai.dirty and now - ai.lastSave > 45 then
			ai.saveBrain()
		end

		if now >= ai.nextLabels then
			ai.nextLabels = now + 0.5
			ai.refreshLabels()
		end
	end

	moduleCleanup.ai = ai.stop
	moduleCleanup["ai play"] = ai.stop
end)()

local function applyThirdPerson()
	if Config.thirdPerson then
		localPlayer.CameraMinZoomDistance = Config.thirdPersonDistance
		localPlayer.CameraMaxZoomDistance = Config.thirdPersonDistance
	else
		localPlayer.CameraMinZoomDistance = originalMinZoom
		localPlayer.CameraMaxZoomDistance = originalMaxZoom
	end
end

local function onRender(dt)
	local camera = workspace.CurrentCamera
	if not camera then return end
	currentCamera = camera

	local now = os.clock()
	local mouse = userInputService:GetMouseLocation()
	perFrame.index += 1
	perFrame.time = now
	perFrame.mouse = mouse
	perFrame.viewport = camera.ViewportSize
	perFrame.origin = camera.CFrame.Position

	updatePing(now)

	if Config.fovOffset > 0 then
		camera.FieldOfView = BASE_FOV + Config.fovOffset
		fovApplied = true
	elseif fovApplied then
		fovApplied = false
		camera.FieldOfView = BASE_FOV
	end

	local desiredCap = Config.fpsEnabled and Config.fpsCap or 240
	if desiredCap ~= lastFpsCap then
		lastFpsCap = desiredCap
		compat.fps(desiredCap)
	end
	if fpsStatus then
		local statusText = Config.fpsEnabled and ("Status: capped at " .. Config.fpsCap) or "Status: restored to 240"
		if fpsStatus.Text ~= statusText then fpsStatus.Text = statusText end
	end

	runModule("combat", updateCombat, dt)
	runModule("ai", ai.tick, now, dt)

	aimCircle.Position = mouse
	aimCircle.Radius = Config.aimFov
	aimCircle.Visible = Config.aimEnabled and Config.aimShowFov and not Config.rageEnabled and not Config.farmEnabled and not Config.aiPlay

	silentCircle.Position = mouse
	silentCircle.Radius = Config.silentFov
	silentCircle.Visible = Config.silentEnabled and Config.silentShowFov and not Config.rageEnabled and not Config.farmEnabled

	if Config.espEnabled and espFeaturesOn() then
		espCleared = false
		runModule("esp", updateAllEsp, now)
	elseif not espCleared then
		espCleared = true
		for _, esp in pairs(espObjects) do hideEsp(esp) end
	end

	runModule("radar", updateRadar)
	runModule("crosshair", updateCrosshair)
	runModule("hud", updateFeatureList, now)
	runModule("target line", updateTargetLine, mouse)
	runModule("world", updateWorld, now)

	for _, entry in ipairs(hooks.render) do runModule(entry[1], entry[2], dt, now, mouse) end
end

do
local hookmetamethod, newcclosure, checkcaller, getnamecallmethod = compat.hooks()
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
	if silentPoint and not checkcaller() and getnamecallmethod() == "Raycast" and self == workspace then
		local origin, direction = ...
		if typeof(origin) == "Vector3" and typeof(direction) == "Vector3" and math.random(1, 100) <= silentChance then
			local rest = { select(3, ...) }
			return oldNamecall(self, origin, (silentPoint - origin).Unit * direction.Magnitude, unpack(rest))
		end
	end
	return oldNamecall(self, ...)
end))
end

-- Config profiles.
local CONFIG_FOLDER = "SpriteRivals"
local AUTOLOAD_FILE = CONFIG_FOLDER .. "/autoload.txt"
local VOLATILE = { aimActive = true }
-- Settings that were retuned in version 4, older profiles keep the new defaults for them.
local RETUNED = { slideSpeed = true, slideDecay = true, slideJumpBoost = true }

local defaults, defaultBinds = {}, {}
for key, value in pairs(Config) do defaults[key] = value end
for name, key in pairs(binds) do defaultBinds[name] = key end

local function cleanConfigName(name)
	name = string.gsub(name or "", "[^%w_%-]", "")
	return name ~= "" and name or "default"
end

local function configPath(name)
	return CONFIG_FOLDER .. "/" .. name .. ".json"
end

local function encodeConfig()
	local data = { version = 4, config = {}, binds = {} }
	for key, value in pairs(Config) do
		local kind = type(value)
		if not VOLATILE[key] and (kind == "boolean" or kind == "number" or kind == "string") then
			data.config[key] = value
		end
	end
	for name, key in pairs(binds) do
		data.binds[name] = { type = tostring(key.EnumType), name = key.Name }
	end
	return httpService:JSONEncode(data)
end

---Recolor the menu, watermark and drawings from a theme table.
function hooks.applyTheme(theme)
	ACCENT = theme.accent
	window:applyTheme(theme)
	watermark.applyTheme(theme)
	radarBorder.Color = ACCENT
	featureList.Color = ACCENT
end

local function applyThemeByName(name)
	hooks.applyTheme(THEMES[name] or THEMES.Aqua)
end

---Push the current Config and binds into every menu widget.
local function refreshWidgets()
	for key, widget in pairs(widgets) do widget:set(Config[key]) end
	for name, widget in pairs(bindWidgets) do widget:set(binds[name]) end
	applyThirdPerson()
	applyPalette(Config.espPalette)
	applyThemeByName(Config.theme)
	window:setAnimated(Config.menuAnimations)
	window:setBlur(Config.menuBlur)
	for _, refresh in ipairs(hooks.refresh) do pcall(refresh) end
end

local function applyConfig(data)
	if hooks.backup then hooks.backup() end
	local outdated = (tonumber(data.version) or 0) < 4
	for key, value in pairs(data.config or {}) do
		local current = Config[key]
		if current == nil or VOLATILE[key] or type(current) ~= type(value) then continue end
		if outdated and RETUNED[key] then continue end

		local options = dropdownOptions[key]
		if options and not table.find(options, value) then continue end

		Config[key] = value
	end

	for name, info in pairs(data.binds or {}) do
		if binds[name] == nil or type(info) ~= "table" then continue end
		local ok, key = pcall(function() return Enum[info.type][info.name] end)
		if ok and key then binds[name] = key end
	end

	refreshWidgets()
end

local function resetConfig()
	if hooks.backup then hooks.backup() end
	for key, value in pairs(defaults) do Config[key] = value end
	for name, key in pairs(defaultBinds) do binds[name] = key end
	refreshWidgets()
end

local function saveConfig(name)
	return pcall(function()
		if not compat.isfolder(CONFIG_FOLDER) then compat.makefolder(CONFIG_FOLDER) end
		compat.writefile(configPath(name), encodeConfig())
	end)
end

local function loadConfig(name)
	local path = configPath(name)
	if not compat.isfile(path) then return false end

	local ok, data = pcall(function() return httpService:JSONDecode(compat.readfile(path)) end)
	if not ok or type(data) ~= "table" then return false end

	applyConfig(data)
	return true
end

local function importConfig(text)
	local ok, data = pcall(function() return httpService:JSONDecode(text) end)
	if not ok or type(data) ~= "table" then return false end

	applyConfig(data)
	return true
end

local function deleteConfig(name)
	local path = configPath(name)
	if not compat.isfile(path) then return false end

	local ok = pcall(compat.delfile, path)
	return ok
end

-- Extras: movement. Gravity, falling, ragdoll, void rescue, click teleport and the noclip key.
;(function()
	local gravityBase = nil
	local ragdollHumanoid = nil
	local safe = { position = nil, time = 0 }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude

	local function setRagdoll(humanoid, enabled)
		pcall(humanoid.SetStateEnabled, humanoid, Enum.HumanoidStateType.FallingDown, enabled)
		pcall(humanoid.SetStateEnabled, humanoid, Enum.HumanoidStateType.Ragdoll, enabled)
	end

	local function restore()
		if gravityBase then
			workspace.Gravity = gravityBase
			gravityBase = nil
		end
		if ragdollHumanoid then
			if ragdollHumanoid.Parent then setRagdoll(ragdollHumanoid, true) end
			ragdollHumanoid = nil
		end
	end

	table.insert(hooks.step, { "move extras", function(dt, now)
		if Config.gravityEnabled then
			if not gravityBase then gravityBase = workspace.Gravity end
			if workspace.Gravity ~= Config.gravityValue then workspace.Gravity = Config.gravityValue end
		elseif gravityBase then
			workspace.Gravity = gravityBase
			gravityBase = nil
		end

		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not (humanoid and root) or humanoid.Health <= 0 then
			ragdollHumanoid = nil
			return
		end

		-- Ragdoll and fall-down states are switched off for the current character, and put back afterwards.
		if Config.noRagdoll then
			if ragdollHumanoid ~= humanoid then
				ragdollHumanoid = humanoid
				setRagdoll(humanoid, false)
			end
			local state = humanoid:GetState()
			if state == Enum.HumanoidStateType.FallingDown or state == Enum.HumanoidStateType.Ragdoll then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		elseif ragdollHumanoid then
			if ragdollHumanoid.Parent then setRagdoll(ragdollHumanoid, true) end
			ragdollHumanoid = nil
		end

		if Config.flyEnabled then return end
		local velocity = root.AssemblyLinearVelocity

		-- Falling speed: a fixed cap, and a lower one while gliding with space held.
		local cap = Config.fallLimit > 0 and Config.fallLimit or nil
		if Config.glideEnabled and (heldKeys[Enum.KeyCode.Space] or hooks.touch.jump) and velocity.Y < -Config.glideSpeed
			and not userInputService:GetFocusedTextBox() and not isGrounded(character, humanoid, root, velocity) then
			cap = math.min(cap or math.huge, Config.glideSpeed)
		end
		if cap and velocity.Y < -cap then
			root.AssemblyLinearVelocity = Vector3.new(velocity.X, -cap, velocity.Z)
		end

		-- Void rescue: remembers the last spot with ground under it, and returns there when falling out of the map.
		if Config.antiVoid then
			local bottom = workspace.FallenPartsDestroyHeight
			if bottom < -1e5 then bottom = -500 end

			if root.Position.Y < bottom + 60 then
				if safe.position then
					local look = root.CFrame.LookVector
					local goal = safe.position + Vector3.new(0, 4, 0)
					root.CFrame = CFrame.lookAt(goal, goal + Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 0.001))
					root.AssemblyLinearVelocity = Vector3.zero
				end
			elseif now - safe.time > 0.4 and isGrounded(character, humanoid, root, velocity) then
				safe.position, safe.time = root.Position, now
			end
		else
			safe.position = nil
		end
	end })

	local function clickTeleport()
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		local mouse = userInputService:GetMouseLocation()
		local ray = currentCamera:ViewportPointToRay(mouse.X, mouse.Y)
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		if not hit then
			window:Notify("Nothing under the crosshair", 1.5)
			return
		end

		local look = root.CFrame.LookVector
		local goal = hit.Position + Vector3.new(0, 3.2, 0)
		root.CFrame = CFrame.lookAt(goal, goal + Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 0.001))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	hooks.clickTeleport = clickTeleport

	table.insert(connections, userInputService.InputBegan:Connect(function(input, processed)
		if window.listening or processed or userInputService:GetFocusedTextBox() then return end

		if Config.clickTp and hooks.pressed(input, binds.clickTp) then clickTeleport() end

		if hooks.pressed(input, binds.noclip) then
			Config.noclip = not Config.noclip
			widgets.noclip:set(Config.noclip)
			window:Notify("Noclip: " .. (Config.noclip and "ON" or "OFF"), 1.5)
		end
	end))

	moduleCleanup["move extras"] = restore
	table.insert(hooks.clean, restore)
end)()

-- Extras: camera, system and server tools.
;(function()
	local teleportService = cloneref(game:GetService("TeleportService"))
	local starterGui = cloneref(game:GetService("StarterGui"))
	local guiService = cloneref(game:GetService("GuiService"))

	local CORE_TYPES = {
		Enum.CoreGuiType.Chat, Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Backpack,
		Enum.CoreGuiType.EmotesMenu, Enum.CoreGuiType.Health,
	}

	local zoomBase, sensBase, qualityBase, hiddenCore = nil, nil, nil, nil
	local nextSystem = 0

	-- Hold to zoom. The field of view from before is put back on release.
	table.insert(hooks.render, { "zoom", function()
		local zooming = Config.zoomEnabled and (hooks.held(binds.zoom) or hooks.touch.zoom) and not userInputService:GetFocusedTextBox()
		if zooming then
			if not zoomBase then zoomBase = currentCamera.FieldOfView end
			currentCamera.FieldOfView = Config.zoomFov
		elseif zoomBase then
			if Config.fovOffset <= 0 then currentCamera.FieldOfView = zoomBase end
			zoomBase = nil
		end
	end })

	---Applies the system level settings. With off set, everything is put back instead.
	local function applySystem(off)
		local sensitivity = off and 100 or Config.mouseSens
		local hideUi = not off and Config.hideCoreUi
		local lowQuality = not off and Config.lowGraphics

		-- Mouse sensitivity.
		if sensitivity ~= 100 then
			if not sensBase then sensBase = userInputService.MouseDeltaSensitivity end
			local wanted = sensBase * sensitivity / 100
			if userInputService.MouseDeltaSensitivity ~= wanted then
				pcall(function() userInputService.MouseDeltaSensitivity = wanted end)
			end
		elseif sensBase then
			pcall(function() userInputService.MouseDeltaSensitivity = sensBase end)
			sensBase = nil
		end

		-- The built-in Roblox interface (chat, player list, backpack, emotes, health).
		if hideUi then
			if not hiddenCore then
				hiddenCore = {}
				for _, kind in ipairs(CORE_TYPES) do
					local ok, enabled = pcall(starterGui.GetCoreGuiEnabled, starterGui, kind)
					hiddenCore[kind] = ok and enabled or false
				end
			end
			for _, kind in ipairs(CORE_TYPES) do pcall(starterGui.SetCoreGuiEnabled, starterGui, kind, false) end
		elseif hiddenCore then
			for kind, was in pairs(hiddenCore) do pcall(starterGui.SetCoreGuiEnabled, starterGui, kind, was) end
			hiddenCore = nil
		end

		-- Lowest render quality.
		if lowQuality then
			if not qualityBase then
				local ok, level = pcall(function() return settings().Rendering.QualityLevel end)
				if ok then qualityBase = level end
			end
			if qualityBase then pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end) end
		elseif qualityBase then
			pcall(function() settings().Rendering.QualityLevel = qualityBase end)
			qualityBase = nil
		end
	end

	table.insert(hooks.render, { "system tweaks", function(dt, now)
		if now < nextSystem then return end
		nextSystem = now + 1
		applySystem()
	end })

	local function restore()
		if zoomBase then
			currentCamera.FieldOfView = zoomBase
			zoomBase = nil
		end
		applySystem(true)
	end
	moduleCleanup["system tweaks"] = restore
	table.insert(hooks.clean, restore)

	-- Rejoin after being kicked or disconnected.
	pcall(function()
		table.insert(connections, guiService.ErrorMessageChanged:Connect(function(message)
			if not Config.autoRejoin or message == nil or message == "" then return end
			task.delay(2, function()
				if Config.autoRejoin then
					pcall(teleportService.Teleport, teleportService, game.PlaceId, localPlayer)
				end
			end)
		end))
	end)

	---Same server when there are other players to keep it open, otherwise any server.
	function hooks.rejoin()
		if #playersService:GetPlayers() <= 1 then
			return pcall(teleportService.Teleport, teleportService, game.PlaceId, localPlayer)
		end
		return pcall(teleportService.TeleportToPlaceInstance, teleportService, game.PlaceId, game.JobId, localPlayer)
	end

	---Joins another public server of this game that still has room.
	function hooks.serverHop()
		local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Desc&limit=100"
		local ok, response = pcall(request, { Url = url, Method = "GET" })
		if not ok or type(response) ~= "table" or response.StatusCode ~= 200 then return false, "Server list unavailable" end

		local decoded, data = pcall(function() return httpService:JSONDecode(response.Body) end)
		if not decoded or type(data) ~= "table" or type(data.data) ~= "table" then return false, "Server list unreadable" end

		local choices = {}
		for _, server in ipairs(data.data) do
			if type(server) == "table" and server.id ~= game.JobId and (server.playing or 0) < (server.maxPlayers or 0) then
				table.insert(choices, server.id)
			end
		end
		if #choices == 0 then return false, "No other server with room" end

		local joined = pcall(teleportService.TeleportToPlaceInstance, teleportService, game.PlaceId, choices[math.random(1, #choices)], localPlayer)
		return joined, joined and "Joining another server" or "Teleport failed"
	end

	function hooks.copyJoin()
		local text = string.format(
			'game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)',
			game.PlaceId, game.JobId
		)
		return (pcall(setclipboard, text))
	end

	---Teleports next to the first player whose name or display name starts with the text.
	function hooks.gotoPlayer(query)
		query = string.lower(query or "")
		if query == "" then return false, "Type a name first" end

		local found
		for _, player in ipairs(playersService:GetPlayers()) do
			if player ~= localPlayer then
				local name, display = string.lower(player.Name), string.lower(player.DisplayName or "")
				if string.sub(name, 1, #query) == query or string.sub(display, 1, #query) == query then
					found = player
					break
				end
			end
		end
		if not found then return false, "No player starts with that" end

		local _, _, targetRoot = getCharacterParts(found)
		local _, _, root = getCharacterParts(localPlayer)
		if not (targetRoot and root) then return false, "No character to go to" end

		local goal = (targetRoot.CFrame * CFrame.new(0, 0, 4)).Position
		root.CFrame = CFrame.lookAt(goal, targetRoot.Position)
		root.AssemblyLinearVelocity = Vector3.zero
		return true, found.DisplayName
	end
end)()

-- Extras: rage. Rapid fire, anti aim, hitbox expander, knife and gun swap, dodge jumps.
;(function()
	local expanded = setmetatable({}, { __mode = "k" })
	local nextHitbox, nextDodge, swapAt = 0, 0, 0
	local swapState = nil
	local flip = 1
	local sideSign, sideUntil = 1, 0

	local function nearestEnemyRoot(root)
		local best, bestDistance
		for _, player in ipairs(getPlayers()) do
			if player ~= localPlayer and isEnemy(player) then
				local _, _, targetRoot = getCharacterParts(player)
				if targetRoot then
					local distance = (targetRoot.Position - root.Position).Magnitude
					if not bestDistance or distance < bestDistance then best, bestDistance = targetRoot, distance end
				end
			end
		end
		return best, bestDistance
	end

	-- Clicks at the chosen rate while the rapid fire key is held, or while the mouse button is held when no key is set.
	local nextRapid, rapidActive = 0, false
	table.insert(hooks.render, { "rapid fire", function(dt, now)
		local active = false
		if Config.rapidFire and not Config.aiPlay and not userInputService:GetFocusedTextBox() then
			if binds.rapid == Enum.KeyCode.Unknown then
				active = userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
			else
				active = hooks.held(binds.rapid)
			end
			active = active or hooks.touch.rapid
		end
		if not active then
			rapidActive = false
			return
		end

		-- A fixed schedule instead of a pause after each click, so the rate does not depend on the frame rate.
		if not rapidActive then
			rapidActive, nextRapid = true, now
		end
		if now < nextRapid then return end

		nextRapid = math.max(nextRapid + 1 / math.max(Config.rapidRate, 1), now - 1 / math.max(Config.rapidRate, 1))
		fireClick(0)
	end })

	-- Turns the character against the camera, so what other players see is not where you are looking.
	table.insert(hooks.step, { "anti aim", function()
		if not Config.antiAim or Config.spinEnabled or Config.flyEnabled or Config.aiPlay then return end
		if Config.farmEnabled then return end

		local _, _, root = getCharacterParts(localPlayer)
		if not root then return end

		local look = currentCamera.CFrame.LookVector
		local yaw = math.atan2(-look.X, -look.Z)
		local angle = math.rad(Config.antiAimAngle)
		local mode = Config.antiAimMode

		if mode == "Jitter" then
			flip = -flip
			yaw += flip * angle / 2
		elseif mode == "Random" then
			yaw += (math.random() * 2 - 1) * angle
		else
			local foe = nearestEnemyRoot(root)
			if not foe then return end
			local offset = foe.Position - root.Position
			yaw = math.atan2(-offset.X, -offset.Z)
			if mode == "Backwards" then
				yaw += math.pi
			else
				-- Side on to the enemy, switching sides now and then.
				local now = os.clock()
				if now > sideUntil then
					sideUntil = now + 0.4 + math.random() * 0.6
					sideSign = -sideSign
				end
				yaw += sideSign * math.pi / 2
			end
		end

		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	end })

	local function putBack(part, saved)
		if not part.Parent then return end
		pcall(function()
			part.Size, part.Transparency, part.CanCollide = saved.size, saved.transparency, saved.collide
		end)
	end

	local function restoreHitboxes()
		for part, saved in pairs(expanded) do
			expanded[part] = nil
			putBack(part, saved)
		end
	end

	-- Enlarges one body part of every enemy on this client. The original sizes are kept and put back.
	table.insert(hooks.step, { "hitbox", function(dt, now)
		if not Config.hitboxEnabled then
			if next(expanded) ~= nil then restoreHitboxes() end
			return
		end
		if now < nextHitbox then return end
		nextHitbox = now + 0.2

		local wanted = Config.hitboxPart == "Head" and "Head" or "HumanoidRootPart"
		local size = Vector3.new(Config.hitboxSize, Config.hitboxSize, Config.hitboxSize)
		local transparency = Config.hitboxAlpha / 100
		local live = {}

		for _, player in ipairs(getPlayers()) do
			if player == localPlayer or not isEnemy(player) then continue end
			local character = player.Character
			local part = character and character:FindFirstChild(wanted)
			if not part then continue end

			live[part] = true
			if not expanded[part] then
				expanded[part] = { size = part.Size, transparency = part.Transparency, collide = part.CanCollide }
			end
			if part.Size ~= size then part.Size = size end
			if part.Transparency ~= transparency then part.Transparency = transparency end
			if part.CanCollide then part.CanCollide = false end
		end

		-- Players who left, teams that changed and a different part choice all go back to normal.
		for part, saved in pairs(expanded) do
			if not live[part] then
				expanded[part] = nil
				putBack(part, saved)
			end
		end
	end })

	-- Knife in hand when an enemy is close, the gun slot otherwise.
	table.insert(hooks.render, { "weapon swap", function(dt, now)
		if not Config.swapEnabled then
			swapState = nil
			return
		end
		if Config.aiPlay or Config.farmEnabled then return end
		if now - swapAt < 0.5 or not compat.active() or userInputService:GetFocusedTextBox() then return end

		local _, _, root = getCharacterParts(localPlayer)
		if not root then return end

		local _, distance = nearestEnemyRoot(root)
		local close = distance ~= nil and distance <= Config.swapDist
		local wanted = close and "knife" or "gun"
		if wanted ~= swapState then
			swapState, swapAt = wanted, now
			local key = SLOT_KEYS[close and Config.swapKnife or Config.swapGun]
			if key then compat.keytap(key) end
		end
	end })

	-- Now and then a jump while an enemy close by can see you.
	table.insert(hooks.step, { "dodge jump", function(dt, now)
		if not Config.dodgeJump or now < nextDodge then return end
		nextDodge = now + Config.dodgeInterval / 1000 * (0.7 + math.random() * 0.6)

		local _, _, root = getCharacterParts(localPlayer)
		if not root then return end

		for _, player in ipairs(getPlayers()) do
			if player ~= localPlayer and isEnemy(player) then
				local character, _, targetRoot = getCharacterParts(player)
				if targetRoot and (targetRoot.Position - root.Position).Magnitude < 70 and isVisibleCached(targetRoot, character) then
					ai.jumpNow = true
					return
				end
			end
		end
	end })

	moduleCleanup.hitbox = restoreHitboxes
	table.insert(hooks.clean, restoreHitboxes)
end)()

-- Extras: aimbot. Auto fire, recoil control, target readout and the aimbot FOV circle style.
-- These run next to the aimbot and read its target, the soft aim code is not involved.
;(function()
	local info = nil
	local FOV_COLORS = {
		White = Color3.fromRGB(255, 255, 255), Red = Color3.fromRGB(255, 80, 80), Green = Color3.fromRGB(90, 255, 140),
		Cyan = Color3.fromRGB(80, 230, 255), Yellow = Color3.fromRGB(255, 220, 90),
	}

	-- Clicks while the aimbot has a target and the cursor is on it.
	table.insert(hooks.render, { "aim auto fire", function(dt, now, mouse)
		local part = aimTargetPart
		if not Config.aimAutoFire or Config.aiPlay or not aimLocked or not part or not part.Parent then return end

		local screenPos, onScreen = currentCamera:WorldToViewportPoint(part.Position)
		if not onScreen then return end

		-- The size of the target part on the screen, so a far head is a small mark.
		local scale = perFrame.viewport.Y / (2 * math.max(screenPos.Z, 1) * math.tan(math.rad(currentCamera.FieldOfView / 2)))
		local radius = math.clamp(part.Size.Y * 0.5 * scale, 4, 40)
		if (Vector2.new(screenPos.X, screenPos.Y) - mouse).Magnitude <= radius then
			fireClick(Config.aimAutoFireDelay)
		end
	end })

	-- Pulls the view down while the fire button is held.
	table.insert(hooks.render, { "recoil control", function()
		if Config.aimRecoil <= 0 or Config.aiPlay or not compat.canMove() or not compat.active() then return end
		if userInputService:GetFocusedTextBox() then return end
		if not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
		compat.move(0, Config.aimRecoil)
	end })

	-- Style of the aimbot FOV circle (the soft aim circle has its own settings).
	table.insert(hooks.render, { "aim circle style", function()
		if aimCircle.Thickness ~= Config.aimFovThickness then aimCircle.Thickness = Config.aimFovThickness end

		local name = Config.aimFovColor
		local color = name == "Accent" and ACCENT or FOV_COLORS[name] or FOV_COLORS.White
		if aimCircle.Color ~= color then aimCircle.Color = color end
	end })

	-- Name, health and distance of the aimbot target, under the circle.
	table.insert(hooks.render, { "aim target info", function(dt, now, mouse)
		if not Config.aimTargetInfo then
			if info and info.Visible then info.Visible = false end
			return
		end
		if not info then
			info = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = Color3.fromRGB(255, 255, 255), Visible = false })
		end

		local part, player = aimTargetPart, aimLocked
		if not (part and part.Parent and player) then
			info.Visible = false
			return
		end

		local _, humanoid = getCharacterParts(player)
		local text = string.format(
			"%s  %d hp  %d studs", player.DisplayName, humanoid and math.floor(humanoid.Health) or 0,
			math.floor((currentCamera.CFrame.Position - part.Position).Magnitude)
		)
		if info.Text ~= text then info.Text = text end
		info.Position = Vector2.new(mouse.X, mouse.Y + Config.aimFov + 12)
		info.Visible = true
	end })

	table.insert(hooks.clean, function()
		if info then
			pcall(function() info:Remove() end)
			info = nil
		end
	end)
end)()

-- Extras: hit feedback. A sound and a marker when an enemy you are shooting at loses health.
;(function()
	local health = setmetatable({}, { __mode = "k" })
	local nextScan = 0
	local sound = nil
	local marker, markerShown = nil, false
	local markerUntil, markerKill = 0, false

	local function hit(kill)
		if Config.hitSound then
			if not sound then
				sound = Instance.new("Sound")
				sound.Name = tostring(math.random(10000, 99999))
				sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
				sound.Parent = cloneref(game:GetService("SoundService"))
			end
			sound.Volume = math.clamp(Config.hitVolume / 100, 0, 1) * 2
			sound.PlaybackSpeed = kill and 1.45 or 1
			sound.TimePosition = 0
			sound:Play()
		end
		if Config.hitMarker then
			markerUntil, markerKill = os.clock() + 0.18, kill
		end
	end

	table.insert(hooks.render, { "hit feedback", function(dt, now)
		local wantMarker = Config.hitMarker

		if Config.hitSound or wantMarker then
			if now >= nextScan then
				nextScan = now + 0.03
				local shooting = now - lastShot < 0.3 or userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)

				-- A drop in an enemy's health while you are firing counts as a hit.
				for _, player in ipairs(getPlayers()) do
					if player == localPlayer or not isEnemy(player) then continue end
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					if not humanoid then continue end

					local current = humanoid.Health
					local before = health[humanoid]
					health[humanoid] = current
					if shooting and before and current < before - 0.5 then hit(current <= 0) end
				end
			end
		elseif next(health) ~= nil then
			table.clear(health)
		end

		if wantMarker and now < markerUntil then
			if not marker then
				marker = {}
				for index = 1, 4 do
					marker[index] = newDrawing("Line", { Thickness = 2, Color = Color3.fromRGB(255, 255, 255), Visible = false })
				end
			end

			local center = perFrame.viewport / 2
			local fade = (markerUntil - now) / 0.18
			local color = markerKill and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(255, 255, 255)
			local near, far = 5, 14
			for index, line in ipairs(marker) do
				local sx, sy = index % 2 == 1 and -1 or 1, index <= 2 and -1 or 1
				line.From = center + Vector2.new(sx * near, sy * near)
				line.To = center + Vector2.new(sx * far, sy * far)
				line.Color, line.Transparency, line.Visible = color, fade, true
			end
			markerShown = true
		elseif markerShown then
			markerShown = false
			for _, line in ipairs(marker) do line.Visible = false end
		end
	end })

	table.insert(hooks.clean, function()
		if sound then
			pcall(function() sound:Destroy() end)
			sound = nil
		end
		if marker then
			for _, line in ipairs(marker) do pcall(function() line:Remove() end) end
			marker = nil
		end
	end)
end)()

-- Extras: HUD readouts and color grading.
;(function()
	local speedText, enemyText = nil, nil
	local lastPosition, speedValue = nil, 0
	local nextCount = 0
	local grade = nil

	table.insert(hooks.render, { "hud speed", function(dt)
		if not Config.hudSpeed then
			if speedText and speedText.Visible then speedText.Visible = false end
			lastPosition = nil
			return
		end
		if not speedText then
			speedText = newDrawing("Text", { Size = 15, Center = true, Outline = true, Color = ACCENT, Visible = false })
		end

		local _, _, root = getCharacterParts(localPlayer)
		if not root then
			speedText.Visible = false
			lastPosition = nil
			return
		end

		local position = root.Position
		if lastPosition and dt > 0 then
			local moved = Vector3.new(position.X - lastPosition.X, 0, position.Z - lastPosition.Z).Magnitude / dt
			-- A teleport is not speed.
			if moved < 400 then speedValue += (moved - speedValue) * math.min(dt * 12, 1) end
		end
		lastPosition = position

		local text = string.format("%d studs/s", math.floor(speedValue + 0.5))
		if speedText.Text ~= text then speedText.Text = text end
		if speedText.Color ~= ACCENT then speedText.Color = ACCENT end
		speedText.Position = Vector2.new(perFrame.viewport.X / 2, perFrame.viewport.Y - 120)
		speedText.Visible = true
	end })

	table.insert(hooks.render, { "hud enemies", function(dt, now)
		if not Config.hudEnemies then
			if enemyText and enemyText.Visible then enemyText.Visible = false end
			nextCount = 0
			return
		end
		if not enemyText then
			enemyText = newDrawing("Text", { Size = 14, Center = true, Outline = true, Color = Color3.fromRGB(255, 255, 255), Visible = false })
		end

		if now >= nextCount then
			nextCount = now + 0.25
			local alive = 0
			for _, player in ipairs(getPlayers()) do
				if player ~= localPlayer and isEnemy(player) and getCharacterParts(player) then alive += 1 end
			end
			local text = alive == 1 and "1 enemy left" or (alive .. " enemies left")
			if enemyText.Text ~= text then enemyText.Text = text end
		end
		enemyText.Position = Vector2.new(perFrame.viewport.X / 2, 54)
		enemyText.Visible = true
	end })

	-- A color correction layer over the whole screen. The no post effects option leaves it alone.
	table.insert(hooks.render, { "color grade", function()
		if not Config.colorGrade then
			if grade and grade.Enabled then grade.Enabled = false end
			return
		end
		if not (grade and grade.Parent) then
			grade = Instance.new("ColorCorrectionEffect")
			grade.Name = tostring(math.random(10000, 99999))
			grade.Parent = lightingService
			hooks.grade = grade
		end

		local saturation, contrast = Config.gradeSaturation / 100, Config.gradeContrast / 100
		if grade.Saturation ~= saturation then grade.Saturation = saturation end
		if grade.Contrast ~= contrast then grade.Contrast = contrast end
		if not grade.Enabled then grade.Enabled = true end
	end })

	table.insert(hooks.clean, function()
		if speedText then pcall(function() speedText:Remove() end) end
		if enemyText then pcall(function() enemyText:Remove() end) end
		speedText, enemyText = nil, nil
		if grade then
			pcall(function() grade:Destroy() end)
			grade, hooks.grade = nil, nil
		end
	end)
end)()

-- Extras: config tools. Backup, last session, copy, rename, links and per-tab resets.
;(function()
	local BACKUP = CONFIG_FOLDER .. "/_backup.json"
	local LAST = CONFIG_FOLDER .. "/_last.json"
	local lastAuto = os.clock()

	local function write(path)
		return pcall(function()
			if not compat.isfolder(CONFIG_FOLDER) then compat.makefolder(CONFIG_FOLDER) end
			compat.writefile(path, encodeConfig())
		end)
	end

	---Keep the current settings before something replaces them. The startup load is not counted.
	function hooks.backup()
		if hooks.ready and Config.cfgBackup then write(BACKUP) end
	end

	---Restoring swaps: the settings from before the restore become the new backup.
	function hooks.restoreBackup()
		return loadConfig("_backup")
	end

	function hooks.loadLast()
		return loadConfig("_last")
	end

	function hooks.copyConfig(from, to)
		return (pcall(function()
			local path = configPath(from)
			if not compat.isfile(path) then error("missing") end
			compat.writefile(configPath(to), compat.readfile(path))
		end))
	end

	function hooks.renameConfig(from, to)
		if from == to or not hooks.copyConfig(from, to) then return false end
		return deleteConfig(from)
	end

	function hooks.importLink(url)
		if type(url) ~= "string" or not string.match(url, "^https?://") then return false end
		local ok, response = pcall(request, { Url = url, Method = "GET" })
		if not ok or type(response) ~= "table" or response.StatusCode ~= 200 then return false end
		return importConfig(response.Body)
	end

	---Puts every setting of one tab back to its default.
	function hooks.resetTab(name)
		local bucket = hooks.tabKeys[name]
		if not bucket then return false end

		hooks.backup()
		for key in pairs(bucket) do
			if defaults[key] ~= nil then Config[key] = defaults[key] end
		end
		refreshWidgets()
		return true
	end

	table.insert(hooks.render, { "config autosave", function(dt, now)
		local minutes = Config.cfgAutoMinutes
		if minutes <= 0 then
			lastAuto = now
		elseif now - lastAuto >= minutes * 60 then
			lastAuto = now
			write(LAST)
		end
	end })

	table.insert(hooks.clean, function()
		if Config.cfgSaveOnExit then write(LAST) end
	end)
end)()

-- Extras: interface. Menu look settings and the custom or rainbow accent.
;(function()
	local rainbowOn, nextRainbow = false, 0

	---A color from text such as "#ff8800" or "ff8800", nil when it is not a hex color.
	function hooks.parseHex(text)
		local hex = string.match(text or "", "^%s*#?(%x%x%x%x%x%x)%s*$")
		if not hex then return nil end
		return Color3.fromRGB(
			tonumber(string.sub(hex, 1, 2), 16), tonumber(string.sub(hex, 3, 4), 16), tonumber(string.sub(hex, 5, 6), 16)
		)
	end

	---The accent that applies right now: the custom color when one is set, otherwise the chosen theme.
	function hooks.syncAccent()
		local color = hooks.parseHex(Config.customAccent)
		if color then
			hooks.applyTheme(UI.customTheme(color))
		else
			applyThemeByName(Config.theme)
		end
	end

	---Picking a theme replaces a custom or rainbow accent.
	function hooks.pickTheme(name)
		Config.customAccent, Config.rainbowAccent = "", false
		if widgets.customAccent then widgets.customAccent:set("") end
		if widgets.rainbowAccent then widgets.rainbowAccent:set(false) end
		applyThemeByName(name)
	end

	function hooks.applyInterface()
		window:setBubbles(Config.menuBubbles / 100)
		window.bubbleSpeed = Config.menuBubbleSpeed / 100
		window:setBlurSize(Config.menuBlurSize)
		window:setOpacity(Config.menuOpacity)
		window.rimSpin, window.fizzOn, window.tabFade = Config.menuRimSpin, Config.menuFizz, Config.menuFade
		window.locked = Config.menuLock
		window:setNotify(Config.notifyEnabled, Config.notifySeconds, Config.notifySide)
		compat.mode(Config.mobileMode)
		window:setScale(Config.menuScale, Config.menuFit)
		if window.dock then window.dock.scale.Scale = Config.touchScale / 100 end
		if hooks.device then
			for index, line in ipairs(compat.report()) do
				if hooks.device[index] then hooks.device[index].Text = line end
			end
		end
		if not Config.rainbowAccent then hooks.syncAccent() end
	end
	table.insert(hooks.refresh, hooks.applyInterface)

	-- The accent drifts through the colors while the menu is open.
	table.insert(hooks.render, { "rainbow accent", function(dt, now)
		if not Config.rainbowAccent then
			if rainbowOn then
				rainbowOn = false
				hooks.syncAccent()
			end
			return
		end
		rainbowOn = true
		if now < nextRainbow or not window.gui.Enabled then return end

		nextRainbow = now + 0.12
		hooks.applyTheme(UI.customTheme(Color3.fromHSV((now / 14) % 1, 0.65, 1)))
	end })
end)()

-- Menu.
window = UI.new("sprite", "rivals")

local function toggle(tab, text, key, extra)
	local handle = tab:Toggle(text, Config[key], function(state)
		Config[key] = state
		if extra then extra(state) end
	end)
	widgets[key] = handle
	hooks.track(tab, key)
	return handle
end

local function slider(tab, text, key, minimum, maximum, extra)
	widgets[key] = tab:Slider(text, minimum, maximum, Config[key], function(value)
		Config[key] = value
		if extra then extra(value) end
	end)
	hooks.track(tab, key)
end

local function dropdown(tab, text, key, options, extra)
	dropdownOptions[key] = options
	widgets[key] = tab:Dropdown(text, options, Config[key], function(value)
		Config[key] = value
		if extra then extra(value) end
	end)
	hooks.track(tab, key)
end

---A text setting. The value is stored when the box loses focus.
function hooks.input(tab, text, key, placeholder, extra)
	widgets[key] = tab:Input(text, Config[key], function(value)
		Config[key] = value
		if extra then extra(value) end
	end, placeholder)
	hooks.track(tab, key)
end

local function bind(tab, text, name)
	bindWidgets[name] = tab:Bind(text, binds[name], function(key)
		-- Clearing the menu key would lock you out of the menu.
		if name == "menu" and key == Enum.KeyCode.Unknown then
			key = defaultBinds.menu
			bindWidgets.menu:set(key)
			window:Notify("The menu key can't be cleared", 2)
		end
		binds[name] = key
	end)
end

local moveTab = window:Tab("Move")
moveTab:Section("Ground")
toggle(moveTab, "Walk speed", "walkEnabled")
slider(moveTab, "Walk speed value", "walkSpeed", 16, 120)
slider(moveTab, "Ground response", "walkResponse", 4, 40)
moveTab:Section("Slide")
moveTab:Label("Hold Ctrl or C while moving")
toggle(moveTab, "Slide boost", "slideEnabled")
slider(moveTab, "Slide speed", "slideSpeed", 16, 150)
slider(moveTab, "Slide decay", "slideDecay", 0, 80)
slider(moveTab, "Slide steering", "slideSteer", 1, 12)
slider(moveTab, "Slide jump boost (%)", "slideJumpBoost", 100, 200)
bind(moveTab, "Extra slide key", "slide")
moveTab:Section("Jumping")
toggle(moveTab, "Air jump (double / infinite)", "infJump")
slider(moveTab, "Air jumps (0 = unlimited)", "airJumps", 0, 10)
slider(moveTab, "Air jump power", "airJumpPower", 30, 120)
toggle(moveTab, "Jump power", "jumpEnabled")
slider(moveTab, "Jump power value", "jumpPower", 40, 150)
toggle(moveTab, "Bunny hop (hold space)", "bhop")
moveTab:Section("Air control")
toggle(moveTab, "Air strafe", "airStrafe")
slider(moveTab, "Air acceleration", "airAccel", 5, 100)
slider(moveTab, "Air wish speed", "airWish", 2, 30)
moveTab:Section("Safety")
toggle(moveTab, "Move assist (speed fallback)", "moveAssist")
toggle(moveTab, "Speed limiter", "speedLimit")
slider(moveTab, "Max speed", "speedLimitValue", 20, 300)
moveTab:Section("Flight")
local flyToggle = toggle(moveTab, "Fly", "flyEnabled")
bind(moveTab, "Fly key", "fly")
dropdown(moveTab, "Fly mode", "flyMode", { "Linear", "Smooth" })
slider(moveTab, "Fly speed", "flySpeed", 10, 300)
toggle(moveTab, "Noclip while flying", "flyNoclip")
slider(moveTab, "Vertical speed (%)", "flyVertical", 25, 200)
moveTab:Section("Other")
toggle(moveTab, "Noclip", "noclip")
bind(moveTab, "Noclip key", "noclip")
moveTab:Section("Sprint")
toggle(moveTab, "Sprint (hold key)", "sprintEnabled")
slider(moveTab, "Sprint speed", "sprintSpeed", 16, 150)
bind(moveTab, "Sprint key", "sprint")
moveTab:Section("Gravity and falling")
toggle(moveTab, "Gravity override", "gravityEnabled")
slider(moveTab, "Gravity", "gravityValue", 20, 300)
slider(moveTab, "Fall speed cap (0 = off)", "fallLimit", 0, 200)
toggle(moveTab, "Glide (hold space)", "glideEnabled")
slider(moveTab, "Glide fall speed", "glideSpeed", 2, 40)
toggle(moveTab, "No ragdoll", "noRagdoll")
toggle(moveTab, "Void rescue", "antiVoid")
moveTab:Section("Teleport")
toggle(moveTab, "Click teleport", "clickTp")
bind(moveTab, "Teleport key", "clickTp")

local mainTab = window:Tab("Misc")
mainTab:Section("Camera")
slider(mainTab, "FOV offset", "fovOffset", 0, 40)
toggle(mainTab, "Third person", "thirdPerson", applyThirdPerson)
slider(mainTab, "Third person distance", "thirdPersonDistance", 4, 40, applyThirdPerson)
toggle(mainTab, "Zoom (hold key)", "zoomEnabled")
slider(mainTab, "Zoom FOV", "zoomFov", 10, 60)
bind(mainTab, "Zoom key", "zoom")
mainTab:Section("Performance")
toggle(mainTab, "FPS cap", "fpsEnabled")
slider(mainTab, "FPS cap value", "fpsCap", 30, 500)
fpsStatus = mainTab:Label("Status: restored to 240")
mainTab:Section("Utility")
toggle(mainTab, "Anti AFK", "antiAfk")
mainTab:Section("System")
slider(mainTab, "Mouse sensitivity (%)", "mouseSens", 25, 200)
toggle(mainTab, "Hide Roblox UI", "hideCoreUi")
toggle(mainTab, "Low graphics", "lowGraphics")
mainTab:Section("Sound")
toggle(mainTab, "Hit sound", "hitSound")
slider(mainTab, "Hit volume", "hitVolume", 0, 100)
mainTab:Section("Server")
toggle(mainTab, "Auto rejoin", "autoRejoin")
mainTab:Button("Rejoin server", function()
	window:Notify("Rejoining")
	hooks.rejoin()
end)
mainTab:Button("Server hop", function()
	local _, message = hooks.serverHop()
	window:Notify(message or "Hopping")
end)
mainTab:Button("Copy join script", function()
	window:Notify(hooks.copyJoin() and "Join script copied" or "Clipboard unavailable")
end)
hooks.input(mainTab, "Player name", "gotoName", "name")
mainTab:Button("Teleport to player", function()
	local ok, message = hooks.gotoPlayer(widgets.gotoName.get())
	window:Notify(ok and ("Teleported to " .. message) or message)
end)

local espTab = window:Tab("ESP")
espTab:Section("Player ESP")
toggle(espTab, "ESP enabled", "espEnabled")
bind(espTab, "ESP toggle key", "espToggle")
toggle(espTab, "Box", "espBox")
dropdown(espTab, "Box style", "espBoxStyle", { "Full", "Corner" })
toggle(espTab, "Skeleton", "espSkeleton")
toggle(espTab, "Head dot", "espHeadDot")
toggle(espTab, "Look direction line", "espLookLine")
toggle(espTab, "Name", "espName")
toggle(espTab, "Health bar", "espHealth")
toggle(espTab, "Health number", "espHealthText")
toggle(espTab, "Distance", "espDistance")
toggle(espTab, "Tracers", "espTracer")
dropdown(espTab, "Tracer origin", "espTracerOrigin", { "Bottom", "Center", "Cursor" })
toggle(espTab, "Chams", "espChams")
slider(espTab, "Chams opacity (%)", "chamsOpacity", 0, 100)
toggle(espTab, "Off-screen arrows", "espArrows")
slider(espTab, "Arrow radius", "espArrowRadius", 60, 400)
espTab:Section("Settings")
toggle(espTab, "Visibility colors", "espVisColors")
dropdown(espTab, "Color palette", "espPalette", PALETTE_NAMES, applyPalette)
toggle(espTab, "Team check", "teamCheck")
slider(espTab, "Max distance", "espMaxDist", 100, 5000)
espTab:Section("Style")
toggle(espTab, "Box fill", "espBoxFill")
slider(espTab, "Fill opacity (%)", "espFillOpacity", 0, 100)
dropdown(espTab, "Color mode", "espColorMode", { "Palette", "Team", "Health", "Distance", "Rainbow" })
slider(espTab, "Line thickness", "espThickness", 1, 4)
slider(espTab, "Text size", "espTextSize", 10, 22)
dropdown(espTab, "Name style", "espNameMode", { "Display", "Username", "Both" })
toggle(espTab, "Held item", "espWeapon")
slider(espTab, "Head dot size (%)", "espHeadDotSize", 50, 250)
slider(espTab, "Look line length", "espLookLength", 2, 30)
slider(espTab, "Arrow size", "espArrowSize", 8, 40)
espTab:Section("Chams")
toggle(espTab, "Chams outline", "chamsOutline")
toggle(espTab, "Chams through walls", "chamsWalls")
espTab:Section("Filters")
toggle(espTab, "Only visible enemies", "espVisibleOnly")
slider(espTab, "Only below health (%)", "espHpFilter", 0, 100)
toggle(espTab, "Highlight target", "espTargetHighlight")

local aimTab = window:Tab("Aim")
aimTab:Section("Aimbot")
toggle(aimTab, "Enabled", "aimEnabled")
bind(aimTab, "Lock key", "aim")
toggle(aimTab, "Hold mode (off = toggle)", "aimHold")
toggle(aimTab, "Only while firing", "aimOnFire")
dropdown(aimTab, "Aim part", "aimPart", { "Head", "Torso", "Closest" })
dropdown(aimTab, "Target priority", "aimTargetMode", { "Cursor", "Distance", "Lowest HP" })
dropdown(aimTab, "Aim method", "aimMethod", { "Camera", "Mouse" })
toggle(aimTab, "Show FOV circle", "aimShowFov")
slider(aimTab, "FOV size", "aimFov", 30, 600)
toggle(aimTab, "Smoothing", "aimSmoothOn")
slider(aimTab, "Smoothness", "aimSmooth", 1, 99)
slider(aimTab, "Deadzone (px)", "aimDeadzone", 0, 20)
slider(aimTab, "Humanize jitter", "aimJitter", 0, 10)
slider(aimTab, "Max speed (0 = off)", "aimMaxSpeed", 0, 100)
slider(aimTab, "Prediction (ms)", "aimPrediction", 0, 200)
toggle(aimTab, "Wall check", "wallCheck")
toggle(aimTab, "Bone fallback", "aimBoneFallback")
toggle(aimTab, "Target line", "aimTargetLine")
toggle(aimTab, "Sticky target", "aimSticky")
slider(aimTab, "Reaction delay (ms)", "aimReaction", 0, 300)
toggle(aimTab, "Dynamic smoothing", "aimDynamic")
toggle(aimTab, "Velocity estimation", "aimVelocityEst")
toggle(aimTab, "Ping compensation", "aimAutoPing")
aimTab:Section("Soft Aim")
toggle(aimTab, "Soft aim enabled", "silentEnabled")
toggle(aimTab, "Soft aim FOV circle", "silentShowFov")
slider(aimTab, "Soft aim FOV size", "silentFov", 30, 800)
slider(aimTab, "Hit chance", "silentHitChance", 1, 100)
aimTab:Section("Targeting")
slider(aimTab, "Max distance (0 = off)", "aimMaxDist", 0, 1000)
toggle(aimTab, "Require right mouse", "aimNeedRmb")
toggle(aimTab, "Ignore friends", "aimIgnoreFriends")
slider(aimTab, "Vertical strength (%)", "aimVertical", 0, 100)
slider(aimTab, "Aim height offset", "aimHeight", -20, 20)
aimTab:Section("Pull")
dropdown(aimTab, "Pull curve", "aimCurve", { "Exponential", "Linear", "Ramp up" })
slider(aimTab, "Snap time (ms)", "aimSnap", 0, 300)
aimTab:Section("Projectiles")
slider(aimTab, "Bullet speed (0 = off)", "aimBulletSpeed", 0, 2000)
slider(aimTab, "Bullet drop", "aimDrop", 0, 200)
aimTab:Section("Firing")
toggle(aimTab, "Auto fire on target", "aimAutoFire")
slider(aimTab, "Auto fire delay (ms)", "aimAutoFireDelay", 0, 500)
slider(aimTab, "Recoil control", "aimRecoil", 0, 30)
aimTab:Section("Circle and readout")
slider(aimTab, "FOV circle thickness", "aimFovThickness", 1, 5)
dropdown(aimTab, "FOV color", "aimFovColor", { "White", "Red", "Green", "Cyan", "Yellow", "Accent" })
toggle(aimTab, "Target info text", "aimTargetInfo")

local rageTab = window:Tab("Rage")
rageTab:Section("Rage Aimbot")
toggle(rageTab, "Enabled", "rageEnabled")
toggle(rageTab, "Auto shoot", "rageAutoShoot")
toggle(rageTab, "Ignore walls", "rageIgnoreWalls")
slider(rageTab, "Shoot delay (ms)", "rageDelay", 0, 500)
rageTab:Section("Triggerbot")
toggle(rageTab, "Trigger enabled", "triggerEnabled")
slider(rageTab, "Trigger delay (ms)", "triggerDelay", 0, 500)
toggle(rageTab, "Trigger head only", "triggerHeadOnly")
rageTab:Section("Misc")
toggle(rageTab, "Spinbot", "spinEnabled")
slider(rageTab, "Spin speed", "spinSpeed", 1, 90)
rageTab:Section("Auto Farm")
toggle(rageTab, "Auto farm", "farmEnabled")
hooks.farm.label = rageTab:Label("Farm: off", 2)
dropdown(rageTab, "Queue with", "farmQueueHow", { "Auto", "Play menu", "Pad", "Remembered spot", "Off" })
dropdown(rageTab, "Match type", "farmQueueMode", { "Any", "1v1", "2v2", "3v3", "4v4", "5v5" })
dropdown(rageTab, "Kill method", "farmMethod", { "Void", "Gun" })
dropdown(rageTab, "Target mode", "farmMode", { "Nearest", "Lowest HP", "Random" })
slider(rageTab, "Void attempts", "farmVoidTries", 1, 8)
slider(rageTab, "Distance behind", "farmDistance", 1, 15)
slider(rageTab, "Height offset", "farmHeight", -5, 15)
slider(rageTab, "Match over after (s)", "farmIdle", 3, 30)
toggle(rageTab, "Keep farming after teleports", "farmResume")
hooks.input(rageTab, "Reload link", "farmUrl", "raw script link")
rageTab:Button("Copy farm report", function()
	local copied = hooks.farm.copyReport()
	window:Notify(copied and "Farm report copied" or "Farm report saved to SpriteRivals/farm_report.txt", 3)
end)
rageTab:Button("Find pads", function()
	local part, count = hooks.farm.find()
	if count == nil then
		window:Notify("Spawn in first", 2)
	elseif part then
		window:Notify(count .. " pad(s) found, using " .. part.Name, 3)
	else
		window:Notify("No pad found. Stand on one and press Remember this spot", 4)
	end
end)
rageTab:Button("Remember this spot as the pad", function()
	window:Notify(hooks.farm.remember() and "Pad remembered" or "Spawn in first", 2)
end)
rageTab:Button("Forget remembered pad", function()
	hooks.farm.forget()
	window:Notify("Remembered pad cleared", 2)
end)
rageTab:Section("Rapid Fire")
toggle(rageTab, "Rapid fire", "rapidFire")
bind(rageTab, "Rapid fire key", "rapid")
slider(rageTab, "Clicks per second", "rapidRate", 2, 40)
rageTab:Label("Without a key it fires while you hold the mouse", 2)
rageTab:Section("Anti Aim")
toggle(rageTab, "Anti aim", "antiAim")
dropdown(rageTab, "Mode", "antiAimMode", { "Jitter", "Random", "Backwards", "Sideways" })
slider(rageTab, "Angle", "antiAimAngle", 10, 180)
rageTab:Section("Hitbox")
toggle(rageTab, "Hitbox expander", "hitboxEnabled")
dropdown(rageTab, "Part", "hitboxPart", { "Head", "Body" })
slider(rageTab, "Hitbox size", "hitboxSize", 2, 20)
slider(rageTab, "Hitbox transparency (%)", "hitboxAlpha", 0, 100)
rageTab:Section("Weapon Swap")
toggle(rageTab, "Knife when close", "swapEnabled")
slider(rageTab, "Swap distance", "swapDist", 3, 40)
dropdown(rageTab, "Knife slot", "swapKnife", { "1", "2", "3", "4" })
dropdown(rageTab, "Gun slot", "swapGun", { "1", "2", "3", "4" })
rageTab:Section("Evasion")
toggle(rageTab, "Dodge jump", "dodgeJump")
slider(rageTab, "Dodge interval (ms)", "dodgeInterval", 300, 4000)

;(function()
	local aiTab = window:Tab("AI")
	aiTab:Section("Progress")
	ai.labels = { aiTab:Label("-"), aiTab:Label("-"), aiTab:Label("-", 2) }
	for _, label in ipairs(ai.labels) do label.TextTruncate = Enum.TextTruncate.AtEnd end
	ai.labelSets = { ai.labels }

	aiTab:Section("Learn")
	toggle(aiTab, "Watch and learn", "aiLearn")
	dropdown(aiTab, "Learn from", "aiSource", { "Top killers", "Everyone", "Named players", "Me" })
	aiTab:Input("Player names", "", ai.setNames, "name, name")
	toggle(aiTab, "Learn from own results", "aiSelfLearn")
	slider(aiTab, "Explore (%)", "aiExplore", 0, 50)

	aiTab:Section("Play")
	toggle(aiTab, "AI plays", "aiPlay")
	bind(aiTab, "AI play key", "ai")
	toggle(aiTab, "AI moves", "aiMove")
	toggle(aiTab, "AI avoids walls", "aiAvoid")
	toggle(aiTab, "AI hunts enemies", "aiHunt")
	slider(aiTab, "Move hold (%)", "aiHold", 25, 300)
	toggle(aiTab, "AI aims", "aiAim")
	toggle(aiTab, "AI looks around", "aiLook")
	dropdown(aiTab, "Aim mode", "aiAimMode", { "Camera", "Silent" })
	dropdown(aiTab, "Aim at", "aiAimPart", { "Auto", "Head", "Chest" })
	slider(aiTab, "Aim speed (%)", "aiAimSpeed", 25, 400)
	slider(aiTab, "Look speed (%)", "aiLookSpeed", 25, 300)
	toggle(aiTab, "AI shoots", "aiShoot")
	slider(aiTab, "Shoot delay (ms)", "aiShootDelay", 0, 500)
	toggle(aiTab, "Shoot through walls", "aiWalls")
	dropdown(aiTab, "Weapon slot", "aiSlot", { "Off", "1", "2", "3", "4" })

	aiTab:Section("Keys and mouse")
	toggle(aiTab, "Use my keys", "aiKeys")
	toggle(aiTab, "Use my mouse", "aiMouse")
	toggle(aiTab, "Learn my keys and clicks", "aiKeyLearn")
	slider(aiTab, "Key press rate (%)", "aiKeyRate", 0, 200)
	ai.keyLabels = { keys = aiTab:Label("-", 2), input = aiTab:Label("-", 2) }
	ai.keyLabels.keys.TextTruncate = Enum.TextTruncate.AtEnd
	ai.keyLabels.input.TextTruncate = Enum.TextTruncate.AtEnd
	aiTab:Button("Forget my keys", function()
		ai.forgetKeys()
		ai.refreshLabels()
		window:Notify("Forgot the learned keys")
	end)
	aiTab:Label("It learns the keys you press in fights")

	aiTab:Section("Brain")
	local brainName = aiTab:Input("Brain name", "default")
	local brainSaved = aiTab:Label("Saved: none")
	brainSaved.TextTruncate = Enum.TextTruncate.AtEnd

	function ai.refreshSaved()
		local names = ai.listBrains()
		brainSaved.Text = "Saved: " .. (#names > 0 and table.concat(names, ", ") or "none")
		brainName:set(ai.brain.name)
	end

	aiTab:Button("Save brain", function()
		local ok, name = ai.saveBrain(brainName.get())
		window:Notify(ok and ("Saved brain: " .. name) or "Save failed")
		ai.refreshSaved()
	end)
	aiTab:Button("Load brain", function()
		local loaded = ai.loadBrain(brainName.get())
		window:Notify(loaded and ("Loaded brain: " .. ai.brain.name) or "No brain with that name")
		if loaded then ai.refreshSaved() end
	end)
	aiTab:Button("New brain (keeps a backup)", function()
		ai.resetBrain()
		window:Notify("Started a new brain")
		ai.refreshSaved()
	end)
	toggle(aiTab, "Autosave", "aiAutoSave")
	toggle(aiTab, "Load last brain on start", "aiAutoload")

	aiTab:Section("Share")
	local brainText = aiTab:Input("Brain JSON", "", nil, "paste")
	local brainUrl = aiTab:Input("Brain link", "", nil, "https://")
	aiTab:Button("Copy brain to clipboard", function()
		local ok = pcall(function() setclipboard(ai.exportBrain()) end)
		window:Notify(ok and "Brain copied" or "Clipboard unavailable")
	end)
	aiTab:Button("Add pasted brain", function()
		window:Notify(ai.importBrain(brainText.get()) and "Brain added" or "Invalid brain text")
	end)
	aiTab:Button("Add brain from link", function()
		window:Notify(ai.fetchBrain(brainUrl.get()) and "Brain added" or "Could not load that link")
	end)
	aiTab:Label("Added brains merge into the current one")

	aiTab:Section("Skill")
	slider(aiTab, "Reaction time (ms)", "aiReaction", 0, 600)
	slider(aiTab, "Aim wobble", "aiWobble", 0, 100)
	slider(aiTab, "Shot timing spread (%)", "aiShootVariance", 0, 100)
	slider(aiTab, "Max range (0 = any)", "aiRange", 0, 500)
	slider(aiTab, "Target cone (0 = any)", "aiCone", 0, 180)

	aiTab:Section("Movement style")
	dropdown(aiTab, "Style", "aiStyle", { "Learned", "Aggressive", "Defensive", "Strafer" })
	slider(aiTab, "Keep distance (0 = off)", "aiDistance", 0, 120)
	slider(aiTab, "Retreat under health (%)", "aiRetreat", 0, 100)
	slider(aiTab, "Jump rate (%)", "aiJumpRate", 0, 300)
	toggle(aiTab, "Yield to my move keys", "aiYield")

	aiTab:Section("Learning")
	slider(aiTab, "Learning rate (%)", "aiLearnRate", 25, 400)
	slider(aiTab, "Pros to watch", "aiPros", 1, 8)
	slider(aiTab, "Watch range", "aiWatchRange", 40, 400)
	aiTab:Button("Reset statistics", function()
		ai.resetStats()
		ai.refreshLabels()
		window:Notify("Statistics reset")
	end)
	aiTab:Button("Delete saved brain", function()
		local ok, name = ai.deleteBrain(brainName.get())
		window:Notify(ok and ("Deleted brain: " .. name) or ("No brain named " .. name))
		ai.refreshSaved()
	end)

	ai.refreshSaved()
end)()

local visualsTab = window:Tab("Visuals")
visualsTab:Section("Crosshair")
toggle(visualsTab, "Custom crosshair", "crosshairEnabled")
toggle(visualsTab, "Center dot", "crosshairDot")
slider(visualsTab, "Length", "crosshairSize", 2, 30)
slider(visualsTab, "Gap", "crosshairGap", 0, 20)
slider(visualsTab, "Thickness", "crosshairThickness", 1, 4)
dropdown(visualsTab, "Color", "crosshairColor", { "Palette", "Accent", "Rainbow", "White", "Red", "Green", "Cyan", "Pink" })
slider(visualsTab, "Crosshair opacity (%)", "crosshairAlpha", 10, 100)
toggle(visualsTab, "Crosshair outline", "crosshairOutline")
toggle(visualsTab, "T-shaped crosshair", "crosshairT")
toggle(visualsTab, "Opens up when moving", "crosshairDynamic")
visualsTab:Section("Radar")
toggle(visualsTab, "Radar", "radarEnabled")
slider(visualsTab, "Radar size", "radarSize", 100, 300)
slider(visualsTab, "Radar range (studs)", "radarRange", 30, 500)
dropdown(visualsTab, "Corner", "radarCorner", { "Top left", "Top right", "Bottom left", "Bottom right" })
toggle(visualsTab, "Rotates with view", "radarRotate")
slider(visualsTab, "Background (%)", "radarAlpha", 0, 100)
visualsTab:Section("HUD")
toggle(visualsTab, "Active feature list", "hudList")
toggle(visualsTab, "Hit marker", "hitMarker")
toggle(visualsTab, "Speedometer", "hudSpeed")
toggle(visualsTab, "Enemy counter", "hudEnemies")
visualsTab:Section("World")
toggle(visualsTab, "Fullbright", "fullbright")
toggle(visualsTab, "No fog", "noFog")
toggle(visualsTab, "No post effects", "noPost")
toggle(visualsTab, "Time of day override", "clockOverride")
slider(visualsTab, "Time of day", "clockTime", 0, 24)
toggle(visualsTab, "No shadows", "noShadows")
toggle(visualsTab, "Color grading", "colorGrade")
slider(visualsTab, "Saturation", "gradeSaturation", -100, 100)
slider(visualsTab, "Contrast", "gradeContrast", -50, 100)

-- Skin changer, client side only: your own weapons show the skin, wrap and charm you pick. Nothing is sent to the server.
;(function()
	local FALLBACK_SKINS = [[
Assault Rifle=AK-47|AUG|Tommy Gun|Boneclaw Rifle|Gingerbread AUG|AKEY-47|100K Visits|10 Billion Visits|Phoenix Rifle
Bow=Compound Bow|Raven Bow|Dream Bow|Bat Bow|Frostbite Bow|Beloved Bow|Balloon Bow|Glorious Bow|Key Bow|Arch Bow
Burst Rifle=Electro Burst|Aqua Burst|FAMAS|Spectral Burst|Pine Burst
Crossbow=Pixel Crossbow|Harpoon Crossbow|Violin Crossbow|Crossbone|Frostbite Crossbow|Arch Crossbow|Glorious Crossbow
Distortion=Plasma Distortion|Magma Distortion|Cyber Distortion|Expirement D15|Sleighstortion
Energy Rifle=Hacker Rifle|Hydro Rifle|Void Rifle|Soul Rifle|New Years Energy Rifle
Flamethrower=Pixel Flamethrower|Lamethrower|Glitterthrower|Jack O' Thrower|Snowblower|Keythrower|Rainbowthrower
Grenade Launcher=Swashbuckler|Uranium Launcher|Gearnade Launcher|Skull Grenade Launcher|Snowball Launcher
Gunblade=Hyper Gunblade|Crude Gunblade|Gunsaw|Boneblade|Elf's Gunblade
Minigun=Lasergun 3000|Pixel Minigun|Fighter Jet|Pumpkin Minigun|Wrapped Minigun
Paintball Gun=Slime Gun|Boba Gun|Ketchup Gun|Brain Gun|Snowball Gun
RPG=Nuke Launcher|Spaceship Launcher|Squid Launcher|Pumpkin Launcher|Firework Launcher
Shotgun=Balloon Shotgun|Hyper Shotgun|Cactus Shotgun|Broomstick|Wrapped Shotgun
Sniper=Pixel Sniper|Hyper Sniper|Event Horizon|Eyething Sniper|Gingerbread Sniper|Keyper|Glorious Sniper
Daggers=Aces|Paper Planes|Shurikens|Bat Daggers|Cookies|Crystal Daggers|Keynais
Energy Pistols=Void Pistols|Hydro Pistols|Soul Pistols|New Years Energy Pistols
Exogun=Singularity|Raygun|Repulsor|Exogourd|Midnight Festive Exogun
Flare Gun=Firework Gun|Dynamite Gun|Banana Flare|Vexed Flare Gun|Wrapped Flare Gun
Handgun=Blaster|Hand Gun|Gumball Handgun|Pumpkin Handgun|Gingerbread Handgun
Revolver=Desert Eagle|Sheriff|Peppergun|Boneclaw Revolver|Peppermint Sheriff
Shorty=Not So Shorty|Lovely Shorty|Balloon Shorty|Demon Shorty|Wrapped Shorty
Slingshot=Stick|Goal Post|Harp|Boneshot|Reindeer Slingshot|Lucky Horseshoe
Spray=Lovely Spray|Nail Gun|Bottle Spray|Boneclaw Spray|Pine Spray|Key Spray
Uzi=Water Uzi|Electro Uzi|Money Gun|Demon Uzi|Pine Uzi
Warper=Glitter Warper|Arcane Warper|Hotel Bell|Experiment W4|Frost Warper
Battle Axe=The Shred|Ban Axe|Cerulean Axe|Mimic Axe|Nordic Axe
Chainsaw=Blobsaw|Handsaws|Mega Drill|Buzzsaw|Festive Buzzsaw
Fists=Boxing Gloves|Brass Knuckles|Fists Of Hurt|Pumpkin Claws|Festive Fists
Katana=Saber|Lightning Bolt|Stellar Katana|Evil Trident|New Years Katana|Keytana|Arch Katana|Crystal Katana|Pixel Katana|Glorious Katana
Knife=Chancla|Karambit|Balisong|Machete|Candy Cane|Keylisong|Keyrambit|Caladbolg
Riot Shield=Door|Energy Shield|Masterpiece|Tombstone Shield|Sled
Scythe=Scythe of Death|Anchor|Sakura Scythe|Bat Scythe|Cryo Scythe|Crystal Scythe|Keythe|Bug Net|Arch Scythe
Trowel=Plastic Shovel|Garden Shovel|Paintbrush|Pumpkin Carver|Snow Shovel
Flashbang=Disco Ball|Camera|Lightbulb|Skullbang|Shining Star
Freeze Ray=Temporal Ray|Bubble Ray|Gum Ray|Spider Ray|Wrapped Freeze Ray
Grenade=Whoopee Cushion|Water Balloon|Dynamite|Soul Grenade|Jingle Grenade
Jump Pad=Trampoline|Bounce House|Shady Chicken Sandwich|Spider Web|Jolly Man
Medkit=Sandwich|Laptop|Medkitty|Bucket of Candy|Milk & Cookies|Box of Chocolates|Briefcase
Molotov=Coffee|Torch|Lava Lamp|Vexed Candle|Hot Coals|Arch Molotov
Satchel=Advanced Satchel|Notebook Satchel|Bag O' Money|Potion Satchel|Suspicious Gift
Smoke Grenade=Emoji Cloud|Balance|Hourglass|Eyeball|Snowglobe
Subspace Tripmine=Don't Press|Spring|DIY Tripmine|Trick or Treat|Dev In the Box|Pot O Keys
War Horn=Trumpet|Megaphone|Air Horn|Boneclaw Horn|Mammoth Horn
Warpstone=Cyber Warpstone|Teleport Disc|Electropunk Warpstone|Warpbone|Warpstar
Permafrost=Snowman Permafrost|Ice Permafrost|Glorious Permafrost
]]
	local FALLBACK_WRAPS = "Gold|Diamond|Midas Touch|Community Wrap|Blush Wrapping|Brain|Crystalliz|Damascus|Black Damascus|.exe wrap|Groove|Hollow Wrap|Hesper|Hyperdrive|Gingerbread|Neon Lights|Hologram Arena|Sunset|Pink Lemonade|Lovely Leopard|Dawn|Spectral|Danger|Termination|Moonstone|Starfall|Black Glass|Rift Wrap|Starblaze|Maganite|Watermelon|Reptile|Water|OranGG|A5|Cheese|Nova|Supernova|Glass|Mesh|Meat Wrap|Black Dark Wrap|Cardinal|Pixel Camo|Nauseite|Sensite|Urban Camo|Frosted|Slime Wrap|Carpet Wrap|Cross Wrap|Mainframe Wrap|Honeycomb Wrap|Black Opal Wrap|Patriot|PB&J Wrap|Digital Camo|Street Camo|Ocean Camo|Circuit|Clouds|Woven|Ladybug"

	local skins = {
		picks = {}, weapons = {}, skinsOf = {}, wraps = { "None" }, charms = { "None" }, kinds = {}, found = {},
		stats = { made = 0, skin = 0, charm = 0, errors = 0 }, tracked = setmetatable({}, { __mode = "k" }),
		originals = {}, hooked = false, started = false, searching = false, failed = false, dead = false,
		weapon = nil, file = "SpriteRivals/skins.json", favorites = {}, index = {}, weaponKeys = {}, previewing = false,
	}
	hooks.skins = skins

	local function parseLists(text)
		local result = {}
		for line in string.gmatch(text, "[^\n]+") do
			local weapon, list = string.match(line, "^(.-)=(.*)$")
			if weapon then
				local names = {}
				for name in string.gmatch(list, "[^|]+") do names[#names + 1] = name end
				result[weapon] = names
			end
		end
		return result
	end

	local function readField(object, key)
		local ok, value = pcall(function() return object[key] end)
		if ok then return value end
		return nil
	end

	local function kindOf(name, entry)
		for _, key in ipairs({ "Type", "type", "Category", "Slot", "Kind" }) do
			local value = readField(entry, key)
			if type(value) == "string" then return string.lower(value) end
		end
		if string.find(string.lower(name), "charm", 1, true) then return "charm" end
		return nil
	end

	---Skin names the game lists for a weapon, when its library can tell us.
	local function liveSkins(weapon)
		local library = skins.cosmetic
		if not library or type(readField(library, "GetSkins")) ~= "function" then return {} end

		local ok, result = pcall(library.GetSkins, weapon)
		if not ok or type(result) ~= "table" then
			ok, result = pcall(library.GetSkins, library, weapon)
		end

		local names = {}
		if ok and type(result) == "table" then
			for key, value in pairs(result) do
				local name = key
				if type(name) ~= "string" then name = type(value) == "string" and value or readField(value, "Name") end
				if type(name) == "string" then names[#names + 1] = name end
			end
		end
		table.sort(names)
		return names
	end

	---Everything that can be picked: skins per weapon, wraps and charms.
	function skins.build()
		local library = skins.cosmetic and readField(skins.cosmetic, "Cosmetics")
		local known = type(library) == "table" and library or nil
		local fallback = parseLists(FALLBACK_SKINS)

		local weapons = {}
		local viewModels = skins.items and readField(skins.items, "ViewModels")
		if type(viewModels) == "table" then
			for name in pairs(viewModels) do
				if type(name) == "string" then weapons[name] = true end
			end
		end
		for name in pairs(fallback) do weapons[name] = true end

		table.clear(skins.skinsOf)
		table.clear(skins.kinds)
		skins.weapons = {}
		for weapon in pairs(weapons) do
			skins.weapons[#skins.weapons + 1] = weapon
			local list, seen = { "Default" }, { Default = true }
			local function add(name)
				if seen[name] or (known and known[name] == nil) then return end
				seen[name] = true
				list[#list + 1] = name
			end
			for _, name in ipairs(liveSkins(weapon)) do add(name) end
			for _, name in ipairs(fallback[weapon] or {}) do add(name) end
			skins.skinsOf[weapon] = list
		end
		table.sort(skins.weapons)

		local wraps, charms = { "None" }, { "None" }
		local seenWrap, seenCharm = { None = true }, { None = true }
		if known then
			local names = {}
			for name in pairs(known) do
				if type(name) == "string" then names[#names + 1] = name end
			end
			table.sort(names)
			for _, name in ipairs(names) do
				local entry = known[name]
				local kind = type(entry) == "table" and kindOf(name, entry) or nil
				if kind then skins.kinds[kind] = (skins.kinds[kind] or 0) + 1 end
				if kind == "wrap" and not seenWrap[name] then
					seenWrap[name] = true
					wraps[#wraps + 1] = name
				elseif kind == "charm" and not seenCharm[name] then
					seenCharm[name] = true
					charms[#charms + 1] = name
				end
			end
		end
		for name in string.gmatch(FALLBACK_WRAPS, "[^|]+") do
			if not seenWrap[name] and (not known or known[name] ~= nil) then
				seenWrap[name] = true
				wraps[#wraps + 1] = name
			end
		end
		skins.wraps, skins.charms = wraps, charms

		if not skins.weapon or not skins.skinsOf[skins.weapon] then
			skins.weapon = skins.skinsOf["Assault Rifle"] and "Assault Rifle" or skins.weapons[1]
		end
		skins.reindex()
	end

	local ALIASES = { "DisplayName", "Display", "Title", "PrettyName", "FriendlyName" }

	---A name the way a tile on the game's screen could spell it: lower case letters and digits only.
	local function keyOf(text)
		local plain = string.gsub(string.lower(text), "<[^>]*>", "")
		return (string.gsub(plain, "[^%w]", ""))
	end

	---Looks every skin, wrap and charm up by that spelling, so tiles on the game's own screen can be read.
	function skins.reindex()
		table.clear(skins.index)
		table.clear(skins.weaponKeys)
		local library = skins.cosmetic and readField(skins.cosmetic, "Cosmetics")
		local function note(spelling, name, kind, weapon)
			local key = keyOf(spelling)
			if key == "" then return end
			local entry = skins.index[key]
			if not entry then
				entry = { names = {}, kinds = {}, weapons = {} }
				skins.index[key] = entry
			end
			entry.names[name], entry.kinds[kind] = true, true
			if weapon then entry.weapons[weapon] = true end
		end
		local function add(name, kind, weapon)
			note(name, name, kind, weapon)
			-- A tile may be written with a display name that is not the name the library uses.
			local base = type(library) == "table" and library[name] or nil
			for _, field in ipairs(ALIASES) do
				local alias = type(base) == "table" and readField(base, field) or nil
				if type(alias) == "string" and alias ~= "" then note(alias, name, kind, weapon) end
			end
		end
		for _, weapon in ipairs(skins.weapons) do
			skins.weaponKeys[keyOf(weapon)] = weapon
			for _, name in ipairs(skins.skinsOf[weapon] or {}) do
				if name ~= "Default" then add(name, "Skin", weapon) end
			end
		end
		for _, name in ipairs(skins.wraps) do
			if name ~= "None" then add(name, "Wrap") end
		end
		for _, name in ipairs(skins.charms) do
			if name ~= "None" then add(name, "Charm") end
		end
	end

	-- What the browser shows for each name: a rarity color, words to search, a picture when the game has one.
	local PLAIN_TILE = Color3.fromRGB(26, 26, 32)
	local UNRATED = Color3.fromRGB(96, 120, 148)
	local RARITY_COLORS = {
		common = Color3.fromRGB(150, 160, 172), uncommon = Color3.fromRGB(120, 255, 0), rare = Color3.fromRGB(0, 200, 255),
		epic = Color3.fromRGB(96, 96, 240), legendary = Color3.fromRGB(255, 150, 0), mythical = Color3.fromRGB(255, 34, 34),
		mythic = Color3.fromRGB(255, 34, 34), exclusive = Color3.fromRGB(255, 70, 200),
	}
	-- A rarity the list above does not know still gets one of the game's tile colors, the same one every time.
	local RARITY_SPREAD = {
		Color3.fromRGB(0, 200, 255), Color3.fromRGB(120, 255, 0), Color3.fromRGB(255, 34, 34), Color3.fromRGB(96, 96, 240),
		Color3.fromRGB(255, 150, 0),
	}

	local function entryOf(name)
		local library = skins.cosmetic and readField(skins.cosmetic, "Cosmetics")
		local entry = type(library) == "table" and library[name] or nil
		if type(entry) == "table" then return entry end
		return nil
	end

	local function textField(entry, keys)
		for _, key in ipairs(keys) do
			local value = entry and readField(entry, key)
			if type(value) == "string" and value ~= "" then return value end
		end
		return nil
	end

	function skins.colorOf(entry)
		local rarity = textField(entry, { "Rarity", "rarity", "Tier" })
		if not rarity then return UNRATED end
		local known = RARITY_COLORS[string.lower(rarity)]
		if known then return known end
		local total = 0
		for index = 1, #rarity do total += string.byte(rarity, index) end
		return RARITY_SPREAD[total % #RARITY_SPREAD + 1]
	end

	local function tooltipOf(entry)
		local parts = {}
		for _, key in ipairs({ "Rarity", "Tooltip", "Description", "Desc", "Collection", "Series" }) do
			local value = textField(entry, { key })
			if value then parts[#parts + 1] = value end
		end
		return string.sub(table.concat(parts, " "), 1, 160)
	end

	local function iconOf(entry)
		for _, key in ipairs({ "Icon", "Image", "Thumbnail", "ImageId", "IconId" }) do
			local value = entry and readField(entry, key)
			if type(value) == "number" and value > 100000 then return string.format("rbxassetid://%.0f", value) end
			if type(value) == "string" and (string.sub(value, 1, 13) == "rbxassetid://" or string.sub(value, 1, 11) == "rbxasset://") then
				return value
			end
		end
		return nil
	end

	---The tiles the browser shows for one kind of cosmetic, "Skin", "Wrap" or "Charm".
	function skins.itemsFor(kind, weapon)
		local names = skins.wraps
		if kind == "Skin" then
			if not weapon then return {} end
			names = skins.skinsOf[weapon] or { "Default" }
		elseif kind == "Charm" then
			names = skins.charms
		end
		local none = kind == "Skin" and "Default" or "None"
		local items = {}
		for _, name in ipairs(names) do
			local entry = name ~= none and entryOf(name) or nil
			items[#items + 1] = {
				name = name, plain = name == none, color = name == none and PLAIN_TILE or skins.colorOf(entry),
				tooltip = tooltipOf(entry), icon = iconOf(entry), favorite = skins.favorites[kind .. ":" .. name] == true,
			}
		end
		return items
	end

	---What is picked for a weapon, in the shape the browser wants.
	function skins.picksFor(weapon)
		local pick = weapon and skins.picks[weapon]
		if not pick then return { Skin = "Default", Wrap = "None", Charm = "None" } end
		return { Skin = pick.Skin, Wrap = pick.Wrap, Charm = pick.Charm }
	end

	function skins.setFavorite(kind, name, on)
		skins.favorites[kind .. ":" .. name] = on and true or nil
		skins.save()
	end

	function skins.pickOf(weapon)
		local pick = skins.picks[weapon]
		if not pick then
			pick = { Skin = "Default", Wrap = "None", Charm = "None" }
			skins.picks[weapon] = pick
		end
		return pick
	end

	function skins.save()
		pcall(function()
			if not compat.isfolder("SpriteRivals") then compat.makefolder("SpriteRivals") end
			compat.writefile(skins.file, httpService:JSONEncode({ version = 1, picks = skins.picks, favorites = skins.favorites }))
		end)
	end

	function skins.load()
		pcall(function()
			if not compat.isfile(skins.file) then return end
			local data = httpService:JSONDecode(compat.readfile(skins.file))
			if type(data) ~= "table" or type(data.picks) ~= "table" then return end
			for weapon, saved in pairs(data.picks) do
				if type(weapon) == "string" and type(saved) == "table" then
					local pick = skins.pickOf(weapon)
					if type(saved.Skin) == "string" then pick.Skin = saved.Skin end
					if type(saved.Wrap) == "string" then pick.Wrap = saved.Wrap end
					if type(saved.Charm) == "string" then pick.Charm = saved.Charm end
				end
			end
			if type(data.favorites) == "table" then
				for key, on in pairs(data.favorites) do
					if type(key) == "string" and on == true then skins.favorites[key] = true end
				end
			end
		end)
	end

	local function dataFor(name, kind)
		local library = skins.cosmetic and readField(skins.cosmetic, "Cosmetics")
		local base = type(library) == "table" and library[name] or nil
		if type(base) ~= "table" then return nil end
		local data = table.clone(base)
		data.Name, data.Type = name, kind
		return data
	end

	local function slotKey(name)
		local classes = skins.classes
		local ok, key = pcall(classes.ToEnum, classes, name)
		if ok then return key end
		return nil
	end

	---Only weapons that belong to you are touched, never another player's.
	local function ownItem(item)
		local fighter = rawget(item, "ClientFighter")
		if fighter == nil then fighter = readField(item, "ClientFighter") end
		if fighter == nil then return skins.previewing == true end
		return readField(fighter, "Player") == localPlayer
	end

	local function pickFor(item)
		if not Config.skinsEnabled or type(item) ~= "table" then return nil end
		local weapon = readField(item, "Name")
		local pick = type(weapon) == "string" and skins.picks[weapon] or nil
		if pick and ownItem(item) then return pick end
		return nil
	end

	---Puts the chosen skin and charm into the data a view model is built from.
	local function inject(data, item)
		local pick = pickFor(item)
		if not pick or type(data) ~= "table" then return end

		local dataKey = slotKey("Data")
		if dataKey == nil then return end
		local box = data[dataKey]
		if type(box) ~= "table" then
			box = {}
			data[dataKey] = box
		end

		if pick.Skin ~= "Default" then
			local skinData, skinKey, nameKey = dataFor(pick.Skin, "Skin"), slotKey("Skin"), slotKey("Name")
			if skinData and skinKey ~= nil then
				box[skinKey] = skinData
				if nameKey ~= nil then box[nameKey] = pick.Skin end
				skins.stats.skin += 1
			end
		end
		if pick.Charm ~= "None" then
			local charmData, charmKey = dataFor(pick.Charm, "Charm"), slotKey("Charm")
			if charmData and charmKey ~= nil then
				box[charmKey] = charmData
				skins.stats.charm += 1
			end
		end
	end

	local function wrapOf(model)
		local item = readField(model, "ClientItem")
		local pick = pickFor(item)
		if pick and pick.Wrap ~= "None" then return dataFor(pick.Wrap, "Wrap") end
		return nil
	end

	local function charmOf(model)
		local item = readField(model, "ClientItem")
		local pick = pickFor(item)
		if pick and pick.Charm ~= "None" then return dataFor(pick.Charm, "Charm") end
		return nil
	end

	local function unlock(object)
		pcall(function()
			if type(isreadonly) == "function" and isreadonly(object) and type(setreadonly) == "function" then
				setreadonly(object, false)
			end
		end)
	end

	---Replaces the view model constructor and the wrap and charm getters. restore() puts the originals back.
	function skins.install()
		if skins.hooked then return true end
		local model = skins.viewModel
		if not (model and skins.classes and skins.cosmetic) or type(readField(model, "new")) ~= "function" then
			return false
		end

		unlock(model)
		local originalNew = model.new
		local originalWrap = readField(model, "GetWrap")
		local originalCharm = readField(model, "GetCharm")
		skins.originals = { model = model, new = originalNew, GetWrap = originalWrap, GetCharm = originalCharm }

		model.new = function(data, item, ...)
			if not pcall(inject, data, item) then skins.stats.errors += 1 end
			local made = originalNew(data, item, ...)
			skins.stats.made += 1
			if type(made) == "table" then skins.tracked[made] = true end
			return made
		end
		if type(originalWrap) == "function" then
			model.GetWrap = function(self, ...)
				local ok, result = pcall(wrapOf, self)
				if ok and result then return result end
				return originalWrap(self, ...)
			end
		end
		if type(originalCharm) == "function" then
			model.GetCharm = function(self, ...)
				local ok, result = pcall(charmOf, self)
				if ok and result then return result end
				return originalCharm(self, ...)
			end
		end

		skins.hooked = true
		return true
	end

	function skins.restore()
		local saved = skins.originals
		if not skins.hooked or not saved.model then return end
		pcall(function()
			saved.model.new = saved.new
			if saved.GetWrap then saved.model.GetWrap = saved.GetWrap end
			if saved.GetCharm then saved.model.GetCharm = saved.GetCharm end
		end)
		skins.hooked = false
	end

	---Weapons already in your hands pick up a new wrap straight away, skins and charms show on the next equip.
	function skins.refresh()
		for model in pairs(skins.tracked) do
			local update = readField(model, "_UpdateWrap")
			if type(update) == "function" then pcall(update, model) end
		end
	end

	---Hands the game's own modules to the changer. Used by the search below and by the tests.
	function skins.attach(modules)
		for _, key in ipairs({ "cosmetic", "items", "classes", "viewModel" }) do
			if modules[key] and not skins[key] then
				skins[key] = modules[key]
				skins.found[key] = modules.how or "given"
			end
		end
		return skins.cosmetic ~= nil and skins.classes ~= nil and skins.viewModel ~= nil
	end

	local function findModule(root, name)
		if not root then return nil end
		local ok, found = pcall(root.FindFirstChild, root, name, true)
		if ok then return found end
		return nil
	end

	local function scanMemory()
		if type(getgc) ~= "function" then return end
		local ok, objects = pcall(getgc, true)
		if not ok or type(objects) ~= "table" then return end

		local seen = 0
		for _, object in ipairs(objects) do
			if type(object) == "table" then
				if not skins.cosmetic and rawget(object, "Cosmetics") ~= nil and (rawget(object, "Equip") ~= nil or rawget(object, "GetSkins") ~= nil) then
					skins.cosmetic, skins.found.cosmetic = object, "memory"
				elseif not skins.items and rawget(object, "ViewModels") ~= nil then
					skins.items, skins.found.items = object, "memory"
				elseif not skins.classes and type(rawget(object, "ToEnum")) == "function" then
					skins.classes, skins.found.classes = object, "memory"
				elseif not skins.viewModel and type(rawget(object, "new")) == "function" and rawget(object, "GetWrap") ~= nil then
					skins.viewModel, skins.found.viewModel = object, "memory"
				end
			end
			seen += 1
			if seen % 5000 == 0 then task.wait() end
		end
	end

	---Looks for the game's cosmetic modules, first by requiring them and then by scanning memory.
	function skins.discover()
		local storage = game:GetService("ReplicatedStorage")
		local scripts = localPlayer:FindFirstChild("PlayerScripts")
		local wanted = {
			cosmetic = findModule(storage, "CosmeticLibrary"), items = findModule(storage, "ItemLibrary"),
			classes = findModule(storage, "ReplicatedClass"), viewModel = findModule(scripts, "ClientViewModel"),
		}
		for key, instance in pairs(wanted) do
			if not skins[key] and instance then
				local ok, result = pcall(require, instance)
				if ok and type(result) == "table" then
					skins[key], skins.found[key] = result, "require"
				end
			end
		end
		if not (skins.cosmetic and skins.classes and skins.viewModel) then scanMemory() end
		return skins.cosmetic ~= nil and skins.classes ~= nil and skins.viewModel ~= nil
	end

	---Build the lists, load the saved picks and hook the view models.
	function skins.finish()
		skins.build()
		skins.load()
		skins.failed = not skins.install()
		if skins.reloadUi then skins.reloadUi() end
		return not skins.failed
	end

	function skins.start()
		if skins.started then return end
		skins.started, skins.searching = true, true
		task.spawn(function()
			for _ = 1, 40 do
				if skins.dead then return end
				local searched, found = pcall(skins.discover)
				if searched and found then break end
				task.wait(1.5)
			end
			skins.searching = false
			if skins.dead then return end
			local ok = pcall(skins.finish)
			if not (ok and not skins.failed) then
				skins.failed = true
				if window then pcall(window.Notify, window, "Skin changer: cosmetic code not found", 4) end
			elseif window then
				pcall(window.Notify, window, "Skin changer ready", 2)
			end
		end)
	end

	-- The game's own skin screen ---------------------------------------------------------------------------------------
	-- The strip is found by its search box. Lock marks on its tiles are hidden and a tap on a tile becomes a pick here instead of a
	-- request to the game, which would turn down a skin you do not own. Nothing is sent to the game from here.
	local screen = {
		tiles = {}, hidden = {}, hints = {}, errors = 0, empty = 0, scanAt = 0, pauseUntil = 0, hintAt = -100, dead = false, open = false,
		count = 0, file = "SpriteRivals/skin_screen_report.txt",
	}
	skins.screen = screen

	local KIND_ORDER = { "Skin", "Wrap", "Charm" }
	local NONE_OF = { Skin = "Default", Wrap = "None", Charm = "None" }

	function screen.guiRoot()
		local ok, root = pcall(function() return localPlayer:FindFirstChildOfClass("PlayerGui") end)
		if ok then return root end
		return nil
	end

	local function pathOf(item)
		local ok, path = pcall(item.GetFullName, item)
		if ok and type(path) == "string" then return path end
		return tostring(item.Name)
	end

	---Whether an object and everything above it is switched on.
	local function showing(item)
		local node = item
		while node do
			if node:IsA("ScreenGui") then return node.Enabled end
			if node:IsA("GuiObject") and not node.Visible then return false end
			node = node.Parent
		end
		return true
	end

	---The text of a label or button, when it is short enough to be a name.
	local function nameText(item)
		local class = item.ClassName
		if class ~= "TextLabel" and class ~= "TextButton" then return nil end
		local text = item.Text
		if type(text) == "string" and text ~= "" and #text <= 60 then return text end
		return nil
	end

	---What a piece of text on the screen is: a known cosmetic, or the tile that clears the pick.
	local function entryOfText(text)
		local key = keyOf(text)
		local entry = skins.index[key]
		if entry then return entry, key end
		if key == "default" or key == "none" then
			return { plain = true, kinds = {}, weapons = {}, names = {} }, key
		end
		return nil, key
	end

	---Whether a container holds tiles: two names, or a name and the tile that clears the pick.
	local function holdsTiles(container)
		local names, plain = 0, 0
		for _, item in ipairs(container:GetDescendants()) do
			local text = nameText(item)
			local entry = text and entryOfText(text)
			if entry then
				if entry.plain then plain += 1 else names += 1 end
				if names >= 2 or (names >= 1 and plain >= 1) then return true end
			end
		end
		return false
	end

	---The smallest container around the search box that also holds tiles.
	local function findRoot(box, gui)
		local node = box.Parent
		while node and node ~= gui do
			if holdsTiles(node) then return node end
			node = node.Parent
		end
		if holdsTiles(gui) then return gui end
		return nil
	end

	---The search box of the skin screen, the screen it is on and the container that holds its tiles.
	local function findBox(playerGui)
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and gui.Enabled and not UI.own[gui] then
				for _, item in ipairs(gui:GetDescendants()) do
					if item.ClassName == "TextBox" and string.find(string.lower(tostring(item.PlaceholderText)), "search by", 1, true) and showing(item) then
						local root = findRoot(item, gui)
						if root then return item, gui, root end
					end
				end
			end
		end
		return nil, nil, nil
	end

	local function markName(name)
		local lower = string.lower(name)
		if string.find(lower, "lock", 1, true) and not string.find(lower, "unlock", 1, true) then return "lock" end
		if string.find(lower, "equipped", 1, true) then return "check" end
		for _, word in ipairs({ "check", "tick" }) do
			if string.sub(lower, 1, #word) == word or string.find(lower, "[_%s%-]" .. word) then return "check" end
		end
		return nil
	end

	---Reads the strip: one entry per tile, found through the name written on it, and the lock and check marks of the screen.
	local function readTiles(root, box)
		local labels, marks, keysAt, countAt = {}, {}, {}, {}
		for _, item in ipairs(root:GetDescendants()) do
			local text = nameText(item)
			if text then
				local entry, key = entryOfText(text)
				if entry and showing(item) then labels[#labels + 1] = { item = item, entry = entry, text = text, key = key } end
			end
			local what = markName(item.Name)
			if what then marks[#marks + 1] = { item = item, what = what } end
		end

		-- How many different names sit under each container, so a tile is the largest container holding just one.
		for _, label in ipairs(labels) do
			local node = label.item.Parent
			while node and node ~= root do
				local keys = keysAt[node]
				if not keys then
					keys = {}
					keysAt[node], countAt[node] = keys, 0
				end
				if not keys[label.key] then
					keys[label.key] = true
					countAt[node] += 1
				end
				node = node.Parent
			end
		end

		local list, byTile = {}, {}
		for _, label in ipairs(labels) do
			local tile, node = nil, label.item.Parent
			while node and node ~= root and countAt[node] == 1 and not box:IsDescendantOf(node) do
				tile = node
				node = node.Parent
			end
			if tile and tile:IsA("GuiObject") and not byTile[tile] then
				local read = { tile = tile, entry = label.entry, text = label.text }
				byTile[tile] = read
				list[#list + 1] = read
			end
		end
		return { tiles = list, byTile = byTile, marks = marks, keysAt = keysAt }
	end

	---The kind of cosmetic most of the tiles are.
	local function majorityKind(list)
		local counts = { Skin = 0, Wrap = 0, Charm = 0 }
		for _, tile in ipairs(list) do
			local only, many = nil, 0
			for kind in pairs(tile.entry.kinds) do only, many = kind, many + 1 end
			if many == 1 then counts[only] += 1 end
		end
		local best, top = "Skin", 0
		for _, kind in ipairs(KIND_ORDER) do
			if counts[kind] > top then best, top = kind, counts[kind] end
		end
		return best
	end

	local function kindFor(entry, major)
		if entry.plain or entry.kinds[major] then return major end
		for _, kind in ipairs(KIND_ORDER) do
			if entry.kinds[kind] then return kind end
		end
		return major
	end

	local function nameFor(entry)
		local best
		for name in pairs(entry.names) do
			if best == nil or name < best then best = name end
		end
		return best
	end

	---Weapon names written anywhere on the screen.
	local function weaponHints(gui)
		local hints, seen = {}, {}
		for _, item in ipairs(gui:GetDescendants()) do
			local text = nameText(item)
			if text then
				local weapon = skins.weaponKeys[keyOf(text)]
				if weapon and not seen[weapon] and showing(item) then
					seen[weapon] = true
					hints[#hints + 1] = weapon
				end
			end
		end
		return hints
	end

	---The weapon the strip is for. Skins belong to a weapon, so the weapons that own every skin shown are the candidates, and a
	---weapon named on the screen settles a tie. Nil when nothing says.
	local function weaponFor(list, hints, current)
		local pool
		for _, tile in ipairs(list) do
			if tile.kind == "Skin" and not tile.plain then
				if not pool then
					pool = table.clone(tile.entry.weapons)
				else
					for weapon in pairs(pool) do
						if not tile.entry.weapons[weapon] then pool[weapon] = nil end
					end
				end
			end
		end

		local only, many = nil, 0
		for weapon in pairs(pool or {}) do only, many = weapon, many + 1 end
		if many == 1 then return only end

		local named, namedCount = nil, 0
		for _, weapon in ipairs(hints) do
			if not pool or pool[weapon] then named, namedCount = weapon, namedCount + 1 end
		end
		if namedCount == 1 then return named end

		if many > 1 then
			if current and pool[current] then return current end
			local first
			for weapon in pairs(pool) do
				if not first or weapon < first then first = weapon end
			end
			return first
		end
		return nil
	end

	screen.majorityKind, screen.weaponFor = majorityKind, weaponFor

	---Puts an invisible button over a tile. The game's own button never sees the tap, so nothing is sent to the game, and the tick
	---that shows what is picked here sits on it.
	local function makeCatcher(entry)
		local tile = entry.tile
		if entry.catcher then pcall(entry.catcher.Destroy, entry.catcher) end
		local width = 0
		pcall(function() width = tile.AbsoluteSize.X end)
		local size = width > 0 and math.clamp(math.floor(width * 0.34), 22, 44) or 36

		-- A name the lock and check search above would never take for one of the game's marks.
		local name = randomName(8)
		while markName(name) do name = randomName(8) end

		local catcher = UI.create("TextButton", {
			Name = name,
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 200,
			Parent = tile,
		})
		local check = UI.tick(catcher, size, 201)
		check.Position = UDim2.new(0, 3, 1, -math.floor(size * 1.85))
		check.Visible = false
		catcher.MouseButton1Click:Connect(function() pcall(screen.choose, entry) end)
		entry.catcher, entry.check = catcher, check
	end

	---Ticks the tile that is picked for the weapon in view. A skin picked here is the one shown, so the game's own marks stay hidden.
	function screen.marks()
		if not screen.open then return end
		local picked = skins.picks[screen.weapon or skins.weapon]
		for _, entry in pairs(screen.tiles) do
			local current = picked and picked[entry.kind] or nil
			if entry.check then entry.check.Visible = not entry.plain and current ~= nil and current == entry.name end
		end
	end

	---A tap on a tile of the game's screen: picks it, or clears the pick when it was already picked.
	function screen.choose(entry)
		if screen.dead or not Config.skinsScreen or not Config.skinsEnabled then return end
		local kind = entry.kind
		local weapon = screen.weapon or skins.weapon
		if not (kind and weapon and skins.skinsOf[weapon]) then return end

		local none = NONE_OF[kind]
		local value = entry.plain and none or entry.name
		if kind == "Skin" and value ~= none and not table.find(skins.skinsOf[weapon], value) then return end

		skins.pickWeapon(weapon)
		if value ~= none and skins.pickOf(weapon)[kind] == value then value = none end
		skins.setPick(kind, value)
		if window then pcall(window.Notify, window, value == none and (kind .. " cleared") or (kind .. ": " .. value), 2) end
	end

	---Matches the screen to the tiles read from it: catchers on new tiles, old ones removed, locks hidden, ticks set.
	function screen.apply(read, gui)
		local list = read.tiles
		local major = majorityKind(list)
		for _, tile in ipairs(list) do
			tile.kind = kindFor(tile.entry, major)
			tile.plain = tile.entry.plain == true
			tile.name = tile.plain and NONE_OF[tile.kind] or nameFor(tile.entry)
		end

		local names = {}
		for index, tile in ipairs(list) do names[index] = tile.name end
		local signature, now = table.concat(names, "|"), os.clock()
		if signature ~= screen.signature or now - screen.hintAt > 3 then
			screen.signature, screen.hintAt = signature, now
			screen.hints = weaponHints(gui)
		end
		screen.kind = major
		screen.weapon = weaponFor(list, screen.hints, skins.weapon) or screen.weapon or skins.weapon

		for tile, entry in pairs(screen.tiles) do
			if not read.byTile[tile] or tile.Parent == nil then
				if entry.catcher then pcall(entry.catcher.Destroy, entry.catcher) end
				screen.tiles[tile] = nil
			end
		end
		for _, tile in ipairs(list) do
			local entry = screen.tiles[tile.tile]
			if not entry then
				entry = { tile = tile.tile }
				screen.tiles[tile.tile] = entry
				makeCatcher(entry)
			elseif entry.catcher == nil or entry.catcher.Parent ~= tile.tile then
				makeCatcher(entry)
			end
			entry.kind, entry.name, entry.plain, entry.weapons = tile.kind, tile.name, tile.plain, tile.entry.weapons
		end

		-- Lock marks always go. The game's own equipped marks go while a pick made here is shown instead.
		local picks = skins.picks[screen.weapon]
		local current = picks and picks[major] or nil
		local picked = current ~= nil and current ~= NONE_OF[major]
		local wanted = {}
		for _, mark in ipairs(read.marks) do
			local item = mark.item
			if (mark.what == "lock" or picked) and not read.byTile[item] and not read.keysAt[item] and item:IsA("GuiObject") then
				local node, inside = item.Parent, false
				while node and node ~= screen.root do
					if read.byTile[node] then
						inside = true
						break
					end
					node = node.Parent
				end
				if inside then
					wanted[item] = true
					if not screen.hidden[item] and item.Visible then
						local ok = pcall(function() item.Visible = false end)
						if ok then screen.hidden[item] = true end
					end
				end
			end
		end
		for item in pairs(screen.hidden) do
			if not wanted[item] then
				pcall(function() item.Visible = true end)
				screen.hidden[item] = nil
			end
		end

		screen.open, screen.count = #list > 0, #list
		skins.previewing = screen.open
		screen.marks()
	end

	---Puts everything back the way the game made it.
	function screen.release()
		for tile, entry in pairs(screen.tiles) do
			if entry.catcher then pcall(entry.catcher.Destroy, entry.catcher) end
			screen.tiles[tile] = nil
		end
		for item in pairs(screen.hidden) do
			pcall(function() item.Visible = true end)
			screen.hidden[item] = nil
		end
		screen.box, screen.gui, screen.root, screen.signature, screen.weapon, screen.kind = nil, nil, nil, nil, nil, nil
		screen.open, screen.count, screen.empty = false, 0, 0
		skins.previewing = false
	end

	---One look at the screen: find the strip when it is open, keep its tiles in step while it stays open.
	function screen.scan()
		local playerGui = screen.guiRoot()
		if not playerGui then return end

		if screen.box and not (screen.box.Parent ~= nil and screen.root.Parent ~= nil and showing(screen.box)) then screen.release() end
		if not screen.box then
			local box, gui, root = findBox(playerGui)
			if not box then return end
			screen.box, screen.gui, screen.root = box, gui, root
		end

		local read = readTiles(screen.root, screen.box)
		if #read.tiles == 0 then
			screen.empty += 1
			if screen.empty >= 3 then
				screen.release()
				return
			end
		else
			screen.empty = 0
		end
		screen.apply(read, screen.gui)
	end

	function screen.step(now)
		local active = Config.skinsEnabled and Config.skinsScreen and skins.hooked and not skins.dead and not screen.dead
		if not active then
			if screen.box then screen.release() end
			screen.scanAt = now + 1
			return
		end
		if now < screen.pauseUntil then return end

		local ok, problem = pcall(screen.scan)
		if ok then
			screen.errors = 0
			screen.scanAt = now + (screen.box and 0.5 or 2)
			return
		end

		screen.errors += 1
		screen.lastError = tostring(problem)
		screen.scanAt = now + 2
		screen.pauseUntil = now + 4 * screen.errors
		pcall(screen.release)
		if screen.errors >= 5 then
			screen.dead = true
			if window then pcall(window.Notify, window, "Skin screen unlock stopped", 3) end
		end
	end

	---Everything the screen code can see, as text, so a screen that does nothing can be looked at from the outside.
	function screen.report()
		local lines = {}
		local function add(text) lines[#lines + 1] = text end

		add("sprite skin screen report")
		add(string.format("place %s | skin changer %s | game screen %s | hooked %s | failed %s", tostring(game.PlaceId),
			Config.skinsEnabled and "on" or "off", Config.skinsScreen and "on" or "off", tostring(skins.hooked), tostring(skins.failed)))
		local indexed = 0
		for _ in pairs(skins.index) do indexed += 1 end
		add(string.format("lists: %d weapons, %d wraps, %d charms, %d names to match tiles with", #skins.weapons,
			math.max(#skins.wraps - 1, 0), math.max(#skins.charms - 1, 0), indexed))
		local hiddenCount = 0
		for _ in pairs(screen.hidden) do hiddenCount += 1 end
		add(string.format("screen %s | tiles %d | kind %s | weapon %s | hidden marks %d | errors %d", screen.open and "found" or "not found",
			screen.count, tostring(screen.kind), tostring(screen.weapon), hiddenCount, screen.errors))
		if screen.lastError then add("last error: " .. screen.lastError) end
		if screen.root then add("strip: " .. pathOf(screen.root)) end

		local boxes = {}
		local root = screen.guiRoot()
		if root then
			pcall(function()
				for _, gui in ipairs(root:GetChildren()) do
					if gui:IsA("ScreenGui") and not UI.own[gui] then
						for _, item in ipairs(gui:GetDescendants()) do
							if item.ClassName == "TextBox" and #boxes < 8 then
								boxes[#boxes + 1] = string.format("  %s | \"%s\" | %s", pathOf(item), tostring(item.PlaceholderText),
									showing(item) and "shown" or "hidden")
							end
						end
					end
				end
			end)
		end
		add("text boxes on screen: " .. (#boxes > 0 and "" or "none"))
		for _, line in ipairs(boxes) do add(line) end

		local first
		for _, entry in pairs(screen.tiles) do
			if not first or tostring(entry.name) < tostring(first.name) then first = entry end
		end
		if first then
			add(string.format("one tile: %s (%s, %s)", pathOf(first.tile), tostring(first.kind), tostring(first.name)))
			local listed = 0
			for _, item in ipairs(first.tile:GetDescendants()) do
				if listed >= 30 then break end
				listed += 1
				add(string.format("  %s (%s)", tostring(item.Name), tostring(item.ClassName)))
			end
		end

		if screen.root then
			local others, seen = {}, {}
			pcall(function()
				for _, item in ipairs(screen.root:GetDescendants()) do
					local text = nameText(item)
					if text and #others < 15 and not seen[text] and not entryOfText(text) then
						seen[text] = true
						others[#others + 1] = text
					end
				end
			end)
			add("other texts in the strip: " .. (#others > 0 and table.concat(others, " | ") or "none"))
		end
		return table.concat(lines, "\n")
	end

	---Writes the report to a file and puts it on the clipboard when the executor can.
	function screen.copyReport()
		local text = screen.report()
		local copied = type(setclipboard) == "function" and pcall(setclipboard, text)
		pcall(function()
			if not compat.isfolder("SpriteRivals") then compat.makefolder("SpriteRivals") end
			compat.writefile(screen.file, text)
		end)
		return copied == true, text
	end

	local function screenLine()
		if not Config.skinsScreen then return nil end
		if screen.dead then return "Skin screen: stopped after errors." end
		if screen.open then return string.format("Skin screen: %d tiles unlocked.", screen.count) end
		return "Skin screen: open it, tap a tile."
	end

	function skins.status()
		if not Config.skinsEnabled then return "Off. Turn it on, then pick below." end
		if skins.searching then return "Looking for the game's cosmetic code..." end
		if skins.failed then return "Cosmetic code not found. This game version may have changed." end
		if not skins.hooked then return "Not started." end
		local text = string.format(
			"Ready: %d weapons, %d wraps, %d charms.\nApplied so far: %d skins, %d charms.",
			#skins.weapons, #skins.wraps - 1, #skins.charms - 1, skins.stats.skin, skins.stats.charm
		)
		local line = screenLine()
		if line then text = text .. "\n" .. line end
		return text
	end

	table.insert(hooks.clean, function()
		skins.dead, screen.dead = true, true
		screen.release()
		skins.restore()
	end)

	table.insert(hooks.refresh, function()
		if Config.skinsEnabled then skins.start() end
	end)

	-- Menu -------------------------------------------------------------------------------------------
	local skinTab = window:Tab("Skins")
	skinTab:Section("Skin changer")
	toggle(skinTab, "Enabled", "skinsEnabled", function(state)
		if state then skins.start() else skins.refresh() end
	end)
	local statusLabel = skinTab:Label("Off. Turn it on, then pick below.", 3)
	skinTab:Button("Open skin browser", function() skins.openBrowser() end)

	local weaponOptions, skinOptions, wrapOptions, charmOptions = { "Loading" }, { "Default" }, { "None" }, { "None" }

	local function fill(options, list, empty)
		table.clear(options)
		for _, value in ipairs(list) do options[#options + 1] = value end
		if #options == 0 then options[1] = empty end
	end

	skins.ui = { weapons = weaponOptions, skins = skinOptions, wraps = wrapOptions, charms = charmOptions }

	skinTab:Section("Pick for a weapon")
	local weaponBox, skinBox, wrapBox, charmBox

	local function showPick()
		local pick = skins.weapon and skins.picks[skins.weapon] or { Skin = "Default", Wrap = "None", Charm = "None" }
		fill(skinOptions, skins.weapon and skins.skinsOf[skins.weapon] or {}, "Default")
		skinBox:set(pick.Skin)
		wrapBox:set(pick.Wrap)
		charmBox:set(pick.Charm)
	end

	function skins.reloadUi()
		fill(weaponOptions, skins.weapons, "Loading")
		fill(wrapOptions, skins.wraps, "None")
		fill(charmOptions, skins.charms, "None")
		weaponBox:set(skins.weapon or weaponOptions[1])
		showPick()
		skins.sync(true)
	end

	---Hands what is picked to the strip along the bottom and to the ticks on the game's own screen.
	function skins.sync(full)
		local browser = window.browser
		if browser and not browser.destroyed then
			browser.setPicks(skins.picksFor(skins.weapon))
			if full then
				browser.setWeapons(skins.weapons, skins.weapon)
				browser.setItems("Wrap", skins.itemsFor("Wrap"))
				browser.setItems("Charm", skins.itemsFor("Charm"))
			else
				browser.setWeapon(skins.weapon)
			end
			browser.setItems("Skin", skins.itemsFor("Skin", skins.weapon))
		end
		screen.marks()
	end

	---One pick for the weapon in view. The menu, the strip and the game's own screen all end up here.
	function skins.setPick(kind, value)
		if not skins.weapon then return end
		skins.pickOf(skins.weapon)[kind] = value
		skins.save()
		skins.refresh()
		showPick()
		skins.sync()
	end

	function skins.pickWeapon(name)
		if not skins.skinsOf[name] then return end
		skins.weapon = name
		weaponBox:set(name)
		showPick()
		skins.sync()
	end

	local function choose(kind, value)
		skins.setPick(kind, value)
	end

	---Opens the strip along the bottom of the screen, starting the changer first when it is off.
	function skins.openBrowser()
		if not Config.skinsEnabled then
			Config.skinsEnabled = true
			widgets.skinsEnabled:set(true)
		end
		skins.start()
		local browser = window.browser
		if not browser or browser.destroyed then
			browser = window:SkinBrowser({
				onPick = function(kind, name) skins.setPick(kind, name) end,
				onFavorite = function(kind, name, on) skins.setFavorite(kind, name, on) end,
				onWeapon = function(name) skins.pickWeapon(name) end,
			})
			skins.sync(true)
		end
		browser.open()
	end

	weaponBox = skinTab:Dropdown("Weapon", weaponOptions, weaponOptions[1], function(value)
		skins.pickWeapon(value)
	end)
	skinBox = skinTab:Dropdown("Skin", skinOptions, skinOptions[1], function(value) choose("Skin", value) end)
	wrapBox = skinTab:Dropdown("Wrap", wrapOptions, wrapOptions[1], function(value) choose("Wrap", value) end)
	charmBox = skinTab:Dropdown("Charm", charmOptions, charmOptions[1], function(value) choose("Charm", value) end)

	function skins.find(text)
		local wanted = string.lower((string.gsub(text or "", "^%s+", "")))
		if wanted == "" or not skins.weapon then return false end
		for _, set in ipairs({ { "Skin", skinOptions, skinBox }, { "Wrap", wrapOptions, wrapBox }, { "Charm", charmOptions, charmBox } }) do
			for _, name in ipairs(set[2]) do
				if string.find(string.lower(name), wanted, 1, true) then
					set[3]:set(name)
					choose(set[1], name)
					window:Notify(set[1] .. ": " .. name, 2)
					return true
				end
			end
		end
		window:Notify("Nothing called " .. text, 2)
		return false
	end
	skinTab:Input("Find by name", "", skins.find, "part of a name")

	skinTab:Section("Quick picks")
	local function randomOf(list)
		if #list <= 1 then return list[1] end
		return list[math.random(2, #list)]
	end
	local function shuffle(weapon)
		local pick = skins.pickOf(weapon)
		pick.Skin = randomOf(skins.skinsOf[weapon] or { "Default" })
		pick.Wrap, pick.Charm = randomOf(skins.wraps), randomOf(skins.charms)
	end

	function skins.randomWeapon()
		if not skins.weapon then return end
		shuffle(skins.weapon)
		skins.save()
		showPick()
		skins.refresh()
	end

	function skins.randomAll()
		for _, weapon in ipairs(skins.weapons) do shuffle(weapon) end
		skins.save()
		showPick()
		skins.refresh()
	end

	function skins.copyToAll()
		if not skins.weapon then return end
		local source = skins.pickOf(skins.weapon)
		for _, weapon in ipairs(skins.weapons) do
			local pick = skins.pickOf(weapon)
			pick.Wrap, pick.Charm = source.Wrap, source.Charm
		end
		skins.save()
		skins.refresh()
		window:Notify("Wrap and charm copied", 2)
	end

	function skins.clearWeapon()
		if not skins.weapon then return end
		skins.picks[skins.weapon] = nil
		skins.save()
		showPick()
		skins.refresh()
	end

	function skins.clearAll()
		table.clear(skins.picks)
		skins.save()
		showPick()
		skins.refresh()
	end

	skinTab:Button("Random look for this weapon", skins.randomWeapon)
	skinTab:Button("Random look for every weapon", skins.randomAll)
	skinTab:Button("Copy wrap and charm to all weapons", skins.copyToAll)
	skinTab:Button("Clear this weapon", skins.clearWeapon)
	skinTab:Button("Clear every weapon", skins.clearAll)
	skinTab:Label("Only you see these. A new skin or charm shows the next time you equip the weapon, wraps change at once.", 3)

	skinTab:Section("Game skin screen")
	toggle(skinTab, "Unlock the game's screen", "skinsScreen", function(state)
		if not state then screen.release() end
	end)
	skinTab:Button("Copy skin screen report", function()
		local copied = screen.copyReport()
		window:Notify(copied and "Skin screen report copied" or "Skin screen report saved to " .. screen.file, 3)
	end)
	skinTab:Label("Open the game's skin screen and tap a tile. Locked ones apply here only and nothing is sent to the game.", 3)

	local statusAt = 0
	table.insert(hooks.render, { "skins status", function(dt, now)
		if now < statusAt then return end
		statusAt = now + 0.5
		local text = skins.status()
		if statusLabel.Text ~= text then statusLabel.Text = text end
	end })

	table.insert(hooks.render, { "skins screen", function(dt, now)
		if now < screen.scanAt then return end
		screen.step(now)
	end })
end)()

local configTab = window:Tab("Config")
configTab:Section("Profiles")
local nameInput = configTab:Input("Config name", "default")
local savedLabel = configTab:Label("Saved: none")
savedLabel.TextTruncate = Enum.TextTruncate.AtEnd
hooks.autoloadLabel = configTab:Label("Autoload: none")
hooks.autoloadLabel.TextTruncate = Enum.TextTruncate.AtEnd

local function refreshSavedList()
	local names = {}
	pcall(function()
		if not compat.isfolder(CONFIG_FOLDER) then return end
		for _, path in ipairs(compat.listfiles(CONFIG_FOLDER)) do
			local name = string.match(path, "([^/\\]+)%.json$")
			if name and string.sub(name, 1, 1) ~= "_" then table.insert(names, name) end
		end
	end)
	table.sort(names)
	savedLabel.Text = "Saved: " .. (#names > 0 and table.concat(names, ", ") or "none")

	local autoload = "none"
	pcall(function()
		if compat.isfile(AUTOLOAD_FILE) then autoload = cleanConfigName(compat.readfile(AUTOLOAD_FILE)) end
	end)
	hooks.autoloadLabel.Text = "Autoload: " .. autoload
end

configTab:Button("Save config", function()
	local name = cleanConfigName(nameInput.get())
	local ok = saveConfig(name)
	window:Notify(ok and ("Saved config: " .. name) or "Save failed")
	refreshSavedList()
end)

configTab:Button("Load config", function()
	local name = cleanConfigName(nameInput.get())
	window:Notify(loadConfig(name) and ("Loaded config: " .. name) or ("No config named " .. name))
end)

configTab:Button("Set as autoload", function()
	local name = cleanConfigName(nameInput.get())
	local ok = pcall(function()
		if not compat.isfolder(CONFIG_FOLDER) then compat.makefolder(CONFIG_FOLDER) end
		compat.writefile(AUTOLOAD_FILE, name)
	end)
	window:Notify(ok and ("Autoload: " .. name) or "Could not set autoload")
	refreshSavedList()
end)

configTab:Button("Clear autoload", function()
	pcall(function()
		if compat.isfile(AUTOLOAD_FILE) then compat.delfile(AUTOLOAD_FILE) end
	end)
	window:Notify("Autoload cleared")
	refreshSavedList()
end)

configTab:Button("Delete config", function()
	local name = cleanConfigName(nameInput.get())
	window:Notify(deleteConfig(name) and ("Deleted config: " .. name) or ("No config named " .. name))
	refreshSavedList()
end)

configTab:Button("Reset to defaults", function()
	resetConfig()
	window:Notify("Settings reset")
end)

configTab:Section("Share")
local importInput = configTab:Input("Import JSON", "", nil, "paste")
configTab:Button("Copy config to clipboard", function()
	local ok = pcall(function() setclipboard(encodeConfig()) end)
	window:Notify(ok and "Config copied" or "Clipboard unavailable")
end)
configTab:Button("Import pasted config", function()
	window:Notify(importConfig(importInput.get()) and "Config imported" or "Invalid config text")
end)

configTab:Section("Safety")
toggle(configTab, "Backup before loading", "cfgBackup")
toggle(configTab, "Save session on unload", "cfgSaveOnExit")
slider(configTab, "Autosave (min, 0 = off)", "cfgAutoMinutes", 0, 30)
configTab:Button("Restore backup", function()
	window:Notify(hooks.restoreBackup() and "Backup restored" or "No backup yet")
end)
configTab:Button("Load last session", function()
	window:Notify(hooks.loadLast() and "Last session loaded" or "No saved session yet")
end)

configTab:Section("Manage")
do
	configTab:Button("Duplicate config", function()
		local name = cleanConfigName(nameInput.get())
		local copy = name .. "_copy"
		window:Notify(hooks.copyConfig(name, copy) and ("Copied to " .. copy) or ("No config named " .. name))
		refreshSavedList()
	end)

	local renameInput = configTab:Input("New name", "")
	configTab:Button("Rename config", function()
		local name, new = cleanConfigName(nameInput.get()), cleanConfigName(renameInput.get())
		window:Notify(hooks.renameConfig(name, new) and ("Renamed to " .. new) or "Rename failed")
		refreshSavedList()
	end)

	local linkInput = configTab:Input("Config link", "", nil, "https://")
	configTab:Button("Import from link", function()
		window:Notify(hooks.importLink(linkInput.get()) and "Config imported" or "Could not load that link")
	end)

	local resetTarget = "Move"
	configTab:Dropdown("Reset tab", { "Move", "Misc", "ESP", "Aim", "Rage", "AI", "Visuals", "Interface" }, resetTarget, function(value)
		resetTarget = value
	end)
	configTab:Button("Reset selected tab", function()
		window:Notify(hooks.resetTab(resetTarget) and (resetTarget .. " settings reset") or "Nothing to reset")
	end)
end

local interfaceTab = window:Tab("Interface")
interfaceTab:Section("Menu")
bind(interfaceTab, "Menu key", "menu")
bind(interfaceTab, "Panic key (unload)", "panic")
dropdown(interfaceTab, "Theme", "theme", THEME_NAMES, hooks.pickTheme)
slider(interfaceTab, "Menu scale (%)", "menuScale", 60, 140, function(value)
	window:setScale(value, Config.menuFit)
end)
toggle(interfaceTab, "Bubble animations", "menuAnimations", function(state)
	window:setAnimated(state)
end)
toggle(interfaceTab, "Frosted blur", "menuBlur", function(state)
	window:setBlur(state)
end)
interfaceTab:Label("Click a bind, then press a key. Esc cancels, Backspace clears", 2)
interfaceTab:Section("Touch")
dropdown(interfaceTab, "Mobile mode", "mobileMode", { "Auto", "On", "Off" }, function(value)
	compat.mode(value)
end)
toggle(interfaceTab, "Menu and quick buttons", "touchButtons")
slider(interfaceTab, "Button size (%)", "touchScale", 70, 160, function(value)
	if window.dock then window.dock.scale.Scale = value / 100 end
end)
toggle(interfaceTab, "Fit menu to screen", "menuFit", function()
	window:setScale(Config.menuScale, Config.menuFit)
end)
hooks.device = {}
for index, line in ipairs(compat.report()) do
	hooks.device[index] = interfaceTab:Label(line)
end
interfaceTab:Section("Glass")
slider(interfaceTab, "Glass clearness (%)", "menuOpacity", 0, 100, function(value) window:setOpacity(value) end)
slider(interfaceTab, "Blur strength", "menuBlurSize", 0, 40, function(value) window:setBlurSize(value) end)
slider(interfaceTab, "Bubble amount (%)", "menuBubbles", 0, 100, function(value) window:setBubbles(value / 100) end)
slider(interfaceTab, "Bubble speed (%)", "menuBubbleSpeed", 25, 300, function(value) window.bubbleSpeed = value / 100 end)
toggle(interfaceTab, "Rim light spin", "menuRimSpin", function(state) window.rimSpin = state end)
toggle(interfaceTab, "Bubble fizz", "menuFizz", function(state) window.fizzOn = state end)
toggle(interfaceTab, "Page fade", "menuFade", function(state) window.tabFade = state end)
interfaceTab:Section("Accent")
hooks.input(interfaceTab, "Accent hex", "customAccent", "#rrggbb", function(value)
	if value ~= "" and not hooks.parseHex(value) then
		window:Notify("Use a hex color like #ff8800", 2)
	elseif not Config.rainbowAccent then
		hooks.syncAccent()
	end
end)
toggle(interfaceTab, "Rainbow accent", "rainbowAccent")
interfaceTab:Section("Notifications")
toggle(interfaceTab, "Notifications", "notifyEnabled", hooks.applyInterface)
slider(interfaceTab, "Notification time (s)", "notifySeconds", 1, 10, hooks.applyInterface)
dropdown(interfaceTab, "Notify side", "notifySide", { "Right", "Left" }, hooks.applyInterface)
interfaceTab:Section("Intro")
toggle(interfaceTab, "Play intro on load", "introEnabled")
slider(interfaceTab, "Intro volume (%)", "introVolume", 0, 100)
interfaceTab:Button("Play intro now", function() hooks.intro.replay() end)
interfaceTab:Section("Window")
toggle(interfaceTab, "Lock menu position", "menuLock", function(state) window.locked = state end)
toggle(interfaceTab, "Start hidden", "menuStartHidden")
interfaceTab:Button("Reset menu position", function() window:resetPosition() end)
interfaceTab:Section("Script")
interfaceTab:Button("Re-enable stopped modules", function()
	resetModules()
	window:Notify("Modules re-enabled")
end)
interfaceTab:Button("Unload script", function() detach() end)

for _, player in ipairs(playersService:GetPlayers()) do
	if player ~= localPlayer then createEsp(player) end
end

table.insert(connections, playersService.PlayerAdded:Connect(createEsp))
table.insert(connections, playersService.PlayerRemoving:Connect(removeEsp))

-- Run after the camera so ESP and aim read the final camera frame.
runService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 1, onRender)

table.insert(connections, runService.Stepped:Connect(function(_, dt)
	runModule("movement", updateMovement, dt, os.clock())

	for _, entry in ipairs(hooks.step) do runModule(entry[1], entry[2], dt, os.clock()) end

	if not (Config.noclip or (Config.flyEnabled and Config.flyNoclip)) then return end
	local character = localPlayer.Character
	if not character then return end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
		end
	end
end))

table.insert(connections, localPlayer.Idled:Connect(function()
	if not Config.antiAfk then return end
	pcall(function()
		virtualUser:CaptureController()
		virtualUser:ClickButton2(Vector2.zero)
	end)
end))

table.insert(connections, userInputService.JumpRequest:Connect(queueJump))

-- Touch controls: the round menu button and quick buttons for what a keyboard would do.
;(function()
	local touch = hooks.touch

	local function say(text)
		window:Notify(text, 1.2)
	end

	local function latch(flag, label)
		return function()
			touch[flag] = not touch[flag]
			say(label .. (touch[flag] and ": ON" or ": OFF"))
		end
	end

	local function hold(flag)
		return function() touch[flag] = true end, function() touch[flag] = false end
	end

	local function item(text, visible, active, press, release)
		return { text = text, visible = visible, active = active, press = press, release = release }
	end

	local function always() return true end

	window:Dock({
		item("AIM", always, function() return Config.aimActive end, function()
			if not Config.aimEnabled then
				say("Turn on the aimbot first")
				return
			end
			Config.aimActive = Config.aimHold and true or not Config.aimActive
			if not Config.aimHold then say("Aim lock: " .. (Config.aimActive and "ON" or "OFF")) end
		end, function()
			if Config.aimHold then Config.aimActive = false end
		end),
		item("FLY", always, function() return Config.flyEnabled end, function()
			Config.flyEnabled = not Config.flyEnabled
			flyToggle:set(Config.flyEnabled)
			say("Fly: " .. (Config.flyEnabled and "ON" or "OFF"))
		end),
		item("UP", function() return Config.flyEnabled end, function() return touch.up end, hold("up")),
		item("DOWN", function() return Config.flyEnabled end, function() return touch.down end, hold("down")),
		item("SLIDE", function() return Config.slideEnabled end, function() return touch.slide end, hold("slide")),
		item("RUN", function() return Config.sprintEnabled end, function() return touch.sprint end, latch("sprint", "Run")),
		item("ZOOM", function() return Config.zoomEnabled end, function() return touch.zoom end, latch("zoom", "Zoom")),
		item("FIRE", function() return Config.rapidFire end, function() return touch.rapid end, hold("rapid")),
		item("JUMP", function() return Config.bhop or Config.glideEnabled end, function() return touch.jump end, hold("jump")),
		item("TP", function() return Config.clickTp end, function() return false end, function() hooks.clickTeleport() end),
	})

	table.insert(hooks.render, { "touch buttons", function()
		window.dock:refresh(compat.on and Config.touchButtons and not hooks.introActive)
	end })

	-- A different screen size, such as turning the phone, refits the menu.
	local lastView
	table.insert(hooks.render, { "menu fit", function()
		local view = perFrame.viewport
		if view ~= lastView then
			lastView = view
			window:fit()
		end
	end })

	table.insert(hooks.clean, function()
		for flag in pairs(touch) do touch[flag] = false end
	end)
end)()

-- Opening cutscene. Its sound is a short MP3 kept inside this script: it is written to the executor's workspace once and
-- played from there. Without file support the cutscene uses two built-in sounds, or plays silent.
hooks.intro = { active = nil, data = nil, closed = false }
do
	local PATHS = { "SpriteRivalsMedia/intro_v1.mp3", "sprite_intro_v1.mp3" }
	local BYTES = 51572
	local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local FALLBACK = {
		{ at = 3.12, id = "rbxasset://sounds/impact_explosion_03.mp3" },
		{ at = 3.95, id = "rbxasset://sounds/electronicpingshort.wav" },
	}

	local function decode(text)
		text = string.gsub(text, "[^%w%+/=]", "")
		local lookup = {}
		for index = 1, 64 do lookup[string.byte(ALPHABET, index)] = index - 1 end
		local out, count = {}, 0
		for position = 1, #text, 4 do
			local a, b, c, d = string.byte(text, position, position + 3)
			local value = (lookup[a] or 0) * 262144 + (lookup[b] or 0) * 4096 + (lookup[c] or 0) * 64 + (lookup[d] or 0)
			local first, second, third = math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256
			count += 1
			if c == 61 then
				out[count] = string.char(first)
			elseif d == 61 then
				out[count] = string.char(first, second)
			else
				out[count] = string.char(first, second, third)
			end
		end
		return table.concat(out)
	end
	hooks.intro.decode = decode

	local function makeSound(id, volume)
		local ok, sound = pcall(function()
			local object = Instance.new("Sound")
			object.Name = randomName(8)
			object.SoundId = id
			object.Volume = volume
			object.Looped = false
			object.Parent = cloneref(game:GetService("SoundService"))
			return object
		end)
		return ok and sound or nil
	end

	---The asset id of the sound file, or nil when this executor can't play files from its workspace.
	local function assetFor(data)
		local fetch = getcustomasset or getsynasset
		if type(fetch) ~= "function" or type(isfile) ~= "function" or type(readfile) ~= "function" or type(writefile) ~= "function" then
			return nil
		end
		for _, path in ipairs(PATHS) do
			local ok, id = pcall(function()
				local folder = string.match(path, "^(.+)/")
				if folder and type(isfolder) == "function" and type(makefolder) == "function" and not isfolder(folder) then
					makefolder(folder)
				end
				if not (isfile(path) and #readfile(path) == BYTES) then writefile(path, decode(data)) end
				return fetch(path)
			end)
			if ok and type(id) == "string" and id ~= "" then return id end
		end
		return nil
	end

	---Plays the cutscene over the game. The menu is hidden for the duration and onDone is called when it ends.
	function hooks.intro.play(data, onDone)
		local running = hooks.intro.active
		if hooks.intro.closed or (running and not running.finished) then return false end

		hooks.introActive = true
		window.gui.Enabled = false

		local volume = math.clamp(Config.introVolume / 100, 0, 1) * 1.4
		local track, cues = nil, {}
		local asset = data and volume > 0 and assetFor(data)
		if asset then
			track = makeSound(asset, volume)
			if track then
				local waited = 0
				while not track.IsLoaded and waited < 1.5 do
					task.wait(0.05)
					waited += 0.05
				end
				if not track.IsLoaded then
					pcall(function() track:Destroy() end)
					track = nil
				end
			end
		end
		if not track and volume > 0 then
			for _, entry in ipairs(FALLBACK) do
				local sound = makeSound(entry.id, volume)
				if sound then table.insert(cues, { at = entry.at, sound = sound }) end
			end
		end

		if hooks.intro.closed then
			if track then pcall(function() track:Destroy() end) end
			for _, cue in ipairs(cues) do pcall(function() cue.sound:Destroy() end) end
			return false
		end

		local made, intro = pcall(window.Intro, window, { light = compat.on, touch = compat.on, track = track, cues = cues })
		if not made then
			warn("sprite intro could not start: " .. tostring(intro))
			hooks.introActive = false
			if track then pcall(function() track:Destroy() end) end
			for _, cue in ipairs(cues) do pcall(function() cue.sound:Destroy() end) end
			if onDone then onDone("error") end
			return false
		end

		hooks.intro.active = intro
		intro.start(function(reason)
			hooks.introActive = false
			if onDone then onDone(reason) end
		end)
		return true
	end

	---Called once when the script has finished loading.
	function hooks.intro.start(data)
		hooks.intro.data = data
		local function ready()
			window.gui.Enabled = not Config.menuStartHidden
			window:Notify(compat.on and "sprite loaded  |  the round button shows or hides the menu"
				or ("sprite loaded  |  " .. keyName(binds.menu) .. " toggles the menu"), 4)
		end
		if not Config.introEnabled or Config.farmEnabled then
			ready()
			return
		end
		hooks.introActive = true
		window.gui.Enabled = false
		task.spawn(function()
			local ok, problem = pcall(hooks.intro.play, data, ready)
			if not ok then
				warn("sprite intro failed: " .. tostring(problem))
				hooks.introActive = false
				ready()
			end
		end)
	end

	function hooks.intro.replay()
		hooks.intro.play(hooks.intro.data, function()
			window.gui.Enabled = true
		end)
	end

	table.insert(hooks.clean, function()
		hooks.intro.closed = true
		local running = hooks.intro.active
		if running and not running.finished then running.destroy() end
		hooks.introActive = false
	end)
end

local function matchesBind(input, key)
	if key == Enum.KeyCode.Unknown then return false end
	return input.KeyCode == key or input.UserInputType == key
end

table.insert(connections, userInputService.InputBegan:Connect(function(input, processed)
	heldKeys[input.KeyCode] = true

	if window.listening then return end

	-- Count the space press even when the game already used it, only typing blocks it.
	if input.KeyCode == Enum.KeyCode.Space and not userInputService:GetFocusedTextBox() then
		queueJump()
	end

	-- Don't hide the menu while typing in a text box (RightShift is also a typing key).
	if matchesBind(input, binds.menu) and not userInputService:GetFocusedTextBox() then
		window.gui.Enabled = not window.gui.Enabled
	end

	if processed then return end

	if matchesBind(input, binds.fly) then
		Config.flyEnabled = not Config.flyEnabled
		flyToggle:set(Config.flyEnabled)
		window:Notify("Fly: " .. (Config.flyEnabled and "ON" or "OFF"), 1.5)
	end

	if matchesBind(input, binds.ai) then
		Config.aiPlay = not Config.aiPlay
		widgets.aiPlay:set(Config.aiPlay)
		window:Notify("AI: " .. (Config.aiPlay and "ON" or "OFF"), 1.5)
	end

	if matchesBind(input, binds.aim) then
		Config.aimActive = Config.aimHold and true or not Config.aimActive
		if not Config.aimHold then
			window:Notify("Aim lock: " .. (Config.aimActive and "ON" or "OFF"), 1.5)
		end
	end

	if matchesBind(input, binds.espToggle) then
		Config.espEnabled = not Config.espEnabled
		widgets.espEnabled:set(Config.espEnabled)
		window:Notify("ESP: " .. (Config.espEnabled and "ON" or "OFF"), 1.5)
	end

	if matchesBind(input, binds.panic) and not userInputService:GetFocusedTextBox() then
		detach()
	end
end))

table.insert(connections, userInputService.InputEnded:Connect(function(input)
	heldKeys[input.KeyCode] = nil
	if Config.aimHold and matchesBind(input, binds.aim) then
		Config.aimActive = false
	end
end))

detach = function()
	if ai.dirty and Config.aiAutoSave then pcall(ai.saveBrain) end
	pcall(ai.releaseAll)
	pcall(function() runService:UnbindFromRenderStep(RENDER_NAME) end)
	for _, connection in ipairs(connections) do pcall(connection.Disconnect, connection) end
	for player in pairs(espObjects) do pcall(removeEsp, player) end

	for _, cleanup in ipairs(hooks.clean) do pcall(cleanup) end

	local drawings = {
		aimCircle, silentCircle, targetLine, featureList,
		radarBack, radarBorder, radarSelf, crosshairDot, crosshairLines.shadowDot,
	}
	for _, line in ipairs(crosshairLines) do table.insert(drawings, line) end
	for _, line in ipairs(crosshairLines.shadow) do table.insert(drawings, line) end
	for _, object in ipairs(drawings) do
		pcall(function() object:Remove() end)
	end
	pcall(watermark.destroy)

	worldRestore()
	silentPoint = nil
	if fovApplied then
		fovApplied = false
		pcall(function() workspace.CurrentCamera.FieldOfView = BASE_FOV end)
	end
	Config.flyEnabled, Config.thirdPerson = false, false
	pcall(applyThirdPerson)
	pcall(setfpscap, 240)
	pcall(function() window:destroy() end)

	for _, store in ipairs({ globalTable, shared }) do
		store[INSTANCE_KEY] = nil
		store.SpriteRivals = nil
	end
end

globalTable[INSTANCE_KEY] = { detach = detach }

-- Load the autoload profile last so every widget exists to receive its values.
refreshSavedList()
pcall(function()
	if not compat.isfile(AUTOLOAD_FILE) then return end
	local name = cleanConfigName(compat.readfile(AUTOLOAD_FILE))
	if loadConfig(name) then
		window:Notify("Autoloaded config: " .. name)
	end
end)

if Config.aiAutoload and pcall(ai.autoload) then
	ai.refreshSaved()
end

hooks.farm.resume()

hooks.ready = true
hooks.applyInterface()

-- The cutscene sound, as base64 MP3 (6.3 seconds).
hooks.intro.start([=[
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
bzflDTYzL1fPUi56TRUo6flDCqMVFRKYF+rQLdt1SgQEtpEYiMRFQ2KZ6dss/lzL8sXqcIAqj4sivR8YfcWQzq0zpSh/D9bjxDSYi5NPhVX0JFotr8Gr4f+U9T6lywWeVDlQVvs81K1SJhn8x01bXq70IihAy0M0
pCo+WfLHg696jQIFI4OkgHKnlM7//0bNfcMNdn+0f//brh+kl/l1Y/SZwcMgqfndbsS5yABNEktbGmGgCBOMuKMDxKi6treqeBDGqxIUsp+qtRFhzZ3aGcOs1rr/+1jE2gEPhTUpLSx6Sgkio8WnjxCm4IsMkPW4
8CtZ8bps9hatbmrT2m3NnADNh7Iqttt4v+etuy+4PHSqFuhn/+Y//83////7dKKrU5aCBFNK8HMAapS2vWpAakTM9mryU7wGvAs53qieoCTDFPUrxhYcBdcWl5/Fso42f7ctfvTm+UA6ey3mtSy90sJQ7pi2Lw6W
+8DpGt3/DuHXut22s2AxoRNlTSQmWaEpJzVhoQlUqklqe/Fd62KaEUKkqiBFBpRmj2nrUD3LYyNDMiN9bHr1xY4kJGAItFyQkb+wCsmJMRsrS5HagS3N64cDmZ3GG8VYuILInhXOL5mXLg5PZYtt5rAxwCDiYa+p
Hs2FAQYCTHtdrHEyxijf6/rDhqv/+1jE4AOPWKscTOmUgcAcooGnrtDVXY+sYVDVjVvq57bHerDpQ/9aU1Jjv+pN/3Y1Joaw1h9z/pBib2pfqXw7+pbf2MpBkv2/9lUX96xMNN90UKjPS0xBTUUzLjEwMFVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+1jE8AORBNcIB+FtQjc53gRnjeFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEw
MFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+1jE
egPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/+1jEegPAAAGkAAAAIAAANIAAAARVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVU=
]=])
