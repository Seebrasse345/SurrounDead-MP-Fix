-- MPFix v3.3 - Ultra defensive, wrapped in pcall everywhere
local UEHelpers = require("UEHelpers")

print("[MPFix] ========================================")
print("[MPFix] Loading v3.7 - SpawnDefaultPawnAtTransform")
print("[MPFix] ========================================")

local State = {
    LastAttempt = 0,
    Cooldown = 2.0,
    Tried = {},
    SpawnAttempts = {},
    LastControllerCount = 0,
    InGame = false
}

local function Log(msg)
    print("[MPFix] " .. tostring(msg))
end

local function LogEvent(event, details)
    print("[MPFix][" .. event .. "] " .. tostring(details))
end

local function SafeCall(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        Log("ERROR in " .. name .. ": " .. tostring(err))
    end
    return ok
end

local function IsValid(obj)
    if not obj then return false end
    local ok, valid = pcall(function()
        if obj.IsValid then return obj:IsValid() end
        return false
    end)
    return ok and valid
end

local function IsServer()
    local ok, result = pcall(function()
        local gm = FindFirstOf("GameModeBase")
        return IsValid(gm)
    end)
    return ok and result
end

local function IsInGame()
    local ok, result = pcall(function()
        -- Check if we're actually in a game (not main menu)
        local world = FindFirstOf("World")
        if not IsValid(world) then return false end

        local gm = FindFirstOf("GameModeBase")
        if not IsValid(gm) then return false end

        return true
    end)
    return ok and result
end

local function GetLocalPC()
    local result = nil
    pcall(function()
        local pcs = FindAllOf("PlayerController")
        if pcs then
            for _, pc in ipairs(pcs) do
                local ok, isLocal = pcall(function() return pc:IsLocalController() end)
                if ok and isLocal then
                    result = pc
                    return
                end
            end
        end
    end)
    return result
end

local function GetSpawnLocation()
    local loc = { X = 0, Y = 0, Z = 5000 }

    pcall(function()
        local chars = FindAllOf("BP_PlayerCharacter_C")
        if chars then
            for _, c in ipairs(chars) do
                local ok, charLoc = pcall(function() return c:K2_GetActorLocation() end)
                if ok and charLoc and charLoc.Z > -500 then
                    loc = { X = charLoc.X + 300, Y = charLoc.Y, Z = charLoc.Z + 100 }
                    return
                end
            end
        end
    end)

    return loc
end

local function GetPlayerName(pc)
    local name = "Unknown"
    pcall(function()
        if pc and pc.PlayerState then
            local ps = pc.PlayerState
            if ps and ps.GetPlayerName then
                local fstring = ps:GetPlayerName()
                -- FString needs :ToString() conversion
                if fstring then
                    if type(fstring) == "string" then
                        name = fstring
                    elseif fstring.ToString then
                        name = fstring:ToString()
                    else
                        name = tostring(fstring)
                    end
                end
            end
        end
    end)
    return name
end

local function TrySpawnForController(pc)
    if not IsValid(pc) then return end

    local playerName = GetPlayerName(pc)
    LogEvent("SPAWN", "Attempting spawn for: " .. tostring(playerName))

    local spawnLoc = GetSpawnLocation()

    -- Method 1: RestartPlayer
    pcall(function()
        local gm = FindFirstOf("GameModeBase")
        if gm and gm.RestartPlayer then
            gm:RestartPlayer(pc)
            Log("RestartPlayer called")
        end
    end)

    -- Method 2: ServerRestartPlayer
    pcall(function()
        if pc.ServerRestartPlayer then
            pc:ServerRestartPlayer()
            Log("ServerRestartPlayer called")
        end
    end)

    -- Method 3: Try SpawnDefaultPawnAtTransform
    pcall(function()
        Log("Trying SpawnDefaultPawnAtTransform...")
        local gm = FindFirstOf("GameModeBase")
        if gm and gm.SpawnDefaultPawnAtTransform then
            local transform = {}
            transform.Translation = spawnLoc
            transform.Rotation = { Pitch = 0, Yaw = 0, Roll = 0, W = 1, X = 0, Y = 0, Z = 0 }
            transform.Scale3D = { X = 1, Y = 1, Z = 1 }

            local newPawn = gm:SpawnDefaultPawnAtTransform(pc, transform)
            if IsValid(newPawn) then
                Log("SpawnDefaultPawnAtTransform SUCCESS!")
                pc:Possess(newPawn)
                Log("Possessed new pawn")
            else
                Log("SpawnDefaultPawnAtTransform returned nil")
            end
        else
            Log("No SpawnDefaultPawnAtTransform available")
        end
    end)

    -- Method 3b: Try K2_SpawnActor
    pcall(function()
        Log("Trying K2_SpawnActor...")
        local existingChar = FindFirstOf("BP_PlayerCharacter_C")
        if existingChar then
            local charClass = existingChar:GetClass()
            if charClass then
                Log("Found character class: " .. tostring(charClass:GetFullName()))

                local world = FindFirstOf("World")
                if world and world.SpawnActor then
                    local transform = {}
                    transform.Translation = spawnLoc
                    transform.Rotation = { Pitch = 0, Yaw = 0, Roll = 0 }
                    transform.Scale3D = { X = 1, Y = 1, Z = 1 }

                    local newActor = world:SpawnActor(charClass, transform)
                    if IsValid(newActor) then
                        Log("SpawnActor SUCCESS!")
                        newActor:SetOwner(pc)
                        pc:Possess(newActor)
                        Log("Possessed spawned actor")
                    end
                end
            end
        end
    end)

    -- Method 4: Try ClientRestart
    pcall(function()
        if pc.ClientRestart then
            Log("Trying ClientRestart...")
            local starts = FindAllOf("PlayerStart")
            if starts and #starts > 0 then
                pc:ClientRestart(starts[1])
                Log("ClientRestart called")
            end
        end
    end)

    -- Method 5: Find unpossessed character and possess it
    pcall(function()
        Log("Looking for unpossessed characters...")
        local chars = FindAllOf("BP_PlayerCharacter_C")
        if chars then
            Log("Found " .. #chars .. " characters")
            for i, char in ipairs(chars) do
                local controller = nil
                pcall(function() controller = char.Controller end)
                if not IsValid(controller) then
                    Log("Character " .. i .. " has no controller - trying to possess")

                    -- Possess the character
                    pcall(function()
                        pc:Possess(char)
                        Log("Possess called!")
                    end)

                    -- Move the character to spawn location
                    pcall(function()
                        char:K2_SetActorLocation(spawnLoc, false, {}, true)
                        Log("Moved character to spawn")
                    end)

                    -- Enable input on controller
                    pcall(function()
                        pc:EnableInput(pc)
                        Log("EnableInput called")
                    end)

                    -- Set replication
                    pcall(function()
                        if char.SetReplicates then
                            char:SetReplicates(true)
                            Log("SetReplicates(true) called")
                        end
                    end)

                    -- Try to enable movement
                    pcall(function()
                        local movement = char.CharacterMovement
                        if movement then
                            movement:SetMovementMode(1) -- Walking
                            Log("SetMovementMode called")
                        end
                    end)

                    -- Client restart to init properly
                    pcall(function()
                        if pc.ClientRestart then
                            pc:ClientRestart(char)
                            Log("ClientRestart with pawn called")
                        end
                    end)

                    -- Acknowledge possession
                    pcall(function()
                        if pc.AcknowledgePossession then
                            pc:AcknowledgePossession(char)
                            Log("AcknowledgePossession called")
                        end
                    end)

                    -- Set owner for replication
                    pcall(function()
                        if char.SetOwner then
                            char:SetOwner(pc)
                            Log("SetOwner called")
                        end
                    end)

                    -- Force net update
                    pcall(function()
                        if char.ForceNetUpdate then
                            char:ForceNetUpdate()
                            Log("ForceNetUpdate called")
                        end
                    end)

                    -- Set autonomous proxy (client authority)
                    pcall(function()
                        if char.SetAutonomousProxy then
                            char:SetAutonomousProxy(true)
                            Log("SetAutonomousProxy called")
                        end
                    end)

                    -- Try OnRep functions
                    pcall(function()
                        if char.OnRep_Controller then
                            char:OnRep_Controller()
                            Log("OnRep_Controller called")
                        end
                    end)

                    pcall(function()
                        if char.OnRep_PlayerState then
                            char:OnRep_PlayerState()
                            Log("OnRep_PlayerState called")
                        end
                    end)

                    -- Restart the player properly via GameMode
                    pcall(function()
                        local gm = FindFirstOf("GameModeBase")
                        if gm and gm.RestartPlayerAtPlayerStart then
                            local starts = FindAllOf("PlayerStart")
                            if starts and #starts > 0 then
                                gm:RestartPlayerAtPlayerStart(pc, starts[1])
                                Log("RestartPlayerAtPlayerStart called")
                            end
                        end
                    end)

                    break
                end
            end
        end
    end)
end

local function CheckControllers()
    -- Early exit if not in game
    if not IsInGame() then
        return
    end

    Log("CheckControllers starting...")

    local pcs = nil
    local ok = pcall(function()
        pcs = FindAllOf("PlayerController")
    end)

    if not ok or not pcs then
        Log("Failed to get PlayerControllers")
        return
    end

    local count = 0
    pcall(function() count = #pcs end)

    Log("Found " .. tostring(count) .. " controllers")

    -- Detect new players
    if count > State.LastControllerCount then
        Log("New player detected!")
        State.Tried = {}
    end
    State.LastControllerCount = count

    -- Check each controller
    for i = 1, count do
        SafeCall("CheckController" .. i, function()
            local pc = pcs[i]
            if not IsValid(pc) then
                Log("Controller " .. i .. " invalid")
                return
            end

            local playerName = GetPlayerName(pc)
            local hasPawn = false
            local isLocal = false

            pcall(function()
                hasPawn = pc.Pawn and IsValid(pc.Pawn)
            end)
            pcall(function()
                isLocal = pc:IsLocalController()
            end)

            Log("  " .. i .. ": " .. tostring(playerName) .. " Local=" .. tostring(isLocal) .. " Pawn=" .. tostring(hasPawn))

            -- Remote player without pawn - try to spawn
            if not hasPawn and not isLocal then
                local pcKey = tostring(i)
                if not State.Tried[pcKey] then
                    State.Tried[pcKey] = true
                    Log("Remote player needs pawn!")
                    TrySpawnForController(pc)
                end
            end

            -- Check if player is underground
            if hasPawn then
                pcall(function()
                    local pawnLoc = pc.Pawn:K2_GetActorLocation()
                    if pawnLoc.Z < -500 then
                        Log("Player underground at Z=" .. tostring(pawnLoc.Z))
                        local spawnLoc = GetSpawnLocation()
                        pc.Pawn:K2_SetActorLocation(spawnLoc, false, {}, true)
                        Log("Teleported to Z=" .. tostring(spawnLoc.Z))
                    end
                end)
            end
        end)
    end

    Log("CheckControllers done")
end

-- ============================================
-- CONSOLE COMMANDS
-- ============================================

RegisterKeyBind(Key.F6, function()
    Log("F6 pressed")
    State.Tried = {}
    SafeCall("F6_Check", CheckControllers)
end)

RegisterConsoleCommandHandler("mpfix", function()
    Log("mpfix command")
    State.Tried = {}
    SafeCall("mpfix_Check", CheckControllers)
    return true
end)

RegisterConsoleCommandHandler("mpinfo", function()
    Log("========== MP INFO ==========")

    SafeCall("mpinfo", function()
        Log("IsServer: " .. tostring(IsServer()))
        Log("IsInGame: " .. tostring(IsInGame()))

        local gm = FindFirstOf("GameModeBase")
        if gm then
            local gmName = "?"
            pcall(function() gmName = gm:GetFullName() end)
            Log("GameMode: " .. gmName)
        else
            Log("GameMode: NOT FOUND")
        end

        local pcs = FindAllOf("PlayerController")
        if pcs then
            Log("Controllers: " .. #pcs)
        end

        local chars = FindAllOf("BP_PlayerCharacter_C")
        Log("Characters: " .. tostring(chars and #chars or 0))
    end)

    Log("=============================")
    return true
end)

RegisterConsoleCommandHandler("tphost", function()
    SafeCall("tphost", function()
        -- Get host's pawn location
        local pc = GetLocalPC()
        if not pc then
            Log("No local PC")
            return
        end

        local hostPawn = pc.Pawn
        if not IsValid(hostPawn) then
            Log("Host has no pawn")
            return
        end

        local hostLoc = hostPawn:K2_GetActorLocation()
        Log("Host location: " .. tostring(hostLoc.X) .. "," .. tostring(hostLoc.Y) .. "," .. tostring(hostLoc.Z))

        -- Teleport all other characters TO the host
        local chars = FindAllOf("BP_PlayerCharacter_C")
        if chars then
            local offset = 200
            for _, c in ipairs(chars) do
                if c ~= hostPawn then
                    local newLoc = { X = hostLoc.X + offset, Y = hostLoc.Y, Z = hostLoc.Z + 50 }
                    c:K2_SetActorLocation(newLoc, false, {}, true)
                    Log("Teleported player to host")
                    offset = offset + 200
                end
            end
        end
    end)
    return true
end)

-- ============================================
-- PERIODIC CHECK
-- ============================================

local function StartPeriodicCheck()
    Log("Starting periodic check (every 3s)")

    LoopAsync(3000, function()
        SafeCall("PeriodicCheck", function()
            if IsInGame() then
                CheckControllers()
            end
        end)
        return false -- keep looping
    end)
end

-- ============================================
-- INITIALIZATION
-- ============================================

ExecuteWithDelay(5000, function()
    Log("========================================")
    Log("Initializing MPFix v3.3")
    Log("========================================")

    StartPeriodicCheck()
end)

print("[MPFix] v3.3 Loaded")
print("[MPFix] Commands: mpfix, mpinfo, tphost | F6 = manual fix")
