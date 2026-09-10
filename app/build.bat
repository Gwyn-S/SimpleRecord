@echo off
setlocal
cd /d "%~dp0"

set SYMBOLS=build\symbols

if "%~1"=="" goto usage
if /i "%~1"=="win" goto build_windows
if /i "%~1"=="apk" goto build_apk
if /i "%~1"=="all" goto build_all
goto usage

:usage
echo.
echo Usage: build.bat [win ^| apk ^| all]
echo   win - Build Windows desktop release
echo   apk - Build Android arm64-v8a APK (release, R8 + obfuscate)
echo   all - Build win + apk in sequence
echo.
exit /b 1

:build_windows
echo.
echo === Building Windows release ===
flutter build windows --release --split-debug-info=%SYMBOLS%\windows --obfuscate --dart-define-from-file=.env.release
if errorlevel 1 exit /b 1
echo.
echo Windows build OK: build\windows\x64\runner\Release\
exit /b 0

:build_apk
echo.
echo === Building Android arm64-v8a release ===
flutter build apk --release --target-platform android-arm64 --split-per-abi --split-debug-info=%SYMBOLS%\android --obfuscate --dart-define-from-file=.env.release
if errorlevel 1 exit /b 1
echo.
echo Android build OK: build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
exit /b 0

:build_all
call :build_windows
if errorlevel 1 exit /b 1
call :build_apk
if errorlevel 1 exit /b 1
echo.
echo === All builds finished ===
exit /b 0
