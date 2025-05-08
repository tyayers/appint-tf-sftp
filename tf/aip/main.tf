variable "project_id" {
  description = "Project id."
  type        = string
}

variable "region" {
  description = "GCP region."
  type        = string
}

variable "bucket" {
  description = "Storage bucket name."
  type        = string
}

module "project" {
  source          = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/project?ref=v15.0.0"
  name            = var.project_id
  project_create  = false
  services = [
    "apigee.googleapis.com",
    "integrations.googleapis.com",
    "connectors.googleapis.com",
    "secretmanager.googleapis.com",
    "firestore.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "servicenetworking.googleapis.com"
  ]
  policy_boolean = {
    "constraints/compute.requireOsLogin" = false
    "constraints/compute.requireShieldedVm" = false
  }
  policy_list = {
    "constraints/compute.vmExternalIpAccess" = {
        inherit_from_parent: false
        status: true
        suggested_value: null
        values: [],
        allow: {
          all=true
        }
    }
  }
}

resource "google_storage_bucket" "int-bucket" {
 name          = var.bucket
 project       = module.project.project_id
 location      = "EU"
 storage_class = "STANDARD"

 uniform_bucket_level_access = true
}

resource "google_integrations_client" "integration_region" {
  project = module.project.project_id
  location = var.region
}

resource "google_service_account" "int-service" {
  project = module.project.project_id
  account_id = "int-service"
  display_name = "Integration Service Account"
}

resource "google_project_iam_member" "int-service-run-invoker" {
  project = module.project.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.int-service.email}"
}

resource "google_project_iam_member" "int-service-integration-invoker" {
  project = module.project.project_id
  role    = "roles/integrations.integrationInvoker"
  member  = "serviceAccount:${google_service_account.int-service.email}"
}

resource "google_project_iam_member" "int-service-storage-admin" {
  project = module.project.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.int-service.email}"
}

resource "google_project_iam_member" "int-service-secret-viewer" {
  project = module.project.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.int-service.email}"
}

resource "google_project_iam_member" "int-service-secret-accessor" {
  project = module.project.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.int-service.email}"
}

resource "google_secret_manager_secret" "sftp" {
  secret_id = "sftp"
  project = module.project.project_id

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "sftp" {
  secret = google_secret_manager_secret.sftp.id

  secret_data = "apigeeRocks%12"
}

# data "archive_file" "sftp-function-file" {
#   type        = "zip"
#   output_path = "../../src/sftp-function/function-source.zip"
#   source_dir  = "."
# }

# resource "google_storage_bucket_object" "sftp-object" {
#   name   = "function-source.zip"
#   bucket = google_storage_bucket.int-bucket.name
#   source = data.archive_file.sftp-function-file.output_path # Add path to the zipped function source code
# }

# resource "google_cloudfunctions2_function" "sftp-function" {
#   name        = "sftp-function"
#   location    = var.region
#   project     = module.project.project_id
#   description = "SFTP function"

#   build_config {
#     runtime     = "nodejs20"
#     entry_point = "sftp-zip-handler" # Set the entry point
#     source {
#       storage_source {
#         bucket = google_storage_bucket.int-bucket.name
#         object = google_storage_bucket_object.sftp-object.name
#       }
#     }
#   }

#   service_config {
#     max_instance_count = 1
#     available_memory   = "256M"
#     timeout_seconds    = 60
#   }
# }

# resource "google_integration_connectors_connection" "sftpconnection" {
#   name     = "sftpconnector"
#   location = var.region
#   connector_version = "projects/${var.project_id}/locations/global/providers/gcp/connectors/sftp/versions/1"
#   description = "tf created description"
#   config_variable {
#     key = "project_id"
#     string_value = "connectors-example"
#   }
#   config_variable {
#     key = "topic_id"
#     string_value = "test"
#   }
# }