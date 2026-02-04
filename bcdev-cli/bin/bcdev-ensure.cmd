@echo off
setlocal EnableDelayedExpansion

:: Get script directory
set "SCRIPT_DIR=%~dp0.."

:: Config
set "DEFAULT_VERSION=1.1"
if "%BCDEV_CLI_VERSION%"=="" (set "VERSION=%DEFAULT_VERSION%") else (set "VERSION=%BCDEV_CLI_VERSION%")
set "REPO=navipartner/BC-Dev-CLI"

:: Validate version format (prevent path traversal)
echo %VERSION% | findstr /R "^[0-9][0-9]*\.[0-9][0-9]*" >nul
if %ERRORLEVEL% neq 0 (
    echo Error: Invalid version format: %VERSION% >&2
    echo Version must match pattern: X.Y or X.Y.Z ^(e.g., 0.7, 1.0.0^) >&2
    exit /b 1
)

set "CACHE_DIR=%LOCALAPPDATA%\bcdev\cli\v%VERSION%"
set "BINARY=%CACHE_DIR%\bcdev.exe"
set "LOCK_DIR=%LOCALAPPDATA%\bcdev\.lock"
set "CHECKSUMS_FILE=%SCRIPT_DIR%\checksums.txt"

:: Check if binary exists
if exist "%BINARY%" goto :run

:: Acquire lock (mkdir-based)
set "LOCK_ATTEMPTS=0"
:acquire_lock
mkdir "%LOCK_DIR%" 2>nul
if %ERRORLEVEL% neq 0 (
    set /a LOCK_ATTEMPTS+=1
    if !LOCK_ATTEMPTS! geq 30 (
        echo Error: Could not acquire lock after 30 seconds >&2
        exit /b 1
    )
    timeout /t 1 /nobreak >nul
    goto :acquire_lock
)

:: Re-check after lock
if exist "%BINARY%" goto :release_and_run

:: Create cache directory
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

:: Download
set "URL=https://github.com/%REPO%/releases/download/v%VERSION%/bcdev-win-x64.exe"
set "TEMP_FILE=%TEMP%\bcdev-download-%RANDOM%.exe"

echo Downloading BC Dev CLI v%VERSION% for Windows... >&2

:: Use curl (Windows 10+) or PowerShell fallback with TLS 1.2
where curl >nul 2>&1
if %ERRORLEVEL%==0 (
    curl -fSL "%URL%" -o "%TEMP_FILE%"
) else (
    powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%URL%' -OutFile '%TEMP_FILE%'"
)

if %ERRORLEVEL% neq 0 (
    echo Error: Failed to download BC Dev CLI v%VERSION% >&2
    echo URL: %URL% >&2
    del "%TEMP_FILE%" 2>nul
    rmdir "%LOCK_DIR%" 2>nul
    exit /b 1
)

:: Verify checksum if available
if exist "%CHECKSUMS_FILE%" (
    for /f "tokens=3" %%a in ('findstr /B /C:"%VERSION% win-x64 " "%CHECKSUMS_FILE%"') do set "EXPECTED_CHECKSUM=%%a"
    if defined EXPECTED_CHECKSUM (
        echo Verifying checksum... >&2
        for /f "skip=1 tokens=*" %%b in ('certutil -hashfile "%TEMP_FILE%" SHA256') do (
            if not defined ACTUAL_CHECKSUM set "ACTUAL_CHECKSUM=%%b"
        )
        set "ACTUAL_CHECKSUM=!ACTUAL_CHECKSUM: =!"
        if /i "!ACTUAL_CHECKSUM!" neq "!EXPECTED_CHECKSUM!" (
            echo Error: Checksum verification failed! >&2
            echo Expected: !EXPECTED_CHECKSUM! >&2
            echo Actual:   !ACTUAL_CHECKSUM! >&2
            del "%TEMP_FILE%" 2>nul
            rmdir "%LOCK_DIR%" 2>nul
            exit /b 1
        )
    ) else (
        echo Warning: No checksum available for v%VERSION% win-x64 >&2
    )
)

:: Atomic move to final location
move /y "%TEMP_FILE%" "%BINARY%" >nul

:release_and_run
rmdir "%LOCK_DIR%" 2>nul

:run
"%BINARY%" %*
