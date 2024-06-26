module "naming" {
  source  = "Azure/naming/azurerm"
  version = "0.3.0"
}

# This picks a random region from the list of regions.
resource "random_integer" "region_index" {
  max = length(local.azure_regions) - 1
  min = 0
}

# This is required for resource modules
resource "azurerm_resource_group" "this" {
  location = local.azure_regions[random_integer.region_index.result]
  name     = module.naming.resource_group.name_unique
  tags     = var.tags
}

# Create Azure Log Analytics workspace for Azure Virtual Desktop
module "avm_res_operationalinsights_workspace" {
  source              = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version             = "0.1.3"
  enable_telemetry    = var.enable_telemetry
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  name                = module.naming.log_analytics_workspace.name_unique
  tags                = local.tags
}

# Create Azure Virtual Desktop host pool
module "avm_res_desktopvirtualization_hostpool" {
  source                                             = "Azure/avm-res-desktopvirtualization-hostpool/azurerm"
  version                                            = "0.1.4"
  enable_telemetry                                   = var.enable_telemetry
  resource_group_name                                = azurerm_resource_group.this.name
  virtual_desktop_host_pool_type                     = var.virtual_desktop_host_pool_type
  virtual_desktop_host_pool_location                 = azurerm_resource_group.this.location
  virtual_desktop_host_pool_load_balancer_type       = var.virtual_desktop_host_pool_load_balancer_type
  virtual_desktop_host_pool_resource_group_name      = azurerm_resource_group.this.name
  virtual_desktop_host_pool_name                     = var.virtual_desktop_host_pool_name
  virtual_desktop_host_pool_custom_rdp_properties    = var.virtual_desktop_host_pool_custom_rdp_properties
  virtual_desktop_host_pool_maximum_sessions_allowed = var.virtual_desktop_host_pool_maximum_sessions_allowed
  virtual_desktop_host_pool_start_vm_on_connect      = var.virtual_desktop_host_pool_start_vm_on_connect
  tags                                               = var.virtual_desktop_host_pool_tags
  diagnostic_settings = {
    to_law = {
      name                  = "to-law"
      workspace_resource_id = module.avm_res_operationalinsights_workspace.resource.id
    }
  }
  virtual_desktop_host_pool_scheduled_agent_updates = {
    enabled = "true"
    schedule = tolist([{
      day_of_week = "Sunday"
      hour_of_day = 0
    }])
  }
}

# Registration information for the host pool.
resource "azurerm_virtual_desktop_host_pool_registration_info" "registrationinfo" {
  expiration_date = timeadd(timestamp(), "48h")
  hostpool_id     = module.avm_res_desktopvirtualization_hostpool.resource.id
}

# Get an existing built-in role definition
data "azurerm_role_definition" "this" {
  name = "Desktop Virtualization User"
}

# Get an existing Azure AD group that will be assigned to the application group
data "azuread_group" "existing" {
  display_name     = var.user_group_name
  security_enabled = true
}

# Assign the Azure AD group to the application group
resource "azurerm_role_assignment" "this" {
  principal_id                     = data.azuread_group.existing.object_id
  scope                            = module.avm_res_desktopvirtualization_applicationgroup.resource.id
  role_definition_id               = data.azurerm_role_definition.this.id
  skip_service_principal_aad_check = false
}

# Create Azure Virtual Desktop application group
module "avm_res_desktopvirtualization_applicationgroup" {
  source                                                = "Azure/avm-res-desktopvirtualization-applicationgroup/azurerm"
  enable_telemetry                                      = var.enable_telemetry
  version                                               = "0.1.2"
  virtual_desktop_application_group_name                = var.virtual_desktop_application_group_name
  virtual_desktop_application_group_type                = var.virtual_desktop_application_group_type
  virtual_desktop_application_group_host_pool_id        = module.avm_res_desktopvirtualization_hostpool.resource.id
  virtual_desktop_application_group_resource_group_name = azurerm_resource_group.this.name
  virtual_desktop_application_group_location            = azurerm_resource_group.this.location
  user_group_name                                       = var.user_group_name
  virtual_desktop_application_group_tags                = local.tags
}

