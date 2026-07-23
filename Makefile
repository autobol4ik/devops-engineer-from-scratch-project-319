SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

DOCKER ?= docker
TERRAFORM ?= terraform
KUBECTL ?= kubectl
HELM ?= helm

APP_SOURCE_REF := e2a10825742b2bd281051653ec72ec27a2c5494b
APP_IMAGE_REPOSITORY ?= autobol4ik/hexlet-5-bulletin-board

COMPOSE_PROJECT_NAME ?= hexlet-5-local
COMPOSE := $(DOCKER) compose --project-name "$(COMPOSE_PROJECT_NAME)" \
	--file docker-compose.yaml
LOCAL_DB_PASSWORD ?= hexlet-5-local-db-password
LOCAL_S3_ACCESS_KEY ?= hexlet5local
LOCAL_S3_SECRET_KEY ?= hexlet-5-local-s3-secret-key
COMPOSE_ENV := HEXLET_5_APP_IMAGE="$(APP_IMAGE_REPOSITORY):$(APP_SOURCE_REF)" \
	HEXLET_5_DB_PASSWORD="$(LOCAL_DB_PASSWORD)" \
	HEXLET_5_S3_ACCESS_KEY="$(LOCAL_S3_ACCESS_KEY)" \
	HEXLET_5_S3_SECRET_KEY="$(LOCAL_S3_SECRET_KEY)"
LOCAL_APPLICATION_URL ?= http://127.0.0.1:18080
LOCAL_MANAGEMENT_URL ?= http://127.0.0.1:19090

NAMESPACE ?= hexlet-5
HELM_RELEASE ?= hexlet-5
CHART_DIR := k8s/bulletin-board
PRODUCTION_VALUES := $(CHART_DIR)/values-prod.yaml
MANAGED_SECRET_NAME ?= hexlet-5-app-managed
HELM_ADOPTION_ARGS ?=
APP_SECRET_ENV_FILE ?= .env

TF_DATA_ROOT ?= /tmp/hexlet-5-terraform
BOOTSTRAP_TF_DATA := $(TF_DATA_ROOT)/bootstrap
MAIN_TF_DATA := $(TF_DATA_ROOT)/main
BOOTSTRAP_STATE ?= $(HOME)/.local/state/hexlet-5-bootstrap/terraform.tfstate
BOOTSTRAP_VAR_FILE ?= terraform.tfvars
MAIN_VAR_FILE ?= terraform.tfvars
PRODUCTION_VAR_FILE ?= production.tfvars.example
BACKEND_CONFIG ?= backend.hcl

KUBECONFIG ?= /tmp/hexlet-5-kubeconfig
export KUBECONFIG

GWIN_CHART := oci://cr.yandex/yc-marketplace/yandex-cloud/gwin/charts/gwin-chart
GWIN_CHART_VERSION := v1.8.2
ESO_CHART := oci://cr.yandex/yc-marketplace/yandex-cloud/external-secrets/charts/external-secrets
ESO_CHART_VERSION := 2.5.0-2
PROMETHEUS_CHART := oci://cr.yandex/yc-marketplace/yandex-cloud/prometheus/charts/kube-prometheus-stack
PROMETHEUS_CHART_VERSION := 86.2.3-1
FLUENT_BIT_CHART := oci://cr.yandex/yc-marketplace/yandex-cloud/fluent-bit/charts/fluent-bit
FLUENT_BIT_CHART_VERSION := 5.0.0

.PHONY: help setup check test lint boundary validate-app-source-ref \
	compose-config compose-up compose-down compose-smoke print-app-source-ref \
	terraform-fmt terraform-validate \
	terraform-bootstrap-init terraform-bootstrap-plan terraform-bootstrap-apply \
	terraform-init terraform-plan terraform-apply terraform-scale-plan \
	terraform-scale-apply kubeconfig context-check raw-secret raw-deploy \
	raw-scale raw-status raw-check observability-check platform-namespaces \
	gwin-install eso-install \
	prometheus-install fluent-bit-install helm-check helm-adopt helm-deploy \
	helm-history helm-rollback

help:
	@echo "Validation: make check"
	@echo "Local stack: make compose-up | compose-smoke | compose-down"
	@echo "Terraform: make terraform-bootstrap-plan | terraform-plan | terraform-scale-plan"
	@echo "Kubernetes: make raw-deploy | raw-scale | helm-adopt | helm-deploy"

setup: check

check: lint test

test: terraform-validate raw-check observability-check compose-config

lint: boundary validate-app-source-ref terraform-fmt helm-check

