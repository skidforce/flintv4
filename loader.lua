-- SkidV5 Loader
-- Entry point: publishes the auth flag main.lua requires, refreshes cached files when
-- version.txt changes, then runs main.lua. No key gate -- skidv5 authenticates by flag.
--
-- Optimisation notes:
--   * When the cached version matches the repo's version.txt, main.lua is NOT re-downloaded
--     (one HttpGet for version.txt instead of two for version + main). Updates land when
--     version.txt bumps, which make-version.ps1 does on every release.
--   * The progress bar is tweened, not polled -- no busy loop during downloads or boot.
--   * Every read/write/fetch is pcall'd so a missing filesystem or a bad response degrades
--     to "download it fresh" instead of erroring out of the loader.

local cloneref = cloneref or function(obj)
	return obj
end

local RAW_BASE = 'https://raw.githubusercontent.com/skidforce/skidv5/refs/heads/main'
local MAIN_URL = RAW_BASE .. '/main.lua'
local VERSION_URL = RAW_BASE .. '/version.txt'

local CACHE_MAIN = 'skidv5/main.lua'
local CACHE_VERSION = 'skidv5/profiles/version.txt'

-- ignore duplicate executions within 3 minutes
if shared.SkidV5LoaderBoot and os.clock() - shared.SkidV5LoaderBoot < 180 then
	warn('[skidv5] loader is already running, ignoring duplicate execution')
	return
end
shared.SkidV5LoaderBoot = os.clock()

-- main.lua refuses to run without this (normally published by the key gate)
shared.SkidV5Authenticated = true

-- ------------------------------------------------------------- cache helpers
local function readCached(path)
	local ok, res = pcall(readfile, path)
	if ok and type(res) == 'string' and res ~= '' then return res end
	return nil
end

local function writeCached(path, content)
	pcall(function()
		writefile(path, content)
	end)
end

-- --------------------------------------------------------------- fetch util
-- 4 attempts with a short backoff. Compile checks only apply to .lua responses: an outage
-- can hand back a 503/error page as the body, and caching that would poison the install.
local function fetch(url, compile)
	for attempt = 1, 4 do
		local ok, res = pcall(game.HttpGet, game, url, true)
		if ok and type(res) == 'string' and res ~= '' and res ~= '404: Not Found' then
			if compile and not loadstring(res) then
				statusSet('Bad response, retrying ('..attempt..'/4)...')
			else
				return res
			end
		end
		task.wait(attempt * 0.5)
	end
	return nil
end

-- ------------------------------------------------------------ loading gui
-- Clean panel: title, accent rule, status line, tweened progress bar with percentage,
-- and a version footer. Nothing here is polled -- the bar animates via TweenService.

local gui, panel, statusLabel, fillBar, fillPercent, versionLabel
local tweenService = cloneref(game:GetService('TweenService'))
local activeTween

local ok, hui = pcall(function() return gethui() end)
local root = ok and hui or cloneref(game:GetService('CoreGui'))

local function statusSet(text)
	if statusLabel then
		pcall(function() statusLabel.Text = tostring(text) end)
	else
		warn('[skidv5] '..tostring(text))
	end
end

local function setProgress(frac)
	if not fillBar then return end
	frac = math.clamp(frac, 0, 1)
	if activeTween then
		pcall(function() activeTween:Cancel() end)
	end
	activeTween = tweenService:Create(fillBar, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromScale(frac, 1)
	})
	activeTween:Play()
	pcall(function() fillPercent.Text = math.floor(frac * 100)..'%' end)
end

local function hide()
	if gui then
		pcall(function() gui:Destroy() end)
		gui, panel, statusLabel, fillBar, fillPercent, versionLabel = nil, nil, nil, nil, nil, nil
	end
end

