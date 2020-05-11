## Copyright 2017 Istio Authors
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

#-----------------------------------------------------------------------------
# Global Variables
#-----------------------------------------------------------------------------
ISTIO_GO := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
export ISTIO_GO
SHELL := /bin/bash -o pipefail

VERSION ?= 1.5-dev

# Base version of Istio image to use
BASE_VERSION ?= 1.5-dev.3

export GO111MODULE ?= on
export GOPROXY ?= https://proxy.golang.org
export GOSUMDB ?= sum.golang.org

ISTIO_CNI_HUB ?= gcr.io/istio-testing
export ISTIO_CNI_HUB
ISTIO_CNI_TAG ?= latest
export ISTIO_CNI_TAG

# cumulatively track the directories/files to delete after a clean
DIRS_TO_CLEAN:=
FILES_TO_CLEAN:=

# If GOPATH is not set by the env, set it to a sane value
GOPATH ?= $(shell cd ${ISTIO_GO}/../../..; pwd)
export GOPATH

# If GOPATH is made up of several paths, use the first one for our targets in this Makefile
GO_TOP := $(shell echo ${GOPATH} | cut -d ':' -f1)
export GO_TOP

GO ?= go

GOARCH_LOCAL := $(TARGET_ARCH)
GOOS_LOCAL := $(TARGET_OS)

export ENABLE_COREDUMP ?= false

# NOTE: env var EXTRA_HELM_SETTINGS can contain helm chart override settings, example:
# EXTRA_HELM_SETTINGS="--set istio-cni.excludeNamespaces={} --set-string istio-cni.tag=v0.1-dev-foo"

#-----------------------------------------------------------------------------
# Output control
#-----------------------------------------------------------------------------
# Invoke make VERBOSE=1 to enable echoing of the command being executed
export VERBOSE ?= 0
# Place the variable Q in front of a command to control echoing of the command being executed.
Q = $(if $(filter 1,$VERBOSE),,@)
# Use the variable H to add a header (equivalent to =>) to informational output
H = $(shell printf "\033[34;1m=>\033[0m")

ifeq ($(origin DEBUG), undefined)
  BUILDTYPE_DIR:=release
else ifeq ($(DEBUG),0)
  BUILDTYPE_DIR:=release
else
  BUILDTYPE_DIR:=debug
  export GCFLAGS:=all=-N -l
  $(info $(H) Build with debugger information)
endif

# Optional file including user-specific settings (HUB, TAG, etc)
-include .istiorc.mk

# Environment for tests, the directory containing istio and deps binaries.
# Typically same as GOPATH/bin, so tests work seemlessly with IDEs.

export ISTIO_BIN=$(GOBIN)
# Using same package structure as pkg/

export ISTIO_OUT:=$(TARGET_OUT)
export ISTIO_OUT_LINUX:=$(TARGET_OUT_LINUX)

# LOCAL_OUT should point to architecture where we are currently running versus the desired.
# This is used when we need to run a build artifact during tests or later as part of another
# target. If we are running in the Linux build container on non Linux hosts, we add the
# linux binaries to the build dependencies, BUILD_DEPS, which can be added to other targets
# that would need the Linux binaries (ex. tests).
BUILD_DEPS:=
ifeq ($(IN_BUILD_CONTAINER),1)
  export LOCAL_OUT := $(ISTIO_OUT_LINUX)
  ifneq ($(GOOS_LOCAL),"linux")
    BUILD_DEPS += build-linux
  endif
else
  export LOCAL_OUT := $(ISTIO_OUT)
endif

export HELM=helm
export ARTIFACTS ?= $(ISTIO_OUT)
export JUNIT_OUT ?= $(ARTIFACTS)/junit.xml
export REPO_ROOT := $(shell git rev-parse --show-toplevel)

# Make directories needed by the build system
$(shell mkdir -p $(ISTIO_OUT))
$(shell mkdir -p $(ISTIO_OUT_LINUX))
$(shell mkdir -p $(ISTIO_OUT_LINUX)/logs)
$(shell mkdir -p $(dir $(JUNIT_OUT)))

# scratch dir: this shouldn't be simply 'docker' since that's used for docker.save to store tar.gz files
ISTIO_DOCKER:=${ISTIO_OUT_LINUX}/docker_temp

