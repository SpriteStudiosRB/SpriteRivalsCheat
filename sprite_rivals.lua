if not game:IsLoaded() then game.Loaded:Wait() end

-- Services.
local playersService = cloneref(game:GetService("Players"))
local runService = cloneref(game:GetService("RunService"))
local userInputService = cloneref(game:GetService("UserInputService"))
local coreGui = cloneref(game:GetService("CoreGui"))
local tweenService = cloneref(game:GetService("TweenService"))
local httpService = cloneref(game:GetService("HttpService"))
local statsService = cloneref(game:GetService("Stats"))
local virtualUser = cloneref(game:GetService("VirtualUser"))
local lightingService = cloneref(game:GetService("Lighting"))

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
		}, Window)

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
		self.notifyHolder = create("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -18, 1, -18),
			Size = UDim2.fromOffset(260, 320),
			BackgroundTransparency = 1,
			ZIndex = 50,
			Parent = self.gui,
		}, { self.notifyLayout })

		-- Header: logo bubble, name, page title. The whole strip drags the window.
		local header = create("Frame", {
			Size = UDim2.new(1, 0, 0, HEADER_H),
			BackgroundTransparency = 1,
			ZIndex = 6,
			Parent = self.main,
		})
		local paint = function(instance, property, role) self:paint(instance, property, role) end
		local _, glow = logoBubble(header, 32, UDim2.fromOffset(EDGE + 2, 12), paint)
		self.logoGlow = glow

		textLabel({
			Position = UDim2.fromOffset(EDGE + 44, 7),
			Size = UDim2.fromOffset(110, 26),
			Text = title,
			Font = FONT_BRAND,
			TextSize = 21,
			Parent = header,
		})
		local tag = textLabel({
			Position = UDim2.fromOffset(EDGE + 45, 30),
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

	---Destroy the window.
	function Window:destroy()
		self.destroyed = true
		if self.blur then self.blur:Destroy() end
		for _, connection in ipairs(self.connections) do
			connection:Disconnect()
		end
		self.gui:Destroy()
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
	knifeEnabled = false, knifeAutoEquip = true, knifeSlot = "3", knifeRange = 10,
	knifeTeleport = false, knifeTpRange = 120, knifeDelay = 150,
	knifeBackstab = true, knifeBackAngle = 70,
	farmEnabled = false, farmMode = "Nearest", farmMethod = "Knife", farmDistance = 4, farmHeight = 0,
	spinEnabled = false, spinSpeed = 30,
	rapidFire = false, rapidRate = 12, antiAim = false, antiAimMode = "Jitter", antiAimAngle = 90,
	hitboxEnabled = false, hitboxSize = 8, hitboxPart = "Head", hitboxAlpha = 70,
	swapEnabled = false, swapDist = 12, swapGun = "1", dodgeJump = false, dodgeInterval = 1200,

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
}

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
local knifeEquipped = false
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

local function facingAway(root, targetRoot, angleLimit)
	local toUs = root.Position - targetRoot.Position
	if toUs.Magnitude < 0.01 then return true end
	local angle = math.deg(math.acos(math.clamp(targetRoot.CFrame.LookVector:Dot(toUs.Unit), -1, 1)))
	return angle <= angleLimit
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
	if Config.aimNeedRmb and not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then return end

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

	if Config.aimMethod == "Mouse" then
		if not onScreen or not isrbxactive() then return end

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
			mousemoverel(moveX, moveY)
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
	if os.clock() - lastShot < delayMs / 1000 or not isrbxactive() then return end
	lastShot = os.clock()
	mouse1click()
end

local function equipKnife()
	if knifeEquipped or not Config.knifeAutoEquip or not isrbxactive() then return end
	knifeEquipped = true
	keytap(SLOT_KEYS[Config.knifeSlot])
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
		farmTarget = pickFarmTarget(root)
		if farmTarget then
			local targetCharacter, _, targetRoot = getCharacterParts(farmTarget)
			local goal = targetRoot.CFrame * CFrame.new(0, Config.farmHeight, Config.farmDistance)
			root.CFrame = CFrame.lookAt(goal.Position, targetRoot.Position)
			root.AssemblyLinearVelocity = Vector3.zero

			if Config.farmMethod == "Knife" then
				equipKnife()
				currentCamera.CFrame = CFrame.lookAt(currentCamera.CFrame.Position, targetRoot.Position)
				if not Config.knifeBackstab or facingAway(root, targetRoot, Config.knifeBackAngle) then
					fireClick(Config.knifeDelay)
				end
			else
				local point = aimPoint(targetCharacter:FindFirstChild("Head") or targetRoot)
				currentCamera.CFrame = CFrame.lookAt(currentCamera.CFrame.Position, point)
				silentPoint, silentChance, silentCharacter = point, 100, targetCharacter
				fireClick(Config.rageDelay)
			end
			return
		end
		knifeEquipped = false
	else
		farmTarget = nil
	end

	-- Auto knifer.
	if Config.knifeEnabled and root then
		local best, bestDist = nil, Config.knifeTeleport and Config.knifeTpRange or Config.knifeRange
		for _, player in ipairs(playersService:GetPlayers()) do
			if not isEnemy(player) then continue end
			local _, _, targetRoot = getCharacterParts(player)
			if not targetRoot then continue end
			local dist = (targetRoot.Position - root.Position).Magnitude
			if dist < bestDist then best, bestDist = targetRoot, dist end
		end

		if best then
			equipKnife()
			if Config.knifeTeleport then
				local goal = best.CFrame * CFrame.new(0, 0, 3)
				root.CFrame = CFrame.lookAt(goal.Position, best.Position)
				root.AssemblyLinearVelocity = Vector3.zero
			end
			currentCamera.CFrame = CFrame.lookAt(currentCamera.CFrame.Position, best.Position)
			if not Config.knifeBackstab or facingAway(root, best, Config.knifeBackAngle) then
				fireClick(Config.knifeDelay)
			end
			return
		end
		knifeEquipped = false
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
		and (not Config.aimOnFire or userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1))
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
	{ "Knifer", "knifeEnabled" }, { "Farm", "farmEnabled" }, { "Spin", "spinEnabled" },
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
	return binds.slide ~= Enum.KeyCode.Unknown and heldKeys[binds.slide] == true
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
	if Config.sprintEnabled and hooks.held(binds.sprint) and not userInputService:GetFocusedTextBox() then
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
		if heldKeys[Enum.KeyCode.Space] then move += Vector3.yAxis end
		if heldKeys[Enum.KeyCode.LeftShift] then move -= Vector3.yAxis end

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
	if not queued and Config.bhop and not typing and grounded and heldKeys[Enum.KeyCode.Space] then
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
			if not isfolder(FOLDER) then makefolder(FOLDER) end
			writefile(brainPath(name), httpService:JSONEncode(brain))
			if not keepAutoload then writefile(AUTOLOAD, name) end
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
			if not isfile(path) then return end
			local text = readfile(path)
			if #text > MAX_TEXT then return end
			clean = sanitize(httpService:JSONDecode(text))
		end)
		if not clean then return false end

		clean.name = name
		ai.brain, ai.dirty, ai.lastSave = clean, false, os.clock()
		pcall(writefile, AUTOLOAD, name)
		return true
	end

	function ai.listBrains()
		local names = {}
		pcall(function()
			if not isfolder(FOLDER) then return end
			for _, path in ipairs(listfiles(FOLDER)) do
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
			if not isfile(path) then return false end
			delfile(path)
			return true
		end)
		return ok and removed == true, name
	end

	function ai.autoload()
		local ok, name = pcall(function()
			if isfile(AUTOLOAD) then return cleanName(readfile(AUTOLOAD)) end
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
				knifeEquipped = false
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
		setfpscap(desiredCap)
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
		if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
		writefile(configPath(name), encodeConfig())
	end)
