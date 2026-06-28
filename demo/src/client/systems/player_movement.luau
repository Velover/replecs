local Players = game:GetService "Players"
local ReplicatedStorage = game:GetService "ReplicatedStorage"
local UserInputService = game:GetService "UserInputService"
local c = require(ReplicatedStorage.code.components)
local jecs = require(ReplicatedStorage.packages.jecs)
local replecs = require(ReplicatedStorage.packages.replecs)
local ref = require(ReplicatedStorage.code.utils.ecs.ref)
local scheduler = require(ReplicatedStorage.code.utils.ecs.scheduler)
local world = require(ReplicatedStorage.code.world)

local replicator = require(script.Parent.Parent.replicator)

local MOVE_SPEED = 50
local JUMP_FORCE = 40
local GRAVITY = 80

local velocity_y = 0
local is_grounded = false
local last_tick = os.clock()

function PLAYER_MOVEMENT()
	local player = Players.LocalPlayer
	local entity = ref.search(player)
	if not entity then
		return
	end

	if not replicator:has_ownership(entity, c.transform) then
		return
	end

	local now = os.clock()
	local dt = now - last_tick
	last_tick = now

	if dt > 0.1 then
		dt = 0.1
	end

	local current_cf = world:get(entity, c.transform) :: CFrame
	if not current_cf then
		return
	end

	local pos = current_cf.Position
	local move_dir = Vector3.zero

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		move_dir += Vector3.new(0, 0, -1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		move_dir += Vector3.new(0, 0, 1)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		move_dir += Vector3.new(-1, 0, 0)
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		move_dir += Vector3.new(1, 0, 0)
	end

	if move_dir.Magnitude > 0 then
		move_dir = move_dir.Unit
	end

	-- Jump
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) and is_grounded then
		velocity_y = JUMP_FORCE
		is_grounded = false
	end

	-- Apply gravity
	velocity_y -= GRAVITY * dt

	local new_pos = pos + Vector3.new(move_dir.X * MOVE_SPEED * dt, velocity_y * dt, move_dir.Z * MOVE_SPEED * dt)

	-- Ground check
	if new_pos.Y <= 4 then
		new_pos = Vector3.new(new_pos.X, 4, new_pos.Z)
		velocity_y = 0
		is_grounded = true
	end

	local new_cf = CFrame.new(new_pos)
	replicator:request_set(entity, c.transform, new_cf, true) -- unreliable
end

scheduler.System(PLAYER_MOVEMENT)
return PLAYER_MOVEMENT