# scratch dir for building isolated images. Please don't remove it again - using
# ISTIO_DOCKER results in slowdown, all files (including multiple copies of envoy) will be
# copied to the docker temp container - even if you add only a tiny file, >1G of data will
# be copied, for each docker image.
DOCKER_BUILD_TOP:=${ISTIO_OUT_LINUX}/docker_build
DOCKERX_BUILD_TOP:=${ISTIO_OUT_LINUX}/dockerx_build

# dir where tar.gz files from docker.save are stored
ISTIO_DOCKER_TAR:=${ISTIO_OUT_LINUX}/release/docker

# Populate the git version for istio/proxy (i.e. Envoy)
ifeq ($(PROXY_REPO_SHA),)
  export PROXY_REPO_SHA:=$(shell grep PROXY_REPO_SHA istio.deps  -A 4 | grep lastStableSHA | cut -f 4 -d '"')
endif

# Envoy binary variables Keep the default URLs up-to-date with the latest push from istio/proxy.

export ISTIO_ENVOY_BASE_URL ?= https://storage.googleapis.com/istio-build/proxy

# OS-neutral vars. These currently only work for linux.
export ISTIO_ENVOY_VERSION ?= ${PROXY_REPO_SHA}
export ISTIO_ENVOY_DEBUG_URL ?= $(ISTIO_ENVOY_BASE_URL)/envoy-debug-$(ISTIO_ENVOY_VERSION).tar.gz
export ISTIO_ENVOY_RELEASE_URL ?= $(ISTIO_ENVOY_BASE_URL)/envoy-alpha-$(ISTIO_ENVOY_VERSION).tar.gz

# Envoy Linux vars.
export ISTIO_ENVOY_LINUX_VERSION ?= ${ISTIO_ENVOY_VERSION}
export ISTIO_ENVOY_LINUX_DEBUG_URL ?= ${ISTIO_ENVOY_DEBUG_URL}
export ISTIO_ENVOY_LINUX_RELEASE_URL ?= ${ISTIO_ENVOY_RELEASE_URL}
# Variables for the extracted debug/release Envoy artifacts.
export ISTIO_ENVOY_LINUX_DEBUG_DIR ?= ${TARGET_OUT_LINUX}/debug
export ISTIO_ENVOY_LINUX_DEBUG_NAME ?= envoy-debug-${ISTIO_ENVOY_LINUX_VERSION}
export ISTIO_ENVOY_LINUX_DEBUG_PATH ?= ${ISTIO_ENVOY_LINUX_DEBUG_DIR}/${ISTIO_ENVOY_LINUX_DEBUG_NAME}
export ISTIO_ENVOY_LINUX_RELEASE_DIR ?= ${TARGET_OUT_LINUX}/release
export ISTIO_ENVOY_LINUX_RELEASE_NAME ?= envoy-${ISTIO_ENVOY_VERSION}
export ISTIO_ENVOY_LINUX_RELEASE_PATH ?= ${ISTIO_ENVOY_LINUX_RELEASE_DIR}/${ISTIO_ENVOY_LINUX_RELEASE_NAME}

# MOSN generic vars.
#export ISTIO_MOSN_BASE_URL ?= https://github.com/mosn/mosn/releases/download/
export ISTIO_MOSN_BASE_URL ?= https://github.com/wangfakang/mosn.bin/releases/download/
export ISTIO_MOSN_VERSION ?= 0.10.0
export ISTIO_MOSN_URL ?= ${ISTIO_MOSN_BASE_URL}/${ISTIO_MOSN_VERSION}/mosn
export ISTIO_MOSN_LINUX_PATH ?= ${ISTIO_ENVOY_LINUX_RELEASE_DIR}/mosn


# Envoy macOS vars.
# TODO Change url when official envoy release for macOS is available
export ISTIO_ENVOY_MACOS_VERSION ?= 1.0.2
export ISTIO_ENVOY_MACOS_RELEASE_URL ?= https://github.com/istio/proxy/releases/download/${ISTIO_ENVOY_MACOS_VERSION}/istio-proxy-${ISTIO_ENVOY_MACOS_VERSION}-macos.tar.gz
# Variables for the extracted debug/release Envoy artifacts.
export ISTIO_ENVOY_MACOS_RELEASE_DIR ?= ${TARGET_OUT}/release
export ISTIO_ENVOY_MACOS_RELEASE_NAME ?= envoy-${ISTIO_ENVOY_MACOS_VERSION}
export ISTIO_ENVOY_MACOS_RELEASE_PATH ?= ${ISTIO_ENVOY_MACOS_RELEASE_DIR}/${ISTIO_ENVOY_MACOS_RELEASE_NAME}

