local run = function(func)
	func()
end
local cloneref = cloneref or function(obj)
	return obj
end

local playersService = cloneref(game:GetService('Players'))
local inputService = cloneref(game:GetService('UserInputService'))
local replicatedStorage = cloneref(game:GetService('ReplicatedStorage'))
local collectionService = cloneref(game:GetService('CollectionService'))
local textChatService = cloneref(game:GetService('TextChatService'))
local runService = cloneref(game:GetService('RunService'))
local guiService = cloneref(game:GetService('GuiService'))
local coreGui = cloneref(game:GetService('CoreGui'))

local gameCamera = workspace.CurrentCamera
local gameLighting = game:GetService('Lighting')
local httpService = cloneref(game:GetService('HttpService'))
local tweenService = cloneref(game:GetService('TweenService'))
local lplr = playersService.LocalPlayer
local vape = shared.vape
local entitylib = vape.Libraries.entity
local whitelist = vape.Libraries.whitelist
local prediction = vape.Libraries.prediction
local targetinfo = vape.Libraries.targetinfo
local sessioninfo = vape.Libraries.sessioninfo

local bw = {}
local blocks = {}
local BlockTimes = {}
local AnticheatBypass
local bypassRoot
local isAttacking

local combatRemotes = replicatedStorage:WaitForChild('GameEvents'):WaitForChild('CombatRemotes')
local combatFeint = combatRemotes:WaitForChild('Combat_FeintSwing')
local combatAttack = combatRemotes:WaitForChild('Combat_RequestAttack')

local function applySpeed(speed, dt)
	local root = entitylib.character.RootPart
	local dest = (entitylib.character.Humanoid.MoveDirection * math.max((speed + (entitylib.character.Humanoid.WalkSpeed - 16)) - entitylib.character.Humanoid.WalkSpeed, 0) * dt)
	local rayCheck = RaycastParams.new()
	rayCheck.RespectCanCollide = true
	rayCheck.FilterDescendantsInstances = {lplr.Character, gameCamera}
	rayCheck.CollisionGroup = root.CollisionGroup

	local ray = workspace:Raycast(root.Position, dest, rayCheck)
	if ray then
		dest = ((ray.Position + ray.Normal) - root.Position)
	end
	root.CFrame += dest
end

local function collection(tags, module, customadd, customremove)
	tags = typeof(tags) ~= 'table' and {tags} or tags
	local objs, connections = {}, {}

	for _, tag in tags do
		table.insert(connections, collectionService:GetInstanceAddedSignal(tag):Connect(function(v)
			if customadd then
				customadd(objs, v, tag)
				return
			end
			table.insert(objs, v)
		end))
		table.insert(connections, collectionService:GetInstanceRemovedSignal(tag):Connect(function(v)
			if customremove then
				customremove(objs, v, tag)
				return
			end
			v = table.find(objs, v)
			if v then
				table.remove(objs, v)
			end
		end))

		for _, v in collectionService:GetTagged(tag) do
			if customadd then
				customadd(objs, v, tag)
				continue
			end
			table.insert(objs, v)
		end
	end

	local cleanFunc = function(self)
		for _, v in connections do
			v:Disconnect()
		end
		table.clear(connections)
		table.clear(objs)
		table.clear(self)
	end
	if module then
		module:Clean(cleanFunc)
	end
	return objs, cleanFunc
end

local function getInventory()
	local inv = {}
	local backpack = lplr:FindFirstChildWhichIsA('Backpack')
	if backpack then
		inv = backpack:GetChildren()
	end

	local equipped = lplr.Character and lplr.Character:FindFirstChildWhichIsA('Tool')
	if equipped then
		table.insert(inv, equipped)
	end

	return inv
end

local function getTool()
	return lplr.Character and lplr.Character:FindFirstChildWhichIsA('Tool')
end

run(function()
	local oldstart = entitylib.start
	local function customEntity(ent)
		entitylib.addEntity(ent, nil, function(self)
			return (lplr.Team and lplr.Team.Name or '') ~= self.Character:GetAttribute('TeamId')
		end)
	end

	entitylib.start = function()
		oldstart()
		if entitylib.Running then
			for _, ent in collectionService:GetTagged('Attackable') do
				customEntity(ent)
			end
			table.insert(entitylib.Connections, collectionService:GetInstanceAddedSignal('Attackable'):Connect(customEntity))
			table.insert(entitylib.Connections, collectionService:GetInstanceRemovedSignal('Attackable'):Connect(function(ent)
				entitylib.removeEntity(ent)
			end))
		end
	end
end)
entitylib.start()

