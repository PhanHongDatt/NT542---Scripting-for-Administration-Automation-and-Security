## 1. Hướng Dẫn Setup Môi Trường

### Bước 1.1: Cài đặt các công cụ bắt buộc
Máy tính của bạn cần phải có sẵn những món sau:
1. **Azure CLI**: Cung cấp lệnh `az` để giao tiếp với Azure.
2. **Kubectl**: Cung cấp lệnh `kubectl` để điều khiển cụm Kubernetes.
   - *Cách cài cực nhanh (Windows)*: Mở PowerShell (Run as Administrator) và chạy lệnh `az aks install-cli`. Cài xong thì tắt mở lại Terminal là xài được.
3. **Terraform**: Dùng để quản lý vòng đời hạ tầng (không bắt buộc nếu bạn không sửa hạ tầng).
4. **Git**: Để kéo Source code về máy tính.

### Bước 1.2: Lấy Source Code & Bỏ Private Key vào đúng chỗ
1. Clone repo Git của dự án về máy: 
   ```bash
   git clone <nhập_đường_dẫn_git_project_vào_đây>
   ```
2. Trưởng nhóm đã gửi cho bạn một file chìa khoá tên là `aks-key`. Bạn phải chép nó vào **đúng đường dẫn có tính bảo mật** sau (để không lọt lên Github):
   ```text
   cis-aks-audit/terraform/.ssh/aks-key
   ```

### Bước 1.3: Đăng nhập Azure & Xin cấp quyền
1. Gõ lệnh sau trên trình duyệt và đăng nhập bằng Mail nhận credit sinh viên:
   ```powershell
   az login
   ```
2. Bạn phải báo trưởng nhóm thêm Email của bạn vào danh sách có quyền hạn **Contributor** vào ổ tài nguyên tên là `rg-cis-aks-audit`. Nếu không có quyền, bạn sẽ bị Azure đá văng khi gõ lệnh.

### Bước 1.4: Tải Kubeconfig (Kết nối máy tính với AKS)
Sau khi có quyền từ sếp, bạn gõ lệnh này để thọt dây sang hệ thống Azure và lấy chìa khoá điều khiển `kubectl` về nhét vào ổ C của bạn:
```powershell
az aks get-credentials --resource-group rg-cis-aks-audit --name aks-cis-audit --overwrite-existing
```
*Lưu ý: Bạn nào thích xài hàng Linux (Ubuntu/WSL) để gõ lệnh cho giống sách thì nhớ copy file `.kube/config` từ Windows nhảy sang Linux bằng lệnh `cp /mnt/c/Users/<tên_user_trong_máy_bạn>/.kube/config ~/.kube/config` nhé!*

---

## 💰 2. Ý Thức Giữ Gìn Ngân Sách Azure (BẮT BUỘC)
> **⚠️ LƯU Ý CHI PHÍ:** Do tài khoản Azure for Students bị giới hạn số lượng Credit nhất định, **MỌI NGƯỜI BẮT BUỘC PHẢI TẮT CLUSTER NGAY SAU KHI LÀM XONG (Ví dụ: đi ngủ, đi chơi, đi học)**. Chỉ mở lên khi làm bài.

### ☀️ Bật Cluster (Trước khi code)
```powershell
az aks start --name aks-cis-audit --resource-group rg-cis-aks-audit
```
*(Chờ khoảng 5 phút)* Rồi kiểm tra xem máy chủ đã thức dậy và giãn cơ sẵn sàng chưa bằng lệnh:
```powershell
kubectl get nodes
``` 
*(Nếu ra chữ `Ready` là OK múc luôn)*

### 🌙 Tắt Cluster (Sau khi làm xong)
```powershell
az aks stop --name aks-cis-audit --resource-group rg-cis-aks-audit
```
Kiểm tra xem nó đã "tắt thở" thành công chưa bằng lệnh soi thông số điện năng: 
```powershell
az aks show --name aks-cis-audit --resource-group rg-cis-aks-audit --query powerState.code -o tsv
```
*(Output phải hiện chình ình chữ `Stopped`)*
