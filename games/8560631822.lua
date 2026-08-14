local vape = shared.vape
local loadstring = function(...)
	local res, err = loadstring(...)
	if err and vape then 
		vape:CreateNotification('Vape', 'Failed to load : '..err, 30, 'alert') 
	end
	return res
end
local isfile = isfile or function(file)
	local suc, res = pcall(function() 
		return readfile(file) 
	end)
	return suc and res ~= nil and res ~= ''
end
vape.Place = 6872274481
-- 8560631822 is the same BedWars game under a different PlaceId.
-- All BedWars modules are built into 6872274481.lua (CatV6-based).
local gamePath = 'flintv4/games/6872274481.lua'
local cached = isfile(gamePath) and readfile(gamePath) or nil
if cached and cached:gsub('%s', '') ~= '' then
	loadstring(cached, '6872274481')()
elseif not shared.FlintV4Developer then
	-- Fetched from GitHub on first run.
	local content
	for attempt = 1, 4 do
		local suc, res = pcall(function()
			return game:HttpGet('https://raw.githubusercontent.com/skidforce/flintv4/main/games/6872274481.lua', true)
		end)
		if suc and res and res ~= '' and res ~= '404: Not Found' then
			content = res
			break
		end
		if attempt < 4 then
			task.wait(attempt)
		end
	end
	if content then
		pcall(writefile, gamePath, '--This watermark is used to delete the file if its cached, remove it to make the file persist after vape updates.\n'..content)
		loadstring(content, '6872274481')()
	end
end
