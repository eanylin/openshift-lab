.PHONY: test lock lock-t2 legacy-requirements legacy-image act1-repro act2-chain act2-image act3a-image act3b-image act3b-hash-fail reset restore-act3b reset-note

include digests.env
export

IMAGE_REPO ?= $(FXRATE_IMAGE_REPO)
LEGACY_TAG ?= 1.0.0-legacy
LEGACY_BASE_REF ?= $(LEGACY_PYTHON_IMAGE)@$(LEGACY_PYTHON_DIGEST)
PIP_INDEX_URL ?= $(NEXUS_PYPI_SIMPLE)

# Local unit tests (Act 2+ app). Use RHHI builder for release locks.
test:
	python3 -m pytest -W error::DeprecationWarning -q

# Generate hashed lockfile. Prefer running inside RHHI builder (constitution II).
lock:
	pip-compile --generate-hashes --strip-extras -o requirements.txt requirements.in

legacy-requirements:
	@echo "Legacy top-level pins live in legacy/requirements.txt (do not lock)."

# Act 1 fallback: R0 resolve → Werkzeug 3.x → url_quote ImportError
act1-repro:
	bash ../cluster/demo/act1-rebuild-fails.sh

# Act 2: Requires-Python / ResolutionImpossible chain traps
act2-chain:
	bash ../cluster/demo/act2-chain-fails.sh

act2-image:
	podman build -f Containerfile.act2 \
	  --build-arg ACT2_BASE=$(ACT2_PYTHON_REF) \
	  --build-arg PIP_INDEX_URL=$(PIP_INDEX_URL) \
	  -t $(IMAGE_REPO):2.0.0-act2 \
	  .

act3a-image:
	podman build -f Containerfile.act3a \
	  --build-arg RHHI_BUILDER=$(RHHI_BUILDER_REF) \
	  --build-arg RHHI_RUNTIME=$(RHHI_RUNTIME_REF) \
	  --build-arg PIP_INDEX_URL=$(PIP_INDEX_URL) \
	  -t $(IMAGE_REPO):3.0.0-act3a \
	  .

# Act 3b lock against Trusted Libraries (run inside RHHI builder).
lock-t2:
	pip-compile --generate-hashes --strip-extras --no-emit-index-url \
	  --index-url $(NEXUS_RHTL_SIMPLE) \
	  -o requirements-t2.txt requirements.in

act3b-image:
	podman build -f Containerfile.act3b \
	  --build-arg RHHI_BUILDER=$(RHHI_BUILDER_REF) \
	  --build-arg RHHI_RUNTIME=$(RHHI_RUNTIME_REF) \
	  --build-arg PIP_INDEX_URL=$(NEXUS_RHTL_SIMPLE) \
	  --build-arg PIP_TRUSTED_HOST=$(NEXUS_TRUSTED_HOST) \
	  -t $(IMAGE_REPO):3.0.0-act3b \
	  .

act3b-hash-fail:
	bash ../cluster/demo/act3b-hash-fail.sh

# Historical Act 0 image (FR-041) — outside Trusted Pipeline.
legacy-image:
	podman build \
	  -f Containerfile.legacy \
	  --build-arg LEGACY_BASE=$(LEGACY_BASE_REF) \
	  --build-arg PIP_INDEX_URL=$(PIP_INDEX_URL) \
	  -t $(IMAGE_REPO):$(LEGACY_TAG) \
	  .
	@echo "Built $(IMAGE_REPO):$(LEGACY_TAG)"
	@echo "Push: podman push $(IMAGE_REPO):$(LEGACY_TAG)"
	@echo "Then record RepoDigest in digests.env as FXRATE_LEGACY_DIGEST / FXRATE_IMAGE_DIGEST"

# Cluster reset / restore (prefer repo-root: make reset). Requires RESET_CONFIRM=yes.
reset:
	@$(MAKE) -C .. reset

restore-act3b:
	@$(MAKE) -C .. restore-act3b

reset-note:
	@echo "RESET_CONFIRM=yes make reset          # Act 0 on dev, clear prod"
	@echo "RESET_CONFIRM=yes make restore-act3b  # Act 3b on dev+prod"
	@echo "See ../cluster/docs/DEMO-RUNBOOK.md"
