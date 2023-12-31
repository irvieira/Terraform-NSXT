provider "vsphere" {
  vsphere_server       = var.vsphere_server
  user                 = var.vsphere_user
  password             = var.vsphere_password
  allow_unverified_ssl = true
}

# Data source for vCenter Datacenter
data "vsphere_datacenter" "datacenter" {
  name = var.data_center
}
# Data source for vCenter Cluster
data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# Data source for vCenter Datastore
data "vsphere_datastore" "datastore" {
  name          = var.workload_datastore
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# Data source for vCenter Portgroup
data "vsphere_network" "mgmt" {
  name          = var.mgmt_pg
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# Data source for vCenter Resource Pool. In our case we will use the root resource pool
data "vsphere_resource_pool" "pool" {
  name          = format("%s%s", data.vsphere_compute_cluster.cluster.name, "/Resources")
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# Data source for ESXi host to deploy to
data "vsphere_host" "host" {
  name          = var.compute_host
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# Data source for the OVF to read the required OVF Properties
data "vsphere_ovf_vm_template" "ovfLocal" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_resource_pool.pool.id
  datastore_id     = data.vsphere_datastore.datastore.id
  host_system_id   = data.vsphere_host.host.id
  local_ovf_path   = var.local_ovf_path
  ovf_network_map = {
    "Network 1" = data.vsphere_network.mgmt.id
  }
}
# Deployment of VM from Local OVA
resource "vsphere_virtual_machine" "nsxt01" {
  name                 = var.vm_name
  folder               = var.vm_folder
  datacenter_id        = data.vsphere_datacenter.datacenter.id
  datastore_id         = data.vsphere_ovf_vm_template.ovfLocal.datastore_id
  host_system_id       = data.vsphere_ovf_vm_template.ovfLocal.host_system_id
  resource_pool_id     = data.vsphere_ovf_vm_template.ovfLocal.resource_pool_id
  num_cpus             = data.vsphere_ovf_vm_template.ovfLocal.num_cpus
  num_cores_per_socket = data.vsphere_ovf_vm_template.ovfLocal.num_cores_per_socket
  memory               = data.vsphere_ovf_vm_template.ovfLocal.memory
  guest_id             = data.vsphere_ovf_vm_template.ovfLocal.guest_id
  scsi_type            = data.vsphere_ovf_vm_template.ovfLocal.scsi_type
  dynamic "network_interface" {
    for_each = data.vsphere_ovf_vm_template.ovfLocal.ovf_network_map
    content {
      network_id = network_interface.value
    }
  }
  wait_for_guest_net_timeout = 5
  ovf_deploy {
    allow_unverified_ssl_cert = true
    local_ovf_path            = var.local_ovf_path
    disk_provisioning         = "thin"
    deployment_option         = var.deployment_option
  }
  vapp {
    properties = {
      "nsx_role"               = var.nsx_role,
      "nsx_ip_0"               = var.nsx_ip_0,
      "nsx_netmask_0"          = var.nsx_netmask_0,
      "nsx_gateway_0"          = var.nsx_gateway_0,
      "nsx_dns1_0"             = var.nsx_dns1_0,
      "nsx_domain_0"           = var.nsx_domain_0,
      "nsx_ntp_0"              = var.nsx_ntp_0,
      "nsx_isSSHEnabled"       = var.nsx_isSSHEnabled,
      "nsx_allowSSHRootLogin"  = var.nsx_allowSSHRootLogin,
      "nsx_passwd_0"           = var.nsx_passwd_0,
      "nsx_cli_passwd_0"       = var.nsx_cli_passwd_0,
      "nsx_cli_audit_passwd_0" = var.nsx_cli_audit_passwd_0,
      "nsx_hostname"           = var.nsx_hostname
    }
  }
  lifecycle {
    ignore_changes = [
      #vapp # Enable this to ignore all vapp properties if the plan is re-run
      vapp[0].properties["nsx_role"], # Avoid unwanted changes to specific vApp properties.
      vapp[0].properties["nsx_passwd_0"],
      vapp[0].properties["nsx_cli_passwd_0"],
      vapp[0].properties["nsx_cli_audit_passwd_0"],
      host_system_id # Avoids moving the VM back to the host it was deployed to if DRS has relocated it
    ]
  }
}