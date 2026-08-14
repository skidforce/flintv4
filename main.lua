-- main.lua is re-run directly in two places -- the queued teleport script below, and the GUI's
-- reinject buttons.
-- pcall'd: after a teleport shared.vape can still point at the previous server's instance,
-- whose GUI and connections no longer exist. An error walking that corpse would abort main.lua
-- on line one and leave the queued re-injection doing nothing at all.
if shared.vape then pcall(function() shared.vape:Uninject() end) end

local vape
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then
		vape:CreateNotification('FlintV4', 'Failed to load : '..err, 30, 'alert')
	end
	return res
end
local queue_on_teleport = queue_on_teleport or syn and syn.queue_on_teleport
local hasQueueOnTeleport = queue_on_teleport ~= nil
queue_on_teleport = queue_on_teleport or function() end
local isfile = isfile or function(file)
	local suc, res = pcall(function()
		return readfile(file)
	end)
	return suc and res ~= nil and res ~= ''
end
local cloneref = cloneref or function(obj)
	return obj
end
local playersService = cloneref(game:GetService('Players'))

-- isfile is not the question. A zero-byte file reads back as PRESENT through every executor's
-- real isfile, and only the fallback above treats empty as absent -- so on executors that ship
-- one (most of them), an interrupted write leaves a truncated file that nothing ever repairs.
--
-- That is not hypothetical: cancelling, crashing or teleporting during the concurrent asset
-- prefetch below leaves a half-written PNG. From then on prefetchFolder skips it, downloadFile
-- skips it, getcustomasset hands the corrupt file to the client, and the resulting invalid
-- content id throws 'ContentId formatting failed' at the assignment -- taking the whole GUI
-- chunk with it. Every route that could have fixed it asked isfile and was told the file was
-- fine, which is why the only known remedy was reinstalling the entire script.
--
-- Treating empty as missing makes it repair itself on the next run instead.
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
			content = '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..content
		end
		writefile(path, content)
	end
	return (func or readfile)(path)
end

-- Standalone progress label for the prefetch phase, since it runs before the GUI framework
-- (and its own downloader label) exists yet.
local downloaderGui, downloaderLabel
local function updateDownloader(text)
	if not downloaderGui then
		downloaderGui = Instance.new('ScreenGui')
		downloaderGui.Name = 'FlintV4Downloader'
		downloaderGui.ResetOnSpawn = false
		downloaderGui.Parent = cloneref(game:GetService('CoreGui'))
		downloaderLabel = Instance.new('TextLabel')
		downloaderLabel.Size = UDim2.new(1, 0, 0, 40)
		downloaderLabel.BackgroundTransparency = 1
		downloaderLabel.TextStrokeTransparency = 0
		downloaderLabel.TextSize = 20
		downloaderLabel.TextColor3 = Color3.new(1, 1, 1)
		downloaderLabel.Parent = downloaderGui
	end
	downloaderLabel.Text = text
end
local function destroyDownloader()
	if downloaderGui then
		downloaderGui:Destroy()
		downloaderGui, downloaderLabel = nil, nil
	end
end