run(function()
	bw = {
		RemoteIndex = require(replicatedStorage.Modules.RemotesIndex),
		BlockBreakConstants = require(replicatedStorage.Modules.Configs.BlockBreakConfig),
		ShopConfig = require(replicatedStorage.Modules.Configs.ShopConfig),
		Inventory = debug.getupvalue(require(replicatedStorage.Modules.ShopUIClient).Start, 8)
	}

	blocks = collection('BedWarsX_PlacedBlock', vape, function(tab, block)
		tab[block.Position // 3] = block
	end, function(tab, block)
		tab[block.Position // 3] = nil
	end)

	local kills = sessioninfo:AddItem('Kills')
	local beds = sessioninfo:AddItem('Beds')
	local wins = sessioninfo:AddItem('Wins')
	local games = sessioninfo:AddItem('Games')

	task.delay(1, function()
		if workspace:GetAttribute('ServerType') ~= 'Lobby' then
			games:Increment()
		end
	end)

	vape:Clean(lplr:GetAttributeChangedSignal('RoundKills'):Connect(function()
		if lplr:GetAttribute('RoundKills') > 0 then
			kills:Increment()
		end
	end))

	vape:Clean(bw.RemoteIndex.Round_Event.OnClientEvent:Connect(function(data)
		if type(data) == 'table' and data.id == 'final_kill' then
			if lplr.Team and lplr.Team.Name == data.teamId then
				wins:Increment()
			end
		end
	end))

	vape:Clean(bw.RemoteIndex.Bed_Destroyed.OnClientEvent:Connect(function(data)
		if type(data) == 'table' and data.breakerId == lplr.UserId then
			beds:Increment()
		end
	end))

	vape:Clean(entitylib.Events.EntityAdded:Connect(function(entity)
		BlockTimes[entity.Character] = 0

		local animator = entity.Humanoid:FindFirstChild('Animator')
		if animator then
			table.insert(entity.Connections, animator.AnimationPlayed:Connect(function(track)
				if track.Animation.AnimationId == 'rbxassetid://99664081334494' or track.Animation.AnimationId == 'rbxassetid://75062274621204' then
					BlockTimes[entity.Character] = os.clock()
				end
			end))
		end
	end))

	vape:Clean(entitylib.Events.EntityRemoving:Connect(function(entity)
		BlockTimes[entity.Character] = nil
	end))
end)

for _, v in {'AimAssist', 'Reach', 'SilentAim', 'TriggerBot', 'Jesus', 'AutoRejoin', 'Disabler', 'FastProxPrompt', 'SafeWalk', 'MurderMystery'} do
	vape:Remove(v)
end

run(function()
	local overParams = RaycastParams.new()
	overParams.RespectCanCollide = true
	
	local function clampVec(vec, max)
		if vec.Magnitude > max then
			return vec.Unit == vec.Unit and vec.Unit * max or Vector3.zero
		end
	
		return vec
	end
	
	AnticheatBypass = vape.Categories.Blatant:CreateModule({
		Name = 'AnticheatBypass',
		Function = function(callback)
			if callback then
				bypassRoot = Instance.new('Part')
				bypassRoot.CanCollide = false
				bypassRoot.CanQuery = false
				bypassRoot.Size = Vector3.new(2, 2, 1)
				bypassRoot.Material = Enum.Material.SmoothPlastic
				bypassRoot.Transparency = 1
				bypassRoot.Parent = workspace.CurrentCamera
				AnticheatBypass:Clean(bypassRoot)
	
				local oldcf, oldvelo
				local bindKey = game:GetService('HttpService'):GenerateGUID(true)
				runService:BindToRenderStep(bindKey, 0, function()
					if entitylib.isAlive and oldcf then
						entitylib.character.RootPart.CFrame = oldcf
					end
				end)
	
				AnticheatBypass:Clean(function()
					runService:UnbindFromRenderStep(bindKey)
				end)
	
				for _, connection in {entitylib.Events.LocalAdded, replicatedStorage.GameEvents.BedWarsRemotes.AntiCheat_Strike.OnClientEvent} do
					AnticheatBypass:Clean(connection:Connect(function()
						oldcf = nil
					end))
				end
	
				local tpTimer = 0
				local fallTimer = 0
				AnticheatBypass:Clean(runService.Heartbeat:Connect(function(dt)
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						if not oldcf then
							bypassRoot.CFrame = root.CFrame
						end
						oldcf = root.CFrame
	
						local diff = (oldcf.Position - bypassRoot.Position) * Vector3.new(1, 0, 1)
						local united = diff.Unit
						united = united == united and diff.Magnitude > 0.1 and united * entitylib.character.Humanoid.WalkSpeed or Vector3.zero
						bypassRoot.AssemblyLinearVelocity = Vector3.new(united.X, 0, united.Z)
						bypassRoot.CFrame = CFrame.lookAlong(Vector3.new(bypassRoot.Position.X, root.Position.Y, bypassRoot.Position.Z), root.CFrame.LookVector)
						if diff.Magnitude > 6 and (os.clock() - tpTimer) > 0.75 then
							bypassRoot.CFrame += clampVec(diff, entitylib.character.Humanoid.WalkSpeed)
							tpTimer = os.clock()
						end
	
						overParams.CollisionGroup = root.CollisionGroup
						overParams.FilterDescendantsInstances = {lplr.Character, gameCamera}
						local flyCheck = workspace:Raycast(bypassRoot.Position, Vector3.new(0, -8, 0), overParams)
						if not flyCheck then
							if fallTimer == 0 then
								fallTimer = os.clock()
							end
							bypassRoot.CFrame -= Vector3.new(0, ((os.clock() - fallTimer) % 1) * 10, 0)
						else
							fallTimer = 0
						end
	
						root.CFrame = bypassRoot.CFrame
						if root.AssemblyLinearVelocity.Magnitude < 0.1 then
							root.AssemblyLinearVelocity += Vector3.new(0, -0.1, 0)
						end
					else
						bypassRoot.CFrame = CFrame.new()
						bypassRoot.AssemblyLinearVelocity = Vector3.zero
					end
				end))
			else
				bypassRoot = nil
			end
		end,
		Tooltip = 'Using various methods to bypass the Anticheat.'
	})
end)

local Fly
run(function()
	local Value
	local Keys
	local Mode
	local Platform = Instance.new('Part')
	Platform.CanQuery = false
	Platform.Anchored = true
	Platform.Size = Vector3.new(4, 1, 4)
	Platform.Transparency = 1
	Platform.Parent = nil

	local up, down = 0, 0
	local lookFly = false

	Fly = vape.Categories.Blatant:CreateModule({
		Name = 'Fly',
		Function = function(callback)
			if callback then
				if not AnticheatBypass.Enabled then
					AnticheatBypass:Toggle()
				end

				local mode = Mode.Value

				if mode == 'Platform' then
					Platform.Parent = gameCamera

					Fly:Clean(runService.PreSimulation:Connect(function(dt)
						if entitylib.isAlive then
							applySpeed(Value.Value, dt)
							Platform.CFrame = down ~= 0 and CFrame.identity or entitylib.character.RootPart.CFrame + Vector3.new(0, -(entitylib.character.HipHeight + 0.5), 0)
						end
					end))

				elseif mode == 'Velocity' then
					Fly:Clean(runService.Heartbeat:Connect(function(dt)
						if entitylib.isAlive then
							local root = entitylib.character.RootPart
							local hum = entitylib.character.Humanoid
							local moveDir = hum.MoveDirection
							local velo = root.AssemblyLinearVelocity

							local horizontal = moveDir * Value.Value
							local vertical = (up - down) * Value.Value * 0.8

							root.AssemblyLinearVelocity = Vector3.new(horizontal.X, vertical, horizontal.Z)
							root.AssemblyLinearVelocity = Vector3.new(velo.X, vertical, velo.Z)
						end
					end))

				elseif mode == 'CFrame' then
					Fly:Clean(runService.PreSimulation:Connect(function(dt)
						if entitylib.isAlive then
							local root = entitylib.character.RootPart
							local hum = entitylib.character.Humanoid
							local moveDir = hum.MoveDirection
							local camCF = gameCamera.CFrame

							local move = Vector3.zero
							if moveDir.Magnitude > 0 then
								move = (camCF * CFrame.new(moveDir)).Position - camCF.Position
								move = move.Unit * Value.Value * dt
							end

							local vertical = (up - down) * Value.Value * dt

							root.CFrame = root.CFrame + move + Vector3.new(0, vertical, 0)
							root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						end
					end))

				elseif mode == 'Look' then
					lookFly = true
					Fly:Clean(runService.PreSimulation:Connect(function(dt)
						if entitylib.isAlive then
							local root = entitylib.character.RootPart
							local camCF = gameCamera.CFrame
							local move = camCF.LookVector * Value.Value * dt

							if not inputService:IsKeyDown(Enum.KeyCode.W) then
								move = Vector3.zero
							end

							local vertical = (up - down) * Value.Value * dt

							root.CFrame = root.CFrame + move + Vector3.new(0, vertical, 0)
							root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						end
					end))

				elseif mode == 'Hover' then
					local hoverY = nil
					Fly:Clean(runService.PreSimulation:Connect(function(dt)
						if entitylib.isAlive then
							local root = entitylib.character.RootPart
							local hum = entitylib.character.Humanoid
							local moveDir = hum.MoveDirection

							if not hoverY then
								hoverY = root.Position.Y
							end

							hoverY = hoverY + (up - down) * Value.Value * dt * 0.3

							if moveDir.Magnitude > 0 then
								local horiz = moveDir * Value.Value * dt
								root.CFrame = root.CFrame + horiz
							end

							root.CFrame = CFrame.new(root.CFrame.Position.X, hoverY, root.CFrame.Position.Z) * (root.CFrame - root.CFrame.Position)
							root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
						end
					end))
				end

				-- keybinds for up/down
				for _, v in {'InputBegan', 'InputEnded'} do
					Fly:Clean(inputService[v]:Connect(function(input)
						if not inputService:GetFocusedTextBox() then
							local divided = Keys.Value:split('/')
							if input.KeyCode == Enum.KeyCode[divided[1]] then
								up = v == 'InputBegan' and 1 or 0
							elseif input.KeyCode == Enum.KeyCode[divided[2]] then
								down = v == 'InputBegan' and -1 or 0
							end
						end
					end))
				end

				if inputService.TouchEnabled then
					pcall(function()
						local jumpButton = lplr.PlayerGui.TouchGui.TouchControlFrame.JumpButton
						Fly:Clean(jumpButton:GetPropertyChangedSignal('ImageRectOffset'):Connect(function()
							up = jumpButton.ImageRectOffset.X == 146 and 1 or 0
						end))
					end)
				end
			else
				Platform.Parent = nil
				up, down = 0, 0
				lookFly = false
			end
		end,
		ExtraText = function()
			return Mode.Value
		end,
		Tooltip = 'Multiple fly modes\nPlatform: AC bypass platform\nVelocity: direct velocity control\nCFrame: smooth teleport\nLook: fly where camera faces\nHover: stay at height'
	})
	Mode = Fly:CreateDropdown({
		Name = 'Mode',
		List = {'Platform', 'Velocity', 'CFrame', 'Look', 'Hover'},
		Default = 'Platform',
		Tooltip = 'Platform: uses AC bypass\nVelocity: direct velocity\nCFrame: teleport movement\nLook: fly where you look\nHover: maintain height'
	})
	Keys = Fly:CreateDropdown({
		Name = 'Keys',
		List = {'Space/LeftControl', 'Space/LeftShift', 'E/Q', 'Space/Q', 'ButtonA/ButtonL2'},
		Tooltip = 'The key combination for going up & down'
	})
	Value = Fly:CreateSlider({
		Name = 'Speed',
		Min = 1,
		Max = 300,
		Default = 100,
		Suffix = function(val)
			return val == 1 and 'stud' or 'studs'
		end
	})
end)

run(function()
	local Killaura
	local AttackRange
	local SwingRange
	local CPSMin
	local CPSMax
	local Angle
	local SortMode
	local FaceTarget
	local SilentRotation
	local SmoothRotation
	local TargetBoxes = {}
	local TargetParticles = {}
	local lastAttack = 0
	local lastTargets = {}
	local AttackDelay = {}

	local function sortTargets(entities)
		local sorted = {}
		for _, ent in entities do
			if ent and ent.Character and ent.RootPart and ent ~= lplr then
				local teamId = ent.Character:GetAttribute('TeamId')
				if teamId and lplr.Team and teamId ~= lplr.Team.Name then
					local dist = (ent.RootPart.Position - entitylib.character.RootPart.Position).Magnitude
					table.insert(sorted, {Entity = ent, Distance = dist})
				end
			end
		end
		if SortMode.Value == 'Distance' then
			table.sort(sorted, function(a, b) return a.Distance < b.Distance end)
		elseif SortMode.Value == 'Health' then
			table.sort(sorted, function(a, b)
				local hpA = a.Entity.Humanoid and a.Entity.Humanoid.Health or 0
				local hpB = b.Entity.Humanoid and b.Entity.Humanoid.Health or 0
				return hpA < hpB
			end)
		end
		return sorted
	end

	local function createTargetBox()
		local box = Instance.new('BoxHandleAdornment')
		box.Adornee = nil
		box.AlwaysOnTop = true
		box.ZIndex = 10
		box.Size = Vector3.new(3, 5, 3)
		box.Color3 = Color3.fromRGB(255, 80, 80)
		box.Transparency = 0.5
		box.Parent = gameCamera
		return box
	end

	local function createTargetParticle()
		local part = Instance.new('Part')
		part.Size = Vector3.new(0.1, 0.1, 0.1)
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 1
		part.Parent = gameCamera
		local emitter = Instance.new('ParticleEmitter')
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 80, 80))
		emitter.Size = NumberSequence.new(0.5)
		emitter.Lifetime = NumberRange.new(0.3, 0.5)
		emitter.Rate = 50
		emitter.Speed = NumberRange.new(2, 4)
		emitter.Parent = part
		emitter.Enabled = false
		return part, emitter
	end

	for i = 1, 20 do
		TargetBoxes[i] = createTargetBox()
		TargetParticles[i] = createTargetParticle()
	end

	Killaura = vape.Categories.Combat:CreateModule({
		Name = 'Killaura',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						local rootPos = root.Position
						local cameraCF = gameCamera.CFrame
						local entities = entitylib.AllPosition()
						local sorted = sortTargets(entities)
						local attacked = 0
						local targets = {}

						for i, data in sorted do
							if attacked >= 10 then break end
							local ent = data.Entity
							local entRoot = ent.RootPart
							if not entRoot then continue end

							local angle = math.deg(math.acos(math.clamp(cameraCF.LookVector:Dot((entRoot.Position - rootPos).Unit), -1, 1)))
							if angle > Angle.Value then continue end

							if BlockTimes[ent.Character] and (os.clock() - BlockTimes[ent.Character]) < 0.3 then
								continue
							end

							if (os.clock() - (AttackDelay[ent.Character] or 0)) < 0.03 then
								continue
							end

							local dist = data.Distance
							if dist > AttackRange.Value then continue end

							attacked += 1
							table.insert(targets, ent)
							lastTargets[ent] = tick()

							if FaceTarget.Enabled then
								local lookDir = (entRoot.Position - rootPos) * Vector3.new(1, 0, 1)
								if lookDir.Magnitude > 0 then
									root.CFrame = CFrame.lookAt(rootPos, rootPos + lookDir.Unit)
								end
							end

							if TargetBoxes[attacked] then
								TargetBoxes[attacked].Adornee = entRoot
							end
							if TargetParticles[attacked] then
								TargetParticles[attacked].Position = entRoot.Position
								TargetParticles[attacked].Parent = gameCamera
							end
						end

						local now = tick()
						local cps = math.random(CPSMin.Value, CPSMax.Value)
						local delay = 1 / math.max(cps, 1)
						if attacked > 0 and (now - lastAttack) >= delay then
							for _, ent in targets do
								pcall(function()
									combatFeint:FireServer()
									combatAttack:FireServer(
										ent.Character and ent.Character:GetAttribute('EquippedWeaponType') or 'Sword',
										ent.Character
									)
								end)
								AttackDelay[ent.Character] = now
							end
							lastAttack = now
						end

						for i = attacked + 1, 20 do
							if TargetBoxes[i] then TargetBoxes[i].Adornee = nil end
							if TargetParticles[i] then TargetParticles[i].Parent = nil end
						end
					end
					task.wait()
				until not Killaura.Enabled
			else
				for i = 1, 20 do
					if TargetBoxes[i] then TargetBoxes[i].Adornee = nil end
					if TargetParticles[i] then TargetParticles[i].Parent = nil end
				end
				lastTargets = {}
			end
		end,
		Tooltip = 'Auto attacks nearby enemies'
	})
	AttackRange = Killaura:CreateSlider({
		Name = 'Attack range',
		Min = 1,
		Max = 20,
		Default = 14,
		Suffix = 'studs'
	})
	SwingRange = Killaura:CreateSlider({
		Name = 'Swing range',
		Min = 1,
		Max = 20,
		Default = 14,
		Suffix = 'studs'
	})
	CPSMin = Killaura:CreateSlider({
		Name = 'CPS min',
		Min = 1,
		Max = 20,
		Default = 8
	})
	CPSMax = Killaura:CreateSlider({
		Name = 'CPS max',
		Min = 1,
		Max = 20,
		Default = 12
	})
	Angle = Killaura:CreateSlider({
		Name = 'Angle',
		Min = 30,
		Max = 180,
		Default = 90,
		Suffix = 'deg'
	})
	SortMode = Killaura:CreateDropdown({
		Name = 'Sort mode',
		List = {'Distance', 'Health'},
		Default = 'Distance'
	})
	FaceTarget = Killaura:CreateToggle({
		Name = 'Face target',
		Default = true
	})
	SilentRotation = Killaura:CreateToggle({
		Name = 'Silent rotation',
		Default = false,
		Tooltip = 'Rotate without sending to server'
	})
	SmoothRotation = Killaura:CreateToggle({
		Name = 'Smooth rotation',
		Default = false,
		Tooltip = 'Lerp rotation smoothly'
	})
end)

