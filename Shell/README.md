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
* [get_machine_id](#get_machine_id)
* [activate_instance](#activate_instance)
* [activate_instance_with_cli](#activate_instance_with_cli)
* [activate_instance_with_code](#activate_instance_with_code)
* [url_encode](#url_encode)
* [curl_request](#curl_request)

### show_help

Displays help/usage information.

_Function has no arguments._

#### Exit codes

* **0**: for success (always).

### parse_args

Parse the incoming arguments.

#### Arguments

* **$1** (string): All arguments to parse.

#### Variables set

* **API_TOKEN** (string): API token for activation (from --api-key).
* **NODE_NAME** (string): Node name for activation (from --node).
* **ACTIVATION_CODE** (string): Activation code for activation (from --code).
* **MACHINE_ID** (string): 12-character machine ID override (from --machine-id).
* **INSTANCE_NAME** (string): Instance name/hostname override (from --instance-name).
* **INSTALL_PLAYWRIGHT/INSTALL_LEGACY** (bool): Whether to install optional Playwright and legacy monitor packages.
* **SKIP_INSTALL** (bool): Whether to skip the installation of the Catchpoint SyntheticAgent.

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

Checks if both API_TOKEN and NODE_NAME or the ACTIVATION_CODE are
provided.
If only one of API_TOKEN or NODE_NAME is provided, it prints an error message
and returns a non-zero exit code.
If ACTIVATION_CODE is provided, it will be used for activation instead of API_TOKEN and NODE_NAME.
If none are provided, it prints an informational message and sleeps for 5 seconds
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

### get_machine_id

Retrieves the machine ID using the Catchpoint CLI. If the Catchpoint 
CLI is not installed, it prints an error message and returns a non-zero exit code.

_Function has no arguments._

#### Exit codes

* **0**: If the machine ID is retrieved successfully.
* **1**: If the Catchpoint CLI is not installed or if there is an error retrieving the machine ID.

#### Output on stdout

* The machine ID if the Catchpoint CLI is installed and the command succeeds.

### activate_instance

Activates the Catchpoint instance.
if ACTIVATION_CODE is specified, the activation uses a direct curl call to the endpoint.
Otherwise, if API_TOKEN and NODE_NAME are provided, the activation uses the 
Catchpoint CLI with the provided API token and node name.
If either the API token or node name is missing, it prints an informational message and skips activation.

_Function has no arguments._

#### Exit codes

* **0**: If activation is successful or skipped due to missing credentials.
* **1**: If activation fails due to an error.

### activate_instance_with_cli

Activates the Catchpoint instance using the Catchpoint CLI with 
the provided API token and node name.

_Function has no arguments._

#### Exit codes

* **0**: If activation is successful.
* **1**: If activation fails due to an error.

### activate_instance_with_code

Activates the Catchpoint instance using the provided ACTIVATION_CODE 
by making a direct API call to the activation endpoint.

_Function has no arguments._

#### Exit codes

* **0**: If activation is successful.
* **1**: If activation fails due to an error.

### url_encode

URL-encodes the provided string using Python's urllib library. 
It first checks for the availability of Python 3, and if not found, it falls 
back to a specific Catchpoint Python interpreter. The encoded string is printed to stdout.

#### Arguments

* **$1** (string): The string to be URL-encoded.

#### Output on stdout

* The URL-encoded string.

### curl_request

Makes a curl request to the specified URL with the given method 
and data. It handles HTTP response codes and errors, returning the JSON 
response if successful.

#### Arguments

* **$1** (string): The HTTP method (e.g., GET, POST).
* **$2** (string): The URL to which the request is made.
* **$3** (string): [Optional] The data to be sent with the request (for POST/PUT requests).

#### Exit codes

* **0**: If the request is successful and returns a valid JSON response.
* **1**: If there is an error with the request or response.

#### Output on stdout

* The JSON response from the server if the request is successful.