-- Downloads every file in a repo folder concurrently instead of one HttpGet per getcustomasset call,
-- so GUI construction reads already-cached files instead of blocking on ~190 sequential round trips.
local function prefetchFolder(folder)
	local reqSuc, res = pcall(function()
		return game:HttpGet('https://api.github.com/repos/skidforce/flintv4/contents/'..folder, true)
	end)
	if not (reqSuc and res and res ~= '404: Not Found') then return end
	local bodySuc, body = pcall(function()
		return cloneref(game:GetService('HttpService')):JSONDecode(res)
	end)
	if not (bodySuc and body and typeof(body) == 'table') then return end

	local toFetch = {}
	for _, v in body do
		-- hasContent, not isfile: a truncated asset from an interrupted prefetch must be picked
		-- up again here rather than skipped forever. See the note on hasContent.
		if v.type == 'file' and not hasContent('flintv4/'..folder..'/'..v.name) then
			table.insert(toFetch, v.name)
		end
	end
	if #toFetch <= 0 then return end

	local completed, total = 0, #toFetch
	local done = Instance.new('BindableEvent')
	updateDownloader('Downloading '..folder..' ('..completed..'/'..total..')')

	-- A fixed pool rather than one task per file. assets/new alone holds 63 files, and a user
	-- on any other theme prefetches their theme AND assets/new -- so spawning per file put
	-- 60+ HttpGets in flight at once, each holding its response body, each able to retry four
	-- times. That is a large memory and socket spike at boot on a device that has not even
	-- built the GUI yet. Same files, same order, same completion signal; just a ceiling on how
	-- many are outstanding at once.
	local PREFETCH_WORKERS = 6
	local nextIndex = 1
	local workers = math.min(PREFETCH_WORKERS, total)
	local active = workers

	for _ = 1, workers do
		task.spawn(function()
			while true do
				-- Claiming an index takes no yield between the read and the increment, so
				-- two workers can never be handed the same file.
				local index = nextIndex
				nextIndex += 1
				if index > total then break end

				pcall(downloadFile, 'flintv4/'..folder..'/'..toFetch[index])
				completed += 1
				-- pcall'd and after the counter: if this ever threw, the worker would die
				-- before releasing the wait below and the boot would hang on a GUI error
				pcall(updateDownloader, 'Downloading '..folder..' ('..completed..'/'..total..')')
			end
			active -= 1
			if active <= 0 then
				done:Fire()
			end
		end)
	end
	-- Only wait when a worker is still outstanding. task.spawn runs each task inline until it
	-- yields, so on executors where HttpGet does NOT yield the scheduler every worker drains
	-- the whole queue inside the loop above -- done:Fire() then lands with nothing listening
	-- yet, and an unconditional Wait() blocks forever with the label frozen at total/total.
	-- Same guard the loader's downloaders already use.
	if active > 0 then
		done.Event:Wait()
	end
	done:Destroy()
end

-- False while a game script is still registering its modules on its own thread. A fast game
-- script sets this back to true before runGameScript even returns, so the common path never
-- observes it as false. finishLoading needs it because two of the things it starts are unsafe
-- until every module exists: the autosave loop, and the profile it applies.
local gameScriptFinished = true

-- Set once the profile has been applied against the full module set. Every Save() is gated on
-- this rather than on gameScriptFinished: a protected payload never sets that flag, so gating
-- saves on it would mean BedWars never autosaved or persisted a config change at all.
local profileApplied = false

