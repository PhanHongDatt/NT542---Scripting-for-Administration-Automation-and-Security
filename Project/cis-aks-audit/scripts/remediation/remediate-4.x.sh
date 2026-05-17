#!/bin/bash
# =====================================================================
# remediate-4.x.sh
# Remediation cho CIS AKS Benchmark Section 4.x
# Sửa lỗi trực tiếp trên các file YAML K8s Manifests và apply lại.
# =====================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/common.sh"
MANIFESTS_DIR="$SCRIPT_DIR/../../k8s-manifests"
BACKUP_DIR="$MANIFESTS_DIR/.backup-$(date +%Y%m%d-%H%M%S)"

main() {
    echo ""
    echo -e "${C_BLUE}╔══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BLUE}║   CIS AKS Benchmark v1.8.0 — Remediation Section 4.x        ║${C_RESET}"
    echo -e "${C_BLUE}║   Kubernetes Manifests (Pod Security, Secrets, Namespace)    ║${C_RESET}"
    echo -e "${C_BLUE}╚══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo -e "  Thời gian: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    log_section "ĐANG TỰ ĐỘNG SỬA LỖI SECTION 4.x"

    # #2: Backup trước khi sửa
    mkdir -p "$BACKUP_DIR"
    cp "$MANIFESTS_DIR"/*.yaml "$BACKUP_DIR/" 2>/dev/null
    log_info "Đã backup manifest gốc vào: $BACKUP_DIR"

    # 1. Sửa lỗi 03-busybox-bad.yaml (4.2.x)
    local file_busybox="$MANIFESTS_DIR/03-busybox-bad.yaml"
    if [ -f "$file_busybox" ]; then
        log_info "Đang sửa đổi file: 03-busybox-bad.yaml (Các vi phạm Pod Security)"
        cat << 'EOF' > "$file_busybox"
apiVersion: v1
kind: Pod
metadata:
  name: busybox-bad
  namespace: staging
  labels:
    purpose: audit-test-remediated
    audit-compliance: "pass"
spec:
  hostPID: false
  hostIPC: false
  hostNetwork: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
    - name: busybox
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      securityContext:
        privileged: false
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
        capabilities:
          drop:
            - ALL
      resources:
        requests:
          memory: "32Mi"
          cpu: "50m"
        limits:
          memory: "64Mi"
          cpu: "100m"
EOF
        log_pass "Đã sửa file 03-busybox-bad.yaml ✓"
    fi

    # 2. Sửa lỗi 04-secret-env-bad.yaml (4.5.1)
    local file_secret="$MANIFESTS_DIR/04-secret-env-bad.yaml"
    if [ -f "$file_secret" ]; then
        log_info "Đang sửa đổi file: 04-secret-env-bad.yaml (Vi phạm Inject Secret Env)"
        
        # Do YAML cấu trúc phức tạp khi đổi từ env sang volumeMounts, ta sẽ ghi đè nội dung an toàn
        cat << 'EOF' > "$file_secret"
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
  namespace: dev
  labels:
    audit-test: "true"
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=
  username: ZGJfdXNlcg==
---
apiVersion: v1
kind: Pod
metadata:
  name: app-with-env-secret
  namespace: dev
  labels:
    audit-compliance: "pass"
    purpose: audit-test-remediated
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "sleep 3600"]
      # ĐÃ SỬA LỖI (4.5.1): Chuyển thành Volume Mount thay vì env variables
      volumeMounts:
        - name: secret-volume
          mountPath: /etc/secrets
          readOnly: true
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        runAsUser: 1000
      resources:
        requests:
          memory: "32Mi"
          cpu: "50m"
        limits:
          memory: "64Mi"
          cpu: "100m"
  volumes:
    - name: secret-volume
      secret:
        secretName: db-credentials
EOF
        log_pass "Đã cấu trúc lại file 04-secret-env-bad.yaml dùng Volume Mount ✓"
    fi

    echo ""
    # 3. Xóa pods cũ vì nhiều trường spec của Pod là immutable.
    log_info "Đang xóa pods vi phạm cũ để apply cấu hình đã sửa..."
    kubectl delete pod busybox-bad -n staging --ignore-not-found=true
    kubectl delete pod app-with-env-secret -n dev --ignore-not-found=true

    # 4. Apply lại vào cluster (#3: chỉ apply file đã sửa)
    if ask_remediate "Apply các file manifest đã sửa lỗi vào cluster? [Y/n]: "; then
        log_info "Đang apply..."
        local apply_ok=true

        if [ -f "$file_busybox" ]; then
            kubectl apply -f "$file_busybox" || apply_ok=false
        fi
        if [ -f "$file_secret" ]; then
            kubectl apply -f "$file_secret" || apply_ok=false
        fi

        if [ "$apply_ok" = true ]; then
            log_pass "Đã apply thành công lên cluster! ✓"

            # #4: Verify pods sau apply
            log_info "Đang verify pods..."
            kubectl wait pod busybox-bad -n staging --for=condition=Ready --timeout=30s 2>/dev/null \
                && log_pass "Pod busybox-bad: Ready ✓" \
                || log_warn "Pod busybox-bad: chưa Ready sau 30s"
            kubectl wait pod app-with-env-secret -n dev --for=condition=Ready --timeout=30s 2>/dev/null \
                && log_pass "Pod app-with-env-secret: Ready ✓" \
                || log_warn "Pod app-with-env-secret: chưa Ready sau 30s"
        else
            log_fail "Apply thất bại. Khôi phục từ backup:"
            log_warn "  kubectl apply -f $BACKUP_DIR/"
        fi
    else
        log_warn "Bỏ qua việc apply lên cluster. Lệnh thủ công: kubectl apply -f $file_busybox && kubectl apply -f $file_secret"
    fi

    echo ""
    log_section "HOÀN TẤT REMEDIATION 4.x"
}

main
