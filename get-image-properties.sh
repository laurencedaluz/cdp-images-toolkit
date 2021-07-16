#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] -i image_uuid -u paywall_username -p paywall_password

This is a helper script that gathers a list of properties required to bake a custom RHEL image suitable for CDP. The output of this script is a set of environment variables that can be used as input in the CDP custom image baking process:
https://github.com/hortonworks/cloudbreak-images

This script reads properties from the CDP Production Image Catalog:
https://cloudbreak-imagecatalog.s3.amazonaws.com/v3-prod-cb-image-catalog.json

Note: this script will only display the output variables in the console, but will not execute the commands to set the variables. 

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --image-uuid      Image uuid (from the CDP Image Catalog)
-u, --username     Paywall username for cloudera
-p, --password     Paywall password for cloudera
-f, --freeipa-image Optional flag to indicate a freeipa image is required (default is CDP Runtime Image)
EOF
  exit
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  uuid=''
  p_user=''
  p_pass=''
  freeipa=0

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x ;;
    --no-color) NO_COLOR=1 ;;
    -u | --username) # parameter for paywall username
      p_user="${2-}"
      shift
      ;;
    -p | --password) # parameter for paywall password
      p_pass="${2-}"
      shift
      ;;
    -i | --image-uuid) # parameter for image uuid
      uuid="${2-}"
      shift
      ;;
    -f | --freeipa-image) freeipa=1 ;; # optional parameter for image type (defaults to "runtime")
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  # check required params and arguments
  if [[ ${freeipa} -eq 1 ]]
  then
    msg "${BLUE}Freeipa flag is set, ignoring all input parameters${NOFORMAT}"
  else
    [[ -z "${uuid-}" ]] && die "Missing required parameter: --image-uuid"
    [[ -z "${p_user-}" ]] && die "Missing required parameter: --username"
    [[ -z "${p_pass-}" ]] && die "Missing required parameter: --password"
    
    msg "${BLUE}Script input parameters:${NOFORMAT}"
    msg "- image-uuid: ${uuid}"
    msg "- username: ${p_user}"
    msg "- password: ${p_pass}"
  fi

  msg "${BLUE}-----------------------${NOFORMAT}"
  return 0
}

setup_colors
parse_params "$@"

## START SCRIPT ##

if [[ ${freeipa} -eq 1 ]]
then
  ## FreeIPA Image ##

  echo "## FreeIPA Settings"
  echo "export CLOUD_PROVIDER=Azure"
  echo "export CUSTOM_IMAGE_TYPE=freeipa"
  echo "export IMAGE_BURNING_TYPE=freeipa"
  echo "export IMAGE_NAME=freeipa-cdh--$(date +%s)"