# Allow user-override for a local Envoy build.
export USE_LOCAL_PROXY ?= 0
ifeq ($(USE_LOCAL_PROXY),1)
  export ISTIO_ENVOY_LOCAL ?= $(realpath ${ISTIO_GO}/../proxy/bazel-bin/src/envoy/envoy)
  # Point the native paths to the local envoy build.
  ifeq ($(GOOS_LOCAL), Darwin)
    export ISTIO_ENVOY_MACOS_RELEASE_DIR = $(dir ${ISTIO_ENVOY_LOCAL})
    export ISTIO_ENVOY_MACOS_RELEASE_PATH = ${ISTIO_ENVOY_LOCAL}
  else
    export ISTIO_ENVOY_LINUX_DEBUG_DIR = $(dir ${ISTIO_ENVOY_LOCAL})
    export ISTIO_ENVOY_LINUX_RELEASE_DIR = $(dir ${ISTIO_ENVOY_LOCAL})
    export ISTIO_ENVOY_LINUX_DEBUG_PATH = ${ISTIO_ENVOY_LOCAL}
    export ISTIO_ENVOY_LINUX_RELEASE_PATH = ${ISTIO_ENVOY_LOCAL}
  endif
endif

GO_VERSION_REQUIRED:=1.10

HUB?=istio
ifeq ($(HUB),)
  $(error "HUB cannot be empty")
endif

# If tag not explicitly set in users' .istiorc.mk or command line, default to the git sha.
TAG ?= $(shell git rev-parse --verify HEAD)
ifeq ($(TAG),)
  $(error "TAG cannot be empty")
endif

VARIANT :=
ifeq ($(VARIANT),)
  TAG_VARIANT:=${TAG}
else
  TAG_VARIANT:=${TAG}-${VARIANT}
endif

PULL_POLICY ?= IfNotPresent
ifeq ($(TAG),latest)
  PULL_POLICY = Always
endif
ifeq ($(PULL_POLICY),)
  $(error "PULL_POLICY cannot be empty")
endif

include operator/operator.mk

.PHONY: default
default: init build test

.PHONY: init
# Downloads envoy, based on the SHA defined in the base pilot Dockerfile
init: $(ISTIO_OUT)/istio_is_init
	mkdir -p ${TARGET_OUT}/logs
	mkdir -p ${TARGET_OUT}/release

# I tried to make this dependent on what I thought was the appropriate
# lock file, but it caused the rule for that file to get run (which
# seems to be about obtaining a new version of the 3rd party libraries).
$(ISTIO_OUT)/istio_is_init: bin/init.sh istio.deps | $(ISTIO_OUT)
	ISTIO_OUT=$(ISTIO_OUT) ISTIO_BIN=$(ISTIO_BIN) GOOS_LOCAL=$(GOOS_LOCAL) bin/init.sh
	touch $(ISTIO_OUT)/istio_is_init

# init.sh downloads envoy and webassembly plugins
${ISTIO_OUT}/envoy: init
${ISTIO_ENVOY_LINUX_DEBUG_PATH}: init
${ISTIO_ENVOY_LINUX_RELEASE_PATH}: init
${ISTIO_ENVOY_MACOS_RELEASE_PATH}: init

# Pull dependencies, based on the checked in Gopkg.lock file.
# Developers must manually run `dep ensure` if adding new deps
depend: init | $(ISTIO_OUT)

DIRS_TO_CLEAN := $(ISTIO_OUT)
DIRS_TO_CLEAN += $(ISTIO_OUT_LINUX)

$(OUTPUT_DIRS):
	@mkdir -p $@

.PHONY: ${GEN_CERT}
GEN_CERT := ${ISTIO_BIN}/generate_cert
${GEN_CERT}:
	GOOS=$(GOOS_LOCAL) && GOARCH=$(GOARCH_LOCAL) && CGO_ENABLED=1 common/scripts/gobuild.sh $@ ./security/tools/generate_cert

