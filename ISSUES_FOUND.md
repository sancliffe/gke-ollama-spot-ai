# Project Issues and Errors Found

## Critical Issues

### 1. **REGION Environment Variable Not Respected in cleanup.sh** ⚠️ CRITICAL
- **Location**: [scripts/cleanup.sh](scripts/cleanup.sh#L64)
- **Issue**: The cleanup script hardcodes `REGION="us-central1"` instead of respecting the `REGION` environment variable
- **Impact**: If a user deploys to `us-east1` (or any other region), the cleanup script will attempt to delete resources from `us-central1`, leaving orphaned resources and continuing billing
- **Current code**:
  ```bash
  REGION="us-central1"  # Hardcoded!
  ```
- **Fix**: Should use:
  ```bash
  REGION="${REGION:-us-central1}"  # Respect environment variable, default to us-central1
  ```

---

## Documentation Issues

### 2. **Misleading Script Header - setup-cluster.sh**
- **Location**: [scripts/setup-cluster.sh](scripts/setup-cluster.sh#L1-L5)
- **Issue**: Script header says "Purpose: **Provision a GPU-enabled** GKE Autopilot cluster for Ollama inference" but deployment is actually **CPU-based**
- **Current header**:
  ```bash
  # Purpose: Provision a GPU-enabled GKE Autopilot cluster for Ollama inference
  ```
- **Fix**: Update to:
  ```bash
  # Purpose: Provision a CPU-based GKE Autopilot cluster for Ollama inference
  # (Can be upgraded to GPU; see deployment.yaml for GPU configuration)
  ```

---

### 3. **Missing Port-Forward Instructions in Notebook**
- **Location**: [notebooks/test-api.ipynb](notebooks/test-api.ipynb#L17-L60) - Cell 2 (Setup cell)
- **Issue**: The notebook mentions `kubectl port-forward` as a configuration option but doesn't provide clear instructions on how to set it up
- **Current comment**:
  ```python
  # - KEDA interceptor: kubectl port-forward -n keda svc/keda-http-add-on-interceptor-proxy 9090:8081
  ```
- **Fix**: Add example command showing how to run the port-forward in a separate terminal:
  ```python
  # - KEDA interceptor: 
  #   In a separate terminal, run:
  #   kubectl port-forward -n keda svc/keda-http-add-on-interceptor-proxy 9090:8081
  #   Then set: OLLAMA_ENDPOINT=http://localhost:9090
  ```

---

## Configuration Issues

### 4. **Inconsistent Resource Specs vs Documentation**
- **Location**: [CHANGELOG.md](CHANGELOG.md#L16-L25)
- **Issue**: CHANGELOG states "Resource specifications: 2 CPU → 4 CPU, 8GB → 16GB RAM" but [k8s/deployment.yaml](k8s/deployment.yaml#L25-L30) still shows:
  ```yaml
  cpu: "2"
  memory: "4Gi"
  ```
- **Impact**: CHANGELOG documents 4 CPU / 16GB but actual deployment uses 2 CPU / 4GB. This mismatch could confuse users about actual resource requirements and costs
- **Note**: The README correctly states "2-core CPU with 4GB RAM", so deployment.yaml is correct but CHANGELOG is outdated

---

## Minor Issues

### 5. **Duplicate Documentation Line in README.md**
- **Location**: [README.md](README.md#L12-L14)
- **Issue**: The feature list contains a duplicate line:
  ```markdown
  - **Near-Zero Idle Cost**: GKE Autopilot scales to zero pods when idle; costs drop to ~$5/month (storage only)
  - **Near-Zero Idle Cost**: GKE Autopilot scales to zero pods when idle; costs drop to ~$5/month (storage only)
  ```
- **Fix**: Remove the duplicate line

---

### 6. **Helm Dependency Not in Main Prerequisites**
- **Location**: [README.md](README.md#L29-L33)
- **Issue**: Helm is required (for KEDA HTTP Add-on installation) but is listed as "*(Optional)*" in the prerequisites
- **Current text**:
  ```markdown
  - **Helm** installed (for KEDA HTTP Add-on; [install guide](https://helm.sh/docs/intro/install/))
  ```
- **Impact**: Users might skip installing Helm and then encounter errors during KEDA HTTP Add-on installation
- **Fix**: Remove optional designation and make it required:
  ```markdown
  - **Helm** installed (required for KEDA HTTP Add-on; [install guide](https://helm.sh/docs/intro/install/))
  ```

---

## Best Practices

### 7. **Potential Timeout Issues in seed-initial-model.sh**
- **Location**: [scripts/seed-initial-model.sh](scripts/seed-initial-model.sh#L95)
- **Issue**: The script uses `kubectl wait` with a 600-second timeout, but this timeout is not configurable
- **Concern**: On slower networks or resource-constrained projects, 10 minutes might not be enough
- **Recommendation**: Add environment variable support:
  ```bash
  READY_TIMEOUT="${READY_TIMEOUT:-600s}"  # Default to 600s, can be overridden
  kubectl wait --for=condition=Ready pod -l app=ollama --timeout="$READY_TIMEOUT"
  ```

---

## Summary Table

| Issue | Severity | Type | Status |
|-------|----------|------|--------|
| REGION variable ignored in cleanup.sh | 🔴 Critical | Bug | ❌ Not Fixed |
| Setup script header says GPU but uses CPU | 🟡 High | Documentation | ❌ Not Fixed |
| Port-forward instructions unclear | 🟡 Medium | Documentation | ❌ Not Fixed |
| CHANGELOG vs deployment.yaml resource mismatch | 🟠 Medium | Documentation | ❌ Not Fixed |
| Duplicate README line | 🔵 Low | Documentation | ❌ Not Fixed |
| Helm marked as optional | 🟡 Medium | Documentation | ❌ Not Fixed |
| Timeout not configurable | 🟠 Medium | Best Practice | ❌ Suggested |

---

## Recommendations

1. **Immediate**: Fix the REGION variable issue in cleanup.sh (Critical)
2. **High Priority**: Update script header and clarify Helm requirement
3. **Medium Priority**: Improve port-forward documentation and update CHANGELOG
4. **Nice-to-Have**: Make timeout configurable in seed script
