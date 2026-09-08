#!/bin/sh
# @file get_agent.sh
# @brief This script installs the Catchpoint SyntheticAgent on a Linux system. It supports both Debian-based and Red Hat-based distributions.

readonly SCRIPT_VERSION="1.0.0"

# Defaults
CACHE_UPDATE_COMMAND=""
INSTALL_PACKAGES_COMMAND=""
PACKAGES_TO_INSTALL=""
DISTRO_FLAVOR=""
MACHINE_ID=""
INSTANCE_NAME=""
INSTALL_PLAYWRIGHT="true"
INSTALL_LEGACY="true"
API_TOKEN=""
NODE_NAME=""
EXCLUDE_SWITCHES=""

if command -v tput > /dev/null 2>&1 && [ "$(tput colors 2> /dev/null || echo 0)" -ge 8 ]; then
    RED=$(tput setaf 1)
    readonly RED
    GREEN=$(tput setaf 2)
    readonly GREEN
    YELLOW=$(tput setaf 3)
    readonly YELLOW
    NO_COLOR=$(tput sgr0)
    readonly NO_COLOR
fi

readonly REQUIRED_PACKAGES='curl sudo'

readonly MACHINE_ID_KEY="Node_InstanceId"
readonly INSTANCE_NAME_KEY="Node_InstanceName"
readonly COMMENG_CONF="/etc/catchpoint.d/CommEng.conf"

#########################################################################################
# RHEL
readonly CATCHPOINT_RHEL_REPO="https://repo.catchpoint.net/repo/%s/%s"
readonly CATCHPOINT_RHEL_REPO_FILE="/etc/yum.repos.d/catchpoint.repo"

#########################################################################################
# DEB
readonly CATCHPOINT_DEB_REPO="https://proddebrepo.catchpoint.net/repo/proddebrepo.list"
readonly CATCHPOINT_DEB_REPO_FILE="/etc/apt/sources.list.d/catchpoint.list"
readonly CATCHPOINT_DEB_KEY_URL="https://proddebrepo.catchpoint.net/repo/prod-key.asc"
readonly CATCHPOINT_DEB_KEY_LEGACY_DIR="/etc/apt/trusted.gpg.d"

###############################################################################
# @description Displays help/usage information.
#
# @noargs
#
# @exitcode 0 for success (always).
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

DESCRIPTION:
    This script installs the Catchpoint SyntheticAgent on a Linux system. It supports both Debian-based and
    Red Hat-based distributions.

    If api-key and node are provided, the agent will be activated after installation. If not provided, the
    agent will not be activated.

    To skip the installation of the Playwright package, use the --skip-playwright option. This removes the
    ability to run Playwright or Puppeteer monitors.

    To skip the installation of the syntheticagent-legacy package, use the --skip-legacy option. This removes
    the ability to run legacy monitors (e.g. Chrome, Selenium).

    Machine ID will default to the system's primary network adapter's MAC address if not provided. This can
    be overridden with the '--machine-id' option. The machine ID must be a 12-character alphanumeric string.

    The Instance Name will default to the system's hostname if not provided. This can be overridden with the
    '--instance-name' option.

    If your hostname has a '.' in it, the instance name will be truncated to the first part of the hostname
    (e.g. 'host.domain.com' will become 'host').

OPTIONS:
    -a, --api-key        [Optional] Provide an API token for activation. Must be used with --node.
    -n, --node           [Optional] Provide a node name for activation. Must be used with --api-key.
    -m, --machine-id     [Optional] Specify a machine ID to use for the installation.
    -i, --instance-name  [Optional] Specify an instance name to use for the installation.
    --skip-playwright    [Optional] Skip the installation of the Playwright package.
    --skip-legacy        [Optional] Skip the installation of the syntheticagent-legacy package.
    -h, --help           Show this help message and exit.
    -v, --version        Show the script version and exit.
EOF
}