end

local function loadConfig(name)
	local path = configPath(name)
	if not isfile(path) then return false end

	local ok, data = pcall(function() return httpService:JSONDecode(readfile(path)) end)
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
	if not isfile(path) then return false end

	local ok = pcall(delfile, path)
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
		if Config.glideEnabled and heldKeys[Enum.KeyCode.Space] and velocity.Y < -Config.glideSpeed
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
			window:Notify("Nothing under the cursor", 1.5)
			return
		end

		local look = root.CFrame.LookVector
		local goal = hit.Position + Vector3.new(0, 3.2, 0)
		root.CFrame = CFrame.lookAt(goal, goal + Vector3.new(look.X, 0, look.Z) + Vector3.new(0, 0, 0.001))
		root.AssemblyLinearVelocity = Vector3.zero
	end

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
		local zooming = Config.zoomEnabled and hooks.held(binds.zoom) and not userInputService:GetFocusedTextBox()
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
		if Config.farmEnabled or Config.knifeEnabled then return end

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
		if Config.aiPlay or Config.farmEnabled or Config.knifeEnabled then return end
		if now - swapAt < 0.5 or not isrbxactive() or userInputService:GetFocusedTextBox() then return end

		local _, _, root = getCharacterParts(localPlayer)
		if not root then return end

		local _, distance = nearestEnemyRoot(root)
		local close = distance ~= nil and distance <= Config.swapDist
		local wanted = close and "knife" or "gun"
		if wanted ~= swapState then
			swapState, swapAt = wanted, now
			local key = SLOT_KEYS[close and Config.knifeSlot or Config.swapGun]
			if key then keytap(key) end
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
		if Config.aimRecoil <= 0 or Config.aiPlay or not isrbxactive() then return end
		if userInputService:GetFocusedTextBox() then return end
		if not userInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then return end
		mousemoverel(0, Config.aimRecoil)
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
			if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
			writefile(path, encodeConfig())
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
			if not isfile(path) then error("missing") end
			writefile(configPath(to), readfile(path))
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
rageTab:Section("Auto Knifer")
toggle(rageTab, "Knifer enabled", "knifeEnabled")
toggle(rageTab, "Auto equip knife", "knifeAutoEquip")
dropdown(rageTab, "Knife slot", "knifeSlot", { "1", "2", "3", "4" })
slider(rageTab, "Swing range", "knifeRange", 3, 30)
toggle(rageTab, "Teleport to target", "knifeTeleport")
slider(rageTab, "Teleport range", "knifeTpRange", 10, 300)
slider(rageTab, "Swing delay (ms)", "knifeDelay", 50, 1000)
toggle(rageTab, "Require backstab angle", "knifeBackstab")
slider(rageTab, "Backstab angle", "knifeBackAngle", 10, 180)
rageTab:Section("Auto Farm")
toggle(rageTab, "Farm enabled", "farmEnabled")
dropdown(rageTab, "Target mode", "farmMode", { "Nearest", "Lowest HP", "Random" })
dropdown(rageTab, "Kill method", "farmMethod", { "Knife", "Gun" })
slider(rageTab, "Distance behind", "farmDistance", 1, 15)
slider(rageTab, "Height offset", "farmHeight", -5, 15)
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
		if not isfolder(CONFIG_FOLDER) then return end
		for _, path in ipairs(listfiles(CONFIG_FOLDER)) do
			local name = string.match(path, "([^/\\]+)%.json$")
			if name and string.sub(name, 1, 1) ~= "_" then table.insert(names, name) end
		end
	end)
	table.sort(names)
	savedLabel.Text = "Saved: " .. (#names > 0 and table.concat(names, ", ") or "none")

	local autoload = "none"
	pcall(function()
		if isfile(AUTOLOAD_FILE) then autoload = cleanConfigName(readfile(AUTOLOAD_FILE)) end
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
		if not isfolder(CONFIG_FOLDER) then makefolder(CONFIG_FOLDER) end
		writefile(AUTOLOAD_FILE, name)
	end)
	window:Notify(ok and ("Autoload: " .. name) or "Could not set autoload")
	refreshSavedList()
end)

configTab:Button("Clear autoload", function()
	pcall(function()
		if isfile(AUTOLOAD_FILE) then delfile(AUTOLOAD_FILE) end
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
	window.scale.Scale = value / 100
end)
toggle(interfaceTab, "Bubble animations", "menuAnimations", function(state)
	window:setAnimated(state)
end)
toggle(interfaceTab, "Frosted blur", "menuBlur", function(state)
	window:setBlur(state)
end)
interfaceTab:Label("Click a bind, then press a key. Esc cancels, Backspace clears", 2)
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
	if not isfile(AUTOLOAD_FILE) then return end
	local name = cleanConfigName(readfile(AUTOLOAD_FILE))
	if loadConfig(name) then
		window:Notify("Autoloaded config: " .. name)
	end
end)

if Config.aiAutoload and pcall(ai.autoload) then
	ai.refreshSaved()
end

hooks.ready = true
hooks.applyInterface()

window:Notify("sprite loaded  |  " .. keyName(binds.menu) .. " toggles the menu", 4)
if Config.menuStartHidden then window.gui.Enabled = false end
