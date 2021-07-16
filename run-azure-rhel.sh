#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] -i image_uuid -u paywall_username -p paywall_password

This is a wrapper script that gathers a list of properties required to bake a custom RHEL image suitable for CDP, and then triggers an image build using the CDP custom image baking process.
To use this script, clone the following repository and then copy this script into the base directory:
https://github.com/hortonworks/cloudbreak-images

This script reads properties from the CDP Production Image Catalog:
https://cloudbreak-imagecatalog.s3.amazonaws.com/v3-prod-cb-image-catalog.json

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --image-uuid      Image uuid (from the CDP Image Catalog)
-u, --username     Paywall username for cloudera
-p, --password     Paywall password for cloudera
-f, --freeipa-image	Optional flag to indicate a freeipa image is required (default is CDP Runtime Image)
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

## Check that the required azure envs are set
msg "${BLUE}Checking that the required environemnt variables are set:${NOFORMAT}"

required_vars=(ARM_BUILD_REGION AZURE_BUILD_STORAGE_ACCOUNT ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID ARM_TENANT_ID ARM_GROUP_NAME ARM_STORAGE_ACCOUNT)
missing_vars=()
var=''
for var in "${required_vars[@]}"
do
  if [ -z ${!var+x} ]
  then
    missing_vars+=("$var")
  else
    msg "$var is set"
  fi
