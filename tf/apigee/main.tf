variable "project_id" {
  description = "Project id (also used for the Apigee Organization)."
  type        = string
}

variable "region" {
  description = "GCP region for the Apigee runtime & analytics data (see https://cloud.google.com/apigee/docs/api-platform/get-started/install-cli)."
  type        = string
}

variable "apigee_envgroups" {
  description = "Apigee Environment Groups."
  type = map(object({
    hostnames = list(string)
  }))
  default = null
}

variable "apigee_instances" {
  description = "Apigee Instances (only one instance for EVAL orgs)."
  type = map(object({
    region       = string
    ip_range     = string
    environments = list(string)
  }))
  default = null
}

variable "apigee_environments" {
  description = "Apigee Environments."
  type = map(object({
    display_name = optional(string)
    description  = optional(string)
    node_config = optional(object({
      min_node_count = optional(number)
      max_node_count = optional(number)
    }))
    iam       = optional(map(list(string)))
    envgroups = list(string)
    type      = optional(string)
  }))
  default = null
}

variable "apigee_environment_name_list" {
  description = "List of the Apigee environment names."
  type = list(string)
  default = ["dev", "prod"]
}

variable "network" {
  description = "VPC name."
  type        = string
}

variable "peering_range" {
  description = "Peering CIDR range"
  type        = string
}

variable "support_range" {
  description = "Support CIDR range of length /28 (required by Apigee for troubleshooting purposes)."
  type        = string
}

variable "billing_id" {
  description = "Billing account id."
  type        = string
  default     = null
}

variable "apigee_billing_type" {
  description = "Apigee billing type - either PAYG, EVALUATION, or SUBSCRIPTION"
  type        = string
  default     = "EVALUATION"
}

variable "project_parent" {
  description = "Parent folder or organization in 'folders/folder_id' or 'organizations/org_id' format."
  type        = string
  default     = null
  validation {
    condition     = var.project_parent == null || can(regex("(organizations|folders)/[0-9]+", var.project_parent))
    error_message = "Parent must be of the form folders/folder_id or organizations/organization_id."
  }
}

variable "project_create" {
  description = "Create project. When set to false, uses a data source to reference existing project."
  type        = bool
  default     = true
}

variable "psc_ingress_network" {
  description = "PSC ingress VPC name."
  type        = string
}

variable "psc_ingress_subnets" {
  description = "Subnets for exposing Apigee services via PSC"
  type = list(object({
    name               = string
    ip_cidr_range      = string
    region             = string
    secondary_ip_range = map(string)
  }))
  default = []
}

locals {
  psc_subnet_region_name = { for subnet in var.psc_ingress_subnets :
    subnet.region => "${subnet.region}/${subnet.name}"
  }
}

module "project" {
  source          = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/project?ref=v15.0.0"
  name            = var.project_id
  parent          = var.project_parent
  billing_account = var.billing_id
  project_create  = var.project_create
  services = [
    "apigee.googleapis.com",
    "integrations.googleapis.com",
    "connectors.googleapis.com",
    "secretmanager.googleapis.com",
    "firestore.googleapis.com",
    "cloudkms.googleapis.com",
    "compute.googleapis.com",
    "servicenetworking.googleapis.com"
  ]
  policy_boolean = {
    "constraints/compute.requireOsLogin" = false
    "constraints/compute.requireShieldedVm" = false
  }
  policy_list = {
    "constraints/iam.allowedPolicyMemberDomains" = {
        inherit_from_parent: false
        status: true
        suggested_value: null
        values: [],
        allow: {
          all=true
        }
    },
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

module "vpc" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/net-vpc?ref=v28.0.0"
  project_id = module.project.project_id
  name       = var.network
  psa_config = {
    ranges = {
      apigee-range         = var.peering_range
      apigee-support-range = var.support_range
    }
  }
}

module "nip-development-hostname" {
  source             = "github.com/apigee/terraform-modules/modules/nip-development-hostname"
  project_id         = module.project.project_id
  address_name       = "apigee-external"
  subdomain_prefixes = [for name, _ in var.apigee_envgroups : name]
}

resource "google_integrations_client" "appintegration" {
  project = module.project.project_id
  location = var.region
}

/**
billing_type = PAYG, EVALUATION, SUBSCRIPTION
*/

module "apigee-x-core" {
  source              = "github.com/apigee/terraform-modules/modules/apigee-x-core"
  billing_type        = var.apigee_billing_type
  project_id          = module.project.project_id
  ax_region           = var.region
  apigee_environments = var.apigee_environments
  apigee_envgroups = {
    for name, env_group in var.apigee_envgroups : name => {
      hostnames = concat(env_group.hostnames, ["${name}.${module.nip-development-hostname.hostname}"])
    }
  }
  apigee_instances = var.apigee_instances
  network          = module.vpc.network.id
}

module "psc-ingress-vpc" {
  source                  = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/net-vpc?ref=v28.0.0"
  project_id              = module.project.project_id
  name                    = var.psc_ingress_network
  auto_create_subnetworks = false
  subnets                 = var.psc_ingress_subnets
}

resource "google_compute_region_network_endpoint_group" "psc_neg" {
  project               = var.project_id
  for_each              = var.apigee_instances
  name                  = "psc-neg-${each.value.region}"
  region                = each.value.region
  network               = module.psc-ingress-vpc.network.id
  subnetwork            = module.psc-ingress-vpc.subnet_self_links[local.psc_subnet_region_name[each.value.region]]
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = module.apigee-x-core.instance_service_attachments[each.value.region]
  lifecycle {
    create_before_destroy = true
  }
}

module "nb-psc-l7xlb" {
  source          = "github.com/apigee/terraform-modules/modules/nb-psc-l7xlb"
  project_id      = module.project.project_id
  name            = "apigee-xlb-psc"
  ssl_certificate = [module.nip-development-hostname.ssl_certificate]
  external_ip     = module.nip-development-hostname.ip_address
  psc_negs        = [for _, psc_neg in google_compute_region_network_endpoint_group.psc_neg : psc_neg.id]
}

module "apigee_addons" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/apigee"
  project_id = module.project.project_id
  addons_config = {
    monetization = true
    api_security = true
    advanced_api_ops = true
  }
  depends_on = [ module.apigee-x-core ]
}
