#!/bin/bash
################################################################################
# GKE Autopilot Cluster Setup Script
# Purpose: Provision a GPU-enabled GKE Autopilot cluster for Ollama inference
# Uses Spot VMs for cost optimization (~60-91% cheaper than standard pricing)
################################################################################

set -e  # Exit immediately if any command fails

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
CLUSTER_NAME="ai-spot-cluster"

echo "[INFO] Starting GKE cluster setup script."
echo "[INFO] Enabling required Google Cloud APIs..."
gcloud services enable container.googleapis.com compute.googleapis.com
echo "[INFO] Google Cloud APIs enabled successfully."

echo "[INFO] Creating GKE Autopilot Cluster '$CLUSTER_NAME' in region '$REGION'..."
# --tier standard: Qualifies for GCP free-tier management credits
# --release-channel regular: Stable Kubernetes version updates
gcloud container clusters create-auto $CLUSTER_NAME \
    --region $REGION \
    --project $PROJECT_ID \
    --release-channel regular \
    --tier standard
echo "[INFO] GKE Autopilot Cluster '$CLUSTER_NAME' created successfully."

echo "[INFO] Getting Kubernetes credentials for cluster '$CLUSTER_NAME'..."
# Fetch kubectl credentials and configure ~/.kube/config for local access
gcloud container clusters get-credentials $CLUSTER_NAME --region $REGION
echo "[INFO] Kubernetes credentials configured."

echo "[SUCCESS] Cluster setup complete."
echo "[NEXT] Run: ./scripts/seed-initial-model.sh to deploy Ollama and pull models."