-- MPFix v4.6 - Server spawn fix + Enhanced client input fix
local UEHelpers = require("UEHelpers")

print("[MPFix] ========================================")
print("[MPFix] Loading v4.6 - Server + Enhanced Client Fix")
print("[MPFix] ========================================")

local Config = {
    CheckInterval = 3000,
    InitialDelay = 5000,
    UndergroundZ = -500,
    SpawnOffsetX = 300,
    SpawnOffsetZ = 100,
    SpawnRetryInterval = 3000,
}

local State = {
    Initialized = false,
    ControllerCount = -1,
    ProcessedControllers = {},
    CharacterClass = nil,
    LastSpawnAttempt = {},
}

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

local function TryRegisterKeyBinds(onF6, onEsc)
    if not RegisterKeyBind or not Key then
        return false
    end
    if not Key.F6 or not Key.ESCAPE then
        return false
    end

    RegisterKeyBind(Key.F6, onF6)
    RegisterKeyBind(Key.ESCAPE, onEsc)
    Log("Keybinds registered (F6, ESC)")
    return true
end

local function GetLocalPlayerController()
    local pcs = FindAllOf("PlayerController") or FindAllOf("Controller")
    if pcs then
        for _, pc in ipairs(pcs) do
            if IsValidObject(pc) then
                local isLocal = false
                pcall(function() isLocal = pc:IsLocalController() end)
                if isLocal then
                    return pc
                end
            end
        end
        for _, pc in ipairs(pcs) do
            if IsValidObject(pc) then
                return pc
            end
        end
    end
    return nil
end

local function GetWorldSafe()
    local pc = GetLocalPlayerController()
    if IsValidObject(pc) then
        local world = nil
        pcall(function() world = pc:GetWorld() end)
        if IsValidObject(world) then
            return world
        end
    end
    local world = nil
    pcall(function() world = FindFirstOf("World") end)
    if IsValidObject(world) then
        return world
    end
    local world = nil
    pcall(function() world = UEHelpers.GetWorld() end)
    if IsValidObject(world) then
        return world
    end
    return nil
end

local function GetNetMode()
    local world = GetWorldSafe()
    if IsValidObject(world) then
        local result = nil
        pcall(function() result = world.NetMode end)
        if result ~= nil then
            return result
        end
        pcall(function()
            if world.GetNetMode then
                result = world:GetNetMode()
            end
        end)
        if result ~= nil then
            return result
        end
    end

    local ksl = nil
    pcall(function() ksl = UEHelpers.GetKismetSystemLibrary() end)
    if IsValidObject(ksl) then
        local ctx = GetWorldSafe() or GetLocalPlayerController()
        if IsValidObject(ctx) then
            local result = nil
            pcall(function()
                if ksl.GetNetMode then
                    result = ksl:GetNetMode(ctx)
                end
            end)
            if result ~= nil then
                return result
            end
        end
    end

    return nil
end

local function GetNetDriver()
    local world = GetWorldSafe()
    if IsValidObject(world) then
        local nd = nil
        pcall(function() nd = world.NetDriver end)
        if IsValidObject(nd) then return nd end
        pcall(function() nd = world.GameNetDriver end)
        if IsValidObject(nd) then return nd end
    end
    return nil
end

local function IsServer()
    local netDriver = GetNetDriver()
    if IsValidObject(netDriver) then
        local serverConn = nil
        pcall(function() serverConn = netDriver.ServerConnection end)
        if IsValidObject(serverConn) then
            return false
        end

        local clientConns = nil
        pcall(function() clientConns = netDriver.ClientConnections end)
        if clientConns and #clientConns > 0 then
            return true
        end

        local netMode = GetNetMode()
        if netMode == 0 or netMode == 1 or netMode == 2 then
            return true
        end

        return false
    end

    local netMode = GetNetMode()
    if netMode == 3 then return false end
    if netMode == 0 or netMode == 1 or netMode == 2 then return true end
    return false
end

