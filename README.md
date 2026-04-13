GKE Autopilot: Cost-Optimized AI Inference with Ollama

**Production-ready deployment of Ollama on GKE using Spot VMs with KEDA autoscaling for near-zero idle costs.**

This project demonstrates how to deploy a production-grade AI inference engine (Ollama) on Google Kubernetes Engine (GKE) Autopilot using Spot VMs with intelligent autoscaling. Currently configured for CPU-based testing with multi-replica load balancing.

**Important**: This deployment has been tested and verified working in production. All documented steps reflect real deployment experience and lessons learned.
- **Near-Zero Idle Cost**: GKE Autopilot scales to zero pods when idle; costs drop to ~$5/month (storage only)
- **CPU-Based Inference**: 2-core CPU with 4GB RAM (optimized for stable scheduling; scales 0-2 pods)
- **Resilient Design**: PersistentVolumeClaims ensure models persist across Spot VM preemptions
- **Automatic Scaling**: KEDA monitors HTTP traffic; scales from 0→up to 2 pods for load balancing
- **Multi-Replica Support**: Test load balancing with up to 2 concurrent pods
- **Easy Deployment**: Fully automated with Bash scripts and Kubernetes YAML manifests
- **Regional Flexibility**: Supports us-central1 (primary) and us-east1 (fallback for quota issues)

## Repository Structure

```
.
├── README.md                    # This file
├── k8s/                         # Kubernetes manifests
│   ├── deployment.yaml          # Ollama deployment (2-core CPU, 4GB RAM)
│   ├── keda-autoscaler.yaml     # KEDA HTTP interceptor config (scales 0-2 pods)
│   ├── service.yaml             # Internal ClusterIP service
│   └── storage.yaml             # 50GB persistent volume claim
├── scripts/                     # Cluster lifecycle scripts
│   ├── setup-cluster.sh         # Provision GKE cluster
│   ├── seed-initial-model.sh    # Pull initial model
│   └── cleanup.sh               # Complete teardown (stop all billing)
└── notebooks/
    └── test-api.ipynb           # Jupyter notebook for testing API
```

## Architecture

**How Spot Resilience Works:**

When GCP reclaims a Spot VM (~30-second notice):
1. Kubernetes scheduler detects pod is terminating
2. Ollama gracefully saves state (25-second grace period)
3. GKE provisions a new Spot node
4. PersistentVolume re-attaches to new pod
5. Ollama resumes without re-downloading models (~1 minute total)

Result: Service interruption << model download time

## Quick Start

