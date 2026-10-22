[CmdletBinding()]
param(
    [ValidateSet('Check', 'Build', 'Deploy', 'Rollback')]
    [string]$Action = 'Check',
    [string]$Go = 'go',
    [string]$RunDirectory,
    [string]$Candidate,
    [string]$UpstreamRef = 'upstream/main'
)

$ErrorActionPreference = 'Stop'
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$branch = 'main'

function Invoke-Git([string[]]$Arguments) {
    $result = & git -C $source @Arguments
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($Arguments -join ' ')" }
    return $result
}

function Invoke-Go([string]$Directory, [string[]]$Arguments) {
    Push-Location -LiteralPath $Directory
    try {
        & $Go @Arguments
        if ($LASTEXITCODE -ne 0) { throw "go failed: $($Arguments -join ' ')" }
    } finally { Pop-Location }
}

function Copy-Data([string]$From, [string]$To) {
    if (-not (Test-Path -LiteralPath $From)) { return }
    & robocopy $From $To /E /COPY:DATS /DCOPY:DAT /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Could not copy data from $From" }
}

function Running-Custom {
    @(Get-CimInstance Win32_Process -Filter "Name = 'magpie-custom.exe'" | Where-Object {
        $_.ExecutablePath -and [IO.Path]::GetFullPath($_.ExecutablePath) -eq $script:executable
    })
}

function Stop-Custom {
    foreach ($proc in (Running-Custom)) {
        $running = Get-Process -Id $proc.ProcessId -ErrorAction SilentlyContinue
        if ($running) {
            $null = $running.CloseMainWindow()
            try { $running.WaitForExit(10000) | Out-Null } catch { }
        }
    }
    if ((Running-Custom).Count) { throw 'Quit the custom Magpie from its tray menu, then retry. No process was killed.' }
}

function Start-Custom {
    $proc = Start-Process -FilePath $script:executable -ArgumentList 'gui' -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $proc.Refresh()
        if ($proc.HasExited) { throw 'The custom executable exited during startup.' }
        # Check the listener belongs to this process, not to another Magpie.
        if (Get-NetTCPConnection -State Listen -LocalPort 3425 -ErrorAction SilentlyContinue | Where-Object OwningProcess -eq $proc.Id) {
            & $script:executable healthcheck
            if ($LASTEXITCODE -eq 0) { return }
        }
    }
    throw 'The custom executable did not start its gateway on port 3425.'
}

