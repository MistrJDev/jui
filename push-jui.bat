@echo off
REM push-jui.bat
REM ---------------------------------------------------------------------
REM Run this from inside your actual Jui addon folder. It does NOT need
REM to already be a git repo or already be cloned from GitHub - this
REM script sets that up itself if it isn't:
REM   - runs `git init` if the folder isn't a git repo yet
REM   - adds (or fixes) the "origin" remote to point at MistrJDev/jui
REM   - stages everything, commits, and force-pushes
REM
REM End result: https://github.com/MistrJDev/jui is made to match this
REM folder exactly, regardless of what was on GitHub before.
REM
REM Usage:
REM   push-jui.bat                   (timestamped commit message)
REM   push-jui.bat "Fix scaling"     (custom commit message)
REM
REM --force overwrites GitHub with exactly what's in this folder, no
REM merge, no history check. Fine for a solo repo; if anyone else (or
REM another machine) also pushes to this repo, this can wipe their
REM commits without warning.

setlocal enabledelayedexpansion

set "REPO_URL=https://github.com/MistrJDev/jui.git"
set "BRANCH=main"

if "%~1"=="" (
    for /f "delims=" %%I in ('powershell -NoProfile -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set "TIMESTAMP=%%I"
    set "COMMIT_MSG=Update Jui !TIMESTAMP!"
) else (
    set "COMMIT_MSG=%~1"
)

echo.
echo === Checking for git ===
git --version >nul 2>&1
if errorlevel 1 (
    echo ERROR: git is not installed, or not on PATH.
    echo Install it from https://git-scm.com/downloads and try again.
    goto :end
)

echo.
echo === Checking if this folder is already a git repo ===
git rev-parse --is-inside-work-tree >nul 2>&1
if errorlevel 1 (
    echo Not a git repo yet - running "git init" in this folder.
    git init
    if errorlevel 1 (
        echo ERROR: git init failed. See the output above.
        goto :end
    )
) else (
    echo Already a git repo - continuing.
)

echo.
echo === Checking the "origin" remote ===
set "CURRENT_ORIGIN="
for /f "delims=" %%U in ('git remote get-url origin 2^>nul') do set "CURRENT_ORIGIN=%%U"

if "!CURRENT_ORIGIN!"=="" (
    echo No "origin" remote set yet - adding %REPO_URL%
    git remote add origin "%REPO_URL%"
) else if not "!CURRENT_ORIGIN!"=="%REPO_URL%" (
    echo "origin" currently points to: !CURRENT_ORIGIN!
    echo Changing it to: %REPO_URL%
    git remote set-url origin "%REPO_URL%"
) else (
    echo "origin" already correctly points to %REPO_URL%
)

echo.
echo === Staging all files in this folder ===
git add -A
if errorlevel 1 (
    echo ERROR: git add failed. See the output above.
    goto :end
)

echo.
echo === Committing ===
git commit -m "%COMMIT_MSG%"
if errorlevel 1 (
    echo NOTE: commit reported an error above - most commonly this just
    echo means nothing changed since the last commit. Continuing to push
    echo anyway, in case an earlier commit was made but never pushed.
)

echo.
echo === Making sure the branch is named "%BRANCH%" ===
git branch -M %BRANCH%

echo.
echo === Force-pushing - this REPLACES everything on GitHub with this folder ===
git push --force origin %BRANCH%
if errorlevel 1 (
    echo ERROR: git push failed. Common causes:
    echo   - Not authenticated ^(GitHub needs a personal access token or SSH
    echo     key - plain password login was removed years ago^)
    echo   - You don't have write access to MistrJDev/jui with this account
    echo Try running: git push --force origin %BRANCH%
    echo directly in a terminal to see the full error text.
    goto :end
)

echo.
echo === Done. https://github.com/MistrJDev/jui now matches this folder. ===

:end
endlocal
echo.
pause
