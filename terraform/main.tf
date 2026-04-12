terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

resource "local_file" "test" {
  content  = "Hello from Terraform via GitHub Actions"
  filename = "C:\\temp\\terraform-test.txt"
}
