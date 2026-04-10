# Contributing to GKE Ollama Spot AI

Thank you for contributing to this project! This document provides guidelines for contribution workflow, commit conventions, and best practices.

## Code of Conduct

Treat all contributors with respect and professionalism.

## Getting Started

### Prerequisites
- Google Cloud Project with Billing enabled
- `gcloud` CLI installed and authenticated
- `kubectl` installed
- Bash shell
- Git

### Setup Development Environment

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/gke-ollama-spot-ai.git
   cd gke-ollama-spot-ai
   ```

2. **Configure Git with commit template**
   ```bash
   git config commit.template .gitmessage
   ```

3. **Install pre-commit hooks** (optional but recommended)
   ```bash
   bash -n scripts/*.sh  # Manually validate scripts
   ```

## Branch Strategy

Use the following branch naming convention:

```
feature/<description>   # New features: feature/add-model-selection
bugfix/<description>    # Bug fixes: bugfix/fix-gpu-timeout
hotfix/<description>    # Urgent production fixes: hotfix/rollback-v1.2
docs/<description>      # Documentation: docs/expand-troubleshooting
chore/<description>     # Maintenance: chore/update-keda-version
```

### Example Workflow

1. **Create feature branch**
   ```bash
   git checkout -b feature/add-mistral-support
   ```

2. **Make changes** (test locally first)
   ```bash
   # Edit files
   # Test with: kubectl apply --dry-run -f k8s/
   # Test scripts: bash -n scripts/setup-cluster.sh
   ```

3. **Commit with conventional format**
   ```bash
   git add .
   git commit  # Opens editor with .gitmessage template
   ```

4. **Push and open PR**
   ```bash
   git push origin feature/add-mistral-support
   ```

## Commit Message Convention

Follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- **feat**: New feature or capability
- **fix**: Bug fix or correction
- **docs**: Documentation changes (README, comments)
- **infra**: Kubernetes manifests, Terraform, infrastructure scripts
- **test**: Test additions or updates
- **chore**: Dependencies, maintenance, no functional change
- **refactor**: Code restructuring without behavior change

### Scope (Optional)
Specific area: `deployment`, `scripts`, `keda`, `storage`, `models`, `readme`, `ci`, etc.

### Subject
- Use imperative mood: "add" not "added"
- Don't capitalize first letter
- No period at end
- Maximum 50 characters

### Body
- Explain *what* and *why*, not *how*
- Wrap at 72 characters
- Use bullet points if multiple items

### Footer
Reference issues and breaking changes:
```
Closes #42
Fixes #18
BREAKING CHANGE: Deployment now requires KEDA v2.13 minimum
```

### Examples

**Good:**
```
feat(keda): add HTTP interceptor for scale-to-zero

Implement KEDA HTTPScaledObject to enable traffic-based autoscaling.
This allows the Ollama deployment to scale to 0 replicas when idle,
reducing costs from $511/mo to ~$5/mo in storage only.

Closes #42
```

**Good:**
```
fix(deployment): quote GPU resource limits

Change nvidia.com/gpu: 1 to nvidia.com/gpu: "1" to fix Kubernetes
validation error. Integer values cause apiserver rejection.

Fixes #18
```

**Good:**
```
docs: expand troubleshooting section with KEDA timeout guide
```

## Testing Changes

Before submitting a PR:

1. **Validate shell scripts**
   ```bash
   bash -n scripts/setup-cluster.sh
   bash -n scripts/seed-initial-model.sh
   bash -n scripts/cleanup.sh
   ```

2. **Validate Kubernetes manifests**
   ```bash
   kubectl apply -f k8s/ --dry-run=client
   ```

3. **Check for hardcoded secrets**
   ```bash
   grep -r "password\|secret\|api-key\|token" scripts/ k8s/ README.md
   ```

4. **Test locally** (if possible)
   ```bash
   # On staging GKE cluster (CPU-based testing)
   ./scripts/setup-cluster.sh
   kubectl apply -f k8s/
   ./scripts/seed-initial-model.sh
   # Test API calls (note: CPU inference will be slower than GPU)
   ./scripts/cleanup.sh
   ```

5. **For GPU testing** (optional)
   - Uncomment GPU nodeSelector in k8s/deployment.yaml
   - Ensure L4 GPU quota in GCP console
   - Update deployment.yaml resource limits to GPU: "1"

## Pull Request Process

1. **Create PR** with title matching commit format: `feat(keda): add HTTP interceptor`
2. **Use the PR template** - fill out all sections
3. **Link related issues** in PR description
4. **Ensure CI/CD passes** (all GitHub Actions complete)
5. **Request review** from code owners
6. **Respond to feedback** and make changes if requested
7. **Squash commits** before merge (optional, depends on maintainer preference)
8. **Merge to main** only after approval

## Versioning & Releases

Semantic Versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes (e.g., new Ollama version requirement)
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

### Tagging a Release

```bash
# Create and push release tag
git tag -a v1.2.0 -m "feat: add KEDA HTTP autoscaling"
git push origin v1.2.0

# Verify tag
git tag -l -n1
```

## Documentation

- **README.md**: Main project documentation, user-facing
- **CONTRIBUTING.md**: This file, development guidelines
- **CHANGELOG.md**: Detailed change history by version
- **Code comments**: Explain *why*, not *what*

### When to Update Docs
- Adding/changing user-facing features → Update README
- Infrastructure changes → Update README architecture section
- New troubleshooting discovered → Add to README troubleshooting
- Any non-trivial change → Add to CHANGELOG as unreleased

## Code Style

### Bash Scripts
- Use `set -e` at start to fail on errors
- Add comments for complex sections
- Use `echo "[INFO]"`, `echo "[SUCCESS]"`, `echo "[WARNING]"` for output
- Avoid hardcoding project-specific values (use variables)

### Kubernetes YAML
- Use 2-space indentation
- Add comments explaining non-obvious settings
- Include resource requests/limits
- Document why specific settings are chosen

### Python/Notebooks
- Follow PEP 8 when possible
- Add docstrings to functions
- Include error handling
- Comment complex logic

## Issues

### Reporting Bugs
- Use the bug report template
- Include environment details (Ollama version, GKE version, GPU type)
- Provide steps to reproduce
- Include relevant error logs

### Requesting Features
- Use the feature request template
- Explain the use case and motivation
- Suggest implementation approach if possible
- Explain how success would be measured

## Questions?

- Open an issue with `[QUESTION]` label
- Check existing issues/discussions
- Review README and CONTRIBUTING.md first

---

Thank you for contributing! 🎉
