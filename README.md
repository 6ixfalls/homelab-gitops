# Homelab
## Cluster initialization

Add the `debian-12-standard_12.2-1_amd64` CT Template to the local storage. Run `tofu apply` to deploy the auroraboot LXC container. Setup your router to point to the correct PXE server. Edit the agent VMs and add the string `,serial=longhorn` to the scsi1 disk: (https://github.com/bpg/terraform-provider-proxmox/issues/1290). Boot and success