run(function()
	local Speed
	local Value
	local AutoJump
	local JumpPower
	local WallCheck

	Speed = vape.Categories.Blatant:CreateModule({
		Name = 'Speed',
		Function = function(callback)
			if callback then
				repeat
					if entitylib.isAlive then
						local root = entitylib.character.RootPart
						local hum = entitylib.character.Humanoid
						local moveDir = hum.MoveDirection

						if moveDir.Magnitude > 0 then
							local speed = math.max(Value.Value, 16)
							local dest = moveDir * speed * (1 / 60)

							if WallCheck.Enabled then
								local rayParams = RaycastParams.new()
								rayParams.FilterDescendantsInstances = {lplr.Character, gameCamera}
								rayParams.RespectCanCollide = true
								local ray = workspace:Raycast(root.Position, dest, rayParams)
								if ray then
									dest = (ray.Position + ray.Normal) - root.Position
								end
							end

							root.CFrame += dest
						end

						if AutoJump.Enabled and moveDir.Magnitude > 0 then
							local rayParams = RaycastParams.new()
							rayParams.FilterDescendantsInstances = {lplr.Character, gameCamera}
							rayParams.RespectCanCollide = true
							local ray = workspace:Raycast(root.Position, Vector3.new(0, -3, 0), rayParams)
							if ray then
								hum:ChangeState(Enum.HumanoidStateType.Jumping)
								root.AssemblyLinearVelocity = Vector3.new(
									root.AssemblyLinearVelocity.X,
									JumpPower.Value,
									root.AssemblyLinearVelocity.Z
								)
							end
						end
					end
					task.wait()
				until not Speed.Enabled
			end
		end,
		ExtraText = function()
			return 'BlockWars'
		end,
		Tooltip = 'Move faster than normal'
	})
	Value = Speed:CreateSlider({
		Name = 'Speed',
		Min = 16,
		Max = 300,
		Default = 100,
		Suffix = 'studs'
	})
	AutoJump = Speed:CreateToggle({
		Name = 'Auto jump',
		Default = true
	})
	JumpPower = Speed:CreateSlider({
		Name = 'Jump power',
		Min = 50,
		Max = 500,
		Default = 200,
		Suffix = 'studs'
	})
	WallCheck = Speed:CreateToggle({
		Name = 'Wall check',
		Default = true
	})
end)

