terraform {
    required_providers {
        proxmox = {
            source = "bpg/proxmox"
            version = "0.42.0"
        }
        opnsense = {
            source = "xyhhx/opnsense"
            version = "0.3.1-rc2"
        }
    }
}

variable "virtual_environment_endpoint" {
  type        = string
  description = "The endpoint for the Proxmox Virtual Environment API (example: https://host:port)"
}

variable "virtual_environment_password" {
  type        = string
  description = "The password for the Proxmox Virtual Environment API"
}

variable "virtual_environment_username" {
  type        = string
  description = "The username and realm for the Proxmox Virtual Environment API (example: root@pam)"
}

variable "opnsense_endpoint" {
  type        = string
  description = "The endpoint for the OPNsense API (example: https://host:port)"
}

variable "opnsense_password" {
  type        = string
  description = "The password for the OPNsense API"
}

variable "opnsense_username" {
  type        = string
  description = "The username for the OPNsense API"
}

variable "doppler_token" {
    type        = string
    description = "The Doppler token for cluster bootstrap secrets"
}

variable "doppler_project" {
    type        = string
    description = "The Doppler project for cluster bootstrap secrets"
}

variable "cluster_domain" {
    type        = string
    description = "The domain for the cluster"
}

provider "proxmox" {
  endpoint = var.virtual_environment_endpoint
  username = var.virtual_environment_username
  password = var.virtual_environment_password
  insecure = true
}

provider "opnsense" {
    uri = var.opnsense_endpoint
    user = var.opnsense_username
    password = var.opnsense_password
    allow_unverified_tls = true
}

variable "control_mac_addresses" {
  description = "List of MAC addresses for the control planes"
  type        = list(string)
  default     = ["BC:24:11:CA:7B:77", "BC:24:11:FA:F2:EB", "BC:24:11:97:43:81"]
}

variable "agent_mac_addresses" {
  description = "List of MAC addresses for the agents"
  type        = list(string)
  default     = ["BC:24:11:C9:BF:99", "BC:24:11:22:0D:00", "BC:24:11:D9:44:8B"]
}

variable "nodes" {
  description = "List of nodes"
  type        = list(string)
  default     = ["hutao"]
}

data "http" "ssh_keys" {
    url = "https://github.com/6ixfalls.keys"
    method = "GET"
}

resource "proxmox_virtual_environment_vm" "cluster_node" {
    agent {
        enabled = true
    }

    name = "cluster-node-template"

    bios = "ovmf"

    cpu {
        cores = 2
        sockets = 1
        type = "x86-64-v2-AES"
    }

    memory {
        dedicated = 4096
    }

    efi_disk {
        datastore_id = "local-zfs"
        file_format = "raw"
        type = "4m"
    }

    disk {
        datastore_id = "local-zfs"
        file_format = "raw"
        interface = "scsi0"
        size = 24
        iothread = true
    }

    network_device {
        bridge = "taonet"
        model = "virtio"
    }

    boot_order = ["scsi0", "net0"]

    node_name = "hutao"

    scsi_hardware = "virtio-scsi-single"

    template = true

    depends_on = [proxmox_virtual_environment_container.auroraboot]
}

resource "proxmox_virtual_environment_vm" "control_plane" {
  count = length(var.control_mac_addresses)

  name       = "control-plane-${count.index + 1}"
  node_name  = var.nodes[count.index % length(var.nodes)]
  migrate    = true
  vm_id      = 500 + count.index + 1

  clone {
    vm_id = proxmox_virtual_environment_vm.cluster_node.vm_id
  }

  network_device {
    bridge      = "taonet"
    model       = "virtio"
    mac_address = var.control_mac_addresses[count.index]
  }

  depends_on = [opnsense_dhcp_static_map.control_plane, proxmox_virtual_environment_vm.cluster_node]
}

resource "opnsense_dhcp_static_map" "control_plane" {
    count = length(var.control_mac_addresses)
    
    interface = "lan"
    mac = var.control_mac_addresses[count.index]
    ipaddr = "10.17.2.${count.index + 1}"
    hostname = "control-plane-${count.index + 1}"
}

resource "proxmox_virtual_environment_vm" "agent" {
  count = length(var.agent_mac_addresses)

  name       = "k3s-agent-${count.index + 1}"
  node_name  = var.nodes[count.index % length(var.nodes)]
  migrate    = true
  vm_id      = 600 + count.index + 1

  clone {
    vm_id = proxmox_virtual_environment_vm.cluster_node.vm_id
  }

  network_device {
    bridge      = "taonet"
    model       = "virtio"
    mac_address = var.agent_mac_addresses[count.index]
  }

  depends_on = [opnsense_dhcp_static_map.agent, proxmox_virtual_environment_vm.cluster_node]
}

resource "opnsense_dhcp_static_map" "agent" {
    count = length(var.agent_mac_addresses)
    
    interface = "lan"
    mac = var.agent_mac_addresses[count.index]
    ipaddr = "10.17.3.${count.index + 1}"
    hostname = "k3s-agent-${count.index + 1}"
}

resource "random_password" "auroraboot_container_password" {
  length           = 16
  override_special = "_%@"
  special          = true
}

output "auroraboot_container_password" {
  value     = random_password.auroraboot_container_password.result
  sensitive = true
}

resource "proxmox_virtual_environment_file" "debian_container_template" {
  content_type = "vztmpl"
  datastore_id = "local"
  node_name    = "hutao"

  source_file {
    path = "http://download.proxmox.com/images/system/debian-12-standard_12.2-1_amd64.tar.zst"
  }
}

resource "proxmox_virtual_environment_container" "auroraboot" {
    description = "AuroraBoot managed by OpenTofu"

    cpu {
        cores = 2
    }

    memory {
        dedicated = 4096
    }

    node_name = "hutao"
    
    initialization {
        hostname = "auroraboot"

        ip_config {
            ipv4 {
                address = "10.17.32.8/16"
                gateway = "10.17.0.1"
            }
        }

        user_account {
            keys = [data.http.ssh_keys.response_body]
            password = random_password.auroraboot_container_password.result
        }
    }

    network_interface {
        name = "eth0"
        bridge = "taonet"
    }

    operating_system {
        template_file_id = proxmox_virtual_environment_file.debian_container_template.id
        type = "debian"
    }

    disk {
        datastore_id = "local-zfs"
        size = 12
    }

    features {
        nesting = true
        keyctl = true
    }

    connection {
        type = "ssh"
        user = "root"
        private_key = file("~/.ssh/id_ed25519")
        host = "10.17.32.8"
    }

    provisioner "file" {
        source = "./aurora_init.sh"
        destination = "."
    }

    provisioner "remote-exec" {
        inline = [
            "chmod +x aurora_init.sh",
            "DOPPLER_TOKEN=${var.doppler_token} DOPPLER_PROJECT=${var.doppler_project} CLUSTER_DOMAIN=${var.cluster_domain} ./aurora_init.sh",
            "rm aurora_init.sh"
        ]
    }

    unprivileged = true
}