boundary:
	@for path in src frontend gradle Dockerfile build.gradle.kts \
		settings.gradle.kts gradlew gradlew.bat public versions.properties \
		ansible; do \
		test ! -e "$$path" || { \
			echo "$$path belongs in the application repository"; \
			exit 1; \
		}; \
	done

validate-app-source-ref:
	@printf '%s\n' "$(APP_SOURCE_REF)" | grep -Eq '^[0-9a-f]{40}$$'

compose-config: validate-app-source-ref
	$(COMPOSE_ENV) $(COMPOSE) config --quiet

compose-up: validate-app-source-ref
	$(COMPOSE_ENV) $(COMPOSE) up --detach --wait --wait-timeout 240

compose-down:
	$(COMPOSE_ENV) $(COMPOSE) down --remove-orphans

compose-smoke: compose-up
	curl --fail --silent --show-error \
		"$(LOCAL_MANAGEMENT_URL)/actuator/health/readiness" | \
		jq --exit-status '.status == "UP"' >/dev/null
	curl --fail --silent --show-error \
		"$(LOCAL_MANAGEMENT_URL)/actuator/prometheus" >/dev/null
	test "$$($(COMPOSE_ENV) $(COMPOSE) exec --no-TTY application id -u)" = 10001
	upload="$$(curl --fail --silent --show-error \
		--form file=@docs/evidence/dashboard.png \
		"$(LOCAL_APPLICATION_URL)/api/files/upload")"; \
	key="$$(printf '%s' "$$upload" | jq --exit-status --raw-output '.key')"; \
	object_url="$$(curl --fail --silent --show-error --get \
		--data-urlencode "key=$$key" \
		"$(LOCAL_APPLICATION_URL)/api/files/view" | \
		jq --exit-status --raw-output '.url')"; \
	curl --fail --silent --show-error "$$object_url" >/dev/null; \
	payload="$$(jq --null-input --compact-output --arg image_key "$$key" \
		'{title:"hexlet-5 compose smoke",description:"PostgreSQL and MinIO smoke",state:"PUBLISHED",contact:"smoke@example.com",price:1,imageKey:$$image_key}')"; \
	bulletin_id="$$(curl --fail --silent --show-error \
		--header 'Content-Type: application/json' \
		--request POST --data "$$payload" \
		"$(LOCAL_APPLICATION_URL)/api/bulletins" | \
		jq --exit-status --raw-output '.id')"; \
	curl --fail --silent --show-error \
		"$(LOCAL_APPLICATION_URL)/api/bulletins/$$bulletin_id" >/dev/null; \
	curl --fail --silent --show-error --request DELETE \
		"$(LOCAL_APPLICATION_URL)/api/bulletins/$$bulletin_id" >/dev/null

terraform-fmt:
	$(TERRAFORM) fmt -check -recursive terraform

terraform-validate: terraform-fmt
	mkdir -p "$(BOOTSTRAP_TF_DATA)" "$(MAIN_TF_DATA)"
	TF_DATA_DIR="$(BOOTSTRAP_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform/bootstrap init -backend=false -lockfile=readonly
	TF_DATA_DIR="$(BOOTSTRAP_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform/bootstrap validate
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform init -backend=false -lockfile=readonly
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) -chdir=terraform validate

terraform-bootstrap-init:
	install -d -m 700 "$$(dirname "$(BOOTSTRAP_STATE)")"
	mkdir -p "$(BOOTSTRAP_TF_DATA)"
	TF_DATA_DIR="$(BOOTSTRAP_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform/bootstrap init -reconfigure -lockfile=readonly \
		-backend-config="path=$(BOOTSTRAP_STATE)"

terraform-bootstrap-plan: terraform-bootstrap-init
	test -f "terraform/bootstrap/$(BOOTSTRAP_VAR_FILE)"
	TF_DATA_DIR="$(BOOTSTRAP_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform/bootstrap plan -var-file="$(BOOTSTRAP_VAR_FILE)"

terraform-bootstrap-apply: terraform-bootstrap-init
	test -f "terraform/bootstrap/$(BOOTSTRAP_VAR_FILE)"
	TF_DATA_DIR="$(BOOTSTRAP_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform/bootstrap apply -var-file="$(BOOTSTRAP_VAR_FILE)"

terraform-init:
	test -f "terraform/$(BACKEND_CONFIG)"
	test -n "$${AWS_ACCESS_KEY_ID:-}"
	test -n "$${AWS_SECRET_ACCESS_KEY:-}"
	mkdir -p "$(MAIN_TF_DATA)"
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform init -reconfigure -lockfile=readonly \
		-backend-config="$(BACKEND_CONFIG)"

terraform-plan: terraform-init
	test -f "terraform/$(MAIN_VAR_FILE)"
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform plan -var-file="$(MAIN_VAR_FILE)"

