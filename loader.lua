local PUBLIC_BUILD = true

if PUBLIC_BUILD then
	shared.FlintV4Developer = nil
	pcall(function()
		if getmetatable(shared) ~= nil then return end
		setmetatable(shared, {
			__index = function(self, key)
				if key == 'FlintV4Developer' then return nil end
				return rawget(self, key)
			end,
			__newindex = function(self, key, value)
				if key == 'FlintV4Developer' then return end
				rawset(self, key, value)
			end
		})
	end)
end

local isDeveloper = (not PUBLIC_BUILD) and shared.FlintV4Developer and true or false

if shared.FlintV4LoaderBoot and os.clock() - shared.FlintV4LoaderBoot < 180 then
	warn('[flintv4] loader is already running, ignoring duplicate execution')
	return
end
shared.FlintV4LoaderBoot = os.clock()

local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(ref)
	return ref
end
local delfile = delfile or function(file)
	writefile(file, '')
end

local setclipboard = setclipboard or toclipboard or (Clipboard and Clipboard.set)

local Watermark = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.'
local HELP_URL = 'https://discord.gg/flintv4'

local function hasContent(path)
	if not isfile(path) then return false end
	local ok, body = pcall(readfile, path)
	return ok and type(body) == 'string' and body ~= ''
end

local function downloadFile(path, func)
	if not hasContent(path) then
		local relPath = select(1, path:gsub('flintv4/', ''))
		local content
		for attempt = 1, 4 do
			local suc, res = pcall(function()
				return game:HttpGet('https://raw.githubusercontent.com/skidforce/flintv4/main/'..relPath, true)
			end)
			if suc and res and res ~= '' and res ~= '404: Not Found' and (not path:find('.lua') or loadstring(res) ~= nil) then
				content = res
				break
			end
			if attempt < 4 then
				task.wait(attempt)
			end
		end
		if not content then
			error('failed to download '..path..' after 4 attempts')
		end
		if path:find('.lua') then
			content = Watermark..'\n'..content
		end
		writefile(path, content)
	end
	return (func or readfile)(path)
end

