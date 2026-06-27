@echo off
cd /d "%~dp0"
set PYTHON=E:\dev\anaconda3\python.exe

echo ========================================
echo   Grid Explorer - Pathfinding Lab
echo ========================================
echo.
echo Starting game (20x20 grid, random walk) ...
echo.

REM Write initial commands
echo set mode walk > command.txt
echo set intensity 1.0 >> command.txt
echo set interval 0.001 >> command.txt

REM Launch game
start "Grid Explorer" "%PYTHON%" main.py
timeout /t 2 /nobreak >nul

echo.
echo === Controls ============================
echo   Mouse click    - F: target / P: draw / E: erase
echo   T key          - Start pathfinding
echo   G key          - Set player position
echo   1-9 keys       - Select algo (N mode) or map (M mode)
echo   N key          - 1-9 control algorithms
echo   M key          - 1-9 control map slots
echo   Q              - Clear map
echo   R              - Procedural generate
echo   S              - Save to current slot
echo   Up / Down      - Adjust intensity
echo   Esc            - Quit
echo.
echo === Console Commands ====================
echo   restart                  regenerate map
echo   set mode [walk^|cave]     map generator (default=walk)
echo   set intensity N          random walk intensity (0.5-3.0)
echo   set fill N               cave: fill ratio
echo   set seed N               random seed
echo   set algo [mod^|astar^|bfs^|greedy^|jps]
echo   set rays [on^|off]        toggle 5-ray collision viz
echo   set map NAME             load saved map on launch
echo   set grid W H             resize grid (5-100)
echo   quit                     exit
echo ==========================================
echo.

:loop
set /p cmd="> "
if "%cmd%"=="quit" (
    echo %cmd% > command.txt
    echo Shutting down...
    exit /b
)
echo %cmd% > command.txt
goto loop
