


***

```markdown
I recently set up cross-account, multi-region VPC peering on AWS using Terraform.

I hit a bunch of real-world errors along the way (VPC lookups, route tables, Route 53 cleanup, key pairs), so I documented the full process and fixes.

Sharing in case it saves someone a few hours of debugging.

## Building Cross-Account, Multi-Region VPC Peering on AWS with Terraform (and Fixing the problems encountered)

This walkthrough covers how I set up VPC peering between two AWS accounts using Terraform, the steps I followed, and the real‑world errors I hit—and how I fixed them.

## Architecture and Goals

I wanted:

- Two VPCs in different regions and different AWS accounts:
  - Primary: Account A, region `us-east-1`
  - Secondary: Account B, region `us-west-2`
- Each VPC with:
  - One public subnet, internet gateway, and route table
  - A security group allowing SSH and cross‑VPC traffic
  - One EC2 instance
- Cross‑account VPC peering between the VPCs so instances can talk over private IPs.

---

## Terraform Setup

### Providers and variables

I defined two provider aliases, one per account/region, and variables for VPCs and keys:

```hcl
provider "aws" {
  alias  = "primary"
  region = var.primary   # us-east-1
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary # us-west-2
}

variable "primary"   { default = "us-east-1" }
variable "secondary" { default = "us-west-2" }

variable "primary_vpc_cidr"   { default = "10.0.0.0/16" }
variable "secondary_vpc_cidr" { default = "10.1.0.0/16" }

variable "primary_key_name" {
  description = "Name of the SSH key pair for Primary VPC instance (us-east-1)"
  type        = string
  default     = ""
}

variable "secondary_key_name" {
  description = "Name of the SSH key pair for Secondary VPC instance (us-west-2)"
  type        = string
  default     = ""
}
```

In `terraform.tfvars` I set:

```hcl
primary_key_name   = "vpc-peering-demo"
secondary_key_name = "vpc-peering-demo"
```

and created a key pair named `vpc-peering-demo` in both `us-east-1` and `us-west-2`.

---

## Network Resources

### VPCs and subnets

I created one VPC and one public subnet per account:

```hcl
resource "aws_vpc" "primary_vpc" {
  provider             = aws.primary
  cidr_block           = var.primary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "Primary-VPC-${var.primary}" }
}

resource "aws_vpc" "secondary_vpc" {
  provider             = aws.secondary
  cidr_block           = var.secondary_vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "Secondary-VPC-${var.secondary}" }
}

resource "aws_subnet" "primary_subnet" {
  provider                = aws.primary
  vpc_id                  = aws_vpc.primary_vpc.id
  cidr_block              = cidrsubnet(var.primary_vpc_cidr, 8, 1)   # e.g. 10.0.1.0/24
  availability_zone       = data.aws_availability_zones.primary.names
  map_public_ip_on_launch = true

  tags = {
    Name        = "Primary-Subnet-${var.primary}"
    Environment = "Demo"
  }
}

resource "aws_subnet" "secondary_subnet" {
  provider                = aws.secondary
  vpc_id                  = aws_vpc.secondary_vpc.id
  cidr_block              = cidrsubnet(var.secondary_vpc_cidr, 8, 1) # e.g. 10.1.1.0/24
  availability_zone       = data.aws_availability_zones.secondary.names
  map_public_ip_on_launch = true

  tags = {
    Name        = "Secondary-Subnet-${var.secondary}"
    Environment = "Demo"
  }
}
```

---

### Internet gateways and route tables

I attached an internet gateway and created a route table in each VPC with a default route to the internet:

```hcl
resource "aws_internet_gateway" "primary_igw" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id

  tags = {
    Name        = "Primary-IGW-${var.primary}"
    Environment = "Demo"
  }
}

resource "aws_internet_gateway" "secondary_igw" {
  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id

  tags = {
    Name        = "Secondary-IGW-${var.secondary}"
    Environment = "Demo"
  }
}

resource "aws_route_table" "primary_rt" {
  provider = aws.primary
  vpc_id   = aws_vpc.primary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.primary_igw.id
  }

  tags = {
    Name        = "Primary-RT-${var.primary}"
    Environment = "Demo"
  }
}

