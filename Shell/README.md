# get_agent.sh

This script installs the Catchpoint SyntheticAgent on a Linux system. It supports both Debian-based and Red Hat-based distributions.

## Overview

Displays help/usage information.

## Index

* [show_help](#show_help)
* [parse_args](#parse_args)
* [print_message](#print_message)
* [print_info](#print_info)
* [print_warning](#print_warning)
* [print_error](#print_error)
* [is_root](#is_root)
* [confirm_is_activateable](#confirm_is_activateable)
* [confirm_prerequisites](#confirm_prerequisites)
* [install_repo](#install_repo)
* [set_machine_id](#set_machine_id)
* [set_instance_name](#set_instance_name)
* [get_env](#get_env)
* [get_os](#get_os)
* [activate_instance](#activate_instance)

### show_help

Displays help/usage information.

_Function has no arguments._

#### Exit codes

* **0**: for success (always).

### parse_args

Parse the incoming arguments.

#### Variables set

* **API_TOKEN** (string): API token provided via `--api-key` for post-install activation.
* **NODE_NAME** (string): Node name provided via `--node` for post-install activation.
* **MACHINE_ID** (string): Optional 12-character alphanumeric machine ID override provided via `--machine-id`.
* **INSTANCE_NAME** (string): Optional instance/hostname override provided via `--instance-name`.
* **INSTALL_PLAYWRIGHT / INSTALL_LEGACY** (boolean): Whether to install the optional Playwright and legacy monitor packages.

#### Exit codes

* **0**: for success.
* **1**: for failure.
* **2**: for invalid arguments.

### print_message

Prints a message with a timestamp to stderr.

#### Arguments

* **$1** (string): Any number of args will be printed to stderr.

#### Exit codes

* **0**: If printf succeeds.
* **1**: If printf fails (this should never occur).

### print_info

Prints a message with a GREEN 'INFO:' header to stderr.

#### Arguments

* **$1** (string): Any number of args will be printed to stderr.

#### Exit codes

* **0**: If printf succeeds.
* **1**: If printf fails (this should never occur).

### print_warning

Prints a message with a YELLOW 'WARNING:' header to stderr.

#### Arguments

* **$1** (string): Any number of args will be printed to stderr.

#### Exit codes

* **0**: If printf succeeds.
* **1**: If printf fails (this should never occur).

### print_error

Prints a message in RED with an 'ERROR:' header to stderr.

#### Arguments

* **$1** (string): Any number of args will be printed to stderr.

#### Exit codes

* **0**: If printf succeeds.
* **1**: If printf fails (this should never occur).

### is_root

Checks if the script is being run as root.

_Function has no arguments._

#### Exit codes

* **0**: If the script is being run as root.
* **1**: If the script is not being run as root.

### confirm_is_activateable

Checks if both API_TOKEN and NODE_NAME are provided for activation.
If only one is provided, it prints an error message and returns a non-zero exit code.
If neither is provided, it prints an informational message and sleeps for 5 seconds
to allow the user to cancel if they want to provide these values.

_Function has no arguments._

#### Exit codes

* **0**: If both API_TOKEN and NODE_NAME are provided or if neither is provided.
* **1**: If only one of API_TOKEN or NODE_NAME is provided.

### confirm_prerequisites

Checks for required prerequisites and determines the appropriate 
package manager and repository configuration based on the Linux distribution.

_Function has no arguments._

#### Variables set

* **#** (@sets): CACHE_UPDATE_COMMAND string The command to update the package manager's cache.
* **#** (@sets): INSTALL_PACKAGES_COMMAND string The command to install packages using the package manager.
* **#** (@sets): PACKAGES_TO_INSTALL string The name of the Catchpoint package to install.
* **#** (@sets): DISTRO_FLAVOR string A string representing the Linux distribution flavor (e.g., 'debian', 'rhel7', 'rhel8', 'rhel9').
* **#** (@sets): EXCLUDE_SWITCHES string A string containing any package manager switches to exclude certain packages from installation.

#### Exit codes

* **0**: If all prerequisites are met and the distribution is supported.
* **1**: If any prerequisites are missing or the distribution is unsupported.

### install_repo

Configures the appropriate package repository for the Linux distribution
and updates the package manager's cache.

_Function has no arguments._

#### Exit codes

* **0**: If the repository is configured and the cache is updated successfully.
* **1**: If there is an error configuring the repository or updating the cache.

### set_machine_id

Sets the machine ID in the Catchpoint configuration file if a 
MACHINE_ID variable is provided.

_Function has no arguments._

#### Exit codes

* **0**: If the machine ID is set successfully or if MACHINE_ID is not provided.
* **1**: If there is an error setting the machine ID in the configuration file.

### set_instance_name

Sets the instance name in the Catchpoint configuration file if 
an INSTANCE_NAME variable is provided.

_Function has no arguments._

#### Exit codes

* **0**: If the instance name is set successfully or if INSTANCE_NAME is not provided.
* **1**: If there is an error setting the instance name in the configuration file.

### get_env

Retrieves the value of the ActiveConfigurationEnvironment variable from the Catchpoint configuration file.
If the variable is not found, it returns an empty string.

_Function has no arguments._

#### Output on stdout

* The value of the ActiveConfigurationEnvironment variable, or an empty string if not found.

### get_os

Determines the operating system and version of the current machine.
Note: this function returns the strings based on what the production OS values are.

_Function has no arguments._

#### Output on stdout

* The operating system and version (e.g., "Ubuntu 20", "Red Hat 8", "Amazon Linux", "Rocky Linux", or "Catchpoint Appliance").

### activate_instance

Activates the Catchpoint instance using the provided API token and node name.
If either the API token or node name is missing, it prints an informational message and skips activation.

_Function has no arguments._

#### Exit codes

* **0**: If activation is successful or skipped due to missing credentials.
* **1**: If activation fails due to an error.

