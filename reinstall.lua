if shared.vape then
	pcall(function() shared.vape:Uninject() end)
	shared.vape = nil
end

shared.VapeCustomProfile = nil
shared.vapereload = nil

task.wait(2)

if isfolder and isfolder('flintv4') then
	local ok, err = pcall(delfolder, 'flintv4')
	if not ok then
		warn('FlintV4 reinstall: failed to delete flintv4 folder - '..tostring(err))
	end
end

task.wait(2)
shared.VapeSmoothBoot = true

local suc, res = pcall(function()
	return game:HttpGet('https://raw.githubusercontent.com/skidforce/flintv4/refs/heads/main/loader.lua', true)
end)
if not suc or not res or res == '' or res == '404: Not Found' then
	error('FlintV4 reinstall: failed to download loader.lua - '..tostring(res))
end
loadstring(res, 'loader')()
