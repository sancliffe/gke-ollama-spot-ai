---
name: Bug Report
about: Report a bug or issue with the deployment
title: "[BUG] "
labels: bug
assignees: ''

---

## Describe the Bug
<!-- Clear and concise description of the bug -->

## Steps to Reproduce
1. 
2. 
3. 

## Expected Behavior
<!-- What should have happened? -->

## Actual Behavior
<!-- What actually happened? Include error messages -->

## Environment
- **Ollama Version**: 
- **GKE Version** (output of `gcloud container clusters list`): 
- **KEDA Version**: 
- **GPU Type**: NVIDIA L4 / Other
- **Region**: us-central1 / Other
- **OS**: Linux / macOS / Windows

## Logs & Error Messages
```
Paste relevant logs here:
- kubectl logs -l app=ollama
- kubectl describe pod -l app=ollama
- GCP Cloud Logging output
```

## Current Workaround
<!-- If you've found a workaround, describe it here -->

## Additional Context
<!-- Any other context (screenshots, config changes, etc.) -->
