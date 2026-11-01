if not game:IsLoaded() then game.Loaded:Wait() end

-- Services.
local playersService = cloneref(game:GetService("Players"))
local runService = cloneref(game:GetService("RunService"))
local userInputService = cloneref(game:GetService("UserInputService"))
local coreGui = cloneref(game:GetService("CoreGui"))
local tweenService = cloneref(game:GetService("TweenService"))

local localPlayer = playersService.LocalPlayer
local currentCamera = workspace.CurrentCamera

if shared.SpriteRivals then
	shared.SpriteRivals.detach()
end

-- UI constants.
local BUBBLE_COUNT = 36
local CYAN = Color3.fromRGB(80, 220, 255)
local WHITE = Color3.fromRGB(255, 255, 255)
local DEEP_BLUE = Color3.fromRGB(10, 40, 70)
local SOFT_BLUE = Color3.fromRGB(120, 170, 255)

local FizzUI = {}
FizzUI.__index = FizzUI

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

---Create an instance with properties and children.
local function create(className, properties, children)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

---Tween helper with a smooth default style.
local function tween(instance, duration, goal)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local playing = tweenService:Create(instance, info, goal)
	playing:Play()
	return playing
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

local function stroke(color, transparency, thickness)
	return create("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

---Frosted glass row used by every control.
local function glassRow(parent, height)
	local row = create("Frame", {
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.88,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		corner(10),
		stroke(WHITE, 0.8),
		create("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(0, 0.6),
		}),
	})
	return row
end

---Build the animated carbonation layer.
function Window:buildBubbles(container)
	self.bubbles = {}
	for _ = 1, BUBBLE_COUNT do
		local size = math.random(6, 24)
		local frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.88,
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = container,
		}, {
			corner(size),
			stroke(CYAN, 0.55),
		})
		table.insert(self.bubbles, {
			frame = frame,
			x = math.random(),
			y = math.random(),
			speed = 0.04 + math.random() * 0.08,
			sway = 0.01 + math.random() * 0.02,
			freq = 0.8 + math.random() * 1.6,
			phase = math.random() * 6.28,
		})
	end

	self.bubbleConnection = runService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		for _, bubble in ipairs(self.bubbles) do
			bubble.y -= bubble.speed * deltaTime
			if bubble.y < -0.1 then
				bubble.y = 1.1
				bubble.x = math.random()
			end
			local offsetX = math.sin(now * bubble.freq + bubble.phase) * bubble.sway
			bubble.frame.Position = UDim2.fromScale(bubble.x + offsetX, bubble.y)
		end
	end)
end

