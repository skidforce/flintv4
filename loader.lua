-- SkidV5 Loader
-- Entry point: publishes the auth flag main.lua requires, keeps every cached file fresh
-- against the GitHub repo, then runs main.lua. No key gate -- skidv5 authenticates by flag.
--
-- Boot flow, adapted from the pistonware loader:
--   * a fake terminal console opens with the boot status and stays up through injection
--   * cached .lua files are refreshed against the repo tree via the filecheck.json
--     manifest (blob SHAs) -- only files already cached get refreshed, everything else
--     keeps downloading on demand
--   * a fresh install offers the shipped configs, an existing install offers a sync
--   * version.txt is re-fetched every boot so the GUI watermark stays in step with the
--     make-version.ps1 bump that ships with each update
--   * reinjects (shared.vapereload) run the same boot with a headless console

local PUBLIC_BUILD = true

local isDeveloper = shared.SkidV5Developer and true or false

-- ignore duplicate executions within 3 minutes
if shared.SkidV5LoaderBoot and os.clock() - shared.SkidV5LoaderBoot < 180 then
	warn('[skidv5] loader is already running, ignoring duplicate execution')
	return
end
shared.SkidV5LoaderBoot = os.clock()

-- main.lua refuses to run without this (normally published by a key gate)
shared.SkidV5Authenticated = true

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

-- ========================================================================

-- Empty counts as missing. The executor's real isfile reports a zero-byte file as present, so a
-- write interrupted by a cancel, a crash or a teleport leaves a truncated file that this
-- function would otherwise never fetch again. For a .lua file that means a chunk that silently
-- does nothing; for an asset it means getcustomasset producing an invalid content id, which
-- throws 'ContentId formatting failed' and kills the GUI. Both states used to survive every
-- retry, because everything that could have repaired them asked isfile and was told the file
-- was fine -- so the only remedy was reinstalling the script.
local function hasContent(path)
	if not isfile(path) then return false end
	local ok, body = pcall(readfile, path)
	return ok and type(body) == 'string' and body ~= ''
end

local function downloadFile(path, func)
	if not hasContent(path) then
		local relPath = select(1, path:gsub('skidv5/', ''))
		local content
		for attempt = 1, 4 do
			local suc, res = pcall(function()
				return game:HttpGet('https://raw.githubusercontent.com/skidforce/skidv5/main/'..relPath, true)
			end)
			-- For .lua files, a compile check too: an outage can hand back the 503/error page
			-- as the body, and caching that would poison the install silently (cache-first
			-- means it would never be refetched).
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

local function fetchProfilesListing(ref)
	local reqSuc, res = pcall(function()
		return game:HttpGet('https://api.github.com/repos/skidforce/skidv5/contents/profiles'..(ref and ('?ref='..ref) or ''), true)
	end)
	if not (reqSuc and res and res ~= '404: Not Found') then return nil end
	local bodySuc, body = pcall(function()
		return cloneref(game:GetService('HttpService')):JSONDecode(res)
	end)
	if not (bodySuc and body and typeof(body) == 'table') then return nil end
	return body
end

local function mergeGuiState(path, incoming)
	if not path:find('%.gui%.txt$') then return incoming end
	local ok, merged = pcall(function()
		local httpService = cloneref(game:GetService('HttpService'))
		local new = httpService:JSONDecode(incoming)
		if type(new) ~= 'table' then return incoming end
		if isfile(path) then
			local old = httpService:JSONDecode(readfile(path))
			if type(old) == 'table' then
				if old.Profiles ~= nil then new.Profiles = old.Profiles end
				if old.Profile ~= nil then new.Profile = old.Profile end
			end
		end
		return httpService:JSONEncode(new)
	end)
	return (ok and type(merged) == 'string') and merged or incoming
end

