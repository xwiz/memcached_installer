@echo off
setlocal enabledelayedexpansion

:: Check if script is being called as service controller
if "%~1"=="service_run" goto :service_controller

:: Main installation section
set "INSTALL_DIR=C:\memcached"
set "VERSION=1.6.8"
set "DOWNLOAD_URL=https://github.com/jefyt/memcached-windows/releases/download/%VERSION%_mingw/memcached-%VERSION%-win64-mingw.zip"
set "ZIP_FILE=%TEMP%\memcached-%VERSION%.zip"
set "EXTRACT_DIR=%TEMP%\memcached-extract"
set "MEMORY_LIMIT=2048"
set "SERVICE_NAME=memcached"

echo.
echo WARNING: This script will:
echo  - Kill any running memcached processes
echo  - Remove existing memcached Windows service
echo  - Replace any existing memcached installation in %INSTALL_DIR%
echo.
set /p CONFIRM="Press Y to continue or any other key to exit: "
if /i not "%CONFIRM%"=="Y" (
    echo Installation cancelled.
    exit /b 1
)
echo.

if not "%~1"=="" set "VERSION=%~1"
if not "%~2"=="" set "MEMORY_LIMIT=%~2"

echo [%date% %time%] Installing Memcached Server version %VERSION%...

net session >nul 2>&1
if errorlevel 1 (
    echo ERROR: Please run this script as Administrator
    pause
    exit /b 1
)

:: Clean up existing processes
taskkill /F /IM memcached.exe /T 2>nul
timeout /t 2 /nobreak >nul

:: Full service cleanup
call :cleanup_service
if errorlevel 1 (
    echo ERROR: Failed to cleanup existing service
    exit /b 1
)

if exist "%ZIP_FILE%" del "%ZIP_FILE%" 2>nul
if exist "%EXTRACT_DIR%" rd /s /q "%EXTRACT_DIR%" 2>nul
mkdir "%EXTRACT_DIR%"

echo Downloading Memcached from: %DOWNLOAD_URL%
where curl >nul 2>&1
if not errorlevel 1 (
    curl -L -o "%ZIP_FILE%" "%DOWNLOAD_URL%" --progress-bar
) else (
    certutil -urlcache -split -f "%DOWNLOAD_URL%" "%ZIP_FILE%" >nul
)

if not exist "%ZIP_FILE%" (
    echo ERROR: Download failed
    exit /b 1
)

cd /d "%EXTRACT_DIR%"
tar -xf "%ZIP_FILE%"
if errorlevel 1 (
    echo ERROR: Extraction failed
    exit /b 1
)

set "BIN_DIR=%EXTRACT_DIR%\memcached-%VERSION%-win64-mingw\bin"
if not exist "%BIN_DIR%\memcached.exe" (
    echo ERROR: memcached.exe not found in extracted files
    echo Expected path: %BIN_DIR%\memcached.exe
    exit /b 1
)

if not exist "%INSTALL_DIR%" (
    mkdir "%INSTALL_DIR%"
) else (
    echo Cleaning installation directory...
    del /F /Q "%INSTALL_DIR%\*.exe" 2>nul
    del /F /Q "%INSTALL_DIR%\*.pid" 2>nul
)

copy /Y "%BIN_DIR%\memcached.exe" "%INSTALL_DIR%\" >nul
if errorlevel 1 (
    echo ERROR: Failed to copy memcached.exe
    exit /b 1
)

copy /Y "%~f0" "%INSTALL_DIR%\install_memcached.bat" >nul

cd /d "%INSTALL_DIR%"
del "%ZIP_FILE%" 2>nul
rd /s /q "%EXTRACT_DIR%" 2>nul

:: Install service with full registry configuration
call :install_service
if errorlevel 1 (
    echo ERROR: Service installation failed
    exit /b 1
)

netsh advfirewall firewall delete rule name="Memcached" >nul 2>&1
netsh advfirewall firewall add rule name="Memcached" dir=in action=allow protocol=TCP localport=11211 program= "\"%INSTALL_DIR%\memcached.exe\"" enable=yes >nul

echo Starting service...
sc start %SERVICE_NAME%
if errorlevel 1 (
    echo ERROR: Failed to start service
    sc query %SERVICE_NAME%
    exit /b 1
)

timeout /t 2 /nobreak >nul
netstat -an | find ":11211" | find "LISTENING" >nul
if errorlevel 1 (
    echo WARNING: Port 11211 is not listening yet
) else (
    echo Port 11211 is listening successfully
)

echo.
echo Installation completed!
echo  - Version: %VERSION%
echo  - Memory: %MEMORY_LIMIT%MB
echo  - Port: 11211 (default)
echo  - Directory: %INSTALL_DIR%
echo.
echo To test: telnet localhost 11211
echo To uninstall: sc delete %SERVICE_NAME%

sc query %SERVICE_NAME%
exit /b 0

:cleanup_service
echo Cleaning up existing service...
:: Stop service if running
sc query %SERVICE_NAME% >nul 2>&1
if not errorlevel 1 (
    sc stop %SERVICE_NAME% >nul 2>&1
    timeout /t 2 /nobreak >nul
)

:: Remove service
sc delete %SERVICE_NAME% >nul 2>&1
timeout /t 2 /nobreak >nul

:: Clean registry entries
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\%SERVICE_NAME%" /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations" /v %SERVICE_NAME% /f >nul 2>&1

:: Clean Performance Monitor settings
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%\Performance" /f >nul 2>&1
exit /b 0

:install_service
echo Installing service...
:: Basic service creation
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v DisplayName /t REG_SZ /d "Memcached Server" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v Description /t REG_SZ /d "Memcached high-performance memory object caching system" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v ObjectName /t REG_SZ /d "LocalSystem" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v Start /t REG_DWORD /d 2 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v Type /t REG_DWORD /d 16 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v ErrorControl /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v ImagePath /t REG_EXPAND_SZ /d "\"%INSTALL_DIR%\install_memcached.bat\" service_run %MEMORY_LIMIT%" /f >nul

:: Additional service settings
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v DependOnService /t REG_MULTI_SZ /d "" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v Dependencies /t REG_MULTI_SZ /d "" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v Group /t REG_SZ /d "" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v TagId /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\%SERVICE_NAME%" /v DelayedAutoStart /t REG_DWORD /d 0 /f >nul

:: Event log settings
reg add "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\%SERVICE_NAME%" /v EventMessageFile /t REG_EXPAND_SZ /d "%SystemRoot%\System32\EventCreate.exe" /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Application\%SERVICE_NAME%" /v TypesSupported /t REG_DWORD /d 7 /f >nul
exit /b 0

:service_controller
set "MEMCACHED_PID=%INSTALL_DIR%\memcached.pid"
set "MEMCACHED_MEMORY=%~2"
if "%MEMCACHED_MEMORY%"=="" set "MEMCACHED_MEMORY=2048"

if exist "%MEMCACHED_PID%" del "%MEMCACHED_PID%"

"%INSTALL_DIR%\memcached.exe" -d -m %MEMCACHED_MEMORY% -P "%MEMCACHED_PID%"
if not exist "%MEMCACHED_PID%" (
    exit /b 1
)
:check_running
timeout /t 1 /nobreak >nul
if not exist "%MEMCACHED_PID%" (
    exit /b 1
)
for /f %%i in (%MEMCACHED_PID%) do (
    tasklist /FI "PID eq %%i" | find "%%i" >nul
    if errorlevel 1 (
        del "%MEMCACHED_PID%" 2>nul
        exit /b 1
    )
)
goto :check_running