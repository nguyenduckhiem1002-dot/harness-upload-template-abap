# 02. Quy tắc đặt tên và placeholder

## Placeholder dùng trong `templates/`

Thay TẤT CẢ placeholder trước khi đưa code vào ADT. Cột "Fixed Asset" là giá trị thật của ví dụ.

| Placeholder | Ý nghĩa | Fixed Asset (child 1) | Fixed Asset (child 2) |
|---|---|---|---|
| `{{APP}}` | mã app, viết HOA trong tên view | `MCO_FA` | `MCO_FA` |
| `{{app}}` | mã app, viết thường trong tên table/class | `mco_fa` | `mco_fa` |
| `{{APP_LABEL}}` | nhãn app cho `@EndUserText.label` | `Mass Create Fixed Asset` | |
| `{{ROOT_TBL}}` | bảng Root | `ztb_m_mco_fa_upl` | |
| `{{ROOT_DRAFT}}` | draft table Root (<= 16 ký tự) | `ztb_m_mco_fa_d` | |
| `{{ROOT_I}}` | root view entity | `ZR_M_MCO_FA_UPL` | |
| `{{ROOT_C}}` | root projection | `ZC_M_MCO_FA_UPL` | |
| `{{BP_CLASS}}` | behavior pool | `zbp_r_m_mco_fa_upl` | |
| `{{ABS_UPLOAD}}` | abstract entity tham số uploadExcel | `zabs_file_crud_poc_n` | |
| `{{ABS_DOWNLOAD}}` | abstract entity result downloadFile | `zabs_file_crud_poc` | |
| `{{STATUS_VH}}` | value help view cho status | `zi_req_sta_crud_poc_vh` | |
| `{{MSG_CLASS}}` | message class | `Z_FILE_MSG` (TODO thật) | |
| `{{X}}` / `{{x}}` | mã child HOA / thường | `MCH_FA_UPL` / `mch_fa_upl` | `MCH_FASUPL` / `mch_fasupl` |
| `{{CHILD_TBL}}` | bảng child | `ztb_d_mch_fa_upl` | `ztb_d_mch_fasupl` |
| `{{CHILD_DRAFT}}` | draft table child (<= 16 ký tự) | `ztb_d_mch_fa_d` | `ztb_d_fasup_d` |
| `{{CHILD_I}}` | interface view child | `ZI_D_MCH_FA_UPL` | `ZI_D_MCH_FASUPL` |
| `{{CHILD_C}}` | projection child | `ZC_D_MCH_FA_UPL` | `ZC_D_MCH_FASUPL` |
| `{{CHILD_ALIAS}}` | alias trong BDEF / handler | `Data` | `DataSub` |
| `{{child_alias}}` | alias viết thường cho tên class `lhc_` | `data` | `datasub` |
| `{{CHILD_ASSOC}}` | association từ Root | `_Data` | `_DataSub` |
| `{{CHILD_LABEL}}` | nhãn facet / headerInfo | `Asset List` | `Asset Sub-number List` |
| `{{CHILD_TYPE_NAME}}` | headerInfo typeName | `Asset` | `Asset Sub-number` |
| `{{TEMPLATE_CODE}}` | giá trị radio Template Type (1 ký tự) | `M` | `S` |
| `{{TEMPLATE_CONST}}` | tên hằng trong `template_type` | `main` | `sub` |
| `{{API_CLASS}}` | API class | `zcl_fa_master_asset_upload` | `zcl_fa_sub_asset_upload` |
| `{{API_METHOD}}` | method tạo record | `create_assets` | `create_subnumbers` |
| `{{API_ENDPOINT}}` | entity set OData V4 | `/sap/opu/odata4/sap/api_fixedasset/srvd_a2x/sap/fixedasset/0001/FixedAsset` | như child 1 |
| `{{API_ACTION}}` | bound action (sau `SAP__self.`) | `CreateMasterFixedAsset` | `CreateFixedAsset` |
| `{{BUSINESS_FIELDS}}` | khối field nghiệp vụ theo cột Excel | 29 cột B..AC | 29 cột B..AD (có MasterFixedAsset) |
| `{{RESULT_FIELDS}}` | field API trả về cần lưu | `FixedAsset, MasterFixedAsset` | `FixedAsset, FixedAssetSubnumber` |
| `{{KEY_COLS_NOT_EMPTY}}` | cột dùng để loại dòng trống | `CompanyCode, AssetClass` | `CompanyCode, MasterFixedAsset` |

