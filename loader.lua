-- SkidV5 Loader
-- Minimal loader: shows a loading screen, pulls main.lua from the skidv5 repo,
-- refreshes the cached copy, then runs it. Every network/load step is wrapped
-- in pcall + retries so a bad response or crash shows a message on screen
-- instead of failing silently.

local cloneref = cloneref or function(obj)
	return obj
end

local RAW_BASE = 'https://raw.githubusercontent.com/skidforce/skidv5/refs/heads/main'
local MAIN_URL = RAW_BASE .. '/main.lua'

-- ignore duplicate executions within 3 minutes
if shared.SkidV5LoaderBoot and os.clock() - shared.SkidV5LoaderBoot < 180 then
	warn('[skidv5] loader is already running, ignoring duplicate execution')
	return
end
shared.SkidV5LoaderBoot = os.clock()

-- main.lua refuses to run without this (normally published by the key gate)
shared.SkidV5Authenticated = true

-- ------------------------------------------------------------ loading gui
local gui, status, fill
local animating = false

local function setStatus(text)
	if status then
		pcall(function() status.Text = tostring(text) end)
	else
		warn('[skidv5] '..tostring(text))
	end
end

local function hide()
	animating = false
	if gui then
		pcall(function() gui:Destroy() end)
		gui = nil
	end
end

local ok, hui = pcall(function() return gethui() end)
local root = ok and hui or cloneref(game:GetService('CoreGui'))

pcall(function()
	gui = Instance.new('ScreenGui')
	gui.Name = 'SkidV5Loader'
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = root

	local frame = Instance.new('Frame')
	frame.Size = UDim2.fromOffset(340, 140)
	frame.Position = UDim2.new(0.5, -170, 0.5, -70)
	frame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local frameCorner = Instance.new('UICorner')
	frameCorner.CornerRadius = UDim.new(0, 10)
	frameCorner.Parent = frame

	local accent = Instance.new('Frame')
	accent.Size = UDim2.new(1, -20, 0, 2)
	accent.Position = UDim2.fromOffset(10, 34)
	accent.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
	accent.BorderSizePixel = 0
	accent.Parent = frame
	local accentCorner = Instance.new('UICorner')
	accentCorner.CornerRadius = UDim.new(1, 0)
	accentCorner.Parent = accent

	local title = Instance.new('TextLabel')
	title.Size = UDim2.fromOffset(320, 30)
	title.Position = UDim2.fromOffset(10, 4)
	title.BackgroundTransparency = 1
	title.Text = 'SkidV5'
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.Font = Enum.Font.GothamBold
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	status = Instance.new('TextLabel')
	status.Size = UDim2.fromOffset(320, 40)
	status.Position = UDim2.fromOffset(10, 48)
	status.BackgroundTransparency = 1
	status.Text = 'Pulling stuff from skidv5...'
	status.TextColor3 = Color3.fromRGB(170, 170, 185)
	status.TextSize = 13
	status.Font = Enum.Font.Gotham
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.TextWrapped = true
	status.Parent = frame

	local bar = Instance.new('Frame')
	bar.Size = UDim2.fromOffset(320, 6)
	bar.Position = UDim2.fromOffset(10, 122)
	bar.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
	bar.BorderSizePixel = 0
	bar.Parent = frame
	local barCorner = Instance.new('UICorner')
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	fill = Instance.new('Frame')
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(0, 200, 120)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local fillCorner = Instance.new('UICorner')
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
end)

-- sweep the progress bar while the loader works
animating = true
task.spawn(function()
	while animating and gui do
		local t = (os.clock() % 1.6) / 1.6
		pcall(function() fill.Size = UDim2.fromScale(t, 1) end)
		task.wait(0.05)
	end
	pcall(function() fill.Size = UDim2.fromScale(1, 1) end)
end)

-- ---------------------------------------------------------- download util
local function fetch(url)
	for attempt = 1, 4 do
		local ok, res = pcall(game.HttpGet, game, url, true)
		if ok and type(res) == 'string' and res ~= '' and res ~= '404: Not Found' then
			-- never trust or cache a response that isn't valid Lua
			if url:find('%.lua$') and not loadstring(res) then
				setStatus('Bad response, retrying ('..attempt..'/4)...')
			else
				return res
			end
		else
			setStatus('Pulling stuff from skidv5... retry '..attempt..'/4')
		end
		task.wait(attempt)
	end
	return nil
end

-- ------------------------------------------------------------- load flow
local ran, err = pcall(function()
	setStatus('Pulling stuff from skidv5...')
	local src = fetch(MAIN_URL)
	if not src then
		error('failed to download main.lua after 4 attempts')
	end

	-- refresh the cached copy so the workspace always has the latest files
	setStatus('Updating files...')
	pcall(function()
		if writefile then
			writefile('skidv5/main.lua', src)
		end
	end)

	-- publish the build version where the settings pane reads it from
	pcall(function()
		local v = fetch(RAW_BASE .. '/version.txt')
		if v and type(v) == 'string' and v ~= '' and v ~= '404: Not Found' then
			if writefile then
				writefile('skidv5/profiles/version.txt', v:gsub('%s+$', ''))
			end
		end
	end)

	setStatus('Loading...')
	local fn, lerr = loadstring(src)
	if not fn then
		error('failed to compile main.lua: '..tostring(lerr))
	end
	fn()
end)

if not ran then
	setStatus('Something went wrong: '..tostring(err))
	task.wait(3)
	hide()
	return
end

-- hand off to the main GUI, then drop the loading screen
task.wait(1)
hide()
