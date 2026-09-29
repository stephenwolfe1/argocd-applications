SHELL          := /bin/bash -eo pipefail

CHART_DIRS     := $(sort $(patsubst %/Chart.yaml,%,$(wildcard resources/*/Chart.yaml)))
TEMPLATE_DIR   := .templates
KUBE_VERSION   ?= 1.31.0
CRD_SCHEMA_URL := https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json

.PHONY: help charts template lint validate clean

help: ## show available make targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-12s\033[0m %s\n", $$1, $$2}'

charts: ## list the charts found under resources/
	@echo "bootstrap"
	@for chart in $(CHART_DIRS); do echo "$$chart"; done

template: ## render bootstrap and every resources chart into .templates/
	@command -v helm >/dev/null || { echo "helm not found in PATH"; exit 1; }
	@mkdir -p $(TEMPLATE_DIR)
	@echo "==> bootstrap"
	@helm template bootstrap bootstrap --output-dir $(TEMPLATE_DIR) >/dev/null
	@for chart in $(CHART_DIRS); do \
		echo "==> $$chart"; \
		helm template $$(basename $$chart) $$chart --output-dir $(TEMPLATE_DIR) >/dev/null; \
	done
	@echo "rendered into $(TEMPLATE_DIR)/"

lint: ## helm lint every chart; yamllint and kubeconform run when installed
	@command -v helm >/dev/null || { echo "helm not found in PATH"; exit 1; }
	@echo "==> helm lint"
	@helm lint bootstrap
	@for chart in $(CHART_DIRS); do helm lint $$chart; done
	@if command -v yamllint >/dev/null; then \
		echo "==> yamllint"; \
		if [ -f .yamllint ]; then yamllint -c .yamllint .; else yamllint .; fi; \
	else \
		echo "==> yamllint not installed, skipping"; \
	fi
	@if command -v kubeconform >/dev/null; then \
		$(MAKE) --no-print-directory template; \
		echo "==> kubeconform (k8s $(KUBE_VERSION))"; \
		kubeconform -strict -summary -ignore-missing-schemas \
			-kubernetes-version $(KUBE_VERSION) \
			-schema-location default \
			-schema-location '$(CRD_SCHEMA_URL)' \
			$(TEMPLATE_DIR)/; \
	else \
		echo "==> kubeconform not installed, skipping"; \
	fi

validate: template ## kubectl dry-run the rendered manifests (needs cluster access)
	@command -v kubectl >/dev/null || { echo "kubectl not found in PATH"; exit 1; }
	@echo "==> kubectl apply --dry-run=client"
	@kubectl apply --dry-run=client --validate --recursive -f $(TEMPLATE_DIR)/

clean: ## remove the rendered .templates/ output
	@rm -rf $(TEMPLATE_DIR)
	@echo "removed $(TEMPLATE_DIR)/"

.DEFAULT_GOAL := help
