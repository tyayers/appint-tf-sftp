# gcp_poc-application-integration
Repository to hold all issues and content generated during the PoC of Google Application Integration.

## Prerequisites
- Install Terraform
- Install [Google Cloud SDK](https://cloud.google.com/sdk/docs/install)
- Install the [Application Integration CLI](https://github.com/GoogleCloudPlatform/application-integration-management-toolkit)
- Install the [Apigee CLI](https://github.com/apigee/apigeecli)

## Provisioning
```sh
# Set variables
PROJECT_ID=YOUR_PROJECT_ID
REGION=YOUR_REGION
ZONE=YOUR_ZONE
BUCKET=NEW_BUCKET_NAME # this must be a unique bucket name with lower case letters, numbers & dashes

# Application Integration
cd tf/aip
terraform init
terraform apply -var "project_id=$PROJECT_ID" -var "region=$REGION" -var "bucket=$BUCKET"

# SFTP Server
cd tf/sftpserver
terraform init
terraform apply -var "project_id=$PROJECT_ID" -var "region=$REGION" -var "zone=$ZONE"

# WIP Apigee
# cd tf/apigee
# terraform init
# terraform apply -var "project_id=$PROJECT_ID" -var "region=$REGION" -var "zone=$ZONE"

# Deploy integration flows
./1_deploy.sh
```