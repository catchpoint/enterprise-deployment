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
SKIP_INSTALL="false"

# Token-based activation defaults
BASE_ACTIVATION_URI="https://io.catchpoint.com"
ACTIVATION_CODE=""

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

readonly STAGE_URI="https://iostage.catchpoint.com"
readonly QA_URI="https://ioqa.catchpoint.com"
readonly ACTIVATION_ENDPOINT="/api/v4/instances/activate"

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
    -c, --code           [Optional] Provide a one-time use activation code for activation. Cannot be used with --api-key or --node.
    -m, --machine-id     [Optional] Specify a machine ID to use for the installation.
    -i, --instance-name  [Optional] Specify an instance name to use for the installation.
    --skip-playwright    [Optional] Skip the installation of the Playwright package.
    --skip-legacy        [Optional] Skip the installation of the syntheticagent-legacy package.
    --skip-install       [Optional] Skip the installation of the Catchpoint SyntheticAgent (for reactivation purposes).
    -h, --help           Show this help message and exit.
    -v, --version        Show the script version and exit.
EOF
}

###############################################################################
# @description Parse the incoming arguments.
#
# @arg $1 string All arguments to parse.
#
# @set API_TOKEN string API token for activation (from --api-key).
# @set NODE_NAME string Node name for activation (from --node).
# @set ACTIVATION_CODE string Activation code for activation (from --code).
# @set MACHINE_ID string 12-character machine ID override (from --machine-id).
# @set INSTANCE_NAME string Instance name/hostname override (from --instance-name).
# @set INSTALL_PLAYWRIGHT/INSTALL_LEGACY bool Whether to install optional Playwright and legacy monitor packages.
# @set SKIP_INSTALL bool Whether to skip the installation of the Catchpoint SyntheticAgent.
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
            -c|--code)
                if [ -n "$2" ]; then
                    ACTIVATION_CODE="$2"
                    shift 2
                else
                    print_error "Missing argument for --code. Please provide a valid activation code."
                    return 1
                fi
                ;;
            --skip-playwright)
                INSTALL_PLAYWRIGHT=false
                shift
                ;;
            --skip-legacy)
                INSTALL_LEGACY=false
                shift
                ;;
            --skip-install)
                SKIP_INSTALL=true
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
# @description Checks if both API_TOKEN and NODE_NAME or the ACTIVATION_CODE are
# provided.
# If only one of API_TOKEN or NODE_NAME is provided, it prints an error message
# and returns a non-zero exit code.
# If ACTIVATION_CODE is provided, it will be used for activation instead of API_TOKEN and NODE_NAME.
# If none are provided, it prints an informational message and sleeps for 5 seconds
# to allow the user to cancel if they want to provide these values.
#
# @noargs
#
# @exitcode 0 If both API_TOKEN and NODE_NAME are provided or if neither is provided.
# @exitcode 1 If only one of API_TOKEN or NODE_NAME is provided.
confirm_is_activateable() {
    if [ -n "${API_TOKEN}" ] && [ -n "${NODE_NAME}" ]; then
        print_info "API token and node name provided. The agent will be activated after installation."
    elif [ -n "${ACTIVATION_CODE}" ]; then
        print_info "Activation token provided. The agent will be activated after installation."
    # We only reach this point if one of the values was provided but the other wasn't.
    elif [ -n "${API_TOKEN}" ] || [ -n "${NODE_NAME}" ]; then
        print_error "Both API token and node name must be provided for activation. Please provide both or neither."
        return 1
    else
        # Print info and then sleep for 5 seconds to give the user time to read the message and cancel if they want to.
        print_info "No API_token+node_name combo or ACTIVATION_CODE provided. The agent will not be activated after installation."
        print_info "To add an instance directly from the portal, provide the Activation Code using the --code option"
        print_info "To activate an instance under a specific node, provide both the API token and node name using the --api-key and --node options."
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
        print_error "When installing, this script must be run as root. Please run with sudo or as root user."
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
# @description Retrieves the machine ID using the Catchpoint CLI. If the Catchpoint 
# CLI is not installed, it prints an error message and returns a non-zero exit code.
#
# @noargs
#
# @stdout The machine ID if the Catchpoint CLI is installed and the command succeeds.
#
# @exitcode 0 If the machine ID is retrieved successfully.
# @exitcode 1 If the Catchpoint CLI is not installed or if there is an error retrieving the machine ID.
get_machine_id() {
    if ! command -v catchpoint >/dev/null 2>&1; then
        print_error "Catchpoint CLI is not installed. Cannot retrieve machine ID."
        return 1
    fi
    # Take the MID as the value after ': '.
    catchpoint machine-id | cut -d ':' -f 2 | tr -d ' '
}

###############################################################################
# @description Gets the system hostname. Attempts to use the 'hostname' command 
# first, and if it's not available, falls back to 'uname -n'.
#
# @noargs
#
# @stdout The system hostname if the 'hostname' command is available.
#
# @exitcode 0 If the hostname is retrieved successfully.
# @exitcode 1 If neither 'hostname' nor 'uname' command is available or if there is an error retrieving the hostname.
get_hostname() {
    if command -v hostname >/dev/null 2>&1; then
        hostname | cut -d '.' -f 1
    elif command -v uname >/dev/null 2>&1; then
        uname -n | cut -d '.' -f 1
    else
        print_error "The 'hostname' command is not available. Cannot retrieve the system hostname."
        return 1
    fi
}

###############################################################################
# @description Activates the Catchpoint instance.
# if ACTIVATION_CODE is specified, the activation uses a direct curl call to the endpoint.
# Otherwise, if API_TOKEN and NODE_NAME are provided, the activation uses the 
# Catchpoint CLI with the provided API token and node name.
# If either the API token or node name is missing, it prints an informational message and skips activation.
#
# @noargs
#
# @exitcode 0 If activation is successful or skipped due to missing credentials.
# @exitcode 1 If activation fails due to an error.
activate_instance() {
    if [ -n "${ACTIVATION_CODE}" ]; then
        activate_instance_with_code
        return $?
    elif [ -n "${API_TOKEN}" ] && [ -n "${NODE_NAME}" ]; then
        activate_instance_with_cli
        return $?
    else
        print_info "No activation credentials provided. Skipping activation."
        return 0
    fi
}

###############################################################################
# @description Activates the Catchpoint instance using the Catchpoint CLI with 
# the provided API token and node name.
#
# @noargs
#
# @exitcode 0 If activation is successful.
# @exitcode 1 If activation fails due to an error.
activate_instance_with_cli() {
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
    instance_name=${INSTANCE_NAME:-$(get_hostname)}
    extra_switches="--hostname ${instance_name}"

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
# @description Activates the Catchpoint instance using the provided ACTIVATION_CODE 
# by making a direct API call to the activation endpoint.
#
# @noargs
#
# @exitcode 0 If activation is successful.
# @exitcode 1 If activation fails due to an error.
activate_instance_with_code() {
    os=$(url_encode "$(get_os)")

    # The MID source-of-truth should be what the agent is using right now, since the single-use flow
    # doesn't require the user to provide it.
    if ! mid=$(url_encode "$(get_machine_id)"); then
        print_error "Failed to retrieve machine ID. Cannot activate the instance."
        return 1
    fi

    instance_name=${INSTANCE_NAME:-$(get_hostname)}

    payload=$(cat <<EOF
{
    "os": "${os}",
    "machineid": "${mid}",
    "hostname": "$(url_encode "${instance_name}")"
}
EOF
)
    env=$(get_env)
    if [ "${env}" = "stage" ]; then
        BASE_ACTIVATION_URI="${STAGE_URI}"
    elif [ "${env}" = "qa" ]; then
        BASE_ACTIVATION_URI="${QA_URI}"
    fi

    activation_url="${BASE_ACTIVATION_URI}${ACTIVATION_ENDPOINT}"

    print_info "Activating the instance using the provided activation code at ${activation_url}."
    if ! response=$(curl_request "POST" "${activation_url}" "${payload}"); then
        print_error "Failed to activate the instance using the activation code."
        if [ -n "${response}" ]; then
            print_error "Response: ${response}"
        fi
        return 1
    fi

    print_info "Instance activated successfully using the provided activation code."
}

###############################################################################
# @description URL-encodes the provided string using Python's urllib library. 
# It first checks for the availability of Python 3, and if not found, it falls 
# back to a specific Catchpoint Python interpreter. The encoded string is printed to stdout.
#
# @arg $1 string The string to be URL-encoded.
#
# @stdout The URL-encoded string.
url_encode() 
{
    data="${1}"
    # Use available python3 or fall back to catchpoint python
    if ! PYTHON=$(command -v python3); then
        PYTHON="/opt/catchpoint/bin/python"
    fi

    ${PYTHON} -c "try: import urllib.request as urllib
except: import urllib 
import sys
sys.stdout.write(urllib.quote(\"${data}\"))"
}

###############################################################################
# @description Makes a curl request to the specified URL with the given method 
# and data. It handles HTTP response codes and errors, returning the JSON 
# response if successful.
#
# @arg $1 string The HTTP method (e.g., GET, POST).
# @arg $2 string The URL to which the request is made.
# @arg $3 string [Optional] The data to be sent with the request (for POST/PUT requests).
#
# @stdout The JSON response from the server if the request is successful.
#
# @exitcode 0 If the request is successful and returns a valid JSON response.
# @exitcode 1 If there is an error with the request or response.
curl_request()
{
    method=$1
    url=$2
    if [ -z "${method}" ] || [ -z "${url}" ]; then
        print_error "curl_request: method and url are required parameters."
        return 1
    fi

    data="$3"

    accept_header="accept: application/json"
    auth_header="Authorization: Activation ${ACTIVATION_CODE}"
    content_header="Content-Type: application/json"

    # Append the http_code/response code to the end of the json response to provide better error handling experience
    if [ -n "${data}" ]; then
        response=$(curl -sw 'HTTP_STATUS:%{response_code}' -X "${method}" "${url}" -H "${accept_header}" -H "${auth_header}" -H "${content_header}" -d "${data}")
    else
        response=$(curl -sw 'HTTP_STATUS:%{http_code}' -X "${method}" "${url}" -H "${accept_header}" -H "${auth_header}")
    fi

    # HTTP_STATUS:### is appended to the request. Parse it out separately and evaluate it
    json_resp=$(echo "${response}" | sed -E 's/HTTP_STATUS\:[0-9]{3}$//')
    http_code=$(echo "${response}" | tr -d '\n' | sed -E 's/.*HTTP_STATUS:([0-9]{3})$/\1/')
    
    if [ "${http_code}" -eq 400 ]; then
        print_error "Cannot connect to the API - BAD_REQUEST. Check the payload for missing or improperly formatted values"
        if [ -n "${data}" ]; then
            print_error "Payload: ${data}"
        fi
        return 1
    elif [ "${http_code}" -eq 401 ]; then
        print_error "Cannot connect to the API - UNAUTHORIZED. (ensure that the activation code is valid)"
        return 1
    elif [ "${http_code}" -eq 409 ]; then
        print_error "Cannot connect to the API - CONFLICT. The activation code may have already been used."
        return 1
    elif [ "${http_code}" -eq 500 ]; then
        print_error "Cannot connect to the API - INTERNAL SERVER ERROR. Please try again later."
        return 1
    fi

    if [ -z "${json_resp}" ]; then
        print_error "Received no response to query"
        return 1
    fi

    # All payloads should have an errors array (hopefully empty), if we can't find it, something is wrong.
    if ! err_resp=$(echo "${json_resp}" | jq '[.errors[]]' 2>/dev/null); then
        print_error "Response was improperly formatted"
        return 1
    fi

    if [ "$(echo "${err_resp}" | jq 'length' 2>/dev/null)" != '0'  ]; then
        print_error "API call returned errors. Check parameters to ensure they will return appropriate results."
        if [ -n "${err_resp}" ]; then
            print_error "Details: ${err_resp}"
        fi
        return 1
    fi

    echo "${json_resp}"
}

###############################################################################
# MAIN
###############################################################################
if ! parse_args "$@"; then
    exit 1
fi

if [ "${SKIP_INSTALL}" != "true" ] && command -v catchpoint >/dev/null 2>&1; then
    print_info "The SyntheticAgent is already installed. Skipping installation."
    print_info "If you want to reinstall, please uninstall the existing SyntheticAgent first."
    print_info "If you want to upgrade, run 'catchpoint upgrade' instead of this script."
    exit 0
fi

if ! confirm_is_activateable; then
    exit 1
fi

if [ "${SKIP_INSTALL}" = "true" ]; then
    print_info "Skipping installation of the Catchpoint SyntheticAgent as per user request."
else
    print_info "Proceeding with the installation of the Catchpoint SyntheticAgent."

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
fi

if ! activate_instance; then
    exit 1
fi
