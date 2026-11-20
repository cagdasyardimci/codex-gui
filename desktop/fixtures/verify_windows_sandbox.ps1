param(
    [Parameter(Mandatory = $true)]
    [string]$Probe,
    [string]$Codex,
    [switch]$InProfile
)

$ErrorActionPreference = 'Stop'
if ($InProfile) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Expected a standard-user token'
    }

    $profileDirectory = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    if (-not $profileDirectory) { throw 'The test user profile was not loaded' }
    $env:CODEX_HOME = Join-Path $profileDirectory '.codex'
    if (Test-Path $env:CODEX_HOME) { throw 'Expected a fresh Codex profile' }
    $checkout = Join-Path $profileDirectory 'Codex GUI probe checkout'
    New-Item -ItemType Directory -Path $checkout | Out-Null
    Write-Host 'Running under a fresh standard-user profile'
    & $Probe $Codex $checkout
    exit $LASTEXITCODE
}

$Probe = (Resolve-Path $Probe).Path
$stage = Join-Path $env:RUNNER_TEMP ("codex-sandbox-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$distribution = Join-Path $stage 'cli'
npm install --prefix $distribution --no-save --no-audit --no-fund --ignore-scripts '@openai/codex@0.163.0'
if ($LASTEXITCODE -ne 0) { throw 'Failed to install the pinned Codex CLI' }
$executables = @(Get-ChildItem -Path $distribution -Recurse -Filter 'codex.exe' -File)
if ($executables.Count -ne 1) { throw 'Expected one native Codex executable' }
$codexExe = $executables[0].FullName
$stagedProbe = Join-Path $stage 'sandbox-probe.exe'
$stagedScript = Join-Path $stage 'sandbox-probe.ps1'
Copy-Item $Probe $stagedProbe
Copy-Item $PSCommandPath $stagedScript

$username = 'codexqa' + [Guid]::NewGuid().ToString('N').Substring(0, 10)
$password = ConvertTo-SecureString ('Cg!1' + [Guid]::NewGuid().ToString('N')) -AsPlainText -Force
$user = New-LocalUser -Name $username -Password $password
try {
    $members = @(Get-LocalGroupMember -SID 'S-1-5-32-545')
    if ($user.SID -notin $members.SID) {
        Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $user
    }
    $sid = $user.SID.Value
    & icacls.exe $stage /grant "*${sid}:(OI)(CI)RX" /Q
    if ($LASTEXITCODE -ne 0) { throw 'Failed to grant access to the isolated probe binaries' }

    $credential = [PSCredential]::new("$env:COMPUTERNAME\$username", $password)
    $arguments = '-NoLogo -NoProfile -NonInteractive -File "{0}" -Probe "{1}" -Codex "{2}" -InProfile' -f $stagedScript, $stagedProbe, $codexExe
    $output = Join-Path $stage 'stdout.log'
    $errors = Join-Path $stage 'stderr.log'
    $process = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -Credential $credential `
        -LoadUserProfile -ArgumentList $arguments -WorkingDirectory $stage `
        -RedirectStandardOutput $output -RedirectStandardError $errors -PassThru
    if (-not $process.WaitForExit(210000)) {
        Stop-Process -Id $process.Id
        throw 'The Windows sandbox probe timed out'
    }
    Get-Content $output
    Get-Content $errors
    if ($process.ExitCode -ne 0) { throw "The Windows sandbox probe exited with code $($process.ExitCode)" }
} finally {
    Remove-LocalUser -SID $user.SID
}
