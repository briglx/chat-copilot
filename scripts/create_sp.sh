#!/usr/bin/env bash
######################################################
# Create a system identity to authenticate using
# Sets CLIENT_ID to .env
# Globals:
#   TENANT_ID
#   SUBSCRIPTION_ID
#   CLIENT_NAME
#   BASH_ENV (Optional) file path to environment variables.
# Params
#    -h, --help             Show this message and get help for a command.
######################################################

# Stop on errors
set -e

show_help() {
    echo "$0 : Create a cloud system identity." >&2
    echo "Usage: create_sp.sh [OPTIONS]" >&2
    echo "Sets CLIENT_ID in .env" >&2
    echo "Globals"
    echo "   CLIENT_NAME"
    echo "   TENANT_ID"
    echo "   SUBSCRIPTION_ID"
    echo "   BASH_ENV (Optional)"
    echo
    echo "Arguments"
    echo "   -h, --help             Show this message and get help for a command."
    echo
}

validate_parameters(){

    # Check SUBSCRIPTION_ID
    if [ -z "$SUBSCRIPTION_ID" ]
    then
        echo "SUBSCRIPTION_ID is required" >&2
        show_help
        exit 1
    fi

    # Check TENANT_ID
    if [ -z "$TENANT_ID" ]
    then
        echo "TENANT_ID is required" >&2
        show_help
        exit 1
    fi

    # Check CLIENT_NAME
    if [ -z "$CLIENT_NAME" ]
    then
        echo "CLIENT_NAME is required" >&2
        show_help
        exit 1
    fi

    # # Check GITHUB_ORG
    # if [ -z "$GITHUB_ORG" ]
    # then
    #     echo "GITHUB_ORG is required" >&2
    #     show_help
    #     exit 1
    # fi

    # Check GITHUB_REPO
    # if [ -z "$GITHUB_REPO" ]
    # then
    #     echo "GITHUB_REPO is required" >&2
    #     show_help
    #     exit 1
    # fi

}

