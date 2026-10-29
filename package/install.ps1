# Black 2 MMO setup (Windows). Run through "Install Black 2 MMO.bat".
# Asks for your name, the server and a room code (saved in lua\b2mmo.ini), where BizHawk is and
# where your Pokemon Black 2 ROM is, then writes "Play Black 2 MMO.bat" next to this file.
# Run it again to change any answer (the previous ones are the defaults).
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Utf8 = New-Object System.Text.UTF8Encoding($false)

function Ask([string]$prompt, [string]$default) {
    $v = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrWhiteSpace($v)) { return $default }
    return $v.Trim().Trim('"')
}

# The frames carry plain ASCII: name[16] and room[12], NUL-padded.
function Clean([string]$s, [int]$max) {
    $s = ($s -replace '[^\x20-\x7e]', '').Trim()
    if ($s.Length -gt $max) { $s = $s.Substring(0, $max) }
    return $s
}

$Ini = Join-Path $Here 'lua\b2mmo.ini'
$old = @{}
if (Test-Path $Ini) {
    foreach ($line in Get-Content $Ini) { if ($line -match '^\s*(\w+)\s*=\s*(.*)$') { $old[$Matches[1]] = $Matches[2].Trim() } }
}
function Old([string]$k, [string]$d) { if ($old.ContainsKey($k)) { return $old[$k] } return $d }

Write-Host 'Black 2 MMO setup'
Write-Host '-----------------'
$name = Clean (Ask 'Your name (shown above your trainer)' (Old 'name' (Clean $env:USERNAME 15))) 15
if (-not $name) { $name = 'Trainer' }
$server = Ask 'Server address (the host''s IP, or 127.0.0.1 if you host on this PC)' (Old 'server' '127.0.0.1')
$port = Ask 'Server port' (Old 'port' '7777')
$room = (Clean (Ask 'Room code (everyone with the same code plays together)' (Old 'room' 'UNOVA')) 11).ToUpper()
$greeting = Clean (Ask 'What you say when someone talks to you' (Old 'greeting' 'Hi! Want to battle or trade?')) 39

# --- BizHawk and the ROM ----------------------------------------------------------------------
# Asked every time (the saved path is the default) so running setup again can fix a wrong one.
function AskFile([string]$about, [string]$prompt, [string]$default, [scriptblock]$fix, [scriptblock]$ok) {
    if (-not ($default -and (& $ok $default))) { $default = '' }
    while ($true) {
        Write-Host ''
        Write-Host $about
        $v = Ask $prompt $default
        if ($v) { $v = & $fix $v }
        if ($v -and (& $ok $v)) { return (Resolve-Path -LiteralPath $v).ProviderPath }
        if ($v) { Write-Host "Not found or not the right file: $v" }
    }
}
$emu = AskFile 'Where is BizHawk? (2.9 or newer, from https://github.com/TASEmulators/BizHawk/releases)' `
    'Path to EmuHawk.exe or its folder' (Old 'emuhawk' '') `
    { param($p) if (Test-Path -LiteralPath $p -PathType Container) { Join-Path $p 'EmuHawk.exe' } else { $p } } `
    { param($p) (Test-Path -LiteralPath $p -PathType Leaf) -and ([IO.Path]::GetExtension($p) -eq '.exe') }
$rom = AskFile 'Where is your Pokemon Black 2 (USA) ROM? (.nds, your own dump)' `
    'Path to the .nds file' (Old 'rom' '') `
    { param($p) $p } `
    { param($p) (Test-Path -LiteralPath $p -PathType Leaf) -and ([IO.Path]::GetExtension($p) -eq '.nds') }

$lines = @(
    "# Black 2 MMO settings. Edit and restart the script (BizHawk: Tools > Lua Console) to apply.",
    "name=$name", "server=$server", "port=$port", "room=$room", "greeting=$greeting",
    "# labels=0 hides names above friends' heads", "labels=$(Old 'labels' '1')",
    "# To change BizHawk or the ROM, run 'Install Black 2 MMO.bat' again.",
    "emuhawk=$emu", "rom=$rom"
)
[IO.File]::WriteAllLines($Ini, $lines, $Utf8)
Write-Host ''
Write-Host "Saved $Ini"

$lua = Join-Path $Here 'lua\b2mmo.lua'
$play = Join-Path $Here 'Play Black 2 MMO.bat'
$bat = @(
    '@echo off',
    'rem Starts BizHawk with Pokemon Black 2 and the Black 2 MMO script. Made by "Install Black 2 MMO.bat".',
    "start `"`" `"$emu`" --lua=`"$lua`" `"$rom`""
)
[IO.File]::WriteAllLines($play, $bat, (New-Object System.Text.ASCIIEncoding))
Write-Host ''
Write-Host "Done. Double-click 'Play Black 2 MMO.bat' to play."
Write-Host 'In game: friends show up as trainers; press A on one to talk, Tab shows who''s online,'
Write-Host 'and the Black 2 MMO window has chat, trading and battles.'