run(function()
	local AutoLeave
	
	AutoLeave = vape.Categories.Utility:CreateModule({
		Name = 'AutoLeave',
		Function = function(callback)
			if callback then
				AutoLeave:Clean(bw.RemoteIndex.Victory_Show.OnClientEvent:Connect(function()
					replicatedStorage.GameEvents.BedWarsRemotes.Return_To_Lobby:FireServer()
				end))
			end
		end,
		Tooltip = 'Automatically leave after the match ends.'
	})
end)

run(function()
	local AutoQueue
	
	AutoQueue = vape.Categories.Utility:CreateModule({
		Name = 'AutoQueue',
		Function = function(callback)
			if callback then
				if workspace:GetAttribute('ServerType') == 'Lobby' then
					task.spawn(function()
						bw.RemoteIndex.Matchmaking_Request:InvokeServer('queue')
					end)
				end
			end
		end,
		Tooltip = 'Automatically queue in the lobby.'
	})
end)

run(function()
	local AutoToxic
	local GG
	local Toggles, Lists, Cloned, Presets = {}, {}, {}, {}
	
	local function sendMessage(name, obj, default)
		local message = default
		if #Lists[name].ListEnabled > 0 then
			if #Cloned[name] <= 0 then
				Cloned[name] = table.clone(Lists[name].ListEnabled)
			end
	
			local entry = Random.new():NextInteger(1, #Cloned[name])
			message = Cloned[name][entry]
			table.remove(Cloned[name], entry)
		end
	
		if not message then return end
	
		message = message and message:gsub('<obj>', obj or '') or ''
		if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
			if textChatService:CanUserChatAsync(lplr.UserId) then
				textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync(message)
			else
				textChatService.ChatInputBarConfiguration.TargetTextChannel:SendPresetAsync(Presets[message] or Presets['So close'])
			end
		else
			replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, 'All')
		end
	end
	
	AutoToxic = vape.Categories.Utility:CreateModule({
		Name = 'AutoToxic',
		Function = function(callback)
			if callback then
				AutoToxic:Clean(bw.RemoteIndex.Round_Event.OnClientEvent:Connect(function(data)
					if type(data) == 'table' and data.id == 'final_kill' then
						if GG.Enabled then
							if textChatService.ChatVersion == Enum.ChatVersion.TextChatService then
								if textChatService:CanUserChatAsync(lplr.UserId) then
									textChatService.ChatInputBarConfiguration.TargetTextChannel:SendAsync('gg')
								else
									textChatService.ChatInputBarConfiguration.TargetTextChannel:SendPresetAsync(Presets['Good game'])
								end
							else
								replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer('gg', 'All')
							end
						end
	
						if lplr.Team and lplr.Team.Name == data.teamId then
							if Toggles.Win.Enabled then
								sendMessage('Win', nil, 'yall garbage')
							end
						end
					end
				end))
			end
		end,
		Tooltip = 'Says a message after a certain action'
	})
	GG = AutoToxic:CreateToggle({
		Name = 'AutoGG',
		Default = true
	})
	for _, v in {'Win'} do
		Cloned[v] = {}
		Toggles[v] = AutoToxic:CreateToggle({
			Name = v..' ',
			Function = function(callback)
				if Lists[v] then
					Lists[v].Object.Visible = callback
				end
			end
		})
		Lists[v] = AutoToxic:CreateTextList({
			Name = v,
			Darker = true,
			Visible = false,
			Function = function()
				table.clear(Cloned[v])
			end
		})
	end
	
	pcall(function()
		for _, group in textChatService:GetPresetsAsync().categoryGroups do
			for _, category in group.categories do
				for _, message in category.messages do
					Presets[message.value] = message.presetId
				end
			end
		end
	end)
end)