###############################################################################
# @description Parse the incoming arguments.
#
# @args $1... string All arguments to parse.
#
# @set API_TOKEN string API token for activation (from --api-key). 
# @set NODE_NAME string Node name for activation (from --node). 
# @set MACHINE_ID string 12-character machine ID override (from --machine-id). 
# @set INSTANCE_NAME string Instance name/hostname override (from --instance-name). 
# @set INSTALL_PLAYWRIGHT/INSTALL_LEGACY bool Whether to install optional Playwright and legacy monitor packages.
#
# @exitcode 0 for success.
# @exitcode 1 for failure.
# @exitcode 2 for invalid arguments.
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -a|--api-key)
                if [ -n "$2" ]; then
                    API_TOKEN="$2"
                    shift 2
                else
                    print_error "Missing argument for --api-key. Please provide a valid API key."
                    return 1
                fi
                ;;
            -n|--node)
                if [ -n "$2" ]; then
                    NODE_NAME="$2"
                    shift 2
                else
                    print_error "Missing argument for --node. Please provide a valid node name."
                    return 1
                fi
                ;;
            -i|--instance-name)
                if [ -n "$2" ]; then
                    INSTANCE_NAME="$2"
                    shift 2
                else
                    print_error "Missing argument for --instance-name. Please provide a valid instance name."
                    return 1
                fi
                ;;
            -m|--machine-id)
                if [ -z "$2" ]; then
                    print_error "Missing argument for --machine-id. Please provide a valid machine ID."
                    return 1
                elif ! echo "$2" | grep -Eq '^[A-Za-z0-9]{12}$'; then
                    print_error "Invalid machine ID: $2. Machine ID must be a 12-character alphanumeric string."
                    return 1
                fi
                MACHINE_ID="$2"
                shift 2
                ;;
            --skip-playwright)
                INSTALL_PLAYWRIGHT=false
                shift
                ;;
            --skip-legacy)
                INSTALL_LEGACY=false
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "${SCRIPT_VERSION}"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                return 2
                ;;
        esac
    done
}

###############################################################################
# @description Prints a message with a timestamp to stderr.
#
# @arg $1 string Any number of args will be printed to stderr.
#
# @exitcode 0 If printf succeeds.
# @exitcode 1 If printf fails (this should never occur).
print_message() {
    printf "%s %s\n" "$(date "+%FT%T")" "$*" >&2
}

###############################################################################
# @description Prints a message with a GREEN 'INFO:' header to stderr.
#
# @arg $1 string Any number of args will be printed to stderr.
#
# @exitcode 0 If printf succeeds.
# @exitcode 1 If printf fails (this should never occur).
print_info() {
    print_message "$(printf "%sINFO:%s %s" "${GREEN:-}" "${NO_COLOR:-}" "$*")"
}

###############################################################################
# @description Prints a message with a YELLOW 'WARNING:' header to stderr.
#
# @arg $1 string Any number of args will be printed to stderr.
#
# @exitcode 0 If printf succeeds.
# @exitcode 1 If printf fails (this should never occur).
print_warning() {
    print_message "$(printf "%sWARNING:%s %s" "${YELLOW:-}" "${NO_COLOR:-}" "$*")"
}

###############################################################################
# @description Prints a message in RED with an 'ERROR:' header to stderr.
#
# @arg $1 string Any number of args will be printed to stderr.
#
# @exitcode 0 If printf succeeds.
# @exitcode 1 If printf fails (this should never occur).
print_error() {
    print_message "$(printf "%sERROR:%s %s" "${RED:-}" "${NO_COLOR:-}" "$*")"
}

###############################################################################
# @description Checks if the script is being run as root.
#
# @noargs
#
# @exitcode 0 If the script is being run as root.
# @exitcode 1 If the script is not being run as root.
is_root() {
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    fi
    return 0
}