## Table Root: `templatetype` là tuỳ chọn

Template `ztb_m_app_upl.tabl.asstruct` có sẵn 2 dòng `@EndUserText.label : 'Template Type'` / `templatetype : abap.char(1);` cho app nhiều template.
App chỉ có 1 template: xoá 2 dòng đó và mọi chỗ `Templatetype` ở view/projection/BDEF/MDE/`lhc_Root` (xem SKILL.md mục Quy ước).

## Điền `{{BUSINESS_FIELDS}}` / `{{RESULT_FIELDS}}` trong table child

Table DDL không được có comment, nên hướng dẫn để ở đây thay vì trong template:

- 1 cột Excel = 1 field, đúng thứ tự cột; tên snake_case; nhãn bằng `@EndUserText.label : '...'` ngay trên field (không dùng `//`).
- Ưu tiên data element chuẩn SAP khi có: `bukrs`, `kostl`, `prctr`, `werks_d`, `fb_segment`, `lifnr`, `anln1`, `anln2`, `vbeln_va`, `posnr_va`, `etenr`. Còn lại `abap.char(n)` với n = độ dài ở dòng 4 của template; cờ `abap.char(1)` ('X'/''); ngày `abap.dats`; số nguyên `abap.int4`; số lượng `abap.dec(15,3)` + `abap.unit(3)` nếu API trả unit.
- `{{RESULT_FIELDS}}`: field API trả về cần lưu, đặt tên theo property OData (`fixed_asset : anln1`, `fixed_asset_subnumber : anln2`, `schedule_line_result : etenr`).
- Ví dụ đầy đủ: `examples/fixed-asset/ztb_d_mch_fa_upl.tabl.asstruct`, `examples/fixed-asset/ztb_d_mch_fasupl.tabl.asstruct`.

## Quy tắc

1. **Prefix cố định**
   - Table Root `ztb_m_`, table child `ztb_d_`, draft table hậu tố `_d`.
   - Root view `ZR_M_`, child interface `ZI_D_`, projection `ZC_M_` / `ZC_D_`.
   - Behavior pool `zbp_r_m_<app>_upl`. API class `zcl_<đối tượng>_upload`.
2. **Độ dài**: tên table/draft table tối đa 16 ký tự. Khi `ztb_d_<app>_<x>_d` quá dài, cắt `<x>` lại (ví dụ `ztb_d_fasup_d`), nhưng tên view/alias vẫn giữ đủ nghĩa.
3. **Alias**: child đầu tiên là `Data`/`_Data`; child tiếp theo đặt theo nghiệp vụ, ngắn, CamelCase (`DataSub`, `DataChange`). Alias cũng là tên dùng trong `ENTITY <Alias>` và `CREATE BY \_<Assoc>`.
4. **Field CDS**: CamelCase đúng chuẩn SAP (`CompanyCode`, `FixedAssetDescription`), table column snake_case (`company_code`). Mapping trong BDEF liệt kê đủ từng cặp, không dựa vào `corresponding` ngầm cho field có tên khác.
5. **Field kết quả API** đặt theo tên property OData trả về (`FixedAsset`, `FixedAssetSubnumber`) để đọc code là biết nguồn.
6. **Abstract entity upload** dùng chung cho mọi app (`mimeType, fileName, fileContent, fileExtension, templateType`). Không tạo abstract entity riêng từng app trừ khi dialog cần thêm tham số.
7. **Template Type code** là 1 ký tự, mặc định `'M'` cho template chính; giá trị rỗng từ UI phải được coi là `'M'` để tương thích record cũ.
8. **Hằng số** `file_status` và `template_type` khai báo lặp trong mỗi `lhc_*` (handler class không share private constants); giữ nội dung giống hệt nhau.