---Create the main window.
---@param title string
function FizzUI.new(title)
	local self = setmetatable({ tabs = {}, activeTab = nil, connections = {}, listening = false }, Window)

	local parent = (gethui and gethui()) or localPlayer:WaitForChild("PlayerGui")
	self.gui = create("ScreenGui", {
		Name = "FizzUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = parent,
	})

	self.main = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundColor3 = DEEP_BLUE,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = self.gui,
	}, {
		corner(20),
		stroke(CYAN, 0.45, 1.5),
		create("UIGradient", {
			Rotation = 135,
			Color = ColorSequence.new(SOFT_BLUE, DEEP_BLUE),
			Transparency = NumberSequence.new(0.1, 0.45),
		}),
	})

	-- Diagonal reflection streak.
	create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = self.main,
	}, {
		create("UIGradient", {
			Rotation = 35,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.3, 0.7),
				NumberSequenceKeypoint.new(0.45, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})

	local bubbleLayer = create("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Parent = self.main,
	})
	self:buildBubbles(bubbleLayer)

	-- Header with branding.
	local header = create("Frame", {
		Size = UDim2.new(1, 0, 0, 56),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = self.main,
	})

	local logo = create("Frame", {
		Position = UDim2.fromOffset(18, 14),
		Size = UDim2.fromOffset(28, 28),
		BackgroundColor3 = CYAN,
		BackgroundTransparency = 0.35,
		ZIndex = 5,
		Parent = header,
	}, {
		corner(14),
		stroke(WHITE, 0.3, 1.5),
		create("Frame", {
			Position = UDim2.fromOffset(6, 5),
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, { corner(4) }),
	})

	create("TextLabel", {
		Position = UDim2.fromOffset(56, 8),
		Size = UDim2.fromOffset(200, 24),
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = header,
	})
	create("TextLabel", {
		Position = UDim2.fromOffset(56, 30),
		Size = UDim2.fromOffset(200, 16),
		BackgroundTransparency = 1,
		Text = "crisp. clear. refreshing.",
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextColor3 = CYAN,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = header,
	})

	-- Pulse the logo glow.
	task.spawn(function()
		local glow = logo:FindFirstChildOfClass("UIStroke")
		while self.gui.Parent do
			tween(glow, 1.2, { Transparency = 0.7 }).Completed:Wait()
			tween(glow, 1.2, { Transparency = 0.2 }).Completed:Wait()
		end
	end)

	-- Sidebar and content.
	self.sidebar = create("Frame", {
		Position = UDim2.fromOffset(14, 62),
		Size = UDim2.new(0, 130, 1, -76),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.9,
		ZIndex = 5,
		Parent = self.main,
	}, {
		corner(14),
		stroke(WHITE, 0.82),
		create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		create("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),
	})

	self.content = create("Frame", {
		Position = UDim2.fromOffset(156, 62),
		Size = UDim2.new(1, -170, 1, -76),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = self.main,
	})

	-- Dragging.
	local dragging, dragStart, startPosition
	header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = self.main.Position
		end
	end)
	table.insert(self.connections, userInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			self.main.Position = UDim2.new(
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

	-- Open animation.
	tween(self.main, 0.6, { Size = UDim2.fromOffset(580, 390) })

	return self
end

---Switch tabs with a fade and slide.
function Window:selectTab(tab)
	if self.activeTab == tab then
		return
	end
	local previous = self.activeTab
	self.activeTab = tab

	if previous then
		tween(previous.page, 0.15, { GroupTransparency = 1 })
		tween(previous.button, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.15, function()
			if self.activeTab ~= previous then
				previous.page.Visible = false
			end
		end)
	end

	tab.page.Visible = true
	tab.page.GroupTransparency = 1
	tab.page.Position = UDim2.fromOffset(18, 0)
	tween(tab.page, 0.3, { GroupTransparency = 0, Position = UDim2.fromOffset(0, 0) })
	tween(tab.button, 0.2, { BackgroundTransparency = 0.7 })
end

---Add a tab to the sidebar.
---@param name string
function Window:Tab(name)
	local tab = setmetatable({ window = self }, Tab)

	tab.button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundColor3 = CYAN,
		BackgroundTransparency = 1,
		Text = name,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = WHITE,
		AutoButtonColor = false,
		ZIndex = 6,
		LayoutOrder = #self.tabs,
		Parent = self.sidebar,
	}, { corner(10) })

	tab.page = create("CanvasGroup", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		GroupTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = self.content,
	})

	tab.holder = create("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = CYAN,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ZIndex = 5,
		Parent = tab.page,
	}, {
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})

	tab.button.MouseEnter:Connect(function()
		if self.activeTab ~= tab then
			tween(tab.button, 0.15, { BackgroundTransparency = 0.88 })
		end
	end)
	tab.button.MouseLeave:Connect(function()
		if self.activeTab ~= tab then
			tween(tab.button, 0.15, { BackgroundTransparency = 1 })
		end
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

---Add a toggle switch. Returns a handle with :set(state).
function Tab:Toggle(text, default, callback)
	local row = glassRow(self.holder, 40)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -80, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})

	local track = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(44, 22),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.75,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 6,
		Parent = row,
	}, { corner(11), stroke(WHITE, 0.6) })

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(16, 16),
		BackgroundColor3 = WHITE,
		ZIndex = 7,
		Parent = track,
	}, { corner(8) })

	local state = default or false
	local function render(animate)
		local duration = animate and 0.25 or 0
		tween(track, duration, {
			BackgroundColor3 = state and CYAN or WHITE,
			BackgroundTransparency = state and 0.2 or 0.75,
		})
		tween(knob, duration, {
			Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
		})
	end
	render(false)

	track.MouseButton1Click:Connect(function()
		state = not state
		render(true)
		if callback then
			task.spawn(callback, state)
		end
	end)

	return {
		set = function(_, newState)
			state = newState
			render(true)
		end,
	}
end

