#Requires -Version 5.1
<#
.SYNOPSIS
Runs a Catchpoint Enterprise image through the WSL container CLI.
.DESCRIPTION
Run .\Start-Catchpoint.ps1 --help for options and forwarding rules.
This is deliberately a simple script without a param() block so PowerShell
does not bind or reject switches intended for wslc run.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$launcherArguments = @($args)

# Launcher settings and external CLI contracts.
$EnterpriseImage = 'enterprise'
$BaseImage = 'enterprise-base'
$SupportedImages = @($EnterpriseImage, $BaseImage)
$DefaultImageTag = 'stable'
$ImageRepository = 'docker.io/catchpoint'
$MinimumCapabilityVersion = [version] '3.0.5'
$BrowserCapability = 'SYS_ADMIN'
$NativeTimeoutSeconds = 60
$ProcessPollMilliseconds = 200
$MillisecondsPerSecond = 1000
$LauncherExitCodeKey = 'LauncherExitCode'
$ContainerIdFileFormat = 'catchpoint-{0}.cid'
$WslExecutable = 'wsl.exe'
$WslcExecutable = 'wslc.exe'
$WslAdvice = 'Install or update modern WSL with wsl --install or wsl --update, enable Virtual Machine Platform, and restart if requested.'
$WslcAdvice = 'Run wsl --update to install a container-capable WSL release, then open a new PowerShell window. Use a native PowerShell process matching your OS architecture.'
$ExitCodes = @{
    Success = 0
    Failure = 1
    InvalidArgument = 2
    VirtualizationFailed = 11
    WslUnavailable = 12
    WslcUnavailable = 13
    Interrupted = 130
}
$Reasons = @{
    InvalidArgument = 'INVALID_ARGUMENT'
    InvalidImage = 'INVALID_IMAGE'
    InvalidTag = 'INVALID_TAG'
    VirtualizationCheckFailed = 'VIRTUALIZATION_CHECK_FAILED'
    VirtualizationDisabled = 'VIRTUALIZATION_DISABLED'
    WslNotFound = 'WSL_NOT_FOUND'
    WslUnavailable = 'WSL_UNAVAILABLE'
    WslcNotFound = 'WSLC_NOT_FOUND'
    WslcVersionFailed = 'WSLC_VERSION_FAILED'
    ContainerExitStatus = 'CONTAINER_EXIT_STATUS'
    ContainerFailed = 'CONTAINER_FAILED'
    LauncherFailed = 'LAUNCHER_FAILED'
}
$Options = @{
    Separator = '--'
    Help = '--help'
    ShortHelp = '-h'
    Image = '--image'
    Version = '--version'
    ContainerIdFile = '--cidfile'
    AddCapability = '--cap-add'
    Remove = '--rm'
    Detach = '--detach'
    ShortDetach = '-d'
}
$Commands = @{
    WslVersion = '--version'
    WslcVersion = 'version'
    Run = 'run'
    Container = 'container'
    List = 'list'
    Kill = 'kill'
}
$Patterns = @{
    ContainerId = '^[0-9a-fA-F]{12,64}$'
    ImageTag = '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}\z'
    RecognizableVersion = '\d+\.\d+'
    SemanticVersion = '(?<![0-9])(?<version>[0-9]+\.[0-9]+\.[0-9]+)(?![0-9])'
    ArgumentNeedsQuoting = '[\s"]'
    BackslashesBeforeQuote = '(\\*)"'
    TrailingBackslashes = '(\\+)$'
}

function Stop-Launcher {
    param([int] $ExitCode, [string] $Reason, [string] $Message)
    $exception = New-Object System.InvalidOperationException "[$Reason] $Message"
    $exception.Data[$LauncherExitCodeKey] = $ExitCode
    throw $exception
}

