terraform {
  backend "s3" {
    bucket       = "lmngxn-terraform-state-dev"
    key          = "dev/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