else
  ## CDP Runtime Image ##

  # Get image based on provided uuid from the CDP production image catalog
  image=$(curl --progress-bar https://cloudbreak-imagecatalog.s3.amazonaws.com/v3-prod-cb-image-catalog.json | jq --arg uuid "$uuid" '.images."cdh-images"[] | select(.uuid==$uuid)')

  # Add cloudera paywall credentials into all archive.cloudera.com URLs
  image=$(echo $image | sed "s,https://archive.cloudera.com,https://$p_user\:$p_pass\@archive.cloudera.com,g")

  msg "${BLUE}-----------------------${NOFORMAT}"
  msg "${BLUE}# Environment variables for make build-azure-redhat7${NOFORMAT}"

  ## Output required variables

  # General
  echo "## General settings"
  echo "export OS=redhat7  # hardcoded value"
  echo "export CUSTOM_IMAGE_TYPE=hortonworks"
  echo "export STACK_TYPE=CDH  # hardcoded value"
  echo "export PARCELS_ROOT=/opt/cloudera/parcels  # hardcoded value"
  echo "export IMAGE_BURNING_TYPE=prewarm"
  echo "export UUID=$(jq -r '."uuid"' <<< $image)"
  echo "export ENABLE_POSTPROCESSORS=true  # hardcoded value"

  # Stack Details 
  echo "## Stack Details"
  echo "export STACK_BASEURL=$(jq -r '."stack-details".repo.stack.redhat7' <<< $image)"
  echo "export STACK_REPOID=$(jq -r '."stack-details".repo.stack.repoid' <<< $image)"
  echo "export STACK_REPOSITORY_VERSION=$(jq -r '."stack-details".repo.stack."repository-version"' <<< $image)"
  echo "export STACK_VERSION=$(jq -r '."stack-details".version' <<< $image)"
  echo "export STACK_BUILD_NUMBER=$(jq -r '."stack-details"."build-number"' <<< $image)"

  # Get parcel name from stack repository
  echo "export PARCELS_NAME=$(curl -s $(jq -r '."stack-details".repo.stack.redhat7' <<< $image) | grep .parcel\" | cut -d'"' -f 2)"

  # Repo
  echo "export CLUSTERMANAGER_BASEURL=$(jq -r '."repo"."redhat7"' <<< $image)"
  echo "export CLUSTERMANAGER_GPGKEY=$(jq -r '."repo"."redhat7"' <<< $image)RPM-GPG-KEY-cloudera"

  # Package Details
  echo "## Package Details"
  echo "export CFM_BUILD_NUMBER=$(jq -r '."package-versions"."cfm"' <<< $image)"
  echo "export CFM_GBN=$(jq -r '."package-versions"."cfm_gbn"' <<< $image)"
  echo "export CLUSTERMANAGER_VERSION=$(jq -r '."package-versions"."cm"' <<< $image)"
  echo "export CM_BUILD_NUMBER=$(jq -r '."package-versions"."cm-build-number"' <<< $image)"
  echo "export COMPOSITE_GBN=$(jq -r '."package-versions"."composite_gbn"' <<< $image)"
  echo "export CSA_BUILD_NUMBER=$(jq -r '."package-versions"."csa"' <<< $image)"
  echo "export CSA_GBN=$(jq -r '."package-versions"."csa_gbn"' <<< $image)"
  echo "export PROFILER_BUILD_NUMBER=$(jq -r '."package-versions"."profiler"' <<< $image)"
  echo "export DSS_BUILD_NUMBER=$(jq -r '."package-versions"."profiler"' <<< $image)"
  echo "export PROFILER_GBN=$(jq -r '."package-versions"."profiler_gbn"' <<< $image)"
  echo "export SPARK3_BUILD_NUMBER=$(jq -r '."package-versions"."spark3"' <<< $image)"
  echo "export SPARK3_GBN=$(jq -r '."package-versions"."spark3_gbn"' <<< $image)"

  # Duplicates - not included
  # echo "export STACK_BUILD_NUMBER=$(jq -r '."package-versions"."cdh-build-number"' <<< $image)"
  # echo "export STACK_VERSION=$(jq -r '."package-versions"."stack"' <<< $image)"

  # Pre warm packages
  echo "## Pre warm packages"
  echo "export PRE_WARM_CSD='$(jq -c '."pre_warm_csd"' <<< $image | sed 's/"/\\\"/g')'"
  echo "export PRE_WARM_PARCELS='$(jq -c '."pre_warm_parcels"' <<< $image | sed 's/"/\\\"/g')'"

  echo ""
  msg "${BLUE}## Azure parameters to be updated by user:${NOFORMAT}"
  echo "export CLOUD_PROVIDER=Azure"
  echo "export ARM_BUILD_REGION="
  echo "export AZURE_BUILD_STORAGE_ACCOUNT="
  echo "export ARM_CLIENT_ID="
  echo "export ARM_CLIENT_SECRET="
  echo "export ARM_SUBSCRIPTION_ID="
  echo "export ARM_TENANT_ID="
  echo "export ARM_GROUP_NAME="
  echo "export ARM_STORAGE_ACCOUNT="
  echo ""

  msg "${BLUE}OUTPUT COMPLETE: note that the variables here have been displayed in the console only, and have not been set.${NOFORMAT}"

fi
