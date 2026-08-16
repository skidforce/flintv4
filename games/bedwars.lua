-- SkidV5 BedWars combat modules
-- Loaded by 6872274481.lua via loadstring � must grab everything from globals/shared.

local run = function(func)
	local ok, err = pcall(func)
	if not ok then
		warn('[skidv5] bedwars module failed: '..tostring(err))
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
local gameLighting = game:GetService('Lighting')
local lplr = game.Players.LocalPlayer
local canSwing = getgenv().canSwing
local collection = getgenv().collection
local sortmethods = getgenv().sortmethods
local playersService = cloneref(game:GetService('Players'))
local runService = cloneref(game:GetService('RunService'))
local httpService = cloneref(game:GetService('HttpService'))
local prediction = vape.Libraries.prediction
local switchItem = getgenv().switchItem
local getPlacedBlock = getgenv().getPlacedBlock
local getBow = getgenv().getBow

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
	local SortMode
	local SmoothRotation
	local MultiSwing
	local BypassMode
	local Particles, Boxes, AttackDelay = {}, {}, tick()
	local lastTargets = {}
	local rotateAngle = 0
	local Hitreg
	local AttackRemote = {FireServer = function() end}
	task.spawn(function()
		for _ = 1, 10 do
			local ok, remote = pcall(function()
				return bedwars.Client:Get('SwordHit').instance
			end)
			if ok and remote then
				AttackRemote = remote
				return
			end
			task.wait(0.5)
		end
	end)

	local function getSwingReach()
		return (bedwars.CombatConstant and bedwars.CombatConstant.RAYCAST_SWORD_CHARACTER_DISTANCE) or 14.4
	end

	local function canAttack(target)
		if not (target and target.RootPart and target.Character and target.Character:IsDescendantOf(workspace)) then
			return false
		end
		local delta = target.RootPart.Position - entitylib.character.RootPart.Position
		if delta.Magnitude < 0.001 or delta.Magnitude > AttackRange.Value then
			return false
		end
		if Targets and Targets.Walls.Enabled then
			local origin = gameCamera.CFrame.Position
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = {lplr.Character, gameCamera}
			local res = workspace:Raycast(origin, delta.Unit * (delta.Magnitude + 2), params)
			local hit = res and res.Instance
			if not (hit and (hit == target.Character or hit:IsDescendantOf(target.Character))) then
				return false
			end
		end
		return true
	end

	local function hitregCount()
		if not Hitreg or Hitreg.Value == 'Default' then return 1 end
		if Hitreg.Value == 'Low' then return 5 end
		if Hitreg.Value == 'Medium' then return 15 end
		return 35
	end

	local function fireAttack(payload, count)
		local ok = pcall(function()
			for _ = 1, count do
				AttackRemote:FireServer(payload)
			end
		end)
	end

	local function silentAttack(target)
		local actualRoot = target.Character.PrimaryPart or target.RootPart
		if not actualRoot then return end
		local selfpos = entitylib.character.RootPart.Position
		local targetpos = actualRoot.Position
		if MovementCorrection.Enabled then
			local observed = prediction.GetObserved(target.RootPart)
			local velocity = observed and observed.Velocity or target.RootPart.AssemblyLinearVelocity
			if velocity and velocity.Magnitude > 0.5 then
				targetpos = targetpos + velocity * ((lplr:GetNetworkPing() or 0) + 0.1)
			end
		end
		local delta = targetpos - selfpos
		if delta.Magnitude < 0.001 then return end
		local dir = delta.Unit
		local reach = getSwingReach()
		local pos = selfpos + dir * math.max(delta.Magnitude - (reach - 0.1), 0)
		bedwars.SwordController.lastAttack = workspace:GetServerTimeNow()
		store.attackReach = (delta.Magnitude * 100) // 1 / 100
		store.attackReachUpdate = tick() + 1
		local tool = store.hand.tool
		local meta = tool and bedwars.ItemMeta[tool.Name]
		if meta and meta.sword then
			bedwars.SwordController:playSwordEffect(meta, 0)
		end
		fireAttack({
			weapon = tool,
			chargeRatio = 0,
			entityInstance = target.Character,
			validate = {
				raycast = {
					cameraPosition = {value = pos},
					cursorDirection = {value = dir}
				},
				targetPosition = {value = targetpos},
				selfPosition = {value = pos}
			}
		}, hitregCount())
	end

	local function getEmitter(part)
		return part and part:FindFirstChildOfClass('ParticleEmitter')
	end

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
					local ok, err = pcall(function()
						if getAttackData() then
							local plrs = entitylib.AllPosition({
								Range = SwingRange.Value,
								Wallcheck = Targets.Walls.Enabled or nil,
								Part = 'RootPart',
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Limit = Max.Value + 10
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
									local swingCount = MultiSwing.Enabled and math.min(#attacked, 3) or 1

									for swing = 1, swingCount do
										if AttackDelay < tick() then
											local cpsValue = CPS.GetRandomValue()
											AttackDelay = tick() + (1 / cpsValue) + (math.random(-10, 10) / 1000)

											if BypassMode.Value == 'Random Delay' then
												AttackDelay = AttackDelay + (math.random(0, 15) / 1000)
											end

if attacked[swing] then
												local target = attacked[swing].Entity
												if canAttack(target) then
													pcall(silentAttack, target)
												end
											end
										end
									end
								end

								for _, data in attacked do
									lastTargets[data.Entity] = tick()
								end
							end
						end
					end)
					if not ok then warn('[skidv5] killaura attack: '..tostring(err)) end

					pcall(function()
						for i, v in Boxes do
							if attacked[i] and attacked[i].Entity and attacked[i].Entity.RootPart then
								v.Adornee = attacked[i].Entity.RootPart
								v.Color3 = BoxSwingColor.Object.Value
								v.Transparency = 0.5
							else
								v.Adornee = nil
							end
						end
					end)

					pcall(function()
						for i, v in Particles do
							local em = getEmitter(v)
							if em then
								em.Enabled = attacked[i] ~= nil
								if attacked[i] and attacked[i].Entity and attacked[i].Entity.RootPart then
									v.Position = attacked[i].Entity.RootPart.Position
								else
									v.Position = Vector3.new(9e9, 9e9, 9e9)
								end
							end
						end
					end)

					pcall(function()
						if Face.Enabled and attacked[1] then
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
					end)

					task.wait()
				until not Killaura.Enabled
			else
				lastTargets = {}
				for _, v in Boxes do pcall(function() v:Destroy() end) end
				for _, v in Particles do pcall(function() v:Destroy() end) end
				table.clear(Boxes)
				table.clear(Particles)
			end
		end,
		Tooltip = 'Attack players around you\nwithout aiming at them.'
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
		Max = 50,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AttackRange = Killaura:CreateSlider({
		Name = 'Attack range',
		Min = 1,
		Max = 50,
		Default = 18,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	AngleSlider = Killaura:CreateSlider({
		Name = 'Max angle',
		Min = 1,
		Max = 360,
		Default = 180
	})
	Max = Killaura:CreateSlider({
		Name = 'Max targets',
		Min = 1,
		Max = 20,
		Default = 15
	})
	SortMode = Killaura:CreateDropdown({
		Name = 'Sort targets',
		List = {'Distance', 'Health', 'Angle', 'None'},
		Default = 'Distance'
	})
	SmoothRotation = Killaura:CreateToggle({
		Name = 'Smooth rotation',
		Tooltip = 'Smoothly rotates toward targets\ninstead of snapping instantly'
	})
	MultiSwing = Killaura:CreateToggle({
		Name = 'Multi swing',
		Tooltip = 'Attacks multiple targets per tick'
	})
	MovementCorrection = Killaura:CreateToggle({
		Name = 'Movement correction',
		Default = true,
		Tooltip = 'Leads the target by your ping so\nattacks land on moving players'
	})
	Hitreg = Killaura:CreateDropdown({
		Name = 'Hitreg',
		List = {'Default', 'Low', 'Medium', 'High'},
		Default = 'Default',
		Tooltip = 'Number of attack packets sent per hit.\nDefault: 1 | Low: 5 | Medium: 15 | High: 35'
	})
	BypassMode = Killaura:CreateDropdown({
		Name = 'Bypass mode',
		List = {'None', 'Random Delay'},
		Default = 'None',
		Tooltip = 'Random Delay: adds random delays between attacks'
	})
	Mouse = Killaura:CreateToggle({Name = 'Require mouse down'})
	Killaura:CreateToggle({
		Name = 'Show target',
		Function = function(callback)
			BoxSwingColor.Object.Visible = callback
			BoxAttackColor.Object.Visible = callback
			if callback then
				for i = 1, 20 do
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
				for i = 1, 20 do
					local part = Instance.new('Part')
					part.Size = Vector3.new(2, 4, 2)
					part.Anchored = true
					part.CanCollide = false
					part.Transparency = 1
					part.Parent = gameCamera
					local emitter = Instance.new('ParticleEmitter')
					emitter.Enabled = false
					emitter.Parent = part
					Particles[i] = part
				end
			else
				for _, v in Particles do
					v:Destroy()
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
				local em = getEmitter(v)
				if em then em.Color = ColorSequence.new(Color3.fromHSV(hue, sat, val), ParticleColor2.Object.Value) end
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
				local em = getEmitter(v)
				if em then em.Color = ColorSequence.new(ParticleColor1.Object.Value, Color3.fromHSV(hue, sat, val)) end
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
				local em = getEmitter(v)
				if em then em.Size = NumberSequence.new(val) end
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

				pcall(bedwars.breakBlock, v, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealth or nil, AutoTool.Enabled, Wallcheck.Enabled, 'Health', not route)
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
				if block:GetAttribute('Team'..(lplr:GetAttribute('Team') or 0)..'NoBreak') then continue end
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
			if bed:GetAttribute('Team'..(lplr:GetAttribute('Team') or 0)..'NoBreak') then continue end
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

				pcall(bedwars.breakBlock, block, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealth or nil, AutoTool.Enabled, false, 'Health', false)
				chainCount += 1
				task.wait(BreakSpeed.Value)
			end

			-- actually break the bed after clearing the path
			if Breaker.Enabled and bed.Parent then
				pcall(bedwars.breakBlock, bed, Effect.Enabled, Animation.Enabled, CustomHealth.Enabled and customHealth or nil, AutoTool.Enabled, false, 'Health', false)
				chainCount += 1
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
					local uid = obj:GetAttribute('PlacedByUserId')
					local player = uid and playersService:GetPlayerByUserId(uid)
					if player and player:GetAttribute('Team') ~= lplr:GetAttribute('Team') then
						table.insert(tab, obj)
					end
				end)
			end)
			local hives = collection('beehive', Breaker, function(tab, obj)
				task.delay(0.1, function()
					if not Breaker.Enabled or not obj.Parent then return end
					local uid = obj:GetAttribute('PlacedByUserId')
					local player = uid and playersService:GetPlayerByUserId(uid)
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
	local Speed
	local VerticalSpeed
	local WallCheck
	local Expand
	local PlaceDelay
	local PauseInterval
	local PauseDuration
	local up, down = 0, 0
	local origWalkSpeed = 16
	local veloThread

	local adjacent = {}
	for x = -3, 3, 3 do
		for y = -3, 3, 3 do
			for z = -3, 3, 3 do
				local vec = Vector3.new(x, y, z)
				if vec ~= Vector3.zero then
					table.insert(adjacent, vec)
				end
			end
		end
	end

	local function roundPos(vec)
		return Vector3.new(math.round(vec.X / 3) * 3, math.round(vec.Y / 3) * 3, math.round(vec.Z / 3) * 3)
	end

	local function getPlacedBlock(pos)
		if not pos then return end
		local roundedPosition = bedwars.BlockController:getBlockPosition(pos)
		return bedwars.BlockController:getStore():getBlockAt(roundedPosition), roundedPosition
	end

	local function checkAdjacent(pos)
		for _, v in adjacent do
			if getPlacedBlock(pos + v) then
				return true
			end
		end
		return false
	end

	local function blockProximity(pos)
		local mag, returned = 60
		for x = -21, 21, 3 do
			for y = -21, 21, 3 do
				for z = -21, 21, 3 do
					local v = pos + Vector3.new(x, y, z)
					local block = getPlacedBlock(v)
					if block then
						local blockpos = roundPos(v)
						local startpos = blockpos - Vector3.new(3, 3, 3)
						local endpos = blockpos + Vector3.new(3, 3, 3)
						local check = blockpos + (pos - blockpos).Unit * 100
						local near = Vector3.new(math.clamp(check.X, startpos.X, endpos.X), math.clamp(check.Y, startpos.Y, endpos.Y), math.clamp(check.Z, startpos.Z, endpos.Z))
						local newmag = (pos - near).Magnitude
						if newmag < mag then
							mag, returned = newmag, near
						end
					end
				end
			end
		end
		return returned
	end

	local function getScaffoldBlock()
		if store.hand.toolType == 'block' and store.hand.tool then
			return store.hand.tool.Name
		end
		for _, item in store.inventory.inventory.items do
			if bedwars.ItemMeta[item.itemType] and bedwars.ItemMeta[item.itemType].block then
				return item.itemType
			end
		end
		return nil
	end

	local function placeBlockSmart(pos)
		local wool = getScaffoldBlock()
		if not wool then return end
		local block, blockpos = getPlacedBlock(pos)
		if not block then
			local placePos = checkAdjacent(pos) and pos or blockProximity(pos)
			if placePos then
				bedwars.placeBlock(placePos, wool)
			end
		end
	end

	BlockFly = vape.Categories.Blatant:CreateModule({
		Name = 'BlockFly',
		Function = function(callback)
			if callback then
				origWalkSpeed = entitylib.isAlive and entitylib.character.Humanoid.WalkSpeed or 16
				local lastPause = tick()
				local pausing = false
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

				-- velocity spoof thread: keeps reported velocity looking normal
				veloThread = task.spawn(function()
					while BlockFly.Enabled do
						if entitylib.isAlive then
							local root = entitylib.character.RootPart
							local hum = entitylib.character.Humanoid
							if root and hum then
								local moveDir = hum.MoveDirection
								if moveDir.Magnitude > 0 then
									-- report walkspeed velocity in move direction
									root.AssemblyLinearVelocity = Vector3.new(
										moveDir.X * 16,
										math.clamp(root.AssemblyLinearVelocity.Y, -50, 50),
										moveDir.Z * 16
									)
								end
							end
						end
						task.wait(0.05)
					end
				end)

				repeat
					-- periodic pause: stop briefly then continue
					if PauseInterval.Value > 0 and tick() - lastPause >= PauseInterval.Value then
						pausing = true
						if entitylib.isAlive then
							local hum = entitylib.character.Humanoid
							if hum then hum.WalkSpeed = 0 end
						end
						task.wait(PauseDuration.Value)
						if entitylib.isAlive then
							local hum = entitylib.character.Humanoid
							if hum then hum.WalkSpeed = origWalkSpeed end
						end
						lastPause = tick()
						pausing = false
					end

					if not pausing and entitylib.isAlive and isnetworkowner(entitylib.character.RootPart) then
						local root = entitylib.character.RootPart
						local hum = entitylib.character.Humanoid
						local moveDir = hum.MoveDirection

						-- place blocks
						for i = Expand.Value, 1, -1 do
							local blockPos = roundPos(root.Position - Vector3.new(0, hum.HipHeight + 1.5, 0) + moveDir * (i * 3))
							pcall(placeBlockSmart, blockPos)
						end

						-- horizontal via Move: direction * speed factor, the Humanoid handles physics
						if moveDir.Magnitude > 0 then
							local speedFactor = math.clamp(Speed.Value / 16, 1, 6)
							hum:Move(moveDir * speedFactor, false)
						end

						-- vertical via JumpPower
						if up > 0 then
							hum:ChangeState(Enum.HumanoidStateType.Jumping)
							root.AssemblyLinearVelocity = Vector3.new(
								root.AssemblyLinearVelocity.X,
								math.max(VerticalSpeed.Value, 50),
								root.AssemblyLinearVelocity.Z
							)
						elseif down < 0 then
							root.AssemblyLinearVelocity = Vector3.new(
								root.AssemblyLinearVelocity.X,
								-math.max(VerticalSpeed.Value, 50),
								root.AssemblyLinearVelocity.Z
							)
						end

						-- wall check: stop if about to hit
						if WallCheck.Enabled and moveDir.Magnitude > 0 then
							local rayParams = RaycastParams.new()
							rayParams.FilterDescendantsInstances = {lplr.Character, gameCamera}
							rayParams.RespectCanCollide = true
							local ray = workspace:Raycast(root.Position, moveDir * 3, rayParams)
							if ray then
								hum.WalkSpeed = 0
							end
						end
					end
					task.wait(PlaceDelay.Value)
				until not BlockFly.Enabled
			else
				up, down = 0, 0
				if veloThread then task.cancel(veloThread) veloThread = nil end
				if entitylib.isAlive then
					local hum = entitylib.character.Humanoid
					if hum then
						hum.WalkSpeed = origWalkSpeed
					end
				end
			end
		end,
		Tooltip = 'Fly while placing blocks below you\nlike scaffold but in the air'
	})
	Speed = BlockFly:CreateSlider({
		Name = 'Speed',
		Min = 16,
		Max = 100,
		Default = 50,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
	VerticalSpeed = BlockFly:CreateSlider({
		Name = 'Vertical Speed',
		Min = 50,
		Max = 200,
		Default = 100,
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
	PauseInterval = BlockFly:CreateSlider({
		Name = 'Pause interval',
		Min = 0,
		Max = 10,
		Default = 3,
		Decimal = 10,
		Suffix = 'sec',
		Tooltip = 'How often to pause briefly (0 = never)'
	})
	PauseDuration = BlockFly:CreateSlider({
		Name = 'Pause duration',
		Min = 0.1,
		Max = 1,
		Default = 0.3,
		Decimal = 10,
		Suffix = 'sec',
		Tooltip = 'How long to stop each pause'
	})
end)

run(function()
	local NoFall
	local GroundSnap

	NoFall = vape.Categories.Blatant:CreateModule({
		Name = 'NoFall',
		Function = function(callback)
			if callback then
				local groundHit = bedwars.Handler:Get('GroundHit')
				local tracked = 0

				NoFall:Clean(runService.PostSimulation:Connect(function()
					if entitylib.isAlive and store.matchState == 1 then
						local root = entitylib.character.RootPart
						local velo = root.AssemblyLinearVelocity
						if tracked < -45 then
							if GroundSnap.Enabled then
								local pos = root.Position
								local params = RaycastParams.new()
								params.FilterDescendantsInstances = {lplr.Character, gameCamera}
								params.RespectCanCollide = true
								local ray = workspace:Raycast(pos, Vector3.new(0, -50, 0), params)
								if ray then
									local groundY = math.round(ray.Position.Y / 3) * 3
									local groundPos = Vector3.new(math.round(pos.X / 3) * 3, groundY + 3, math.round(pos.Z / 3) * 3)
									root.CFrame = CFrame.new(groundPos) * (root.CFrame - root.CFrame.Position)
								end
							end
							root.AssemblyLinearVelocity = Vector3.new(0, 2.5, 0)
							entitylib.character.Humanoid:ChangeState(Enum.HumanoidStateType.Landed)
							runService.PreRender:Wait()
							groundHit:Fire('SendToServer', nil, Vector3.new(0, tracked, 0), workspace:GetServerTimeNow())
						end
						tracked = velo.Y
					end
				end))
			end
		end,
		Tooltip = 'Prevents fall damage.\nGround Snap teleports to the block below.'
	})
	GroundSnap = NoFall:CreateToggle({
		Name = 'Ground Snap',
		Default = true,
		Tooltip = 'Teleports to the block below before firing\nGroundHit to better bypass anti-cheat'
	})
end)

run(function()
	local BlockHit
	local BlockChance
	local BlockDelay
	local BlockDuration
	local BlockMode
	local RequireEnemy
	local BlockRange
	local animState = nil
	local blockTick = tick()

	local function getBlockItem()
		for _, item in store.inventory.inventory.items do
			if bedwars.ItemMeta[item.itemType] and bedwars.ItemMeta[item.itemType].block then
				return item
			end
		end
		return nil
	end

local function setGrip(tool, forward, right, up)
	if not tool then return end
	pcall(function() tool.GripForward = forward or Vector3.new(0, 0, -1) end)
	pcall(function() tool.GripRight = right or Vector3.new(1, 0, 0) end)
	pcall(function() tool.GripUp = up or Vector3.new(0, 1, 0) end)
end

	local function setToolAnim(tool, state)
		if not tool then return end
		local anim = tool:FindFirstChild('toolanim')
		if not anim then
			anim = Instance.new('StringValue')
			anim.Name = 'toolanim'
			anim.Parent = tool
		end
		anim.Value = state or 'None'
	end

	local function isHoldingSword()
		return store.hand.tool and store.hand.toolType == 'sword'
	end

	local function hasEnemyNearby()
		if not RequireEnemy.Enabled then return true end
		if not entitylib.isAlive then return false end
		local selfpos = entitylib.character.RootPart.Position
		local plrs = entitylib.AllPosition({
			Range = BlockRange.Value,
			Part = 'RootPart',
			Players = true,
			Limit = 1
		})
		return #plrs > 0
	end

	BlockHit = vape.Categories.Combat:CreateModule({
		Name = 'BlockHit',
		Function = function(callback)
			if callback then
				blockTick = tick()
				repeat
					if isHoldingSword() and hasEnemyNearby() and entitylib.isAlive then
						local tool = store.hand.tool
						if tool and canSwing() then
							local r = math.random(1, 100)
							if r <= BlockChance.Value then
								setToolAnim(tool, 'Block')
								setGrip(tool, Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, 1, 0))
								task.wait(BlockDuration.Value / 1000)
								setToolAnim(tool, 'Slash')
								setGrip(tool)
								task.wait(BlockDelay.Value / 1000)
							end
						end
					end
					task.wait()
				until not BlockHit.Enabled
			else
				local tool = store.hand.tool
				if tool then
					setToolAnim(tool, 'None')
					setGrip(tool)
				end
			end
		end,
		Tooltip = 'Block-hit animation for damage reduction\nand knockback resistance'
	})
	BlockChance = BlockHit:CreateSlider({
		Name = 'Block chance',
		Min = 1,
		Max = 100,
		Default = 50,
		Suffix = '%'
	})
	BlockDelay = BlockHit:CreateSlider({
		Name = 'Block delay',
		Min = 10,
		Max = 200,
		Default = 50,
		Suffix = 'ms'
	})
	BlockDuration = BlockHit:CreateSlider({
		Name = 'Block duration',
		Min = 10,
		Max = 200,
		Default = 80,
		Suffix = 'ms'
	})
	BlockRange = BlockHit:CreateSlider({
		Name = 'Enemy range',
		Min = 5,
		Max = 30,
		Default = 18,
		Suffix = function(val) return val == 1 and 'stud' or 'studs' end
	})
	RequireEnemy = BlockHit:CreateToggle({
		Name = 'Require enemy nearby',
		Default = true,
		Tooltip = 'Only block-hit when enemies are within range'
	})
end)

run(function()
	local ProjectileAura
	local Targets
	local AuraRange
	local AuraFOV
	local SortMode
	local AutoShoot
	local ChargeTime
	local PredictMovement
	local TargetsBox, AuraParticles = {}, {}

	local function getProjectileItem()
		for _, item in store.inventory.inventory.items do
			local meta = bedwars.ItemMeta[item.itemType]
			if meta and meta.projectileSource then
				local projSource = meta.projectileSource
				if table.find(projSource.ammoItemTypes, 'arrow') then
					return item, projSource
				end
			end
		end
		return nil, nil
	end

	local function predictPosition(target, dt)
		if not PredictMovement.Enabled then return target.RootPart.Position end
		local vel = target.RootPart.Velocity
		local gravity = workspace.Gravity * Vector3.new(0, -0.5, 0)
		return target.RootPart.Position + vel * dt + gravity * dt * dt
	end

	ProjectileAura = vape.Categories.Combat:CreateModule({
		Name = 'ProjectileAura',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive and store.hand.tool then
						local bow, bowMeta = getProjectileItem()
						if bow and bowMeta then
							local selfpos = entitylib.character.RootPart.Position
							local plrs = entitylib.AllPosition({
								Range = AuraRange.Value,
								Wallcheck = Targets.Walls.Enabled or nil,
								Part = TargetPart and TargetPart.Value or 'RootPart',
								Players = Targets.Players.Enabled,
								NPCs = Targets.NPCs.Enabled,
								Limit = 5
							})

							if #plrs > 0 then
								local facing = entitylib.character.RootPart.CFrame.LookVector * Vector3.new(1, 0, 1)
								local filtered = {}
								for _, v in plrs do
									local delta = (v.RootPart.Position - selfpos) * Vector3.new(1, 0, 1)
									if delta.Magnitude > 0 then
										local angle = math.acos(math.clamp(facing:Dot(delta.Unit), -1, 1))
										if angle <= math.rad(AuraFOV.Value / 2) then
											table.insert(filtered, v)
										end
									end
								end

								if SortMode.Value == 'Distance' then
									table.sort(filtered, function(a, b)
										return (a.RootPart.Position - selfpos).Magnitude < (b.RootPart.Position - selfpos).Magnitude
									end)
								elseif SortMode.Value == 'Health' then
									table.sort(filtered, function(a, b)
										return a.Humanoid.Health < b.Humanoid.Health
									end)
								end

								if #filtered > 0 then
									local target = filtered[1]
									local targetPos = predictPosition(target, 0.5)
									local aimDir = (targetPos - selfpos).Unit

									targetinfo.Targets[target] = tick() + 1

									for i, v in TargetsBox do
										v.Adornee = filtered[i] and filtered[i].RootPart or nil
									end

									if AutoShoot.Enabled then
										local tool = store.hand.tool
										if tool and tool == bow.tool then
											switchItem(tool, 0.05)
											task.wait(ChargeTime.Value / 1000)
											local projType = bowMeta.projectileType('arrow')
											local projSpeed = bedwars.ProjectileMeta[projType] and bedwars.ProjectileMeta[projType].launchVelocity or 100
											local shootPos = (bedwars.ProjectileController:getLaunchPosition(tool) or selfpos)
											local shootDir = (targetPos - shootPos).Unit

											local gravity = 196.2
											local projMeta = bowMeta.projectileType and bowMeta
											if projMeta then
												local pmeta = projMeta.getProjectileMeta and projMeta:getProjectileMeta() or nil
												if pmeta then
													gravity = (pmeta.gravitationalAcceleration or 196.2) * (projMeta.gravityMultiplier or 1)
												end
											end

											local calc = prediction.SolveTrajectory(
												shootPos, projSpeed, gravity,
												targetPos,
												target.RootPart.Velocity,
												workspace.Gravity, target.HipHeight,
												target.Jumping and 42.6 or nil,
												nil, target.Humanoid.FloorMaterial == Enum.Material.Air or math.abs(target.RootPart.Velocity.Y) > 0.01,
												target.RootPart.Position, target.RootPart, nil, true
											)

											if calc then
												local lookDir = (calc - shootPos).Unit
												local shootCF = CFrame.lookAlong(shootPos, lookDir)
												pcall(function()
													local projRemote = bedwars.Handler:Get('ProjectileFire').Remote.instance
													projRemote:InvokeServer(
														tool, projType, projType,
														shootCF.Position, calc,
														lookDir * projSpeed,
														httpService:GenerateGUID(true),
														{drawDurationSeconds = 1},
														workspace:GetServerTimeNow() - 0.045
													)
												end)
											end

											task.wait(0.3)
										end
									end
								else
									for _, v in TargetsBox do
										v.Adornee = nil
									end
								end
							else
								for _, v in TargetsBox do
									v.Adornee = nil
								end
							end
						end
					end
					task.wait()
				until not ProjectileAura.Enabled
			else
				for _, v in TargetsBox do
					v.Adornee = nil
				end
			end
		end,
		Tooltip = 'Automatically aims and fires\nprojectiles at nearby enemies'
	})
	Targets = ProjectileAura:CreateTargets({Players = true, Walls = true})
	AuraRange = ProjectileAura:CreateSlider({
		Name = 'Range',
		Min = 5,
		Max = 100,
		Default = 50,
		Suffix = function(val) return val == 1 and 'stud' or 'studs' end
	})
	AuraFOV = ProjectileAura:CreateSlider({
		Name = 'FOV',
		Min = 30,
		Max = 360,
		Default = 180
	})
	TargetPart = ProjectileAura:CreateDropdown({
		Name = 'Target part',
		List = {'RootPart', 'Head', 'HumanoidRootPart'},
		Default = 'RootPart'
	})
	SortMode = ProjectileAura:CreateDropdown({
		Name = 'Sort targets',
		List = {'Distance', 'Health', 'None'},
		Default = 'Distance'
	})
	AutoShoot = ProjectileAura:CreateToggle({
		Name = 'Auto shoot',
		Default = true,
		Tooltip = 'Automatically charges and fires\nat the nearest target'
	})
	ChargeTime = ProjectileAura:CreateSlider({
		Name = 'Charge time',
		Min = 0,
		Max = 500,
		Default = 100,
		Suffix = 'ms'
	})
	PredictMovement = ProjectileAura:CreateToggle({
		Name = 'Predict movement',
		Default = true,
		Tooltip = 'Accounts for target velocity\nwhen calculating aim'
	})
	ProjectileAura:CreateToggle({
		Name = 'Show target',
		Function = function(callback)
			for _, v in TargetsBox do
				v.Object.Visible = callback
			end
			if callback then
				for i = 1, 5 do
					if not TargetsBox[i] then
						local box = Instance.new('BoxHandleAdornment')
						box.Adornee = nil
						box.AlwaysOnTop = true
						box.Size = Vector3.new(3, 5, 3)
						box.CFrame = CFrame.new(0, -0.5, 0)
						box.ZIndex = 0
						box.Parent = vape.gui
						TargetsBox[i] = box
					end
				end
			else
				for _, v in TargetsBox do
					v:Destroy()
				end
				table.clear(TargetsBox)
			end
		end
	})
end)

run(function()
	local SwordAnims
	local AnimStyle
	local AnimSpeed
	local AnimIntensity
	local OnlyOnAttack
	local ViewMode
	local oldSwing
	local animToken = 0
	local bases = {}
	local running = false

	local function getViewmodelWrist()
		local vm = gameCamera:FindFirstChild('Viewmodel')
		if vm and vm:FindFirstChild('RightHand') then
			return vm.RightHand:FindFirstChild('RightWrist')
		end
		return nil
	end

	local function getCharacterWrist()
		local char = lplr.Character
		if char then
			local hand = char:FindFirstChild('RightHand')
			if hand then
				return hand:FindFirstChild('RightWrist')
			end
		end
		return nil
	end

	local function getTargets()
		local targets = {}
		local mode = ViewMode and ViewMode.Value or 'Viewmodel'
		if mode ~= 'Character' then
			local wrist = getViewmodelWrist()
			if wrist then targets[wrist] = true end
		end
		if mode ~= 'Viewmodel' then
			local wrist = getCharacterWrist()
			if wrist then targets[wrist] = true end
		end
		return targets
	end

	local function playAnimation(style, speed, intensity)
		local targets = getTargets()
		local count = 0
		for _ in targets do count += 1 end
		if count == 0 then return end
		bases = {}
		for wrist in targets do
			bases[wrist] = wrist.C1
		end
		local token = animToken + 1
		animToken = token
		running = true
		local function isActive()
			return running and SwordAnims.Enabled and token == animToken
		end
		local function applyCF(cf)
			for wrist, base in bases do
				pcall(function()
					wrist.C1 = base * cf
				end)
			end
		end

		if style == 'BlockHit' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 10
					local phase = (math.sin(t) + 1) / 2
					local slash = CFrame.Angles(math.rad(-60 * intensity), 0, math.rad(-30 * intensity))
					local block = CFrame.Angles(0, 0, math.rad(90 * intensity))
					applyCF(slash:Lerp(block, phase))
				end
			end)

		elseif style == 'Spam' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 15
					local rx = math.sin(t * 1.3) * 40 * intensity
					local ry = math.cos(t * 0.9) * 25 * intensity
					local rz = math.sin(t * 2.1) * 35 * intensity
					applyCF(CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz)))
				end
			end)

		elseif style == 'Smooth' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 4
					local swing = math.sin(t) * intensity
					local rx = swing * 70
					local rz = math.cos(t * 0.5) * 20 * intensity
					applyCF(CFrame.Angles(math.rad(rx), 0, math.rad(rz)))
				end
			end)

		elseif style == 'Snap' then
			task.spawn(function()
				while isActive() do
					applyCF(CFrame.Angles(math.rad(-80 * intensity), 0, math.rad(40 * intensity)))
					task.wait(0.05 / speed)
					if not isActive() then break end
					applyCF(CFrame.Angles(math.rad(30 * intensity), 0, math.rad(-20 * intensity)))
					task.wait(0.08 / speed)
				end
			end)

		elseif style == 'Circular' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 6
					local rx = math.cos(t) * 45 * intensity
					local ry = math.sin(t) * 30 * intensity
					local rz = math.sin(t * 0.7) * 20 * intensity
					applyCF(CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz)))
				end
			end)

		elseif style == 'Jitter' then
			task.spawn(function()
				while isActive() do
					local rx = (math.random() - 0.5) * 30 * intensity
					local ry = (math.random() - 0.5) * 20 * intensity
					local rz = (math.random() - 0.5) * 25 * intensity
					applyCF(CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz)))
					task.wait(math.random(1, 3) / (speed * 60))
				end
			end)

		elseif style == 'Vertical' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 5
					local phase = math.sin(t)
					local rx = phase * 80 * intensity
					local rz = math.abs(phase) * -30 * intensity
					applyCF(CFrame.Angles(math.rad(rx), 0, math.rad(rz)))
				end
			end)

		elseif style == 'Spin' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 8
					local rx = math.sin(t * 2) * 25 * intensity
					local ry = (t % (math.pi * 2)) * intensity
					local rz = math.cos(t) * 15 * intensity
					applyCF(CFrame.Angles(math.rad(rx), ry, math.rad(rz)))
				end
			end)

		elseif style == 'FigureEight' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 5
					local rx = math.sin(t) * 55 * intensity
					local ry = math.sin(t * 2) * 35 * intensity
					local rz = math.cos(t) * 20 * intensity
					applyCF(CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz)))
				end
			end)

		elseif style == 'Diagonal' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 5
					local phase = math.sin(t)
					local rx = phase * 70 * intensity
					local ry = math.abs(math.cos(t)) * 45 * intensity
					local rz = phase * 30 * intensity
					applyCF(CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz)))
				end
			end)

		elseif style == 'Twirl' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 10
					local rz = math.sin(t) * 180 * intensity
					local rx = math.cos(t * 1.5) * 20 * intensity
					applyCF(CFrame.Angles(math.rad(rx), 0, math.rad(rz)))
				end
			end)

		elseif style == 'Windmill' then
			task.spawn(function()
				local t = 0
				while isActive() do
					local dt = task.wait()
					t = t + dt * speed * 6
					local rx = math.cos(t) * 120 * intensity
					local ry = math.sin(t) * 40 * intensity
					applyCF(CFrame.Angles(math.rad(rx), math.rad(ry), 0))
				end
			end)
		end
	end

	local function stopAnimation()
		running = false
		animToken += 1
		for wrist, base in bases do
			pcall(function()
				wrist.C1 = base
			end)
		end
		bases = {}
	end

	SwordAnims = vape.Categories.Combat:CreateModule({
		Name = 'SwordAnimations',
		Function = function(callback)
			if callback then
				oldSwing = bedwars.SwordController.swingSwordAtMouse
				bedwars.SwordController.swingSwordAtMouse = function(self, ...)
					stopAnimation()
					playAnimation(AnimStyle.Value, AnimSpeed.Value, AnimIntensity.Value)
					return oldSwing(self, ...)
				end
			else
				if oldSwing then
					bedwars.SwordController.swingSwordAtMouse = oldSwing
					oldSwing = nil
				end
				stopAnimation()
			end
		end,
		Tooltip = 'Custom sword animations\nwith 12 different styles'
	})
	AnimStyle = SwordAnims:CreateDropdown({
		Name = 'Animation style',
		List = {'BlockHit', 'Spam', 'Smooth', 'Snap', 'Circular', 'Jitter', 'Vertical', 'Spin', 'FigureEight', 'Diagonal', 'Twirl', 'Windmill'},
		Default = 'BlockHit',
		Tooltip = 'BlockHit: block-slash alternation\nSpam: rapid random rotations\nSmooth: interpolated swing arc\nSnap: instant snap between poses\nCircular: continuous orbital motion\nJitter: small random offsets\nVertical: overhead chopping motion\nSpin: full wrist spin\nFigureEight: figure-eight motion\nDiagonal: angled slash\nTwirl: fast wrist twirl\nWindmill: large overhead windmill'
	})
	AnimSpeed = SwordAnims:CreateSlider({
		Name = 'Animation speed',
		Min = 0.5,
		Max = 3,
		Default = 1,
		Decimal = 10
	})
	AnimIntensity = SwordAnims:CreateSlider({
		Name = 'Animation intensity',
		Min = 0.2,
		Max = 2,
		Default = 1,
		Decimal = 10
	})
	ViewMode = SwordAnims:CreateDropdown({
		Name = 'View mode',
		List = {'Viewmodel', 'Character', 'Both'},
		Default = 'Viewmodel',
		Tooltip = 'Viewmodel: first-person viewmodel\nCharacter: your 3rd person character rig\nBoth: animate both at once'
	})
	OnlyOnAttack = SwordAnims:CreateToggle({
		Name = 'Only on attack',
		Default = true,
		Tooltip = 'Only animate when swinging sword\n(false = continuous animation)'
	})
	SwordAnims:CreateToggle({
		Name = 'Continuous loop',
		Default = false,
		Function = function(callback)
			if callback and SwordAnims.Enabled then
				OnlyOnAttack.Object.Visible = false
				playAnimation(AnimStyle.Value, AnimSpeed.Value, AnimIntensity.Value)
			else
				OnlyOnAttack.Object.Visible = true
			end
		end,
		Tooltip = 'Run animation continuously\ninstead of per-swing'
	})