resource "aws_route_table" "secondary_rt" {
OAOAOA  provider = aws.secondary
  vpc_id   = aws_vpc.secondary_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.secondary_igw.id
  }

  tags = {
    Name        = "Secondary-RT-${var.secondary}"
    Environment = "Demo"
OAOAOA  }
}

resource "aws_route_table_association" "primary_rta" {
  provider       = aws.primary
  subnet_id      = aws_subnet.primary_subnet.id
  route_table_id = aws_route_table.primary_rt.id
}

resource "aws_route_table_association" "secondary_rta" {
  provider       = aws.secondary
  subnet_id      = aws_subnet.secondary_subnet.id
OAOAOA  route_table_id = aws_route_table.secondary_rt.id
}
```

Lesson learned here: `route_table_id` must be the **route table ID** (`rtb-...`), not the VPC ID. Using `aws_route_table.primary_rt.vpc_id` produced an `InvalidRouteTableId.Malformed` error because AWS got a `"vpc-..."` ID where it expected `"rtb-..."`.

---

## Cross-Account VPC Peering

To connect the VPCs across accounts, I followed the standard requester/accepter pattern.

### Peering connection and accepter

Requester in the primary account:

```hcl
resource "aws_vpc_peering_connection" "primary_to_secondary" {
  provider      = aws.primary
  vpc_id        = aws_vpc.primary_vpc.id
  peer_owner_id = var.secondary_account_id
  peer_vpc_id   = aws_vpc.secondary_vpc.id
  peer_region   = var.secondary

  auto_accept = false

  tags = {
    Name = "primary-secondary-peering"
  }
}
```

Accepter in the secondary account:

```hcl
resource "aws_vpc_peering_connection_accepter" "secondary_accepter" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
  auto_accept               = true

  tags = {
    Name = "primary-secondary-peering-accepter"
  }
}
```

### Peering routes

Once the peering was established, I added routes in both directions:

```hcl
resource "aws_route" "primary_to_secondary" {
  provider                  = aws.primary
  route_table_id            = aws_route_table.primary_rt.id
  destination_cidr_block    = var.secondary_vpc_cidr # 10.1.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}

resource "aws_route" "secondary_to_primary" {
  provider                  = aws.secondary
  route_table_id            = aws_route_table.secondary_rt.id
  destination_cidr_block    = var.primary_vpc_cidr  # 10.0.0.0/16
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}
```

I initially duplicated the “primary → secondary” route as a second resource and also mis‑typed the resource reference (`aws.vpc_peering_connection...` instead of `aws_vpc_peering_connection...`), which would either fail at plan time or cause “route already exists” errors. Fix: keep just one route resource and use the correct reference.

---

## Security Groups and Instances

### Security groups

Each VPC got its own security group, allowing SSH from anywhere and traffic from the other VPC CIDR:

```hcl
resource "aws_security_group" "primary_sg" {
  provider    = aws.primary
  name        = "primary-vpc-sg"
  description = "Security group for Primary VPC instance"
  vpc_id      = aws_vpc.primary_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from Secondary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  ingress {
    description = "All TCP from Secondary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.secondary_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Primary-VPC-SG"
    Environment = "Demo"
  }
}

resource "aws_security_group" "secondary_sg" {
  provider    = aws.secondary
  name        = "secondary-vpc-sg"
  description = "Security group for Secondary VPC instance"
  vpc_id      = aws_vpc.secondary_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ICMP from Primary VPC"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  ingress {
    description = "All TCP from Primary VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.primary_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "Secondary-VPC-SG"
    Environment = "Demo"
  }
}
```

### EC2 instances and key pairs

Each instance used an AMI data source, the appropriate subnet and security group, and the shared key pair name `vpc-peering-demo` passed via variables:

```hcl
resource "aws_instance" "primary_instance" {
  provider               = aws.primary
  ami                    = data.aws_ami.primary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.primary_subnet.id
  vpc_security_group_ids = [aws_security_group.primary_sg.id]
  key_name               = var.primary_key_name
  user_data              = local.primary_user_data

  tags = {
    Name        = "Primary-VPC-Instance"
    Environment = "Demo"
    Region      = var.primary
  }

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}

