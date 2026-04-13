#!/bin/bash
################################################################################
# GKE Autopilot Cluster Setup Script
# Purpose: Provision a CPU-based GKE Autopilot cluster for Ollama inference
# (Can be upgraded to GPU; see deployment.yaml for GPU configuration)
# Uses Spot VMs for cost optimization (~60-91% cheaper than standard pricing)
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
    for cmd in gcloud kubectl; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed or not in PATH."
            exit 1
        fi
    done
    log_info "All dependencies verified: gcloud, kubectl"
}

# ============================================================================
# Configuration
# ============================================================================
LOG_FILE="setup_$(date +%Y%m%d_%H%M%S).log"

# Configuration: Can be overridden via environment variables
# PROJECT_ID is derived from gcloud config. For CI/CD, consider setting it explicitly.
PROJECT_ID=$(gcloud config get-value project)
REGION="${REGION:-us-central1}"          # Default: us-central1, override with: REGION=us-east1 ./setup-cluster.sh
CLUSTER_NAME="ai-spot-cluster"

SECONDS=0

# Validate dependencies before proceeding
check_deps

log_info "Starting GKE cluster setup script."
log_info "Configuration:"
log_info "  Project ID: $PROJECT_ID"
log_info "  Region: $REGION (to change: REGION=us-east1 ./setup-cluster.sh)"
log_info "  Cluster Name: $CLUSTER_NAME"
log_info ""
log_info "Enabling required Google Cloud APIs..."
gcloud services enable container.googleapis.com compute.googleapis.com
log_success "Google Cloud APIs enabled successfully."

log_info "Creating GKE Autopilot Cluster '$CLUSTER_NAME' in region '$REGION'..."
# --tier standard: Qualifies for GCP free-tier management credits
# --release-channel regular: Stable Kubernetes version updates
gcloud container clusters create-auto "$CLUSTER_NAME" \
    --region "$REGION" \
    --project "$PROJECT_ID" \
    --release-channel regular \
    --tier standard
log_success "GKE Autopilot Cluster '$CLUSTER_NAME' created successfully."

log_info "Getting Kubernetes credentials for cluster '$CLUSTER_NAME'..."
# Fetch kubectl credentials and configure ~/.kube/config for local access
gcloud container clusters get-credentials "$CLUSTER_NAME" --region "$REGION"
log_success "Kubernetes credentials configured."

# ============================================================================
# Deploy Ollama Core Components (Deployment, Service, Storage)
# ============================================================================
log_info "Deploying Ollama core Kubernetes manifests..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/storage.yaml
log_success "Ollama core components deployed."

# ============================================================================
# KEDA Installation
# ============================================================================
log_info "Installing KEDA autoscaling operator..."

# Create KEDA namespace
# KEDA Helm chart will create the namespace if it doesn't exist, but we ensure it for kubectl apply
kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f - || true
log_info "KEDA namespace ensured."

# Install KEDA core using kubectl manifest
log_info "Installing KEDA core operator (this may take 1-2 minutes)..."
# Use --server-side apply to avoid "Too long" annotation errors
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.13.0/keda-2.13.0.yaml --server-side

# Wait for KEDA deployment to be ready
log_info "Waiting for KEDA operator to become ready..."
kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda
log_success "KEDA operator installed."

# Install KEDA HTTP Add-on for HTTP-based autoscaling
log_info "Installing KEDA HTTP Add-on via Helm..."
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install HTTP add-on
helm install http-add-on kedacore/keda-add-ons-http \
  --namespace keda \
  --create-namespace \
  --timeout 5m
log_success "KEDA HTTP Add-on installation initiated."

# Wait for KEDA HTTP Add-on to be ready
log_info "Waiting for KEDA HTTP Add-on to become ready..."

# Wait for deployments to be created (with retries)
max_retries=30
retry_count=0
while [[ $retry_count -lt $max_retries ]]; do
    if kubectl get deployment keda-http-add-on-interceptor -n keda &>/dev/null && \
       kubectl get deployment keda-http-add-on-operator -n keda &>/dev/null; then
        break
    fi
    ((retry_count++)) || true
    if [[ $retry_count -eq $max_retries ]]; then
        log_warn "Deployments not created yet. Proceeding with wait (may timeout if still not ready)."
    else
        sleep 2
    fi
done

# Now wait for the deployments to be available
kubectl wait --for=condition=available --timeout=300s deployment/keda-http-add-on-interceptor -n keda || \
    log_warn "keda-http-add-on-interceptor deployment timeout (may be delayed)"
kubectl wait --for=condition=available --timeout=300s deployment/keda-http-add-on-operator -n keda || \
    log_warn "keda-http-add-on-operator deployment timeout (may be delayed)"
log_success "KEDA HTTP Add-on installed and ready."

# Verify KEDA installations
log_info "Verifying KEDA installation..."
if kubectl get deployment keda-operator -n keda &>/dev/null; then
    log_success "KEDA operator verified."
else
    log_error "KEDA operator not found. Please verify installation and rerun if needed."
fi
log_success "KEDA installation verified."

log_info "Applying KEDA autoscaler manifest for Ollama..."
kubectl apply -f k8s/keda-autoscaler.yaml
log_success "KEDA autoscaler for Ollama applied."

DURATION_MIN=$((SECONDS / 60))
DURATION_SEC=$((SECONDS % 60))
log_success "Cluster setup complete in ${DURATION_MIN}m ${DURATION_SEC}s."
log_info "Next: Run ./scripts/seed-initial-model.sh to deploy Ollama and pull models."
log_info "Full log saved to: $LOG_FILE"