function Show-LauncherHelp {
    @"
Usage:
  .\Start-Catchpoint.ps1 [launcher options] [--] [wslc run options...]

Launcher options (place before WSLC options):
  --image IMAGE     $EnterpriseImage (default) or $BaseImage.
  --version TAG     Image tag for either image; defaults to $DefaultImageTag.
                    --image=IMAGE and --version=TAG are also accepted.
  --help, -h        Show this help and exit without running prechecks.
  --                End launcher options; forward everything remaining verbatim
                    as wslc run options BEFORE the selected image name.

Images:
  enterprise       Our full-featured offering, including Chrome and Edge browser
                   tests through Playwright and Puppeteer.
                   https://hub.docker.com/repository/docker/catchpoint/enterprise/general

  enterprise-base  Smaller image with additional arm64 support. Does not include
                   Playwright, Puppeteer, Chrome, or Edge support.
                   https://hub.docker.com/repository/docker/catchpoint/enterprise-base/general

Forwarding begins at -- or the first unrecognized argument. After that point,
even --help, --image, and --version are passed to WSLC. The image name is always
the final argument. PowerShell consumes the first -- when the script is run from
a PowerShell prompt, so to forward --help, --image, or --version, put another
WSLC option before it (for example --cap-add SYS_ADMIN --help). PowerShell
quoting applies; quote values containing spaces and use single quotes for
literal text.

Examples:
  .\Start-Catchpoint.ps1 -- $($Options.AddCapability) $BrowserCapability
  .\Start-Catchpoint.ps1 --image enterprise-base --version preview
  .\Start-Catchpoint.ps1 -- $($Options.AddCapability) $BrowserCapability --hostname cp-node01 --env CP_INSTANCEID=ABC123DEF456
  .\Start-Catchpoint.ps1 --image enterprise-base -- --env-file .\catchpoint.env

For $EnterpriseImage, include $($Options.AddCapability) $BrowserCapability so browser tests can sandbox.
Adding capabilities requires WSLC $MinimumCapabilityVersion or later. Older versions warn and
strip $($Options.AddCapability); without $BrowserCapability, browser-based tests will not run.

The container runs in the foreground and is removed when it stops (--rm).
Ctrl+C kills the container started by this launcher.
With $($Options.ShortDetach) or $($Options.Detach), the container runs detached and is left running when the launcher exits.
Checks: virtualization, installed WSL, and wslc version.
Failures print a specific reason to stderr and return a nonzero exit code.
Normally the script returns wslc run's exit code; Ctrl+C returns $($ExitCodes.Interrupted).
"@
}

function ConvertTo-NativeArgument {
    param([AllowEmptyString()] [string] $Value)
    # CRT quoting for .NET Framework / PowerShell 5.1.
    # Double backslashes before quotes and before the closing quote.
    if ($Value.Length -gt 0 -and $Value -notmatch $Patterns.ArgumentNeedsQuoting) { return $Value }
    $escaped = [regex]::Replace($Value, $Patterns.BackslashesBeforeQuote, '$1$1\"')
    $escaped = [regex]::Replace($escaped, $Patterns.TrailingBackslashes, '$1$1')
    return '"' + $escaped + '"'
}

function Invoke-NativeProcess {
    param(
        [string] $FilePath,
        [string[]] $ArgumentList,
        [switch] $Capture,
        [scriptblock] $OnPoll,
        [int] $TimeoutSeconds = $NativeTimeoutSeconds
    )
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    # ArgumentList is unavailable on .NET Framework, so use explicit quoting
    # on both PowerShell editions. Never pass arguments through a shell.
    $quoted = foreach ($value in $ArgumentList) {
        if ($value.IndexOf([char]0) -ge 0) { throw 'Arguments cannot contain NUL characters.' }
        ConvertTo-NativeArgument -Value $value
    }
    $startInfo.Arguments = $quoted -join ' '
    $startInfo.RedirectStandardOutput = [bool] $Capture
    $startInfo.RedirectStandardError = [bool] $Capture
    $startInfo.RedirectStandardInput = [bool] $Capture
    $startInfo.CreateNoWindow = [bool] $Capture
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        [void] $process.Start()
        if ($Capture) {
            # Close stdin so prechecks (e.g. the WSL install prompt) get EOF instead of waiting for a key.
            $process.StandardInput.Close()
            # Drain both streams concurrently to avoid pipe-buffer deadlocks.
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($TimeoutSeconds * $MillisecondsPerSecond)) {
                $process.Kill()
                $process.WaitForExit()
                throw "Timed out after $TimeoutSeconds seconds."
            }
            $stdout = $stdoutTask.GetAwaiter().GetResult().Replace([string][char]0, '').Trim()
            $stderr = $stderrTask.GetAwaiter().GetResult().Replace([string][char]0, '').Trim()
            return [pscustomobject]@{ ExitCode = $process.ExitCode; Stdout = $stdout; Stderr = $stderr }
        }
        # Inherit the caller's console for the foreground container. Poll so
        # Ctrl+C can stop the container while wslc is still attached to it.
        if ($OnPoll) {
            while (-not $process.WaitForExit($ProcessPollMilliseconds)) {
                & $OnPoll
            }
        }
        else {
            $process.WaitForExit()
        }
        return $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
}