run(function()
	local FastBreak
	local Value
	local old
	
	FastBreak = vape.Categories.World:CreateModule({
		Name = 'FastBreak',
		Function = function(callback)
			if callback then
				old = hookfunction(bw.BlockBreakConstants.CooldownFor, function(...)
					return old(...) * (Value.Value / 100)
				end)
			else
				if old then
					hookfunction(bw.BlockBreakConstants.CooldownFor, old)
					old = nil
				end
			end
		end,
		Tooltip = 'Allow you to swing the pickaxe faster.'
	})
	Value = FastBreak:CreateSlider({
		Name = 'Break Speed Percent',
		Min = 0,
		Max = 100,
		Default = 50,
		Suffix = '%'
	})
end)

run(function()
	local AutoBuy
	local shops = {}
	local requirements = {
		armor = {
			['Leather Armor'] = 'pickaxe_iron'
		},
		pickaxe = {
			['pickaxe_gold'] = 'Golden Armor',
			['pickaxe_diamond'] = 'Diamond Armor'
		}
	}
	
	local function buyCategory(ladder, default)
		local tierItems = {}
		for _, item in bw.ShopConfig.Items do
			if item.ladder == ladder then
				table.insert(tierItems, item)
			end
		end
	
		table.sort(tierItems, function(a, b)
			return (a.tier or -1) < (b.tier or -1)
		end)
	
		local nextTier = default and tierItems[1] or nil
		for _, item in tierItems do
			if bw.Inventory.items[item.id] then
				nextTier = tierItems[table.find(tierItems, item) + 1]
				break
			end
		end
	
		if nextTier then
			for index, item in {'Block', 'Gold', 'Diamond'} do
				if (nextTier.cost and nextTier.cost[item] or 0) > (bw.Inventory[index == 1 and 'blocks' or item:lower()] or 0) then
					return false
				end
			end
	
			if requirements[ladder] and requirements[ladder][nextTier.id] and not bw.Inventory.items[requirements[ladder][nextTier.id]] then
				return false
			end
	
			bw.RemoteIndex.Shop_Purchase:InvokeServer({itemId = nextTier.id})
			return true
		end
	
		return false
	end
	
	AutoBuy = vape.Categories.Inventory:CreateModule({
		Name = 'AutoBuy',
		Function = function(callback)
			if callback then
				shops = collection('BedWarsX_ShopNPC')
	
				repeat
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						for _, shop in shops do
							if (shop.Position - localPosition).Magnitude < 20 then
								if buyCategory('armor', true) then break end
								if buyCategory('pickaxe') then break end
								if buyCategory('sword') then break end
								break
							end
						end
					end
	
					task.wait(0.2)
				until not AutoBuy.Enabled
			end
		end,
		Tooltip = 'lol'
	})
end)