local function IsInGame()
    local gs = nil
    pcall(function() gs = FindFirstOf("GameStateBase") end)
    if IsValidObject(gs) then
        return true
    end

    local gm = nil
    pcall(function() gm = FindFirstOf("GameModeBase") end)
    if IsValidObject(gm) then
        return true
    end

    local netDriver = GetNetDriver()
    if IsValidObject(netDriver) then
        return true
    end

    return false
end

local function GetValidSpawnLocation()
    local spawnLoc = { X = 0, Y = 0, Z = 5000 }

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

    if spawnLoc.Z > 4000 then
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

local function GetCharacterClass()
    if State.CharacterClass and IsValidObject(State.CharacterClass) then
        return State.CharacterClass
    end

    pcall(function()
        local char = FindFirstOf("BP_PlayerCharacter_C")
        if IsValidObject(char) then
            State.CharacterClass = char:GetClass()
            if State.CharacterClass then
                Log("Cached character class")
            end
        end
    end)

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
-- CLIENT-SIDE INPUT FIX (v4.6 Enhanced)
-- ============================================

local function SetupEnhancedInput(pc, pawn)
    -- Try to setup Enhanced Input System (UE5)
    pcall(function()
        local localPlayer = nil
        pcall(function() localPlayer = pc:GetLocalPlayer() end)
        if IsValidObject(localPlayer) then
            local subsystem = nil
            pcall(function()
                local subsystemClass = StaticFindObject("/Script/EnhancedInput.EnhancedInputLocalPlayerSubsystem")
                if subsystemClass and IsValidObject(subsystemClass) then
                    subsystem = localPlayer:GetSubsystem(subsystemClass)
                end
            end)
            if IsValidObject(subsystem) then
                Log("Found Enhanced Input Subsystem")
                local mappingContexts = FindAllOf("InputMappingContext")
                if mappingContexts then
                    for _, context in ipairs(mappingContexts) do
                        if IsValidObject(context) then
                            pcall(function()
                                subsystem:AddMappingContext(context, 0)
                                Log("Added mapping context")
                            end)
                        end
                    end
                end
            end
        end
    end)
end

local function FixLocalInput()
    Log("Fixing local input (v4.6 enhanced)...")

    pcall(function()
        local pc = GetLocalPlayerController()
        if not IsValidObject(pc) then
            Log("No local controller found")
            return
        end

        Log("Found local controller")
        local pawn = nil
        pcall(function() pawn = pc:GetPawn() end)

        -- 1. Enable input on controller
        pcall(function()
            if pc.EnableInput then pc:EnableInput(pc) end
        end)

        -- 2. Reset all input ignore flags
        pcall(function()
            if pc.ResetIgnoreInputFlags then pc:ResetIgnoreInputFlags() end
        end)
        pcall(function()
            if pc.SetIgnoreMoveInput then pc:SetIgnoreMoveInput(false) end
            if pc.SetIgnoreLookInput then pc:SetIgnoreLookInput(false) end
        end)

        -- 3. Set input mode to game only (helps movement)
        pcall(function()
            if pc.SetInputModeGameOnly then
                pc:SetInputModeGameOnly()
                Log("Set InputMode to GameOnly")
            elseif pc.SetInputModeGameAndUI then
                pc:SetInputModeGameAndUI(nil, false, false)
                Log("Set InputMode to GameAndUI")
            end
        end)

        -- 4. Mouse setup for gameplay
        pcall(function()
            if pc.SetShowMouseCursor then pc:SetShowMouseCursor(false) end
        end)
        pcall(function()
            if pc.bShowMouseCursor ~= nil then pc.bShowMouseCursor = false end
        end)

        -- 5. Pawn-specific input setup
        if IsValidObject(pawn) then
            Log("Setting up pawn input...")

            -- Enable input on pawn
            pcall(function()
                if pawn.EnableInput then pawn:EnableInput(pc) end
            end)

            -- Set controller rotation usage
            pcall(function()
                if pawn.bUseControllerRotationYaw ~= nil then
                    pawn.bUseControllerRotationYaw = true
                end
            end)

            -- Movement component setup
            pcall(function()
                local movement = pawn.CharacterMovement
                if movement then
                    Log("Setting up CharacterMovement...")
                    -- Set to walking mode
                    if movement.SetMovementMode then
                        movement:SetMovementMode(1)
                    end
                    -- Activate component
                    if movement.Activate then
                        movement:Activate(false)
                    end
                    -- Reset any constraints
                    if movement.SetPlaneConstraintEnabled then
                        movement:SetPlaneConstraintEnabled(false)
                    end
                    -- Check/fix walk speed
                    if movement.MaxWalkSpeed then
                        local speed = movement.MaxWalkSpeed
                        if speed == 0 or speed < 100 then
                            movement.MaxWalkSpeed = 600
                            Log("Fixed MaxWalkSpeed: " .. tostring(speed) .. " -> 600")
                        else
                            Log("MaxWalkSpeed: " .. tostring(speed))
                        end
                    end
                end
            end)

            pcall(function()
                if pawn.Restart then
                    pawn:Restart()
                    Log("Called pawn Restart")
                end
            end)

            -- Force view target
            pcall(function()
                if pc.SetViewTarget then
                    pc:SetViewTarget(pawn)
                end
            end)

            -- Trigger replication callbacks
            pcall(function()
                if pawn.OnRep_Controller then pawn:OnRep_Controller() end
            end)
            pcall(function()
                if pawn.OnRep_PlayerState then pawn:OnRep_PlayerState() end
            end)

            pcall(function()
                if pawn.InputComponent and pc.PushInputComponent then
                    pc:PushInputComponent(pawn.InputComponent)
                    Log("Pushed pawn InputComponent")
                end
            end)
        end

        -- 6. Try Enhanced Input setup
        SetupEnhancedInput(pc, pawn)

        -- 7. Acknowledge possession
        if IsValidObject(pawn) then
            pcall(function()
                if pc.AcknowledgePossession then
                    pc:AcknowledgePossession(pawn)
                    Log("Called AcknowledgePossession")
                end
            end)
        end

        Log("Input fix complete")
    end)