done
if [ ${#missing_vars[@]} -ne 0 ]
then
  die "${RED}ERROR: The following environment variables must be set:${NOFORMAT} ${missing_vars[*]}"
fi

msg "${BLUE}-----------------------${NOFORMAT}"
msg "Setting CLOUD_PROVIDER to Azure"
export CLOUD_PROVIDER=Azure

## Check we are in the right directory (by looking for the Makefile)
MAKEFILE=./Makefile
msg "${BLUE}-----------------------${NOFORMAT}"
msg "${BLUE}Checking the Makefile exists:${NOFORMAT}"
if [ -f "$MAKEFILE" ]; 
then
  msg "Makefile exists: $MAKEFILE"
else
  die "${RED}ERROR: Cannot find Makefile. Check that this script is running from the cloudbreak-images base folder.${NOFORMAT}"
fi


if [[ ${freeipa} -eq 1 ]]
then
  ## FreeIPA Image ##

  msg "${BLUE}## Setting FreeIPA environment variables:${NOFORMAT}"
  export CLOUD_PROVIDER=Azure
  export CUSTOM_IMAGE_TYPE=freeipa
  export IMAGE_BURNING_TYPE=freeipa
  export IMAGE_NAME=freeipa-cdh--$(date +%s)
  msg "Variable set: $CLOUD_PROVIDER"
  msg "Variable set: $CUSTOM_IMAGE_TYPE"
  msg "Variable set: $IMAGE_BURNING_TYPE"
  msg "Variable set: $IMAGE_NAME"

  msg "${BLUE}## Running freeipa image build${NOFORMAT}"
  make build-azure-redhat7

else
  ## CDP Runtime Image ##

  # Get image based on provided uuid from the CDP production image catalog
  image=$(curl --progress-bar https://cloudbreak-imagecatalog.s3.amazonaws.com/v3-prod-cb-image-catalog.json | jq --arg uuid "$uuid" '.images."cdh-images"[] | select(.uuid==$uuid)')

  # Add cloudera paywall credentials into all archive.cloudera.com URLs
  image=$(echo $image | sed "s,https://archive.cloudera.com,https://$p_user\:$p_pass\@archive.cloudera.com,g")

  msg "${BLUE}-----------------------${NOFORMAT}"
  msg "${BLUE}# Setting Runtime image environment variables:${NOFORMAT}"

  ## Output required variables

  # General settings
  msg "${BLUE}## General settings${NOFORMAT}"
  export OS=redhat7  # hardcoded value
  export CUSTOM_IMAGE_TYPE=hortonworks
  export STACK_TYPE=CDH  # hardcoded value
  export PARCELS_ROOT=/opt/cloudera/parcels  # hardcoded value
  export IMAGE_BURNING_TYPE=prewarm
  export UUID=$(jq -r '."uuid"' <<< $image)
  export ENABLE_POSTPROCESSORS=true  # hardcoded value

  msg "Variable set: OS=$OS  # hardcoded value"
  msg "Variable set: CUSTOM_IMAGE_TYPE=$CUSTOM_IMAGE_TYPE"
  msg "Variable set: STACK_TYPE=$STACK_TYPE"
  msg "Variable set: PARCELS_ROOT=$PARCELS_ROOT  # hardcoded value"
  msg "Variable set: IMAGE_BURNING_TYPE=$IMAGE_BURNING_TYPE"
  msg "Variable set: UUID=$UUID"
  msg "Variable set: ENABLE_POSTPROCESSORS=$ENABLE_POSTPROCESSORS  # hardcoded value"


  # Stack Details 
  msg "${BLUE}## Stack Details${NOFORMAT}"
  export STACK_BASEURL=$(jq -r '."stack-details".repo.stack.redhat7' <<< $image)
  export STACK_REPOID=$(jq -r '."stack-details".repo.stack.repoid' <<< $image)
  export STACK_REPOSITORY_VERSION=$(jq -r '."stack-details".repo.stack."repository-version"' <<< $image)
  export STACK_VERSION=$(jq -r '."stack-details".version' <<< $image)
  export STACK_BUILD_NUMBER=$(jq -r '."stack-details"."build-number"' <<< $image)

  msg "Variable set: STACK_BASEURL=$STACK_BASEURL"
  msg "Variable set: STACK_REPOID=$STACK_REPOID"
  msg "Variable set: STACK_REPOSITORY_VERSION=$STACK_REPOSITORY_VERSION"
  msg "Variable set: STACK_VERSION=$STACK_VERSION"
  msg "Variable set: STACK_BUILD_NUMBER=$STACK_BUILD_NUMBER"


  # Get parcel name from stack repository
  export PARCELS_NAME=$(curl -s $(jq -r '."stack-details".repo.stack.redhat7' <<< $image) | grep .parcel\" | cut -d'"' -f 2)
  msg "Variable set: PARCELS_NAME=$PARCELS_NAME"

  # Repo
  export CLUSTERMANAGER_BASEURL=$(jq -r '."repo"."redhat7"' <<< $image)
  export CLUSTERMANAGER_GPGKEY=$(jq -r '."repo"."redhat7"' <<< $image)RPM-GPG-KEY-cloudera

  msg "Variable set: CLUSTERMANAGER_BASEURL=$CLUSTERMANAGER_BASEURL"
  msg "Variable set: CLUSTERMANAGER_GPGKEY=$CLUSTERMANAGER_GPGKEY"
  

  # Package Details
  msg "${BLUE}## Package Details${NOFORMAT}"
  export CFM_BUILD_NUMBER=$(jq -r '."package-versions"."cfm"' <<< $image)
  export CFM_GBN=$(jq -r '."package-versions"."cfm_gbn"' <<< $image)
  export CLUSTERMANAGER_VERSION=$(jq -r '."package-versions"."cm"' <<< $image)
  export CM_BUILD_NUMBER=$(jq -r '."package-versions"."cm-build-number"' <<< $image)
  export COMPOSITE_GBN=$(jq -r '."package-versions"."composite_gbn"' <<< $image)
  export CSA_BUILD_NUMBER=$(jq -r '."package-versions"."csa"' <<< $image)
  export CSA_GBN=$(jq -r '."package-versions"."csa_gbn"' <<< $image)
  export PROFILER_BUILD_NUMBER=$(jq -r '."package-versions"."profiler"' <<< $image)
  export DSS_BUILD_NUMBER=$(jq -r '."package-versions"."profiler"' <<< $image)
  export PROFILER_GBN=$(jq -r '."package-versions"."profiler_gbn"' <<< $image)
  export SPARK3_BUILD_NUMBER=$(jq -r '."package-versions"."spark3"' <<< $image)
  export SPARK3_GBN=$(jq -r '."package-versions"."spark3_gbn"' <<< $image)


  msg "Variable set: CFM_BUILD_NUMBER=$CFM_BUILD_NUMBER"
  msg "Variable set: CFM_GBN=$CFM_GBN"
  msg "Variable set: CLUSTERMANAGER_VERSION=$CLUSTERMANAGER_VERSION"
  msg "Variable set: CM_BUILD_NUMBER=$CM_BUILD_NUMBER"
  msg "Variable set: COMPOSITE_GBN=$COMPOSITE_GBN"
  msg "Variable set: CSA_BUILD_NUMBER=$CSA_BUILD_NUMBER"
  msg "Variable set: CSA_GBN=$CSA_GBN"
  msg "Variable set: PROFILER_BUILD_NUMBER=$PROFILER_BUILD_NUMBER"
  msg "Variable set: DSS_BUILD_NUMBER=$DSS_BUILD_NUMBER"
  msg "Variable set: PROFILER_GBN=$PROFILER_GBN"
  msg "Variable set: SPARK3_BUILD_NUMBER=$SPARK3_BUILD_NUMBER"
  msg "Variable set: SPARK3_GBN=$SPARK3_GBN"

  # Duplicates - not included
  # echo "export STACK_BUILD_NUMBER=$(jq -r '."package-versions"."cdh-build-number"' <<< $image)"
  # echo "export STACK_VERSION=$(jq -r '."package-versions"."stack"' <<< $image)"

  # Pre warm packages
  msg "${BLUE}## Pre warm packages${NOFORMAT}"
  export PRE_WARM_CSD=$(jq -c '.pre_warm_csd' <<< $image | sed 's/"/\\\"/g')
  export PRE_WARM_PARCELS=$(jq -c '."pre_warm_parcels"' <<< $image | sed 's/"/\\\"/g')

  msg "Variable set: PRE_WARM_CSD=$PRE_WARM_CSD"
  msg "Variable set: PRE_WARM_PARCELS=$PRE_WARM_PARCELS"

  msg "${BLUE}## Running CDP Runtime image build${NOFORMAT}"
  make build-azure-redhat7

fi