run(function()
	local Breaker
	local Mode
	local Range
	local BreakSpeed
	local BedToggle
	local GeneratorToggle
	local SelfBreak
	local origCF

	local function breakBlockRemote(v)
		pcall(function()
			bw.RemoteIndex.Block_AttemptHit:FireServer(gameCamera.CFrame.Position, v.Position, v)
		end)
	end

	local function mineBlockRemote(v)
		pcall(function()
			bw.RemoteIndex.Mine_AttemptHit:FireServer(v)
		end)
	end

	local function attemptBreak(tab, localPosition)
		if not tab then return false end
		for _, v in tab do
			if not v or not v.Parent then continue end
			local blockPos = v.Position
			if not SelfBreak.Enabled and v:GetAttribute('PlacedByUserId') == lplr.UserId then continue end

			if Mode.Value == 'Silent' then
				breakBlockRemote(v)
				task.wait(BreakSpeed.Value)
			elseif Mode.Value == 'Teleport' then
				if entitylib.isAlive then
					local root = entitylib.character.RootPart
					origCF = root.CFrame
					root.CFrame = CFrame.new(blockPos + Vector3.new(0, 5, 0))
					task.wait(0.05)
					breakBlockRemote(v)
					task.wait(BreakSpeed.Value)
					if origCF then root.CFrame = origCF end
				end
			else
				if (blockPos - localPosition).Magnitude > Range.Value then continue end
				breakBlockRemote(v)
				task.wait(BreakSpeed.Value)
			end
			return true
		end
		return false
	end

	local function attemptBreakGen(tab, localPosition)
		if not tab then return false end
		for _, v in tab do
			if not v or not v.Parent then continue end
			local blockPos = v.Position

			if Mode.Value == 'Silent' then
				mineBlockRemote(v)
				task.wait(BreakSpeed.Value)
			elseif Mode.Value == 'Teleport' then
				if entitylib.isAlive then
					local root = entitylib.character.RootPart
					origCF = root.CFrame
					root.CFrame = CFrame.new(blockPos + Vector3.new(0, 5, 0))
					task.wait(0.05)
					mineBlockRemote(v)
					task.wait(BreakSpeed.Value)
					if origCF then root.CFrame = origCF end
				end
			else
				if (blockPos - localPosition).Magnitude > Range.Value then continue end
				mineBlockRemote(v)
				task.wait(BreakSpeed.Value)
			end
			return true
		end
		return false
	end

	Breaker = vape.Categories.Minigames:CreateModule({
		Name = 'Breaker',
		Function = function(callback)
			if callback then
				local beds = collection('BedWarsX_BedSpawn', Breaker)
				local generators = collection('BedWarsX_Resource', Breaker)

				repeat
					task.wait(0.1)
					if not Breaker.Enabled then break end
					if entitylib.isAlive then
						local localPosition = entitylib.character.RootPart.Position
						if BedToggle.Enabled then
							if attemptBreak(beds, localPosition) then continue end
						end
						if GeneratorToggle.Enabled then
							if attemptBreakGen(generators, localPosition) then continue end
						end
					end
				until not Breaker.Enabled
			else
				origCF = nil
			end
		end,
		Tooltip = 'Breaks beds and generators\nSilent: fires remote from your position'
	})
	Mode = Breaker:CreateDropdown({
		Name = 'Mode',
		List = {'Silent', 'Teleport', 'Normal'},
		Default = 'Silent',
		Tooltip = 'Silent: fire remote from your position\nTeleport: TP to target, break, TP back\nNormal: break within range'
	})
	Range = Breaker:CreateSlider({
		Name = 'Break range',
		Min = 1,
		Max = 100,
		Default = 18,
		Suffix = 'studs',
		Tooltip = 'Only used in Normal mode'
	})
	BreakSpeed = Breaker:CreateSlider({
		Name = 'Break speed',
		Min = 0,
		Max = 0.3,
		Default = 0.05,
		Decimal = 100,
		Suffix = 'sec'
	})
	BedToggle = Breaker:CreateToggle({
		Name = 'Break beds',
		Default = true
	})
	GeneratorToggle = Breaker:CreateToggle({
		Name = 'Break generators',
		Default = true
	})
	SelfBreak = Breaker:CreateToggle({
		Name = 'Self break',
		Default = false
	})
end)