function Update-ContainerId {
    param([string] $CidFile, [pscustomobject] $State)
    if (-not $State.Id -and [System.IO.File]::Exists($CidFile)) {
        try { $candidate = [System.IO.File]::ReadAllText($CidFile).Trim() }
        catch [System.IO.IOException], [System.UnauthorizedAccessException] { return } # WSLC may still be writing it.
        if ($candidate -match $Patterns.ContainerId) { $State.Id = $candidate }
    }
}

function Stop-StartedContainer {
    param([string] $WslcPath, [string] $CidFile, [pscustomobject] $State)
    if ($State.KillAttempted) { return }
    Update-ContainerId -CidFile $CidFile -State $State
    if (-not $State.Id) { return }

    $State.KillAttempted = $true
    Write-Host "Stopping container $($State.Id)..."
    # Warn rather than throw so an interrupted run still exits with 130.
    try {
        $result = Invoke-NativeProcess -FilePath $WslcPath -ArgumentList @($Commands.Container, $Commands.Kill, $State.Id) -Capture
        if ($result.ExitCode -ne $ExitCodes.Success) {
            Write-Warning "wslc container kill $($State.Id) exited with code $($result.ExitCode): $($result.Stderr)"
        }
    }
    catch {
        Write-Warning "Could not stop container $($State.Id): $($_.Exception.Message)"
    }
}

function Test-ContainerRunning {
    param([string] $WslcPath, [pscustomobject] $State)
    if (-not $State.Id) { return $false }
    try {
        $result = Invoke-NativeProcess -FilePath $WslcPath -ArgumentList @($Commands.Container, $Commands.List, '--quiet', '--no-trunc') -Capture
        return $result.ExitCode -eq $ExitCodes.Success -and @($result.Stdout -split '\s+') -contains $State.Id
    }
    catch { return $false }
}

function Test-BrowserCapability {
    param([string[]] $Arguments)
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $capabilities = $null
        if ($Arguments[$i] -ceq $Options.AddCapability -and $i + 1 -lt $Arguments.Count) { $capabilities = $Arguments[$i + 1] }
        elseif ($Arguments[$i] -clike ($Options.AddCapability + '=*')) { $capabilities = $Arguments[$i].Substring($Options.AddCapability.Length + 1) }
        if ($capabilities) {
            # Capability names are case-insensitive and may carry a CAP_ prefix.
            $names = @($capabilities -split ',' | ForEach-Object { $_.Trim() })
            if ($names -contains $BrowserCapability -or $names -contains "CAP_$BrowserCapability") { return $true }
        }
    }
    return $false
}

function Test-DetachedRun {
    param([string[]] $Arguments)
    return @($Arguments | Where-Object { $_ -ceq $Options.ShortDetach -or $_ -ceq $Options.Detach }).Count -gt 0
}

function Get-RequiredExecutable {
    param([string] $Name, [int] $ExitCode, [string] $Reason, [string] $Advice)
    $commands = @(Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        Stop-Launcher $ExitCode $Reason "$Name was not found on PATH. $Advice"
    }
    return $commands[0].Source
}