local function updateCachedFiles(onProgress)
	local httpService = cloneref(game:GetService('HttpService'))

	local headSuc, headSha = pcall(function()
		return httpService:JSONDecode(game:HttpGet('https://api.github.com/repos/skidforce/flintv4/commits?sha=main&per_page=1', true))[1].sha
	end)
	if not (headSuc and type(headSha) == 'string') then return end

	local treeSuc, tree = pcall(function()
		return httpService:JSONDecode(game:HttpGet('https://api.github.com/repos/skidforce/flintv4/git/trees/'..headSha..'?recursive=1', true))
	end)
	if not (treeSuc and type(tree) == 'table' and type(tree.tree) == 'table') then return end

	local manifest = {}
	pcall(function()
		if isfile('flintv4/filecheck.json') then
			local decoded = httpService:JSONDecode(readfile('flintv4/filecheck.json'))
			if type(decoded) == 'table' then
				manifest = decoded
			end
		end
	end)

	local remote = {}
	for _, v in tree.tree do
		if v.type == 'blob' and v.path:sub(-4) == '.lua' then
			remote[v.path] = v.sha
		end
	end

	local function managed(localPath)
		if not isfile(localPath) then return false end
		if PUBLIC_BUILD then return true end
		return readfile(localPath):sub(1, #Watermark) == Watermark
	end

	local toUpdate = {}
	for path, sha in remote do
		local localPath = 'flintv4/'..path
		if manifest[path] ~= sha and managed(localPath) then
			table.insert(toUpdate, path)
		end
	end

	local changed = false

	if not tree.truncated then
		for path in manifest do
			if not remote[path] then
				pcall(function()
					local localPath = 'flintv4/'..path
					if managed(localPath) then
						delfile(localPath)
					end
				end)
				manifest[path] = nil
				changed = true
			end
		end
	end

	local completed, pending, total = 0, #toUpdate, #toUpdate
	if total > 0 then
		local done = Instance.new('BindableEvent')
		for _, path in toUpdate do
			task.spawn(function()
				for attempt = 1, 4 do
					local suc, res = pcall(function()
						return game:HttpGet('https://raw.githubusercontent.com/skidforce/flintv4/'..headSha..'/'..select(1, path:gsub(' ', '%%20')), true)
					end)
					if suc and res and res ~= '' and res ~= '404: Not Found' and loadstring(res) ~= nil then
						pcall(writefile, 'flintv4/'..path, Watermark..'\n'..res)
						manifest[path] = remote[path]
						changed = true
						break
					end
					if attempt < 4 then
						task.wait(attempt)
					end
				end
				completed += 1
				pending -= 1
				if onProgress then
					onProgress(completed, total)
				end
				if pending <= 0 then
					done:Fire()
				end
			end)
		end
		if pending > 0 then
			done.Event:Wait()
		end
		done:Destroy()
	end

	if changed then
		pcall(writefile, 'flintv4/filecheck.json', httpService:JSONEncode(manifest))
	end
end

-- FlintV4 custom loader UI

local Palette = {
	Window = Color3.fromRGB(18, 18, 22),
	TitleBar = Color3.fromRGB(28, 28, 35),
	Border = Color3.fromRGB(50, 50, 60),
	Title = Color3.fromRGB(220, 220, 220),
	Accent = Color3.fromRGB(0, 170, 255),
	AccentDim = Color3.fromRGB(0, 120, 200),
	Line = Color3.fromRGB(180, 180, 180),
	Footer = Color3.fromRGB(100, 100, 110),
	ButtonIdle = Color3.fromRGB(190, 190, 190),
	ButtonBorder = Color3.fromRGB(55, 55, 65),
	Error = Color3.fromRGB(225, 75, 65),
	Ok = Color3.fromRGB(80, 200, 120),
	BarBg = Color3.fromRGB(30, 30, 38),
	BarFill = Color3.fromRGB(0, 170, 255)
}

local WindowWidth = 460
local TitleBarHeight = 38
local ContentPadding = 20
local BodyY = TitleBarHeight + ContentPadding
local StatusY = BodyY
local BarY = StatusY + 28
local LineY = BarY + 28
local AnswersY = LineY + 28
local WindowHeight = AnswersY + 40 + ContentPadding

local freshInstall = false
local function deleteInstall()
	shared.FlintV4LoaderBoot = nil
	if not freshInstall then return end
	pcall(function()
		if delfolder then
			delfolder('flintv4')
			return
		end
		local function purge(folder)
			for _, path in listfiles(folder) do
				if isfolder(path) then
					purge(path)
				elseif delfile then
					delfile(path)
				end
			end
		end
		purge('flintv4')
	end)
end

local function createConsole()
	local tweenService = cloneref(game:GetService('TweenService'))
	local inputService = cloneref(game:GetService('UserInputService'))
	local playersService = cloneref(game:GetService('Players'))

	pcall(function()
		if type(shared.FlintV4LoaderTeardown) == 'function' then
			shared.FlintV4LoaderTeardown()
		end
	end)

	local connections = {}
	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	local screen = Instance.new('ScreenGui')
	screen.Name = 'FlintV4Loader'
	screen.DisplayOrder = 999999999
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	local parented = pcall(function()
		screen.Parent = (gethui and gethui()) or cloneref(game:GetService('CoreGui'))
	end)
	if not parented then
		pcall(function()
			screen.Parent = playersService.LocalPlayer:FindFirstChildOfClass('PlayerGui')
		end)
	end

	local window = Instance.new('Frame')
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.fromOffset(WindowWidth, WindowHeight)
	window.BackgroundColor3 = Palette.Window
	window.BorderSizePixel = 0
	window.ClipsDescendants = true
	window.Parent = screen
	local windowCorner = Instance.new('UICorner')
	windowCorner.CornerRadius = UDim.new(0, 8)
	windowCorner.Parent = window
	local windowStroke = Instance.new('UIStroke')
	windowStroke.Color = Palette.Border
	windowStroke.Thickness = 1
	windowStroke.Parent = window

	local uiscale = Instance.new('UIScale')
	uiscale.Parent = window
	local camera = workspace.CurrentCamera

	local minimized, maximized = false, false
	local restorePosition = window.Position

	local function applyWindowState(animate)
		local viewport = camera and camera.ViewportSize or Vector2.new(WindowWidth, WindowHeight)
		local width = maximized and (viewport.X / uiscale.Scale) or WindowWidth
		local height = maximized and (viewport.Y / uiscale.Scale) or WindowHeight
		local size = UDim2.fromOffset(width, minimized and TitleBarHeight or height)
		local position = maximized and UDim2.fromScale(0.5, 0.5) or restorePosition
		if animate then
			tweenService:Create(window, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {Size = size, Position = position}):Play()
		else
			window.Size, window.Position = size, position
		end
	end

	local function applyScale()
		local viewport = camera and camera.ViewportSize or Vector2.new(WindowWidth, WindowHeight)
		if viewport.X <= 0 or viewport.Y <= 0 then return end
		local fit = math.min(viewport.X * 0.94 / WindowWidth, viewport.Y * 0.92 / WindowHeight)
		uiscale.Scale = math.clamp(math.min(fit, viewport.Y / 1080), 0.3, 1.4)
		applyWindowState(false)
	end
	applyScale()
	if camera then
		track(camera:GetPropertyChangedSignal('ViewportSize'):Connect(applyScale))
	end

	local titlebar = Instance.new('Frame')
	titlebar.Size = UDim2.new(1, 0, 0, TitleBarHeight)
	titlebar.BackgroundColor3 = Palette.TitleBar
	titlebar.BorderSizePixel = 0
	titlebar.Parent = window
	local titlebarCorner = Instance.new('UICorner')
	titlebarCorner.CornerRadius = UDim.new(0, 8)
	titlebarCorner.Parent = titlebar
	local titlebarFill = Instance.new('Frame')
	titlebarFill.Position = UDim2.new(0, 0, 1, -8)
	titlebarFill.Size = UDim2.new(1, 0, 0, 8)
	titlebarFill.BackgroundColor3 = Palette.TitleBar
	titlebarFill.BorderSizePixel = 0
	titlebarFill.Parent = titlebar

	local title = Instance.new('TextLabel')
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -130, 1, 0)
	title.Position = UDim2.fromOffset(14, 0)
	title.Text = 'FlintV4'
	title.TextColor3 = Palette.Accent
	title.TextSize = 16
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = titlebar

	local subtitle = Instance.new('TextLabel')
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(0, 60, 1, 0)
	subtitle.Position = UDim2.fromOffset(86, 0)
	subtitle.Text = 'loader'
	subtitle.TextColor3 = Palette.Footer
	subtitle.TextSize = 14
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.Parent = titlebar

	local closed, aborted = false, false
	local function destroy()
		if closed then return end
		closed = true
		for _, connection in connections do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(connections)
		pcall(function() screen:Destroy() end)
		if shared.FlintV4LoaderTeardown == destroy then
			shared.FlintV4LoaderTeardown = nil
		end
	end

	local function cancel()
		if aborted then return end
		aborted = true
		destroy()
		deleteInstall()
	end

	for index, kind in {'minimize', 'close'} do
		local button = Instance.new('TextButton')
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -12 - (2 - index) * 32, 0.5, 0)
		button.Size = UDim2.fromOffset(26, 26)
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Text = ''
		button.Parent = titlebar
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		local dot = Instance.new('Frame')
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BorderSizePixel = 0
		dot.Parent = button
		local dotCorner = Instance.new('UICorner')
		dotCorner.CornerRadius = UDim.new(0, kind == 'close' and 5 or 2)
		dotCorner.Parent = dot

		if kind == 'close' then
			dot.BackgroundColor3 = Palette.Error
		else
			dot.BackgroundColor3 = Palette.Accent
		end

		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0.85
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
		end)

		button.MouseButton1Click:Connect(function()
			if kind == 'close' then
				cancel()
			else
				minimized = not minimized
				applyWindowState(true)
			end
		end)
	end

	local dragging, dragStart, dragOrigin
	titlebar.InputBegan:Connect(function(input)
		if maximized then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, dragOrigin = true, input.Position, window.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	track(inputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = input.Position - dragStart
			window.Position = UDim2.new(dragOrigin.X.Scale, dragOrigin.X.Offset + delta.X, dragOrigin.Y.Scale, dragOrigin.Y.Offset + delta.Y)
			restorePosition = window.Position
		end
	end))

	track(inputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.C and inputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			cancel()
		end
	end))

	local status = Instance.new('TextLabel')
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(ContentPadding, StatusY)
	status.Size = UDim2.new(1, -ContentPadding * 2, 0, 24)
	status.TextColor3 = Palette.Accent
	status.TextSize = 15
	status.Font = Enum.Font.GothamBold
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Parent = window

	local barBg = Instance.new('Frame')
	barBg.Position = UDim2.fromOffset(ContentPadding, BarY)
	barBg.Size = UDim2.new(1, -ContentPadding * 2, 0, 6)
	barBg.BackgroundColor3 = Palette.BarBg
	barBg.BorderSizePixel = 0
	barBg.Parent = window
	local barBgCorner = Instance.new('UICorner')
	barBgCorner.CornerRadius = UDim.new(0, 3)
	barBgCorner.Parent = barBg

	local barFill = Instance.new('Frame')
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = Palette.BarFill
	barFill.BorderSizePixel = 0
	barFill.Parent = barBg
	local barFillCorner = Instance.new('UICorner')
	barFillCorner.CornerRadius = UDim.new(0, 3)
	barFillCorner.Parent = barFill

	local line = Instance.new('TextLabel')
	line.BackgroundTransparency = 1
	line.Position = UDim2.fromOffset(ContentPadding, LineY)
	line.Size = UDim2.new(1, -ContentPadding * 2, 0, 24)
	line.Text = ''
	line.TextColor3 = Palette.Line
	line.TextSize = 13
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Font = Enum.Font.Gotham
	line.Parent = window

	local answers = Instance.new('Frame')
	answers.BackgroundTransparency = 1
	answers.Position = UDim2.fromOffset(ContentPadding, AnswersY)
	answers.Size = UDim2.new(1, -ContentPadding * 2, 0, 34)
	answers.Visible = false
	answers.Parent = window
	local answersLayout = Instance.new('UIListLayout')
	answersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	answersLayout.FillDirection = Enum.FillDirection.Horizontal
	answersLayout.Padding = UDim.new(0, 10)
	answersLayout.Parent = answers

	local footer = Instance.new('TextLabel')
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.BackgroundTransparency = 1
	footer.Position = UDim2.new(0, ContentPadding, 1, -10)
	footer.Size = UDim2.new(1, -ContentPadding * 2, 0, 18)
	footer.Text = (inputService.TouchEnabled and not inputService.KeyboardEnabled) and 'Tap [x] to exit' or 'Press [CTRL+C] to exit'
	footer.TextColor3 = Palette.Footer
	footer.TextSize = 12
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Font = Enum.Font.Gotham
	footer.Parent = window

	local function answerButton(text, width, order)
		local button = Instance.new('TextButton')
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(width, 34)
		button.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Modal = true
		button.Text = text
		button.TextColor3 = Palette.ButtonIdle
		button.TextSize = 14
		button.Font = Enum.Font.GothamBold
		button.Parent = answers
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		local stroke = Instance.new('UIStroke')
		stroke.Color = Palette.ButtonBorder
		stroke.Thickness = 1
		stroke.Parent = button
		button.MouseEnter:Connect(function()
			stroke.Color = Palette.Accent
			button.TextColor3 = Palette.Accent
		end)
		button.MouseLeave:Connect(function()
			stroke.Color = Palette.ButtonBorder
			button.TextColor3 = Palette.ButtonIdle
		end)
		return button
	end

	local function clearAnswers()
		for _, child in answers:GetChildren() do
			if child:IsA('TextButton') or child:IsA('TextBox') then
				child:Destroy()
			end
		end
	end

	local console = {}

	function console:SetStatus(text, color)
		status.Text = text
		status.TextColor3 = color or Palette.Accent
	end

	function console:SetLine(text, color)
		line.Text = text
		line.TextColor3 = color or Palette.Line
	end

	function console:SetProgress(alpha)
		local target = math.clamp(alpha, 0, 1)
		tweenService:Create(barFill, TweenInfo.new(0.3, Enum.EasingStyle.Quad), {Size = UDim2.fromScale(target, 1)}):Play()
	end

	function console:IsAborted()
		return aborted
	end

	function console:Ask(question, buttons, timeoutSeconds, fallback)
		if closed then return fallback end
		self:SetLine(question)
		clearAnswers()

		local choice
		for index, def in buttons do
			local button = answerButton(def.text, 132, index)
			button.MouseButton1Click:Connect(function()
				choice = def.key
			end)
		end
		answers.Visible = true

		local timeout = os.clock() + (timeoutSeconds or 60)
		repeat task.wait() until choice ~= nil or closed or os.clock() > timeout
		answers.Visible = false
		clearAnswers()
		self:SetLine('')
		if choice == nil then
			return fallback
		end
		return choice
	end

	function console:Finish(message, seconds)
		if closed then return end
		self:SetProgress(1)
		self:SetStatus('DONE', Palette.Ok)
		seconds = seconds or 5
		local deadline = os.clock() + seconds
		task.spawn(function()
			while not closed do
				local left = math.max(0, math.ceil(deadline - os.clock()))
				self:SetLine(message..' Closing in '..left..'s.')
				if left <= 0 then break end
				task.wait(0.2)
			end
			destroy()
		end)
	end

	function console:Halt() end

	function console:Fail(err)
		if closed then return end
		self:SetStatus('FAILED', Palette.Error)
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.Size = UDim2.new(1, -ContentPadding * 2, 0, AnswersY + 34 - LineY)
		self:SetLine(err, Palette.Error)
		self:SetProgress(0)
	end

	shared.FlintV4LoaderTeardown = destroy
	return console