---Add a slider.
function Tab:Slider(text, minimum, maximum, default, callback)
	local row = glassRow(self.holder, 54)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.new(1, -90, 0, 18),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})
	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 6),
		Size = UDim2.fromOffset(60, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = CYAN,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 6,
		Parent = row,
	})

	local bar = create("Frame", {
		Position = UDim2.new(0, 14, 1, -18),
		Size = UDim2.new(1, -28, 0, 6),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0.8,
		ZIndex = 6,
		Parent = row,
	}, { corner(3) })

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = CYAN,
		ZIndex = 7,
		Parent = bar,
	}, {
		corner(3),
		create("UIGradient", { Color = ColorSequence.new(SOFT_BLUE, CYAN) }),
	})

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = WHITE,
		ZIndex = 8,
		Parent = fill,
	}, { corner(7), stroke(CYAN, 0.2, 2) })

	local value = default or minimum
	local function setValue(newValue, animate)
		value = math.clamp(math.floor(newValue + 0.5), minimum, maximum)
		local alpha = (value - minimum) / (maximum - minimum)
		tween(fill, animate and 0.08 or 0, { Size = UDim2.fromScale(alpha, 1) })
		valueLabel.Text = tostring(value)
		if callback then
			task.spawn(callback, value)
		end
	end
	setValue(value, false)

	local sliding = false
	local function update(input)
		local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		setValue(minimum + (maximum - minimum) * alpha, true)
	end
	bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliding = true
			tween(knob, 0.15, { Size = UDim2.fromOffset(18, 18) })
			update(input)
		end
	end)
	table.insert(self.window.connections, userInputService.InputChanged:Connect(function(input)
		if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input)
		end
	end))
	table.insert(self.window.connections, userInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			sliding = false
			tween(knob, 0.15, { Size = UDim2.fromOffset(14, 14) })
		end
	end))
end

---Add a dropdown. Clicking cycles to the next option.
function Tab:Dropdown(text, options, default, callback)
	local row = glassRow(self.holder, 40)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -150, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})

	local index = table.find(options, default) or 1
	local button = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(116, 24),
		BackgroundColor3 = CYAN,
		BackgroundTransparency = 0.7,
		Text = options[index],
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = WHITE,
		AutoButtonColor = false,
		ZIndex = 6,
		Parent = row,
	}, { corner(8), stroke(CYAN, 0.4) })

	button.MouseButton1Click:Connect(function()
		index = index % #options + 1
		button.Text = options[index]
		if callback then
			task.spawn(callback, options[index])
		end
	end)
end

---Add a keybind picker. Click, then press a key (Escape keeps the current one).
function Tab:Bind(text, default, callback)
	local window = self.window
	local row = glassRow(self.holder, 40)
	create("TextLabel", {
		Position = UDim2.fromOffset(14, 0),
		Size = UDim2.new(1, -120, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = row,
	})

	local current = default
	local listening = false
	local button = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(86, 24),
		BackgroundColor3 = CYAN,
		BackgroundTransparency = 0.7,
		Text = current.Name,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = WHITE,
		AutoButtonColor = false,
		ZIndex = 6,
		Parent = row,
	}, { corner(8), stroke(CYAN, 0.4) })

	button.MouseButton1Click:Connect(function()
		listening = true
		window.listening = true
		button.Text = "..."
	end)

	table.insert(window.connections, userInputService.InputBegan:Connect(function(input)
		if not listening then return end

		local pick
		if input.KeyCode == Enum.KeyCode.Escape then
			pick = current
		elseif input.KeyCode ~= Enum.KeyCode.Unknown then
			pick = input.KeyCode
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.MouseButton3 then
			pick = input.UserInputType
		end
		if not pick then return end

		listening = false
		current = pick
		button.Text = pick.Name
		if callback then callback(pick) end

		-- Clear after other handlers see this press so it doesn't trigger the new bind.
		task.defer(function() window.listening = false end)
	end))
end

---Add a button.
function Tab:Button(text, callback)
	local button = create("TextButton", {
		Size = UDim2.new(1, -8, 0, 40),
		BackgroundColor3 = CYAN,
		BackgroundTransparency = 0.6,
		Text = text,
		Font = Enum.Font.GothamMedium,
		TextSize = 14,
		TextColor3 = WHITE,
		AutoButtonColor = false,
		ZIndex = 6,
		Parent = self.holder,
	}, {
		corner(10),
		stroke(CYAN, 0.3),
		create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 0.4) }),
	})

	button.MouseEnter:Connect(function()
		tween(button, 0.15, { BackgroundTransparency = 0.35 })
	end)
	button.MouseLeave:Connect(function()
		tween(button, 0.2, { BackgroundTransparency = 0.6 })
	end)
	button.MouseButton1Down:Connect(function()
		tween(button, 0.08, { Size = UDim2.new(1, -14, 0, 38) })
	end)
	button.MouseButton1Up:Connect(function()
		tween(button, 0.15, { Size = UDim2.new(1, -8, 0, 40) })
	end)
	button.MouseButton1Click:Connect(function()
		if callback then
			task.spawn(callback)
		end
	end)
end

