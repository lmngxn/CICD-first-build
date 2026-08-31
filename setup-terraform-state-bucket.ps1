# setup-terraform-state-bucket.ps1
# Creates and configures an S3 bucket for Terraform remote state.
# Usage: .\setup-terraform-state-bucket.ps1

$ErrorActionPreference = "Stop"

$BucketName = "lmngxn-terraform-state"
$Region     = "ap-southeast-1"

Write-Host "Creating bucket '$BucketName' in $Region..." -ForegroundColor Cyan
aws s3api create-bucket `
    --bucket $BucketName `
    --region $Region `
    --create-bucket-configuration LocationConstraint=$Region

Write-Host "Enabling versioning..." -ForegroundColor Cyan
aws s3api put-bucket-versioning `
    --bucket $BucketName `
    --versioning-configuration Status=Enabled

Write-Host "Enabling default encryption (AES256)..." -ForegroundColor Cyan
aws s3api put-bucket-encryption `
    --bucket $BucketName `
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

Write-Host "Blocking all public access..." -ForegroundColor Cyan
aws s3api put-public-access-block `
    --bucket $BucketName `
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

Write-Host ""
Write-Host "Done. Bucket '$BucketName' is ready for use as a Terraform backend." -ForegroundColor Green
Write-Host ""
Write-Host "Add this to your Terraform config:" -ForegroundColor Yellow
Write-Host @"
terraform {
  backend "s3" {
    bucket       = "$BucketName"
    key          = "terraform.tfstate"
    region       = "$Region"
    encrypt      = true
    use_lockfile = true   # requires Terraform >= 1.11
  }
}
"@