function Test-NativePrecheck {
    param(
        [string] $FilePath, [string[]] $ArgumentList,
        [int] $ExitCode, [string] $Reason, [string] $Advice,
        [switch] $RequireVersion
    )
    try {
        $result = Invoke-NativeProcess -FilePath $FilePath -ArgumentList $ArgumentList -Capture
    }
    catch {
        Stop-Launcher $ExitCode $Reason "$Advice $($_.Exception.Message)"
    }
    $command = ([System.IO.Path]::GetFileName($FilePath)) + ' ' + ($ArgumentList -join ' ')
    if ($result.ExitCode -ne $ExitCodes.Success) {
        $detail = (@($result.Stderr, $result.Stdout) | Where-Object { $_ }) -join [Environment]::NewLine
        Stop-Launcher $ExitCode $Reason "'$command' exited with code $($result.ExitCode). $Advice $detail"
    }
    if ($RequireVersion) {
        # Require real version-like output on stdout, not just a zero exit code.
        if ([string]::IsNullOrWhiteSpace($result.Stdout) -or $result.Stdout -notmatch $Patterns.RecognizableVersion) {
            Stop-Launcher $ExitCode $Reason "'$command' succeeded but did not print a recognizable version. $Advice"
        }
        Write-Host $result.Stdout
        return $result.Stdout
    }
}

function Read-LauncherArguments {
    param([string[]] $Arguments)
    $parsed = [pscustomobject]@{
        Image = $EnterpriseImage
        Tag = $DefaultImageTag
        HelpRequested = $false
        RuntimeArguments = @()
    }
    $index = 0
    while ($index -lt $Arguments.Count) {
        $argument = $Arguments[$index]
        if ($argument -ceq $Options.Separator) { $index++; break }
        if ($argument -ceq $Options.Help -or $argument -ceq $Options.ShortHelp) {
            $parsed.HelpRequested = $true
            return $parsed
        }
        $option = $argument
        $value = $null
        $equalsIndex = $argument.IndexOf('=')
        if ($equalsIndex -ge 0) {
            $option = $argument.Substring(0, $equalsIndex)
            $value = $argument.Substring($equalsIndex + 1)
        }
        # The first unrecognized argument starts runtime-option forwarding.
        if ($option -cnotin @($Options.Image, $Options.Version)) { break }
        $index++
        if ($equalsIndex -lt 0) {
            if ($index -ge $Arguments.Count) {
                Stop-Launcher $ExitCodes.InvalidArgument $Reasons.InvalidArgument "$option requires a value. Run with --help for usage."
            }
            $value = $Arguments[$index]
            $index++
        }
        if ($option -ceq $Options.Image) { $parsed.Image = $value } else { $parsed.Tag = $value }
    }
    $parsed.RuntimeArguments = @($Arguments | Select-Object -Skip $index)
    return $parsed
}

function Assert-ValidArguments {
    param([string] $Image, [string] $Tag, [string[]] $RuntimeArguments)
    if ($Image -cnotin $SupportedImages) {
        Stop-Launcher $ExitCodes.InvalidArgument $Reasons.InvalidImage "Invalid image '$Image'. Use $($SupportedImages -join ' or ')."
    }
    if ($Tag -cnotmatch $Patterns.ImageTag) {
        Stop-Launcher $ExitCodes.InvalidArgument $Reasons.InvalidTag 'The image tag must be 1-128 ASCII letters, digits, underscores, dots, or hyphens, and cannot start with a dot or hyphen.'
    }
    if (@($RuntimeArguments | Where-Object { $_ -ceq $Options.ContainerIdFile -or $_ -clike ($Options.ContainerIdFile + '=*') }).Count -gt 0) {
        Stop-Launcher $ExitCodes.InvalidArgument $Reasons.InvalidArgument '--cidfile is managed by the launcher so Ctrl+C can stop the started container.'
    }
}

