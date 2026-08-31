terraform {
  backend "s3" {
    bucket       = "lmngxn-terraform-state"
    key          = "dev/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
  }
}