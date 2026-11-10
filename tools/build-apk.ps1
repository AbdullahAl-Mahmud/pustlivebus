# Builds the installable Android release APK without changing machine settings.
param([ValidateSet('all', 'android-arm64', 'android-arm', 'android-x64')][string]$TargetPlatform = 'all')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$temporaryRoot = Join-Path $projectRoot '.build-temp'
$artifactRoot = Join-Path $projectRoot 'artifacts'
$savedEnvironment = @{}
foreach ($key in @('TEMP', 'TMP', 'JAVA_TOOL_OPTIONS', 'JAVA_HOME')) {
    $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}

try {
    New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
    $env:TEMP = $temporaryRoot
    $env:TMP = $temporaryRoot
    $env:JAVA_TOOL_OPTIONS = ($savedEnvironment['JAVA_TOOL_OPTIONS'] +
        ' -Djdk.net.unixdomain.tmpdir="' + $temporaryRoot +
        '" -Djava.io.tmpdir="' + $temporaryRoot + '"').Trim()
    $androidJava = Join-Path $env:ProgramFiles 'Android\Android Studio\jbr'
    if (Test-Path -LiteralPath (Join-Path $androidJava 'bin\java.exe')) {
        $env:JAVA_HOME = $androidJava
        $env:JAVA_TOOL_OPTIONS += ' -Dorg.gradle.java.home="' + $androidJava + '"'
    }

    Push-Location $projectRoot
    try {
        # Flutter refreshes generated Android version metadata from pubspec.
        if ($TargetPlatform -eq 'all') {
            & flutter build apk --release --no-pub
        } else {
            & flutter build apk --release --no-pub --target-platform $TargetPlatform
        }
        if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
    } finally {
        Pop-Location
    }

    $builtApk = Join-Path $projectRoot 'build\app\outputs\apk\release\app-release.apk'
    if (!(Test-Path -LiteralPath $builtApk)) { throw 'The build did not produce the expected release APK.' }
    $versionLine = Get-Content -LiteralPath (Join-Path $projectRoot 'pubspec.yaml') |
        Where-Object { $_ -match '^version:\s*' } | Select-Object -First 1
    $version = (($versionLine -replace '^version:\s*', '').Trim() -split '\+')[0]
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid APK version in pubspec.yaml.' }
    $metadataPath = Join-Path $projectRoot 'build\app\outputs\apk\release\output-metadata.json'
    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ($metadata.elements[0].versionName -ne $version) {
        throw 'Generated Android version differs from pubspec.yaml. Refresh the Flutter Android build configuration before distributing this APK.'
    }
    New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
    $suffix = if ($TargetPlatform -eq 'all') { '' } else { '-' + ($TargetPlatform -replace '^android-', '') }
    $deliveryApk = Join-Path $artifactRoot "PUST-LiveBus-$version$suffix.apk"
    Copy-Item -LiteralPath $builtApk -Destination $deliveryApk
    $checksum = (Get-FileHash -LiteralPath $deliveryApk -Algorithm SHA256).Hash.ToLowerInvariant()
    "$checksum  $([IO.Path]::GetFileName($deliveryApk))" |
        Set-Content -LiteralPath "$deliveryApk.sha256" -Encoding utf8
    Get-Item -LiteralPath $deliveryApk | Select-Object FullName, Length, LastWriteTime
} finally {
    foreach ($key in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
    }
}
