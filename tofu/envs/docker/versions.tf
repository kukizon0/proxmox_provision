terraform {
  required_version = ">= 1.10.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.9"
    }
  }
}

# 未指定なら DOCKER_HOST または unix:///var/run/docker.sock を使う
provider "docker" {}
