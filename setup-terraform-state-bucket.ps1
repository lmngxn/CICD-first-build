# setup-terraform-state-bucket.ps1
# Creates and configures an S3 bucket for Terraform remote state.
# Usage: .\setup-terraform-state-bucket.ps1 -Profile dev-account -BucketName lmngxn-terraform-state
#        .\setup-terraform-state-bucket.ps1 -Profile stg-account  -BucketName lmngxn-terraform-state-staging

param(
    [Parameter(Mandatory)]
    [string]$Profile,

    [string]$BucketName = "lmngxn-terraform-state",
    [string]$Region     = "ap-southeast-1"
)

$ErrorActionPreference = "Stop"

Write-Host "Using profile '$Profile'" -ForegroundColor DarkGray
Write-Host "Creating bucket '$BucketName' in $Region..." -ForegroundColor Cyan
aws s3api create-bucket `
    --bucket $BucketName `
    --region $Region `
    --create-bucket-configuration LocationConstraint=$Region `
    --profile $Profile

Write-Host "Enabling versioning..." -ForegroundColor Cyan
aws s3api put-bucket-versioning `
    --bucket $BucketName `
    --versioning-configuration Status=Enabled `
    --profile $Profile

Write-Host "Enabling default encryption (AES256)..." -ForegroundColor Cyan
aws s3api put-bucket-encryption `
    --bucket $BucketName `
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' `
    --profile $Profile

Write-Host "Blocking all public access..." -ForegroundColor Cyan
aws s3api put-public-access-block `
    --bucket $BucketName `
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true `
    --profile $Profile

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