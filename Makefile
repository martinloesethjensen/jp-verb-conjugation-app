# Utility commands for the project. `make` lists them.
#
# Variables: PYTHON (default python3), PUSH=1 to push after `make sign-commit`.

PYTHON ?= python3
PUSH   ?=

.DEFAULT_GOAL := help
.PHONY: help install-deps data data-check sign verify sign-commit keygen \
        test test-py test-swift project check-project check audio-dry clean

help: ## List the commands
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install-deps: ## Install the Python dependencies (for signing)
	$(PYTHON) -m pip install -r scripts/requirements.txt

# --- Data (data/*.json) ------------------------------------------------------

data: ## Regenerate the generated forms, forms.json and the manifest
	$(PYTHON) scripts/update_data.py

data-check: ## Verify the data is generated, valid and up to date (no writes)
	$(PYTHON) scripts/update_data.py --check

sign: ## Sign data/manifest.json with your private key
	$(PYTHON) scripts/sign_manifest.py sign

verify: ## Check data/manifest.sig against the key the app trusts
	$(PYTHON) scripts/sign_manifest.py verify

sign-commit: ## Check, sign, verify and commit data/manifest.sig (PUSH=1 to push too)
	scripts/sign_and_commit.sh $(if $(PUSH),--push)

keygen: ## Make the signing key (once; see docs/security/data-signing.md)
	$(PYTHON) scripts/sign_manifest.py keygen

# --- Tests and checks --------------------------------------------------------

test: test-py test-swift ## Run the Python and Swift tests

test-py: ## Run the Python script tests
	$(PYTHON) -m unittest discover -s scripts

test-swift: ## Run VerbKit's Swift tests (macOS only)
	cd Packages/VerbKit && swift test

check-project: ## Check project.yml is consistent
	$(PYTHON) scripts/check_project.py

check: data-check test-py verify check-project ## Run the checks CI runs, except Swift

# --- Other -------------------------------------------------------------------

project: ## Generate the Xcode project (needs xcodegen)
	scripts/generate-project.sh

audio-dry: ## List the audio clips that would be generated (no API calls)
	$(PYTHON) scripts/generate_audio.py --dry-run

clean: ## Remove Python caches
	find scripts -name __pycache__ -type d -prune -exec rm -rf {} +
