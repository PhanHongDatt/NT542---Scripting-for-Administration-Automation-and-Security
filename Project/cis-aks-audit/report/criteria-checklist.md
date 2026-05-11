# NT542 CIS AKS Audit - Criteria Checklist

Generated: 2026-05-06

## Summary

- BEFORE audit: 20 PASS, 11 FAIL, 0 WARN, 29 controls.
- AFTER audit: 29 PASS, 0 FAIL, 0 WARN, 29 controls.
- Dashboard: `report/dashboard.html`.
- AFTER reports use `*-v2.json/html`.

## Completed By Evidence

| Week | ID | Status | Evidence |
|---|---|---|---|
| W1 | ĐV-02 | Local OK | `az`, `kubectl`, `jq`, `terraform`, `git`, `code` installed on this machine. |
| W1 | ĐV-03 | Local OK | Azure login works; current account has Contributor on project scope. |
| W1 | ĐV-04 | Local OK | `kubectl`, `jq`, `terraform` available. |
| W1 | ĐV-07 | Local OK | VS Code and Azure/Kubernetes/Terraform/ShellCheck extensions are installed. |
| W2 | ĐV-08 to ĐV-15 | Completed | Terraform files exist; AKS `aks-cis-audit` is running; `kubectl get nodes` returns Ready; sample workloads deployed. |
| W3 | ĐV-16 to ĐV-20 | Completed | `common.sh`, audit 3.1 and 3.2 run successfully; 3.1 = 4/4 PASS, 3.2 = 9/9 PASS. |
| W4 | ĐV-21 to ĐV-24 | Completed | Audit 3.2 extended checks, RBAC, and Pod Security scripts exist and run. |
| W5 | ĐV-25 to ĐV-28 | Completed | Audit 4.4, 4.5+4.6, 5.1+5.4.1, 5.4.3+5.4.4 scripts exist and run. |
| W6 | ĐV-29 | Completed | `scripts/run-all.sh` works as master audit equivalent; `scripts/run-audit-v2.sh` was repaired for AFTER runs. |
| W7 | ĐV-31 | Completed | Node-level controls pass; remediation script verifies kubelet, SSH, NSG. Node image update is available but not required by current audit controls. |
| W7 | ĐV-32 | Completed | K8s remediation applied: Pod Security, secret volume mount, NetworkPolicy, Namespace boundaries. |
| W7 | ĐV-33 | Completed | Azure remediation applied: API authorized IP configured. |
| W7 | ĐV-34 | Completed | Full AFTER audit generated V2 reports and dashboard. |

## Items Requiring Manual Team Confirmation

| ID | Note |
|---|---|
| ĐV-01 | `az consumption budget list` returns 0 budgets in this subscription. If Budget Alert was created elsewhere, confirm from Azure Portal. |
| ĐV-02/03/04/07 | The "ALL members" requirement cannot be verified from this machine; each member should run the tool/login checklist. |
| ĐV-05 | `terraform/.ssh/aks-key.pub` exists, but private key `aks-key` is intentionally not in this local copy. Confirm the group has received it securely. |
| ĐV-06 | Folder structure exists, but this local copy is not a Git worktree (`.git` not present). Confirm the upstream GitHub repo is the source of truth. |

## Residual Notes

- API server authorized IP is `14.169.0.0/16` instead of a single `/32` because the public IP changed during testing. This still avoids `0.0.0.0/0` and passes the audit, but the team should tighten it to stable member IPs before final submission if possible.
- AKS node image has a newer version available: current `AKSUbuntu-2204gen2containerd-202603.18.1`, latest observed `AKSUbuntu-2204gen2containerd-202604.24.0`. This was not upgraded automatically to avoid an unrequested node restart during the report run.