###############################################################################
# @description Checks if both API_TOKEN and NODE_NAME are provided for activation.
# If only one is provided, it prints an error message and returns a non-zero exit code.
# If neither is provided, it prints an informational message and sleeps for 5 seconds
# to allow the user to cancel if they want to provide these values.
#
# @noargs
#
# @exitcode 0 If both API_TOKEN and NODE_NAME are provided or if neither is provided.
# @exitcode 1 If only one of API_TOKEN or NODE_NAME is provided.
confirm_is_activateable() {
    if [ -n "${API_TOKEN}" ] && [ -n "${NODE_NAME}" ]; then
        print_info "API token and node name provided. The agent will be activated after installation."
    elif [ -n "${API_TOKEN}" ] || [ -n "${NODE_NAME}" ]; then
        print_error "Both API token and node name must be provided for activation. Please provide both or neither."
        return 1
    else
        # Print info and then sleep for 5 seconds to give the user time to read the message and cancel if they want to.
        print_info "No API token or node name provided. The agent will not be activated after installation."
        print_warning "Press Ctrl+C within 5 seconds to cancel the installation if you want to provide these values."
        sleep 5
    fi
}

###############################################################################
# @description Checks for required prerequisites and determines the appropriate 
# package manager and repository configuration based on the Linux distribution.
#
# @noargs
#
# @sets CACHE_UPDATE_COMMAND string The command to update the package manager's cache.
# @sets INSTALL_PACKAGES_COMMAND string The command to install packages using the package manager.
# @sets PACKAGES_TO_INSTALL string The name of the Catchpoint package to install.
# @sets DISTRO_FLAVOR string A string representing the Linux distribution flavor (e.g., 'debian', 'rhel7', 'rhel8', 'rhel9').
# @sets EXCLUDE_SWITCHES string A string containing any package manager switches to exclude certain packages from installation.
#
# @exitcode 0 If all prerequisites are met and the distribution is supported.
# @exitcode 1 If any prerequisites are missing or the distribution is unsupported.
confirm_prerequisites() {
    # Block if not x86_64 architecture
    if [ "$(uname -m)" != "x86_64" ]; then
        print_error "Unsupported architecture: $(uname -m). This script only supports x86_64 architecture."
        return 1
    fi

    if ! is_root; then
        print_error "This script must be run as root. Please run with sudo or as root user."
        return 1
    fi

    for package in ${REQUIRED_PACKAGES}; do
        if ! command -v "${package}" >/dev/null 2>&1; then
            print_error "Required package '${package}' is not installed. Please install it and try again."
            return 1
        fi
    done

    if command -v apt-get >/dev/null 2>&1; then
        CACHE_UPDATE_COMMAND="apt-get update"
        INSTALL_PACKAGES_COMMAND="apt-get install -y"
        PACKAGES_TO_INSTALL="syntheticagent"
        if [ "${INSTALL_PLAYWRIGHT}" = "true" ]; then
            PACKAGES_TO_INSTALL="${PACKAGES_TO_INSTALL} playwright"
        else
            EXCLUDE_SWITCHES="--no-install-recommends"
        fi
        if [ "${INSTALL_LEGACY}" = "true" ]; then
            PACKAGES_TO_INSTALL="${PACKAGES_TO_INSTALL} syntheticagent-legacy"
        else
            EXCLUDE_SWITCHES="--no-install-recommends"
        fi
        DISTRO_FLAVOR="debian"
    elif command -v yum >/dev/null 2>&1; then
        CACHE_UPDATE_COMMAND="yum makecache"
        INSTALL_PACKAGES_COMMAND="yum install -y"
        PACKAGES_TO_INSTALL="SyntheticAgent"
        if [ "${INSTALL_PLAYWRIGHT}" = "true" ]; then
            PACKAGES_TO_INSTALL="${PACKAGES_TO_INSTALL} Playwright"
        else
            EXCLUDE_SWITCHES="--exclude=Playwright"
        fi
        if [ "${INSTALL_LEGACY}" = "true" ]; then
            PACKAGES_TO_INSTALL="${PACKAGES_TO_INSTALL} syntheticagent-legacy"
        else
            EXCLUDE_SWITCHES="${EXCLUDE_SWITCHES} --exclude=syntheticagent-legacy"
        fi
        DISTRO_FLAVOR="rhel"
    else
        print_error "Unsupported package manager. This script supports apt-get and yum."
        return 1
    fi

    print_info "Detected package manager: ${CACHE_UPDATE_COMMAND%% *}. Using it to install ${PACKAGES_TO_INSTALL}."
    if [ -n "${EXCLUDE_SWITCHES}" ]; then
        print_info "Excluding packages with switch(es): ${EXCLUDE_SWITCHES}"
    fi
}

