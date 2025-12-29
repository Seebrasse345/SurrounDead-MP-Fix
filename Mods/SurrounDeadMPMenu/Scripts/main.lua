-- SurrounDead MP Menu Enabler (UE4SS)
-- Shows the built-in MP menu (if hidden) and wires Host/Join to open commands.

local MOD_NAME = "SurrounDeadMPMenu"
local VERSION = "1.2.3"

local Config = {
    HostMap = "LongdownValley",
    DefaultJoinIP = "127.0.0.1:7777",
    Debug = true,
}

local State = {
    MainMenu = nil,
    MPUIEnabled = false,
    HasMPButtons = false,
    LastMenuCheck = 0,
    LeftMouseDown = false,
    TickHookInstalled = false,
    PendingStatusCheck = 0,
    PendingStatusAttempts = 0,
    LastStatusLog = 0,
    HostRequestedAt = 0,
    IsHosting = false,
    LastConnCount = -1,
    NextConnCheck = 0,
    ConnHooksInstalled = false,
    NetHooksInstalled = false,
    FailureHooksInstalled = false,
    LastPossessAttempt = 0,
    LastInputFix = 0,
}

local function Log(msg)
    if Config.Debug then
        print(string.format("[%s] %s", MOD_NAME, msg))
    end
end

local function IsValidObj(obj)
    if not obj then return false end
    local ok, valid = pcall(function()
        if obj.IsValid then
            return obj:IsValid()
        end
        return false
    end)
    if ok then
        return valid
    end
    return false
end

local FindGameNetDriver

local function FStringToString(value)
    if value == nil then return nil end
    if type(value) == "string" then return value end
    local ok, str = pcall(function()
        if (type(value) == "userdata" or type(value) == "table") and value.ToString then
            return value:ToString()
        end
        return tostring(value)
    end)
    if not ok then return nil end
    if not str or str == "" then return nil end
    if str:find("FString:", 1, true) then
        return nil
    end
    return str
end

local function IsPathLike(path)
    if not path or path == "" then return false end
    if path:match("^[A-Za-z]:[\\/].+") then return true end
    if path:match("^\\\\") then return true end
    return false
end

local function NormalizePath(path)
    if not path then return nil end
    return tostring(path):gsub("/", "\\")
end

local function EnsureTrailingSlash(path)
    if not path then return nil end
    path = NormalizePath(path)
    if not path:match("[\\/]$") then
        path = path .. "\\"
    end
    return path
end

local function GetScriptDir()
    local info = debug.getinfo(1, "S")
    if not info or not info.source then
        return ".\\"
    end
    local source = info.source
    if source:sub(1, 1) == "@" then
        source = source:sub(2)
    end
    return (source:match("^(.*[\\/])") or ".\\")
end

local function GetModDir()
    local scriptDir = GetScriptDir()
    return (scriptDir:gsub("[\\/]+[Ss]cripts[\\/]+$", "\\"))
end

local function GetProjectDir()
    local dir = nil
    pcall(function()
        if StaticFindObject then
            local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            if KSL and KSL.GetProjectDirectory then
                dir = FStringToString(KSL:GetProjectDirectory())
            end
        end
    end)
    if dir and dir ~= "" then
        return EnsureTrailingSlash(dir)
    end
    return nil
end