run(function()
	local FixGUIs
	
	FixGUIs = vape.Legit:CreateModule({
		Name = 'FixGUIs',
		Function = function(callback)
			if callback then
				local guis = {lplr.PlayerGui:FindFirstChild('Team_UpgradesV3', true), lplr.PlayerGui:FindFirstChild('ItemShopV3', true)}
				if #guis < 2 then
					repeat
						guis = {lplr.PlayerGui:FindFirstChild('Team_UpgradesV3', true), lplr.PlayerGui:FindFirstChild('ItemShopV3', true)}
						task.wait()
					until #guis >= 2 or not FixGUIs.Enabled
	
					if not FixGUIs.Enabled then
						return
					end
				end
	
				local vis = false
				local mouse = Instance.new('ImageLabel')
				mouse.Size = UDim2.fromOffset(20, 20)
				mouse.Visible = false
				mouse.Parent = vape.gui
				FixGUIs:Clean(mouse)
	
				for _, gui in guis do
					if gui then
						for _, v in gui:QueryDescendants('TextButton') do
							local ancestor = v:FindFirstAncestorWhichIsA('ScrollingFrame')
							if not ancestor then
								v.Modal = true
							end
						end
	
						vis = vis or gui.Visible
						FixGUIs:Clean(gui:GetPropertyChangedSignal('Visible'):Connect(function()
							vis = gui.Visible
						end))
					end
				end
	
				FixGUIs:Clean(runService.Heartbeat:Connect(function()
					local location = inputService:GetMouseLocation()
					mouse.Visible = vis
					if mouse.Visible then
						mouse.Position = UDim2.fromOffset(location.X, location.Y)
					end
				end))
			end
		end,
		Tooltip = 'Fix GUI\'s in first person.'
	})
end)

run(function()
	local HideShield
	local parts = {}
	
	local function localAdded(char)
		local shield = char.Character:WaitForChild('ShieldModel', 10)
		if shield then
			parts = shield:QueryDescendants('BasePart')
		end
	end
	
	HideShield = vape.Legit:CreateModule({
		Name = 'HideShield',
		Function = function(callback)
			if callback then
				HideShield:Clean(entitylib.Events.LocalAdded:Connect(localAdded))
				if entitylib.isAlive then
					task.spawn(localAdded, entitylib.character)
				end
	
				repeat
					for _, v in parts do
						v.Transparency = 1
					end
	
					task.wait()
				until not HideShield.Enabled
			else
				table.clear(parts)
			end
		end,
		Tooltip = 'Hide the shield entirely.'
	})
end)

-- ============================================
-- AUTOSAVE CONFIG
-- ============================================
do
	local gameId = game.GameId
	local configPath = 'flintv4/profiles/'..gameId..'.txt'

	local function loadConfig()
		if isfile(configPath) then
			local ok, data = pcall(function()
				return httpService:JSONDecode(readfile(configPath))
			end)
			if ok and data then
				for moduleName, moduleData in pairs(data) do
					if moduleData and type(moduleData) == 'table' then
						local mod = vape.Modules[moduleName]
						if mod then
							if moduleData.Enabled and not mod.Enabled then
								pcall(function() mod:Toggle() end)
							elseif not moduleData.Enabled and mod.Enabled then
								pcall(function() mod:Toggle() end)
							end
							if moduleData.Options then
								for optionName, optionVal in pairs(moduleData.Options) do
									if mod.Options[optionName] then
										pcall(function()
											if type(optionVal) == 'table' and optionVal.Value ~= nil then
												mod.Options[optionName]:SetValue(optionVal.Value)
											elseif type(optionVal) == 'boolean' then
												if mod.Options[optionName].Enabled ~= optionVal then
													mod.Options[optionName]:Toggle()
												end
											elseif type(optionVal) == 'string' then
												mod.Options[optionName]:SetValue(optionVal)
											elseif type(optionVal) == 'number' then
												mod.Options[optionName]:SetValue(optionVal)
											end
										end)
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local function saveConfig()
		local data = {}
		for name, mod in pairs(vape.Modules) do
			if mod.Enabled or (mod.Options and next(mod.Options)) then
				data[name] = {Enabled = mod.Enabled, Options = {}}
				if mod.Options then
					for optName, opt in pairs(mod.Options) do
						pcall(function()
							if opt.Value ~= nil then
								data[name].Options[optName] = {Value = opt.Value}
							elseif opt.Enabled ~= nil then
								data[name].Options[optName] = opt.Enabled
							end
						end)
					end
				end
			end
		end
		pcall(function()
			writefile(configPath, httpService:JSONEncode(data))
		end)
	end

	task.spawn(loadConfig)

	task.spawn(function()
		while task.wait(30) do
			if vape.Loaded then
				pcall(saveConfig)
			end
		end
	end)

	vape:Clean(function()
		pcall(saveConfig)
	end)

	pcall(function()
		game:GetService('Players').LocalPlayer.OnTeleport:Connect(function()
			pcall(saveConfig)
		end)
	end)

	pcall(function()
		lplr.CharacterAdded:Connect(function()
			task.wait(2)
			if vape.Loaded then
				pcall(saveConfig)
			end
		end)
	end)
end

-- ============================================
-- NOFALL (ground snap)
-- ============================================
run(function()
	local NoFall
	local GroundSnap

	NoFall = vape.Categories.Blatant:CreateModule({
		Name = 'NoFall',
		Function = function(callback)
			if callback then
				local groundHit = replicatedStorage.GameEvents.BedWarsRemotes:FindFirstChild('GroundHit')
				local tracked = 0

				NoFall:Clean(runService.PostSimulation:Connect(function()
					if entitylib.isAlive then
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
							if groundHit then
								runService.PreRender:Wait()
								groundHit:FireServer()
							end
						end
						tracked = velo.Y
					end
				end))
			end
		end,
		Tooltip = 'Prevents fall damage\nGround Snap teleports to the block below'
	})
	GroundSnap = NoFall:CreateToggle({
		Name = 'Ground Snap',
		Default = true,
		Tooltip = 'Teleports to block below before firing\nGroundHit to better bypass anti-cheat'
	})
end)