---Add a section label. Returns the TextLabel.
function Tab:Label(text)
	return create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 22),
		BackgroundTransparency = 1,
		Text = string.upper(text),
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = CYAN,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6,
		Parent = self.holder,
	})
end

---Destroy the window.
function Window:destroy()
	if self.bubbleConnection then
		self.bubbleConnection:Disconnect()
	end
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.gui:Destroy()
end

-- Script state.
local Config = {
	espBox = false, espName = false, espHealth = false, espDistance = false,
	espTracer = false, espSkeleton = false, espHeadDot = false, espChams = false,
	espMaxDist = 2000, teamCheck = true,

	aimEnabled = false, aimActive = false, aimHold = false, aimFov = 150, aimShowFov = true,
	aimSmoothOn = true, aimSmooth = 60, aimPart = "Head", aimMethod = "Camera", aimPrediction = 0,
	wallCheck = true,

	silentEnabled = false, silentFov = 200, silentShowFov = true, silentHitChance = 100,

	rageEnabled = false, rageAutoShoot = true, rageIgnoreWalls = true, rageDelay = 50,
	triggerEnabled = false, triggerDelay = 50,
	knifeEnabled = false, knifeAutoEquip = true, knifeSlot = "3", knifeRange = 10,
	knifeTeleport = false, knifeTpRange = 120, knifeDelay = 150,
	knifeBackstab = true, knifeBackAngle = 70,
	farmEnabled = false, farmMode = "Nearest", farmMethod = "Knife", farmDistance = 4, farmHeight = 0,
	spinEnabled = false, spinSpeed = 30,

	walkEnabled = false, walkSpeed = 24,
	slideEnabled = false, slideSpeed = 60,
	infJump = false,
	jumpEnabled = false, jumpPower = 50,
	strafeEnabled = false, strafeSpeed = 60,
	flyEnabled = false, flyMode = "Linear", flySpeed = 60,

	fovOffset = 0, thirdPerson = false,
	fpsEnabled = false, fpsCap = 240,
}

local binds = {
	aim = Enum.KeyCode.Q,
	fly = Enum.KeyCode.P,
	menu = Enum.KeyCode.RightShift,
}

local BASE_FOV = 70
local SLIDE_KEYS = { [Enum.KeyCode.LeftControl] = true, [Enum.KeyCode.C] = true }
local SLOT_KEYS = { ["1"] = 0x31, ["2"] = 0x32, ["3"] = 0x33, ["4"] = 0x34 }

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
local silentLocked = nil
local rageLocked = nil
local farmTarget = nil
local knifeEquipped = false
local espCleared = false
local lastShot = 0
local lastFpsCap = 240
local fpsStatus = nil
local window = nil
local originalMinZoom, originalMaxZoom = localPlayer.CameraMinZoomDistance, localPlayer.CameraMaxZoomDistance
local detach

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local aimCircle = Drawing.new("Circle")
aimCircle.Thickness = 1
aimCircle.NumSides = 64
aimCircle.Color = Color3.fromRGB(255, 255, 255)

local silentCircle = Drawing.new("Circle")
silentCircle.Thickness = 1
silentCircle.NumSides = 64
silentCircle.Color = Color3.fromRGB(255, 80, 80)

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

local function aimAt(point, dt)
	local retain = Config.aimSmoothOn and math.clamp(Config.aimSmooth / 100, 0, 0.99) or 0
	local alpha = 1 - retain ^ (dt * 60)

	if Config.aimMethod == "Mouse" then
		local screenPos, onScreen = currentCamera:WorldToViewportPoint(point)
		if not onScreen or not isrbxactive() then return end
		local delta = (Vector2.new(screenPos.X, screenPos.Y) - userInputService:GetMouseLocation()) * alpha
		mousemoverel(delta.X, delta.Y)
		return
	end

	local goal = CFrame.lookAt(currentCamera.CFrame.Position, point)
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
		if target and isEnemy(target) then fireClick(Config.triggerDelay) end
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
	if Config.aimEnabled and Config.aimActive then
		local part, player = getTarget(Config.aimFov, false, aimLocked)
		aimLocked = player
		if part then aimAt(aimPoint(part), dt) end
	else
		aimLocked = nil
	end
end

local function newDrawing(class, props)
	local object = Drawing.new(class)
	for key, value in pairs(props) do object[key] = value end
	return object
end

