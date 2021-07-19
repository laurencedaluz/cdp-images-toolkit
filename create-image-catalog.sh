#!/usr/bin/env bash

set -Eeuo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v]

This is a helper script used to generate a CDP Image Catalog (JSON file definition) after running a custom image build.
To use this script, copy this script into the base directory of the image build repo and run it after completing an image build:
https://github.com/hortonworks/cloudbreak-images.

The script relies on two output files from the cloudbreak-images process:
 * json properties output
 * scripts/images_in_region

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
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
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

setup_colors
parse_params "$@"

## START SCRIPT ##

# Get latest build output properties from generated JSON file
#id_name=$(ls *_manifest.json | grep -q -E '_[0-9]*_manifest.json' && ls -t *_manifest.json | grep ${image_type} | head -n1 | sed 's/_[0-9]*_manifest.json//' || ls *_manifest.json | sed 's/_manifest.json//' | sort)
id_name=$(ls *_manifest.json | grep -q -E '_[0-9]*_manifest.json' && ls -t *_manifest.json | head -n1 | sed 's/_[0-9]*_manifest.json//' || ls *_manifest.json | sed 's/_manifest.json//' | sort)
build_output_file=$(ls | grep $id_name | grep -v '_manifest')
build_json=$(cat $build_output_file | jq)

# Remove paywall credentials if they exist
search_filter=$(jq -r '."cdh_baseurl"' <<< $build_json | sed "s,https://\(.*\)archive.cloudera.com.*,\1,g")
build_json=$(echo $build_json | sed "s,$search_filter,,g")

# Get list of image paths and regions (& convert to JSON format)
images_in_regions=$(cat ./scripts/images_in_regions | cut -d'=' -f2-3 | jq -R -s '[split("\n")[:-1][] | split("=") | {(.[0]): .[1]}]  | add')

v_created=$(jq -r '."created_at"' <<< $build_json)
v_date=$(jq -r '."created"' <<< $build_json | cut -d' ' -f1)
v_description="CDP Custom Image" 
v_images=${images_in_regions}
v_os=$(jq -r '."os"' <<< $build_json)
v_os_type=$(jq -r '."os_type"' <<< $build_json)
v_uuid=$(jq -r '."uuid"' <<< $build_json)

v_package_versions=$(jq -r '."package_versions"' <<< $build_json)

v_cdh_baseurl=$(jq -r '."cdh_baseurl"' <<< $build_json)
v_cdh_repoid=$(jq -r '."cdh_repoid"' <<< $build_json)
v_cdh_repository_version=$(jq -r '."cdh_repository_version"' <<< $build_json)
v_cdh_version=$(jq -r '."cdh_version"' <<< $build_json)
v_stack_build_number=$(jq -r '."stack_build_number"' <<< $build_json)

v_cm_baseurl=$(jq -r '."cm_baseurl"' <<< $build_json)
v_cm_build_number=$(jq -r '."cm_build_number"' <<< $build_json)

v_pre_warm_parcels=$(jq -r '."pre_warm_parcels"' <<< $build_json)
v_pre_warm_csd=$(jq -r '."pre_warm_csd"' <<< $build_json)


## Runtime Image Properties
json_image_object=$(cat <<EOF
[
  {
    "created": "${v_created}",
    "date": "${v_date}",
    "description": "${v_description}",
    "images": {
      "azure": ${v_images}
    },
    "os": "${v_os}",
    "os_type": "${v_os_type}",
    "uuid": "${v_uuid}",
    "package-versions": ${v_package_versions},
    "stack-details": {
      "repo": {
        "stack": {
          "${v_os_type}": "${v_cdh_baseurl}", 
          "repoid": "${v_cdh_repoid}", 
          "repository-version": "${v_cdh_repository_version}" 
        },
        "util": null
      },
      "version": "${v_cdh_version}", 
      "build-number": "${v_stack_build_number}" 
    },
    "repo": {
      "${v_os_type}": "${v_cm_baseurl}" 
    },
    "version": "${v_cdh_version}", 
    "build-number": "${v_cm_build_number}",
    "pre_warm_parcels": ${v_pre_warm_parcels},
    "pre_warm_csd": ${v_pre_warm_csd}
  }
]
EOF
)

## UUID objects
v_uuid_images=$(cat <<EOF
["$v_uuid"]
EOF
)

## Final Image Catalog
json_runtime_template=$(cat <<EOF
{
  "images": {
    "cdh-images": ${json_image_object}
  },
  "versions": {
    "cloudbreak": [
      {
        "images": ${v_uuid_images},
        "defaults": ${v_uuid_images},
        "versions": [
          "2.43.0-b51"
        ]
      }
    ]
  }
}
EOF
)

file_name="image_catalog.json"
msg "${BLUE}Image Catalog Generated:${NOFORMAT}"
msg "${BLUE}-----------------${NOFORMAT}"
echo $json_runtime_template | jq
echo ""
msg "${BLUE}-----------------${NOFORMAT}"
msg "${BLUE}Writing to file:${NOFORMAT} $file_name"
echo ${json_runtime_template} | jq > $file_name