create_sp(){
    local client_name="$1"
    local subscription="$2"

    # Constants
    # ms_graph_api_id="00000003-0000-0000-c000-000000000000"
    # ms_graph_user_invite_all_permission="09850681-111b-4a89-9bed-3f2cae46d706"
    # ms_graph_user_read_write_all_permission="741f803b-c850-494e-b5df-cde7c675a1ca"
    # ms_graph_directory_read_write_all_permission="19dbc75e-c2e2-444c-a770-ec69d8559fc7"

    # App Names
    app_name="${client_name}"

    # Create an Azure Active Directory application.
    app_list_response=$(az ad app list --display-name "$app_name")
    if [[ $app_list_response == '[]' ]]; then
        response=$(az ad app create --display-name "$app_name")
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo "Failed to create ad app" >&2
            exit 1
        fi

        app_id=$(jq --raw-output .id <(echo "$response"))
        app_client_id=$(jq --raw-output .appId <(echo "$response"))

    else
        # Azure Active Directory application already exists.
        app_id=$(jq --raw-output .[0].id <(echo "$app_list_response"))
        app_client_id=$(jq --raw-output .[0].appId <(echo "$app_list_response"))
    fi

    # Create a service principal for the Azure Active Directory application.
    response=$(az ad sp list --all --display-name "$app_name")
    if [[ $response == '[]' ]]; then
        response=$(az ad sp create --id "$app_id")
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo "Failed to create ad service principal" >&2
            exit 1
        fi

        app_sp_id=$(jq --raw-output .id <(echo "$response"))

    else
        app_sp_id=$(jq --raw-output .[0].id <(echo "$response"))
    fi

    # Assign contributor role to the app service principal
    response=$(az role assignment list --assignee "$app_sp_id" --role contributor)
    if [[ $response == '[]' ]]; then
        # response=$(az role assignment create --role contributor --scope "/subscriptions/$subscription" --assignee "$app_sp_id" )
        response=$(az role assignment create --role contributor --scope "/subscriptions/$subscription" --assignee-object-id "$app_sp_id" --assignee-principal-type ServicePrincipal --subscription "$subscription" )
        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo "Failed to assign contributor role to service principal" >&2
            exit 1
        fi
    fi

    # # Assign Microsoft Graph api permissions to application
    # response=$(jq --raw-output .[0].requiredResourceAccess <(echo "$app_list_response"))
    # # response=$(az ad app permission list --id "$app_client_id" )
    # if [[ $response == '[]' ]]; then
    #     response=$(az ad app permission add --id "$app_client_id" --api "$ms_graph_api_id" --api-permissions "${ms_graph_user_invite_all_permission}=Role ${ms_graph_user_read_write_all_permission}=Role ${ms_graph_directory_read_write_all_permission}=Role")
    #     if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    #         echo "Failed to assign Microsoft Graph api permissions to application" >&2
    #         exit 1
    #     fi
    # fi

    # Grant Microsoft Graph api permissions to application
    # response=$(az ad app permission list-grants --id "$app_client_id")
    # if [[ $response == '[]' ]]; then
    #     response=$(az ad app permission admin-consent --id "$app_client_id")
    #     # response=$(az ad app permission grant --id "$app_client_id" --api "$ms_graph_api_id")
    #     if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    #         echo "Failed to grant Microsoft Graph api permissions to application" >&2
    #         exit 1
    #     fi
    # fi

    # Add OIDC federated credentials for the application.
    # response=$(az ad app federated-credential list --id "$app_id")
    # if [[ $response == '[]' ]]; then
    #     json_sub="repo:$github_org/$github_repo"
    #     json_sub="${json_sub}:ref:refs/heads/main"
    #     json_desc="$client_name GitHub Service"

    #     json_body="{\"name\":\"$federated_secret_name\","
    #     json_body=$json_body'"issuer":"https://token.actions.githubusercontent.com",'
    #     json_body=$json_body"\"subject\":\"$json_sub\","
    #     json_body=$json_body"\"description\":\"$json_desc\",\"audiences\":[\"api://AzureADTokenExchange\"]}"

    #     response=$(az ad app federated-credential create --id "$app_id" --parameters "$json_body")
    #     if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    #         echo "Failed to create a federated identity credential" >&2
    #         exit 1
    #     fi
    # fi

    echo "$app_client_id"

}

# Globals
PROJ_ROOT_PATH=$(cd "$(dirname "$0")"/..; pwd)
ENV_FILE="${PROJ_ROOT_PATH}/.env"
echo "Project root: $PROJ_ROOT_PATH"
SCRIPT_DIRECTORY="${PROJ_ROOT_PATH}/script"

# shellcheck source=./common.sh
# source "${SCRIPT_DIRECTORY}/common.sh"

# Argument/Options
LONGOPTS=help
OPTIONS=h

# Variables
ISO_DATE_UTC=$(date -u +'%Y-%m-%dT%H:%M:%SZ')

# Load .env
# load_env "$ENV_FILE"

# Parse arguments
TEMP=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$TEMP"
unset TEMP
while true; do
    case "$1" in
        -h|--help)
            show_help
            exit
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unknown parameters."
            show_help
            exit 1
            ;;
    esac
done

validate_parameters "$@"

echo "Creating sp"
app_client_id=$(create_sp "$CLIENT_NAME" "$SUBSCRIPTION_ID")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo "Failed to create sp" >&2
    exit 1
fi

# Save variables to .env
echo "Save Azure variables to ${ENV_FILE}"
{
    echo ""
    echo "# Script create_sp output variables."
    echo "# Generated on ${ISO_DATE_UTC} for subscription ${SUBSCRIPTION_ID}"
    echo "CLIENT_ID=$app_client_id"
}>> "$ENV_FILE"