end

local function createHeadlessConsole()
	local console = {}
	function console:SetStatus() end
	function console:SetLine() end
	function console:SetProgress() end
	function console:Finish() end
	function console:Fail() end
	function console:Halt() end
	function console:IsAborted() return false end
	function console:Ask(question, buttons, timeoutSeconds, fallback)
		return fallback
	end
	return console
end

local isReload = shared.vapereload and true or false
local console = isReload and createHeadlessConsole() or createConsole()
console:SetStatus('LOADING')
console:SetProgress(0.08)

do
	local unsupported = {'xeno', 'solara'}
	local executorName = ''
	pcall(function()
		executorName = identifyexecutor and identifyexecutor() or ''
	end)
	local lowered = tostring(executorName):lower()
	for _, name in unsupported do
		if lowered:find(name, 1, true) then
			local message = 'Unsupported executor ('..tostring(executorName)..'), please look in the #supported-executors channel for more info.'
			console:SetStatus('ERROR', Palette.Error)
			console:SetLine(message, Palette.Error)
			warn('[flintv4] '..message)
			console:Halt()
			shared.FlintV4LoaderBoot = nil
			return
		end
	end
end

console:SetStatus('INJECTING')
console:SetLine('Injecting into ROBLOX...')
console:SetProgress(0.12)

