-- MPFix v4.0 - Rewritten based on C++ ModActor implementation
-- Focuses on server-side spawn fix with proper safety checks

local UEHelpers = require("UEHelpers")

print("[MPFix] ========================================")
print("[MPFix] Loading v4.0 - Server-Side Spawn Fix")
print("[MPFix] ========================================")

-- Configuration
local Config = {
    CheckInterval = 3000,      -- ms between checks
    InitialDelay = 5000,       -- ms before first check
    UndergroundZ = -500,       -- Z threshold for underground detection
    SpawnOffsetX = 300,        -- X offset from reference spawn
    SpawnOffsetZ = 100,        -- Z offset (above ground)
}

-- State tracking
local State = {
    Initialized = false,
    ControllerCount = -1,      -- -1 = not yet counted (prevents false "new player" on first run)
    ProcessedControllers = {}, -- Track which controllers we've tried to fix
    CharacterClass = nil,      -- Cached character class
}

-- ============================================
-- UTILITY FUNCTIONS
-- ============================================

local function Log(msg)
    print("[MPFix] " .. tostring(msg))
end

local function SafeCall(name, fn)
    local ok, err = pcall(fn)
    if not ok then
        Log("ERROR in " .. name .. ": " .. tostring(err))
    end
    return ok, err
end

local function IsValidObject(obj)
    if not obj then return false end
    local ok, result = pcall(function()
        return obj:IsValid()
    end)
    return ok and result
end

local function GetNetMode()
    -- Returns: 0=Standalone, 1=DedicatedServer, 2=ListenServer, 3=Client
    local result = 0
    pcall(function()
        local world = UEHelpers.GetWorld()
        if world and world.GetNetMode then
            result = world:GetNetMode()
        end
    end)
    return result
end

local function IsServer()
    local netMode = GetNetMode()
    -- Server = DedicatedServer(1) or ListenServer(2) or Standalone(0)
    return netMode ~= 3
end

local function IsInGame()
    local result = false
    pcall(function()
        local gm = FindFirstOf("GameModeBase")
        result = IsValidObject(gm)
    end)
    return result
end

-- ============================================
-- SPAWN LOCATION
-- ============================================

local function GetValidSpawnLocation()
    local spawnLoc = { X = 0, Y = 0, Z = 5000 } -- Fallback high spawn

    -- Method 1: Try PlayerStart
    pcall(function()
        local starts = FindAllOf("PlayerStart")
        if starts and #starts > 0 then
            local start = starts[1]
            if IsValidObject(start) then
                local loc = start:K2_GetActorLocation()
                if loc and loc.Z > Config.UndergroundZ then
                    spawnLoc = { X = loc.X + Config.SpawnOffsetX, Y = loc.Y, Z = loc.Z + Config.SpawnOffsetZ }
                    return
                end
            end
        end
    end)

    -- Method 2: Find existing character above ground
    if spawnLoc.Z > 4000 then -- Still using fallback
        pcall(function()
            local chars = FindAllOf("Character")
            if chars then
                for _, char in ipairs(chars) do
                    if IsValidObject(char) then
                        local loc = char:K2_GetActorLocation()
                        if loc and loc.Z > Config.UndergroundZ then
                            spawnLoc = { X = loc.X + Config.SpawnOffsetX, Y = loc.Y, Z = loc.Z + Config.SpawnOffsetZ }
                            return
                        end
                    end
                end
            end
        end)
    end

    return spawnLoc
end

-- ============================================
-- CHARACTER CLASS LOADING
-- ============================================