end

-- Escape key handler as backup for pause menu
local function OnEscapeKey()
    Log("Escape pressed - trying pause menu")
    pcall(function()
        local pc = nil
        local pcs = FindAllOf("PlayerController")
        if pcs then
            for _, p in ipairs(pcs) do
                if IsValidObject(p) and p:IsLocalController() then
                    pc = p
                    break
                end
            end
        end
        if pc then
            -- Try SetPause
            pcall(function()
                if pc.SetPause then
                    local isPaused = false
                    pcall(function() isPaused = pc:IsPaused() end)
                    pc:SetPause(not isPaused)
                    Log("Toggled pause: " .. tostring(not isPaused))
                end
            end)
            -- Try showing pause widget
            pcall(function()
                local widgets = FindAllOf("BP_PauseMenu_C")
                if not widgets then widgets = FindAllOf("WBP_PauseMenu_C") end
                if widgets and #widgets > 0 then
                    local menu = widgets[1]
                    if IsValidObject(menu) and menu.SetVisibility then
                        menu:SetVisibility(0)
                        Log("Showed pause menu widget")
                    end
                end
            end)
        end
    end)
end

-- ============================================
-- SERVER-SIDE SPAWN FIX
-- ============================================

local function SetupPossessedPawn(pc, pawn)
    if not IsValidObject(pc) or not IsValidObject(pawn) then return end

    Log("Setting up possessed pawn...")

    pcall(function() if pc.EnableInput then pc:EnableInput(pc) end end)
    pcall(function() if pc.SetInputModeGameOnly then pc:SetInputModeGameOnly() end end)
    pcall(function()
        if pc.SetIgnoreMoveInput then pc:SetIgnoreMoveInput(false) end
        if pc.SetIgnoreLookInput then pc:SetIgnoreLookInput(false) end
    end)
    pcall(function() if pc.SetPawn then pc:SetPawn(pawn) end end)
    pcall(function() if pc.OnRep_Pawn then pc:OnRep_Pawn() end end)

    pcall(function() if pawn.SetOwner then pawn:SetOwner(pc) end end)
    pcall(function()
        if pawn.SetReplicates then pawn:SetReplicates(true) end
        if pawn.SetReplicateMovement then pawn:SetReplicateMovement(true) end
    end)
    pcall(function() if pawn.ForceNetUpdate then pawn:ForceNetUpdate() end end)
    pcall(function() if pawn.SetAutonomousProxy then pawn:SetAutonomousProxy(true) end end)

    pcall(function()
        if pawn.SetActorHiddenInGame then pawn:SetActorHiddenInGame(false) end
        if pawn.SetHidden then pawn:SetHidden(false) end
        if pawn.bHidden ~= nil then pawn.bHidden = false end
    end)

    pcall(function()
        if pawn.bOnlyRelevantToOwner ~= nil then pawn.bOnlyRelevantToOwner = false end
        if pawn.bAlwaysRelevant ~= nil then pawn.bAlwaysRelevant = true end
    end)

    pcall(function()
        if pawn.SetNetDormancy then pawn:SetNetDormancy(0) end
        if pawn.FlushNetDormancy then pawn:FlushNetDormancy() end
    end)

    pcall(function()
        local mesh = pawn.Mesh
        if mesh and mesh.SetVisibility then
            mesh:SetVisibility(true, true)
        end
    end)

    pcall(function()
        local movement = pawn.CharacterMovement
        if movement and movement.SetMovementMode then movement:SetMovementMode(1) end
    end)

    pcall(function() if pawn.OnRep_Controller then pawn:OnRep_Controller() end end)
    pcall(function() if pawn.OnRep_PlayerState then pawn:OnRep_PlayerState() end end)
    pcall(function() if pc.AcknowledgePossession then pc:AcknowledgePossession(pawn) end end)
    pcall(function() if pc.ClientRestart then pc:ClientRestart(pawn) end end)

    Log("Pawn setup complete")
