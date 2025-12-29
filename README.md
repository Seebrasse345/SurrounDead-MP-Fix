# SurrounDead Multiplayer Fix

Fixes multiplayer issues in SurrounDead (UE5.3) where joining players spawn as "camera only" with no character control.

## Current Version: v4.5

## The Problem

When clients join a SurrounDead multiplayer session:
- They spawn as "camera only" - no pawn/character
- Characters spawn underground (Z < -500)
- No input control - can't move, look, or open menus
- Escape key doesn't work

## How Our Fix Works

### Architecture
Two-component system:
1. **Lua Mod (MPFix)** - Runtime spawn detection and possession
2. **Blueprint Mod (MPSpawnFix_P.pak)** - Server-side spawn hooks

### Server-Side Logic (Host)
```
1. Poll every 3 seconds for PlayerControllers
2. Skip local controller (host) - only process remote clients
3. For each remote client without a pawn:
   a. Try SpawnActor(DefaultPawnClass) + Possess()
   b. Try GameMode:RestartPlayer(pc)
   c. Find unpossessed BP_PlayerCharacter_C and Possess()
   d. Try pc:ServerRestartPlayer()
4. Run SetupPossessedPawn() to configure replication
5. Teleport underground pawns to valid location
```

### Client-Side Logic (Joining Player)
```
1. Detect when local controller gets a pawn (client-safe, no GameMode dependency)
2. Run FixLocalInput() to enable controls
3. Set input mode to GameOnly (ESC fallback for menu)
```

### SetupPossessedPawn() - What it does
```lua
pc:EnableInput(pc)
pc:SetInputModeGameOnly()
pc:SetIgnoreMoveInput(false)
pc:SetIgnoreLookInput(false)
pc:SetPawn(pawn)
pc:OnRep_Pawn()
pawn:SetOwner(pc)
pawn:SetReplicates(true)
pawn:SetReplicateMovement(true)
pawn:ForceNetUpdate()
pawn:SetAutonomousProxy(true)
pawn.CharacterMovement:SetMovementMode(1)  -- Walking
pawn:OnRep_Controller()
pawn:OnRep_PlayerState()
pc:AcknowledgePossession(pawn)
pc:ClientRestart(pawn)
```

## Installation

### Quick Install
```bash
git clone https://github.com/Seebrasse345/SurrounDead-MP-Fix.git
cd SurrounDead-MP-Fix
.\install.bat
```

### Manual Install
Copy to `SurrounDead/SurrounDead/Binaries/Win64/`:
- `dwmapi.dll`
- `UE4SS.dll`
- `UE4SS-settings.ini`
- `Mods/` folder

Copy to `SurrounDead/SurrounDead/Content/Paks/LogicMods/`:
- `MPSpawnFix_P.pak`

## Requirements

**BOTH host AND client need this mod installed!**

The server handles spawn/possession, but the client needs the mod for:
- Input fixing
- Client-side setup

## Commands

| Command | Description |
|---------|-------------|
| `mpfix` | Force spawn check + input fix |
| `mpinput` | Fix local input only |
| `mpinfo` | Show multiplayer debug info |
| `mpdebug` | Dump local controller/pawn input status |
| `mpmove` | Test local pawn movement |
| `tphost` | Teleport all players to host |
| **F6** | Hotkey for mpfix |
| **ESC** | Pause menu fallback |

## Known Issues

### Solved
- [x] Game crashes on startup with hooks - **Fixed**: Use polling instead
- [x] UE4SS console shows white window - **Fixed**: GraphicsAPI=dx11
- [x] Crash on "New player detected" - **Fixed**: Skip first check cycle
- [x] FString concatenation errors - **Fixed**: Use tostring()
- [x] tphost crash - **Fixed**: Use {} instead of nil for HitResult

### Current Issues
- [ ] Client may not have full control after spawn
- [ ] Escape menu may still be unreliable on client (ESC fallback added)
- [ ] Replication not 100% reliable

### Root Cause
The game's `BP_SurroundeadGameMode` doesn't properly implement:
- `PostLogin` spawn for remote clients
- Proper pawn class replication
- Network authority setup

## Technical Findings

### What Doesn't Work
- `RegisterHook` on spawn functions - crashes game
- `HandleStartingNewPlayer` hook - crashes
- `PostLogin` hook - crashes
- `RestartPlayer` alone - doesn't actually spawn pawn
- `ServerRestartPlayer` alone - same issue

### What Works
- Polling with `LoopAsync` - stable
- Finding unpossessed characters and `Possess()` - works
- `SetupPossessedPawn()` replication calls - partially works
- Client-side `FixLocalInput()` - helps with controls

### NetMode Values
- 0 = Standalone
- 1 = DedicatedServer
- 2 = ListenServer
- 3 = Client

### Key Classes
- `BP_SurroundeadGameMode` - Game mode (server only)
- `BP_PlayerCharacter_C` - Player character blueprint
- `PlayerController` - Input and possession
- `CharacterMovement` - Movement component

## File Structure

```
SurrounDead/
  SurrounDead/
    Binaries/Win64/
      dwmapi.dll              # UE4SS loader
      UE4SS.dll               # UE4SS core (16MB)
      UE4SS-settings.ini      # Config (GraphicsAPI=dx11)
      UE4SS.log               # Debug log
      Mods/
        MPFix/
          Scripts/
            main.lua          # Main fix mod (v4.5)
        BPModLoaderMod/       # Loads .pak mods
        shared/               # Lua libraries
        mods.txt              # Mod enable list
    Content/Paks/
      LogicMods/
        MPSpawnFix_P.pak      # Blueprint mod
```

## Development

### Source Locations
- Lua mod: `Mods/MPFix/Scripts/main.lua`
- Blueprint source: `ModTools/MPSpawnFix/`
- C++ reference: `ModTools/MPSpawnFix/Source/MPSpawnFix/ModActor.cpp`

### Testing
1. Host starts game, hosts server (F8)
2. Client joins (F9 or console: `open IP:7777`)
3. Check UE4SS.log for `[MPFix]` messages
4. Use `mpinfo` to see controller/pawn status

### Debug Commands
```
mpinfo          # Show all controller/pawn info
mpdebug         # Dump local input/pawn status
mpmove          # Test local pawn movement
stat net        # UE network stats
```

## Version History

### v4.5
- NetDriver-based server/client detection (fixes client mis-detected as server)
- GetNetMode uses World.NetMode and KSL fallback
- World lookup fallback for early join state

### v4.4
- Spawn retry + SpawnActor fallback for stubborn clients
- Safer server/client detection when pawn is missing
- Client input fix re-runs when pawn changes
- UEHelpers PlayerController fallback to avoid "no pawn" deadlock

### v4.3
- Safer keybind registration (no hard failure if Keybinds loads late)
- Force pawn visibility/relevance for host and other clients
- Input fix prefers GameOnly + pushes InputComponent + calls pawn Restart
- Guarded Enhanced Input subsystem lookup

### v4.2
- Enhanced client input recovery (movement component + Enhanced Input mapping)
- ESC pause menu fallback
- New `mpdebug` and `mpmove` commands

### v4.1
- Added client-side input auto-fix
- New `mpinput` command
- F6 fixes input on both server and client
- More pcall safety in GetNetMode/IsInGame

### v4.0
- Complete rewrite based on C++ ModActor
- Fixed crash on first run
- Added NetMode check (server only)
- Comprehensive SetupPossessedPawn()

### v3.x
- Initial polling approach
- Multiple spawn methods
- Hook crashes discovered

## Credits

- UE4SS Team - Scripting system
- SurrounDead community

## License

MIT