local function createEsp(player)
	local esp = {
		box = newDrawing("Square", { Thickness = 1, Filled = false, Color = Color3.new(1, 1, 1) }),
		boxOutline = newDrawing("Square", { Thickness = 3, Filled = false, Color = Color3.new(0, 0, 0) }),
		name = newDrawing("Text", { Size = 13, Center = true, Outline = true, Color = Color3.new(1, 1, 1) }),
		distance = newDrawing("Text", { Size = 12, Center = true, Outline = true, Color = Color3.fromRGB(200, 200, 200) }),
		healthBar = newDrawing("Line", { Thickness = 2, Color = Color3.fromRGB(0, 255, 0) }),
		healthBack = newDrawing("Line", { Thickness = 4, Color = Color3.new(0, 0, 0) }),
		tracer = newDrawing("Line", { Thickness = 1, Color = Color3.new(1, 1, 1) }),
		headDot = newDrawing("Circle", { Thickness = 1, NumSides = 20, Filled = false, Color = Color3.fromRGB(255, 60, 60) }),
		bones = {},
		highlight = nil,
	}
	for i = 1, #R15_BONES do
		esp.bones[i] = newDrawing("Line", { Thickness = 1, Color = Color3.new(1, 1, 1) })
	end
	espObjects[player] = esp
end

local function hideEsp(esp)
	esp.box.Visible = false
	esp.boxOutline.Visible = false
	esp.name.Visible = false
	esp.distance.Visible = false
	esp.healthBar.Visible = false
	esp.healthBack.Visible = false
	esp.tracer.Visible = false
	esp.headDot.Visible = false
	for _, line in ipairs(esp.bones) do line.Visible = false end
	if esp.highlight then esp.highlight.Enabled = false end
end

local function removeEsp(player)
	local esp = espObjects[player]
	if not esp then return end
	for key, value in pairs(esp) do
		if key == "bones" then
			for _, line in ipairs(value) do line:Remove() end
		elseif key == "highlight" then
			if value then value:Destroy() end
		else
			value:Remove()
		end
	end
	espObjects[player] = nil
end

local function updateEsp(player, esp)
	local character, humanoid, root = getCharacterParts(player)
	if not character or not isEnemy(player) then return hideEsp(esp) end

	local distance = (currentCamera.CFrame.Position - root.Position).Magnitude
	if distance > Config.espMaxDist then return hideEsp(esp) end

	local rootPos, onScreen = currentCamera:WorldToViewportPoint(root.Position)
	if not onScreen then return hideEsp(esp) end

	local top = currentCamera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
	local bottom = currentCamera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.5, 0))
	local height = math.abs(bottom.Y - top.Y)
	local width = height / 1.8
	local boxPos = Vector2.new(rootPos.X - width / 2, top.Y)
	local boxSize = Vector2.new(width, height)

	esp.box.Visible = Config.espBox
	esp.boxOutline.Visible = Config.espBox
	if Config.espBox then
		esp.box.Position, esp.box.Size = boxPos, boxSize
		esp.boxOutline.Position, esp.boxOutline.Size = boxPos, boxSize
	end

	esp.name.Visible = Config.espName
	if Config.espName then
		esp.name.Text = player.DisplayName
		esp.name.Position = Vector2.new(rootPos.X, top.Y - 16)
	end

	esp.distance.Visible = Config.espDistance
	if Config.espDistance then
		esp.distance.Text = string.format("[%dm]", distance)
		esp.distance.Position = Vector2.new(rootPos.X, bottom.Y + 2)
	end

	esp.healthBar.Visible = Config.espHealth
	esp.healthBack.Visible = Config.espHealth
	if Config.espHealth then
		local ratio = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
		local x = boxPos.X - 5
		esp.healthBack.From, esp.healthBack.To = Vector2.new(x, boxPos.Y + height), Vector2.new(x, boxPos.Y)
		esp.healthBar.From = Vector2.new(x, boxPos.Y + height)
		esp.healthBar.To = Vector2.new(x, boxPos.Y + height - height * ratio)
		esp.healthBar.Color = Color3.fromRGB(255 * (1 - ratio), 255 * ratio, 0)
	end

	esp.tracer.Visible = Config.espTracer
	if Config.espTracer then
		esp.tracer.From = Vector2.new(currentCamera.ViewportSize.X / 2, currentCamera.ViewportSize.Y)
		esp.tracer.To = Vector2.new(rootPos.X, bottom.Y)
	end

	local head = character:FindFirstChild("Head")
	esp.headDot.Visible = false
	if Config.espHeadDot and head then
		local headPos, headOn = currentCamera:WorldToViewportPoint(head.Position)
		if headOn then
			esp.headDot.Visible = true
			esp.headDot.Position = Vector2.new(headPos.X, headPos.Y)
			esp.headDot.Radius = math.max(height / 12, 2)
		end
	end

	local bones = humanoid.RigType == Enum.HumanoidRigType.R15 and R15_BONES or R6_BONES
	for i, line in ipairs(esp.bones) do
		line.Visible = false
		local pair = bones[i]
		if not (Config.espSkeleton and pair) then continue end
		local a, b = character:FindFirstChild(pair[1]), character:FindFirstChild(pair[2])
		if not (a and b) then continue end
		local aPos, aOn = currentCamera:WorldToViewportPoint(a.Position)
		local bPos, bOn = currentCamera:WorldToViewportPoint(b.Position)
		if aOn and bOn then
			line.Visible = true
			line.From, line.To = Vector2.new(aPos.X, aPos.Y), Vector2.new(bPos.X, bPos.Y)
		end
	end

	if Config.espChams then
		if not esp.highlight then
			esp.highlight = Instance.new("Highlight")
			esp.highlight.FillColor = Color3.fromRGB(255, 60, 60)
			esp.highlight.OutlineColor = Color3.new(1, 1, 1)
			esp.highlight.FillTransparency = 0.5
			esp.highlight.Parent = gethui and gethui() or coreGui
		end
		esp.highlight.Adornee = character
		esp.highlight.Enabled = true
	elseif esp.highlight then
		esp.highlight.Enabled = false
	end
