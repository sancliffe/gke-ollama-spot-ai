#!/bin/bash
################################################################################
# Ollama Initial Model Seeding Script
# Purpose: Scale up the Ollama deployment and pre-load the LLM into storage
# This ensures models are cached and ready for the first inference request
################################################################################

set -e  # Exit immediately if any command fails

echo "[INFO] Starting Ollama initial model seeding script."
echo "[INFO] This script will activate the deployment and pre-load the initial model."

# Step 1: Scale deployment to ensure a pod is provisioned
echo "[INFO] Step 1/4: Scaling deployment 'ollama-gpu' to 1 replica..."
echo "[NOTE] KEDA normally scales to 0 when idle; this manually triggers scale-up."
kubectl scale deployment/ollama-gpu --replicas=1

# Step 2: Wait for pod readiness (includes health checks)
echo "[INFO] Step 2/4: Waiting for Ollama pod to reach Ready state (timeout: 600s)..."
echo "[NOTE] Provisioning a Spot GPU node typically takes 2-4 minutes."
echo "       GKE automatically provisions a new node and attaches the persistent disk."

# Wait for the pod to pass readiness/liveness probes
kubectl wait --for=condition=Ready pod -l app=ollama --timeout=600s
echo "[SUCCESS] Pod is Ready."

# Step 3: Extract the pod name for direct execution
echo "[INFO] Step 3/4: Identifying pod name..."
POD_NAME=$(kubectl get pods -l app=ollama -o jsonpath="{.items[0].metadata.name}")
echo "[INFO] Pod identified: $POD_NAME"

# Step 4: Pull model into persistent volume
echo "[INFO] Step 4/4: Pulling 'gemma2:2b' model into persistent volume (~1.6GB)..."
echo "[NOTE] This may take 2-5 minutes depending on internet speed."
echo "[NOTE] Gemma 2B: lightweight, fast inference, excellent for demos/testing."
kubectl exec -it $POD_NAME -- ollama pull gemma2:2b
echo "[SUCCESS] Model 'gemma2:2b' pulled and cached."

echo ""
echo "[SUCCESS] Initial model seeding COMPLETE!"
echo "[INFO] The model is now persistent and will survive pod restarts."
echo "[INFO] KEDA will scale to zero after 5 minutes of no traffic."
echo "[INFO] Next: Send inference requests to activate the service."