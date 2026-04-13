#!/bin/bash
################################################################################
# GKE Cluster Cleanup & Teardown Script
# Purpose: Completely remove all GKE infrastructure and stop all billing
# WARNING: This is destructive and cannot be undone without reprovisioning
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
# Configuration (must be before dependency check for LOG_FILE)
# ============================================================================
LOG_FILE="cleanup_$(date +%Y%m%d_%H%M%S).log"
CLUSTER_NAME="ai-spot-cluster"

# ============================================================================
# Dependency Validation
# ============================================================================
check_deps() {
    for cmd in gcloud kubectl helm; do
        if ! command -v $cmd &> /dev/null; then
            log_error "$cmd is not installed or not in PATH."
            exit 1
        fi
    done
    log_info "All dependencies verified: gcloud, kubectl, helm"
}

# Validate dependencies before proceeding
check_deps

# Auto-detect cluster region if not specified via environment variable
if [[ -z "$REGION" ]]; then
    # Try to find the cluster in any region
    REGION=$(gcloud container clusters list --format='value(location)' --filter="name=$CLUSTER_NAME" 2>/dev/null | head -1)
    if [[ -z "$REGION" ]]; then
        log_error "Cluster '$CLUSTER_NAME' not found in any region. Please specify REGION explicitly or ensure the cluster exists."
        exit 1
    fi
    log_info "Auto-detected cluster region: $REGION"
else
    log_info "Using specified region: $REGION"
fi

SECONDS=0

log_warn "Starting complete teardown of cluster '$CLUSTER_NAME' in region '$REGION'."
log_warn "This will delete all resources, persistent data, and the cluster."
log_info "Proceeding in 10 seconds... (Ctrl+C to cancel)"
sleep 10

log_info "Starting 6-step cleanup process..."
echo ""

# Step 1: Delete KEDA autoscaling components
log_info "Step 1/6: Deleting KEDA autoscaling resources..."
kubectl delete httpscaledobject.http.keda.sh --all --ignore-not-found || true
log_success "KEDA resources deleted."
echo ""

# Step 2: Delete Deployments and Services  
log_info "Step 2/6: Deleting Kubernetes Services and Deployments..."
kubectl delete service --all --ignore-not-found
kubectl delete deployment --all --ignore-not-found
log_success "Services and Deployments deleted."
echo ""

# Step 3: Delete Persistent Volume Claims
log_info "Step 3/6: Deleting Persistent Volume Claims..."
kubectl delete pvc --all --ignore-not-found
log_success "PVCs deleted."
echo ""

# Step 4: Uninstall KEDA and HTTP Add-on
log_info "Step 4/6: Uninstalling KEDA and HTTP Add-on components..."
if helm status http-add-on -n keda &>/dev/null; then
    helm uninstall http-add-on --namespace keda
fi
kubectl delete -f https://github.com/kedacore/keda/releases/download/v2.13.0/keda-2.13.0.yaml --ignore-not-found
log_success "KEDA components uninstalled."
echo ""

# Step 5: Delete the GKE Cluster
log_info "Step 5/6: Deleting GKE Cluster '$CLUSTER_NAME'..."
log_info "Cluster deletion usually takes 5-10 minutes. Waiting..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if gcloud container clusters delete "$CLUSTER_NAME" --region "$REGION" --quiet; then
        break
    fi
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        log_warn "Cluster deletion failed (likely due to a concurrent operation). Retrying in 30 seconds... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 30
    else
        log_error "Failed to delete cluster after $MAX_RETRIES attempts."
        exit 1
    fi
done
log_success "GKE Cluster '$CLUSTER_NAME' deleted."
echo ""

# Step 6: Final check and cleanup of orphaned disks
log_info "Step 6/6: Checking for orphaned persistent disks..."
# Filter matches the resolved REGION
ORPHANED_DISKS_INFO=$(gcloud compute disks list --filter="zone:($REGION*) AND -users:*" --format="value(name,zone.basename())")

if [ -z "$ORPHANED_DISKS_INFO" ]; then
    log_success "No orphaned disks found."
else
    log_warn "Found orphaned disks—cleaning up now..."
    echo "$ORPHANED_DISKS_INFO" | while read -r DISK_NAME DISK_ZONE; do
        if [ -n "$DISK_NAME" ]; then
            log_info "Deleting: $DISK_NAME (zone: $DISK_ZONE)..."
            gcloud compute disks delete "$DISK_NAME" --zone="$DISK_ZONE" --quiet
            log_success "Disk deleted."
        fi
    done
    log_success "All orphaned disks cleaned up."
fi

DURATION_MIN=$((SECONDS / 60))
DURATION_SEC=$((SECONDS % 60))

echo ""
echo "================================================="
log_success "Cleanup COMPLETE in ${DURATION_MIN}m ${DURATION_SEC}s!"
echo "Billing should now drop to ~\$0/hr"
echo "================================================="
log_info "Full log saved to: $LOG_FILE"