# harness-upload-template-abap

# rap-upload-harness

Harness chuẩn cho chức năng **Upload Excel hàng loạt** trên ABAP RAP (S/4HANA Cloud).

Cách dùng với Claude Code: copy thư mục này vào `.claude/skills/rap-excel-upload/` của project
(hoặc trỏ tới nó trong CLAUDE.md), rồi yêu cầu:

- "Dùng skill rap-excel-upload, làm app upload cho <đối tượng>" -> sinh đủ bộ object.
- "Dùng skill rap-excel-upload, thêm template <tên> vào app <APP>" -> sinh thêm child.

Cấu trúc:

```
SKILL.md                 chuẩn + quy trình (đọc trước)
reference/               giải thích pattern, naming, Excel, status, checklist
templates/               object mẫu có placeholder {{...}} (xem reference/02-naming.md)
examples/fixed-asset/    bộ object thật: Mass Create Fixed Asset (Root + 2 child)
tools/read_xlsx.py       dump file .xlsx ra text để đối chiếu cột
```

Object của ví dụ cố ý không đưa vào `examples/fixed-asset/`:
`ZI_D_MCH_FA_UPL` / `ZC_D_MCH_FA_UPL` (+ MDE) và `zcl_fa_master_asset_upload` giống child 2 chỉ khác
`AssetClass` thay `MasterFixedAsset`, không có `Sequence`, luôn gửi `_Ledger`, action `CreateMasterFixedAsset`;
`zi_req_sta_crud_poc_vh`, `zabs_file_crud_poc` (download), service definition/binding là object dùng chung đã có trên hệ thống.
