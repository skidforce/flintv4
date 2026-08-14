-- FlintV4 BedWars combat modules
-- Loaded by 6872274481.lua via loadstring — must grab everything from globals/shared.

local run = function(func)
	local ok, err = pcall(func)
	if not ok then
		warn('[flintv4] bedwars module failed: '..tostring(err))
	end
end

local vape = shared.vape
local entitylib = vape.Libraries.entity
local targetinfo = vape.Libraries.targetinfo
local bedwars = getgenv().bedwars or shared.bedwars
local store = getgenv().store
local cloneref = cloneref or function(o) return o end
local inputService = cloneref(game:GetService('UserInputService'))
local tweenService = cloneref(game:GetService('TweenService'))
local collectionService = cloneref(game:GetService('CollectionService'))
local gameCamera = workspace.CurrentCamera
local lplr = game.Players.LocalPlayer
local canSwing = getgenv().canSwing
local collection = getgenv().collection
local sortmethods = getgenv().sortmethods
local playersService = cloneref(game:GetService('Players'))
local runService = cloneref(game:GetService('RunService'))

run(function()
	local Killaura
	local Targets
	local CPS
	local SwingRange
	local AttackRange
	local AngleSlider
	local Max
	local Mouse
	local BoxSwingColor
	local BoxAttackColor
	local ParticleTexture
	local ParticleColor1
	local ParticleColor2
	local ParticleSize
	local Face
	local Silent
	local SortMode
	local SmoothRotation
	local MultiSwing
	local Particles, Boxes, AttackDelay = {}, {}, tick()
	local lastTargets = {}
	local rotateAngle = 0

	local function getAttackData()
		if Mouse.Enabled then
			if not inputService:IsMouseButtonPressed(0) then return false end
		end
		return store.hand.tool and store.hand.toolType == 'sword' and canSwing()
	end

	local function sortTargets(targets, method)
		if method == 'Distance' then
			table.sort(targets, function(a, b)
				local aDelta = a.RootPart.Position - entitylib.character.RootPart.Position
				local bDelta = b.RootPart.Position - entitylib.character.RootPart.Position
				return aDelta.Magnitude < bDelta.Magnitude
			end)
		elseif method == 'Health' then
			table.sort(targets, function(a, b)
				return a.Humanoid.Health < b.Humanoid.Health
			end)
		elseif method == 'Angle' then
			local selfpos = entitylib.character.RootPart.Position
			local facing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
			table.sort(targets, function(a, b)
				local aAngle = math.acos(facing:Dot(((a.RootPart.Position - selfpos) * Vector3.new(1, 0, 1)).Unit))
				local bAngle = math.acos(facing:Dot(((b.RootPart.Position - selfpos) * Vector3.new(1, 0, 1)).Unit))
				return aAngle < bAngle
			end)
		end
		return targets
	end

	Killaura = vape.Categories.Combat:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			if callback then
				lastTargets = {}
				repeat
					local attacked = {}
					if getAttackData() then
						local plrs = entitylib.AllPosition({
							Range = SwingRange.Value,
							Wallcheck = Targets.Walls.Enabled or nil,
							Part = 'RootPart',
							Players = Targets.Players.Enabled,
							NPCs = Targets.NPCs.Enabled,
							Limit = Max.Value + 5
						})

						if #plrs > 0 then
							local selfpos = entitylib.character.RootPart.Position
							local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
							local filtered = {}

							for _, v in plrs do
								local delta = (v.RootPart.Position - selfpos)
								local angle = math.acos(math.clamp(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit), -1, 1))
								if angle > (math.rad(AngleSlider.Value) / 2) then continue end
								table.insert(filtered, v)
							end

							filtered = sortTargets(filtered, SortMode.Value)
							for i = 1, math.min(#filtered, Max.Value) do
								local v = filtered[i]
								local delta = (v.RootPart.Position - selfpos)

								table.insert(attacked, {
									Entity = v,
									Check = delta.Magnitude > AttackRange.Value and BoxSwingColor or BoxAttackColor
								})
								targetinfo.Targets[v] = tick() + 1
							end

							if #attacked > 0 then
								local attackCount = Silent.Enabled and #attacked or 1
								local swingCount = MultiSwing.Enabled and math.min(#attacked, 3) or 1

								for swing = 1, swingCount do
									if AttackDelay < tick() then
										local cpsValue = CPS.GetRandomValue()
										AttackDelay = tick() + (1 / cpsValue) + (math.random(-10, 10) / 1000)

										if Silent.Enabled and attacked[swing] then
											local target = attacked[swing].Entity
											local targetPos = target.RootPart.Position
											local lookDir = (targetPos - selfpos).Unit
											local oldCF = entitylib.character.RootPart.CFrame
											entitylib.character.RootPart.CFrame = CFrame.lookAt(selfpos, Vector3.new(targetPos.X, selfpos.Y, targetPos.Z))
											bedwars.SwordController:swingSwordAtMouse()
											entitylib.character.RootPart.CFrame = oldCF
										else
											bedwars.SwordController:swingSwordAtMouse()
										end
									end
								end
							end

							for _, data in attacked do
								lastTargets[data.Entity] = tick()
							end
						end
					end

					for i, v in Boxes do
						v.Adornee = attacked[i] and attacked[i].Entity.RootPart or nil
						if v.Adornee then
							v.Color3 = Color3.fromHSV(attacked[i].Check.Hue, attacked[i].Check.Sat, attacked[i].Check.Value)
							v.Transparency = 1 - attacked[i].Check.Opacity
						end
					end

					for i, v in Particles do
						v.Position = attacked[i] and attacked[i].Entity.RootPart.Position or Vector3.new(9e9, 9e9, 9e9)
						v.Parent = attacked[i] and gameCamera or nil
					end

					if not Silent.Enabled and Face.Enabled and attacked[1] then
						local targetPos = attacked[1].Entity.RootPart.Position
						local currentCF = entitylib.character.RootPart.CFrame
						local targetLook = CFrame.lookAt(currentCF.Position, Vector3.new(targetPos.X, currentCF.Position.Y + 0.01, targetPos.Z))

						if SmoothRotation.Enabled then
							rotateAngle = rotateAngle + (1 / 6)
							local alpha = math.clamp(rotateAngle, 0, 1)
							entitylib.character.RootPart.CFrame = currentCF:Lerp(targetLook, alpha)
						else
							entitylib.character.RootPart.CFrame = targetLook
						end
					elseif not Face.Enabled then
						rotateAngle = 0
					end

					task.wait()
				until not Killaura.Enabled
			else
				lastTargets = {}
				for _, v in Boxes do
					v.Adornee = nil
				end
				for _, v in Particles do
					v.Parent = nil
				end
			end
		end,
		Tooltip = 'Attack players around you\nwithout aiming at them.\nSilent mode rotates attack only.'
	})
	Targets = Killaura:CreateTargets({Players = true, Walls = true})
	CPS = Killaura:CreateTwoSlider({
		Name = 'Attacks per Second',
		Min = 1,
		Max = 20,
		DefaultMin = 12,
		DefaultMax = 14
	})
	SwingRange = Killaura:CreateSlider({
		Name = 'Swing range',
		Min = 1,
		Max = 30,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AttackRange = Killaura:CreateSlider({
		Name = 'Attack range',
		Min = 1,
		Max = 18,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AngleSlider = Killaura:CreateSlider({
		Name = 'Max angle',
		Min = 1,
		Max = 360,
		Default = 90
	})
	Max = Killaura:CreateSlider({
		Name = 'Max targets',
		Min = 1,
		Max = 10,
		Default = 10
	})
	SortMode = Killaura:CreateDropdown({
		Name = 'Sort targets',
		List = {'Distance', 'Health', 'Angle', 'None'},
		Default = 'Distance'
	})
	Silent = Killaura:CreateToggle({
		Name = 'Silent rotation',
		Default = true,
		Tooltip = 'Rotates attack direction without\nmoving your character visually'
	})
	SmoothRotation = Killaura:CreateToggle({
		Name = 'Smooth rotation',
		Tooltip = 'Smoothly rotates toward targets\ninstead of snapping instantly'
	})
	MultiSwing = Killaura:CreateToggle({
		Name = 'Multi swing',
		Tooltip = 'Attacks multiple targets per tick'
	})
	Mouse = Killaura:CreateToggle({Name = 'Require mouse down'})
	Killaura:CreateToggle({
		Name = 'Show target',
		Function = function(callback)
			BoxSwingColor.Object.Visible = callback
			BoxAttackColor.Object.Visible = callback
			if callback then
				for i = 1, 10 do
					local box = Instance.new('BoxHandleAdornment')
					box.Adornee = nil
					box.AlwaysOnTop = true
					box.Size = Vector3.new(3, 5, 3)
					box.CFrame = CFrame.new(0, -0.5, 0)
					box.ZIndex = 0
					box.Parent = vape.gui
					Boxes[i] = box
				end
			else
				for _, v in Boxes do
					v:Destroy()
				end
				table.clear(Boxes)
			end
		end
	})
	BoxSwingColor = Killaura:CreateColorSlider({
		Name = 'Target Color',
		Darker = true,
		DefaultHue = 0.6,
		DefaultOpacity = 0.5,
		Visible = false
	})
	BoxAttackColor = Killaura:CreateColorSlider({
		Name = 'Attack Color',
		Darker = true,
		DefaultOpacity = 0.5,
		Visible = false
	})
	Killaura:CreateToggle({
		Name = 'Target particles',
		Function = function(callback)
			ParticleTexture.Object.Visible = callback
			ParticleColor1.Object.Visible = callback
			ParticleColor2.Object.Visible = callback
			ParticleSize.Object.Visible = callback
			if callback then
				for i = 1, 10 do
					local part = Instance.new('Part')
					part.Size = Vector3.new(2, 4, 2)
					part.Anchored = true
					part.CanCollide = false
					part.Transparency = 1
					part.Parent = gameCamera
					Particles[i] = Instance.new('ParticleEmitter')
					Particles[i].Parent = part
				end
			else
				for _, v in Particles do
					v.Parent:Destroy()
				end
				table.clear(Particles)
			end
		end
	})
	ParticleTexture = Killaura:CreateTextBox({
		Name = 'Particle texture',
		Default = 'rbxassetid://14782936177',
		Visible = false
	})
	ParticleColor1 = Killaura:CreateColorSlider({
		Name = 'Particle color 1',
		DefaultHue = 0.45,
		Darker = true,
		Visible = false,
		Function = function(hue, sat, val)
			for _, v in Particles do
				v.Color = ColorSequence.new(Color3.fromHSV(hue, sat, val), ParticleColor2.Object.Value)
			end
		end
	})
	ParticleColor2 = Killaura:CreateColorSlider({
		Name = 'Particle color 2',
		DefaultHue = 0,
		Darker = true,
		Visible = false,
		Function = function(hue, sat, val)
			for _, v in Particles do
				v.Color = ColorSequence.new(ParticleColor1.Object.Value, Color3.fromHSV(hue, sat, val))
			end
		end
	})
	ParticleSize = Killaura:CreateSlider({
		Name = 'Particle size',
		Min = 0,
		Max = 3,
		Default = 1.5,
		Decimal = 10,
		Visible = false,
		Function = function(val)
			for _, v in Particles do
				v.Size = NumberSequence.new(val)
			end
		end
	})
	Face = Killaura:CreateToggle({Name = 'Face target'})
end)

run(function()
	local AimAssist
	local Targets
	local AimSpeed
	local Distance
	local AngleSlider
	local Mouse
	local ClickAim
	local StrafeIncrease
	local Smoothness
	local Shake
	local Limit
	local Sort
	local AimPart
	local AimMode
	local BlockBreak
	local KillauraTarget
	local cache = {}
	local started, lasttarget, nextsearch = 0, nil, 0

	local sortmethods = {
		Damage = function(a, b)
			return a.Entity.Character:GetAttribute('LastDamageTakenTime') < b.Entity.Character:GetAttribute('LastDamageTakenTime')
		end,
		Health = function(a, b)
			return a.Entity.Health < b.Entity.Health
		end,
		Angle = function(a, b)
			local selfrootpos = entitylib.character.RootPart.Position
			local localfacing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
			local direction = (a.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)
			local direction2 = (b.Entity.RootPart.Position - selfrootpos) * Vector3.new(1, 0, 1)
			local angle = direction.Magnitude > 0 and math.acos(math.clamp(localfacing:Dot(direction.Unit), -1, 1)) or 0
			local angle2 = direction2.Magnitude > 0 and math.acos(math.clamp(localfacing:Dot(direction2.Unit), -1, 1)) or 0
			return angle < angle2
		end,
		Distance = function(a, b)
			local localpos = entitylib.character.RootPart.Position
			return (localpos - a.Entity.RootPart.Position).Magnitude < (localpos - b.Entity.RootPart.Position).Magnitude
		end
	}

	local function ease(x)
		return x * x * (3 - 2 * x)
	end

	local function getMousePosition()
		if inputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
			return gameCamera.ViewportSize / 2
		end
		return inputService.GetMouseLocation(inputService)
	end

	local function getAim(ent)
		if AimPart.Value == 'Closest' then
			if not cache[ent.Character] then
				cache[ent.Character] = ent.Character:GetChildren()
			end
			local localPosition, magnitude, part = getMousePosition(), 9e9, nil
			for _, v in cache[ent.Character] do
				if v and v.Parent and v:IsA('BasePart') then
					local position, vis = gameCamera.WorldToViewportPoint(gameCamera, v.Position)
					if vis then
						local mag = (localPosition - Vector2.new(position.x, position.y)).Magnitude
						if mag < magnitude then
							magnitude = mag
							part = v
						end
					end
				end
			end
			if part then
				return part.Position
			end
		end
		return ent.RootPart.Position
	end

	local aimfuncs = {
		Simple = function(localcframe, ent, fps)
			local rng = Random.new()
			local speed = (AimSpeed.Value + (StrafeIncrease.Enabled and (inputService:IsKeyDown(Enum.KeyCode.A) or inputService:IsKeyDown(Enum.KeyCode.D)) and 10 or 0)) / Smoothness.Value
			return localcframe:Lerp(CFrame.lookAt(localcframe.p, getAim(ent) + Vector3.new((rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps)), speed * fps), speed
		end,
		Adaptive = function(localcframe, ent, fps)
			local prog, rng = ease(math.min(tick() - started, 1)), Random.new()
			local speed = ((AimSpeed.Value * 0.1 * prog) + (1 - prog) + (StrafeIncrease.Enabled and (inputService:IsKeyDown(Enum.KeyCode.A) or inputService:IsKeyDown(Enum.KeyCode.D)) and 10 or 5)) / Smoothness.Value
			return localcframe:Lerp(CFrame.lookAt(localcframe.p, getAim(ent) + Vector3.new((rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps, (rng:NextNumber() - 0.5) * Shake.Value * fps)), speed * fps), speed
		end
	}

	local function isValid(ent)
		if not entitylib.isAlive then return false end
		if not ent or not ent.Character or not ent.Character.Parent then return false end
		if not ent.RootPart or not ent.RootPart.Parent then return false end
		if not ent.Targetable or not entitylib.isVulnerable(ent) then return false end
		local localPosition = entitylib.character.RootPart.Position
		if (localPosition - ent.RootPart.Position).Magnitude > Distance.Value then
			return false
		end
		if Targets.Walls.Enabled and entitylib.Wallcheck(localPosition, ent.RootPart.Position, Targets.Walls.Enabled, ent) then
			return false
		end
		return true
	end

	local function getAttackData()
		if Mouse.Enabled and not inputService:IsMouseButtonPressed(0) and (tick() - bedwars.SwordController.lastSwing) > 0.15 then
			return false
		end
		if ClickAim.Enabled and (tick() - bedwars.SwordController.lastSwing) > 0.3 then
			return false
		end
		if BlockBreak.Enabled and (tick() - store.lastHit) < 0.3 then
			return false
		end
		if Limit.Enabled and store.hand.toolType ~= 'sword' then
			return false
		end

		if isValid(lasttarget) and tick() < nextsearch then
			return lasttarget
		end

		local ent = KillauraTarget.Enabled and isValid(store.KillauraTarget) and store.KillauraTarget or entitylib.EntityPosition({
			Range = Distance.Value,
			Part = 'RootPart',
			Wallcheck = Targets.Walls.Enabled,
			Players = Targets.Players.Enabled,
			NPCs = Targets.NPCs.Enabled,
			Sort = sortmethods[Sort.Value]
		})

		if ent ~= lasttarget then
			started = tick()
		end
		lasttarget = ent
		nextsearch = tick() + 1
		return ent
	end

	AimAssist = vape.Categories.Combat:CreateModule({
		Name = 'AimAssist',
		Function = function(callback)
			if callback then
				local rotate = 0

				AimAssist:Clean(runService.PostSimulation:Connect(function(dt)
					if entitylib.isAlive then
						entitylib.character.Humanoid.AutoRotate = tick() > rotate

						local ent = getAttackData()
						if ent then
							local root = entitylib.character.RootPart
							local delta = (ent.RootPart.Position - root.Position)
							local localfacing = root.CFrame.LookVector * Vector3.new(1, 0, 1)
							local horizontal = delta * Vector3.new(1, 0, 1)
							local angle = localfacing.Magnitude > 0 and horizontal.Magnitude > 0 and math.acos(math.clamp(localfacing.Unit:Dot(horizontal.Unit), -1, 1)) or 0
							if angle >= (math.rad(AngleSlider.Value) / 2) then
								return
							end
							targetinfo.Targets[ent] = tick() + 1

							local firstPerson = entitylib.character.Head.LocalTransparencyModifier == 1
							local perspective = AimMode.Value

							if perspective == 'Mouse' then
								local cframe, speed = aimfuncs[Mode.Value](gameCamera.CFrame, ent, dt)
								local viewport = gameCamera:WorldToViewportPoint(cframe.Position)
								local pos = (Vector2.new(viewport.X, viewport.Y) - inputService:GetMouseLocation()) * (speed / 15)
								mousemoverel(pos.X, pos.Y)
							elseif perspective == 'First person' or (perspective == 'Dynamic' and firstPerson) then
								if not firstPerson then return end
								local cframe = aimfuncs[Mode.Value](gameCamera.CFrame, ent, dt)
								gameCamera.CFrame = cframe
							elseif perspective == 'Third person' or (perspective == 'Dynamic' and not firstPerson) then
								if firstPerson then return end
								local cframe = aimfuncs[Mode.Value](root.CFrame, ent, dt)
								local direction = cframe.LookVector * Vector3.new(1, 0, 1)
								if direction.Magnitude > 0 then
									entitylib.character.Humanoid.AutoRotate = false
									root.CFrame = CFrame.lookAlong(root.Position, direction)
									rotate = tick() + 0.1
								end
							end
						end
					else
						lasttarget = nil
					end
				end))
			else
				lasttarget = nil
				if entitylib.isAlive then
					entitylib.character.Humanoid.AutoRotate = true
				end
			end
		end,
		Tooltip = 'Smoothly aims to closest valid target with sword'
	})
	local modes = {}
	for i in aimfuncs do
		table.insert(modes, i)
	end
	AimMode = AimAssist:CreateDropdown({
		Name = 'Aim perspective',
		Tooltip = 'First person - Uses your camera to aim\nThird person - Moves your character to where your supposed to look\nMouse - Moves your mouse & camera\nDynamic - Uses first person mode if ur in first person, and uses third person if ur in third person',
		List = {'First person', 'Third person', 'Dynamic'},
		Default = 'First person'
	})
	Mode = AimAssist:CreateDropdown({
		Name = 'Mode',
		List = modes,
		Tooltip = 'Simple - Smooth aiming\nAdaptive - Advanced tracking with adaptive behavior',
		Default = modes[1],
	})
	Targets = AimAssist:CreateTargets({
		Players = true,
		Walls = true,
	})
	local methods = {'Damage', 'Distance'}
	for i in sortmethods do
		if not table.find(methods, i) then
			table.insert(methods, i)
		end
	end
	ClickAim = AimAssist:CreateToggle({
		Name = 'Click aim',
		Default = true,
	})
	Mouse = AimAssist:CreateToggle({Name = 'Require mouse down'})
	StrafeIncrease = AimAssist:CreateToggle({Name = 'Strafe increase'})
	BlockBreak = AimAssist:CreateToggle({Name = 'Check block break'})
	KillauraTarget = AimAssist:CreateToggle({Name = 'Use killaura target'})
	AimSpeed = AimAssist:CreateSlider({
		Name = 'Aim speed',
		Min = 1,
		Max = 20,
		Default = 6,
	})
	Smoothness = AimAssist:CreateSlider({
		Name = 'Smoothness',
		Min = 1,
		Max = 20,
		Default = 1,
		Decimal = 10,
		Tooltip = 'Divides the aim speed to soften the snap, 1 leaves aiming unchanged',
	})
	Distance = AimAssist:CreateSlider({
		Name = 'Distance',
		Min = 1,
		Max = 30,
		Default = 30,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end,
	})
	Shake = AimAssist:CreateSlider({
		Name = 'Shake',
		Min = 0,
		Max = 100,
		Default = 0,
		Tooltip = 'Adds random jitter to simulate human aim',
	})
	AngleSlider = AimAssist:CreateSlider({
		Name = 'Max angle',
		Min = 1,
		Max = 360,
		Default = 70,
	})
	Limit = AimAssist:CreateToggle({
		Name = 'Limit to items',
		Tooltip = 'Only attacks when sword is held',
	})
	Sort = AimAssist:CreateDropdown({
		Name = 'Target mode',
		List = methods,
		Default = 'Angle',
	})
	AimPart = AimAssist:CreateDropdown({
		Name = 'Target area',
		List = {'Center', 'Closest'},
		Default = 'Center',
	})
end)

run(function()
	local TriggerBot
	local CPS
	local rayParams = RaycastParams.new()

	TriggerBot = vape.Categories.Combat:CreateModule({
		Name = 'TriggerBot',
		Function = function(callback)
			if callback then
				repeat
					local doAttack
					if not bedwars.AppController:isLayerOpen(bedwars.UILayers.MAIN) then
						if entitylib.isAlive and store.hand.toolType == 'sword' and bedwars.DaoController.chargingMaid == nil then
							local attackRange = bedwars.ItemMeta[store.hand.tool.Name].sword.attackRange
							rayParams.FilterDescendantsInstances = {lplr.Character}

							local unit = lplr:GetMouse().UnitRay
							local localPos = entitylib.character.RootPart.Position
							local rayRange = (attackRange or 14.4)
							local ray = bedwars.QueryUtil:raycast(unit.Origin, unit.Direction * 200, rayParams)
							if ray and (localPos - ray.Instance.Position).Magnitude <= rayRange then
								for _, ent in entitylib.List do
									doAttack = ent.Targetable and ray.Instance:IsDescendantOf(ent.Character) and (localPos - ent.RootPart.Position).Magnitude <= rayRange
									if doAttack then
										break
									end
								end
							end

							doAttack = doAttack or bedwars.SwordController:getTargetInRegion(attackRange or 3.8 * 3, 0)
							if doAttack and canSwing() then
								bedwars.SwordController:swingSwordAtMouse()
							end
						end
					end

					task.wait(doAttack and 1 / CPS.GetRandomValue() or 0.016)
				until not TriggerBot.Enabled
			end
		end,
		Tooltip = 'Automatically swings when hovering over a entity'
	})
	CPS = TriggerBot:CreateTwoSlider({
		Name = 'CPS',
		Min = 1,
		Max = 9,
		DefaultMin = 7,
		DefaultMax = 7
	})
end)

run(function()
	local Breaker
	local Mode
	local Range
	local BreakSpeed
	local UpdateRate
	local Bed
	local Tesla
	local Hive
	local LuckyBlock
	local IronOre
	local Effect
	local Animation
	local SelfBreak
	local LimitItem
	local Wallcheck
	local AutoTool
	local CustomHealth
	local BreakThrough
	local ChainBreaks
	local customHealth = {}

	local function getBlockAt(pos)
		local block = bedwars.BlockController:getStore():getBlockAt(pos)
		return block
	end

	local function attemptBreak(tab, localPosition, route)
		if not tab then return end
		for _, v in tab do
			if (v.Position - localPosition).Magnitude < Range.Value and bedwars.BlockController:isBlockBreakable({blockPosition = v.Position / 3}, lplr) then
				if not SelfBreak.Enabled and v:GetAttribute('PlacedByUserId') == lplr.UserId then continue end
				if (v:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then continue end
				if LimitItem.Enabled and not (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then continue end

				bedwars.breakBlock(v, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealth or nil, AutoTool.Enabled, Wallcheck.Enabled, 'Health', not route)
				task.wait(BreakSpeed.Value)
				return true
			end
		end
		return false
	end

	local function getBlocksAlongPath(from, to)
		local blocks = {}
		local dir = to - from
		local dist = dir.Magnitude
		if dist == 0 then return blocks end
		local unit = dir.Unit
		local step = 3
		local steps = math.ceil(dist / step)
		for i = 1, steps do
			local pos = from + unit * math.min(i * step, dist)
			local blockPos = Vector3.new(math.floor(pos.X / 3 + 0.5) * 3, math.floor(pos.Y / 3 + 0.5) * 3, math.floor(pos.Z / 3 + 0.5) * 3)
			local block = getBlockAt(blockPos)
			if block and not blocks[block] then
				if not SelfBreak.Enabled and block:GetAttribute('PlacedByUserId') == lplr.UserId then continue end
				if (block:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then continue end
				if LimitItem.Enabled and not (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then continue end
				blocks[block] = true
				table.insert(blocks, block)
			end
		end
		return blocks
	end

	local function breakThroughBeds(beds, localPosition)
		if not beds then return false end
		for _, bed in beds do
			if (bed.Position - localPosition).Magnitude > Range.Value then continue end
			if (bed:GetAttribute('BedShieldEndTime') or 0) > workspace:GetServerTimeNow() then continue end
			if not SelfBreak.Enabled and bed:GetAttribute('PlacedByUserId') == lplr.UserId then continue end
			if LimitItem.Enabled and not (store.hand.tool and bedwars.ItemMeta[store.hand.tool.Name].breakBlock) then continue end

			local chainCount = 0
			local maxChains = ChainBreaks.Value
			local pathBlocks = getBlocksAlongPath(localPosition, bed.Position)

			for _, block in pathBlocks do
				if chainCount >= maxChains then break end
				if not Breaker.Enabled then break end
				if not block.Parent then continue end

				bedwars.breakBlock(block, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealth or nil, AutoTool.Enabled, false, 'Health', false)
				chainCount += 1
				task.wait(BreakSpeed.Value)
			end

			if chainCount > 0 then return true end
		end
		return false
	end

	Breaker = vape.Categories.Minigames:CreateModule({
		Name = 'Breaker',
		Function = function(callback)
			if callback then
				local beds = collection('bed', Breaker)
				local teslas = collection('tesla-trap', Breaker, function(tab, obj)
					task.delay(0.1, function()
						if not Breaker.Enabled or not obj.Parent then return end
						local player = playersService:GetPlayerByUserId(obj:GetAttribute('PlacedByUserId'))
						if player and player:GetAttribute('Team') ~= lplr:GetAttribute('Team') then
							table.insert(tab, obj)
						end
					end)
				end)
				local hives = collection('beehive', Breaker, function(tab, obj)
					task.delay(0.1, function()
						if not Breaker.Enabled or not obj.Parent then return end
						local player = playersService:GetPlayerByUserId(obj:GetAttribute('PlacedByUserId'))
						if player and player:GetAttribute('Team') ~= lplr:GetAttribute('Team') then
							table.insert(tab, obj)
						end
					end)
				end)
				local luckyblock = collection('LuckyBlock', Breaker)
				local ironores = collection('iron_ore_mesh_block', Breaker)

				repeat
					task.wait(1 / UpdateRate.Value)
					if not Breaker.Enabled then break end
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position

						if BreakThrough.Enabled then
							if breakThroughBeds(Bed.Enabled and beds, localPosition) then continue end
						else
							if attemptBreak(Bed.Enabled and beds, localPosition, true) then continue end
						end
						if attemptBreak(Hive.Enabled and hives, localPosition) then continue end
						if attemptBreak(Tesla.Enabled and teslas, localPosition) then continue end
						if attemptBreak(LuckyBlock.Enabled and luckyblock, localPosition) then continue end
						if attemptBreak(IronOre.Enabled and ironores, localPosition) then continue end
					end
				until not Breaker.Enabled
			end
		end,
		Tooltip = 'Break blocks around you automatically'
	})
	Mode = Breaker:CreateDropdown({
		Name = 'Break mode',
		List = {'Health', 'Distance'},
		Default = 'Health'
	})
	Range = Breaker:CreateSlider({
		Name = 'Break range',
		Min = 1,
		Max = 30,
		Default = 30,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	BreakSpeed = Breaker:CreateSlider({
		Name = 'Break speed',
		Min = 0,
		Max = 0.3,
		Default = 0.25,
		Decimal = 100,
		Suffix = 'seconds'
	})
	UpdateRate = Breaker:CreateSlider({
		Name = 'Update rate',
		Min = 1,
		Max = 120,
		Default = 60,
		Suffix = 'hz'
	})
	Bed = Breaker:CreateToggle({
		Name = 'Break Bed',
		Default = true
	})
	Tesla = Breaker:CreateToggle({
		Name = 'Break Tesla',
		Default = true
	})
	Hive = Breaker:CreateToggle({
		Name = 'Break Hive',
		Default = true
	})
	LuckyBlock = Breaker:CreateToggle({
		Name = 'Break Lucky Block',
		Default = true
	})
	IronOre = Breaker:CreateToggle({
		Name = 'Break Iron Ore',
		Default = true
	})
	Effect = Breaker:CreateToggle({
		Name = 'Show Healthbar & Effects',
		Default = true
	})
	CustomHealth = Breaker:CreateToggle({
		Name = 'Custom Healthbar',
		Default = true,
		Darker = true
	})
	Animation = Breaker:CreateToggle({Name = 'Animation'})
	SelfBreak = Breaker:CreateToggle({Name = 'Self Break'})
	Wallcheck = Breaker:CreateToggle({
		Name = 'Legit mode',
		Default = true,
		Tooltip = 'Checks for blocks inside the bed instead of directly targetting bed'
	})
	AutoTool = Breaker:CreateToggle({
		Name = 'Auto Tool',
		Tooltip = 'Visualises tool switching on ur client'
	})
	LimitItem = Breaker:CreateToggle({
		Name = 'Limit to items',
		Tooltip = 'Only breaks when tools are held'
	})
	BreakThrough = Breaker:CreateToggle({
		Name = 'Break Through',
		Default = true,
		Tooltip = 'Breaks blocks between you and the bed\nto reach it through walls'
	})
	ChainBreaks = Breaker:CreateSlider({
		Name = 'Chain breaks per tick',
		Min = 1,
		Max = 10,
		Default = 3,
		Darker = true,
		Tooltip = 'How many blocks to break per update tick\nwhen breaking through walls'
	})
end)

run(function()
	local BlockFly
	local Value
	local VerticalValue
	local WallCheck
	local Expand
	local PlaceDelay
	local up, down = 0, 0

	local function getBlockBelow(root, expand)
		local pos = root.Position - Vector3.new(0, entitylib.character.HipHeight + 1.5, 0)
		local moveDir = entitylib.character.Humanoid.MoveDirection
		local blockPos = Vector3.new(
			math.floor((pos.X + moveDir.X * expand * 3) / 3 + 0.5) * 3,
			math.floor(pos.Y / 3 + 0.5) * 3,
			math.floor((pos.Z + moveDir.Z * expand * 3) / 3 + 0.5) * 3
		)
		return blockPos
	end

	local function canPlaceAt(pos)
		local existing = bedwars.BlockController:getStore():getBlockAt(pos)
		if existing then return false end
		local sides = {
			Vector3.FromNormalId(Enum.NormalId.Top),
			Vector3.FromNormalId(Enum.NormalId.Bottom),
			Vector3.FromNormalId(Enum.NormalId.Left),
			Vector3.FromNormalId(Enum.NormalId.Right),
			Vector3.FromNormalId(Enum.NormalId.Front),
			Vector3.FromNormalId(Enum.NormalId.Back),
		}
		for _, side in sides do
			local adj = bedwars.BlockController:getStore():getBlockAt(pos + side * 3)
			if adj then return true end
		end
		return false
	end

	local function getBlockItem()
		if store.hand.toolType == 'block' and store.hand.tool then
			return store.hand.tool.Name
		end
		for _, item in store.inventory.inventory.items do
			if bedwars.ItemMeta[item.itemType].block then
				return item.itemType
			end
		end
		return nil
	end

	BlockFly = vape.Categories.Blatant:CreateModule({
		Name = 'BlockFly',
		Function = function(callback)
			if callback then
				BlockFly:Clean(inputService.InputBegan:Connect(function(input)
					if not inputService:GetFocusedTextBox() then
						if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
							up = 1
						elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
							down = -1
						end
					end
				end))
				BlockFly:Clean(inputService.InputEnded:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonA then
						up = 0
					elseif input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.ButtonL2 then
						down = 0
					end
				end))

				repeat
					if entitylib.isAlive and isnetworkowner(entitylib.character.RootPart) then
						local root = entitylib.character.RootPart
						local moveDir = entitylib.character.Humanoid.MoveDirection
						local dt = 1 / 60
						local wool = getBlockItem()

						if wool then
							for i = 1, Expand.Value do
								local blockPos = getBlockBelow(root, i)
								if canPlaceAt(blockPos) then
									pcall(bedwars.placeBlock, blockPos, wool)
								end
							end
						end

						local verticalVelo = (up + down) * VerticalValue.Value
						local rayParams = RaycastParams.new()
						rayParams.FilterDescendantsInstances = {lplr.Character, gameCamera}
						rayParams.RespectCanCollide = true

						if moveDir.Magnitude > 0 then
							local dest = moveDir * math.max(Value.Value, 0) * dt
							if WallCheck.Enabled then
								local ray = workspace:Raycast(root.Position, dest, rayParams)
								if ray then
									dest = (ray.Position + ray.Normal) - root.Position
								end
							end
							root.CFrame += dest
						end

						root.CFrame += Vector3.new(0, verticalVelo * dt, 0)
						root.AssemblyLinearVelocity = Vector3.new(moveDir.X * math.max(Value.Value, 0), verticalVelo, moveDir.Z * math.max(Value.Value, 0))
					end
					task.wait(PlaceDelay.Value)
				until not BlockFly.Enabled
			else
				up, down = 0, 0
			end
		end,
		Tooltip = 'Fly while placing blocks below you\nlike scaffold but in the air'
	})
	Value = BlockFly:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 100,
		Default = 50,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	VerticalValue = BlockFly:CreateSlider({
		Name = 'Vertical Speed',
		Min = 1,
		Max = 100,
		Default = 50,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	Expand = BlockFly:CreateSlider({
		Name = 'Expand',
		Min = 1,
		Max = 6,
		Default = 3,
		Tooltip = 'How many blocks ahead to place'
	})
	WallCheck = BlockFly:CreateToggle({
		Name = 'Wall Check',
		Default = true
	})
	PlaceDelay = BlockFly:CreateSlider({
		Name = 'Place interval',
		Min = 0,
		Max = 0.1,
		Default = 0.03,
		Decimal = 1000,
		Suffix = 'sec'
	})
end)

return bedwarsmodules
