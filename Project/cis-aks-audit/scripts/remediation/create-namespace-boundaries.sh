#!/bin/bash
# Create namespace boundaries: namespace, default-deny NetworkPolicy, ResourceQuota, RoleBinding to admin
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../helpers/common.sh"

echo ""
echo -e "${C_BLUE}Create Namespace Boundaries${C_RESET}"

for tool in kubectl; do
    if ! command -v "$tool" &>/dev/null; then
        echo -e "${C_RED}[ERROR]${C_RESET} '$tool' chưa cài. Vui lòng cài trước."
        exit 1
    fi
done

read -rp "Tên namespace muốn tạo (ví dụ: team-a): " NS_NAME
if [ -z "$NS_NAME" ]; then
    echo "Canceled - no namespace provided."; exit 1
fi

read -rp "Subject kind (User/Group/ServiceAccount) [User]: " SUBJECT_KIND
SUBJECT_KIND=${SUBJECT_KIND:-User}
read -rp "Subject name (user: user@example.com or group: devs@example.com) : " SUBJECT_NAME
if [ -z "$SUBJECT_NAME" ]; then
    echo "No subject provided — chỉ tạo namespace và các resource cơ bản.";
fi

log_info "Tạo namespace: $NS_NAME"
kubectl create namespace "$NS_NAME" --dry-run=client -o yaml | kubectl apply -f -

log_info "Áp default-deny NetworkPolicy cho namespace $NS_NAME"
cat <<EOF | kubectl apply -n "$NS_NAME" -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

log_info "Áp ResourceQuota mẫu cho namespace $NS_NAME"
cat <<EOF | kubectl apply -n "$NS_NAME" -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: rq-basic
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "20"
EOF

if [ -n "$SUBJECT_NAME" ]; then
    log_info "Tạo RoleBinding: gán 'admin' trong namespace $NS_NAME cho ${SUBJECT_KIND}:${SUBJECT_NAME}"
    # Map user input to proper subject structure
    if [[ "${SUBJECT_KIND,,}" == "serviceaccount" ]]; then
        # expect form: name:namespace or name
        IFS=':' read -r sa_name sa_ns <<< "$SUBJECT_NAME"
        sa_ns=${sa_ns:-$NS_NAME}
        kubectl create rolebinding namespace-admin-binding -n "$NS_NAME" --role=admin --serviceaccount="$sa_ns:$sa_name" --dry-run=client -o yaml | kubectl apply -f -
    else
        kubectl create rolebinding namespace-admin-binding -n "$NS_NAME" --role=admin --${SUBJECT_KIND,,}="$SUBJECT_NAME" --dry-run=client -o yaml | kubectl apply -f -
    fi
    log_pass "Đã tạo RoleBinding (admin) trong namespace $NS_NAME cho ${SUBJECT_KIND}:${SUBJECT_NAME}"
else
    log_warn "Không cung cấp subject - chỉ tạo namespace + policies + resourceQuota." 
fi

echo ""
log_info "Hoàn tất. Kiểm tra bằng: kubectl get ns $NS_NAME && kubectl get networkpolicy -n $NS_NAME && kubectl get resourcequota -n $NS_NAME"

exit 0