local function finishLoading()
	vape.Init = nil
	-- shared.VapeCustomProfile is a ONE-SHOT hint for the load that immediately follows
	-- (set by the loader's first-run config chooser, or by the teleport handler below).
	-- Capture and clear it up front: getgenv()/shared persists across a reinject, so a
	-- value left over from an earlier teleport would keep forcing that old profile and
	-- override the config you actually switched to -- that stale value was the reinject
	-- 'loads the wrong config' bug. Cleared here, a plain reinject always falls through to
	-- the profile saved in gui.txt (i.e. whatever you last switched to).
	local customProfile = shared.VapeCustomProfile
	shared.VapeCustomProfile = nil
	if customProfile == '' then customProfile = nil end

	--[[
		The profile is applied EXACTLY ONCE, and only after every module exists.

		Loading it early and re-applying afterwards was tried and is wrong in both directions.
		Too early and the payload's modules do not exist yet, so they load on defaults; and the
		second pass needed to fix that would happily overwrite anything you had changed by hand
		in the meantime -- a toggle flipped at 10s silently reverting at 30s is a far worse bug
		than a config that arrives late. One load, once everything is registered, is the only
		version that cannot fight the user.

		Save() has the same constraint from the other side: it serialises the module list as it
		stands, so any save taken before the payload finishes writes a profile missing every
		module yet to appear -- destroying those settings on disk. Both the initial save and the
		autosave loop therefore sit behind the same wait.

		A normal game script has already finished by the time we get here (task.spawn runs it
		inline until it yields, and only the BedWars game script yields), so this whole block runs
		synchronously and behaves exactly as it always did.
	]]
	local function applyProfile()
		vape:Load(nil, customProfile)
		profileApplied = true
		-- Persist the applied profile so a reinject before the first autosave tick still comes
		-- back to the same config.
		if customProfile then
			pcall(function() vape:Save() end)
		end
		-- Only now is autosaving safe, and only now is there a profile worth saving.
		task.spawn(function()
			while vape.Loaded do
				vape:Save()
				for _ = 1, 10 do
					task.wait(1)
					if not vape.Loaded then break end
				end
			end
		end)
	end

	-- Waits until the game script has finished registering its modules, because the profile can
	-- only be applied to modules that exist.
	--
	-- An ordinary game script RETURNS, which sets gameScriptFinished. The timeout is a backstop.
	local function waitForModules()
		if gameScriptFinished then return end
		local started = os.clock()
		repeat
			task.wait(0.1)
		until gameScriptFinished
			or os.clock() - started > 120
		local count = 0
		for _ in vape.Modules do count += 1 end
		local how = gameScriptFinished and 'game script returned'
			or 'TIMED OUT after 120s'
		warn(('[flintv4] %d modules in %.1fs (%s) -- applying profile'):format(count, os.clock() - started, how))
	end

	if gameScriptFinished then
		applyProfile()
	else
		task.spawn(function()
			waitForModules()
			applyProfile()
		end)
	end

	local teleportedServers
	vape:Clean(playersService.LocalPlayer.OnTeleport:Connect(function()
		if (not teleportedServers) and (not shared.VapeIndependent) then
			teleportedServers = true
			-- Re-runs main.lua, not the loader. The loader is a full boot -- duplicate-run
			-- guard, GitHub API calls for the update check, the console window, the config
			-- prompt -- and any one of those bailing on the new server leaves the script
			-- uninjected. main.lua only needs the files the loader already cached, so it
			-- comes back reliably; the loader still runs on a manual execute.
			local teleportScript = [[
				shared.vapereload = true
				local cached = isfile and isfile('flintv4/main.lua') and readfile('flintv4/main.lua')
				if cached and cached ~= '' then
					loadstring(cached, 'main')()
				else
					loadstring(game:HttpGet('https://raw.githubusercontent.com/skidforce/flintv4/main/main.lua', true), 'main')()
				end
			]]
			if shared.FlintV4Developer then
				teleportScript = 'shared.FlintV4Developer = true\n'..teleportScript
			end
			if shared.VapeSmoothBoot then
				teleportScript = 'shared.VapeSmoothBoot = true\n'..teleportScript
			end
			-- %q: profile names are user-supplied (the Profiles tab lets
			-- you name one anything), and a name containing a quote or backslash used to produce
			-- a chunk that would not compile -- which silently costs the whole re-injection, not
			-- just the profile.
			-- customProfile is the fallback rather than shared.VapeCustomProfile (cleared above):
			-- queueing before the payload has finished means vape.Profile is not set yet, and
			-- without this the next server would be told to load 'default'.
			teleportScript = 'shared.VapeCustomProfile = '..string.format('%q', vape.Profile or customProfile or 'default')..'\n'..teleportScript
			-- Same rule as everywhere else: saving before the profile has been applied against the
			-- full module set would write one missing every module still to appear. Queueing
			-- straight into a match is exactly when that happens, so skip the save rather than
			-- corrupt the config -- what is on disk is already correct, there is simply nothing
			-- new worth recording yet.
			if profileApplied then
				vape:Save()
			end
			if not hasQueueOnTeleport then
				vape:CreateNotification('FlintV4', 'queue_on_teleport is not supported by your executor -- Vape will not re-inject automatically after this teleport (e.g. queueing into a match). You will need to re-run your loadstring manually.', 15, 'alert')
			end
			queue_on_teleport(teleportScript)
		end
	end))

	if shared.FlintV4SyncResult then
		vape:CreateNotification('FlintV4', shared.FlintV4SyncResult, 15, shared.FlintV4SyncResult:find('failed') and 'alert' or nil)
		shared.FlintV4SyncResult = nil
	end

	if not shared.vapereload then
		if not vape.Categories then return end
		if vape.Categories.Main.Options['GUI bind indicator'].Enabled then
			vape:CreateNotification('FlintV4 | Finished Loading', vape.VapeButton and 'Press the button in the top right to open GUI' or 'Press '..table.concat(vape.Keybind, ' + '):upper()..' to open GUI', 5)
		end
	end
end

	if not isfile('flintv4/profiles/gui.txt') then
		writefile('flintv4/profiles/gui.txt', 'new')
	end
	local gui = readfile('flintv4/profiles/gui.txt')

	if not isfolder('flintv4/assets/'..gui) then
		makefolder('flintv4/assets/'..gui)
	end
	pcall(prefetchFolder, 'assets/'..gui)
	if gui ~= 'new' then
		pcall(prefetchFolder, 'assets/new')
	end
	destroyDownloader()
	vape = loadstring(downloadFile('flintv4/guis/'..gui..'.lua'), 'gui')()
	if not vape then
		warn('[flintv4] GUI theme "'..gui..'" failed to load, falling back to new')
		gui = 'new'
		writefile('flintv4/profiles/gui.txt', 'new')
		vape = loadstring(downloadFile('flintv4/guis/new.lua'), 'gui')()
	end
	shared.vape = vape

if not shared.VapeIndependent then
	-- downloading doesn't need the game loaded; only wait here, right before touching game/character state
	if not game:IsLoaded() then
		-- Deadline, matching every equivalent wait in the loader. Unbounded, a place that never
		-- reports loaded parks this thread forever AFTER the GUI has already been built above --
		-- so the menu opens, no game modules ever register, and nothing says why.
		local loadDeadline = os.clock() + 120
		repeat task.wait() until game:IsLoaded() or os.clock() > loadDeadline
		-- identifyexecutor is absent on some executors (common on mobile); calling it
		-- unguarded errors here and aborts everything below, including the game script.
		local executorName = ''
		pcall(function() executorName = identifyexecutor and identifyexecutor() or '' end)
		task.wait(executorName == 'Opiumware' and 30 or 5)
	end
	-- pcall'd: an error thrown while universal.lua *executes* would otherwise propagate out of
	-- main.lua entirely, skipping the game script below and finishLoading() with it.
	pcall(function()
		loadstring(downloadFile('flintv4/games/universal.lua'), 'universal')()
	end)

	-- Started, never waited on. There is no deadline here by design: a deadline would only be a
	-- guess at how long the payload needs, and whatever number it held would become the time
	-- your profile takes to load. Nothing below depends on this having finished -- finishLoading
	-- applies your profile to the modules that exist now, and re-applies it the moment the rest
	-- register (see finishLoading).
	--
	-- This costs nothing for a normal game script: task.spawn runs the function inline until it
	-- yields, so anything that registers its modules without yielding -- which is every game
	-- file except BedWars -- has already set gameScriptFinished before we get past this line,
	-- and finishLoading takes the single-pass path exactly as it always did.
	--
	-- BedWars is the exception. The CatV6 BedWars script takes ~30s and none of its modules can
	-- exist until it finishes -- that part is not fixable from here. What it must not do is hold
	-- up the GUI, the universal modules and your config, none of which have anything to do with it.
	--
	-- Varargs are packed because '...' is only valid directly in this chunk, never inside the
	-- nested function the spawn needs.
	local gameArgs = table.pack(...)
	local function runGameScript(source, chunkname)
		local fn = loadstring(source, chunkname)
		if not fn then return end
		gameScriptFinished = false

		local started = os.clock()
		local thread = task.spawn(function()
			local ok, err = pcall(fn, table.unpack(gameArgs, 1, gameArgs.n))
			-- Only for a game script slow enough that the split-load path actually engaged; a normal
			-- game script never trips it.
			local elapsed = os.clock() - started
			if elapsed > 5 then
				warn(('[flintv4] %s finished in %.1fs -- its modules now have their saved settings'):format(chunkname, elapsed))
			end
			if not ok then
				warn('[flintv4] '..chunkname..' errored: '..tostring(err))
			end
		end)
		-- gameScriptFinished is set INSIDE the coroutine above. If the coroutine is
		-- killed mid-yield (e.g. by a teleport destroying the running thread), the
		-- flag never flips and waitForModules hangs for the full 120s timeout.
		-- Safety net: poll until the thread is dead, then force the flag. A fast
		-- game script sets it before we even get here, so the extra check costs nothing.
		task.spawn(function()
			repeat task.wait(1) until gameScriptFinished or coroutine.status(thread) == 'dead'
			if not gameScriptFinished then
				warn('[flintv4] '..chunkname..' coroutine died before setting gameScriptFinished -- forcing completion')
				gameScriptFinished = true
			end
		end)
	end

	local gamePath = 'flintv4/games/'..game.PlaceId..'.lua'
	-- A cached-but-empty file is treated as missing and refetched: a truncated write from an
	-- earlier failed download reads back as "present", and loadstring('') silently does
	-- nothing -- indistinguishable from the game script never loading at all.
	local cached = isfile(gamePath) and readfile(gamePath) or nil
	if cached and cached:gsub('%s', '') ~= '' then
		runGameScript(cached, tostring(game.PlaceId))
	elseif not shared.FlintV4Developer then
		-- Single fetch (the old code requested this URL twice: once to probe, then again
		-- inside downloadFile) and load straight from the response, so a stale/corrupt
		-- cache file can't shadow what we just downloaded.
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/skidforce/flintv4/main/games/'..game.PlaceId..'.lua', true)
		end)
		if suc and res and res ~= '' and res ~= '404: Not Found' then
			pcall(writefile, gamePath, '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..res)
			runGameScript(res, tostring(game.PlaceId))
		end
	end
	finishLoading()
else
	vape.Init = finishLoading
	return vape
end
