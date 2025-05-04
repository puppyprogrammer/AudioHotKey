@echo off
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Build a single‑file VoskListener.exe **in this folder**
:: • Embeds libvosk.dll  -> vosk\libvosk.dll
:: • Embeds model\*      -> model\*
:: Leaves commands.txt outside so the overlay can edit it.
::
:: Requirements:  Python (on PATH) with vosk, sounddevice, pyinstaller
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

setlocal ENABLEDELAYEDEXPANSION
pushd "%~dp0"   &  echo (working dir = %CD%)

rem ────────────────────────────────────────────────────────────────────
rem 1) locate libvosk.dll
for /f "usebackq delims=" %%P in (`
  python -c "import importlib.util, os, sys; s=importlib.util.find_spec('vosk'); print(os.path.dirname(s.origin) if s else '')"
`) do set "VOSKDIR=%%P"

if not defined VOSKDIR (
    echo [ERROR] 'vosk' package not found.  pip install vosk
    goto :HALT
)
if not exist "!VOSKDIR!\libvosk.dll" (
    echo [ERROR] libvosk.dll missing in "!VOSKDIR!"
    goto :HALT
)
echo [OK] libvosk.dll -> !VOSKDIR!

rem ────────────────────────────────────────────────────────────────────
rem 2) verify model folder
if not exist "model\" (
    echo [ERROR] model\ folder is missing next to this BAT.
    goto :HALT
)

rem absolute path to model\
for %%F in ("model") do set "MODELPATH=%%~fF"

rem ────────────────────────────────────────────────────────────────────
rem 3) clean previous artefacts
del /q "VoskListener.exe" 2>nul
rd  /s /q build            2>nul

rem ────────────────────────────────────────────────────────────────────
rem 4) run PyInstaller
echo.
echo === PyInstaller (one‑file, model embedded) ===
python -m PyInstaller VoskListener.py ^
        --onefile --noconfirm ^
        --add-binary "!VOSKDIR!\libvosk.dll;vosk" ^
        --add-data  "!MODELPATH!*;model" ^
        --distpath  "." ^
        --workpath  "build" ^
        --specpath  "build"

if exist "VoskListener.exe" (
    echo.
    echo [SUCCESS] VoskListener.exe created in: %CD%
    rem remove temp build folder on success
    rd /s /q build 2>nul
) else (
    echo.
    echo [FAIL] PyInstaller did not create the EXE – scroll up for details.
)

:HALT
echo.
pause
popd
endlocal