###############################################################################
# @description Configures the appropriate package repository for the Linux distribution
# and updates the package manager's cache.
#
# @noargs
#
# @exitcode 0 If the repository is configured and the cache is updated successfully.
# @exitcode 1 If there is an error configuring the repository or updating the cache.
install_repo(){
    if [ "${DISTRO_FLAVOR}" = "debian" ]; then
        # Check the repo directory for *any* .list files that contain "catchpoint" in their name. 
        # If any are found, we assume the repo is already configured.
        if ls /etc/apt/sources.list.d/catchpoint*.list >/dev/null 2>&1; then
            print_info "Catchpoint APT repository is already configured. Skipping repository configuration."
            return 0
        fi

        print_info "Configuring Catchpoint APT repository for Debian-based distribution."
        if ! curl -fsSL "${CATCHPOINT_DEB_REPO}" -o "${CATCHPOINT_DEB_REPO_FILE}"; then 
            print_error "Failed to download Catchpoint APT repository list from ${CATCHPOINT_DEB_REPO}."
            return 1
        fi

        if ! curl -fsSL "${CATCHPOINT_DEB_KEY_URL}" -o "${CATCHPOINT_DEB_KEY_LEGACY_DIR}/prod-key.asc"; then
            print_error "Failed to download or add Catchpoint APT repository key from ${CATCHPOINT_DEB_KEY_URL}."
            return 1
        fi
    elif [ "${DISTRO_FLAVOR}" = "rhel" ]; then
        # Check the repo directory for *any* .repo files that contain "catchpoint" in their name.
        # If any are found, we assume the repo is already configured.
        if ls /etc/yum.repos.d/catchpoint*.repo >/dev/null 2>&1; then
            print_info "Catchpoint YUM repository is already configured. Skipping repository configuration."
            return 0
        fi

        print_info "Configuring Catchpoint YUM repository for Red Hat-based distribution."
        #shellcheck disable=SC1083
        distro_version=$(rpm -E %{rhel})

        # Special case: we support amazon 2023 but it does not set the 'rhel' macro. 
        # If %{rhel} is not set, check for amzn2023 and then override the distro.
        if [ "${distro_version}" = "%{rhel}" ] && [ -n "$(rpm -E '%{?amzn}')" ]; then
            distro_version="9"
        fi

        case "${distro_version}" in
            8)
                #shellcheck disable=SC2059# The CATCHPOINT_RHEL_REPO includes the format specifier.
                repo=$(printf "${CATCHPOINT_RHEL_REPO}" "${DISTRO_FLAVOR}${distro_version}" "catchpoint_el8.repo")
                ;;
            9)
                #shellcheck disable=SC2059# The CATCHPOINT_RHEL_REPO includes the format specifier.
                repo=$(printf "${CATCHPOINT_RHEL_REPO}" "${DISTRO_FLAVOR}${distro_version}" "catchpoint_el9.repo")
                ;;
            *)
                print_error "Unsupported Red Hat version: ${distro_version}. Supported versions are RHEL 8 and 9."
                return 1
                ;;
        esac

        curl -fsSL "${repo}" -o "${CATCHPOINT_RHEL_REPO_FILE}" || {
            print_error "Failed to download Catchpoint YUM repository file from ${repo}."
            return 1
        }
    fi

    print_info "Package repository configured and cache updated successfully."
}

###############################################################################
# @description Sets the machine ID in the Catchpoint configuration file if a 
# MACHINE_ID variable is provided.
#
# @noargs
#
# @exitcode 0 If the machine ID is set successfully or if MACHINE_ID is not provided.
# @exitcode 1 If there is an error setting the machine ID in the configuration file.
set_machine_id() {
    if [ -n "${MACHINE_ID}" ]; then
        if grep -q "^${MACHINE_ID_KEY}=" "${COMMENG_CONF}" 2>/dev/null; then
            sed -i "s/^${MACHINE_ID_KEY}=.*/${MACHINE_ID_KEY}=${MACHINE_ID}/" "${COMMENG_CONF}"
        else
            mkdir -p "$(dirname "${COMMENG_CONF}")"
            echo "${MACHINE_ID_KEY}=${MACHINE_ID}" >> "${COMMENG_CONF}"
        fi
    fi
}

