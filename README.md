# cdp-images-toolkit

This repository contains a set of helper scripts to support the CDP Custom Image building process:
https://github.com/hortonworks/cloudbreak-images

## run-azure-rhel.sh
The `run-azure-rhel.sh` script is a wrapper for the CDP image building process (note: this script is currently tailored for Azure RHEL images). This script inputs an Image UUID (referencing an existing Cloudera Production CentOS image) as well as Cloudera subscription credentials, and will automatically obtain and set a list of required input parameters from the CDP Production Image Catalog, that can be used for a RHEL build.

To use this script, clone the following repository and then copy this script into the base directory:
https://github.com/hortonworks/cloudbreak-images

This script requires that the following Azure specific environment variables are set before running it:
```
export ARM_CLIENT_ID=3234bb21-e6d0-*****-****-**********
export ARM_CLIENT_SECRET=2c8bzH******************************
export ARM_SUBSCRIPTION_ID=a9d4456e-349f-*****-****-**********
export ARM_TENANT_ID=b60c9401-2154-*****-****-**********
export ARM_GROUP_NAME=resourcegroupname
export ARM_STORAGE_ACCOUNT=storageaccountname
export ARM_BUILD_REGION=southeastasia
export AZURE_BUILD_STORAGE_ACCOUNT='"Southeast Asia:storageaccountname"'
```
To run the script: 

```
./run-azure-rhel.sh [-h] [-v] -i image_uuid -u paywall_username -p paywall_password

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --image-uuid      Image uuid (from the CDP Image Catalog)
-u, --username     Paywall username for cloudera
-p, --password     Paywall password for cloudera
-f, --freeipa-image	Optional flag to indicate a freeipa image is required (default is CDP Runtime Image)
```
The Image UUID property defined here is a reference to an existing Cloudera Production image. This Image UUID can be obtained either directly from the CDP Image Catalog JSON or via the CDP Management Console:
https://cloudbreak-imagecatalog.s3.amazonaws.com/v3-prod-cb-image-catalog.json

## create-image-catalog.sh
This `create-image-catalog.sh` script can be used to generate a CDP Image Catalog (JSON file definition) after running a custom image build.
To use this script, copy this script into the base directory of the image build repo and run it after completing an image build:
https://github.com/hortonworks/cloudbreak-images

The script relies on two files that are output from the cloudbreak-images process:
 * json properties output
 * scripts/images_in_region

```
./create-image-catalog.sh [-h] [-v]
Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
```

## get-image-properties.sh
The `get-image-properties.sh` script is a standalone helper script that can be used to display the required input parameters for the image building process. Unlike the `run-azure-rhel.sh` script, `get-image-properties.sh` will only display the required input parameters but will not directly trigger an image build. This is intended to be a standalone helper script for scenarios that are triggering image builds directly via the make command outlined in:
https://github.com/hortonworks/cloudbreak-images

```
./get-image-properties.sh [-h] [-v] -i image_uuid -u paywall_username -p paywall_password

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --image-uuid      Image uuid (from the CDP Image Catalog)
-u, --username     Paywall username for cloudera
-p, --password     Paywall password for cloudera
-f, --freeipa-image Optional flag to indicate a freeipa image is required (default is CDP Runtime Image)
```