#-----------------------------------------------------------------------------
# Target: precommit
#-----------------------------------------------------------------------------
.PHONY: precommit format format.gofmt format.goimports lint buildcache

# Target run by the pre-commit script, to automate formatting and lint
# If pre-commit script is not used, please run this manually.
precommit: format lint

format: fmt

fmt: format-go format-python tidy-go

# Build with -i to store the build caches into $GOPATH/pkg
buildcache:
	GOBUILDFLAGS=-i $(MAKE) -e -f Makefile.core.mk build

# List of all binaries to build
BINARIES:=./istioctl/cmd/istioctl \
  ./pilot/cmd/pilot-discovery \
  ./pilot/cmd/pilot-agent \
  ./sidecar-injector/cmd/sidecar-injector \
  ./mixer/cmd/mixs \
  ./mixer/cmd/mixc \
  ./mixer/tools/mixgen \
  ./galley/cmd/galley \
  ./security/cmd/node_agent \
  ./security/cmd/node_agent_k8s \
  ./security/cmd/istio_ca \
  ./security/tools/sdsclient \
  ./pkg/test/echo/cmd/client \
  ./pkg/test/echo/cmd/server \
  ./mixer/test/policybackend \
  ./tools/istio-iptables \
  ./tools/istio-clean-iptables \
  ./operator/cmd/operator

# List of binaries included in releases
RELEASE_BINARIES:=pilot-discovery pilot-agent sidecar-injector mixc mixs mixgen node_agent node_agent_k8s istio_ca istioctl galley sdsclient

.PHONY: build
build: depend
	STATIC=0 GOOS=$(GOOS_LOCAL) GOARCH=$(GOARCH_LOCAL) LDFLAGS='-extldflags -static -s -w' common/scripts/gobuild.sh $(ISTIO_OUT)/ $(BINARIES)

# The build-linux target is responsible for building binaries used within containers.
# This target should be expanded upon as we add more Linux architectures: i.e. buld-arm64.
# Then a new build target can be created such as build-container-bin that builds these
# various platform images.
.PHONY: build-linux
build-linux: depend
	STATIC=0 GOOS=linux GOARCH=amd64 LDFLAGS='-extldflags -static -s -w' common/scripts/gobuild.sh $(ISTIO_OUT_LINUX)/ $(BINARIES)

# Create targets for ISTIO_OUT_LINUX/binary
# There are two use cases here:
# * Building all docker images (generally in CI). In this case we want to build everything at once, so they share work
# * Building a single docker image (generally during dev). In this case we just want to build the single binary alone
BUILD_ALL ?= true
define build-linux
.PHONY: $(ISTIO_OUT_LINUX)/$(shell basename $(1))
ifeq ($(BUILD_ALL),true)
$(ISTIO_OUT_LINUX)/$(shell basename $(1)): build-linux
else
$(ISTIO_OUT_LINUX)/$(shell basename $(1)): $(ISTIO_OUT_LINUX)
	STATIC=0 GOOS=linux GOARCH=amd64 LDFLAGS='-extldflags -static -s -w' common/scripts/gobuild.sh $(ISTIO_OUT_LINUX)/ $(1)
endif
endef

$(foreach bin,$(BINARIES),$(eval $(call build-linux,$(bin))))

# Create helper targets for each binary, like "pilot-discovery"
# As an optimization, these still build everything
$(foreach bin,$(BINARIES),$(shell basename $(bin))): build

MARKDOWN_LINT_WHITELIST=localhost:8080,storage.googleapis.com/istio-artifacts/pilot/,http://ratings.default.svc.cluster.local:9080/ratings

# To save on memory, run for each folder
lint-go-split:
	@golangci-lint run -c ./common/config/.golangci.yml ./galley/...
	@golangci-lint run -c ./common/config/.golangci.yml ./istioctl/...
	@golangci-lint run -c ./common/config/.golangci.yml ./mixer/...
	@golangci-lint run -c ./common/config/.golangci.yml ./pilot/...
	@golangci-lint run -c ./common/config/.golangci.yml ./pkg/...
	@golangci-lint run -c ./common/config/.golangci.yml ./samples/...
	@golangci-lint run -c ./common/config/.golangci.yml ./security/...
	@golangci-lint run -c ./common/config/.golangci.yml ./sidecar-injector/...
	@golangci-lint run -c ./common/config/.golangci.yml ./tests/...
	@golangci-lint run -c ./common/config/.golangci.yml ./tools/...
	@golangci-lint run -c ./common/config/.golangci.yml ./operator/...