local function GetCharacterClass()
    if State.CharacterClass and IsValidObject(State.CharacterClass) then
        return State.CharacterClass
    end

    -- Try to find existing BP_PlayerCharacter and get its class
    pcall(function()
        local char = FindFirstOf("BP_PlayerCharacter_C")
        if IsValidObject(char) then
            State.CharacterClass = char:GetClass()
            if State.CharacterClass then
                Log("Cached character class: " .. tostring(State.CharacterClass:GetFullName()))
            end
        end
    end)

    -- Fallback: Try GameMode's DefaultPawnClass
    if not State.CharacterClass then
        pcall(function()
            local gm = FindFirstOf("GameModeBase")
            if IsValidObject(gm) and gm.DefaultPawnClass then
                State.CharacterClass = gm.DefaultPawnClass
                Log("Using GameMode DefaultPawnClass")
            end
        end)
    end

    return State.CharacterClass
end

-- ============================================
-- SPAWN AND POSSESSION
-- ============================================

local function SetupPossessedPawn(pc, pawn)
    if not IsValidObject(pc) or not IsValidObject(pawn) then return end

    Log("Setting up possessed pawn...")

    -- Enable input
    pcall(function()
        if pc.EnableInput then
            pc:EnableInput(pc)
        end
    end)

    -- Set input mode to game only
    pcall(function()
        if pc.SetInputModeGameOnly then
            pc:SetInputModeGameOnly()
        end
    end)

    -- Disable move/look input ignore
    pcall(function()
        if pc.SetIgnoreMoveInput then
            pc:SetIgnoreMoveInput(false)
        end
        if pc.SetIgnoreLookInput then
            pc:SetIgnoreLookInput(false)
        end
    end)

    -- Set ownership for replication
    pcall(function()
        if pawn.SetOwner then
            pawn:SetOwner(pc)
        end
    end)

    -- Enable replication
    pcall(function()
        if pawn.SetReplicates then
            pawn:SetReplicates(true)
        end
        if pawn.SetReplicateMovement then
            pawn:SetReplicateMovement(true)
        end
    end)

    -- Force network update
    pcall(function()
        if pawn.ForceNetUpdate then
            pawn:ForceNetUpdate()
        end
    end)

    -- Set autonomous proxy for client authority
    pcall(function()
        if pawn.SetAutonomousProxy then
            pawn:SetAutonomousProxy(true)
        end
    end)

    -- Enable movement
    pcall(function()
        local movement = pawn.CharacterMovement
        if movement and movement.SetMovementMode then
            movement:SetMovementMode(1) -- Walking
        end
    end)

    -- Call replication notify functions
    pcall(function()
        if pawn.OnRep_Controller then
            pawn:OnRep_Controller()
        end
    end)

    pcall(function()
        if pawn.OnRep_PlayerState then
            pawn:OnRep_PlayerState()
        end
    end)

    -- Acknowledge possession
    pcall(function()
        if pc.AcknowledgePossession then
            pc:AcknowledgePossession(pawn)
        end
    end)

    -- Client restart to finalize
    pcall(function()
        if pc.ClientRestart then
            pc:ClientRestart(pawn)
        end
    end)

    Log("Pawn setup complete")
end

