$ErrorActionPreference='Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    flutter pub get
    if($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed' }
    flutter build apk --debug --target-platform android-arm,android-arm64,android-x64
    if($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    & "$PSScriptRoot/verify-apk.ps1" -ApkPath 'build/app/outputs/flutter-apk/app-debug.apk'
} finally { Pop-Location }