pcall(function()
	gui = Instance.new('ScreenGui')
	gui.Name = 'SkidV5Loader'
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 999
	gui.Parent = root

	local uiscale = Instance.new('UIScale')
	uiscale.Parent = gui

	panel = Instance.new('Frame')
	panel.Size = UDim2.fromOffset(400, 170)
	panel.Position = UDim2.new(0.5, -200, 0.5, -85)
	panel.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
	panel.BorderSizePixel = 0
	panel.Parent = gui
	local panelCorner = Instance.new('UICorner')
	panelCorner.CornerRadius = UDim.new(0, 12)
	panelCorner.Parent = panel
	local panelStroke = Instance.new('UIStroke')
	panelStroke.Color = Color3.fromRGB(60, 60, 75)
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local title = Instance.new('TextLabel')
	title.Size = UDim2.fromOffset(360, 32)
	title.Position = UDim2.fromOffset(20, 14)
	title.BackgroundTransparency = 1
	title.Text = 'SkidV5'
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 22
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	local accent = Instance.new('Frame')
	accent.Size = UDim2.new(1, -40, 0, 2)
	accent.Position = UDim2.fromOffset(20, 52)
	accent.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
	accent.BorderSizePixel = 0
	accent.Parent = panel
	local accentCorner = Instance.new('UICorner')
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	statusLabel = Instance.new('TextLabel')
	statusLabel.Size = UDim2.fromOffset(360, 40)
	statusLabel.Position = UDim2.fromOffset(20, 62)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = 'Starting...'
	statusLabel.TextColor3 = Color3.fromRGB(175, 175, 190)
	statusLabel.TextSize = 13
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.TextWrapped = true
	statusLabel.Parent = panel

	local barTrack = Instance.new('Frame')
	barTrack.Size = UDim2.new(1, -40, 0, 6)
	barTrack.Position = UDim2.fromOffset(20, 118)
	barTrack.BackgroundColor3 = Color3.fromRGB(38, 38, 48)
	barTrack.BorderSizePixel = 0
	barTrack.Parent = panel
	local barTrackCorner = Instance.new('UICorner')
	barTrackCorner.CornerRadius = UDim.new(1, 0)
	barTrackCorner.Parent = barTrack

	fillBar = Instance.new('Frame')
	fillBar.Size = UDim2.fromScale(0, 1)
	fillBar.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
	fillBar.BorderSizePixel = 0
	fillBar.Parent = barTrack
	local fillBarCorner = Instance.new('UICorner')
	fillBarCorner.CornerRadius = UDim.new(1, 0)
	fillBarCorner.Parent = fillBar

	fillPercent = Instance.new('TextLabel')
	fillPercent.AnchorPoint = Vector2.new(1, 0)
	fillPercent.Size = UDim2.fromOffset(40, 16)
	fillPercent.Position = UDim2.new(1, -20, 1, 6)
	fillPercent.BackgroundTransparency = 1
	fillPercent.Text = '0%'
	fillPercent.TextColor3 = Color3.fromRGB(140, 140, 155)
	fillPercent.TextSize = 11
	fillPercent.Font = Enum.Font.GothamMedium
	fillPercent.TextXAlignment = Enum.TextXAlignment.Right
	fillPercent.Parent = panel

	versionLabel = Instance.new('TextLabel')
	versionLabel.Size = UDim2.fromOffset(360, 16)
	versionLabel.Position = UDim2.fromOffset(20, 142)
	versionLabel.BackgroundTransparency = 1
	versionLabel.Text = ''
	versionLabel.TextColor3 = Color3.fromRGB(100, 100, 115)
	versionLabel.TextSize = 11
	versionLabel.Font = Enum.Font.Gotham
	versionLabel.TextXAlignment = Enum.TextXAlignment.Left
	versionLabel.Parent = panel
end)

-- ------------------------------------------------------------- load flow
setProgress(0.02)

local ran, err = pcall(function()
	statusSet('Checking for updates...')
	setProgress(0.1)

	-- Version gate: only re-download main.lua when the repo's version.txt changed.
	local remoteVersion = fetch(VERSION_URL)
	local cachedVersion = readCached(CACHE_VERSION)
	local remoteTrim = remoteVersion and remoteVersion:gsub('%s+$', '') or nil
	local cachedTrim = cachedVersion and cachedVersion:gsub('%s+$', '') or nil

	if remoteTrim then
		versionLabel.Text = 'v'..remoteTrim
	else
		versionLabel.Text = cachedTrim and ('v'..cachedTrim) or ''
	end

	local source = nil
	if remoteTrim and remoteTrim == cachedTrim then
		source = readCached(CACHE_MAIN)
		if source then
			statusSet('Using cached build...')
			setProgress(0.4)
		end
	end

	if not source then
		statusSet('Downloading main.lua...')
		setProgress(0.25)
		source = fetch(MAIN_URL, true)
		if not source then
			error('failed to download main.lua after 4 attempts')
		end
		writeCached(CACHE_MAIN, source)
		if remoteTrim then
			writeCached(CACHE_VERSION, remoteTrim)
		end
		setProgress(0.7)
	end

	statusSet('Loading...')
	setProgress(0.85)
	local fn, lerr = loadstring(source)
	if not fn then
		error('failed to compile main.lua: '..tostring(lerr))
	end
	fn()
	setProgress(1)
end)

if not ran then
	statusSet('Something went wrong: '..tostring(err))
	task.wait(3)
	hide()
	return
end

-- hand off to the main GUI, then drop the loading screen
task.wait(1)
hide()