### Prerequisites
- **Google Cloud Project** with Billing enabled
- **gcloud CLI** installed and authenticated (`gcloud auth login`)
- **kubectl** installed (`gcloud components install kubectl`)
- **Helm** installed (required for KEDA HTTP Add-on; [install guide](https://helm.sh/docs/intro/install/))
- **CPU Quota** for Spot VMs (default: 10-50 CPUs available; us-central1 is first choice, us-east1 as fallback if quota exhausted)
- **Ollama**: Version 0.2.x or higher required (project uses latest tag; pulls gemma2 and other modern models)
- *(Optional) GPU Quota for L4 if switching to GPU mode (see deployment.yaml comments)*

### Regional Guidance
- **us-central1** (Default): Primary region with free tier support
- **us-east1** (Fallback): Recommended if us-central1 hits Spot CPU quota limits
  - To use us-east1, set `REGION=us-east1` before running `./scripts/setup-cluster.sh`
  - Quota limits are project-wide; if us-central1 is exhausted, try us-east1


### 60-Second Deployment
```bash
# 1. Provision cluster (5-10 minutes)
./scripts/setup-cluster.sh

# 2. Install KEDA (2-3 minutes)
# Install KEDA core with server-side apply
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.13.0/keda-2.13.0.yaml --server-side

# Install KEDA HTTP Add-on via Helm (more reliable than direct manifests)
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm install http-add-on kedacore/keda-add-ons-http --namespace keda --create-namespace

# 3. Deploy Ollama (1-2 minutes)
kubectl apply -f k8s/

# 4. Load initial model (5-10 minutes, happens once)
./scripts/seed-initial-model.sh

# All done! Pod now scales to 0 after 5 minutes of idle
```
### Step-by-Step Guide

#### 1. Provision the GKE Cluster
Creates a single-zone GKE Autopilot cluster optimized for cost:
```bash
./scripts/setup-cluster.sh
```
**What it does:**
- Enables GCP APIs (container.googleapis.com, compute.googleapis.com)
- Creates `ai-spot-cluster` in us-central1 with standard tier (qualifies for free-tier credits)
- Configures kubectl credentials


**Step A: Install KEDA Core** (server-side apply to avoid annotation errors)
```bash
# Install KEDA core (cost: ~$0.05/month)
# Use --server-side flag to avoid "Too long" annotation errors
kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.13.0/keda-2.13.0.yaml --server-side
```

**Step B: Install KEDA HTTP Add-on via Helm** (recommended for latest versions)
```bash
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install HTTP Add-on via Helm (handles all dependencies and versioning)
helm install http-add-on kedacore/keda-add-ons-http --namespace keda --create-namespace
```

**Why Helm?** The KEDA project has moved its manifest locations in recent versions. Helm is the recommended way to install the HTTP Add-on as it automatically handles dependencies and keeps versions in sync.

**Wait for readiness:**
```bash
kubectl wait -n keda --for=condition=ready pod -l app.kubernetes.io/name=keda-operator --timeout=120s
kubectl wait -n keda --for=condition=ready pod -l app.kubernetes.io/name=keda-http-add-on --timeout=120s
```

**Verification:**
```bash
# Verify both KEDA and HTTP Add-on pods are running
kubectl get pods -n keda
```
```bash
kubectl wait -n keda --for=condition=ready pod -l app.kubernetes.io/name=keda-operator --timeout=120s
```
**Note**: The `--server-side` flag tells Kubernetes to manage configuration server-side instead of storing the entire YAML in annotations, which prevents size-limit errors on large manifests.

#### 3. Deploy Ollama Stack
Applies all Kubernetes manifests (deployment, service, storage, KEDA config):
```bash
kubectl apply -f k8s/
```
**What it creates:**
- `ollama-cpu` Deployment (spec: 2 CPUs, 4GB RAM per pod, up to 2 replicas initially set to 1 for seeding)
- `ollama-service` ClusterIP Service (internal-only)
- `ollama-storage` PersistentVolumeClaim (50GB standard disk)
- `ollama-http-scaler` HTTPScaledObject (KEDA traffic monitoring, scales 0-2)

**Time**: ~2-3 minutes

#### 4. Seed Initial Model (Critical)

**Prerequisites before seeding:**
1. Pod must be at `replicas: 1` (KEDA disabled during seeding)
2. Ollama must be running and ready (check: `kubectl logs -l app=ollama`)
3. Ollama version must be 0.2.x or higher (project uses :latest tag)
4. First model pull must complete before enabling KEDA autoscaling

**Why manual seeding matters:** Pulling models is I/O intensive and can fail during KEDA's scale-to-zero cycles. Seeding with a fixed replica count ensures model stays cached.

**Run the seeding script:**
```bash
./scripts/seed-initial-model.sh
```

**What it does:**
- Ensures deployment is at 1 replica
- Waits for pod readiness (may take 2-4 minutes for Spot node provisioning)
- Pulls `gemma2:2b` model ~1.6GB (executes once, cached forever)
- Model persists in PersistentVolume across restarts

**If seeding times out or fails:**
```bash
# Find the pod name
POD_NAME=$(kubectl get pods -l app=ollama -o jsonpath="{.items[0].metadata.name}")

# Manually complete the model pull
kubectl exec -it $POD_NAME -- ollama pull gemma2:2b

# Verify model was pulled
kubectl exec -it $POD_NAME -- ollama list
```

**Time**: 5-15 minutes (first run only)
### Sending Requests to Ollama

The KEDA HTTP Add-on creates its own `LoadBalancer` service. Find its external IP:
```bash
export KEDA_IP=$(kubectl get svc -n keda keda-http-add-on-interceptor-proxy \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo "KEDA Interceptor IP: $KEDA_IP"
```

**First Request Behavior**
- If pod is at 0 replicas (scaled down), the first request will trigger scale-up
- KEDA queues the request while provisioning a new node (~2-4 minutes)
- Once pod is running, response completes normally
- Subsequent requests are fast (<1 second) until idle timeout

### API Examples

**List Available Models** (triggers scale-up if needed)
```bash
curl --resolve ollama.gke.dev:80:$KEDA_IP http://ollama.gke.dev/api/tags
```

**Generate Text** (streaming tokens in real-time)
```bash
curl --resolve ollama.gke.dev:80:$KEDA_IP http://ollama.gke.dev/api/generate \
  -d '{
### Monthly Cost Breakdown

| Component | GPU (Original) | CPU (Current) | Spot CPU | Savings vs GPU |
|-----------|---|---|---|---|
| GKE Cluster Management | $0/mo (Free Tier) | $0/mo | $0/mo | - |
| Compute (L4 GPU or CPU) | $0.11/hr active | N/A | $0.02-0.04/hr | 60-80% |
| Persistent Disk Storage | $5/mo | $5/mo | $5/mo | - |
| **Monthly (1 hr/day active)** | **~$13/mo** | **~$3-5/mo** | **~$2-3/mo** | 85-90% |
| **Monthly (idle only)** | N/A | N/A | **~$5/mo** | - |

**Real-World Scenario** (CPU-based, 3 hrs/day active):
- 21 hours/day @ $0 (pods scaled to 0)
- 3 hours/day @ $0.03/hr (CPU) = ~$0.09/day
- **Monthly: ~$8/month** (storage + CPU usage)

**Cost Optimization Tips:**
1. **CPU vs GPU trade-off**: Current CPU setup is cheaper but slower; GPU version adds ~$70/mo
2. **Monitor idle time**: Check `kubectl logs -n keda keda-http-add-on-dispatcher` for traffic patterns
3. **Adjust cooldownPeriod**: Edit `k8s/keda-autoscaler.yaml` (default: 300s = 5 min)
4. **Scale down manually**: `kubectl scale deployment/ollama-cpu --replicas=0` to save during off-hours
5. **Adjust max replicas**: Edit `k8s/keda-autoscaler.yaml` (currently max: 2 for load testing)
6. **Use cheaper regions**: us-central1 is already competitive; avoid us-east1

## Troubleshooting

### Pod Stuck in Pending

**Issue**: Pod won't start after deployment
```bash
kubectl describe pod -l app=ollama
```

**Common Causes:**
- **Insufficient Spot VM quota**: Check GCP console for spot instance availability
- **Spot VM preemption**: Try again; capacity fluctuates throughout the day
- **Node not ready**: Wait 5-10 minutes for GKE to provision Spot node
- **CPU oversubscription**: Cluster may be full; try again or scale down other workloads

**Solution:**
```bash
# Check pod events
kubectl describe pod -l app=ollama

# Check node status and resources
kubectl get nodes
kubectl top nodes

# Force new pod
kubectl scale deployment/ollama-cpu --replicas=0
kubectl scale deployment/ollama-cpu --replicas=1
```

### Connection Timeout on First Request

**Issue**: First request hangs for 2-4 minutes
```
curl: (28) Operation timed out after 121000 milliseconds
```

**Why this happens**: KEDA must provision a new Spot node when pods are at 0 replicas. This is **normal behavior**.

**Solution:**
- Increase curl timeout: `curl --max-time 300 ...` (5 minutes)
- Check pod status: `kubectl get pods -w` (watch for Running state)
- Check events: `kubectl describe pod -l app=ollama`
- Monitor KEDA: `kubectl logs -n keda -l app.kubernetes.io/name=keda-http-add-on | head -20`

**Note**: Subsequent requests are faster once pods are running. Additional requests may route to replica 2 if load-balanced.

### KEDA Installation Error: Manifest Not Found (404)

**Issue**: KEDA HTTP Add-on installation fails with 404 error
```
error: unable to recognize "https://github.com/...": no matches for kind
```

**Cause**: KEDA project has moved its manifest locations in recent versions. Direct manifest URLs from GitHub are unreliable.

**Solution**: Use Helm to install KEDA HTTP Add-on (handles dependencies and versioning automatically):
```bash
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install HTTP Add-on via Helm
helm install http-add-on kedacore/keda-add-ons-http --namespace keda --create-namespace

# Verify installation
kubectl get pods -n keda | grep http-add-on
```

**Why Helm?**: Helm is the official recommended way to install KEDA HTTP Add-on. It automatically:
- Resolves all dependencies correctly
- Keeps versions in sync
- Avoids manifest location issues
- Simplifies upgrades and management

### KEDA HTTP Add-on: Namespace Not Found

**Issue**: KEDA HTTP Add-on installation fails with namespace error
```
Error from server (NotFound): namespace "keda" not found
```

**Cause**: The `keda` namespace doesn't exist yet (common on brand-new clusters).

**Solution**: Use `--create-namespace` flag when installing via Helm:
```bash
# Add KEDA Helm repository
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install HTTP Add-on with --create-namespace to create the namespace
helm install http-add-on kedacore/keda-add-ons-http --namespace keda --create-namespace

# Verify installation
kubectl get pods -n keda
```

**Note**: The `--create-namespace` flag ensures the namespace is created if it doesn't exist. This is automatically handled by the project's deployment instructions.

### Model Not Loading

**Issue**: No models appear in `/api/tags`
```bash
# Check if model was seeded
kubectl exec -it deployment/ollama-cpu -- ls ~/.ollama/models/manifests/

# Check PVC attachment

# Check CPU usage (if CPU-bound)
kubectl top pod -l app=ollama
```

**Solution**:
```bash
# Re-run seed script (may take longer on CPU)
./scripts/seed-initial-model.sh

# If timeout occurs on CPU, increase wait time in seed-initial-model.sh
```

### Slow Inference Performance

**Issue**: API responses are very slow (>30s for small prompts)

**Causes:**
- CPU-based inference is slower than GPU
- Pod may be competing with other workloads
- Model may be swapping to disk

**Solution:**
- Check CPU usage: `kubectl top pod -l app=ollama`
- Consider GPU upgrade: Uncomment GPU nodeSelector in k8s/deployment.yaml
- Check pod logs: `kubectl logs -l app=ollama | tail -20`
- Increase CPU request in deployment.yaml for better performance

## Common Deployment Errors & Fixes

### Error: `Insufficient cpu` or `Insufficient memory`

**Issue**: Pod stays in Pending state with resource constraints
```
Warning  Insufficient cpu     ... insufficient cpu
Warning  Insufficient memory  ... insufficient memory
```

**Cause**: Project-wide or region-wide CPU quota exhausted. Common in us-central1 during peak hours.

**Solutions (in order):**
1. **Try a different region**: 
   ```bash
   REGION=us-east1 ./scripts/setup-cluster.sh
   ```
2. **Check GCP quotas**: Go to GCP Console → Quotas → Search "CPU for N1 machines" and "Memory for N1 machines"
3. **Wait and retry**: Spot quotas fluctuate throughout the day; try again in 30 minutes

### Error: `412 Precondition Failed: Newer version of Ollama required`

**Issue**: Model pull fails with 412 error
```
Error 412: Newer version of Ollama required to pull this model
```

**Cause**: Ollama version too old to support modern models (project requires 0.2.x+)

**Solution**: Project uses `ollama/ollama:latest` tag, which should auto-update. If error persists:
```bash
# Force pod restart to pull latest image
kubectl rollout restart deployment/ollama-cpu

# Wait for new pod to start
kubectl wait --for=condition=ready pod -l app=ollama --timeout=300s

# Re-run seeding
./scripts/seed-initial-model.sh
```

### Error: Pod in `CrashLoopBackOff` - Backoff timer tripped

**Issue**: Pod repeatedly crashes then backs off (scales but immediately fails)
```
Status: CrashLoopBackOff  Restarts: 5  
Warning  BackOff  ... restarting failed container
```

**Cause**: KEDA's HTTPScaledObject triggers retry logic that interacts poorly with Kubernetes backoff timer.

**Solution**: Delete and recreate the deployment to reset the backoff timer:
```bash
# Delete current deployment
kubectl delete deployment ollama-cpu

# Reapply all manifests
kubectl apply -f k8s/

# Re-seed the model
./scripts/seed-initial-model.sh
```

### Error: `namespace keda not found`

**Issue**: HTTP Add-on Helm install fails: `Error: namespace "keda" not found`

**Solution**: Use `--create-namespace` flag (already in all project instructions):
```bash
helm install http-add-on kedacore/keda-add-ons-http --namespace keda --create-namespace
```

## Best Practices

### Security
- **Use IAM Service Accounts**: Don't use default compute account
- **Network Policy**: Restrict ingress to KEDA only (if in shared cluster)
- **Private Cluster**: Set `--master-ipv4-cidr` in setup-cluster.sh for private GKE

### Cost Management  
- **Monitor costs**: `gcloud billing accounts list` 
- **Set budgets**: GCP Console → Billing → Budgets & Alerts
- **Delete immediately**: Always run `./scripts/cleanup.sh` when done (prevents phantom costs)

### Performance
- **CPU-based inference**: Currently slower than GPU; suitable for testing and lightweight loads
- **Use streaming**: Set `stream: true` for faster time-to-first-token
- **Batch requests**: Group requests during active periods to minimize cold-start overhead
- **Monitor latency**: Check response times with `time curl ...` to identify bottlenecks
- **Switch to GPU**: Uncomment GPU nodeSelector in k8s/deployment.yaml for 5-10x faster inference (adds ~$70/mo)

### High Availability (Multi-Region)
For production, consider:
1. Deploy to multiple regions (e.g., us-central1, europe-west1)
2. Use Cloud Load Balancer for geographic failover
3. Replicate models across persistent disks

## Cleanup (Important: Stop Billing)

**WARNING**: Resources will continue to incur charges until deleted!
```bash
./scripts/cleanup.sh
```

**What it does:**
1. Deletes KEDA and Ollama resources
2. Deletes persistent disk (critical to avoid $5/month storage charges)
3. Deletes entire GKE cluster
4. Cleans up orphaned disks and load balancers

**Verify cleanup:**
```bash
gcloud container clusters list
gcloud compute disks list --filter="zone:us-central1*"
```

Should return empty results.

## 
**Chat Mode** (multi-turn conversation)
```bash
curl --resolve ollama.gke.dev:80:$KEDA_IP http://ollama.gke.dev/api/chat \
  -d '{
    "model": "gemma2:2b",
    "messages": [
      {"role": "user", "content": "What is the capital of France?"}
    ],
    "stream": false
  }' | jq '.message.content'
```

**Performance Tips:**
- Use `stream: true` for interactive, real-time responses
- Set `num_predict: N` to limit response length (saves tokens/time)
- Use `temperature: 0.3` for factual content, `0.9` for creative content

## Testing

### Jupyter Notebook
Test the API interactively with the provided notebook:
```bash
# Start Jupyter in VS Code or terminal
jupyter notebook notebooks/test-api.ipynb

# Or configure endpoint and run in VS Code notebooks
export OLLAMA_ENDPOINT=http://$KEDA_IP
# Then use the notebook cells to test
```

**Notebook features:**
- Connection test (verifies API is reachable)
- Inference test (full request/response cycle with metrics)
- Advanced examples (code generation, creative writing)
- Error handling and diagnostics

### Manual Testing with kubectl
Port-forward for local testing (when in same network):
```bash
kubectl port-forward svc/ollama-service 11434:80 &
curl http://localhost:11434/api/tags
```

## Cost Analysis
GKE Management	$0.10/hr	$0.00 (via GCP Free Tier Credit)
NVIDIA L4 GPU	~$0.70/hr	~$0.11/hr
Total Hourly	~$0.85/hr	~$0.15/hr
Note: Prices are estimates based on 2026 us-central1 rates. When the Pod is scaled to 0, costs drop to near-zero.

License
MIT License - Created by Stephen Ancliffe