lint-helm-global:
	find manifests -name 'Chart.yaml' -print0 | ${XARGS} -L 1 dirname | xargs -r helm lint --strict -f manifests/global.yaml

lint: lint-python lint-copyright-banner lint-scripts lint-go-split lint-dockerfiles lint-markdown lint-yaml lint-licenses lint-helm-global
	@bin/check_helm.sh
	@bin/check_samples.sh
	@bin/check_dashboards.sh
	@go run mixer/tools/adapterlinter/main.go ./mixer/adapter/...
	@testlinter
	@envvarlinter galley istioctl mixer pilot security sidecar-injector

go-gen:
	@mkdir -p /tmp/bin
	@go build -o /tmp/bin/mixgen "${REPO_ROOT}/mixer/tools/mixgen/main.go"
	@PATH="${PATH}":/tmp/bin go generate ./...

gen-charts:
	@operator/scripts/run_update_charts.sh

refresh-goldens:
	@REFRESH_GOLDEN=true go test ${GOBUILDFLAGS} ./operator/...
	@REFRESH_GOLDEN=true go test ${GOBUILDFLAGS} ./pkg/kube/inject/...

update-golden: refresh-goldens

gen: go-gen mirror-licenses format update-crds operator-proto gen-charts update-golden

gen-check: gen check-clean-repo

#-----------------------------------------------------------------------------
# Target: go build
#-----------------------------------------------------------------------------

# gobuild script uses custom linker flag to set the variables.
# Params: OUT VERSION_PKG SRC

RELEASE_LDFLAGS='-extldflags -static -s -w'
DEBUG_LDFLAGS='-extldflags "-static"'

# Non-static istioctl targets. These are typically a build artifact.
${ISTIO_OUT}/release/istioctl-linux: depend
	STATIC=0 GOOS=linux LDFLAGS=$(RELEASE_LDFLAGS) common/scripts/gobuild.sh $@ ./istioctl/cmd/istioctl
${ISTIO_OUT}/release/istioctl-osx: depend
	STATIC=0 GOOS=darwin LDFLAGS=$(RELEASE_LDFLAGS) common/scripts/gobuild.sh $@ ./istioctl/cmd/istioctl
${ISTIO_OUT}/release/istioctl-win.exe: depend
	STATIC=0 GOOS=windows LDFLAGS=$(RELEASE_LDFLAGS) common/scripts/gobuild.sh $@ ./istioctl/cmd/istioctl

# generate the istioctl completion files
${ISTIO_OUT}/release/istioctl.bash: istioctl
	${LOCAL_OUT}/istioctl collateral --bash && \
	mv istioctl.bash ${ISTIO_OUT}/release/istioctl.bash

${ISTIO_OUT}/release/_istioctl: istioctl
	${LOCAL_OUT}/istioctl collateral --zsh && \
	mv _istioctl ${ISTIO_OUT}/release/_istioctl

.PHONY: binaries-test
binaries-test:
	go test ${GOBUILDFLAGS} ./tests/binary/... -v --base-dir ${ISTIO_OUT} --binaries="$(RELEASE_BINARIES)"

# istioctl-all makes all of the non-static istioctl executables for each supported OS
.PHONY: istioctl-all
istioctl-all: ${ISTIO_OUT}/release/istioctl-linux ${ISTIO_OUT}/release/istioctl-osx ${ISTIO_OUT}/release/istioctl-win.exe

.PHONY: istioctl.completion
istioctl.completion: ${ISTIO_OUT}/release/istioctl.bash ${ISTIO_OUT}/release/_istioctl

# istioctl-install builds then installs istioctl into $GOPATH/BIN
# Used for debugging istioctl during dev work
.PHONY: istioctl-install-container
istioctl-install-container: istioctl

#-----------------------------------------------------------------------------
# Target: test
#-----------------------------------------------------------------------------

.PHONY: test

JUNIT_REPORT := $(shell which go-junit-report 2> /dev/null || echo "${ISTIO_BIN}/go-junit-report")