end)

run(function()
	local HitSound
	local SoundList
	local Volume
	local Pitch

	local sounds = {
		'rbxassetid://14736249347',
		'rbxassetid://8200754399',
		'rbxassetid://6993372814',
		'rbxassetid://279227693',
		'rbxassetid://279229192',
		'rbxassetid://287112271',
		'rbxassetid://388723916',
		'rbxassetid://388726667',
		'rbxassetid://405194080',
		'rbxassetid://481088553',
		'rbxassetid://484200742',
		'rbxassetid://83690472549256',
		'rbxassetid://107176344504758',
		'rbxassetid://111090572475133',
		'rbxassetid://113267949064300',
		'rbxassetid://131326339350805',
	}

	local function getSound()
		local val = SoundList.Value
		if val ~= '' and val:find('rbxassetid') then
			return val
		end
		return sounds[math.random(1, #sounds)]
	end

	HitSound = vape.Categories.Render:CreateModule({
		Name = 'HitSound',
		Function = function(callback)
			if callback then
				HitSound:Clean(vapeEvents.EntityDamageEvent:Connect(function()
					local sound = Instance.new('Sound')
					sound.SoundId = getSound()
					sound.Volume = Volume.Value
					sound.PlaybackSpeed = Pitch.Value
					sound.Parent = gameCamera
					sound.Ended:Connect(function() sound:Destroy() end)
					sound:Play()
				end))
			end
		end,
		Tooltip = 'Plays a sound when you hit an enemy'
	})
	SoundList = HitSound:CreateTextBox({
		Name = 'Sound ID',
		Default = '',
		Placeholder = 'rbxassetid://... (blank = random)',
		Tooltip = 'Enter a Roblox sound ID\nLeave blank for random from preset list'
	})
	Volume = HitSound:CreateSlider({
		Name = 'Volume',
		Min = 0,
		Max = 2,
		Default = 1,
		Decimal = 10
	})
	Pitch = HitSound:CreateSlider({
		Name = 'Pitch',
		Min = 0.5,
		Max = 2,
		Default = 1,
		Decimal = 10
	})
end)

run(function()
	local CustomSky
	local SkyboxTop
	local SkyboxBottom
	local SkyboxLeft
	local SkyboxRight
	local SkyboxFront
	local SkyboxBack
	local SunTex
	local MoonTex
	local StarCount
	local skyObj, sunObj, moonObj, starObj

	local defaultSky = {
		SkyboxBk = 'rbxassetid://6444884337',
		SkyboxDn = 'rbxassetid://6444884785',
		SkyboxFt = 'rbxassetid://6444884337',
		SkyboxLf = 'rbxassetid://6444884337',
		SkyboxRt = 'rbxassetid://6444884337',
		SkyboxUp = 'rbxassetid://6444884785',
		SunAngularSize = 11,
		MoonAngularSize = 11,
		StarCount = 3000,
	}

	local function removeOld()
		if skyObj then pcall(function() skyObj:Destroy() end) skyObj = nil end
		if sunObj then pcall(function() sunObj:Destroy() end) sunObj = nil end
		if moonObj then pcall(function() moonObj:Destroy() end) moonObj = nil end
		if starObj then pcall(function() starObj:Destroy() end) starObj = nil end
	end

	local function applySky()
		removeOld()
		if not CustomSky.Enabled then return end

		skyObj = Instance.new('Sky')
		skyObj.SkyboxBk = SkyboxBack.Value ~= '' and SkyboxBack.Value or defaultSky.SkyboxBk
		skyObj.SkyboxDn = SkyboxBottom.Value ~= '' and SkyboxBottom.Value or defaultSky.SkyboxDn
		skyObj.SkyboxFt = SkyboxFront.Value ~= '' and SkyboxFront.Value or defaultSky.SkyboxFt
		skyObj.SkyboxLf = SkyboxLeft.Value ~= '' and SkyboxLeft.Value or defaultSky.SkyboxLf
		skyObj.SkyboxRt = SkyboxRight.Value ~= '' and SkyboxRight.Value or defaultSky.SkyboxRt
		skyObj.SkyboxUp = SkyboxTop.Value ~= '' and SkyboxTop.Value or defaultSky.SkyboxUp
		skyObj.StarCount = StarCount.Value
		skyObj.Parent = gameLighting

		if SunTex.Value ~= '' then
			sunObj = Instance.new('Sky')
			sunObj.SunTextureId = SunTex.Value
			sunObj.SunAngularSize = 21
			sunObj.Parent = gameLighting
		end

		if MoonTex.Value ~= '' then
			moonObj = Instance.new('Sky')
			moonObj.MoonTextureId = MoonTex.Value
			moonObj.MoonAngularSize = 21
			moonObj.Parent = gameLighting
		end
	end

	CustomSky = vape.Categories.Render:CreateModule({
		Name = 'CustomSky',
		Function = function(callback)
			if callback then
				applySky()
			else
				removeOld()
			end
		end,
		Tooltip = 'Replaces the skybox with custom textures'
	})
	SkyboxTop = CustomSky:CreateTextBox({
		Name = 'Top',
		Default = '',
		Placeholder = 'SkyboxUp texture ID'
	})
	SkyboxBottom = CustomSky:CreateTextBox({
		Name = 'Bottom',
		Default = '',
		Placeholder = 'SkyboxDn texture ID'
	})
	SkyboxLeft = CustomSky:CreateTextBox({
		Name = 'Left',
		Default = '',
		Placeholder = 'SkyboxLf texture ID'
	})
	SkyboxRight = CustomSky:CreateTextBox({
		Name = 'Right',
		Default = '',
		Placeholder = 'SkyboxRt texture ID'
	})
	SkyboxFront = CustomSky:CreateTextBox({
		Name = 'Front',
		Default = '',
		Placeholder = 'SkyboxFt texture ID'
	})
	SkyboxBack = CustomSky:CreateTextBox({
		Name = 'Back',
		Default = '',
		Placeholder = 'SkyboxBk texture ID'
	})
	SunTex = CustomSky:CreateTextBox({
		Name = 'Sun texture',
		Default = '',
		Placeholder = 'Sun texture ID (blank = default)'
	})
	MoonTex = CustomSky:CreateTextBox({
		Name = 'Moon texture',
		Default = '',
		Placeholder = 'Moon texture ID (blank = default)'
	})
	StarCount = CustomSky:CreateSlider({
		Name = 'Star count',
		Min = 0,
		Max = 5000,
		Default = 3000
	})
end)

run(function()
	local Fullbright
	local OldAmbient, OldBrightness

	Fullbright = vape.Categories.Render:CreateModule({
		Name = 'Fullbright',
		Function = function(callback)
			if callback then
				OldAmbient = gameLighting.Ambient
				OldBrightness = gameLighting.Brightness
				gameLighting.Ambient = Color3.fromRGB(255, 255, 255)
				gameLighting.Brightness = 3
				gameLighting.GlobalShadows = false
				gameLighting.ForceEndShadows = true

				Fullbright:Clean(gameLighting.Changed:Connect(function(prop)
					if prop == 'Ambient' then gameLighting.Ambient = Color3.fromRGB(255, 255, 255) end
					if prop == 'Brightness' then gameLighting.Brightness = 3 end
					if prop == 'GlobalShadows' then gameLighting.GlobalShadows = false end
				end))
			else
				gameLighting.Ambient = OldAmbient or Color3.fromRGB(178, 178, 178)
				gameLighting.Brightness = OldBrightness or 1
				gameLighting.GlobalShadows = true
				gameLighting.ForceEndShadows = false
			end
		end,
		Tooltip = 'Max brightness, no shadows\nSee everything clearly'
	})
end)

run(function()
	local ColorCorrection
	local Saturation
	local Contrast
	local Brightness
	local Tint
	local effect

	ColorCorrection = vape.Categories.Render:CreateModule({
		Name = 'ColorCorrection',
		Function = function(callback)
			if callback then
				effect = Instance.new('ColorCorrectionEffect')
				effect.Saturation = Saturation.Value
				effect.Contrast = Contrast.Value
				effect.Brightness = Brightness.Value
				effect.TintColor = TintColor()
				effect.Parent = gameLighting
			else
				if effect then effect:Destroy() effect = nil end
			end
		end,
		Tooltip = 'Adjust screen colors'
	})
	Saturation = ColorCorrection:CreateSlider({
		Name = 'Saturation',
		Min = -1,
		Max = 1,
		Default = 0.3,
		Decimal = 10,
		Tooltip = '-1 = grayscale, 0 = normal, 1 = oversaturated'
	})
	Contrast = ColorCorrection:CreateSlider({
		Name = 'Contrast',
		Min = -1,
		Max = 1,
		Default = 0.1,
		Decimal = 10
	})
	Brightness = ColorCorrection:CreateSlider({
		Name = 'Brightness',
		Min = -0.5,
		Max = 0.5,
		Default = 0,
		Decimal = 10
	})
	local tintColor = Color3.fromRGB(255, 255, 255)
	function TintColor()
		return tintColor
	end
	ColorCorrection:CreateToggle({
		Name = 'Warm tint',
		Default = false,
		Function = function(callback)
			tintColor = callback and Color3.fromRGB(255, 230, 210) or Color3.fromRGB(255, 255, 255)
			if effect then effect.TintColor = tintColor end
		end,
		Tooltip = 'Warm orange tint'
	})
	ColorCorrection:CreateToggle({
		Name = 'Cold tint',
		Default = false,
		Function = function(callback)
			tintColor = callback and Color3.fromRGB(210, 230, 255) or Color3.fromRGB(255, 255, 255)
			if effect then effect.TintColor = tintColor end
		end,
		Tooltip = 'Cool blue tint'
	})
end)

run(function()
	local Bloom
	local Intensity
	local Size
	local Threshold
	local effect

	Bloom = vape.Categories.Render:CreateModule({
		Name = 'Bloom',
		Function = function(callback)
			if callback then
				effect = Instance.new('BloomEffect')
				effect.Intensity = Intensity.Value
				effect.Size = Size.Value
				effect.Threshold = Threshold.Value
				effect.Parent = gameLighting
			else
				if effect then effect:Destroy() effect = nil end
			end
		end,
		Tooltip = 'Glow around bright objects'
	})
	Intensity = Bloom:CreateSlider({
		Name = 'Intensity',
		Min = 0,
		Max = 2,
		Default = 0.8,
		Decimal = 10
	})
	Size = Bloom:CreateSlider({
		Name = 'Size',
		Min = 0,
		Max = 56,
		Default = 24
	})
	Threshold = Bloom:CreateSlider({
		Name = 'Threshold',
		Min = 0,
		Max = 2,
		Default = 1,
		Decimal = 10
	})
end)

run(function()
	local SunRays
	local Intensity
	local Spread
	local effect

	SunRays = vape.Categories.Render:CreateModule({
		Name = 'SunRays',
		Function = function(callback)
			if callback then
				effect = Instance.new('SunRaysEffect')
				effect.Intensity = Intensity.Value
				effect.Spread = Spread.Value
				effect.Parent = gameLighting
			else
				if effect then effect:Destroy() effect = nil end
			end
		end,
		Tooltip = 'Light rays from the sun'
	})
	Intensity = SunRays:CreateSlider({
		Name = 'Intensity',
		Min = 0,
		Max = 1,
		Default = 0.2,
		Decimal = 10
	})
	Spread = SunRays:CreateSlider({
		Name = 'Spread',
		Min = 0,
		Max = 1,
		Default = 0.5,
		Decimal = 10
	})
end)

run(function()
	local AmbientColor
	local AmbientSky
	local AmbientOutdoor
	local effect

	AmbientColor = vape.Categories.Render:CreateModule({
		Name = 'AmbientColor',
		Function = function(callback)
			if callback then
				effect = Instance.new('ColorCorrectionEffect')
				effect.Saturation = 0
				effect.Brightness = 0
				effect.Contrast = 0
				effect.TintColor = Color3.fromRGB(255, 255, 255)
				effect.Parent = gameLighting

				gameLighting.OutdoorAmbient = AmbientOutdoor.Value
				gameLighting.Ambient = AmbientSky.Value
			else
				if effect then effect:Destroy() effect = nil end
				gameLighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
				gameLighting.Ambient = Color3.fromRGB(178, 178, 178)
			end
		end,
		Tooltip = 'Change ambient lighting colors'
	})
	AmbientSky = AmbientColor:CreateColorSlider({
		Name = 'Sky ambient',
		Default = Color3.fromRGB(100, 150, 255),
		Tooltip = 'Color of shadows'
	})
	AmbientOutdoor = AmbientColor:CreateColorSlider({
		Name = 'Outdoor ambient',
		Default = Color3.fromRGB(200, 180, 255),
		Tooltip = 'Color of outdoor lighting'
	})
end)