local function GetModDirCandidates()
    local dirs = {}

    local scriptDir = GetScriptDir()
    if scriptDir then
        local modDir = scriptDir:gsub("[\\/]+[Ss]cripts[\\/]+$", "\\")
        modDir = EnsureTrailingSlash(modDir)
        if modDir then
            dirs[#dirs + 1] = modDir
        end
    end

    local projectDir = GetProjectDir()
    if projectDir then
        local cand1 = EnsureTrailingSlash(projectDir .. "Binaries\\Win64\\Mods\\" .. MOD_NAME)
        local cand2 = EnsureTrailingSlash(projectDir .. "SurrounDead\\Binaries\\Win64\\Mods\\" .. MOD_NAME)
        dirs[#dirs + 1] = cand1
        dirs[#dirs + 1] = cand2
    end

    if os.getenv then
        local cwd = os.getenv("CD") or os.getenv("PWD")
        if cwd and cwd ~= "" then
            dirs[#dirs + 1] = EnsureTrailingSlash(cwd .. "\\Mods\\" .. MOD_NAME)
        end
    end

    local unique = {}
    local result = {}
    for _, dir in ipairs(dirs) do
        local normalized = NormalizePath(dir)
        if normalized and IsPathLike(normalized) and not unique[normalized] then
            unique[normalized] = true
            result[#result + 1] = normalized
        end
    end

    return result
end

local function ReadTrimmedFile(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    if not content then return nil end
    local trimmed = content:gsub("%s+", "")
    if trimmed == "" then return nil end
    return trimmed
end

local function ReadTrimmedFileFromCandidates(filename)
    local dirs = GetModDirCandidates()
    for _, dir in ipairs(dirs) do
        local path = dir .. filename
        local f = io.open(path, "r")
        if f then
            local content = f:read("*all")
            f:close()
            if content then
                local trimmed = content:gsub("%s+", "")
                if trimmed ~= "" then
                    return trimmed, path
                end
            end
        end
    end
    return nil, nil
end

local function DescribeArg(arg)
    if arg == nil then return "nil" end
    local t = type(arg)
    if t == "string" then return arg end
    if t == "number" or t == "boolean" then return tostring(arg) end
    if t == "userdata" or t == "table" then
        local ok, str = pcall(function()
            if arg.ToString then
                return arg:ToString()
            end
            return tostring(arg)
        end)
        if ok and str and str ~= "" then
            return str
        end
    end
    return tostring(arg)
end

local function GetTArrayNum(arr)
    if not arr then return nil end
    local ok, num = pcall(function()
        if arr.Num then
            if type(arr.Num) == "function" then
                return arr:Num()
            end
            return arr.Num
        end
        if arr.GetArrayNum then
            return arr:GetArrayNum()
        end
        if arr.Length then
            return arr.Length
        end
        return nil
    end)
    if ok and type(num) == "number" then
        return num
    end
    return nil
end

local function CheckClientConnections()
    local now = os.clock()
    if now < State.NextConnCheck then
        return
    end
    State.NextConnCheck = now + 1.0

    local NetDriver = FindGameNetDriver()
    if not NetDriver then
        return
    end
    local count = nil
    pcall(function()
        count = GetTArrayNum(NetDriver.ClientConnections)
    end)
    if count ~= nil and count ~= State.LastConnCount then
        Log("Client connections: " .. tostring(count))
        State.LastConnCount = count
        if State.IsHosting then
            EnsureClientPossession()
        end
    end
end

local function GetControllerPawn(pc)
    if not IsValidObj(pc) then return nil end
    local pawn = nil
    pcall(function()
        if pc.GetPawn then
            pawn = pc:GetPawn()
        end
    end)
    if not IsValidObj(pawn) then
        pcall(function()
            pawn = pc.Pawn
        end)
    end
    if IsValidObj(pawn) then
        return pawn
    end
    return nil
end

local function IsLocalController(pc)
    if not IsValidObj(pc) then return false end
    local isLocal = false
    pcall(function()
        if pc.IsLocalController then
            isLocal = pc:IsLocalController()
        end
    end)
    return isLocal
end

local function HasAuthority()
    local pc = FindFirstOf("PlayerController")
    if not IsValidObj(pc) then return false end
    local auth = false
    pcall(function()
        if pc.HasAuthority then
            auth = pc:HasAuthority()
        end
    end)
    return auth
end

local function HasServerConnection()
    local NetDriver = FindGameNetDriver()
    if not NetDriver then
        return false
    end
    local hasConn = false
    pcall(function()
        hasConn = (NetDriver.ServerConnection ~= nil)
    end)
    return hasConn
end

local function EnsureClientPossession()
    if type(FindAllOf) ~= "function" then
        return
    end
    local now = os.clock()
    if now - State.LastPossessAttempt < 2.0 then
        return
    end
    State.LastPossessAttempt = now

    local gm = FindFirstOf("GameModeBase") or FindFirstOf("GameMode") or FindFirstOf("BP_MPGameMode_C") or FindFirstOf("BP_SurroundeadGameMode_C")
    if not IsValidObj(gm) or not gm.RestartPlayer then
        return
    end

    FindAllOf("PlayerController", function(pc)
        if not IsValidObj(pc) then return end
        if IsLocalController(pc) then return end
        local pawn = GetControllerPawn(pc)
        if not pawn then
            pcall(function()
                gm:RestartPlayer(pc)
            end)
            pcall(function()
                if pc.ClientRestart then
                    pc:ClientRestart()
                end
            end)
            Log("RestartPlayer issued for controller: " .. DescribeArg(pc))
        end
    end)
end

local function FixClientInput()
    local now = os.clock()
    if now - State.LastInputFix < 2.0 then
        return
    end
    State.LastInputFix = now

    local pc = FindFirstOf("PlayerController")
    if not IsValidObj(pc) then return end

    local did = false
    pcall(function()
        if pc.SetInputModeGameOnly then
            pc:SetInputModeGameOnly()
            did = true
        end
    end)
    pcall(function()
        if pc.SetIgnoreMoveInput then
            pc:SetIgnoreMoveInput(false)
            did = true
        end
        if pc.SetIgnoreLookInput then
            pc:SetIgnoreLookInput(false)
            did = true
        end
    end)
    pcall(function()
        if pc.SetShowMouseCursor then
            pc:SetShowMouseCursor(false)
            did = true
        elseif pc.bShowMouseCursor ~= nil then
            pc.bShowMouseCursor = false
            did = true
        end
    end)

    if did then
        Log("Client input unblocked")
    end
end

local function RunInGameThread(fn)
    if ExecuteInGameThread then
        ExecuteInGameThread(fn)
    else
        fn()
    end
end

local function ExecConsoleCmd(cmd)
    RunInGameThread(function()
        -- Method 1: PlayerController:ConsoleCommand
        pcall(function()
            local PC = FindFirstOf("PlayerController")
            if PC and PC:IsValid() then
                PC:ConsoleCommand(cmd, false)
                Log("Exec: " .. cmd)
                return
            end
        end)

        -- Method 2: KismetSystemLibrary::ExecuteConsoleCommand
        pcall(function()
            local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
            if KSL then
                local World = FindFirstOf("World")
                local PC = FindFirstOf("PlayerController")
                KSL:ExecuteConsoleCommand(World, cmd, PC)
                Log("Exec via KSL: " .. cmd)
                return
            end
        end)

        -- Method 3: GEngine->Exec
        pcall(function()
            local Engine = FindFirstOf("GameEngine")
            local World = FindFirstOf("World")
            if Engine and World then
                Engine:Exec(World, cmd)
                Log("Exec via Engine: " .. cmd)
                return
            end
        end)
    end)
end

local function GetJoinIPFromMenu(mainMenu)
    if not mainMenu then return nil end

    local candidates = {
        "JoinIPTextBox",
        "ServerIPTextBox",
        "IPTextBox",
        "JoinIP",
        "ServerIP",
        "JoinAddress",
    }

    for _, name in ipairs(candidates) do
        local widget = mainMenu[name]
        if widget then
            local text = nil
            pcall(function()
                if widget.GetText then
                    local t = widget:GetText()
                    if t and t.ToString then
                        text = t:ToString()
                    else
                        text = tostring(t)
                    end
                elseif widget.Text then
                    text = tostring(widget.Text)
                end
            end)
            if text and text:gsub("%s+", "") ~= "" then
                return text:gsub("%s+", "")
            end
        end
    end

    return nil
end

local function GetJoinIP()
    local menuIP = GetJoinIPFromMenu(State.MainMenu)
    if menuIP then
        return menuIP
    end

    local fileIP, filePath = ReadTrimmedFileFromCandidates("join_ip.txt")
    if fileIP then
        Log("Join IP resolved: " .. fileIP .. " (" .. filePath .. ")")
        return fileIP
    end

    return Config.DefaultJoinIP
end

local function GetHostMap()
    local fileMap, filePath = ReadTrimmedFileFromCandidates("host_map.txt")
    if fileMap then
        Log("Host map resolved: " .. fileMap .. " (" .. filePath .. ")")
        return fileMap
    end

    if Config.HostMap and Config.HostMap ~= "" then
        return Config.HostMap
    end

    return "LongdownValley"
end

local function StartHost()
    local mapName = GetHostMap()
    ExecConsoleCmd("open " .. mapName .. "?listen")
    State.PendingStatusCheck = os.clock() + 5.0
    State.PendingStatusAttempts = 0
    State.HostRequestedAt = os.clock()
    State.IsHosting = false
end

local function StartJoin()
    local ip = GetJoinIP()
    if not ip or ip == "" then
        Log("Join IP missing. Set join_ip.txt in the mod folder.")
        return
    end
    local now = os.clock()
    if State.IsHosting or (State.HostRequestedAt > 0 and (now - State.HostRequestedAt) < 60.0) then
        Log("Join blocked on host instance. Use a second PC/instance to join.")
        return
    end
    local NetDriver = nil
    if type(FindGameNetDriver) == "function" then
        NetDriver = FindGameNetDriver()
    end
    if NetDriver and NetDriver.ServerConnection == nil then
        Log("Join requested while hosting. Use a second instance or another PC.")
        return
    end
    ExecConsoleCmd("open " .. ip)
end

local function SetVisible(widget)
    if not IsValidObj(widget) then return end
    pcall(function()
        if widget.SetVisibility then
            widget:SetVisibility(0) -- Visible
        end
    end)
    pcall(function()
        widget.Visibility = 0
    end)
end

local function SetEnabled(widget)
    if not IsValidObj(widget) then return end
    pcall(function()
        if widget.SetIsEnabled then
            widget:SetIsEnabled(true)
        end
    end)
    pcall(function()
        widget.bIsEnabled = true
    end)
end

local function SetText(widget, text)
    if not IsValidObj(widget) then return end
    pcall(function()
        if widget.SetText then
            widget:SetText(text)
        end
    end)
    pcall(function()
        widget.Text = text
    end)
end

local function ApplyFallbackLabels(mainMenu)
    if not mainMenu then return end
    SetText(mainMenu.ShootingRangeText, "HOST")
    SetText(mainMenu.TutorialText, "JOIN")
end

local function EnableMultiplayerUI(mainMenu)
    if not mainMenu then return false end

    local bools = {
        "bMultiplayerEnabled",
        "bShowMultiplayer",
        "bEnableMultiplayer",
        "bCoopEnabled",
        "bShowCoop",
        "bOnlineEnabled",
    }

    for _, name in ipairs(bools) do
        pcall(function()
            if mainMenu[name] ~= nil then
                mainMenu[name] = true
            end
        end)
    end

    local panels = {
        "MultiplayerPanel",
        "OnlinePanel",
        "CoopPanel",
        "HostPanel",
        "JoinPanel",
    }
    for _, name in ipairs(panels) do
        SetVisible(mainMenu[name])
        SetEnabled(mainMenu[name])
    end

    local buttons = {
        "MultiplayerButton",
        "OnlineButton",
        "CoopButton",
        "HostButton",
        "JoinButton",
    }
    local found = 0
    for _, name in ipairs(buttons) do
        local btn = mainMenu[name]
        if btn then
            found = found + 1
            SetVisible(btn)
            SetEnabled(btn)
        end
    end

    -- Try to force the MP menu state if a state variable or handler exists
    pcall(function()
        if mainMenu.MenuState ~= nil then
            mainMenu.MenuState = 3
        end
    end)
    pcall(function()
        if mainMenu.CurrentState ~= nil then
            mainMenu.CurrentState = 3
        end
    end)
    pcall(function()
        local fnNames = {
            "OnMultiplayerClicked",
            "OnMultiplayerButtonClicked",
            "MultiplayerButtonClicked",
            "OpenMultiplayer",
            "ShowMultiplayer",
        }
        for _, fn in ipairs(fnNames) do
            local f = mainMenu[fn]
            if f then
                pcall(function()
                    f(mainMenu)
                end)
            end
        end
    end)

    State.HasMPButtons = (found > 0)
    if not State.HasMPButtons then
        ApplyFallbackLabels(mainMenu)
    end
    State.MPUIEnabled = true
    return true
end

local function ButtonMatches(button, name)
    if not button or not name then return false end
    local btnName = nil
    local fullName = nil
    pcall(function()
        btnName = button:GetName()
    end)
    pcall(function()
        fullName = button:GetFullName()
    end)

    if btnName == name then
        return true
    end
    if fullName and fullName:find(name, 1, true) then
        return true
    end
    return false
end

local function ButtonIsMainMenu(button)
    local fullName = nil
    pcall(function()
        fullName = button:GetFullName()
    end)
    if fullName and fullName:find("MainMenu", 1, true) then
        return true
    end
    return false
end

local function TryAttachToMenu()
    local mainMenu = FindFirstOf("MainMenu_C")
    if not IsValidObj(mainMenu) then
        return false
    end

    State.MainMenu = mainMenu
    return EnableMultiplayerUI(mainMenu)
end

local function GetNetModeLabel(netMode)
    if netMode == 0 then return "Standalone" end
    if netMode == 1 then return "ListenServer" end
    if netMode == 2 then return "DedicatedServer" end
    if netMode == 3 then return "Client" end
    return tostring(netMode)
end

FindGameNetDriver = function()
    local World = FindFirstOf("World")
    if World then
        local nd = nil
        pcall(function()
            nd = World.NetDriver
        end)
        if IsValidObj(nd) then return nd end
        pcall(function()
            nd = World.GameNetDriver
        end)
        if IsValidObj(nd) then return nd end
    end

    local candidates = {}
    local function consider(obj)
        if not IsValidObj(obj) then return end
        local name = nil
        local fullName = nil
        pcall(function()
            name = obj:GetName()
        end)
        pcall(function()
            fullName = obj:GetFullName()
        end)
        if (name and name:find("GameNetDriver", 1, true)) or (fullName and fullName:find("GameNetDriver", 1, true)) then
            candidates[#candidates + 1] = obj
        end
    end

    if type(FindAllOf) == "function" then
        FindAllOf("NetDriver", consider)
        FindAllOf("SteamSocketsNetDriver", consider)
        FindAllOf("IpNetDriver", consider)
    end

    if #candidates > 0 then
        return candidates[1]
    end

    local fallback = FindFirstOf("SteamSocketsNetDriver") or FindFirstOf("IpNetDriver") or FindFirstOf("NetDriver")
    if IsValidObj(fallback) then
        return fallback
    end

    return nil
end

local function DumpNetStatus()
    local now = os.clock()
    if now - State.LastStatusLog < 1.0 then
        return
    end
    State.LastStatusLog = now

    local hasAuth = false
    local gm = nil
    local PC = FindFirstOf("PlayerController")
    if PC and PC.HasAuthority then
        pcall(function()
            hasAuth = PC:HasAuthority()
        end)
    end
    gm = FindFirstOf("GameModeBase")
    if not gm then
        gm = FindFirstOf("BP_MPGameMode_C")
    end
    if not gm then
        gm = FindFirstOf("BP_SurroundeadGameMode_C")
    end

    local World = FindFirstOf("World")
    local netMode = nil
    if World then
        pcall(function()
            if World.GetNetMode then
                netMode = World:GetNetMode()
            end
        end)
        if netMode == nil then
            pcall(function()
                netMode = World.NetMode
            end)
        end
    end

    if netMode ~= nil then
        Log("NetMode: " .. GetNetModeLabel(netMode))
    end

    local NetDriver = FindGameNetDriver()
    if NetDriver then
        local isServer = false
        if netMode ~= nil then
            isServer = (netMode == 1 or netMode == 2)
        end
        if not isServer then
            isServer = (hasAuth or gm ~= nil)
        end
        if not isServer then
            pcall(function()
                if NetDriver.ServerConnection == nil then
                    isServer = true
                end
            end)
        end
        State.IsHosting = isServer
        Log("ServerMode: " .. tostring(isServer))
        Log("HasAuthority: " .. tostring(hasAuth))
        Log("GameMode: " .. tostring(gm ~= nil))
        pcall(function()
            Log("NetDriver: " .. tostring(NetDriver:GetFullName()))
        end)
        pcall(function()
            Log("NetDriver.ServerConnection: " .. tostring(NetDriver.ServerConnection))
        end)
        pcall(function()
            Log("NetDriver.ClientConnections: " .. tostring(NetDriver.ClientConnections))
        end)
    else
        Log("NetDriver: not found")
    end
end

local function FindHoveredButtonByName(pattern)
    if type(FindAllOf) ~= "function" then
        return nil
    end
    local found = nil
    pcall(function()
        FindAllOf("Button", function(btn)
            if found then return end
            if not IsHovered(btn) then return end
            local name = nil
            pcall(function()
                name = btn:GetFullName()
            end)
            if not name then
                pcall(function()
                    name = btn:GetName()
                end)
            end
            if name and name:find(pattern, 1, true) then
                found = btn
            end
        end)
    end)
    return found
end

local function ResolveButton(widget)
    if not widget then return nil end
    if widget.IsHovered then return widget end
    local candidates = {"Button", "Button_0", "MainButton", "Btn"}
    for _, name in ipairs(candidates) do
        local child = widget[name]
        if child and child.IsHovered then
            return child
        end
    end
    return widget
end

local function IsHovered(widget)
    local btn = ResolveButton(widget)
    if not btn then return false end
    local ok, hovered = pcall(function()
        if btn.IsHovered then
            return btn:IsHovered()
        end
        if btn.bIsHovered ~= nil then
            return btn.bIsHovered
        end
        return false
    end)
    if not ok then return false end
    return hovered
end

local function GetLeftMouseKey()
    if Key then
        if Key.LeftMouseButton then return Key.LeftMouseButton end
        if Key.LeftMouse then return Key.LeftMouse end
        if Key.MouseLeft then return Key.MouseLeft end
    end
    return "LeftMouseButton"
end

local function IsLeftMousePressed()
    local PC = FindFirstOf("PlayerController")
    if not PC or not PC:IsValid() then
        return false
    end

    local key = GetLeftMouseKey()

    -- Prefer edge-trigger if available
    local ok, pressed = pcall(function()
        if PC.WasInputKeyJustPressed then
            return PC:WasInputKeyJustPressed(key)
        end
        return nil
    end)
    if ok and pressed ~= nil then
        return pressed
    end

    -- Fallback to current state
    ok, pressed = pcall(function()
        if PC.IsInputKeyDown then
            return PC:IsInputKeyDown(key)
        end
        return false
    end)
    if ok and pressed ~= nil then
        return pressed
    end

    return false
end

local function HandleMenuClick()
    if not State.MainMenu then
        return false
    end

    if State.HasMPButtons then
        if IsHovered(State.MainMenu.HostButton) then
            StartHost()
            return true
        elseif IsHovered(State.MainMenu.JoinButton) then
            StartJoin()
            return true
        elseif IsHovered(State.MainMenu.MultiplayerButton) then
            EnableMultiplayerUI(State.MainMenu)
            return true
        end
    end

    -- Fallback: repurpose existing game mode buttons
    if IsHovered(State.MainMenu.ShootingRangeButton) or IsHovered(State.MainMenu.ShootingRangeBox) then
        StartHost()
        return true
    elseif IsHovered(State.MainMenu.TutorialButton) or IsHovered(State.MainMenu.TutorialBox) then
        StartJoin()
        return true
    end

    -- Global scan fallback (if MainMenu properties are missing)
    local hostBtn = FindHoveredButtonByName("ShootingRange")
    if hostBtn then
        StartHost()
        return true
    end
    local joinBtn = FindHoveredButtonByName("Tutorial")
    if joinBtn then
        StartJoin()
        return true
    end

    return false
end

local function TryRegisterHook(funcPath, cb)
    if type(RegisterHook) ~= "function" then
        return false
    end
    local fn = nil
    pcall(function()
        if StaticFindObject then
            fn = StaticFindObject(funcPath)
        end
    end)
    if not fn then
        return false
    end
    local ok = pcall(function()
        RegisterHook(funcPath, cb)
    end)
    return ok
end

local function RegisterConnectionHooks()
    if State.ConnHooksInstalled then return end
    State.ConnHooksInstalled = true

    local hookDefs = {
        { path = "/Script/Engine.GameModeBase:PreLogin", label = "PreLogin" },
        { path = "/Script/Engine.GameModeBase:PostLogin", label = "PostLogin" },
        { path = "/Script/Engine.GameModeBase:Login", label = "Login" },
        { path = "/Script/Engine.GameModeBase:Logout", label = "Logout" },
        { path = "/Script/Engine.GameMode:PreLogin", label = "PreLogin" },
        { path = "/Script/Engine.GameMode:PostLogin", label = "PostLogin" },
        { path = "/Script/Engine.GameMode:Login", label = "Login" },
        { path = "/Script/Engine.GameMode:Logout", label = "Logout" },
    }

    for _, def in ipairs(hookDefs) do
        TryRegisterHook(def.path, function(self, ...)
            local parts = {}
            local args = { ... }
            for i = 1, #args do
                parts[#parts + 1] = DescribeArg(args[i])
            end
            local suffix = ""
            if #parts > 0 then
                suffix = " | " .. table.concat(parts, " | ")
            end
            Log("Conn " .. def.label .. suffix)
        end)
    end
end

local function RegisterNetDriverHooks()
    if State.NetHooksInstalled then return end
    State.NetHooksInstalled = true

    local hookDefs = {
        { path = "/Script/Engine.NetDriver:NotifyAcceptingConnection", label = "AcceptingConnection" },
        { path = "/Script/Engine.NetDriver:NotifyAcceptedConnection", label = "AcceptedConnection" },
        { path = "/Script/Engine.NetDriver:NotifyAcceptedChannel", label = "AcceptedChannel" },
        { path = "/Script/Engine.NetDriver:NotifyControlMessage", label = "ControlMessage" },
    }

    for _, def in ipairs(hookDefs) do
        TryRegisterHook(def.path, function(self, ...)
            local parts = {}
            local args = { ... }
            for i = 1, #args do
                parts[#parts + 1] = DescribeArg(args[i])
            end
            local suffix = ""
            if #parts > 0 then
                suffix = " | " .. table.concat(parts, " | ")
            end
            Log("Conn " .. def.label .. suffix)
        end)
    end
end

local function RegisterFailureHooks()
    if State.FailureHooksInstalled then return end
    State.FailureHooksInstalled = true

    local hookDefs = {
        { path = "/Script/Engine.GameInstance:HandleNetworkFailure", label = "NetworkFailure" },
        { path = "/Script/Engine.GameInstance:HandleTravelFailure", label = "TravelFailure" },
        { path = "/Script/Engine.Engine:HandleNetworkFailure", label = "EngineNetworkFailure" },
        { path = "/Script/Engine.Engine:HandleTravelFailure", label = "EngineTravelFailure" },
    }

    for _, def in ipairs(hookDefs) do
        TryRegisterHook(def.path, function(self, ...)
            local parts = {}
            local args = { ... }
            for i = 1, #args do
                parts[#parts + 1] = DescribeArg(args[i])
            end
            local suffix = ""
            if #parts > 0 then
                suffix = " | " .. table.concat(parts, " | ")
            end
            Log("NetFail " .. def.label .. suffix)
        end)
    end
end

local function RegisterTickHook()
    local hookPaths = {
        "/Script/Engine.GameViewportClient:Tick",
        "/Script/Engine.PlayerController:PlayerTick",
        "/Script/Engine.Actor:ReceiveTick",
    }

    for _, path in ipairs(hookPaths) do
        local ok = TryRegisterHook(path, function(self, ...)
            local now = os.clock()
            if now - State.LastMenuCheck < 0.2 then
                return
            end
            State.LastMenuCheck = now

            if not State.MPUIEnabled then
                TryAttachToMenu()
            end

            if State.PendingStatusCheck > 0 and now >= State.PendingStatusCheck then
                DumpNetStatus()
                if State.PendingStatusAttempts == 0 then
                    ExecConsoleCmd("stat net")
                end
                State.PendingStatusAttempts = State.PendingStatusAttempts + 1
                if State.IsHosting or State.PendingStatusAttempts >= 3 then
                    State.PendingStatusCheck = 0
                else
                    State.PendingStatusCheck = now + 2.0
                end
            end

            if HasAuthority() then
                CheckClientConnections()
                EnsureClientPossession()
            elseif HasServerConnection() then
                FixClientInput()
            end

            local pressed = IsLeftMousePressed()
            if pressed then
                if not State.LeftMouseDown then
                    State.LeftMouseDown = true
                    HandleMenuClick()
                end
            else
                State.LeftMouseDown = false
            end
        end)
        if ok then
            State.TickHookInstalled = true
            Log("Tick hook installed: " .. path)
            return
        end
    end

    Log("No tick hook available. Use keybinds instead.")
end

local function RegisterKeybinds()
    if type(RegisterKeyBind) ~= "function" then
        Log("RegisterKeyBind unavailable.")
        return
    end

    -- F7 = force MP menu refresh
    RegisterKeyBind(Key.F7, function()
        RunInGameThread(function()
            TryAttachToMenu()
            HandleMenuClick()
        end)
    end)

    -- F8 = Host, F9 = Join
    RegisterKeyBind(Key.F8, function()
        StartHost()
    end)
    RegisterKeyBind(Key.F9, function()
        StartJoin()
    end)
    RegisterKeyBind(Key.F10, function()
        DumpNetStatus()
        ExecConsoleCmd("stat net")
    end)

    Log("Keybinds: F7=Refresh MP Menu, F8=Host, F9=Join, F10=Net Status")
end

local function Initialize()
    Log(MOD_NAME .. " v" .. VERSION .. " init")
    Log("Host map: " .. Config.HostMap)
    Log("Default join IP: " .. Config.DefaultJoinIP)
    Log("Edit host_map.txt and join_ip.txt in the mod folder to override.")
    local dirs = GetModDirCandidates()
    if #dirs > 0 then
        Log("Mod dir candidates: " .. table.concat(dirs, "; "))
    end

    RegisterTickHook()
    RegisterKeybinds()
    RegisterConnectionHooks()
    RegisterNetDriverHooks()
    RegisterFailureHooks()
end

Initialize()
