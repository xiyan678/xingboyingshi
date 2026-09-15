param([Parameter(Mandatory=$true)][string]$ApkPath)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $ApkPath).Path)
try {
    $expected=@{'armeabi-v7a'=40; 'arm64-v8a'=183; 'x86_64'=62}
    foreach($abi in $expected.Keys) {
        $entry=$archive.GetEntry("lib/$abi/libflutter.so")
        if($null -eq $entry) { throw "Missing Flutter engine for $abi" }
        $stream=$entry.Open()
        try {
            $header=New-Object byte[] 20
            $offset=0
            while($offset -lt 20) {
                $read=$stream.Read($header,$offset,20-$offset)
                if($read -eq 0) { throw 'Truncated ELF header' }
                $offset += $read
            }
            if($header[0] -ne 127 -or $header[1] -ne 69 -or $header[2] -ne 76 -or $header[3] -ne 70 -or $header[5] -ne 1) { throw "Invalid ELF header: $abi" }
            $machine=[int]$header[18]+256*[int]$header[19]
            if($machine -ne $expected[$abi]) { throw "Incorrect engine architecture: $abi ($machine)" }
            Write-Output "$abi Flutter engine verified (ELF machine $machine)"
        } finally { $stream.Dispose() }
    }
} finally { $archive.Dispose() }
