@echo off
setlocal

echo ==========================================
echo  SurrounDead MP Fix Installer (v4.6)
echo  Installs UE4SS + MPFix mod
echo ==========================================
echo.

:: Find Steam game path
set "GAME_PATH="

:: Check common Steam locations
if exist "C:\Program Files (x86)\Steam\steamapps\common\SurrounDead\SurrounDead.exe" set "GAME_PATH=C:\Program Files (x86)\Steam\steamapps\common\SurrounDead"
if exist "C:\Program Files\Steam\steamapps\common\SurrounDead\SurrounDead.exe" set "GAME_PATH=C:\Program Files\Steam\steamapps\common\SurrounDead"
if exist "D:\SteamLibrary\steamapps\common\SurrounDead\SurrounDead.exe" set "GAME_PATH=D:\SteamLibrary\steamapps\common\SurrounDead"
if exist "E:\SteamLibrary\steamapps\common\SurrounDead\SurrounDead.exe" set "GAME_PATH=E:\SteamLibrary\steamapps\common\SurrounDead"
if exist "F:\SteamLibrary\steamapps\common\SurrounDead\SurrounDead.exe" set "GAME_PATH=F:\SteamLibrary\steamapps\common\SurrounDead"
if exist "G:\SteamLibrary\steamapps\common\SurrounDead\SurrounDead.exe" set "GAME_PATH=G:\SteamLibrary\steamapps\common\SurrounDead"

if "%GAME_PATH%"=="" (
    echo Could not auto-detect SurrounDead installation.
    set /p "GAME_PATH=Enter path to SurrounDead folder: "
)

echo.
echo Found game at: "%GAME_PATH%"
echo.

set "WIN64=%GAME_PATH%\SurrounDead\Binaries\Win64"
set "LOGICMODS=%GAME_PATH%\SurrounDead\Content\Paks\LogicMods"
set "SYMBOLS=%GAME_PATH%\Symbols"

:: Verify paths exist
if not exist "%WIN64%" (
    echo ERROR: Cannot find "%WIN64%"
    echo Make sure SurrounDead is installed correctly.
    pause
    exit /b 1
)

:: Create LogicMods folder if it doesn't exist
if not exist "%LOGICMODS%" (
    mkdir "%LOGICMODS%"
    echo Created LogicMods folder
)

:: Create symbols cache folder and set user symbol path
if not exist "%SYMBOLS%" (
    mkdir "%SYMBOLS%"
    echo Created Symbols folder
)
set "SYMBOL_PATH=srv*%SYMBOLS%*https://msdl.microsoft.com/download/symbols"
setx _NT_SYMBOL_PATH "%SYMBOL_PATH%" >nul
echo   - Symbol path set for current user

echo Installing UE4SS...
copy /Y "%~dp0dwmapi.dll" "%WIN64%\" >nul
copy /Y "%~dp0UE4SS.dll" "%WIN64%\" >nul
copy /Y "%~dp0UE4SS-settings.ini" "%WIN64%\" >nul
echo   - Core files copied

echo Installing Mods...
xcopy /E /I /Y "%~dp0Mods" "%WIN64%\Mods" >nul
echo   - Mods copied

echo Installing LogicMods pak...
copy /Y "%~dp0LogicMods\*.pak" "%LOGICMODS%\" >nul
echo   - Blueprint mod pak copied

echo.
echo ==========================================
echo  Installation Complete!
echo ==========================================
echo.
echo Commands in-game (press ~ for console):
echo   mpfix    - Force spawn check + input fix
echo   mpinput  - Fix local input only
echo   mpinfo   - Show MP debug info
echo   mpdebug  - Dump local controller/pawn status
echo   mpmove   - Test local pawn movement
echo   tphost   - Teleport all players to host
echo   F6       - Manual spawn fix hotkey
echo   ESC      - Pause menu fallback
echo.
pause
