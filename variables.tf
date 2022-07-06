variable "region" {
  #default region to deploy infrastructure
  type    = string
  default = "us-east-1"
}

variable "cidr" {
  default = "10.0.0.0/16"
}

variable "publicSubnetCIDR" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "privateSubnetCIDR" {
  type    = list(string)
  default = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
}

variable "environment" {
  default = "dev"
}
variable "instance_type" {
  #default instance_type to deploy
  type    = string
  default = "t2.micro"
}

variable "common_tags" {
  #default tags for deploy
  type = map(any)
  default = {
    Owner   = "ktkache-dev"
    Project = "Awesome-HTML-pagee"
  }
}

variable "allowed_ports" {
  description = "List of allowed ports"
  type        = list(any)
  default     = ["80", "443", "22", "8080"]
}

variable "app_name" {
  description = "name of application"
  type        = string
  default     = "SimpleWebPage"
}

variable "app_port" {
  #description = "Port exposed by the docker image to redirect traffic to"
  default = 80
}