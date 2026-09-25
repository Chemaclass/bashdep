SHELL=/bin/bash

-include .env

STATIC_ANALYSIS_CHECKER := $(shell which shellcheck 2> /dev/null)
LINTER_CHECKER := $(shell which ec 2> /dev/null || which editorconfig-checker 2> /dev/null)
BASHUNIT_FLAGS ?=
GIT_HOOKS_DIR = $(shell git rev-parse --git-path hooks 2> /dev/null)
PRE_COMMIT_SCRIPTS_FILE=bin/pre-commit

.DEFAULT_GOAL := help
.PHONY: help test check pre_commit/install pre_commit/run sa lint deps release release/dry-run

help: ## Show this help
	@printf "\nUsage: make [command]\n\nCommands:\n"
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_\/-]+:.*## / {printf "  %-24s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: lib/bashunit ## Run the tests (BASHUNIT_FLAGS="--filter NAME" or --simple)
	@lib/bashunit $(BASHUNIT_FLAGS) tests

check: test sa lint ## Run the full gate: test + sa + lint

pre_commit/install: ## Link the pre-commit hook into .git/hooks
	@ln -sf $(CURDIR)/$(PRE_COMMIT_SCRIPTS_FILE) $(GIT_HOOKS_DIR)/pre-commit
	@echo "pre-commit hook linked to $(PRE_COMMIT_SCRIPTS_FILE)"

pre_commit/run: check ## Hook entry point (same as check)

sa: ## Run shellcheck static analysis tool
ifndef STATIC_ANALYSIS_CHECKER
	@printf "\e[1m\e[31m%s\e[0m\n" "Shellcheck not installed: Static analysis not performed!" && exit 1
else
	@find . -type f \( -name '*.sh' -o -name 'bashdep' -o -name 'pre-commit' \) \
		-not -path './.git/*' -not -path './.claude/*' -not -path './vendor/*' \
		-not -path './lib/*' -not -path './local/*' \
		-exec shellcheck -e SC1091 -e SC2155 -C {} + \
		&& printf "\e[1m\e[32m%s\e[0m\n" "ShellCheck: OK!"
endif

lint: ## Run editorconfig linter tool
ifndef LINTER_CHECKER
	@printf "\e[1m\e[31m%s\e[0m\n" "Editorconfig not installed: Lint not performed!" && exit 1
else
	@$(LINTER_CHECKER) && printf "\e[1m\e[32m%s\e[0m\n" "editorconfig-check: OK!"
endif

deps: ## Install test dependencies from .bashdep (bashdep installs itself)
	@bash install-dependencies.sh

lib/bashunit: .bashdep
	@bash install-dependencies.sh
	@touch $@

release: ## Cut a release: make release VERSION
	@./release.sh $(filter-out $@,$(MAKECMDGOALS))

release/dry-run: ## Preview a release: make release/dry-run VERSION
	@./release.sh $(filter-out $@,$(MAKECMDGOALS)) --dry-run

# Swallow the positional version arg, but only for release goals so typos still fail.
ifneq ($(filter release release/dry-run,$(firstword $(MAKECMDGOALS))),)
%:
	@:
endif