${ISTIO_BIN}/go-junit-report:
	@echo "go-junit-report not found. Installing it now..."
	unset GOOS && unset GOARCH && CGO_ENABLED=1 go get -u github.com/jstemmer/go-junit-report

with_junit_report: | $(JUNIT_REPORT)
	$(MAKE) -e $(TARGET) 2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# Run coverage tests
ifeq ($(WHAT),)
       TEST_OBJ = common-test pilot-test mixer-test security-test galley-test istioctl-test operator-test
else
       TEST_OBJ = selected-pkg-test
endif
test: | $(JUNIT_REPORT)
	KUBECONFIG="$${KUBECONFIG:-$${REPO_ROOT}/tests/util/kubeconfig}" \
	$(MAKE) -e -f Makefile.core.mk --keep-going $(TEST_OBJ) \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

# TODO: remove the racetest targets and just have *-test targets that call race

.PHONY: pilot-test
pilot-test: pilot-racetest

.PHONY: istioctl-test
istioctl-test: istioctl-racetest

.PHONY: operator-test
operator-test:
	go test ${GOBUILDFLAGS} ${T} ./operator/...

.PHONY: mixer-test
mixer-test: mixer-racetest

# Galley test is not using -race yet. See https://github.com/istio/istio/issues/20110
.PHONY: galley-test
galley-test:
	go test ${GOBUILDFLAGS} ${T} ./galley/...

.PHONY: security-test
security-test: security-racetest

.PHONY: common-test
common-test: common-racetest

.PHONY: selected-pkg-test
selected-pkg-test:
	find ${WHAT} -name "*_test.go" | xargs -I {} dirname {} | uniq | xargs -I {} go test ${GOBUILDFLAGS} ${T} -race ./{}

#-----------------------------------------------------------------------------
# Target: coverage
#-----------------------------------------------------------------------------

.PHONY: coverage

# Run coverage tests
coverage: pilot-coverage mixer-coverage security-coverage galley-coverage common-coverage istioctl-coverage

coverage-diff:
	./bin/codecov_diff.sh

.PHONY: pilot-coverage
pilot-coverage:
	bin/codecov.sh pilot

.PHONY: istioctl-coverage
istioctl-coverage:
	bin/codecov.sh istioctl

.PHONY: mixer-coverage
mixer-coverage:
	bin/codecov.sh mixer

.PHONY: galley-coverage
galley-coverage:
	bin/codecov.sh galley

.PHONY: security-coverage
security-coverage:
	bin/codecov.sh security/pkg
	bin/codecov.sh security/cmd

.PHONY: common-coverage
common-coverage:
	bin/codecov.sh pkg

#-----------------------------------------------------------------------------
# Target: go test -race
#-----------------------------------------------------------------------------

.PHONY: racetest

RACE_TESTS ?= pilot-racetest mixer-racetest security-racetest galley-test common-racetest istioctl-racetest operator-racetest
racetest: $(JUNIT_REPORT)
	$(MAKE) -e -f Makefile.core.mk --keep-going $(RACE_TESTS) \
	2>&1 | tee >($(JUNIT_REPORT) > $(JUNIT_OUT))

.PHONY: pilot-racetest
pilot-racetest:
	go test ${GOBUILDFLAGS} ${T} -race ./pilot/...

.PHONY: istioctl-racetest
istioctl-racetest:
	go test ${GOBUILDFLAGS} ${T} -race ./istioctl/...

.PHONY: operator-racetest
operator-racetest:
	RACE_TEST=true go test ${GOBUILDFLAGS} ${T} -race ./operator/...

.PHONY: mixer-racetest
mixer-racetest:
	go test ${GOBUILDFLAGS} ${T} -race ./mixer/...

.PHONY: galley-racetest
galley-racetest:
	go test ${GOBUILDFLAGS} ${T} -race ./galley/...

.PHONY: security-racetest
security-racetest:
	go test ${GOBUILDFLAGS} ${T} -race ./security/pkg/... ./security/cmd/...

.PHONY: common-racetest
common-racetest: ${BUILD_DEPS}
	# Execute bash shell unit tests scripts
	LOCAL_OUT=$(LOCAL_OUT) ./tests/scripts/istio-iptables-test.sh
	go test ${GOBUILDFLAGS} ${T} -race ./pkg/... ./tests/common/... ./tools/istio-iptables/...