###############################################################################
# @description Sets the instance name in the Catchpoint configuration file if 
# an INSTANCE_NAME variable is provided.
#
# @noargs
#
# @exitcode 0 If the instance name is set successfully or if INSTANCE_NAME is not provided.
# @exitcode 1 If there is an error setting the instance name in the configuration file.
set_instance_name() {
    if [ -n "${INSTANCE_NAME}" ]; then
        if grep -q "^${INSTANCE_NAME_KEY}=" "${COMMENG_CONF}" 2>/dev/null; then
            sed -i "s/^${INSTANCE_NAME_KEY}=.*/${INSTANCE_NAME_KEY}=${INSTANCE_NAME}/" "${COMMENG_CONF}"
        else
            mkdir -p "$(dirname "${COMMENG_CONF}")"
            echo "${INSTANCE_NAME_KEY}=${INSTANCE_NAME}" >> "${COMMENG_CONF}"
        fi
    fi
}

###############################################################################
# @description Retrieves the value of the ActiveConfigurationEnvironment variable from the Catchpoint configuration file.
# If the variable is not found, it returns an empty string.
#
# @noargs
#
# @stdout The value of the ActiveConfigurationEnvironment variable, or an empty string if not found.
get_env() {
    env_key="ActiveConfigurationEnvironment"
    if grep -q "^${env_key}=" "${COMMENG_CONF}" 2>/dev/null; then
        # Get the value of the environment variable from the configuration file, removing any surrounding quotes and convert to lowercase.
        env_value=$(grep "^${env_key}=" "${COMMENG_CONF}" | cut -d '=' -f 2 | tr -d '"' | tr '[:upper:]' '[:lower:]')
        echo "${env_value}"
    else
        echo ""
    fi
}

###############################################################################
# @description Determines the operating system and version of the current machine.
# Note: this function returns the strings based on what the production OS values are.
#
# @noargs
#
# @stdout The operating system and version (e.g., "Ubuntu 20", "Red Hat 8", "Amazon Linux", "Rocky Linux", or "Catchpoint Appliance").
get_os() {
    release_file="/etc/os-release"
    is_ubuntu=$(grep -qi "ubuntu" "${release_file}" && echo true || echo false)
    is_oracle_linux=$(grep -qi "oracle" "${release_file}" && echo true || echo false)
    is_redhat=$(grep -qi "red hat" "${release_file}" && echo true || echo false)
    is_amazon=$(grep -qi "amazon" "${release_file}" && echo true || echo false)
    is_rocky=$(grep -qi "rocky" "${release_file}" && echo true || echo false)
    version_major=$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); split($2,a,"."); print a[1]; exit}' "${release_file}" 2>/dev/null || echo "")

    if [ "${is_ubuntu}" = true ]; then
        echo "Ubuntu ${version_major}"
    elif [ "${is_oracle_linux}" = true ]; then
        # Prod only recognizes one version of Oracle Linux, so we will return "Oracle Linux 8" regardless of the actual version.
        echo "Oracle Linux 8"
    elif [ "${is_amazon}" = true ]; then
        echo "Amazon Linux"
    elif [ "${is_rocky}" = true ]; then
        echo "Rocky Linux"
    elif [ "${is_redhat}" = true ]; then
        # if major is 7 or 8, return Red Hat {version}.
        if [ "${version_major}" = "7" ] || [ "${version_major}" = "8" ]; then
            echo "Red Hat ${version_major}"
        else
        # if major is 9 (or greater), return RHEL9 to match what's in prod OS values.
            echo "RHEL9"
        fi
    else
        # If we can't determine the OS, we will return "Catchpoint Appliance" because there's no "unknown" catch-all.
        echo "Catchpoint Appliance"
    fi
}

