SWIFT_MK_DEV_DIR ?=
SWIFT_MK := .make/swift.mk
SWIFT_MK_BASE_URL ?= https://raw.githubusercontent.com/agoodkind/swift-makefile/main
SWIFT_MK_API_REPO ?= agoodkind/swift-makefile
SWIFT_MK_API_REF ?= main
SWIFT_MK_CODELOAD_BASE ?= https://codeload.github.com

SWIFT_MK_BOOTSTRAP := .make/scripts/swift-mk-bootstrap.sh

define _swift_mk_get_bootstrap
	set -euo pipefail; \
	if [[ -n "$(SWIFT_MK_DEV_DIR)" && -f "$(SWIFT_MK_DEV_DIR)/scripts/swift-mk-bootstrap.sh" ]]; then \
		mkdir -p .make/scripts; \
		cp "$(SWIFT_MK_DEV_DIR)/scripts/swift-mk-bootstrap.sh" "$(SWIFT_MK_BOOTSTRAP)"; \
	elif [[ -s "$(SWIFT_MK_BOOTSTRAP)" ]]; then \
		: ; \
	else \
		mkdir -p .make/scripts; \
		tmp_dir=$$(mktemp -d ".make/scripts/.bootstrap-fetch.XXXXXX"); \
		trap "rm -rf \"$$tmp_dir\"" EXIT; \
		if curl -fsSL --connect-timeout 5 --max-time 15 "$(SWIFT_MK_CODELOAD_BASE)/$(SWIFT_MK_API_REPO)/tar.gz/$(SWIFT_MK_API_REF)" -o "$$tmp_dir/snapshot.tar.gz" \
			&& tar -xzf "$$tmp_dir/snapshot.tar.gz" -C "$$tmp_dir" --strip-components 1 \
			&& [[ -s "$$tmp_dir/scripts/swift-mk-bootstrap.sh" ]]; then \
			mv "$$tmp_dir/scripts/swift-mk-bootstrap.sh" "$(SWIFT_MK_BOOTSTRAP)"; \
		else \
			printf "%s\n" "error: could not obtain $(SWIFT_MK_BOOTSTRAP); check network access to $(SWIFT_MK_CODELOAD_BASE)" >&2; \
			exit 1; \
		fi; \
	fi; \
	chmod +x "$(SWIFT_MK_BOOTSTRAP)"
endef

define swift_mk_trace_min
$(shell /usr/bin/env bash -c 'set -euo pipefail; \
	log_dir=".make/logs"; \
	mkdir -p "$$log_dir"; \
	log_dir=$$(cd "$$log_dir" && pwd); \
	tp="$${TRACEPARENT-}"; \
	trace=""; \
	span=""; \
	rest=$${tp#00-}; \
	if [[ "$$rest" != "$$tp" ]]; then \
		trace=$${rest%%-*}; \
		tail=$${rest#*-}; \
		span=$${tail%%-*}; \
	fi; \
	is_id() { \
		local value=$$1; \
		local expected_length=$$2; \
		local stripped; \
		if [[ $${#value} -ne "$$expected_length" ]]; then \
			return 1; \
		fi; \
		stripped=$$(printf "%s" "$$value" | tr -d "0123456789abcdef"); \
		if [[ -n "$$stripped" ]]; then \
			return 1; \
		fi; \
		if [[ -z "$$(printf "%s" "$$value" | tr -d "0")" ]]; then \
			return 1; \
		fi; \
		return 0; \
	}; \
	if ! is_id "$$trace" 32 || ! is_id "$$span" 16; then \
		trace=""; \
		span=""; \
	fi; \
	if [[ -z "$$trace" ]] && is_id "$${TRACE_ID-}" 32 && is_id "$${SPAN_ID-}" 16; then \
		trace="$$TRACE_ID"; \
		span="$$SPAN_ID"; \
	fi; \
	if [[ -z "$$trace" ]] && is_id "$${SWIFT_MK_TRACE_ID-}" 32 && is_id "$${SWIFT_MK_SPAN_ID-}" 16; then \
		trace="$$SWIFT_MK_TRACE_ID"; \
		span="$$SWIFT_MK_SPAN_ID"; \
	fi; \
	if [[ -z "$$trace" ]]; then \
		if ! trace=$$(od -An -N16 -tx1 /dev/urandom | tr -d "[:space:]"); then \
			printf "%s\n" "bootstrap.mk: od failed to read /dev/urandom for trace id" >&2; \
			exit 0; \
		fi; \
		if ! span=$$(od -An -N8 -tx1 /dev/urandom | tr -d "[:space:]"); then \
			printf "%s\n" "bootstrap.mk: od failed to read /dev/urandom for span id" >&2; \
			exit 0; \
		fi; \
	fi; \
	if ! is_id "$$trace" 32 || ! is_id "$$span" 16; then \
		printf "%s\n" "bootstrap.mk: minted ids failed validation; skipping trace export" >&2; \
		exit 0; \
	fi; \
	tp="00-$$trace-$$span-01"; \
	printf "%s\n" "$$tp" >"$$log_dir/.traceparent"; \
	prev=""; \
	if [[ -s "$$log_dir/.run" ]]; then \
		if ! IFS= read -r prev <"$$log_dir/.run"; then \
			printf "%s\n" "bootstrap.mk: failed to read $$log_dir/.run; treating as a new run" >&2; \
			prev=""; \
		fi; \
	fi; \
	if [[ "$$prev" != "$$trace" ]]; then \
		printf "%s\n" "$$trace" >"$$log_dir/.run"; \
		printf "🔎 logs=%s trace_id=%s span_id=%s\n" "$$log_dir" "$$trace" "$$span" >&2; \
	fi; \
	printf "ok %s %s %s" "$$tp" "$$trace" "$$span"')
