locals {
  project = "hexlet-5"

  labels = {
    project     = local.project
    environment = "study"
    managed_by  = "terraform"
  }

  github_oidc_issuer   = "https://token.actions.githubusercontent.com"
  github_oidc_jwks_url = "https://token.actions.githubusercontent.com/.well-known/jwks"
  github_oidc_audience = "https://github.com/autobol4ik"
  github_oidc_subject  = "repo:autobol4ik@306516429/devops-engineer-from-scratch-project-319@1307073429:ref:refs/heads/main"

  gwin_external_subject    = "system:serviceaccount:hexlet-5-gwin:gwin"
  logging_external_subject = "system:serviceaccount:hexlet-5-logging:hexlet-5-fluent-bit"
}