end

local function updateMovement()
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end

	if Config.walkEnabled then
		humanoid.WalkSpeed = Config.walkSpeed
	end

	if Config.jumpEnabled then
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.jumpPower
	end

	local velocity = root.AssemblyLinearVelocity

	if Config.flyEnabled then
		local view = currentCamera.CFrame
		local move = Vector3.zero
		if heldKeys[Enum.KeyCode.W] then move += view.LookVector end
		if heldKeys[Enum.KeyCode.S] then move -= view.LookVector end
		if heldKeys[Enum.KeyCode.D] then move += view.RightVector end
		if heldKeys[Enum.KeyCode.A] then move -= view.RightVector end
		if heldKeys[Enum.KeyCode.Space] then move += Vector3.yAxis end
		if heldKeys[Enum.KeyCode.LeftShift] then move -= Vector3.yAxis end

		local target = move.Magnitude > 0 and move.Unit * Config.flySpeed or Vector3.zero
		root.AssemblyLinearVelocity = Config.flyMode == "Smooth" and velocity:Lerp(target, 0.15) or target
		return
	end

	local direction = humanoid.MoveDirection
	local airborne = humanoid.FloorMaterial == Enum.Material.Air

	if Config.strafeEnabled and airborne and direction.Magnitude > 0 then
		local target = Vector3.new(direction.X * Config.strafeSpeed, velocity.Y, direction.Z * Config.strafeSpeed)
		root.AssemblyLinearVelocity = velocity:Lerp(target, 0.2)
		return
	end

	local sliding = false
	if Config.slideEnabled and not airborne then
		for key in pairs(SLIDE_KEYS) do
			if heldKeys[key] then sliding = true break end
		end
	end

	if sliding and direction.Magnitude > 0 then
		local target = Vector3.new(direction.X * Config.slideSpeed, velocity.Y, direction.Z * Config.slideSpeed)
		root.AssemblyLinearVelocity = velocity:Lerp(target, 0.35)
	elseif Config.walkEnabled and not airborne and direction.Magnitude > 0 then
		-- WalkSpeed alone is ignored by Rivals' movement, so drive velocity directly.
		local target = Vector3.new(direction.X * Config.walkSpeed, velocity.Y, direction.Z * Config.walkSpeed)
		root.AssemblyLinearVelocity = velocity:Lerp(target, 0.4)
	end
end

local function applyThirdPerson()
	if Config.thirdPerson then
		localPlayer.CameraMinZoomDistance = 12
		localPlayer.CameraMaxZoomDistance = 12
	else
		localPlayer.CameraMinZoomDistance = originalMinZoom
		localPlayer.CameraMaxZoomDistance = originalMaxZoom
	end
end