terraform-apply: terraform-init
	test -f "terraform/$(MAIN_VAR_FILE)"
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform apply -var-file="$(MAIN_VAR_FILE)"

terraform-scale-plan: terraform-init
	test -f "terraform/$(MAIN_VAR_FILE)"
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform plan -var-file="$(MAIN_VAR_FILE)" \
		-var-file="$(PRODUCTION_VAR_FILE)"

terraform-scale-apply: terraform-init
	test -f "terraform/$(MAIN_VAR_FILE)"
	TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform apply -var-file="$(MAIN_VAR_FILE)" \
		-var-file="$(PRODUCTION_VAR_FILE)"

kubeconfig: terraform-init
	cluster_id="$$(TF_DATA_DIR="$(MAIN_TF_DATA)" $(TERRAFORM) \
		-chdir=terraform output -raw kubernetes_cluster_id)"; \
	test -n "$${cluster_id}"; \
	KUBECONFIG="$(KUBECONFIG)" yc managed-kubernetes cluster get-credentials \
		--id "$${cluster_id}" --external --force

context-check:
	test -n "$(EXPECTED_CONTEXT)"
	test "$$($(KUBECTL) config current-context)" = "$(EXPECTED_CONTEXT)"

raw-secret: context-check
	test -s "$(APP_SECRET_ENV_FILE)"
	$(KUBECTL) apply --filename k8s/raw/namespace.yaml
	$(KUBECTL) --namespace "$(NAMESPACE)" create secret generic hexlet-5-app \
		--from-env-file="$(APP_SECRET_ENV_FILE)" \
		--dry-run=client --output yaml | $(KUBECTL) apply --filename -

raw-deploy: context-check validate-app-source-ref
	$(KUBECTL) kustomize k8s/raw | \
		sed 's|autobol4ik/hexlet-5-bulletin-board:REPLACE_WITH_FULL_GIT_SHA|$(APP_IMAGE_REPOSITORY):$(APP_SOURCE_REF)|g' | \
		$(KUBECTL) apply --filename -
	$(KUBECTL) --namespace "$(NAMESPACE)" rollout status \
		deployment/hexlet-5-bulletin-board --timeout=10m

raw-scale: context-check validate-app-source-ref
	[[ "$(GWIN_SECURITY_GROUP_ID)" =~ ^[a-z0-9]+$$ ]]
	$(KUBECTL) kustomize k8s/scaled | \
		sed \
			-e 's|autobol4ik/hexlet-5-bulletin-board:REPLACE_WITH_FULL_GIT_SHA|$(APP_IMAGE_REPOSITORY):$(APP_SOURCE_REF)|g' \
			-e 's|REPLACE_WITH_GWIN_SECURITY_GROUP_ID|$(GWIN_SECURITY_GROUP_ID)|g' | \
		$(KUBECTL) apply --filename -
	$(KUBECTL) --namespace "$(NAMESPACE)" rollout status \
		deployment/hexlet-5-bulletin-board --timeout=10m

raw-status: context-check
	$(KUBECTL) get nodes
	$(KUBECTL) --namespace "$(NAMESPACE)" get pods --output wide
	$(KUBECTL) --namespace "$(NAMESPACE)" get service,ingress

raw-check:
	$(KUBECTL) kustomize k8s/raw >/dev/null
	$(KUBECTL) kustomize k8s/scaled >/dev/null

observability-check:
	bash -n k8s/platform/prometheus/post-renderer.sh
	$(DOCKER) run --rm --entrypoint promtool \
		--volume "$(CURDIR)/k8s/platform/prometheus:/work:ro" \
		--workdir /work prom/prometheus:v3.12.0 check rules rules.yaml

platform-namespaces: context-check
	$(KUBECTL) apply --filename k8s/platform/namespaces.yaml

gwin-install: context-check
	test -n "$(FOLDER_ID)"
	test -n "$(GWIN_SERVICE_ACCOUNT_ID)"
	$(HELM) upgrade --install hexlet-5-gwin "$(GWIN_CHART)" \
		--version "$(GWIN_CHART_VERSION)" --namespace hexlet-5-gwin \
		--create-namespace --values k8s/platform/gwin/values.yaml \
		--set-string controller.folderId="$(FOLDER_ID)" \
		--set-string controller.ycServiceAccount.workloadIdentityFederation.serviceAccountID="$(GWIN_SERVICE_ACCOUNT_ID)" \
		--atomic --wait --timeout 10m

eso-install: context-check
	$(HELM) upgrade --install hexlet-5-eso "$(ESO_CHART)" \
		--version "$(ESO_CHART_VERSION)" --namespace hexlet-5-eso \
		--create-namespace --values k8s/platform/external-secrets/values.yaml \
		--atomic --wait --timeout 10m

