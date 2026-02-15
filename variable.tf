# variable "enviroment" {
#   default = "dev"
#   type = string
# }

# # variable "instance_count" {
# #   description = "Number of EC2 instances to create"
# #   type = number
# # }

# variable "region" {
#   type = string
#   default = "us-east-1"
# }

# variable "monitoring" {
#   description = "Enabling detailed monitoring on ec2 instances"
#   type = bool
#   default = true
# }

# variable "associate_public_ip_address" {
#   type = bool
#   default = true
# }

# variable "cidr_block" {
#   description = "cidr block for the vpc"
#   type = list(string)
#   default = ["10.0.0.0/16","192.168.0.0/16","172.16.0.0/12"]
# }


# variable "allowed_vm_type" {
#   description = "list of allowed vm types"
#   type = list(string)
#   default = ["t2.micro","t3.micro","t2.small","t3.small"]
# }

# variable "allowed_region" {
#   description = "list of allowed aws regions"
#   type = set(string)
#   default = [ "us-east-1" ,"us-east-2" ,"us-east-3","us-east-1"]
# }


# variable "tags" {
#   type = map(string)
#   default = {
#     Enviroment = "var.enviroment"
#     Created    = "terraform"
#   }
 
# }

# variable "ingress_value" {
#   type = tuple([ number,string,number ])
#   default = [ 443, "tcp", 443 ]
# }

# variable "config" {
#   type = object({
#     region = string
#     monitoring=bool
#     instance_count=number
#   })
#   default = {
#     region = "us-east-1"
#     monitoring = true
#     instance_count = 1
#   }
# }

# variable "bucket_name" {
#   description = "s3 bucket for demo project"
#   type = string
#   default = "terraformbysmartjosh"
# }

# variable "bucket_name_set" {
#   description = "list of s3 bucket names to create"
#   type = set(string)
#   default = [ "my_smart_bucket3", "my_smart_bucket4"]
# }

variable "primary" {
  type = string
  default = "us-east-1"
}

variable "secondary" {
  type = string
  default = "us-west-2"
}

variable "primary_vpc_cidr" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "secondary_vpc_cidr" {
  description = "CIDR block for the primary VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "primary_subnet_cidr" {
  description = "CIDR block for the primary subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "secondary_subnet_cidr" {
  description = "CIDR block for the secondary subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

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