#-----------------------------------------------------------------------------
# Target: clean
#-----------------------------------------------------------------------------
.PHONY: clean

clean:
	rm -rf $(DIRS_TO_CLEAN)
	rm -f $(FILES_TO_CLEAN)

#-----------------------------------------------------------------------------
# Target: docker
#-----------------------------------------------------------------------------
.PHONY: push artifacts

# for now docker is limited to Linux compiles - why ?
include tools/istio-docker.mk

push: docker.push

$(HOME)/.helm:
	$(HELM) init --client-only

# create istio-init.yaml
istio-init.yaml: $(HOME)/.helm
	cat install/kubernetes/namespace.yaml > install/kubernetes/$@
	cat install/kubernetes/helm/istio-init/files/crd-* >> install/kubernetes/$@
	$(HELM) template --name=istio --namespace=istio-system \
		--set-string global.tag=${TAG_VARIANT} \
		--set-string global.hub=${HUB} \
		install/kubernetes/helm/istio-init >> install/kubernetes/$@

# creates istio-demo.yaml istio-remote.yaml
# Ensure that values-$filename is present in install/kubernetes/helm/istio
istio-demo.yaml istio-remote.yaml istio-minimal.yaml: $(HOME)/.helm
	cat install/kubernetes/namespace.yaml > install/kubernetes/$@
	cat install/kubernetes/helm/istio-init/files/crd-* >> install/kubernetes/$@
	$(HELM) template \
		--name=istio \
		--namespace=istio-system \
		--set-string global.tag=${TAG_VARIANT} \
		--set-string global.hub=${HUB} \
		--set-string global.imagePullPolicy=$(PULL_POLICY) \
		--set global.proxy.enableCoreDump=${ENABLE_COREDUMP} \
		--set istio_cni.enabled=${ENABLE_ISTIO_CNI} \
		${EXTRA_HELM_SETTINGS} \
		--values install/kubernetes/helm/istio/values-$@ \
		install/kubernetes/helm/istio >> install/kubernetes/$@

e2e_files = istio-auth-non-mcp.yaml \
		istio-auth-sds.yaml \
		istio-non-mcp.yaml \
		istio.yaml \
		istio-auth.yaml \
		istio-auth-mcp.yaml \
		istio-auth-multicluster.yaml \
		istio-mcp.yaml \
		istio-one-namespace.yaml \
		istio-one-namespace-auth.yaml \
		istio-one-namespace-trust-domain.yaml \
		istio-multicluster.yaml \
		istio-multicluster-split-horizon.yaml

FILES_TO_CLEAN+=install/consul/istio.yaml \
                install/kubernetes/istio-auth.yaml \
                install/kubernetes/istio-citadel-plugin-certs.yaml \
                install/kubernetes/istio-citadel-with-health-check.yaml \
                install/kubernetes/istio-one-namespace-auth.yaml \
                install/kubernetes/istio-one-namespace-trust-domain.yaml \
                install/kubernetes/istio-one-namespace.yaml \
                install/kubernetes/istio.yaml \
                samples/bookinfo/platform/consul/bookinfo.sidecars.yaml

#-----------------------------------------------------------------------------
# Target: environment and tools
#-----------------------------------------------------------------------------
.PHONY: show.env show.goenv

show.env: ; $(info $(H) environment variables...)
	$(Q) printenv

show.goenv: ; $(info $(H) go environment...)
	$(Q) $(GO) version
	$(Q) $(GO) env

# tickle
# show makefile variables. Usage: make show.<variable-name>
show.%: ; $(info $* $(H) $($*))
	$(Q) true

# Deprecated. This target exists only to satisify old CI tests that cannot be updated atomically, and can be removed.
localTestEnv:

#-----------------------------------------------------------------------------
# Target: custom resource definitions
#-----------------------------------------------------------------------------

update-crds:
	bin/update_crds.sh

#-----------------------------------------------------------------------------
# Target: artifacts and distribution
#-----------------------------------------------------------------------------
# deb, rpm, etc packages
include tools/packaging/packaging.mk

#-----------------------------------------------------------------------------
# Target: e2e tests
#-----------------------------------------------------------------------------
include tests/istio.mk

#-----------------------------------------------------------------------------
# Target: integration tests
#-----------------------------------------------------------------------------
include tests/integration/tests.mk

include common/Makefile.common.mk