###############################################################################
# @description Activates the Catchpoint instance using the provided API token and node name.
# If either the API token or node name is missing, it prints an informational message and skips activation.
#
# @noargs
#
# @exitcode 0 If activation is successful or skipped due to missing credentials.
# @exitcode 1 If activation fails due to an error.
activate_instance() {
    if [ -z "${API_TOKEN}" ] || [ -z "${NODE_NAME}" ]; then
        print_info "API token or node name not provided. Skipping activation."
        print_info "To activate the instance later, use the following command:"
        print_info "catchpoint activate --api-key <API_TOKEN> --node <NODE_NAME> --os <OS>"
        return 0
    fi

    if ! command -v catchpoint >/dev/null 2>&1; then
        print_error "Catchpoint CLI is not installed. Cannot activate the instance."
        return 1
    fi

    os=$(get_os)
    print_info "Detected operating system: ${os}, attempting to activate the instance under node name '${NODE_NAME}' with the provided API token."

    if [ -z "${os}" ]; then
        print_error "Failed to determine the operating system. Cannot activate the instance."
        return 1
    fi

    # If INSTANCE_NAME is provided, use it. Otherwise, try to get the system hostname.
    # Else, the activation script will use the default hostname of the system.
    if [ -n "${INSTANCE_NAME}" ]; then
        print_info "Using provided instance name: ${INSTANCE_NAME}"
        extra_switches="--hostname ${INSTANCE_NAME}"
    elif command -v hostname >/dev/null 2>&1; then
        INSTANCE_NAME=$(hostname | cut -d '.' -f 1)
        print_info "No instance name provided. Using system hostname: ${INSTANCE_NAME}"
        extra_switches="--hostname ${INSTANCE_NAME}"
    fi

    if [ -n "${MACHINE_ID}" ]; then
        print_info "Using provided machine ID: ${MACHINE_ID}"
        extra_switches="${extra_switches} --machine-id ${MACHINE_ID}"
    fi

    env=$(get_env)
    if [ "${env}" = "stage" ] || [ "${env}" = "qa" ]; then
        extra_switches="${extra_switches} --${env}"
    fi

    print_info "Activating the instance with the following command:"
    print_info "catchpoint activate --api-key <REDACTED> --node ${NODE_NAME} --os ${os} ${extra_switches} --yes"
    # shellcheck disable=SC2086 # We need globbing here for the extra switches.
    if ! catchpoint activate --api-key "${API_TOKEN}" --node "${NODE_NAME}" --os "${os}" ${extra_switches} --yes; then
        print_error "Failed to activate the instance with the provided API token and node name."
        return 1
    fi

    print_info "Instance activated successfully under node name '${NODE_NAME}'."
}

###############################################################################
# MAIN
###############################################################################
if command -v catchpoint >/dev/null 2>&1; then
    print_info "The SyntheticAgent is already installed. Skipping installation."
    print_info "If you want to reinstall, please uninstall the existing SyntheticAgent first."
    print_info "If you want to upgrade, run 'catchpoint upgrade' instead of this script."
    exit 0
fi

if ! parse_args "$@"; then
    exit 1
fi

if ! confirm_is_activateable; then
    exit 1
fi

if ! confirm_prerequisites; then
    exit 1
fi

if ! install_repo; then
    exit 1
fi

if ! ${CACHE_UPDATE_COMMAND}; then
    print_error "Failed to update package manager cache."
    exit 1
fi

if ! set_machine_id; then
    print_error "Failed to set machine ID in configuration."
    exit 1
fi

if ! set_instance_name; then
    print_error "Failed to set instance name in configuration."
    exit 1
fi

#shellcheck disable=SC2086# We need globbing here for EXCLUDE_SWITCHES and PACKAGES_TO_INSTALL.
if ! ${INSTALL_PACKAGES_COMMAND} ${EXCLUDE_SWITCHES} ${PACKAGES_TO_INSTALL}; then
    print_error "Failed to install packages: ${PACKAGES_TO_INSTALL}"
    exit 1
fi

print_info "Catchpoint installation completed successfully."
print_info "Installed packages: ${PACKAGES_TO_INSTALL}"

if ! activate_instance; then
    exit 1
fi