local function downloadProfilesListing(body, commit, onProgress)
	local files = {}
	for _, v in body do
		if v.type == 'file' then
			table.insert(files, v)
		end
	end
	local completed, pending, total = 0, #files, #files
	local done = Instance.new('BindableEvent')
	for _, v in files do
		local relPath = ({v.path:gsub(' ', '%%20')})[1]
		task.spawn(function()
			if commit then
				pcall(function()
					for attempt = 1, 4 do
						local suc, res = pcall(function()
							return game:HttpGet('https://raw.githubusercontent.com/skidforce/skidv5/'..commit..'/'..relPath, true)
						end)
						if suc and res and res ~= '' and res ~= '404: Not Found' then
							writefile('skidv5/'..relPath, mergeGuiState('skidv5/'..relPath, res))
							break
						end
						if attempt < 4 then
							task.wait(attempt)
						end
					end
				end)
			else
				pcall(downloadFile, 'skidv5/'..relPath)
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

local function fetchProfilesCommit()
	local reqSuc, res = pcall(function()
		return game:HttpGet('https://api.github.com/repos/skidforce/skidv5/commits?path=profiles&sha=main&per_page=1', true)
	end)
	if not (reqSuc and res and res ~= '404: Not Found') then return nil end
	local bodySuc, body = pcall(function()
		return cloneref(game:GetService('HttpService')):JSONDecode(res)
	end)
	if not (bodySuc and body and typeof(body) == 'table' and body[1] and body[1].sha) then return nil end
	return body[1].sha
end

local function updateCachedFiles(onProgress)
	local httpService = cloneref(game:GetService('HttpService'))

	local headSuc, headSha = pcall(function()
		return httpService:JSONDecode(game:HttpGet('https://api.github.com/repos/skidforce/skidv5/commits?sha=main&per_page=1', true))[1].sha
	end)
	if not (headSuc and type(headSha) == 'string') then return end

	local treeSuc, tree = pcall(function()
		return httpService:JSONDecode(game:HttpGet('https://api.github.com/repos/skidforce/skidv5/git/trees/'..headSha..'?recursive=1', true))
	end)
	if not (treeSuc and type(tree) == 'table' and type(tree.tree) == 'table') then return end

	local manifest = {}
	pcall(function()
		if isfile('skidv5/filecheck.json') then
			local decoded = httpService:JSONDecode(readfile('skidv5/filecheck.json'))
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

	-- Only files already cached get refreshed here -- everything else keeps downloading on
	-- demand, and is picked up by this pass on the session after it first appears.
	local toUpdate = {}
	for path, sha in remote do
		local localPath = 'skidv5/'..path
		if manifest[path] ~= sha and managed(localPath) then
			table.insert(toUpdate, path)
		end
	end

	local changed = false

	if not tree.truncated then
		for path in manifest do
			if not remote[path] then
				pcall(function()
					local localPath = 'skidv5/'..path
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
						return game:HttpGet('https://raw.githubusercontent.com/skidforce/skidv5/'..headSha..'/'..select(1, path:gsub(' ', '%%20')), true)
					end)
					-- compile check: never overwrite a working cached file with an error page
					if suc and res and res ~= '' and res ~= '404: Not Found' and loadstring(res) ~= nil then
						pcall(writefile, 'skidv5/'..path, Watermark..'\n'..res)
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
		pcall(writefile, 'skidv5/filecheck.json', httpService:JSONEncode(manifest))
	end
end

--[[
	Loader console
	--------------
	A fake terminal window that stands in for the executor console while skidv5 boots.
	The SKIDV5 logo is drawn one row at a time as the boot progresses, so the art is only
	ever complete at the same moment the status flips to '> DONE'.
]]

local SkidLogo = {
	'====:::====:::====:::====:::====',
	'SSSSS S   S IIIII DDD   V   V 55555',
	'S     S  S    I   D   D V   V 5    ',
	'S     S S     I   D   D V   V 5    ',
	' SSS  SS      I   D   D V   V 55555',
	'    S S S     I   D   D  V V     5',
	'    S S  S    I   D   D  V V     5',
	'SSSSS S   S IIIII DDD     V   55555',
	'====:::====:::====:::====:::===='
}

-- Every offset below is authored against the base window and scaled as a whole by the
-- UIScale, so the layout can't drift apart on other resolutions.
local WindowWidth = 900
local TitleBarHeight = 44
local ContentPadding = 26
-- Rows are packed slightly tighter than the glyph size so the 9-row logo stays a sane
-- height. Text is never clipped by its own frame in Roblox, so the 2px per row overlaps
-- harmlessly.
local AsciiTextSize = 20
local AsciiLineHeight = 18

-- The rows under the art are positioned off the art itself, so a taller or shorter logo
-- pushes them (and the bottom of the window) down instead of colliding with them.
local AsciiTop = TitleBarHeight + 16
local StatusY = AsciiTop + #SkidLogo * AsciiLineHeight + 16
local LineY = StatusY + 32
local AnswersY = LineY + 30
local WindowHeight = AnswersY + 34 + 30 + 22 + 16

local Palette = {
	Window = Color3.fromRGB(12, 12, 14),
	TitleBar = Color3.fromRGB(30, 30, 36),
	Border = Color3.fromRGB(56, 56, 66),
	Title = Color3.fromRGB(232, 232, 232),
	Glyph = Color3.fromRGB(176, 176, 188),
	Accent = Color3.fromRGB(0, 205, 125),
	Line = Color3.fromRGB(238, 238, 238),
	Footer = Color3.fromRGB(108, 108, 120),
	ButtonIdle = Color3.fromRGB(200, 200, 200),
	ButtonBorder = Color3.fromRGB(62, 62, 62),
	Error = Color3.fromRGB(225, 80, 70),
	Ok = Color3.fromRGB(120, 225, 150)
}

-- Ascii shading: the logo letters stay white while the terminal frame rows read as dimmer
-- dither, so the wordmark pops against the window instead of drowning in it.
local AsciiShades = {
	['='] = '#6B6B6B',
	[':'] = '#4A4A4A'
}

-- Cancelling the loader has to leave nothing behind that THIS boot created, so on a fresh
-- install the whole folder is wiped. On an install that already existed before this run the
-- wipe is skipped entirely -- the folder holds the user's custom profiles, and cancelling a
-- reinject must never cost them those; only an explicit reinstall (reinstall.lua) deletes an
-- existing install. delfolder already recurses on the executors that have it; the manual walk
-- is for the ones that only ship delfile.
local freshInstall = false
local function deleteInstall()
	-- every cancel/abort path comes through here, so a cancelled boot immediately frees the
	-- duplicate-execution guard for the next manual run
	shared.SkidV5LoaderBoot = nil
	if not freshInstall then return end
	pcall(function()
		if delfolder then
			delfolder('skidv5')
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
		purge('skidv5')
	end)
end

local function asciiRichText(line)
	local out = {}
	local runColor, runStart = nil, 1
	local function flush(stop)
		if stop < runStart then return end
		local chunk = line:sub(runStart, stop)
		table.insert(out, runColor and ('<font color="'..runColor..'">'..chunk..'</font>') or chunk)
	end
	for i = 1, #line do
		local color = AsciiShades[line:sub(i, i)]
		if i > 1 and color ~= runColor then
			flush(i - 1)
			runStart = i
		end
		runColor = color
	end
	flush(#line)
	return table.concat(out)
end

local function createConsole()
	local tweenService = cloneref(game:GetService('TweenService'))
	local inputService = cloneref(game:GetService('UserInputService'))
	local playersService = cloneref(game:GetService('Players'))

	-- Whatever a previous run left standing goes first. Several paths through this file
	-- return without destroying the console -- Fail() leaves the window up on purpose so the
	-- message can be read -- and each one leaves behind a GUI tree, three service-level
	-- connections and the reveal thread below. Re-executing is the natural response to all of
	-- them, so without this the leak grows once per attempt rather than being replaced.
	pcall(function()
		if type(shared.SkidV5LoaderTeardown) == 'function' then
			shared.SkidV5LoaderTeardown()
		end
	end)

	-- Connections on services and the camera, which outlive screen:Destroy() -- unlike the
	-- button and titlebar ones, which are parented into the GUI and go with it.
	local connections = {}
	local function track(connection)
		table.insert(connections, connection)
		return connection
	end

	local screen = Instance.new('ScreenGui')
	screen.Name = 'SkidV5Loader'
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
	-- so minimising can roll the console up behind its own titlebar
	window.ClipsDescendants = true
	window.Parent = screen
	local windowCorner = Instance.new('UICorner')
	windowCorner.CornerRadius = UDim.new(0, 10)
	windowCorner.Parent = window
	local windowStroke = Instance.new('UIStroke')
	windowStroke.Color = Palette.Border
	windowStroke.Thickness = 1
	windowStroke.Parent = window

	-- One UIScale drives the whole window, so the console keeps its proportions from a phone up
	-- to a 4K monitor: full size at 1080p, shrunk to fit anything smaller.
	local uiscale = Instance.new('UIScale')
	uiscale.Parent = window
	local camera = workspace.CurrentCamera

	-- Window state, the way a desktop WM handles it: minimise rolls the window up into its own
	-- titlebar (there is no taskbar to minimise *to* here, so shading is the recoverable
	-- equivalent) and maximise fills the viewport, both toggling back on a second click.
	local minimized, maximized = false, false
	local restorePosition = window.Position

	local function applyWindowState(animate)
		local viewport = camera and camera.ViewportSize or Vector2.new(WindowWidth, WindowHeight)
		-- Sizes are pre-UIScale, so divide by the scale to land on the viewport once scaled.
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
		uiscale.Scale = math.clamp(math.min(fit, viewport.Y / 1080), 0.25, 1.4)
		-- a maximised window has to keep tracking the viewport it is filling
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
	titlebarCorner.CornerRadius = UDim.new(0, 10)
	titlebarCorner.Parent = titlebar
	-- Squares off the bottom two corners the UICorner above rounded.
	local titlebarFill = Instance.new('Frame')
	titlebarFill.Position = UDim2.new(0, 0, 1, -10)
	titlebarFill.Size = UDim2.new(1, 0, 0, 10)
	titlebarFill.BackgroundColor3 = Palette.TitleBar
	titlebarFill.BorderSizePixel = 0
	titlebarFill.Parent = titlebar

	local icon = Instance.new('TextLabel')
	icon.Position = UDim2.fromOffset(10, 10)
	icon.Size = UDim2.fromOffset(24, 24)
	icon.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	icon.BorderSizePixel = 0
	icon.Text = '>_'
	icon.TextColor3 = Palette.Accent
	icon.TextSize = 13
	icon.Font = Enum.Font.Code
	icon.Parent = titlebar
	local iconCorner = Instance.new('UICorner')
	iconCorner.CornerRadius = UDim.new(0, 5)
	iconCorner.Parent = icon

	local title = Instance.new('TextLabel')
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, -220, 1, 0)
	title.Position = UDim2.fromOffset(110, 0)
	title.Text = './skidv5-loader'
	title.TextColor3 = Palette.Title
	title.TextSize = 18
	title.Font = Enum.Font.Code
	title.Parent = titlebar

	local closed, aborted = false, false
	local function destroy()
		if closed then return end
		-- Set first: the reveal thread and every wait loop below key off it, so they stop
		-- even if destroying the GUI throws.
		closed = true
		for _, connection in connections do
			pcall(function() connection:Disconnect() end)
		end
		table.clear(connections)
		pcall(function() screen:Destroy() end)
		-- Only clear the handle if it is still ours; a newer console may already own it.
		if shared.SkidV5LoaderTeardown == destroy then
			shared.SkidV5LoaderTeardown = nil
		end
	end

	-- Closing the window by hand is a cancel, not a dismissal: the boot stops at the next
	-- checkpoint, and on a first install everything the run wrote is deleted so a half-finished
	-- install can't be left behind (and no config gets silently picked for you). On an existing
	-- install deleteInstall refuses to wipe, so cancelling a reinject just stops the boot.
	local function cancel()
		if aborted then return end
		aborted = true
		destroy()
		deleteInstall()
	end

	-- Chrome glyphs are drawn from thin rotated bars rather than typed: Roblox's Code font has
	-- no chevron glyphs, and a literal 'v'/'^' reads as text sitting next to the title instead
	-- of as window controls.
	local function drawGlyph(parent, kind)
		local bars = {}
		local function bar(length, x, y, rotation)
			local piece = Instance.new('Frame')
			piece.AnchorPoint = Vector2.new(0.5, 0.5)
			piece.Position = UDim2.fromOffset(x, y)
			piece.Size = UDim2.fromOffset(length, 2)
			piece.BackgroundColor3 = Palette.Glyph
			piece.BorderSizePixel = 0
			piece.Rotation = rotation
			piece.Parent = parent
			local corner = Instance.new('UICorner')
			corner.CornerRadius = UDim.new(0, 1)
			corner.Parent = piece
			table.insert(bars, piece)
		end
		-- Arms meet at the centre of the 34x34 button: a chevron is two 10px bars at +-45
		-- degrees, the close is the same two bars crossed.
		if kind == 'minimize' then
			bar(10, 13.5, 17, 45)
			bar(10, 20.5, 17, -45)
		elseif kind == 'maximize' then
			bar(10, 13.5, 17, -45)
			bar(10, 20.5, 17, 45)
		else
			bar(15, 17, 17, 45)
			bar(15, 17, 17, -45)
		end
		return bars
	end

	for index, kind in {'minimize', 'maximize', 'close'} do
		local button = Instance.new('TextButton')
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -14 - (3 - index) * 38, 0.5, 0)
		button.Size = UDim2.fromOffset(34, 34)
		button.BackgroundColor3 = Color3.new(1, 1, 1)
		button.BackgroundTransparency = 1
		button.AutoButtonColor = false
		button.Modal = true
		button.Text = ''
		button.Parent = titlebar
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button

		local bars = drawGlyph(button, kind)
		button.MouseEnter:Connect(function()
			button.BackgroundTransparency = 0.9
			for _, piece in bars do
				piece.BackgroundColor3 = kind == 'close' and Palette.Error or Color3.new(1, 1, 1)
			end
		end)
		button.MouseLeave:Connect(function()
			button.BackgroundTransparency = 1
			for _, piece in bars do
				piece.BackgroundColor3 = Palette.Glyph
			end
		end)

		button.MouseButton1Click:Connect(function()
			if kind == 'close' then
				cancel()
			elseif kind == 'minimize' then
				minimized = not minimized
				applyWindowState(true)
			else
				-- maximising an already rolled-up window unrolls it, as a WM would
				maximized = not maximized
				minimized = false
				applyWindowState(true)
			end
		end)
	end

	-- Drag by the titlebar. Offsets live in screen space (the UIScale only rescales children),
	-- so the delta can be applied straight to the window position.
	local dragging, dragStart, dragOrigin
	titlebar.InputBegan:Connect(function(input)
		-- a maximised window is pinned to the viewport; unmaximise it to move it
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
			-- so unmaximising and unminimising both come back to where it was left
			restorePosition = window.Position
		end
	end))

	local ascii = Instance.new('Frame')
	ascii.BackgroundTransparency = 1
	ascii.Position = UDim2.fromOffset(ContentPadding, AsciiTop)
	ascii.Size = UDim2.fromOffset(WindowWidth - ContentPadding * 2, #SkidLogo * AsciiLineHeight)
	ascii.Parent = window

	local rows = {}
	for index, line in SkidLogo do
		local label = Instance.new('TextLabel')
		label.BackgroundTransparency = 1
		label.Position = UDim2.fromOffset(0, (index - 1) * AsciiLineHeight)
		label.Size = UDim2.new(1, 0, 0, AsciiLineHeight)
		label.RichText = true
		label.Text = asciiRichText(line)
		label.TextColor3 = Color3.new(1, 1, 1)
		label.TextSize = AsciiTextSize
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextTransparency = 1
		label.Font = Enum.Font.Code
		label.Visible = false
		label.Parent = ascii
		rows[index] = label
	end

	local status = Instance.new('TextLabel')
	status.BackgroundTransparency = 1
	status.Position = UDim2.fromOffset(ContentPadding, StatusY)
	status.Size = UDim2.new(1, -ContentPadding * 2, 0, 28)
	status.RichText = true
	status.TextColor3 = Palette.Line
	status.TextSize = 22
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Font = Enum.Font.Code
	status.Parent = window

	local line = Instance.new('TextLabel')
	line.BackgroundTransparency = 1
	line.Position = UDim2.fromOffset(ContentPadding, LineY)
	line.Size = UDim2.new(1, -ContentPadding * 2, 0, 24)
	line.Text = ''
	line.TextColor3 = Palette.Line
	line.TextSize = 17
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.Font = Enum.Font.Code
	line.Parent = window

	-- Answer buttons sit on the row directly under the question and are reused for every
	-- prompt, so answering one question simply rewrites the line above them.
	local answers = Instance.new('Frame')
	answers.BackgroundTransparency = 1
	answers.Position = UDim2.fromOffset(ContentPadding, AnswersY)
	answers.Size = UDim2.new(1, -ContentPadding * 2, 0, 34)
	answers.Visible = false
	answers.Parent = window
	local answersLayout = Instance.new('UIListLayout')
	answersLayout.SortOrder = Enum.SortOrder.LayoutOrder
	answersLayout.FillDirection = Enum.FillDirection.Horizontal
	answersLayout.Padding = UDim.new(0, 12)
	answersLayout.Parent = answers

	-- Explains what the hovered answer actually does. It rides in the same list layout as the
	-- buttons (LayoutOrder puts it last, after however many there are) so it lands on their row
	-- with the same gap between, and a hidden child takes no space -- the row closes up around
	-- it while nothing is hovered. Ask() only clears TextButtons, so this survives each question.
	local tooltip = Instance.new('TextLabel')
	tooltip.Name = 'Tooltip'
	tooltip.LayoutOrder = 999
	tooltip.AutomaticSize = Enum.AutomaticSize.X
	tooltip.Size = UDim2.fromOffset(0, 34)
	tooltip.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.Text = ''
	tooltip.TextColor3 = Palette.Line
	tooltip.TextSize = 15
	tooltip.Font = Enum.Font.Code
	tooltip.Parent = answers
	local tooltipPadding = Instance.new('UIPadding')
	tooltipPadding.PaddingLeft = UDim.new(0, 12)
	tooltipPadding.PaddingRight = UDim.new(0, 12)
	tooltipPadding.Parent = tooltip
	local tooltipCorner = Instance.new('UICorner')
	tooltipCorner.CornerRadius = UDim.new(0, 4)
	tooltipCorner.Parent = tooltip
	local tooltipStroke = Instance.new('UIStroke')
	tooltipStroke.Color = Palette.ButtonBorder
	tooltipStroke.Thickness = 1
	tooltipStroke.Parent = tooltip

	local footer = Instance.new('TextLabel')
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.BackgroundTransparency = 1
	footer.Position = UDim2.new(0, ContentPadding, 1, -16)
	footer.Size = UDim2.new(1, -ContentPadding * 2, 0, 22)
	-- Touch-only devices have no ctrl key, so point them at the titlebar button instead.
	footer.Text = (inputService.TouchEnabled and not inputService.KeyboardEnabled) and 'Tap [x] to exit' or 'Press [CTRL+C] to exit'
	footer.TextColor3 = Palette.Footer
	footer.TextSize = 17
	footer.TextXAlignment = Enum.TextXAlignment.Left
	footer.Font = Enum.Font.Code
	footer.Parent = window

	track(inputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.C and inputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			cancel()
		end
	end))

	local revealed, revealTarget = 0, 0
	-- Set by Halt() on the paths that leave the window up for reading but have no more rows
	-- to draw. Without it this thread outlives the boot at ~14Hz for the rest of the session.
	local halted = false
	task.spawn(function()
		while not closed and not halted do
			if revealed < revealTarget then
				revealed += 1
				local row = rows[revealed]
				row.Visible = true
				tweenService:Create(row, TweenInfo.new(0.18), {TextTransparency = 0}):Play()
			end
			task.wait(0.07)
		end
	end)

	-- One flat terminal button, shared by the answer row Ask() builds.
	local function answerButton(text, width, order)
		local button = Instance.new('TextButton')
		-- keeps the buttons in the order given, ahead of the tooltip that trails them
		button.LayoutOrder = order
		button.Size = UDim2.fromOffset(width, 34)
		button.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		-- Frees the touch cursor so the button is tappable on phones (where input would
		-- otherwise be locked to the game).
		button.Modal = true
		button.Text = text
		button.TextColor3 = Palette.ButtonIdle
		button.TextSize = 17
		button.Font = Enum.Font.Code
		button.Parent = answers
		local corner = Instance.new('UICorner')
		corner.CornerRadius = UDim.new(0, 4)
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

	-- Everything Ask() put on the answer row, cleared between prompts. The tooltip label
	-- shares the frame and has to survive, hence the class test rather than a blanket
	-- ClearAllChildren.
	local function clearAnswers()
		for _, child in answers:GetChildren() do
			if child:IsA('TextButton') then
				child:Destroy()
			end
		end
	end

	local console = {}

	-- `chevron` is the glyph in front of the status word. It points forward ('>') for every
	-- step of the boot itself. Escaped, since the label is RichText.
	function console:SetStatus(text, color, chevron)
		status.Text = '<font color="#9E9E9E">'..(chevron == '<' and '&lt;' or '&gt;')..'</font> <font color="'..(color or '#00CD7D')..'">'..text..'</font>'
	end

	function console:SetLine(text, color)
		line.Text = text
		line.TextColor3 = color or Palette.Line
	end

	-- alpha is how far through the boot we are; the logo is drawn to match, one row at a time.
	-- Clamped upwards only: a late progress report from a background step must never pull rows
	-- back off the logo (nothing here ever un-boots).
	function console:SetProgress(alpha)
		local count = math.clamp(math.floor(alpha * #SkidLogo + 0.5), 0, #SkidLogo)
		revealTarget = math.max(revealTarget, count)
	end

	function console:IsAborted()
		return aborted
	end

	-- Asks a question on the output line, waits for one of the buttons underneath it, then
	-- clears the line again so the next question can take its place. `fallback` is returned if
	-- the loader is closed or the timeout elapses -- a missed click must never hang injection.
	function console:Ask(question, buttons, timeoutSeconds, fallback)
		if closed then return fallback end
		self:SetLine(question)
		clearAnswers()

		tooltip.Visible = false

		local choice
		for index, def in buttons do
			local button = answerButton(def.text, 132, index)
			if def.tooltip then
				button.MouseEnter:Connect(function()
					tooltip.Text = def.tooltip
					tooltip.Visible = true
				end)
				button.MouseLeave:Connect(function()
					tooltip.Visible = false
				end)
			end
			button.MouseButton1Click:Connect(function()
				choice = def.key
			end)
		end
		answers.Visible = true

		local timeout = os.clock() + (timeoutSeconds or 60)
		repeat task.wait() until choice ~= nil or closed or os.clock() > timeout
		answers.Visible = false
		clearAnswers()
		tooltip.Visible = false
		self:SetLine('')
		if choice == nil then
			return fallback
		end
		return choice
	end

	-- Draws whatever rows are still missing, and only once the logo is whole flips the header
	-- to '> DONE' and counts the window out.
	function console:Finish(message, seconds)
		if closed then return end
		self:SetProgress(1)
		local drawn = os.clock() + 2
		repeat task.wait() until revealed >= #SkidLogo or closed or os.clock() > drawn
		-- the last row is still fading in when the counter hits the end
		task.wait(0.2)
		if closed then return end
		self:SetStatus('DONE')
		seconds = seconds or 5
		local deadline = os.clock() + seconds
		task.spawn(function()
			while not closed do
				local left = math.max(0, math.ceil(deadline - os.clock()))
				self:SetLine(message..' Loader will close in '..left..'s.')
				if left <= 0 then break end
				task.wait(0.2)
			end
			destroy()
		end)
	end

	-- Stops the reveal thread without taking the window down, for the paths that end the boot
	-- but still want the message on screen. Everything already drawn stays drawn.
	function console:Halt()
		halted = true
	end

	function console:Fail(err)
		if closed then return end
		self:SetStatus('FAILED', '#E15046')
		-- Executor errors carry absolute file paths that run off the right edge on a single
		-- line. Nothing is going to be asked at this point, so the output line is allowed to
		-- wrap down through the space the answer row was holding.
		line.TextWrapped = true
		line.TextYAlignment = Enum.TextYAlignment.Top
		line.Size = UDim2.new(1, -ContentPadding * 2, 0, AnswersY + 34 - LineY)
		self:SetLine(err, Palette.Error)
		-- Nothing further is drawn after a failure, so the thread has no work left.
		self:Halt()
	end

	-- Published so the next execution can tear this console down before building its own.
	shared.SkidV5LoaderTeardown = destroy

	return console
end

-- Same surface as the console, wired to nothing. Reloads are not user-initiated -- the queued
-- teleport script, the GUI's reinject buttons -- so they run the same boot with no window over
-- the game, and every call site below stays identical instead of guarding each one.
local function createHeadlessConsole()
	local console = {}
	function console:SetStatus() end
	function console:SetLine() end
	function console:SetProgress() end
	function console:Finish() end
	function console:Fail() end
	function console:Halt() end
	function console:IsAborted() return false end
	-- unattended, so a question can only answer with whatever the timeout would have picked
	function console:Ask(question, buttons, timeoutSeconds, fallback)
		return fallback
	end
	return console
end

-- shared.vapereload marks a run that something else started rather than a manual execution.
-- Read once here: it is cleared after main.lua has had its look at it (see the bottom of this
-- file), because nothing else clears it and a stale true would hide the console from every
-- later manual execution in the session.
local isReload = shared.vapereload and true or false

local console = isReload and createHeadlessConsole() or createConsole()
console:SetStatus('INJECTING')
console:SetLine('Injecting into ROBLOX...')
console:SetProgress(0.08)

-- Decided before the folders are created, while 'did this run create the install' is still
-- observable.
freshInstall = not isfolder('skidv5')
for _, folder in {'skidv5', 'skidv5/games', 'skidv5/profiles', 'skidv5/assets', 'skidv5/libraries', 'skidv5/guis'} do
	if not isfolder(folder) then
		makefolder(folder)
	end
end

-- Step 0: the human-facing version. filecheck.json drives updates, not this -- version.txt is
-- the label the GUI watermark shows, bumped by make-version.ps1 on every release, and it is
-- re-fetched on every boot so a bump lands on the next run. Not served from cache: the
-- manifest only refreshes .lua files, and a stale label is worse than none.
local scriptVersion
pcall(function()
	for attempt = 1, 4 do
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/skidforce/skidv5/main/profiles/version.txt', true)
		end)
		if suc and res and res ~= '' and res ~= '404: Not Found' then
			scriptVersion = res:gsub('%s+$', '')
			if scriptVersion ~= '' then
				writefile('skidv5/profiles/version.txt', scriptVersion)
			end
			break
		end
		task.wait(attempt)
	end
end)
if not scriptVersion then
	pcall(function()
		if hasContent('skidv5/profiles/version.txt') then
			scriptVersion = readfile('skidv5/profiles/version.txt'):gsub('%s+$', '')
		end
	end)
end

-- Step 1: hold here until ROBLOX itself is ready. Everything after this touches game state
-- (or hands off to main.lua, which does), so the shared.Vape* flags the injecting loadstring
-- sets have to be in place and the place has to be loaded before we move on.
do
	local playersService = cloneref(game:GetService('Players'))
	local deadline = os.clock() + 120
	repeat task.wait() until game:IsLoaded() or console:IsAborted() or os.clock() > deadline
	console:SetProgress(0.24)
	repeat task.wait() until playersService.LocalPlayer or console:IsAborted() or os.clock() > deadline
	-- A previous injection still holding shared.vape means the old GUI is mid-teardown;
	-- main.lua uninjects it, so just let the flag settle before reading the rest of them.
	if shared.vape then
		task.wait(0.25)
	end
	console:SetProgress(0.4)
end
if console:IsAborted() then deleteInstall() return end

-- Step 1b: bring every cached .lua file up to date BEFORE any of it runs. Skipped on
-- reloads (the first manual run this session already did it, and reinjects should stay
-- fast) and for developers (running local edits is the whole point of developer mode --
-- and their watermark-stripped files would be skipped anyway).
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

-- Detect the very first run (empty/near-empty profiles folder) BEFORE downloading, so we
-- know afterwards whether to show the prompts below.
local firstRunProfiles = false
pcall(function()
	firstRunProfiles = #listfiles('skidv5/profiles') < 3
end)

-- profilecheck.txt persists a prior 'No' answer, so the download prompt only asks once --
-- without it, a user who declines would get nagged again on every reinject (the profiles
-- folder stays under 3 files forever if nothing gets downloaded).
local declinedDownload = false
pcall(function()
	if isfile('skidv5/profiles/profilecheck.txt') then
		declinedDownload = readfile('skidv5/profiles/profilecheck.txt') == 'false'
	end
end)

-- Step 2: offer the shipped configs.
local wantsDownload = true
if firstRunProfiles and not declinedDownload then
	console:SetProgress(0.47)
	local ok, res = pcall(function()
		return console:Ask('Would you like to download the latest config?', {
			{text = 'Yes', key = true, tooltip = 'Downloads the Blatant and Legit configs from GitHub'},
			{text = 'No', key = false, tooltip = 'Starts on default settings and stops asking on future runs'}
		}, 60, true)
	end)
	-- checked before the answer is acted on, so cancelling mid-question never counts as a 'No'
	if console:IsAborted() then deleteInstall() return end
	wantsDownload = ok and res == true
	if not wantsDownload then
		pcall(function() writefile('skidv5/profiles/profilecheck.txt', 'false') end)
	end
end
console:SetProgress(0.53)

local downloadedConfigs = false
if firstRunProfiles and not declinedDownload and wantsDownload then
	console:SetLine('Downloading configs...')
	pcall(function()
		local body = fetchProfilesListing()
		if body then
			downloadProfilesListing(body, nil, function(completed, total)
				console:SetLine('Downloading configs ('..completed..'/'..total..')...')
				console:SetProgress(0.53 + 0.2 * (completed / math.max(total, 1)))
			end)
		end
	end)
	pcall(function()
		downloadedConfigs = #listfiles('skidv5/profiles') >= 3
	end)
	-- Record which commit this download reflects, so later sessions can tell whether profiles/
	-- has changed on GitHub since (see the sync prompt below).
	if downloadedConfigs then
		pcall(function()
			local commit = fetchProfilesCommit()
			if commit then
				writefile('skidv5/profiles/profilecommit.txt', commit)
			end
		end)
	end
end
-- Deleted again here: downloads already in flight when cancel fired can land after its wipe.
if console:IsAborted() then deleteInstall() return end

-- Step 2b: existing installs (3+ profiles). If profiles/ has changed on GitHub since the last
-- download/sync, offer to overwrite the shipped configs with the latest ones. Only the files
-- that exist in the GitHub profiles folder get redownloaded -- profiles the user made
-- themselves are left alone. Skipped on reinjects/teleports so it only ever asks once per
-- session, on the first manual execution.
if not firstRunProfiles and not declinedDownload and not isReload then
	local latestCommit, cachedCommit
	pcall(function()
		latestCommit = fetchProfilesCommit()
		cachedCommit = isfile('skidv5/profiles/profilecommit.txt') and readfile('skidv5/profiles/profilecommit.txt'):gsub('%s', '') or nil
	end)
	if latestCommit and latestCommit ~= cachedCommit then
		console:SetProgress(0.6)
		local ok, wantsSync = pcall(function()
			return console:Ask('Would you like to sync to the latest config?', {
				{text = 'Yes', key = true, tooltip = 'Replaces the shipped configs with the newer ones on GitHub'},
				{text = 'No', key = false, tooltip = 'Keeps the configs you have, asks again next session'}
			}, 60, false)
		end)
		if console:IsAborted() then deleteInstall() return end
		if ok and wantsSync == true then
			console:SetLine('Syncing configs...')

			-- Read BEFORE anything is overwritten. <GameId>.gui.txt holds `Profile` -- the
			-- config currently equipped -- and the sync rewrites that file from the repo's
			-- copy, whose Profile is whatever happened to be equipped when it was committed
			-- ('blatant', in the version shipping today). mergeGuiState carries the local
			-- value across, but on any decode failure it falls back to writing the incoming
			-- file verbatim, and that fallback is exactly how someone on 'legit' or on a
			-- config they made themselves comes back up on 'blatant'. Re-applying the name
			-- below makes the equipped config survive the sync whether the merge held or not.
			local lastProfile
			pcall(function()
				-- The live object first. SetProfile stamps a switch into gui.txt immediately,
				-- so the file is normally current -- but this is read before the Uninject
				-- below flushes in-memory state, and vape.Profile cannot be stale under any
				-- ordering. On a fresh execution there is no object and the file is the only
				-- source, which is the common case here.
				local live = shared.vape and shared.vape.Profile
				if type(live) == 'string' and live ~= '' then
					lastProfile = live
					return
				end

				local guipath = 'skidv5/profiles/'..game.GameId..'.gui.txt'
				if not isfile(guipath) then return end
				local guidata = cloneref(game:GetService('HttpService')):JSONDecode(readfile(guipath))
				if type(guidata) == 'table' and type(guidata.Profile) == 'string' and guidata.Profile ~= '' then
					lastProfile = guidata.Profile
				end
			end)

			pcall(function()
				-- If a previous instance is still injected, uninject it BEFORE overwriting:
				-- Uninject() saves the old in-memory config to disk as its first step, and
				-- main.lua would otherwise trigger it right after us -- clobbering the freshly
				-- synced profiles with the old settings. Same for its autosave loop.
				if shared.vape then
					pcall(function() shared.vape:Uninject() end)
					shared.vape = nil
				end
				-- Listing and file contents both pinned to latestCommit so a sync run right
				-- after a push can't grab a stale CDN copy of the branch head.
				local body = fetchProfilesListing(latestCommit)
				if body then
					downloadProfilesListing(body, latestCommit, function(completed, total)
						console:SetLine('Syncing configs ('..completed..'/'..total..')...')
						console:SetProgress(0.6 + 0.13 * (completed / math.max(total, 1)))
					end)
					writefile('skidv5/profiles/profilecommit.txt', latestCommit)
				end
			end)
			if console:IsAborted() then deleteInstall() return end

			-- Hand the equipped config back to the load that is about to happen. This covers
			-- a config the user made themselves and 'legit' alike -- and 'blatant' and
			-- 'default' too, since the shipped gui.txt names one of them and a user sitting
			-- on either would otherwise be indistinguishable from one who got reset onto it.
			-- finishLoading in main.lua treats this as a one-shot and clears it, so it steers
			-- only the load that follows this sync and does not leak into later reinjects.
			-- Left nil when gui.txt was unreadable, which keeps the old behaviour of letting
			-- whatever ends up in gui.txt decide rather than inventing a profile here.
			if lastProfile then
				shared.VapeCustomProfile = lastProfile
			end
		end
		-- On "No"/timeout the stored commit stays stale, so the prompt returns next session
		-- until the user agrees to sync once.
	end
end
console:SetProgress(0.73)

-- Step 3: after the shipped configs finish downloading, ask which one should load by default
-- and hand it to the GUI via shared.VapeCustomProfile. main.lua's finishLoading passes this
-- straight into vape:Load as the profile to load, replacing the 'default' profile. The keys
-- match the profile file name prefixes (e.g. blatant<PlaceId>.txt) so Load can find the file.
if downloadedConfigs then
	-- No fallback: only an explicit button click may force a config. This used to
	-- default to 'blatant' -- on a timeout (user tabbed away for 120s) or on the
	-- headless console (which answers every Ask with the fallback instantly) that
	-- silently stamped 'blatant' into shared.VapeCustomProfile, overriding the
	-- profile saved in gui.txt without the user ever choosing it. With nil the
	-- type(choice) guard below skips the override and the saved profile decides.
	local ok, choice = pcall(function()
		return console:Ask('Which config would you like to load by default?', {
			{text = 'Blatant', key = 'blatant', tooltip = 'Makes Blatant your default config: everything on, obvious'},
			{text = 'Legit', key = 'legit', tooltip = 'Makes Legit your default config: toned down to look normal'}
		}, 120, nil)
	end)
	if console:IsAborted() then deleteInstall() return end
	if ok and type(choice) == 'string' then
		shared.VapeCustomProfile = choice
	end
end

console:SetProgress(0.8)
console:SetLine('Loading skidv5...')
-- Creeps the last couple of rows in while main.lua downloads and builds the GUI, so the logo
-- is still one row short of finished when injection actually completes.
local injecting = true
task.spawn(function()
	local alpha = 0.8
	while injecting and alpha < 0.93 do
		task.wait(0.6)
		-- injection can finish while this thread is asleep; reporting the stale alpha here
		-- would land after Finish() has already asked for the full logo.
		if not injecting then break end
		alpha += 0.02
		console:SetProgress(alpha)
	end
end)

-- pcall'd so a failure surfaces on the console line instead of leaving the window stuck on
-- 'Loading skidv5...'; warn() keeps it in the executor output too.
local ok, result = pcall(function()
	return loadstring(downloadFile('skidv5/main.lua'), 'main')()
end)
injecting = false
-- Consumed only now: main.lua reads the flag itself while loading (it suppresses the 'Finished
-- Loading' notification on a reload). Left set it would leak into the rest of the session,
-- since main.lua never clears it and the next teleport/reinject sets it again anyway.
shared.vapereload = nil
-- Boot is over (successfully or not) -- reinjects and later manual runs may proceed.
shared.SkidV5LoaderBoot = nil

-- Cancelled while the GUI was already building: tear that back down too, then wipe whatever
-- the run wrote after cancel's first pass.
if console:IsAborted() then
	if shared.vape then
		pcall(function() shared.vape:Uninject() end)
	end
	shared.VapeCustomProfile = nil
	deleteInstall()
	return
end

if ok then
	console:Finish('Injected successfully.'..(scriptVersion and (' -- v'..scriptVersion) or ''), 5)
	return result
end
warn('[skidv5] '..tostring(result))
-- Copied as well as printed: the message is long, full of executor paths, and the person
-- hitting it is usually being asked to report it. Done here rather than inside console:Fail so
-- a headless reload (which has no window to read) still leaves it on the clipboard.
local failure = 'Injection failed: '..tostring(result)
local copied = pcall(function() setclipboard(failure) end)
console:Fail(failure..(copied and '\n\n(copied to clipboard)' or ''))