function Assert-Virtualization {
    Write-Host 'Checking virtualization...'
    try {
        $computer = Get-CimInstance -ClassName Win32_ComputerSystem -Property HypervisorPresent -ErrorAction Stop
        # An active hypervisor can mask the CPU firmware flag. Accept it first.
        if ($computer.HypervisorPresent -eq $true) { return }
        $processors = @(Get-CimInstance -ClassName Win32_Processor -Property VirtualizationFirmwareEnabled -ErrorAction Stop)
        if ($processors.Count -eq 0 -or @($processors | Where-Object { $null -eq $_.VirtualizationFirmwareEnabled }).Count -gt 0) {
            throw 'CIM did not report processor virtualization status.'
        }
        $enabled = @($processors | Where-Object { $_.VirtualizationFirmwareEnabled -ne $true }).Count -eq 0
    }
    catch {
        Stop-Launcher $ExitCodes.VirtualizationFailed $Reasons.VirtualizationCheckFailed "Cannot verify virtualization using CIM: $($_.Exception.Message)"
    }
    if (-not $enabled) {
        Stop-Launcher $ExitCodes.VirtualizationFailed $Reasons.VirtualizationDisabled 'Hardware virtualization is disabled. Enable Intel VT-x / AMD-V (SVM) in BIOS/UEFI and restart. In a VM, enable nested virtualization on its host.'
    }
}

function Get-WslcRuntime {
    Write-Host 'Checking WSL installation...'
    $wslPath = Get-RequiredExecutable $WslExecutable $ExitCodes.WslUnavailable $Reasons.WslNotFound $WslAdvice
    [void] (Test-NativePrecheck -FilePath $wslPath -ArgumentList @($Commands.WslVersion) -ExitCode $ExitCodes.WslUnavailable -Reason $Reasons.WslUnavailable -Advice $WslAdvice -RequireVersion)

    Write-Host 'Checking WSLC version...'
    $wslcPath = Get-RequiredExecutable $WslcExecutable $ExitCodes.WslcUnavailable $Reasons.WslcNotFound $WslcAdvice
    $versionOutput = Test-NativePrecheck -FilePath $wslcPath -ArgumentList @($Commands.WslcVersion) -ExitCode $ExitCodes.WslcUnavailable -Reason $Reasons.WslcVersionFailed -Advice $WslcAdvice -RequireVersion
    $versionMatch = [regex]::Match($versionOutput, $Patterns.SemanticVersion)
    if (-not $versionMatch.Success) {
        Stop-Launcher $ExitCodes.WslcUnavailable $Reasons.WslcVersionFailed 'wslc version did not include a recognizable semantic version.'
    }
    return [pscustomobject]@{ Path = $wslcPath; Version = [version] $versionMatch.Groups['version'].Value }
}

function Remove-CapabilityArguments {
    param([string[]] $Arguments)
    $filtered = New-Object 'System.Collections.Generic.List[string]'
    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        if ($argument -ceq $Options.AddCapability) {
            if ($index + 1 -lt $Arguments.Count) { $index++ }
            continue
        }
        if ($argument -clike ($Options.AddCapability + '=*')) { continue }
        $filtered.Add($argument)
    }
    return $filtered.ToArray()
}

