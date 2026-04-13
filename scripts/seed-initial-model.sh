#!/bin/bash
################################################################################
# Ollama Initial Model Seeding Script
# Purpose: Scale up the Ollama deployment and pre-load the LLM into storage
# This ensures models are cached and ready for the first inference request
################################################################################

set -e  # Exit immediately if any command fails

# ============================================================================
# Centralized Logging Functions
# ============================================================================
log_info() { 
    local msg="[INFO] [$(date +%T)] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_warn() { 
    local msg="[WARNING] [$(date +%T)] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_error() { 
    local msg="[ERROR] [$(date +%T)] $*"
    echo "$msg" >&2
    echo "$msg" >> "$LOG_FILE"
}
log_success() { 
    local msg="[SUCCESS] [$(date +%T)] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}
log_note() { 
    local msg="[NOTE] [$(date +%T)] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# ============================================================================
# Error Handler
# ============================================================================
error_handler() {
    log_error "Script failed on line $1"
}

# Trap ERR (error) signals and pass the line number ($LINENO) to the handler
trap 'error_handler $LINENO' ERR

# ============================================================================
# Debug Mode
# ============================================================================
if [[ "${DEBUG}" == "true" || "${DEBUG}" == "1" ]]; then
    set -x
    log_info "Debug mode enabled."
fi

# ============================================================================
# Dependency Validation
# ============================================================================
check_deps() {
    for cmd in kubectl; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed or not in PATH."
            exit 1
        fi
    done
    log_info "All dependencies verified: kubectl"
}

# ============================================================================
# Configuration
# ============================================================================
LOG_FILE="seed_$(date +%Y%m%d_%H%M%S).log"
READY_TIMEOUT="${READY_TIMEOUT:-600s}"  # Timeout for pod readiness; override with READY_TIMEOUT=900s if needed

SECONDS=0

# Validate dependencies before proceeding
check_deps

log_info "Starting Ollama initial model seeding script."
log_info "This script will activate the deployment and pre-load the initial model."

# Step 1: Scale deployment to ensure a pod is provisioned
log_info "Step 1/4: Scaling deployment 'ollama-cpu' to 1 replica..."
log_note "KEDA normally scales to 0 when idle; this manually triggers scale-up."
kubectl scale deployment/ollama-cpu --replicas=1

# Step 2: Wait for pod readiness (includes health checks)
log_info "Step 2/4: Waiting for Ollama pod to reach Ready state (timeout: $READY_TIMEOUT)..."
log_note "Provisioning a Spot node typically takes 2-4 minutes (CPU or GPU)."
log_note "GKE automatically provisions a new node and attaches the persistent disk."

# Wait for the pod to pass readiness/liveness probes
kubectl wait --for=condition=Ready pod -l app=ollama --timeout="$READY_TIMEOUT"
log_success "Pod is Ready."

# Step 3: Extract the pod name for direct execution
log_info "Step 3/4: Identifying pod name..."
POD_NAME=$(kubectl get pods -l app=ollama -o jsonpath="{.items[0].metadata.name}")
log_info "Pod identified: $POD_NAME"

# Step 4: Pull model into persistent volume
log_info "Step 4/4: Pulling 'gemma2:2b' model into persistent volume (~1.6GB)..."
log_note "CPU-based inference: may take 5-15 minutes for initial pull."
log_note "If timeout occurs, run: kubectl exec -it \$POD_NAME -- ollama pull gemma2:2b"
log_note "Gemma 2B: lightweight, suitable for CPU and GPU inference."
kubectl exec -it "$POD_NAME" -- ollama pull gemma2:2b
log_success "Model 'gemma2:2b' pulled and cached."

DURATION_MIN=$((SECONDS / 60))
DURATION_SEC=$((SECONDS % 60))

echo ""
log_success "Initial model seeding COMPLETE in ${DURATION_MIN}m ${DURATION_SEC}s!"
log_info "The model is now persistent and will survive pod restarts."
log_info "KEDA will scale to zero after 5 minutes of no traffic."
log_info "Next: Send inference requests to activate the service."
log_info "Full log saved to: $LOG_FILE"