freshInstall = not isfolder('flintv4')
for _, folder in {'flintv4', 'flintv4/games', 'flintv4/profiles', 'flintv4/assets', 'flintv4/libraries', 'flintv4/guis'} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

do
	local playersService = cloneref(game:GetService('Players'))
	local deadline = os.clock() + 120
	repeat task.wait() until game:IsLoaded() or console:IsAborted() or os.clock() > deadline
	console:SetProgress(0.24)
	repeat task.wait() until playersService.LocalPlayer or console:IsAborted() or os.clock() > deadline
	if shared.vape then
		task.wait(0.25)
	end
	console:SetProgress(0.4)
end
if console:IsAborted() then deleteInstall() return end

if not isReload and not isDeveloper then
	console:SetLine('Checking for updates...')
	pcall(updateCachedFiles, function(completed, total)
		console:SetLine('Updating files ('..completed..'/'..total..')...')
		console:SetProgress(0.4 + 0.06 * (completed / math.max(total, 1)))
	end)
	console:SetLine('')
	if console:IsAborted() then deleteInstall() return end
end
console:SetProgress(0.46)
console:SetLine('Loading flintv4...')
local injecting = true
task.spawn(function()
	local alpha = 0.5
	while injecting and alpha < 0.93 do
		task.wait(0.6)
		if not injecting then break end
		alpha += 0.02
		console:SetProgress(alpha)
	end
end)

local ok, result = pcall(function()
	return loadstring(downloadFile('flintv4/main.lua'), 'main')()
end)
injecting = false
shared.vapereload = nil
shared.FlintV4LoaderBoot = nil

if console:IsAborted() then
	if shared.vape then
		pcall(function() shared.vape:Uninject() end)
	end
	deleteInstall()
	return
end

if ok then
	console:Finish('Injected successfully.', 5)
	return result
end
warn('[flintv4] '..tostring(result))
local failure = 'Injection failed: '..tostring(result)
local copied = pcall(function() setclipboard(failure) end)
console:Fail(failure..(copied and '\n\n(copied to clipboard)' or ''))