function Register-InterruptHandlerType {
    if ('CatchpointInterrupt' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Threading;

public static class CatchpointInterrupt
{
    private static int requested;
    public static bool Requested { get { return Interlocked.CompareExchange(ref requested, 0, 0) != 0; } }
    public static void Reset() { Interlocked.Exchange(ref requested, 0); }
    public static void OnCancel(object sender, ConsoleCancelEventArgs args)
    {
        if (args.SpecialKey == ConsoleSpecialKey.ControlC)
        {
            args.Cancel = true;
            Interlocked.Exchange(ref requested, 1);
        }
    }
}
'@
}

function Invoke-Container {
    param([string] $WslcPath, [string] $ImageReference, [string[]] $RuntimeArguments)
    $detached = Test-DetachedRun -Arguments $RuntimeArguments
    Register-InterruptHandlerType
    $cidFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), ($ContainerIdFileFormat -f [guid]::NewGuid().ToString('N')))
    $containerState = [pscustomobject]@{ Id = $null; KillAttempted = $false }
    # Forward runtime options unchanged before the selected image. The image
    # remains the final argument; its entrypoint receives no appended arguments.
    $runArguments = @($Commands.Run, $Options.Remove, $Options.ContainerIdFile, $cidFile) + $RuntimeArguments + @($ImageReference)
    Write-Host "Starting $ImageReference..."
    [CatchpointInterrupt]::Reset()
    $cancelHandler = [System.Delegate]::CreateDelegate(
        [System.ConsoleCancelEventHandler],
        [CatchpointInterrupt].GetMethod('OnCancel')
    )
    try {
        [Console]::add_CancelKeyPress($cancelHandler)
        $runExitCode = Invoke-NativeProcess -FilePath $WslcPath -ArgumentList $runArguments -OnPoll {
            Update-ContainerId -CidFile $cidFile -State $containerState
            if ([CatchpointInterrupt]::Requested) {
                Stop-StartedContainer -WslcPath $WslcPath -CidFile $cidFile -State $containerState
            }
        }
    }
    finally {
        # Neither helper throws, so every cleanup step below always runs.
        Update-ContainerId -CidFile $cidFile -State $containerState
        # wslc also receives Ctrl+C and can exit before our handler sets the flag, so check the container itself.
        # A detached wslc run returns while the container keeps running, so it must not be killed.
        if ([CatchpointInterrupt]::Requested -or (-not $detached -and (Test-ContainerRunning -WslcPath $WslcPath -State $containerState))) {
            Stop-StartedContainer -WslcPath $WslcPath -CidFile $cidFile -State $containerState
        }
        [Console]::remove_CancelKeyPress($cancelHandler)
        if ([System.IO.File]::Exists($cidFile)) { [System.IO.File]::Delete($cidFile) }
    }
    if ([CatchpointInterrupt]::Requested -or $containerState.KillAttempted) { return $ExitCodes.Interrupted }
    if ($runExitCode -ne $ExitCodes.Success) {
        if ($containerState.Id) {
            [Console]::Error.WriteLine("[$($Reasons.ContainerExitStatus)] wslc run returned code $runExitCode.")
        }
        else {
            [Console]::Error.WriteLine("[$($Reasons.ContainerFailed)] wslc run exited with code $runExitCode.")
        }
    }
    return $runExitCode
}

try {
    $parsed = Read-LauncherArguments -Arguments $launcherArguments
    if ($parsed.HelpRequested) {
        Show-LauncherHelp
        exit $ExitCodes.Success
    }
    Assert-ValidArguments -Image $parsed.Image -Tag $parsed.Tag -RuntimeArguments $parsed.RuntimeArguments
    $runtimeArguments = @($parsed.RuntimeArguments)

    Assert-Virtualization
    $wslc = Get-WslcRuntime
    if ($wslc.Version -lt $MinimumCapabilityVersion) {
        Write-Warning "wslc $($wslc.Version) does not support adding capabilities; any $($Options.AddCapability) options will be ignored."
        $runtimeArguments = @(Remove-CapabilityArguments -Arguments $runtimeArguments)
    }
    if ($parsed.Image -ceq $EnterpriseImage -and -not (Test-BrowserCapability -Arguments $runtimeArguments)) {
        Write-Warning "The $EnterpriseImage image needs $($Options.AddCapability) $BrowserCapability for browser tests. Without it, browser-based tests will not run."
    }

    $imageReference = "$ImageRepository/$($parsed.Image):$($parsed.Tag)"
    exit (Invoke-Container -WslcPath $wslc.Path -ImageReference $imageReference -RuntimeArguments $runtimeArguments)
}
catch {
    $failureExitCode = $ExitCodes.Failure
    if ($_.Exception.Data.Contains($LauncherExitCodeKey)) {
        $failureExitCode = [int] $_.Exception.Data[$LauncherExitCodeKey]
        [Console]::Error.WriteLine($_.Exception.Message)
    }
    else {
        [Console]::Error.WriteLine("[$($Reasons.LauncherFailed)] $($_.Exception.Message)")
    }
    exit $failureExitCode
}