local function SpawnPawnForController(pc)
    if not IsValidObject(pc) then
        Log("SpawnPawnForController: Invalid controller")
        return false
    end

    Log("Attempting to spawn pawn for remote client...")

    local spawnLoc = GetValidSpawnLocation()
    Log("Spawn location: X=" .. tostring(spawnLoc.X) .. " Y=" .. tostring(spawnLoc.Y) .. " Z=" .. tostring(spawnLoc.Z))

    -- Method 1: Try GameMode RestartPlayer (simplest, most reliable if it works)
    local success = false
    pcall(function()
        local gm = FindFirstOf("GameModeBase")
        if IsValidObject(gm) and gm.RestartPlayer then
            Log("Trying RestartPlayer...")
            gm:RestartPlayer(pc)

            -- Check if it worked
            ExecuteWithDelay(500, function()
                if IsValidObject(pc) and IsValidObject(pc.Pawn) then
                    Log("RestartPlayer SUCCESS!")
                    SetupPossessedPawn(pc, pc.Pawn)
                    success = true
                end
            end)
        end
    end)

    -- Method 2: Find unpossessed character and possess it
    if not success then
        pcall(function()
            Log("Looking for unpossessed characters...")
            local chars = FindAllOf("BP_PlayerCharacter_C")
            if chars then
                for _, char in ipairs(chars) do
                    if IsValidObject(char) then
                        local controller = char.Controller
                        if not IsValidObject(controller) then
                            Log("Found unpossessed character - possessing...")

                            -- Move to spawn location first
                            pcall(function()
                                char:K2_SetActorLocation(spawnLoc, false, nil, true)
                            end)

                            -- Possess
                            pcall(function()
                                pc:Possess(char)
                            end)

                            -- Setup
                            SetupPossessedPawn(pc, char)
                            success = true
                            return
                        end
                    end
                end
            end
        end)
    end

    -- Method 3: Try ServerRestartPlayer
    if not success then
        pcall(function()
            if pc.ServerRestartPlayer then
                Log("Trying ServerRestartPlayer...")
                pc:ServerRestartPlayer()
            end
        end)
    end

    return success
end

local function TeleportUndergroundPawn(pawn)
    if not IsValidObject(pawn) then return end

    local spawnLoc = GetValidSpawnLocation()

    pcall(function()
        local oldLoc = pawn:K2_GetActorLocation()
        Log("Teleporting pawn from Z=" .. tostring(oldLoc.Z) .. " to Z=" .. tostring(spawnLoc.Z))
        pawn:K2_SetActorLocation(spawnLoc, false, nil, true)
    end)
end

-- ============================================
-- MAIN CHECK FUNCTION
-- ============================================

local function CheckForPawnlessPlayers()
    -- Only run on server
    if not IsServer() then
        return
    end

    -- Only run if in game
    if not IsInGame() then
        return
    end

    local pcs = nil
    local ok = pcall(function()
        pcs = FindAllOf("PlayerController")
    end)

    if not ok or not pcs then
        return
    end

    local count = #pcs

    -- First run initialization
    if State.ControllerCount == -1 then
        State.ControllerCount = count
        Log("Initial controller count: " .. tostring(count))
        return -- Don't process on first run
    end

    -- Detect new players
    if count > State.ControllerCount then
        Log("New player joined! Controllers: " .. tostring(State.ControllerCount) .. " -> " .. tostring(count))
        -- Clear processed list for new players
        State.ProcessedControllers = {}
    end
    State.ControllerCount = count

    -- Check each controller
    for i, pc in ipairs(pcs) do
        if IsValidObject(pc) then
            -- Skip local controller (host)
            local isLocal = false
            pcall(function()
                isLocal = pc:IsLocalController()
            end)

            if not isLocal then
                -- This is a remote client
                local pawn = nil
                pcall(function()
                    pawn = pc:GetPawn()
                end)

                local pcKey = tostring(pc:GetAddress())

                if not IsValidObject(pawn) then
                    -- No pawn - spawn one
                    if not State.ProcessedControllers[pcKey] then
                        State.ProcessedControllers[pcKey] = true
                        Log("Remote client #" .. tostring(i) .. " has no pawn - spawning...")
                        SpawnPawnForController(pc)
                    end
                else
                    -- Has pawn - check if underground
                    pcall(function()
                        local loc = pawn:K2_GetActorLocation()
                        if loc and loc.Z < Config.UndergroundZ then
                            Log("Remote client #" .. tostring(i) .. " is underground (Z=" .. tostring(loc.Z) .. ")")
                            TeleportUndergroundPawn(pawn)
                        end
                    end)

                    -- Ensure pawn is properly set up
                    if not State.ProcessedControllers[pcKey .. "_setup"] then
                        State.ProcessedControllers[pcKey .. "_setup"] = true
                        SetupPossessedPawn(pc, pawn)
                    end
                end
            end
        end
    end
end

-- ============================================
-- CONSOLE COMMANDS
-- ============================================

