# Automated-Azure-Terraform-App

Infrastructure-as-Code project that provisions an auto-scaling web tier on
**Microsoft Azure** using **Terraform** and the `azurerm` provider.

It builds a complete stack around an Azure **Virtual Machine Scale Set
(VMSS)** fronted by a **Public Load Balancer**, wired into a dedicated VNet,
subnet, NSG, public IP, NAT rule, and an availability set — all defined
declaratively so the environment can be recreated, destroyed, and version
controlled.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Project Structure](#project-structure)
4. [Resources Provisioned](#resources-provisioned)
5. [Prerequisites](#prerequisites)
6. [Authentication](#authentication)
7. [Variables Reference](#variables-reference)
8. [Outputs Reference](#outputs-reference)
9. [Usage](#usage)
10. [Autoscaling Behavior](#autoscaling-behavior)
11. [Networking and Security](#networking-and-security)
12. [Verification and Testing](#verification-and-testing)
13. [Tearing Down](#tearing-down)
14. [Known Limitations and Notes](#known-limitations-and-notes)
15. [Roadmap](#roadmap)
16. [References](#references)
17. [Author](#author)

---

## Overview

This project demonstrates how to use Terraform to manage a horizontally
scalable Linux web tier on Azure. The goal is a small but realistic example
that you can `init`, `plan`, and `apply` end-to-end, and that exercises the
main building blocks you would use in a production-style Azure environment:

- A dedicated **Resource Group** as the deployment boundary.
- A **Virtual Network + Subnet** to isolate the workload.
- A **Public Load Balancer** with a backend address pool, a health probe,
  and a NAT rule.
- A **Network Security Group** that allows inbound HTTP and SSH.
- An **Availability Set** for fault domain spreading.
- A **VM Scale Set** of Ubuntu VMs that registers into the load balancer
  backend pool, with autoscaling based on CPU utilization.

The entire stack is described in three Terraform files — `main.tf`,
`variables.tf`, and `outputs.tf` — and can be deployed with the standard
Terraform workflow.

---

## Architecture

```
                       ┌────────────────────────┐
   Internet ─────────► │   Public IP (Static)   │
                       │   autoscaling_group_pip│
                       └────────────┬───────────┘
                                    │
                       ┌────────────▼───────────┐
                       │   Azure Load Balancer  │
                       │   autoscaling_group_lb │
                       │   • Frontend IP        │
                       │   • Backend Pool       │
                       │   • HTTP Probe (/, :80)│
                       │   • NAT Rule (80→80)   │
                       └────────────┬───────────┘
                                    │
                       ┌────────────▼────────────┐
                       │  VM Scale Set (VMSS)    │
                       │  autoscaling_group      │
                       │  • Ubuntu 16.04 LTS     │
                       │  • SKU Standard_DS1_v2  │
                       │  • Autoscale on CPU>70% │
                       └────────────┬────────────┘
                                    │
                       ┌────────────▼────────────┐
                       │ Subnet 10.0.1.0/24      │
                       │ in VNet 10.0.0.0/16     │
                       │ (NSG: allow 80, 22)     │
                       └────────────┬────────────┘
                                    │
                       ┌────────────▼────────────┐
                       │ Resource Group: eastus  │
                       │ autoscaling_group_rg    │
                       └─────────────────────────┘
```

---

## Project Structure

```
Automated-Azure-Terraform-App/
├── main.tf         # All resource definitions (RG, VNet, LB, NSG, VMSS, etc.)
├── variables.tf    # Input variable declarations (auth + VM config)
├── outputs.tf      # Outputs exposed after `terraform apply`
├── .gitignore      # Git ignore rules (currently empty — see Notes)
└── Readme.md       # This file
```

| File           | Purpose                                                                 |
| -------------- | ----------------------------------------------------------------------- |
| `main.tf`      | Declares the `azurerm` provider and every Azure resource in the stack. |
| `variables.tf` | Declares input variables: Azure SP credentials, region, RG name, admin. |
| `outputs.tf`   | Exposes resource group name, load balancer public IP, backend pool ID. |
| `.gitignore`   | Reserved for ignoring Terraform state, plan files, and local overrides. |

---

## Resources Provisioned

Defined in `main.tf`:

| Terraform Address                                       | Azure Resource                          | Key Settings                                                          |
| ------------------------------------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| `azurerm_resource_group.autoscaling_group_rg`           | Resource Group                          | name `autoscaling_group_rg`, location `eastus`                       |
| `azurerm_virtual_network.autoscaling_group_vnet`        | Virtual Network                         | address space `10.0.0.0/16`, inline subnet `10.0.1.0/24`             |
| `azurerm_public_ip.autoscaling_group_pip`               | Public IP                               | static allocation                                                     |
| `azurerm_lb.autoscaling_group_lb`                       | Load Balancer                           | frontend `PublicIPAddress`, backend pool, HTTP probe on `/` port 80   |
| `azurerm_lb_nat_rule.autoscaling_group_nat_rule`        | LB NAT Rule                             | TCP, frontend 80 → backend 80                                         |
| `azurerm_network_security_group.autoscaling_group_nsg`  | Network Security Group                  | inbound rules: `AllowHTTPInbound` (80), `AllowSSHInbound` (22)        |
| `azurerm_availability_set.autoscaling_group_as`         | Availability Set                        | groups VMSS instances for fault-domain spreading                      |
| `azurerm_virtual_machine_scale_set.autoscaling_group`   | Virtual Machine Scale Set               | SKU `Standard_DS1_v2`, 2 instances, Ubuntu Server 16.04 LTS           |

---

## Prerequisites

1. **Terraform CLI** ≥ 1.3 — [Download](https://developer.hashicorp.com/terraform/downloads).
2. **Azure CLI** ≥ 2.x — [Install](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) (optional, but the easiest way to bootstrap a Service Principal).
3. **An active Azure subscription** with permission to create:
   - Resource Groups
   - Virtual Networks, Subnets, NSGs, Public IPs
   - Load Balancers and NAT rules
   - Availability Sets and Virtual Machine Scale Sets
4. **A Service Principal** (Client ID + Client Secret + Tenant ID) with at
   least `Contributor` role on the target subscription, OR an Azure CLI
   login that Terraform can reuse.
5. (Optional) **A remote state backend** (e.g. an Azure Storage Account
   container) if you intend to share state across machines or pipelines.

---

## Authentication

There are two practical ways to authenticate Terraform against Azure for
this project. Pick one.

### Option A — Azure CLI login (simplest for local development)

```bash
az login
az account set --subscription "<your_subscription_id>"
```

With this in place, Terraform's `azurerm` provider will pick up your CLI
credentials automatically. You can leave the `provider` block in `main.tf`
empty or remove the placeholder credentials.

### Option B — Service Principal (recommended for CI/CD)

1. Create a Service Principal:

   ```bash
   az ad sp create-for-rbac \
     --name "automated-azure-terraform-app-sp" \
     --role Contributor \
     --scopes "/subscriptions/<your_subscription_id>"
   ```

2. Note down `appId` (client_id), `password` (client_secret), `tenant`
   (tenant_id), plus your `subscription_id`.

3. Provide them to Terraform. The cleanest way is via environment variables:

   ```bash
   export ARM_SUBSCRIPTION_ID="<your_subscription_id>"
   export ARM_CLIENT_ID="<client_id>"
   export ARM_CLIENT_SECRET="<client_secret>"
   export ARM_TENANT_ID="<tenant_id>"
   ```

   Or via a `terraform.tfvars` file that maps onto the variables declared
   in `variables.tf`:

   ```hcl
   subscription_id = "<your_subscription_id>"
   client_id       = "<client_id>"
   client_secret   = "<client_secret>"
   tenant_id       = "<tenant_id>"
   admin_password  = "<strong_admin_password>"
   ```

> Note: `main.tf` currently hardcodes `<subscription_id>` style placeholders
> directly in the `provider "azurerm" { ... }` block. See
> [Known Limitations and Notes](#known-limitations-and-notes) for how to
> wire the provider block to the variables defined in `variables.tf`.

---

## Variables Reference

Declared in `variables.tf`:

| Variable              | Type     | Default                 | Sensitive | Description                                          |
| --------------------- | -------- | ----------------------- | --------- | ---------------------------------------------------- |
| `subscription_id`     | `string` | — (required)            | no        | Azure Subscription ID.                               |
| `client_id`           | `string` | — (required)            | no        | Azure Service Principal Client ID (App ID).          |
| `client_secret`       | `string` | — (required)            | **yes**   | Azure Service Principal Client Secret.               |
| `tenant_id`           | `string` | — (required)            | no        | Azure Tenant ID.                                     |
| `location`            | `string` | `"East US"`             | no        | Azure region for all resources.                      |
| `resource_group_name` | `string` | `"autoscaling_group_rg"`| no        | Name of the Resource Group to create.                |
| `admin_username`      | `string` | `"adminuser"`           | no        | Admin username for the VMSS instances.               |
| `admin_password`      | `string` | — (required)            | **yes**   | Admin password for the VMSS instances.               |

> Tip: Keep `client_secret` and `admin_password` out of source control. Use
> environment variables (`TF_VAR_admin_password=...`), a local
> `terraform.tfvars` (gitignored), or a secret manager.

---

## Outputs Reference

Declared in `outputs.tf` — printed at the end of `terraform apply` and
queryable via `terraform output`:

| Output                    | Description                                              |
| ------------------------- | -------------------------------------------------------- |
| `resource_group_name`     | The name of the created Azure Resource Group.            |
| `load_balancer_public_ip` | The public IP address of the load balancer frontend.     |
| `backend_address_pool_id` | The ID of the load balancer's backend address pool.      |

Print all outputs:

```bash
terraform output
```

Print a single value (machine-readable):

```bash
terraform output -raw load_balancer_public_ip
```

---

## Usage

### 1. Clone the repository

```bash
git clone https://github.com/sssrikar16-lgtm/Automated-Azure-Terraform-App.git
cd Automated-Azure-Terraform-App
```

### 2. Configure credentials

Use one of the methods in [Authentication](#authentication). The simplest
local-dev option is `az login`.

### 3. Initialize Terraform

```bash
terraform init
```

This downloads the `azurerm` provider plugin.

### 4. Review the plan

```bash
terraform plan -out tfplan
```

Terraform prints every resource it intends to create. Read this carefully
before applying.

### 5. Apply

```bash
terraform apply tfplan
```

Confirm with `yes` if prompted. Provisioning takes a few minutes (VMSS
creation is the slowest step).

### 6. Inspect outputs

```bash
terraform output
```

The `load_balancer_public_ip` is the address to hit in your browser /
`curl` once the VMs are up and serving on port 80.

---

## Autoscaling Behavior

The VM Scale Set is configured to scale based on CPU utilization:

- **Scale-out trigger**: average CPU > **70%** over a **5-minute** window
  → add **1** instance (`ChangeCount`).
- **Scale-in trigger**: average CPU below threshold over the same window
  → remove **20%** of running instances (`PercentChangeCount`).
- **Cooldown** between scaling actions: **5 minutes** per rule, **10
  minutes** at the policy level.
- **Initial instance count**: **2**.

> The scaling block is declared inline on the `azurerm_virtual_machine_scale_set`
> resource in `main.tf`. On modern `azurerm` provider versions Azure
> autoscale is typically managed with a separate
> `azurerm_monitor_autoscale_setting` resource — see
> [Known Limitations and Notes](#known-limitations-and-notes).

---

## Networking and Security

- **VNet**: `10.0.0.0/16`
- **Subnet**: `10.0.1.0/24` (inline subnet on the VNet)
- **Public IP**: Static, attached to the load balancer frontend.
- **Load Balancer Probe**: HTTP `GET /` on port `80`, 5s interval, 2 probes.
- **NSG inbound rules**:

  | Name                | Protocol | Port | Source | Priority |
  | ------------------- | -------- | ---- | ------ | -------- |
  | `AllowHTTPInbound`  | TCP      | 80   | `*`    | 100      |
  | `AllowSSHInbound`   | TCP      | 22   | `*`    | 101      |

> Allowing SSH from `*` (the entire internet) is fine for a demo but
> **not** recommended for production. Tighten `source_address_prefix` to
> your office IP / VPN range, or front it with Azure Bastion.

---

## Verification and Testing

After `terraform apply` completes:

1. **HTTP check from your machine**

   ```bash
   curl -i "http://$(terraform output -raw load_balancer_public_ip)/"
   ```

   You should get an HTTP response from one of the VMSS instances (note
   that the base Ubuntu image does **not** ship with a web server — see
   [Roadmap](#roadmap) for adding one via `custom_data` / cloud-init).

2. **Check VMSS instances in the Azure Portal**
   - Navigate to your resource group → `autoscaling_group` (VMSS).
   - Confirm `instances = 2` and that both instances are healthy.

3. **Confirm load balancing**
   - In the portal, open the Load Balancer → Backend pools → confirm both
     VMSS instances are listed.
   - Open Health probes → confirm probe status is healthy.

4. **Confirm autoscaling settings**
   - In the portal, open the VMSS → Scaling. The CPU thresholds and min/max
     instance count should match what's in `main.tf`.

---

## Tearing Down

When you're done, destroy everything to avoid charges:

```bash
terraform destroy
```

Confirm with `yes`. Terraform tears down resources in reverse dependency
order. Once it finishes, double-check in the Azure Portal that
`autoscaling_group_rg` is gone.

---

## Known Limitations and Notes

These are caveats in the **current** code that an operator should be aware
of. They are intentionally documented (not silently fixed) so the project
stays as you authored it.

1. **Provider block hardcodes placeholders.**
   `main.tf` currently has:

   ```hcl
   provider "azurerm" {
     subscription_id = "<subscription_id>"
     client_id       = "<client_id>"
     client_secret   = "<client_secret>"
     tenant_id       = "<tenant_id>"
   }
   ```

   These placeholders are not consumed from `variables.tf`. To use the
   declared variables, change the block to:

   ```hcl
   provider "azurerm" {
     features        = {}
     subscription_id = var.subscription_id
     client_id       = var.client_id
     client_secret   = var.client_secret
     tenant_id       = var.tenant_id
   }
   ```

   The `features {}` block is required by recent `azurerm` provider
   versions.

2. **`.gitignore` is empty.**
   You almost certainly want to ignore Terraform state and plan files.
   Suggested contents:

   ```gitignore
   *.tfstate
   *.tfstate.*
   *.tfplan
   .terraform/
   .terraform.lock.hcl
   crash.log
   override.tf
   override.tf.json
   *.auto.tfvars
   terraform.tfvars
   ```

3. **Some VMSS blocks use older `azurerm` syntax.**
   The current resource uses `storage_profile_image_reference`,
   `storage_profile_os_disk`, `os_profile`, an inline `scaling_policy`,
   and two `upgrade_policy` blocks. These were valid in older `azurerm`
   provider releases but the modern (`> 2.x`) provider uses
   `source_image_reference`, `os_disk`, `admin_username` / `admin_password`
   at the resource level, and a separate
   `azurerm_monitor_autoscale_setting` resource. If you upgrade the
   provider, plan to refactor this block.

4. **Inline subnet on the VNet.**
   `main.tf` declares the subnet inline on `azurerm_virtual_network`. The
   newer pattern is a dedicated `azurerm_subnet` resource, which gives
   you a stable `azurerm_subnet.X.id` to wire into the VMSS NIC.

5. **NSG is not associated with the subnet or NIC.**
   The NSG `autoscaling_group_nsg` is created but no
   `azurerm_subnet_network_security_group_association` (or NIC-level
   association) is declared. The rules won't take effect until that
   association is added.

6. **Ubuntu 16.04 LTS image is out of support.**
   Consider upgrading the image reference to `22_04-lts` (Ubuntu 22.04
   LTS) or newer for a supported OS.

---

## Roadmap

Ideas for extending this project:

- Replace hardcoded credentials with variable references and add a
  `features {}` block (see Note 1 above).
- Switch to `azurerm_monitor_autoscale_setting` for autoscale rules.
- Use a dedicated `azurerm_subnet` resource and associate the NSG with it.
- Upgrade the OS image to Ubuntu 22.04 LTS.
- Inject a `custom_data` / cloud-init script that installs and starts
  `nginx` on each VM so the LB serves real traffic out of the box.
- Add a **remote state backend** (Azure Storage) and state locking.
- Add a **CI workflow** (GitHub Actions / Azure DevOps) that runs
  `terraform fmt`, `terraform validate`, `tflint`, and `terraform plan`
  on every pull request.
- Replace the password-based admin with an SSH public key
  (`admin_ssh_key` block).
- Move the LB frontend port from 80 to 443 with a TLS-terminating
  Application Gateway in front.

---

## References

- [Terraform — `azurerm` provider docs](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Virtual Machine Scale Sets overview](https://learn.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
- [Azure Load Balancer overview](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-overview)
- [Azure Monitor autoscale](https://learn.microsoft.com/en-us/azure/azure-monitor/autoscale/autoscale-overview)
- [Terraform Best Practices](https://developer.hashicorp.com/terraform/tutorials)

---

## Author

Made by **sssrikar16-lgtm**
GitHub: [https://github.com/sssrikar16-lgtm](https://github.com/sssrikar16-lgtm)

> Feel free to fork this project and customize it for your infrastructure needs.
