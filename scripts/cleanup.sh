#!/bin/bash
################################################################################
# GKE Cluster Cleanup & Teardown Script
# Purpose: Completely remove all GKE infrastructure and stop all billing
# WARNING: This is destructive and cannot be undone without reprovisioning
################################################################################

set -e  # Exit immediately if any command fails

CLUSTER_NAME="ai-spot-cluster"
REGION="us-central1"

echo "[WARNING] Starting complete teardown of cluster '$CLUSTER_NAME'."
echo "[WARNING] This will delete all resources, persistent data, and the cluster."
echo "[INFO] Proceeding in 10 seconds... (Ctrl+C to cancel)"
sleep 10

echo "[INFO] Starting 6-step cleanup process..."
echo ""

# Step 1: Delete KEDA autoscaling components
echo "[INFO] Step 1/6: Deleting KEDA autoscaling resources..."
# HTTPScaledObject is a custom resource from KEDA HTTP add-on
kubectl delete httpscaledobject.http.keda.sh --all --ignore-not-found
echo "[SUCCESS] KEDA resources deleted."
echo ""

# Step 2: Delete Deployments and Services  
echo "[INFO] Step 2/6: Deleting Kubernetes Services and Deployments..."
# Deleting LoadBalancer services is critical—they incur charges even without pods
kubectl delete service --all --ignore-not-found
kubectl delete deployment --all --ignore-not-found
echo "[SUCCESS] Services and Deployments deleted."
echo ""

# Step 3: Delete Persistent Volume Claims
echo "[INFO] Step 3/6: Deleting Persistent Volume Claims..."
# CRITICAL: Deleting PVCs frees persistent disks. Without this,
# the 50GB model storage disk remains and continues incurring charges
kubectl delete pvc --all --ignore-not-found
echo "[SUCCESS] PVCs deleted."
echo ""

# Step 4: Uninstall KEDA and HTTP Add-on
echo "[INFO] Step 4/6: Uninstalling KEDA and HTTP Add-on components..."
# Must uninstall before cluster deletion to clean up CRDs and webhooks

# Uninstall KEDA HTTP Add-on via Helm (installed via Helm chart)
helm uninstall http-add-on --namespace keda --ignore-not-found

# Uninstall KEDA core via kubectl (installed via direct manifest)
kubectl delete -f https://github.com/kedacore/keda/releases/download/v2.13.0/keda-2.13.0.yaml --ignore-not-found

echo "[SUCCESS] KEDA components uninstalled."
echo ""

# Step 5: Delete the GKE Cluster
echo "[INFO] Step 5/6: Deleting GKE Cluster '$CLUSTER_NAME'..."
echo "[NOTE] Cluster deletion usually takes 5-10 minutes. Waiting..."
gcloud container clusters delete $CLUSTER_NAME \
    --region $REGION \
    --quiet
echo "[SUCCESS] GKE Cluster '$CLUSTER_NAME' deleted."
echo ""

# Step 6: Final check and cleanup of orphaned disks
echo "[INFO] Step 6/6: Checking for orphaned persistent disks..."
# Filter: zone matches region AND disk has no users (not attached)
ORPHANED_DISKS_INFO=$(gcloud compute disks list --filter="zone:($REGION*) AND -users:*" --format="value(name,zone.basename())")

if [ -z "$ORPHANED_DISKS_INFO" ]; then
    echo "[SUCCESS] No orphaned disks found."
else
    echo "[WARNING] Found orphaned disks—cleaning up now..."
    echo "$ORPHANED_DISKS_INFO" | while read -r DISK_NAME DISK_ZONE; do
        if [ -n "$DISK_NAME" ]; then
            echo "[INFO] Deleting: $DISK_NAME (zone: $DISK_ZONE)..."
            gcloud compute disks delete "$DISK_NAME" --zone="$DISK_ZONE" --quiet
            echo "[SUCCESS] Disk deleted."
        fi
    done
    echo "[SUCCESS] All orphaned disks cleaned up."
fi

echo ""
echo "================================================="
echo "[SUCCESS] Cleanup COMPLETE!"
echo "Billing should now drop to ~$0/hr"
echo "================================================="