RegisterKeyBind(Key.F6, function()
    Log("F6 pressed - manual check")
    State.ProcessedControllers = {}
    SafeCall("F6_Check", CheckForPawnlessPlayers)
end)

RegisterConsoleCommandHandler("mpfix", function()
    Log("mpfix command - forcing spawn check")
    State.ProcessedControllers = {}
    SafeCall("mpfix_Check", CheckForPawnlessPlayers)
    return true
end)

RegisterConsoleCommandHandler("mpinfo", function()
    Log("========== MP INFO ==========")
    SafeCall("mpinfo", function()
        Log("NetMode: " .. tostring(GetNetMode()) .. " (0=Standalone, 1=Dedicated, 2=Listen, 3=Client)")
        Log("IsServer: " .. tostring(IsServer()))
        Log("IsInGame: " .. tostring(IsInGame()))
        Log("ControllerCount: " .. tostring(State.ControllerCount))

        local gm = FindFirstOf("GameModeBase")
        if gm then
            Log("GameMode: " .. tostring(gm:GetFullName()))
        end

        local pcs = FindAllOf("PlayerController")
        if pcs then
            Log("Controllers found: " .. tostring(#pcs))
            for i, pc in ipairs(pcs) do
                if IsValidObject(pc) then
                    local isLocal = pcall(function() return pc:IsLocalController() end) and pc:IsLocalController()
                    local hasPawn = IsValidObject(pc.Pawn)
                    Log("  #" .. i .. ": Local=" .. tostring(isLocal) .. " HasPawn=" .. tostring(hasPawn))
                end
            end
        end

        local chars = FindAllOf("BP_PlayerCharacter_C")
        Log("BP_PlayerCharacter_C count: " .. tostring(chars and #chars or 0))
    end)
    Log("=============================")
    return true
end)

RegisterConsoleCommandHandler("tphost", function()
    SafeCall("tphost", function()
        local localPC = nil
        local pcs = FindAllOf("PlayerController")
        if pcs then
            for _, pc in ipairs(pcs) do
                if IsValidObject(pc) and pc:IsLocalController() then
                    localPC = pc
                    break
                end
            end
        end

        if not localPC or not IsValidObject(localPC.Pawn) then
            Log("Host has no pawn")
            return
        end

        local hostLoc = localPC.Pawn:K2_GetActorLocation()
        Log("Host location: " .. tostring(hostLoc.X) .. "," .. tostring(hostLoc.Y) .. "," .. tostring(hostLoc.Z))

        local chars = FindAllOf("BP_PlayerCharacter_C")
        if chars then
            local offset = 200
            for _, c in ipairs(chars) do
                if c ~= localPC.Pawn and IsValidObject(c) then
                    local newLoc = { X = hostLoc.X + offset, Y = hostLoc.Y, Z = hostLoc.Z + 50 }
                    c:K2_SetActorLocation(newLoc, false, nil, true)
                    Log("Teleported player to host")
                    offset = offset + 200
                end
            end
        end
    end)
    return true
end)

-- ============================================
-- INITIALIZATION
-- ============================================

ExecuteWithDelay(Config.InitialDelay, function()
    Log("========================================")
    Log("Initializing MPFix v4.0")
    Log("NetMode: " .. tostring(GetNetMode()))
    Log("IsServer: " .. tostring(IsServer()))
    Log("========================================")

    -- Pre-cache character class
    GetCharacterClass()

    -- Start periodic check
    Log("Starting periodic check (every " .. tostring(Config.CheckInterval) .. "ms)")
    LoopAsync(Config.CheckInterval, function()
        SafeCall("PeriodicCheck", CheckForPawnlessPlayers)
        return false -- keep looping
    end)

    State.Initialized = true
end)

print("[MPFix] v4.0 Loaded")
print("[MPFix] Commands: mpfix, mpinfo, tphost | F6 = manual fix")