local function onRender(dt)
	currentCamera = workspace.CurrentCamera
	local mouse = userInputService:GetMouseLocation()

	if Config.fovOffset > 0 then
		currentCamera.FieldOfView = BASE_FOV + Config.fovOffset
	end

	local desiredCap = Config.fpsEnabled and Config.fpsCap or 240
	if desiredCap ~= lastFpsCap then
		lastFpsCap = desiredCap
		setfpscap(desiredCap)
	end
	if fpsStatus then
		fpsStatus.Text = string.upper(Config.fpsEnabled and ("Status: capped at " .. Config.fpsCap) or "Status: restored to 240")
	end

	updateMovement()
	updateCombat(dt)

	aimCircle.Position = mouse
	aimCircle.Radius = Config.aimFov
	aimCircle.Visible = Config.aimEnabled and Config.aimShowFov and not Config.rageEnabled and not Config.farmEnabled

	silentCircle.Position = mouse
	silentCircle.Radius = Config.silentFov
	silentCircle.Visible = Config.silentEnabled and Config.silentShowFov and not Config.rageEnabled and not Config.farmEnabled

	local espActive = Config.espBox or Config.espName or Config.espHealth or Config.espDistance
		or Config.espTracer or Config.espSkeleton or Config.espHeadDot or Config.espChams
	if espActive then
		espCleared = false
		for player, esp in pairs(espObjects) do
			updateEsp(player, esp)
		end
	elseif not espCleared then
		espCleared = true
		for _, esp in pairs(espObjects) do hideEsp(esp) end
	end
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

-- Menu.
window = FizzUI.new("sprite")

local function toggle(tab, text, key, extra)
	return tab:Toggle(text, Config[key], function(state)
		Config[key] = state
		if extra then extra() end
	end)
end

local function slider(tab, text, key, minimum, maximum)
	tab:Slider(text, minimum, maximum, Config[key], function(value)
		Config[key] = value
	end)
end

local function dropdown(tab, text, key, options)
	tab:Dropdown(text, options, Config[key], function(value)
		Config[key] = value
	end)
end

local function bind(tab, text, name)
	tab:Bind(text, binds[name], function(key)
		binds[name] = key
	end)
end

local mainTab = window:Tab("Main")
mainTab:Label("Movement")
toggle(mainTab, "Walk speed", "walkEnabled")
slider(mainTab, "Walk speed value", "walkSpeed", 16, 200)
toggle(mainTab, "Slide speed", "slideEnabled")
slider(mainTab, "Slide speed value", "slideSpeed", 16, 300)
toggle(mainTab, "Infinite double jump", "infJump")
toggle(mainTab, "Jump power", "jumpEnabled")
slider(mainTab, "Jump power value", "jumpPower", 50, 200)
toggle(mainTab, "Auto strafe", "strafeEnabled")
slider(mainTab, "Strafe speed", "strafeSpeed", 16, 250)
local flyToggle = toggle(mainTab, "Fly", "flyEnabled")
bind(mainTab, "Fly key", "fly")
dropdown(mainTab, "Fly mode", "flyMode", { "Linear", "Smooth" })
slider(mainTab, "Fly speed", "flySpeed", 10, 500)
mainTab:Label("Camera")
slider(mainTab, "FOV offset", "fovOffset", 0, 40)
toggle(mainTab, "Third person", "thirdPerson", applyThirdPerson)
mainTab:Label("Performance")
toggle(mainTab, "FPS cap", "fpsEnabled")
slider(mainTab, "FPS cap value", "fpsCap", 30, 500)
fpsStatus = mainTab:Label("Status: restored to 240")

local espTab = window:Tab("ESP")
espTab:Label("Player ESP")
toggle(espTab, "Box", "espBox")
toggle(espTab, "Skeleton", "espSkeleton")
toggle(espTab, "Head dot", "espHeadDot")
toggle(espTab, "Name", "espName")
toggle(espTab, "Health bar", "espHealth")
toggle(espTab, "Distance", "espDistance")
toggle(espTab, "Tracers", "espTracer")
toggle(espTab, "Chams", "espChams")
espTab:Label("Settings")
toggle(espTab, "Team check", "teamCheck")
slider(espTab, "Max distance", "espMaxDist", 100, 5000)

local aimTab = window:Tab("Aim")
aimTab:Label("Aimbot")
toggle(aimTab, "Enabled", "aimEnabled")
bind(aimTab, "Lock key", "aim")
toggle(aimTab, "Hold mode (off = toggle)", "aimHold")
dropdown(aimTab, "Aim part", "aimPart", { "Head", "Torso", "Closest" })
dropdown(aimTab, "Aim method", "aimMethod", { "Camera", "Mouse" })
toggle(aimTab, "Show FOV circle", "aimShowFov")
slider(aimTab, "FOV size", "aimFov", 30, 600)
toggle(aimTab, "Smoothing", "aimSmoothOn")
slider(aimTab, "Smoothness", "aimSmooth", 1, 99)
slider(aimTab, "Prediction (ms)", "aimPrediction", 0, 200)
toggle(aimTab, "Wall check", "wallCheck")
aimTab:Label("Soft Aim")
toggle(aimTab, "Soft aim enabled", "silentEnabled")
toggle(aimTab, "Soft aim FOV circle", "silentShowFov")
slider(aimTab, "Soft aim FOV size", "silentFov", 30, 800)
slider(aimTab, "Hit chance", "silentHitChance", 1, 100)

