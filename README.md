# SurrounDead Multiplayer Fix

Fixes multiplayer issues in SurrounDead where joining players spawn as "camera only" with no character control.

## Features

- Automatic detection of players without pawns
- Multiple spawn/possession methods for reliability
- Teleport commands for stuck players
- Works on both host and client

## Quick Install

### Option 1: Automatic (Recommended)

1. Download this repo (Code > Download ZIP) or clone it
2. Run `install.bat`
3. Done!

### Option 2: Manual Install

Copy files to your SurrounDead installation:

```
SurrounDead/
  SurrounDead/
    Binaries/Win64/
      dwmapi.dll          <- copy here
      UE4SS.dll           <- copy here
      UE4SS-settings.ini  <- copy here
      Mods/               <- copy entire folder here
    Content/Paks/
      LogicMods/          <- create if doesn't exist
        MPSpawnFix_P.pak  <- copy here
```

## Installation Commands (PowerShell)

```powershell
# Clone the repo
git clone https://github.com/Seebrasse345/SurrounDead-MP-Fix.git

# Navigate to folder
cd SurrounDead-MP-Fix

# Run installer
.\install.bat
```

## Alternative: One-liner Install

```powershell
# Download and run (PowerShell as Admin)
Invoke-WebRequest -Uri "https://github.com/Seebrasse345/SurrounDead-MP-Fix/archive/refs/heads/main.zip" -OutFile "$env:TEMP\mpfix.zip"; Expand-Archive -Path "$env:TEMP\mpfix.zip" -DestinationPath "$env:TEMP\mpfix" -Force; & "$env:TEMP\mpfix\SurrounDead-MP-Fix-main\install.bat"
```

## In-Game Commands

Open console with `~` (tilde) key:

| Command | Description |
|---------|-------------|
| `mpfix` | Force spawn fix for stuck players |
| `mpinfo` | Show multiplayer debug info |
| `tphost` | Teleport all players to host location |

**Hotkey:** Press `F6` to manually trigger spawn fix

## Requirements

- SurrounDead (Steam version)
- Both host AND client need this mod installed

## Troubleshooting

### White/blank UE4SS console window
Already fixed in this package - uses DirectX 11 instead of OpenGL.

### Player still has no control after joining
1. Host should type `mpfix` in console
2. Try `tphost` to teleport client to host
3. Client may need to rejoin

### Game crashes on startup
- Verify game files through Steam
- Make sure you're using the correct game version

## File Structure

```
UE4SS_Package/
  install.bat           # Auto-installer
  dwmapi.dll            # UE4SS loader
  UE4SS.dll             # UE4SS core
  UE4SS-settings.ini    # Config (GraphicsAPI=dx11)
  Mods/
    MPFix/              # Main multiplayer fix mod
    BPModLoaderMod/     # Blueprint mod loader
    shared/             # Shared Lua libraries
    ...
  LogicMods/
    MPSpawnFix_P.pak    # Blueprint spawn fix
```

## Technical Details

This mod uses UE4SS (Unreal Engine 4/5 Scripting System) to:
- Poll for PlayerControllers without possessed pawns
- Attempt multiple spawn methods (RestartPlayer, SpawnDefaultPawnAtTransform, etc.)
- Find and possess orphaned character actors
- Handle replication setup for multiplayer

## Version

- MPFix: v3.7
- UE4SS: Latest compatible version

## License

MIT - Feel free to modify and redistribute.

## Credits

- UE4SS Team for the scripting system
- SurrounDead community