# Create Azure Virtual Desktop workspace
module "avm_res_desktopvirtualization_workspace" {
  source              = "Azure/avm-res-desktopvirtualization-workspace/azurerm"
  version             = "0.1.2"
  enable_telemetry    = var.enable_telemetry
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  description         = var.description
  name                = var.virtual_desktop_workspace_name
  tags                = local.tags
  diagnostic_settings = {
    to_law = {
      name                  = "to-law"
      workspace_resource_id = module.avm_res_operationalinsights_workspace.resource.id
    }
  }
}

resource "azurerm_virtual_desktop_workspace_application_group_association" "workappgrassoc" {
  application_group_id = module.avm_res_desktopvirtualization_applicationgroup.resource.id
  workspace_id         = module.avm_res_desktopvirtualization_workspace.resource.id
}

# Get the subscription
data "azurerm_subscription" "primary" {}

# Get the service principal for Azure Vitual Desktop
data "azuread_service_principal" "spn" {
  client_id = "9cdead84-a844-4324-93f2-b2e6bb768d07"
}

resource "random_uuid" "example" {}

data "azurerm_role_definition" "power_role" {
  name = "Desktop Virtualization Power On Off Contributor"
}

resource "azurerm_role_assignment" "new" {
  principal_id         = data.azuread_service_principal.spn.object_id
  scope                = data.azurerm_subscription.primary.id
  role_definition_name = "Desktop Virtualization Power On Off Contributor"
}

# Create Azure Virtual Desktop scaling plan
module "avm_res_desktopvirtualization_scaling_plan" {
  source                                           = "Azure/avm-res-desktopvirtualization-scalingplan/azurerm"
  enable_telemetry                                 = var.enable_telemetry
  version                                          = "0.1.2"
  virtual_desktop_scaling_plan_name                = var.virtual_desktop_scaling_plan_name
  virtual_desktop_scaling_plan_location            = azurerm_resource_group.this.location
  virtual_desktop_scaling_plan_resource_group_name = azurerm_resource_group.this.name
  virtual_desktop_scaling_plan_time_zone           = var.virtual_desktop_scaling_plan_time_zone
  virtual_desktop_scaling_plan_description         = var.virtual_desktop_scaling_plan_description
  virtual_desktop_scaling_plan_tags                = local.tags
  virtual_desktop_scaling_plan_host_pool = toset(
    [
      {
        hostpool_id          = module.avm_res_desktopvirtualization_hostpool.resource.id
        scaling_plan_enabled = true
      }
    ]
  )
  virtual_desktop_scaling_plan_schedule = toset(
    [
      {
        name                                 = "Weekday"
        days_of_week                         = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
        ramp_up_start_time                   = "09:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        ramp_up_minimum_hosts_percent        = 50
        ramp_up_capacity_threshold_percent   = 80
        peak_start_time                      = "10:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "17:00"
        ramp_down_load_balancing_algorithm   = "BreadthFirst"
        ramp_down_minimum_hosts_percent      = 50
        ramp_down_force_logoff_users         = true
        ramp_down_wait_time_minutes          = 15
        ramp_down_notification_message       = "The session will end in 15 minutes."
        ramp_down_capacity_threshold_percent = 50
        ramp_down_stop_hosts_when            = "ZeroActiveSessions"
        off_peak_start_time                  = "18:00"
        off_peak_load_balancing_algorithm    = "BreadthFirst"
      },
      {
        name                                 = "Weekend"
        days_of_week                         = ["Saturday", "Sunday"]
        ramp_up_start_time                   = "09:00"
        ramp_up_load_balancing_algorithm     = "BreadthFirst"
        ramp_up_minimum_hosts_percent        = 50
        ramp_up_capacity_threshold_percent   = 80
        peak_start_time                      = "10:00"
        peak_load_balancing_algorithm        = "DepthFirst"
        ramp_down_start_time                 = "17:00"
        ramp_down_load_balancing_algorithm   = "BreadthFirst"
        ramp_down_minimum_hosts_percent      = 50
        ramp_down_force_logoff_users         = true
        ramp_down_wait_time_minutes          = 15
        ramp_down_notification_message       = "The session will end in 15 minutes."
        ramp_down_capacity_threshold_percent = 50
        ramp_down_stop_hosts_when            = "ZeroActiveSessions"
        off_peak_start_time                  = "18:00"
        off_peak_load_balancing_algorithm    = "BreadthFirst"
        count = var.virtual_desktop_host_pool_type == "Personal" ? 0 : 1
      }
    ]
  )
}