local rageTab = window:Tab("Rage")
rageTab:Label("Rage Aimbot")
toggle(rageTab, "Enabled", "rageEnabled")
toggle(rageTab, "Auto shoot", "rageAutoShoot")
toggle(rageTab, "Ignore walls", "rageIgnoreWalls")
slider(rageTab, "Shoot delay (ms)", "rageDelay", 0, 500)
rageTab:Label("Triggerbot")
toggle(rageTab, "Trigger enabled", "triggerEnabled")
slider(rageTab, "Trigger delay (ms)", "triggerDelay", 0, 500)
rageTab:Label("Misc")
toggle(rageTab, "Spinbot", "spinEnabled")
slider(rageTab, "Spin speed", "spinSpeed", 1, 90)
rageTab:Label("Auto Knifer")
toggle(rageTab, "Knifer enabled", "knifeEnabled")
toggle(rageTab, "Auto equip knife", "knifeAutoEquip")
dropdown(rageTab, "Knife slot", "knifeSlot", { "1", "2", "3", "4" })
slider(rageTab, "Swing range", "knifeRange", 3, 30)
toggle(rageTab, "Teleport to target", "knifeTeleport")
slider(rageTab, "Teleport range", "knifeTpRange", 10, 300)
slider(rageTab, "Swing delay (ms)", "knifeDelay", 50, 1000)
toggle(rageTab, "Require backstab angle", "knifeBackstab")
slider(rageTab, "Backstab angle", "knifeBackAngle", 10, 180)
rageTab:Label("Auto Farm")
toggle(rageTab, "Farm enabled", "farmEnabled")
dropdown(rageTab, "Target mode", "farmMode", { "Nearest", "Lowest HP", "Random" })
dropdown(rageTab, "Kill method", "farmMethod", { "Knife", "Gun" })
slider(rageTab, "Distance behind", "farmDistance", 1, 15)
slider(rageTab, "Height offset", "farmHeight", -5, 15)

local interfaceTab = window:Tab("Interface")
interfaceTab:Label("Menu")
bind(interfaceTab, "Menu key", "menu")
interfaceTab:Button("Unload script", function() detach() end)

for _, player in ipairs(playersService:GetPlayers()) do
	if player ~= localPlayer then createEsp(player) end
end

table.insert(connections, playersService.PlayerAdded:Connect(createEsp))
table.insert(connections, playersService.PlayerRemoving:Connect(removeEsp))

-- Run after the camera so ESP and aim read the final camera frame.
runService:BindToRenderStep("SpriteRivals", Enum.RenderPriority.Camera.Value + 1, onRender)

table.insert(connections, userInputService.JumpRequest:Connect(function()
	if not Config.infJump then return end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return end
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	local velocity = root.AssemblyLinearVelocity
	local power = humanoid.JumpPower > 0 and humanoid.JumpPower or 50
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, power, velocity.Z)
end))

local function matchesBind(input, key)
	return input.KeyCode == key or input.UserInputType == key
end

table.insert(connections, userInputService.InputBegan:Connect(function(input, processed)
	heldKeys[input.KeyCode] = true

	if window.listening then return end

	if matchesBind(input, binds.menu) then
		window.gui.Enabled = not window.gui.Enabled
	end

	if processed then return end

	if matchesBind(input, binds.fly) then
		Config.flyEnabled = not Config.flyEnabled
		flyToggle:set(Config.flyEnabled)
	end

	if matchesBind(input, binds.aim) then
		Config.aimActive = Config.aimHold and true or not Config.aimActive
	end
end))

table.insert(connections, userInputService.InputEnded:Connect(function(input)
	heldKeys[input.KeyCode] = nil
	if Config.aimHold and matchesBind(input, binds.aim) then
		Config.aimActive = false
	end
end))

detach = function()
	runService:UnbindFromRenderStep("SpriteRivals")
	for _, connection in ipairs(connections) do connection:Disconnect() end
	for player in pairs(espObjects) do removeEsp(player) end
	aimCircle:Remove()
	silentCircle:Remove()
	window:destroy()
	silentPoint = nil
	Config.flyEnabled, Config.thirdPerson = false, false
	applyThirdPerson()
	setfpscap(240)
	shared.SpriteRivals = nil
end

shared.SpriteRivals = { detach = detach }