end

local function SpawnNewPawnForController(pc, spawnLoc)
    local charClass = GetCharacterClass()
    if not IsValidObject(charClass) then
        Log("No character class available for SpawnActor")
        return false
    end

    local world = nil
    pcall(function() world = pc:GetWorld() end)
    if not IsValidObject(world) then
        Log("No valid world for SpawnActor")
        return false
    end

    local pawn = nil
    pcall(function()
        pawn = world:SpawnActor(charClass, spawnLoc, { Pitch = 0, Yaw = 0, Roll = 0 })
    end)

    if IsValidObject(pawn) then
        Log("SpawnActor created pawn")
        pcall(function()
            if pc.Possess then pc:Possess(pawn) end
        end)
        SetupPossessedPawn(pc, pawn)
        return true
    end

    Log("SpawnActor failed")
    return false
end

local function SpawnPawnForController(pc)
    if not IsValidObject(pc) then return false end

    Log("Attempting spawn for remote client...")
    local spawnLoc = GetValidSpawnLocation()
    Log("Spawn location: " .. tostring(spawnLoc.X) .. "," .. tostring(spawnLoc.Y) .. "," .. tostring(spawnLoc.Z))

    local success = false

    -- Method 0: SpawnActor
    if not success then
        success = SpawnNewPawnForController(pc, spawnLoc)
    end

    -- Method 1: RestartPlayer
    pcall(function()
        local gm = FindFirstOf("GameModeBase")
        if IsValidObject(gm) and gm.RestartPlayer then
            Log("Trying RestartPlayer...")
            gm:RestartPlayer(pc)
            ExecuteWithDelay(500, function()
                local pawn = nil
                pcall(function() pawn = pc:GetPawn() end)
                if IsValidObject(pc) and IsValidObject(pawn) then
                    Log("RestartPlayer SUCCESS!")
                    SetupPossessedPawn(pc, pawn)
                    success = true
                end
            end)
        end
    end)

    -- Method 2: Find unpossessed character
    if not success then
        pcall(function()
            Log("Looking for unpossessed characters...")
            local chars = FindAllOf("BP_PlayerCharacter_C")
            if chars then
                for _, char in ipairs(chars) do
                    if IsValidObject(char) and not IsValidObject(char.Controller) then
                        Log("Found unpossessed character - possessing...")
                        pcall(function() char:K2_SetActorLocation(spawnLoc, false, {}, true) end)
                        pcall(function() pc:Possess(char) end)
                        SetupPossessedPawn(pc, char)
                        success = true
                        return
                    end
                end
            end
        end)
    end

    -- Method 3: ServerRestartPlayer
    if not success then
        pcall(function()
            if pc.ServerRestartPlayer then
                Log("Trying ServerRestartPlayer...")
                pc:ServerRestartPlayer()
            end
        end)
    end

    ExecuteWithDelay(800, function()
        local pawn = nil
        pcall(function() pawn = pc:GetPawn() end)
        if IsValidObject(pawn) then
            SetupPossessedPawn(pc, pawn)
        end
    end)

    return success
