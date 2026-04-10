# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- CPU-based testing configuration with multi-replica support (scales 0-2 pods)
- Enhanced troubleshooting section with CPU-specific guidance
- Performance tips for CPU vs GPU trade-offs

### Changed
- **BREAKING**: Deployment switched from GPU (L4) to CPU-based (4-core, 16GB RAM) for cost-effective testing
- Max replicas increased from 1 to 2 to support load balancing testing
- Updated architecture documentation to reflect CPU baseline with GPU upgrade instructions
- Resource specifications: 2 CPU → 4 CPU, 8GB → 16GB RAM (removed GPU requirement)
- Updated cost analysis to reflect CPU pricing (~$0.02-0.04/hr vs $0.11/hr for GPU)

### Fixed
- GPU resource limits properly quoted in previous version
- Clarified GPU as optional upgrade in deployment.yaml comments

---

## [1.0.0] - 2026-04-10

### Added
- Initial release of GKE Ollama Spot AI inference stack
- KEDA HTTP interceptor autoscaling (scale-to-zero when idle)
- Spot VM support (60-91% cost savings vs standard pricing)
- PersistentVolume for model caching across pod restarts
- Comprehensive deployment scripts:
  - `setup-cluster.sh`: GKE Autopilot cluster provisioning
  - `seed-initial-model.sh`: Initial model pulling and setup
  - `cleanup.sh`: Complete teardown and cost cleanup
- Kubernetes manifests:
  - `deployment.yaml`: Ollama deployment with GPU specs
  - `service.yaml`: Internal ClusterIP service
  - `storage.yaml`: 50GB persistent volume claim
  - `keda-autoscaler.yaml`: KEDA HTTP scaling configuration
- Jupyter notebook for API testing (`test-api.ipynb`)
- Production-ready health checks (readiness and liveness probes)
- Resource limits optimized for L4 GPUs
- Security notes and recommendations in code comments
- Comprehensive README with architecture overview, deployment steps, cost analysis
- All bash scripts with detailed comments and error handling

### Technical Details

**Architecture:**
- GKE Autopilot (us-central1)
- Spot NVIDIA L4 GPU (24GB VRAM)
- Ollama v0.1.32 (LLM inference engine)
- KEDA v2.13.0 (traffic-based autoscaling)
- 50GB Standard persistent disk for models

**Key Features:**
- Near-zero idle cost (~$5/month storage only)
- Graceful Spot VM preemption handling (25-second termination grace)
- Multiple model support (gemma2:2b included)
- HTTP-based request queuing for zero-downtime scaling
- Production-ready security notes

**Monitoring & Observability:**
- Health check probes (readiness: 10s interval, liveness: 20s interval)
- Comprehensive error logging in deployment
- KEDA HTTP interceptor logging for scale decisions

---

## Version Support

| Version | Released | Status | End of Life |
|---------|----------|--------|------------|
| 1.0.0   | 2026-04-10 | Current | TBD |

---

## Migration Guides

### From Standalone Ollama to GKE Deployment

If migrating from local Ollama to this GKE deployment:

1. Export your models from local Ollama:
   ```bash
   ollama list
   ```

2. Pull the same models in the GKE pod after deployment:
   ```bash
   kubectl exec -it <pod-name> -- ollama pull <model-name>
   ```

3. Update your client endpoints from `localhost:11434` to the KEDA interceptor IP

---

## Known Issues

None currently. See GitHub Issues for active work items.

---

## Future Roadmap

- [ ] Multi-region deployment support
- [ ] Custom Ollama image with non-root user
- [ ] PodDisruptionBudget for high availability
- [ ] Prometheus metrics collection
- [ ] Helm chart for easier deployment
- [ ] GitHub Actions CI/CD pipeline
- [ ] Support for additional GPU types (A100, H100)
- [ ] Automated model pulling (configurable via ConfigMap)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on how to contribute to this project.

---

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---

## Changelog Format

This changelog is updated with each release following these conventions:

### Categories
- **Added**: New features or functionality
- **Changed**: Changes in existing functionality
- **Deprecated**: Features marked for removal
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements or vulnerability fixes
- **Infra**: Infrastructure or deployment changes
- **Performance**: Performance improvements

### Version Format
- `[Unreleased]`: Changes not yet released
- `[X.Y.Z] - YYYY-MM-DD`: Released versions with date

### Commit Mapping
- `feat:` → Added
- `fix:` → Fixed  
- `infra:` → Infra
- `perf:` → Performance
- `refactor:` → Changed
- `docs:` → Documentation updates (usually not included in main changelog)
