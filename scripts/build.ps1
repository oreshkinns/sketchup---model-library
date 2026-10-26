$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path $PSScriptRoot -Parent
$source = Get-Content -LiteralPath (Join-Path $projectRoot 'maf_library.rb') -Raw
$version = [regex]::Match($source, 'VERSION = ''([^'']+)''').Groups[1].Value
if (-not $version) { throw 'Extension version not found' }
$toolsRoot = Join-Path $projectRoot '.tools'
$stagingPath = Join-Path $toolsRoot ('build-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $toolsRoot ('maf_library-' + $version + '-' + [guid]::NewGuid().ToString('N') + '.rbz')
$outputPath = Join-Path $projectRoot ('dist\maf_library-' + $version + '.rbz')
try {
    New-Item -ItemType Directory -Path (Join-Path $stagingPath 'maf_library\icons') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $projectRoot 'maf_library.rb') -Destination $stagingPath
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'maf_library') -Filter '*.rb' -File |
        Copy-Item -Destination (Join-Path $stagingPath 'maf_library')
    Get-ChildItem -LiteralPath (Join-Path $projectRoot 'maf_library\icons') -Filter '*.png' -File |
        Copy-Item -Destination (Join-Path $stagingPath 'maf_library\icons')
    Copy-Item -LiteralPath (Join-Path $projectRoot 'preview.html') -Destination (Join-Path $stagingPath 'maf_library\ui.html')
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingPath, $archivePath)
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $paths = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        if ('maf_library.rb' -notin $paths -or 'maf_library/ui.html' -notin $paths) { throw 'Invalid RBZ structure' }
    } finally { $archive.Dispose() }
    New-Item -ItemType Directory -Path (Join-Path $projectRoot 'dist') -Force | Out-Null
    Move-Item -LiteralPath $archivePath -Destination $outputPath -Force
    Write-Output $outputPath
    Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
} finally {
    $resolvedStaging = [System.IO.Path]::GetFullPath($stagingPath)
    $resolvedTools = [System.IO.Path]::GetFullPath($toolsRoot) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $resolvedStaging.StartsWith($resolvedTools, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path' }
    if (Test-Path -LiteralPath $resolvedStaging) { Remove-Item -LiteralPath $resolvedStaging -Recurse -Force }
}
