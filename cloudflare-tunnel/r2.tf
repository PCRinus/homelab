# R2 bucket for Terraform state storage
# Import existing bucket with: terraform import cloudflare_r2_bucket.terraform_state "<account_id>/homelab-terraform-state/eu"
resource "cloudflare_r2_bucket" "terraform_state" {
  account_id   = var.account_id
  name         = "homelab-terraform-state"
  jurisdiction = "eu"
}