end

local function TeleportUndergroundPawn(pawn)
    if not IsValidObject(pawn) then return end
    local spawnLoc = GetValidSpawnLocation()
    pcall(function()
        Log("Teleporting underground pawn to Z=" .. tostring(spawnLoc.Z))
        pawn:K2_SetActorLocation(spawnLoc, false, {}, true)
    end)
end

local function CheckForPawnlessPlayers()
    if not IsServer() or not IsInGame() then return end

    local pcs = nil
    local ok = pcall(function() pcs = FindAllOf("PlayerController") end)
    if not ok or not pcs then return end

    local count = #pcs

    if State.ControllerCount == -1 then
        State.ControllerCount = count
        Log("Initial controller count: " .. tostring(count))
        return
    end

    if count > State.ControllerCount then
        Log("New player joined! " .. tostring(State.ControllerCount) .. " -> " .. tostring(count))
        State.ProcessedControllers = {}
        State.LastSpawnAttempt = {}
    end
    State.ControllerCount = count

    for i, pc in ipairs(pcs) do
        if IsValidObject(pc) then
            local isLocal = false
            pcall(function() isLocal = pc:IsLocalController() end)

            if not isLocal then
                local pawn = nil
                pcall(function() pawn = pc:GetPawn() end)

                local pcKey = tostring(pc:GetAddress())

                if not IsValidObject(pawn) then
                    local nowMs = os.clock() * 1000
                    local lastAttempt = State.LastSpawnAttempt[pcKey] or 0
                    if nowMs - lastAttempt >= Config.SpawnRetryInterval then
                        State.LastSpawnAttempt[pcKey] = nowMs
                        Log("Remote client #" .. tostring(i) .. " has no pawn")
                        SpawnPawnForController(pc)
                    end
                else
                    State.LastSpawnAttempt[pcKey] = nil
                    pcall(function()
                        if pc.Possess and (not IsValidObject(pawn.Controller) or pawn.Controller ~= pc) then
                            Log("Re-possessing pawn for controller")
                            pc:Possess(pawn)
                        end
                    end)

                    pcall(function()
                        local loc = pawn:K2_GetActorLocation()
                        if loc and loc.Z < Config.UndergroundZ then
                            TeleportUndergroundPawn(pawn)
                        end
                    end)

                    if not State.ProcessedControllers[pcKey .. "_setup"] then
                        State.ProcessedControllers[pcKey .. "_setup"] = true
                        SetupPossessedPawn(pc, pawn)
                    end
                end
            end
        end
    end
end

-- Client check
local function CheckClientInput()
    if IsServer() or not IsInGame() then return end

    local localPC = GetLocalPlayerController()
    if not IsValidObject(localPC) then
        return
    end

    local pawn = nil
    pcall(function() pawn = localPC:GetPawn() end)
    if not IsValidObject(pawn) then
        State.ProcessedControllers["client_fixed"] = nil
        return
    end

    local pawnKey = tostring(pawn:GetAddress())
    if State.ProcessedControllers["client_fixed"] ~= pawnKey then
        State.ProcessedControllers["client_fixed"] = pawnKey
        Log("Client has pawn - fixing input")
        FixLocalInput()
    end
end

-- ============================================
-- COMMANDS
-- ============================================

local function OnF6Key()
    Log("F6 pressed")
    State.ProcessedControllers = {}
    State.LastSpawnAttempt = {}
    if IsServer() then
        SafeCall("F6_Server", CheckForPawnlessPlayers)
    end
    SafeCall("F6_Input", FixLocalInput)
