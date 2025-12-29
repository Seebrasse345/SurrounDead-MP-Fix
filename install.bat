@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo  SurrounDead MP Fix Installer
echo  Installs UE4SS + MPFix mod
echo ==========================================
echo.

:: Find Steam game path
set "GAME_PATH="

:: Check common Steam locations
for %%P in (
    "C:\Program Files (x86)\Steam\steamapps\common\SurrounDead"
    "C:\Program Files\Steam\steamapps\common\SurrounDead"
    "D:\SteamLibrary\steamapps\common\SurrounDead"
    "E:\SteamLibrary\steamapps\common\SurrounDead"
    "F:\SteamLibrary\steamapps\common\SurrounDead"
    "G:\SteamLibrary\steamapps\common\SurrounDead"
) do (
    if exist "%%~P\SurrounDead.exe" (
        set "GAME_PATH=%%~P"
        goto :found
    )
)

:: If not found, ask user
echo Could not auto-detect SurrounDead installation.
set /p "GAME_PATH=Enter path to SurrounDead folder: "

:found
echo.
echo Found game at: %GAME_PATH%
echo.

set "WIN64=%GAME_PATH%\SurrounDead\Binaries\Win64"
set "LOGICMODS=%GAME_PATH%\SurrounDead\Content\Paks\LogicMods"

:: Verify paths exist
if not exist "%WIN64%" (
    echo ERROR: Cannot find %WIN64%
    pause
    exit /b 1
)

:: Create LogicMods folder if it doesn't exist
if not exist "%LOGICMODS%" (
    mkdir "%LOGICMODS%"
    echo Created LogicMods folder
)

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
echo   mpfix   - Force spawn fix for stuck players
echo   mpinfo  - Show MP debug info
echo   tphost  - Teleport all players to host
echo   F6      - Manual spawn fix hotkey
echo.
pause