-- ============================================
-- SWORD ANIMATIONS
-- ============================================
run(function()
	local SwordAnims
	local AnimStyle
	local AnimSpeed
	local AnimIntensity
	local oldSwing
	local playing = false
	local oldC1

	local function stopAnimation()
		playing = false
		local vm = gameCamera:FindFirstChild('Viewmodel')
		if vm then
			local wrist = vm:FindFirstChild('RightHand') and vm.RightHand:FindFirstChild('RightWrist')
			if wrist and oldC1 then
				wrist.C1 = oldC1
			end
		end
	end

	local function playAnimation(style, speed, intensity)
		if playing then return end
		playing = true
		local vm = gameCamera:FindFirstChild('Viewmodel')
		if not vm then return end
		local wrist = vm:FindFirstChild('RightHand') and vm.RightHand:FindFirstChild('RightWrist')
		if not wrist then return end
		if not oldC1 then oldC1 = wrist.C1 end

		if style == 'Spam' then
			task.spawn(function()
				while playing and SwordAnims.Enabled do
					wrist.C1 = oldC1 * CFrame.Angles(
						math.rad(math.random(-80, 80) * intensity),
						math.rad(math.random(-50, 50) * intensity),
						math.rad(math.random(-60, 60) * intensity)
					)
					task.wait(0.04 / speed)
				end
			end)

		elseif style == 'Smooth' then
			task.spawn(function()
				local t = 0
				while playing and SwordAnims.Enabled do
					local dt = task.wait()
					t = t + dt * speed * 4
					local swing = math.sin(t) * intensity
					local rx = swing * 70
					local rz = math.cos(t * 0.5) * 20 * intensity
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(rx), 0, math.rad(rz))
				end
			end)

		elseif style == 'Snap' then
			task.spawn(function()
				while playing and SwordAnims.Enabled do
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(-80 * intensity), 0, math.rad(40 * intensity))
					task.wait(0.05 / speed)
					if not playing then break end
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(30 * intensity), 0, math.rad(-20 * intensity))
					task.wait(0.08 / speed)
				end
			end)

		elseif style == 'Circular' then
			task.spawn(function()
				local t = 0
				while playing and SwordAnims.Enabled do
					local dt = task.wait()
					t = t + dt * speed * 6
					local rx = math.cos(t) * 50 * intensity
					local ry = math.sin(t) * 40 * intensity
					local rz = math.sin(t * 1.5) * 30 * intensity
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
				end
			end)

		elseif style == 'Jitter' then
			task.spawn(function()
				while playing and SwordAnims.Enabled do
					local rx = math.sin(tick() * 40) * 15 * intensity
					local ry = math.cos(tick() * 30) * 10 * intensity
					local rz = math.sin(tick() * 50) * 12 * intensity
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
					task.wait(0.03)
				end
			end)

		elseif style == 'Vertical' then
			task.spawn(function()
				while playing and SwordAnims.Enabled do
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(-90 * intensity), 0, 0)
					task.wait(0.1 / speed)
					if not playing then break end
					wrist.C1 = oldC1 * CFrame.Angles(math.rad(40 * intensity), 0, 0)
					task.wait(0.12 / speed)
				end
			end)
		end
	end

	SwordAnims = vape.Categories.Combat:CreateModule({
		Name = 'SwordAnimations',
		Function = function(callback)
			if callback then
				oldSwing = combatFeint.FireServer
				combatFeint.FireServer = function(self, ...)
					stopAnimation()
					playAnimation(AnimStyle.Value, AnimSpeed.Value, AnimIntensity.Value)
					return oldSwing(self, ...)
				end
			else
				if oldSwing then
					combatFeint.FireServer = oldSwing
					oldSwing = nil
				end
				stopAnimation()
			end
		end,
		Tooltip = 'Custom viewmodel sword animations'
	})
	AnimStyle = SwordAnims:CreateDropdown({
		Name = 'Animation style',
		List = {'Spam', 'Smooth', 'Snap', 'Circular', 'Jitter', 'Vertical'},
		Default = 'Smooth',
		Tooltip = 'Spam: rapid random rotations\nSmooth: interpolated swing arc\nSnap: instant snap between poses\nCircular: continuous orbital motion\nJitter: small random offsets\nVertical: overhead chopping motion'
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
end)

-- ============================================
-- HITSOUND
-- ============================================
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
				HitSound:Clean(combatAttack.OnClientEvent:Connect(function()
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

-- ============================================
-- FULLBRIGHT
-- ============================================
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
			else
				gameLighting.Ambient = OldAmbient or Color3.fromRGB(178, 178, 178)
				gameLighting.Brightness = OldBrightness or 1
				gameLighting.GlobalShadows = true
				gameLighting.ForceEndShadows = false
			end
		end,
		Tooltip = 'Max brightness, no shadows'
	})
end)

-- ============================================
-- BLOOM
-- ============================================
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

-- ============================================
-- SUNRAYS
-- ============================================
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

-- ============================================
-- COLOR CORRECTION
-- ============================================
run(function()
	local ColorCorrection
	local Saturation
	local Contrast
	local Brightness
	local effect

	ColorCorrection = vape.Categories.Render:CreateModule({
		Name = 'ColorCorrection',
		Function = function(callback)
			if callback then
				effect = Instance.new('ColorCorrectionEffect')
				effect.Saturation = Saturation.Value
				effect.Contrast = Contrast.Value
				effect.Brightness = Brightness.Value
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
		Decimal = 10
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
end)

-- ============================================
-- CUSTOM SKY
-- ============================================
run(function()
	local CustomSky
	local SkyboxTop
	local SkyboxBottom
	local SkyboxLeft
	local SkyboxRight
	local SkyboxFront
	local SkyboxBack
	local skyObj

	local function removeOld()
		if skyObj then pcall(function() skyObj:Destroy() end) skyObj = nil end
	end

	local function applySky()
		removeOld()
		if not CustomSky.Enabled then return end

		skyObj = Instance.new('Sky')
		skyObj.SkyboxBk = SkyboxBack.Value ~= '' and SkyboxBack.Value or 'rbxassetid://6444884337'
		skyObj.SkyboxDn = SkyboxBottom.Value ~= '' and SkyboxBottom.Value or 'rbxassetid://6444884785'
		skyObj.SkyboxFt = SkyboxFront.Value ~= '' and SkyboxFront.Value or 'rbxassetid://6444884337'
		skyObj.SkyboxLf = SkyboxLeft.Value ~= '' and SkyboxLeft.Value or 'rbxassetid://6444884337'
		skyObj.SkyboxRt = SkyboxRight.Value ~= '' and SkyboxRight.Value or 'rbxassetid://6444884337'
		skyObj.SkyboxUp = SkyboxTop.Value ~= '' and SkyboxTop.Value or 'rbxassetid://6444884785'
		skyObj.Parent = gameLighting
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
end)