end

local function RegisterKeyBindsWithRetry()
    if TryRegisterKeyBinds(OnF6Key, OnEscapeKey) then
        return
    end
    if ExecuteWithDelay then
        ExecuteWithDelay(2000, function()
            if not TryRegisterKeyBinds(OnF6Key, OnEscapeKey) then
                Log("Keybinds unavailable; use console commands (mpfix/mpinput)")
            end
        end)
    else
        Log("Keybinds unavailable; use console commands (mpfix/mpinput)")
    end
end

RegisterKeyBindsWithRetry()

RegisterConsoleCommandHandler("mpfix", function()
    Log("mpfix command")
    State.ProcessedControllers = {}
    State.LastSpawnAttempt = {}
    if IsServer() then
        SafeCall("mpfix_Server", CheckForPawnlessPlayers)
    end
    SafeCall("mpfix_Input", FixLocalInput)
    return true
end)

RegisterConsoleCommandHandler("mpinput", function()
    Log("mpinput - fixing local input")
    SafeCall("mpinput", FixLocalInput)
    return true
end)

RegisterConsoleCommandHandler("mpinfo", function()
    Log("========== MP INFO ==========")
    SafeCall("mpinfo", function()
        Log("NetMode: " .. tostring(GetNetMode()) .. " (0=Standalone, 1=Dedicated, 2=Listen, 3=Client)")
        Log("IsServer: " .. tostring(IsServer()))
        Log("IsInGame: " .. tostring(IsInGame()))

        local netDriver = GetNetDriver()
        if IsValidObject(netDriver) then
            local serverConn = "nil"
            pcall(function()
                if netDriver.ServerConnection then
                    serverConn = tostring(netDriver.ServerConnection)
                end
            end)
            local clientCount = "nil"
            pcall(function()
                if netDriver.ClientConnections then
                    clientCount = tostring(#netDriver.ClientConnections)
                end
            end)
            Log("NetDriver.ServerConnection: " .. tostring(serverConn))
            Log("NetDriver.ClientConnections: " .. tostring(clientCount))
        else
            Log("NetDriver: nil")
        end

        local pcs = FindAllOf("PlayerController")
        if pcs then
            Log("Controllers: " .. tostring(#pcs))
            for i, pc in ipairs(pcs) do
                if IsValidObject(pc) then
                    local isLocal = false
                    pcall(function() isLocal = pc:IsLocalController() end)
                    local pawn = nil
                    pcall(function() pawn = pc:GetPawn() end)
                    local hasPawn = IsValidObject(pawn)
                    Log("  #" .. i .. ": Local=" .. tostring(isLocal) .. " Pawn=" .. tostring(hasPawn))
                end
            end
        end
    end)
    Log("=============================")
    return true
end)

-- Debug command to show detailed pawn/input status
RegisterConsoleCommandHandler("mpdebug", function()
    Log("========== MP DEBUG ==========")
    SafeCall("mpdebug", function()
        local pc = GetLocalPlayerController()
        if not IsValidObject(pc) then
            Log("Local PlayerController not found")
            return
        end

        Log("Local PlayerController found")

        local hasAuthority = "unknown"
        pcall(function()
            if pc.HasAuthority then
                hasAuthority = pc:HasAuthority()
            end
        end)
        Log("  HasAuthority: " .. tostring(hasAuthority))
        Log("  NetMode: " .. tostring(GetNetMode()))

        local ignoringMove = "unknown"
        pcall(function()
            if pc.IsMoveInputIgnored then
                ignoringMove = pc:IsMoveInputIgnored()
            end
        end)
        if ignoringMove == "unknown" then
            pcall(function() ignoringMove = pc.bIgnoreMoveInput end)
        end

        local ignoringLook = "unknown"
        pcall(function()
            if pc.IsLookInputIgnored then
                ignoringLook = pc:IsLookInputIgnored()
            end
        end)
        if ignoringLook == "unknown" then
            pcall(function() ignoringLook = pc.bIgnoreLookInput end)
        end

        Log("  IgnoreMoveInput: " .. tostring(ignoringMove))
        Log("  IgnoreLookInput: " .. tostring(ignoringLook))

        -- Check pawn
        local pawn = nil
        pcall(function() pawn = pc:GetPawn() end)
        if IsValidObject(pawn) then
            Log("  Pawn: " .. tostring(pawn:GetFullName()))

            pcall(function()
                if pawn.Controller then
                    Log("  Pawn.Controller: " .. tostring(pawn.Controller:GetFullName()))
                end
            end)

            -- Movement component
            pcall(function()
                local movement = pawn.CharacterMovement
                if movement then
                    Log("  CharacterMovement:")
                    Log("    MovementMode: " .. tostring(movement.MovementMode))
                    Log("    MaxWalkSpeed: " .. tostring(movement.MaxWalkSpeed))
                    Log("    IsActive: " .. tostring(movement:IsActive()))
                    if movement.Velocity then
                        Log("    Velocity: " .. tostring(movement.Velocity.X) .. "," .. tostring(movement.Velocity.Y) .. "," .. tostring(movement.Velocity.Z))
                    end
                end
            end)

            -- Input component
            pcall(function()
                if pawn.InputComponent then
                    Log("  Pawn InputComponent: EXISTS")
                else
                    Log("  Pawn InputComponent: MISSING")
                end
            end)
        else
            Log("  Pawn: NONE")
        end
    end)
    Log("==============================")
    return true
end)

-- Force movement test command
RegisterConsoleCommandHandler("mpmove", function()
    Log("Testing movement...")
    SafeCall("mpmove", function()
        local pcs = FindAllOf("PlayerController")
        if pcs then
            for _, pc in ipairs(pcs) do
                if IsValidObject(pc) and pc:IsLocalController() then
                    local pawn = pc:GetPawn()
                    if IsValidObject(pawn) then
                        -- Try to move forward
                        pcall(function()
                            local loc = pawn:K2_GetActorLocation()
                            local rot = pc:GetControlRotation()
                            -- Move forward 100 units
                            local newLoc = {
                                X = loc.X + 100,
                                Y = loc.Y,
                                Z = loc.Z
                            }
                            pawn:K2_SetActorLocation(newLoc, false, {}, true)
                            Log("Moved pawn forward 100 units")
                        end)

                        -- Try AddMovementInput
                        pcall(function()
                            if pawn.AddMovementInput then
                                pawn:AddMovementInput({X=1, Y=0, Z=0}, 1.0, false)
                                Log("Called AddMovementInput")
                            end
                        end)
                    end
                    break
                end
            end
        end
    end)
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
        Log("Host: " .. tostring(hostLoc.X) .. "," .. tostring(hostLoc.Y) .. "," .. tostring(hostLoc.Z))

        local chars = FindAllOf("BP_PlayerCharacter_C")
        if chars then
            local offset = 200
            for _, c in ipairs(chars) do
                if c ~= localPC.Pawn and IsValidObject(c) then
                    pcall(function()
                        c:K2_SetActorLocation({ X = hostLoc.X + offset, Y = hostLoc.Y, Z = hostLoc.Z + 50 }, false, {}, true)
                    end)
                    Log("Teleported player at offset " .. tostring(offset))
                    offset = offset + 200
                end
            end
        end
    end)
    return true
end)

-- ============================================
-- INIT
-- ============================================

ExecuteWithDelay(Config.InitialDelay, function()
    Log("========================================")
    Log("Initializing MPFix v4.6")
    Log("NetMode: " .. tostring(GetNetMode()))
    Log("IsServer: " .. tostring(IsServer()))
    Log("========================================")

    GetCharacterClass()

    Log("Starting periodic check (every " .. tostring(Config.CheckInterval) .. "ms)")
    LoopAsync(Config.CheckInterval, function()
        if IsServer() then
            SafeCall("ServerCheck", CheckForPawnlessPlayers)
        else
            SafeCall("ClientCheck", CheckClientInput)
        end
        return false
    end)

    State.Initialized = true
end)

print("[MPFix] v4.6 Loaded")
print("[MPFix] Commands: mpfix, mpinfo, mpinput, mpdebug, mpmove, tphost | F6 = manual fix | ESC = pause menu")