resource "aws_instance" "secondary_instance" {
  provider               = aws.secondary
  ami                    = data.aws_ami.secondary_ami.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.secondary_subnet.id
  vpc_security_group_ids = [aws_security_group.secondary_sg.id]
  key_name               = var.secondary_key_name
  user_data              = local.secondary_user_data

  tags = {
    Name        = "Secondary-VPC-Instance"
    Environment = "Demo"
    Region      = var.secondary
  }

  depends_on = [aws_vpc_peering_connection_accepter.secondary_accepter]
}
```

---

## Problems Encountered and How They Were Fixed

### 1. “No matching EC2 VPC found”

I initially tried to look up a VPC by `tag:Name = "default"` and got “no matching EC2 VPC found” because the default VPC didn’t have that Name tag. Switching to explicitly created VPC resources with known CIDRs and tags solved it.

**Lesson:** don’t assume default VPCs are tagged; manage your own VPCs.

---

### 2. Wrong route table association ID

Error:

> InvalidRouteTableId.Malformed: Invalid id: "vpc-..." (expecting "rtb-...")

Cause: I used `aws_route_table.primary_rt.vpc_id` in `route_table_id` instead of the route table’s `.id`.

Fix:

```hcl
route_table_id = aws_route_table.primary_rt.id
```

**Lesson:** route table associations take route table IDs, not VPC IDs.

---

### 3. Invalid CIDR in internet route

Error:

> The destination CIDR block 10.1.0.0/16 is equal to or more specific than one of this VPC's CIDR blocks. This route can target only an interface or an instance.

I had mistakenly used the VPC CIDR as the destination for the IGW route, which conflicts with the implicit local route for the VPC CIDR.

Fix: use `0.0.0.0/0` as the internet route destination in each route table; keep VPC CIDRs only in the peering routes.

**Lesson:** VPC CIDRs belong in peering/TGW routes, not IGW default routes.

---

### 4. Missing `aws_vpc_peering_connection` / accepter references

At one point, I referenced `aws_vpc_peering_connection.primary_to_secondary` and `aws_vpc_peering_connection_accepter.secondary_accepter` before actually defining those resources, and also mis‑typed the resource name (`aws.vpc_peering_connection...`).

Fix: define both resources with the correct types and names, remove duplicate routes, and depend on the accepter where needed.

**Lesson:** keep your resource names consistent; Terraform will call you out if it can’t find them.

---

### 5. Route 53 hosted zone deletion failed (`HostedZoneNotEmpty`)

While cleaning up, deleting a Route 53 hosted zone failed with:

> HostedZoneNotEmpty: The specified hosted zone contains non-required resource record sets and so cannot be deleted.

Route 53 only allows zone deletion when only the NS and SOA records remain; any extra records must be deleted first.

Fix: list all records and delete non-default ones (manually or via CLI) before destroying the hosted zone.

**Lesson:** Route 53 hosted zones have to be emptied before you destroy them.

---

### 6. `InvalidKeyPair.NotFound` when launching EC2

Error:

> InvalidKeyPair.NotFound: The key pair 'vpc-peering-demo-east' does not exist

Variables and `tfvars` were fine; the problem was that I referenced key names that didn’t actually exist in the target regions.

Fix:

1. Normalized on a single key name `vpc-peering-demo` created in both regions.
2. Updated `terraform.tfvars`:

   ```hcl
   primary_key_name   = "vpc-peering-demo"
   secondary_key_name = "vpc-peering-demo"
   ```

3. Verified with `aws ec2 describe-key-pairs` in both regions.

**Lesson:** key pairs are regional; names in Terraform must match EC2 exactly.

---

## Final Verification

With everything applied:

- Both EC2 instances had public IPs and could reach the internet via their IGWs.
- From the primary instance, I could SSH to the secondary instance’s private IP (and vice versa), confirming:
  - VPC peering was active.
  - Routes in both directions were correct.
  - Security groups allowed cross‑VPC traffic.

If you’ve done something similar with modules/TGW or have ideas to improve this setup, I’d love to see your approach.
```

***

---
