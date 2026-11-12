# Catchpoint Enterprise on WSLC

`Start-Catchpoint.ps1` runs either Catchpoint image through `wslc.exe`. It defaults to **`catchpoint/enterprise:stable`**. Both images default to the `stable` tag.

| Image | Features | Details |
| --- | --- | --- |
| `enterprise` | Full-featured offering with Chrome and Edge browser tests through Playwright and Puppeteer. | [Docker Hub](https://hub.docker.com/repository/docker/catchpoint/enterprise/general) |
| `enterprise-base` | Smaller image with additional arm64 support; lacks Playwright, Puppeteer, Chrome, and Edge support. | [Docker Hub](https://hub.docker.com/repository/docker/catchpoint/enterprise-base/general) |

## Prerequisites

- PowerShell 5.1 or PowerShell 7.
- Hardware virtualization enabled in BIOS/UEFI; nested virtualization enabled on the host if running in a VM.
- Modern WSL installed, with Virtual Machine Platform enabled. Microsoft's [WSLC tutorial](https://learn.microsoft.com/en-us/windows/wsl/tutorials/wsl-containers) specifies WSL 2.9.3 or later. Install/update using `wsl --install` / `wsl --update`, and restart if requested.
- `wsl.exe` and `wslc.exe` available on `PATH`. Use a native PowerShell process matching your OS architecture. A separately installed Linux distribution is not required by this launcher.
- Registry access for the initial image download. WSLC pulls an image when it is missing locally; it uses its normal local cache on later runs. Use `.\Start-Catchpoint.ps1 -- --cap-add SYS_ADMIN --pull always` to refresh the default image's moving tag every run.

The launcher checks prerequisites and reports failures; it does not install software or change system settings. Run it from a PowerShell session whose execution policy permits the script.

## Usage

Open PowerShell in the folder containing the script:

```powershell
# Show help (no prechecks or container launch).
.\Start-Catchpoint.ps1 --help

# Run the full image with the stable tag and browser sandbox capability.
.\Start-Catchpoint.ps1 -- --cap-add SYS_ADMIN

# Run the smaller image with the stable tag.
.\Start-Catchpoint.ps1 --image enterprise-base

# Override the image tag for either image.
.\Start-Catchpoint.ps1 --image enterprise --version preview -- --cap-add SYS_ADMIN
.\Start-Catchpoint.ps1 --image=enterprise-base --version=preview
```

`--version TAG` selects an **image tag**, rather than displaying the launcher's version. Numeric tags are accepted as well. The tag must exist in the selected repository; see the Docker Hub links above.

| Launcher option | Meaning |
| --- | --- |
| `--image IMAGE` | `enterprise` (default) or `enterprise-base`. |
| `--version TAG` | Tag to use, default `stable`. |
| `--help`, `-h` | Display image differences, links, and usage; exit successfully. |
| `--` | End launcher options and forward all remaining arguments as WSLC runtime options before the image name. |

The value options also accept `--option=value`. Place all launcher options before WSLC runtime options.

## Forwarding runtime options

Everything after `--` is forwarded unchanged to `wslc run` **before the selected image name**. This lets you supply hostname, environment variables, mounts, networking, and other customization options supported by your installed WSLC version. The launcher consumes the first `--` separator; the selected image is always the final argument.

The launcher reserves `--cidfile` to track the exact container it starts. Supplying your own `--cidfile` is rejected.

```powershell
# Set the hostname and Catchpoint instance ID.
.\Start-Catchpoint.ps1 --image enterprise-base -- `
    --hostname cp-node01 --env 'CP_INSTANCEID=ABC123DEF456'

# Load environment variables from a file and run in the background.
.\Start-Catchpoint.ps1 --image enterprise --version stable -- `
    --cap-add SYS_ADMIN --env-file .\catchpoint.env --name cp-agent --detach
```

Parsing also stops at the first unrecognized argument, forwarding that argument and everything following it before the image name. After forwarding begins, the launcher no longer interprets `--help`, `--image`, or `--version`. PowerShell itself consumes the first `--` when the script is run from a PowerShell prompt (it is preserved with `powershell -File`), so `-- --help` shows the launcher help there. To request WSLC's run help or forward an option named like a launcher option, put another runtime option first, for example `.\Start-Catchpoint.ps1 --cap-add SYS_ADMIN --help`. Unknown switches begin forwarding, so spelling launcher options correctly matters.

PowerShell parses your command first. Quote arguments with spaces; single quotes preserve literal `$`, quotes, and other characters. PowerShell splits single-dash switches written with a colon (for example `-p:8080:80`), so write `-p 8080:80` or `--publish=8080:80` instead. The launcher preserves argument boundaries, empty strings, embedded quotes, and backslashes when starting WSLC. When invoking from another native shell, that shell and the `powershell.exe`/`pwsh.exe -File` boundary also apply their own parsing.

## WSLC runtime options and Catchpoint activation

Pass the complete sequence of runtime options and their values after `--`:

```powershell
.\Start-Catchpoint.ps1 --image enterprise-base -- `
    --hostname cp-node01 --env 'CP_INSTANCEID=ABC123DEF456'
```

This constructs the following command (the launcher invokes the executable directly):

```text
wslc run --rm --hostname cp-node01 --env CP_INSTANCEID=ABC123DEF456 docker.io/catchpoint/enterprise-base:stable
```

Choose your own hostname and instance ID. Catchpoint's [deployment guidance](https://hub.docker.com/r/catchpoint/enterprise-base) recommends a hostname matching the portal instance and a fixed 12-character uppercase alphanumeric `CP_INSTANCEID`. Activation remains necessary. The image documentation describes manual activation and the `CP_APIKEY` / `CP_NODENAME` environment variables for automatic activation. The launcher prints the image name, without echoing forwarded values.

When using the full `enterprise` image, include `--cap-add SYS_ADMIN` so browser tests can sandbox properly. Without it, no browser-based tests run. Adding capabilities requires WSLC 3.0.5 or later; on older versions, the launcher warns and strips all `--cap-add` options, then warns that browser tests cannot run. The `enterprise-base` image does not need this browser capability. Use `wslc run --help` to check other runtime options supported by your installed version.

The container runs in the foreground by default, with WSLC output connected to the caller's console. Pressing Ctrl+C makes the launcher send `wslc container kill` to the ID written by `--cidfile`; `--rm` removes it after it stops. The launcher deletes its temporary ID file afterward and exits with code `130` for Ctrl+C. An interactive Bash shell can also return `130` after a command was interrupted: plain `exit` preserves the previous command's status. Use `exit 0` when you intend a successful shell exit. Container removal by `--rm` does not depend on an exit code of zero. WSLC's default pull policy is `missing`. To use background operation, pass `--detach` after `--`; then the exit code reports startup, rather than the eventual container outcome. A detached container is no longer tied to the launcher's Ctrl+C handler; stop it separately with `wslc container stop <ID>`.

## Prechecks and exit codes

Before launching the selected image, the script:

1. Checks CIM for an active hypervisor or enabled processor virtualization. An active hypervisor is accepted because it can mask the firmware flag. Failure to read the status is reported explicitly.
2. Finds `wsl.exe` and requires `wsl --version` to succeed and print a recognizable version.
3. Finds `wslc.exe` and requires `wslc version` to succeed and print a recognizable version.

Each native precheck has a 60-second timeout. On failure the script stops immediately, writes a bracketed reason and diagnostic details to stderr, and does not run the selected image. Runtime, registry download, and workload failures are reported by `wslc run`.

| Exit code | Meaning |
| --- | --- |
| `0` | Help displayed, or `wslc run` succeeded. |
| `1` | Unexpected launcher/process error (`LAUNCHER_FAILED`). |
| `2` | Invalid launcher option value, image, or tag. |
| `11` | Virtualization disabled or its status could not be verified. |
| `12` | WSL executable missing, version command failed, or version output invalid. |
| `13` | WSLC executable missing, version command failed, or version output invalid. |
| `130` | Foreground run interrupted with Ctrl+C; the launcher sent `wslc container kill` to its container ID. |
| Other run result | After launching, the exact `wslc run` exit code is returned unless Ctrl+C was pressed. A nonzero result from a started container is labeled `CONTAINER_EXIT_STATUS`; a failure before its ID is recorded is labeled `CONTAINER_FAILED`. |

After calling the script from PowerShell, inspect `$LASTEXITCODE` to check success or failure. Avoid dot-sourcing this launcher: it uses `exit` to return its result.
