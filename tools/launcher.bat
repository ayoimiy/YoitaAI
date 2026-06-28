@echo off
cd /d "%~dp0"
set PYTHON=E:\dev\anaconda3\pythonw.exe

set MODE=%1
if "%MODE%"=="" set MODE=big

echo ========================================
echo   Grid Explorer - Pathfinding Lab
echo ========================================
echo.
echo Mode: %MODE%
echo.

if /i "%MODE%"=="small" (
    echo Starting SMALL-GRID mode ^(20x20 animated^) ...
    echo.
    REM Write initial config for small mode
    echo set mode walk > command.txt
    echo set intensity 1.0 >> command.txt
    echo set interval 0.001 >> command.txt

    start "" "%PYTHON%" main.py small
    timeout /t 1 /nobreak >nul

    echo Game running. Type commands below ^(real-time config^):
    echo -------------------------------------------------------
    echo   restart              regenerate procedural map
    echo   set mode walk^|cave   map generator
    echo   set intensity N      walk intensity ^(0.3-3.0^)
    echo   set fill N           cave fill ratio ^(0.35-0.55^)
    echo   set seed N           random seed
    echo   set algo MOD         mod^|astar^|bfs^|greedy^|jps^|weight
    echo   set rays on^|off      toggle 5-ray viz
    echo   set grid W H         resize grid ^(5-100^)
    echo   set map N            load map slot N ^(1-9^)
    echo   set interval N       seconds/step ^(0.001-10^)
    echo   quit                 close game
    echo -------------------------------------------------------

    :loop_small
    set /p cmd="> "
    if "%cmd%"=="quit" (
        echo quit > command.txt
        echo Shutting down...
        exit /b
    )
    echo %cmd% > command.txt
    goto loop_small
) else (
    echo Starting BIG-GRID mode ^(1000x1000 instant^) ...
    echo.
    echo   Controls in-game:
    echo     Wheel = zoom   Drag = pan   L-click = target
    echo     T = pathfind   R = regen    1-5 = algo
    echo.
    start "" "%PYTHON%" main.py big
    echo Big-grid mode launched. Close the game window to exit.
)

echo.
pause