function Restore-Deployment($Deployment) {
    $backupPath = [IO.Path]::GetFullPath($Deployment.backup)
    $backupRoot = [IO.Path]::GetFullPath((Join-Path $run '.backups')) + [IO.Path]::DirectorySeparatorChar
    if (-not $backupPath.StartsWith($backupRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Backup is outside this installation.' }
    if ($Deployment.restored) { throw 'This deployment has already been rolled back.' }
    $oldExe = Join-Path $backupPath 'magpie-custom.exe'
    if ($Deployment.hadExe -and -not (Test-Path -LiteralPath $oldExe)) { throw 'Backup executable is missing.' }
    if ($Deployment.hadData -and -not (Test-Path -LiteralPath (Join-Path $backupPath 'data'))) { throw 'Backup data is missing.' }
    $failed = Join-Path $run ('.failed-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-ffff'))
    New-Item -ItemType Directory -Path $failed | Out-Null
    # Preserve the newer data as well; rollback never deletes either generation.
    if (Test-Path -LiteralPath $data) {
        if ([IO.Path]::GetFullPath($data) -ne (Join-Path $run 'data')) { throw 'Unexpected data path.' }
        Move-Item -LiteralPath $data -Destination (Join-Path $failed 'data')
    }
    if ($Deployment.hadData) { Copy-Data (Join-Path $backupPath 'data') $data }
    if (Test-Path -LiteralPath $script:executable) {
        Move-Item -LiteralPath $script:executable -Destination (Join-Path $failed 'magpie-custom.exe')
    }
    if ($Deployment.hadExe) {
        Copy-Item -LiteralPath $oldExe -Destination $script:executable
        Start-Custom
    }
    $Deployment | Add-Member -NotePropertyName restored -NotePropertyValue $true -Force
    $Deployment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateFile -Encoding utf8
    Write-Host "Restored the previous executable and data. Newer files preserved at $failed"
}

$lock = $null
$oldEnvironment = @{}
try {
    $gitDir = (Invoke-Git -Arguments @('rev-parse', '--absolute-git-dir')).Trim()
    $lock = [IO.File]::Open((Join-Path $gitDir 'custom-update.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if ($Action -in @('Check', 'Build')) {
        if ((Invoke-Git -Arguments @('branch', '--show-current')).Trim() -ne $branch) { throw "Run from $branch." }
        if (Invoke-Git -Arguments @('status', '--porcelain')) { throw 'Commit or move your local changes before updating.' }
        $upstream = (Invoke-Git -Arguments @('remote', 'get-url', 'upstream')).Trim()
        if ($upstream -notin @('https://github.com/yetone/magpie.git', 'https://github.com/yetone/magpie')) { throw 'Unexpected upstream URL.' }
        Invoke-Git -Arguments @('fetch', 'upstream', '--tags') | Out-Host
        $target = (Invoke-Git -Arguments @('rev-parse', '--verify', "$UpstreamRef^{commit}")).Trim()
        $base = (Invoke-Git -Arguments @('rev-parse', 'HEAD')).Trim()
        Write-Host "Current: $base`nUpstream target: $target"
        if ($Action -eq 'Check') { return }

        $Go = (Get-Command $Go -ErrorAction Stop).Source
        foreach ($name in @('GOPATH', 'GOMODCACHE', 'GOCACHE', 'CGO_ENABLED', 'HOME', 'USERPROFILE')) {
            $oldEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        }
        foreach ($name in @('GOPATH', 'GOMODCACHE', 'GOCACHE')) {
            $value = & $Go env $name
            if ($LASTEXITCODE -ne 0) { throw "Cannot read $name" }
            [Environment]::SetEnvironmentVariable($name, $value.Trim(), 'Process')
        }
        $env:CGO_ENABLED = '0'
        $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-ffff')
        $work = Join-Path $gitDir "custom-builds/$stamp/source"
        $package = Join-Path $gitDir "custom-builds/$stamp/package"
        New-Item -ItemType Directory -Path $package -Force | Out-Null
        Invoke-Git -Arguments @('worktree', 'add', '-b', "custom/update-$stamp", $work, $base) | Out-Host
        & git -C $work merge --no-edit $target
        if ($LASTEXITCODE -ne 0) { throw "Resolve the merge in $work; the running app is unchanged." }
        $head = (& git -C $work rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Cannot read candidate commit.' }
        $isolatedHome = Join-Path $gitDir "custom-builds/$stamp/home"
        New-Item -ItemType Directory -Path $isolatedHome | Out-Null
        $env:HOME = $isolatedHome
        $env:USERPROFILE = $isolatedHome
        Invoke-Go -Directory $work -Arguments @('vet', './...')
        Invoke-Go -Directory $work -Arguments @('test', '-tags', 'nogui', './...')
        Invoke-Go -Directory $work -Arguments @('run', 'github.com/tc-hib/go-winres@v0.3.3', 'make', '--in', 'build/windows/winres.json', '--arch', 'amd64,arm64', '--out', 'rsrc', '--file-version', '0.0.0', '--product-version', '0.0.0')
        Invoke-Go -Directory $work -Arguments @('build', '-tags', 'production', '-trimpath', '-ldflags', "-s -w -H windowsgui -X main.version=custom-$($head.Substring(0,12))", '-o', (Join-Path $package 'magpie-custom.exe'), '.')
        $manifest = [ordered]@{
            base = $base; upstream = $target; commit = $head
            source = $work; executable = 'magpie-custom.exe'
            sha256 = (Get-FileHash -LiteralPath (Join-Path $package 'magpie-custom.exe')).Hash
            go = (& $Go version) -join ''
            builtUtc = [DateTime]::UtcNow.ToString('o')
            checks = @('native vet', 'existing nogui suite', 'Windows desktop build')
            remainingChecks = @('GUI browsers', 'Linux vet/build', 'race', 'isolated real-agent use')
        }
        $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $package 'manifest.json') -Encoding utf8
        Write-Host "Candidate: $package`nReview remaining checks before deployment. Source branch and running app are unchanged."
        return
    }

    if (-not $RunDirectory) { throw 'Deploy/Rollback requires -RunDirectory, a dedicated portable installation.' }
    $run = [IO.Path]::GetFullPath($RunDirectory)
    if ($run -eq [IO.Path]::GetPathRoot($run) -or $run -eq $source) { throw 'Use a dedicated runtime directory, not a drive root or source checkout.' }
    if (-not (Test-Path -LiteralPath (Join-Path $run '.portable'))) { throw 'Create a dedicated portable installation with a .portable marker first.' }
    $script:executable = Join-Path $run 'magpie-custom.exe'
    $data = Join-Path $run 'data'
    $stateFile = Join-Path $run 'custom-deployment.json'
    if ($Action -eq 'Deploy') {
        if (-not $Candidate) { throw 'Deploy requires -Candidate <package-directory>.' }
        $candidateRoot = [IO.Path]::GetFullPath($Candidate)
        $manifest = Get-Content -LiteralPath (Join-Path $candidateRoot 'manifest.json') -Raw | ConvertFrom-Json
        if ($manifest.executable -ne 'magpie-custom.exe') { throw 'Unexpected candidate executable.' }
        $newExe = Join-Path $candidateRoot 'magpie-custom.exe'
        if ((Get-FileHash -LiteralPath $newExe).Hash -ne $manifest.sha256) { throw 'Candidate checksum mismatch.' }
        if ($manifest.remainingChecks.Count) { throw 'Finish and record the manifest remainingChecks before deployment.' }
        $ownPids = @((Running-Custom) | ForEach-Object ProcessId)
        if (Get-NetTCPConnection -State Listen -LocalPort 3425 -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -notin $ownPids }) { throw 'Port 3425 is occupied by another process.' }
        Stop-Custom
        if (Get-NetTCPConnection -State Listen -LocalPort 3425 -ErrorAction SilentlyContinue) { throw 'Port 3425 has not been released.' }
        $backup = Join-Path $run ('.backups/' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-ffff'))
        New-Item -ItemType Directory -Path $backup | Out-Null
        Copy-Data $data (Join-Path $backup 'data')
        $previous = Join-Path $backup 'magpie-custom.exe'
        $hadExe = Test-Path -LiteralPath $script:executable
        $staged = Join-Path $run 'magpie-custom.exe.new'
        Copy-Item -LiteralPath $newExe -Destination $staged
        try {
            if ($hadExe) { [IO.File]::Replace($staged, $script:executable, $previous) }
            else { [IO.File]::Move($staged, $script:executable) }
        } catch {
            if ($hadExe -and (Test-Path -LiteralPath $script:executable)) { Start-Custom }
            throw
        }
        $deployment = [pscustomobject]@{ backup = $backup; hadExe = $hadExe; hadData = (Test-Path -LiteralPath (Join-Path $backup 'data')); candidate = $manifest }
        try {
            $deployment | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateFile -Encoding utf8
            Start-Custom
        }
        catch {
            Write-Warning "Startup failed. Rollback state saved at $stateFile. $($_.Exception.Message)"
            # A failed process may still be running; never overwrite its files.
            Stop-Custom
            Restore-Deployment $deployment
            throw
        }
        Write-Host "Deployed $($manifest.commit). Backup: $backup"
    } else {
        $deployment = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
        Stop-Custom
        Restore-Deployment $deployment
    }
} finally {
    foreach ($name in $oldEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name], 'Process')
    }
    if ($lock) { $lock.Dispose() }
}
