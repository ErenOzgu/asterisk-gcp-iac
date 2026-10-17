.PHONY: help lint tf-check inventory deploy verify

help: ## Show this help
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

lint: ## yamllint, ansible-lint, shellcheck, terraform fmt
	yamllint -c .yamllint ansible .github
	cd ansible && ansible-lint
	shellcheck -S style scripts/*.sh tests/*.sh terraform/tests/*.sh
	terraform -chdir=terraform fmt -check -recursive

tf-check: ## Offline Terraform checks (no cloud credentials needed)
	cd terraform && terraform init -backend=false -input=false && terraform validate
	cd terraform && GOOGLE_OAUTH_ACCESS_TOKEN=plan-only-token terraform plan -input=false -lock=false -var-file=tests/ci.tfvars -out=tfplan
	cd terraform && terraform show -json tfplan > plan.json && tests/check_plan.sh plan.json
	cd terraform && tests/negative.sh

inventory: ## Write ansible/inventory/hosts.ini from the Terraform outputs
	scripts/make-inventory.sh

deploy: ## Configure the VM (needs the inventory and group_vars/asterisk/vault.yml)
	cd ansible && ansible-playbook site.yml --ask-vault-pass

verify: ## Run the checks on the host itself (as root, on the VM)
	sudo -E tests/verify.sh