endef

SWIFT_MK_TRACE_RESULT := $(call swift_mk_trace_min)
ifeq ($(word 1,$(SWIFT_MK_TRACE_RESULT)),ok)
TRACEPARENT := $(word 2,$(SWIFT_MK_TRACE_RESULT))
TRACE_ID := $(word 3,$(SWIFT_MK_TRACE_RESULT))
SPAN_ID := $(word 4,$(SWIFT_MK_TRACE_RESULT))
SWIFT_MK_TRACE_ID := $(TRACE_ID)
SWIFT_MK_SPAN_ID := $(SPAN_ID)
export TRACEPARENT TRACE_ID SPAN_ID SWIFT_MK_TRACE_ID SWIFT_MK_SPAN_ID
endif

ifeq ($(strip $(_SWIFT_MK_PROVISIONED)),1)
$(if $(wildcard $(SWIFT_MK_BOOTSTRAP)),,$(error swift-makefile expected $(SWIFT_MK_BOOTSTRAP); the engine snapshot is incomplete))
else
$(if $(filter ok,$(shell /usr/bin/env bash -c 'mkdir -p .make && $(call _swift_mk_get_bootstrap) && printf ok')),,$(error swift-makefile failed to obtain $(SWIFT_MK_BOOTSTRAP)))
endif

ifneq ($(strip $(SWIFT_MK_DEV_DIR)),)
$(if $(filter ok,$(shell mkdir -p .make && cp "$(SWIFT_MK_DEV_DIR)/swift.mk" "$(SWIFT_MK)" && printf ok)),,$(error swift-makefile failed to copy swift.mk from $(SWIFT_MK_DEV_DIR)))
endif

$(if $(filter ok,$(shell SWIFT_MK_API_REPO="$(SWIFT_MK_API_REPO)" SWIFT_MK_API_REF="$(SWIFT_MK_API_REF)" SWIFT_MK_MODULES="$(SWIFT_MK_MODULES)" SWIFT_MK_CODELOAD_BASE="$(SWIFT_MK_CODELOAD_BASE)" SWIFT_MK_DEV_DIR="$(SWIFT_MK_DEV_DIR)" _SWIFT_MK_PROVISIONED="$(_SWIFT_MK_PROVISIONED)" GITHUB_ACTIONS="$(GITHUB_ACTIONS)" GITHUB_RUN_ID="$(GITHUB_RUN_ID)" bash "$(SWIFT_MK_BOOTSTRAP)" >&2 && printf ok)),,$(error swift-makefile failed to provision the engine snapshot))
ifeq ($(strip $(SWIFT_MK_DEV_DIR)),)
override _SWIFT_MK_PROVISIONED := 1
endif

-include $(SWIFT_MK)