prometheus-install: context-check
	test -n "$(MONITORING_WORKSPACE_ID)"
	$(KUBECTL) --namespace hexlet-5-monitoring get \
		secret/hexlet-5-monitoring-credentials >/dev/null
	$(HELM) upgrade --install hexlet-5-monitoring "$(PROMETHEUS_CHART)" \
		--version "$(PROMETHEUS_CHART_VERSION)" \
		--namespace hexlet-5-monitoring --create-namespace \
		--values k8s/platform/prometheus/values.yaml \
		--set-string prometheusWorkspaceId="$(MONITORING_WORKSPACE_ID)" \
		--post-renderer k8s/platform/prometheus/post-renderer.sh \
		--atomic --wait --timeout 15m

fluent-bit-install: context-check
	test -n "$(LOG_GROUP_ID)"
	test -n "$(LOGGING_SERVICE_ACCOUNT_ID)"
	$(HELM) upgrade --install hexlet-5-logging "$(FLUENT_BIT_CHART)" \
		--version "$(FLUENT_BIT_CHART_VERSION)" \
		--namespace hexlet-5-logging --create-namespace \
		--values k8s/platform/fluent-bit/values.yaml \
		--set-string loggingGroupId="$(LOG_GROUP_ID)" \
		--set-string ycServiceAccount.workloadIdentityFederation.serviceAccountID="$(LOGGING_SERVICE_ACCOUNT_ID)" \
		--atomic --wait --timeout 10m

helm-check:
	$(HELM) lint "$(CHART_DIR)" \
		--set-string image.tag="$(APP_SOURCE_REF)"
	$(HELM) template "$(HELM_RELEASE)" "$(CHART_DIR)" \
		--namespace "$(NAMESPACE)" \
		--set-string image.tag="$(APP_SOURCE_REF)" >/dev/null
	$(HELM) lint "$(CHART_DIR)" --values "$(PRODUCTION_VALUES)" \
		--set-string image.tag="$(APP_SOURCE_REF)" \
		--set-string ingress.securityGroupId=hexlet-5-validation \
		--set-string externalSecret.lockboxId=hexlet5validation
	$(HELM) template "$(HELM_RELEASE)" "$(CHART_DIR)" \
		--namespace "$(NAMESPACE)" --values "$(PRODUCTION_VALUES)" \
		--set-string image.tag="$(APP_SOURCE_REF)" \
		--set-string ingress.securityGroupId=hexlet-5-validation \
		--set-string externalSecret.lockboxId=hexlet5validation >/dev/null

helm-adopt: HELM_ADOPTION_ARGS := --take-ownership
helm-adopt: helm-deploy

helm-deploy: context-check validate-app-source-ref
	test -n "$(GWIN_SECURITY_GROUP_ID)"
	test -n "$(LOCKBOX_ID)"
	$(HELM) upgrade --install "$(HELM_RELEASE)" "$(CHART_DIR)" \
		--namespace "$(NAMESPACE)" --create-namespace \
		--values "$(PRODUCTION_VALUES)" \
		--set-string image.repository="$(APP_IMAGE_REPOSITORY)" \
		--set-string image.tag="$(APP_SOURCE_REF)" \
		--set-string existingSecret="$(MANAGED_SECRET_NAME)" \
		--set-string externalSecret.targetSecretName="$(MANAGED_SECRET_NAME)" \
		--set-string ingress.securityGroupId="$(GWIN_SECURITY_GROUP_ID)" \
		--set-string externalSecret.lockboxId="$(LOCKBOX_ID)" \
		$(HELM_ADOPTION_ARGS) --atomic --wait --timeout 10m
	$(KUBECTL) --namespace "$(NAMESPACE)" wait \
		--for=condition=Ready externalsecret/hexlet-5-bulletin-board \
		--timeout=5m
	$(KUBECTL) --namespace "$(NAMESPACE)" rollout status \
		deployment/hexlet-5-bulletin-board --timeout=10m

helm-history: context-check
	$(HELM) history "$(HELM_RELEASE)" --namespace "$(NAMESPACE)"

helm-rollback: context-check
	test -n "$(REVISION)"
	$(HELM) rollback "$(HELM_RELEASE)" "$(REVISION)" \
		--namespace "$(NAMESPACE)" --wait --timeout 10m
	$(KUBECTL) --namespace "$(NAMESPACE)" rollout status \
		deployment/hexlet-5-bulletin-board --timeout=10m

print-app-source-ref:
	@printf '%s\n' "$(APP_SOURCE_REF)"
