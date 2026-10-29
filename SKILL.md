---
name: rap-excel-upload
description: Chuẩn chung (harness) để xây chức năng "Upload Excel -> RAP draft -> Post Confirm gọi API" trên SAP S/4HANA Cloud (ABAP RAP managed + draft). Dùng khi cần tạo mới một app upload hàng loạt theo template Excel, thêm một loại template/child mới vào app upload đã có, hoặc review code upload cho đúng chuẩn. Có template object với placeholder và ví dụ chuẩn Mass Create Fixed Asset.
---

# RAP Excel Upload Harness

Chuẩn này mô tả MỘT pattern duy nhất, mọi app upload mới phải theo đúng pattern:

```
[Fiori Elements List Report]
   |  static action uploadExcel (dialog: file + Template Type)
   v
Root  = 1 file đã upload          (ztb_m_<app>_upl  ->  ZR_M_<APP>_UPL / ZC_M_<APP>_UPL)
   |  composition
   v
Child = 1 dòng dữ liệu trong file (ztb_d_<app>_<x>  ->  ZI_D_<APP>_<X> / ZC_D_<APP>_<X>)
   |  action PostConfirm (per row / multi-select)
   v
API class  zcl_<app>_<x>_upload  ->  zcl_call_api=>call_api (OData V4, JSON build tay)
```

Mỗi **loại template Excel** = 1 child entity riêng (bảng riêng, view riêng, handler riêng, API class riêng).
Root giữ file + trạng thái tổng; `Root.Templatetype` quyết định file được đổ vào child nào.

## Khi nào dùng harness này

| Yêu cầu của user | Việc phải làm |
|---|---|
| "Làm app upload mới cho đối tượng X" | Sinh đủ bộ object ở mục **Bộ object chuẩn** từ `templates/`, điền placeholder theo `reference/02-naming.md` |
| "Thêm template / child mới vào app upload có sẵn" | Chỉ sinh nhóm **Child** + sửa Root (composition, BDEF, MDE facet, `getExcelData`, `uploadExcel`), xem `reference/01-architecture.md` mục *Thêm child thứ 2* |
| "Sửa parse Excel theo template mới" | Đọc template bằng `tools/read_xlsx.py`, cập nhật `ty_file_upload_*` + `read_*_sheet` theo `reference/03-excel-template.md` |
| "Gọi API tạo/đổi X" | Sinh API class từ `templates/zcl_app_x_upload.clas.abap`, map payload theo curl/metadata user đưa |

## Quy trình bắt buộc (làm theo thứ tự)

1. **Thu thập đầu vào**, hỏi/nhận từ user, KHÔNG tự đoán:
   - File template Excel thật (dump bằng `python -I -X utf8 tools/read_xlsx.py <file> > dump.txt`).
   - Tên app code `<APP>` (ngắn, vd `MCO_FA`) và tên child `<X>` (vd `MCH_FA_UPL`, `MCH_FASUPL`).
   - Curl / payload mẫu của API đích (entity set, bound action, các node `_General`, `_Ledger`...).
   - Các data element/view dùng chung đã có trên hệ thống: `zde_attachment`, `zde_mime_type`, `zde_filename`, `zi_req_sta_crud_poc_vh`, `zcl_call_api`, `ztb_api_auth`.
2. **Đặt tên** theo `reference/02-naming.md`; kiểm tra draft table tối đa 16 ký tự.
3. **Sinh object** theo thứ tự activate trong `reference/05-checklist.md`, mỗi object lấy từ `templates/` và thay placeholder.
   Vùng `{{BUSINESS_FIELDS}}` trong template = danh sách cột nghiệp vụ của template Excel, đúng thứ tự cột.
4. **Mapping Excel -> entity**: XCO đọc theo VỊ TRÍ CỘT, nên thứ tự field trong `ty_file_upload_<x>` phải khớp cột A, B, C... của sheet. Ngày `DD.MM.YYYY` -> `to_date`, cờ `T/F` hoặc `X` -> `to_flag`, số -> `to_int`.
5. **API class**: 1 dòng Excel = 1 request POST; kết quả trả về theo `row_id`; HTTP 201 = success; lỗi lấy `error.message` từ body OData.
6. **Trạng thái**: cập nhật `Messagetype`/`Message` cho child, `Status`/`ZcountDone` cho Root theo `reference/04-status-flow.md` (tính trên TẤT CẢ child table của file, không chỉ dòng vừa xử lý).
7. **Bàn giao**: liệt kê những gì user phải tự làm trên ADT (tạo draft table bằng quick fix, message class, ledger config, activate theo thứ tự).

## Bộ object chuẩn (1 Root + N Child)

| Nhóm | Object | Template |
|---|---|---|
| Root | Table `ztb_m_<app>_upl` + draft `ztb_m_<app>_d` | `templates/ztb_m_app_upl.tabl.asstruct` |
| Root | View `ZR_M_<APP>_UPL` (root view entity) | `templates/zr_m_app_upl.ddls.asddls` |
| Root | Projection `ZC_M_<APP>_UPL` | `templates/zc_m_app_upl.ddls.asddls` |
| Root | MDE `ZC_M_<APP>_UPL` | `templates/zc_m_app_upl.ddlx.asddlxs` |
| Root | Abstract entity tham số upload (dùng chung mọi app) | `templates/zabs_file_upload.ddls.asddls` |
| Root | BDEF base `ZR_M_<APP>_UPL` + projection `ZC_M_<APP>_UPL` | `templates/zr_m_app_upl.bdef.asbdef`, `templates/zc_m_app_upl.bdef.asbdef` |
| Root | Behavior pool `zbp_r_m_<app>_upl` (Local Types) | `templates/zbp_r_m_app_upl.clas.locals_imp.abap` |
| Child (mỗi template) | Table `ztb_d_<app>_<x>` + draft `ztb_d_<x>_d` | `templates/ztb_d_app_x.tabl.asstruct` |
| Child | View `ZI_D_<APP>_<X>` + projection `ZC_D_<APP>_<X>` | `templates/zi_d_app_x.ddls.asddls`, `templates/zc_d_app_x.ddls.asddls` |
| Child | MDE `ZC_D_<APP>_<X>` | `templates/zc_d_app_x.ddlx.asddlxs` |
| Child | Handler `lhc_<alias>` trong behavior pool | trong `templates/zbp_r_m_app_upl.clas.locals_imp.abap` |
| Child | API class `zcl_<app>_<x>_upload` | `templates/zcl_app_x_upload.clas.abap` |
| Dùng chung | `zcl_call_api` (CSRF + Basic auth từ `ztb_api_auth`), `zi_req_sta_crud_poc_vh` (value help status) | đã có trên hệ thống, không sinh lại |

Service definition / service binding (OData V4 UI) vẫn phải expose `ZC_M_<APP>_UPL`, mọi `ZC_D_<APP>_<X>` và `zi_req_sta_crud_poc_vh`.

## Quy ước cố định (không đổi giữa các app)

- **Root field cố định**: `Uuid, Zcount, ZcountDone, Status, Criticality, Attachment, Mimetype, Filename, Countline, Createdbyuser, Createddate, Changedbyuser, Changeddate`.
- **`Templatetype` CHỈ khi một chương trình upload nhiều loại template** (nhiều child, radio Template Type trên dialog). App 1 template: bỏ `templatetype` khỏi table Root, Root view, projection, BDEF (readonly + mapping), MDE, và bỏ `ls_mn_root-Templatetype` + hằng `template_type` trong `lhc_Root`; `getExcelData` không rẽ nhánh. Abstract entity upload dùng chung vẫn giữ `templateType`, app 1 template chỉ bỏ qua tham số này. Ví dụ: `examples/fixed-asset` = nhiều template, `examples/so-schedline` = 1 template.
- **Child field cố định**: `Uuid, Uuidfile, Status, Type, Sequence, {{BUSINESS_FIELDS}}, {{RESULT_FIELDS}}, Messagetype, Criticality, Message, CreatedBy, CreatedAt, LastChangedBy, LocalLastChangedAt, LastChangedAt`.
- **Alias**: Root = `Root`; child đầu = `Data` / assoc `_Data`; child sau đặt theo nghĩa (`DataSub` / `_DataSub`). Child -> parent luôn là `_File`.
- **Actions**: Root có `uploadExcel` (static, parameter abstract entity) và `downloadFile` (static, result abstract entity); child có `PostConfirm` (instance, `result [1] $self`, features: instance).
- **Determinations** trên Root: `setStatusToOpen on modify { create; }` (Status = 'M', Zcount = max+1 theo user) và `getExcelData on save { field Filename; }` (parse Excel, `CREATE BY \_<Child>`).
- **Instance features**: Root khoá update/delete khi `Status = 'D'`; child khoá update/delete/PostConfirm khi `Messagetype = 'S'`.
- **Mã trạng thái** (`file_status`): `M` open, `A` accepted, `X` rejected, `D` done, `P` in process, `E` error, `S` success. Root dùng `M/P/D`, child `Messagetype` dùng `''/E/S`.
- **Criticality**: Root `'' -> 0, P -> 2, D -> 3`; child `'' -> 0, E -> 1, S -> 3`.
- **Giới hạn**: tối đa 100 dòng dữ liệu / file (message lỗi nếu vượt), PostConfirm chạy đồng bộ (không schedule job).
- **Template Excel**: 4 dòng header (nhóm cột / tên cột / R-O / độ dài), dữ liệu từ dòng 5, sheet dữ liệu ở vị trí 1, các sheet sau chỉ là danh mục tra cứu.
- **Message class**: thay `Z_FILE_MSG` / số message trong template bằng message class thật của app (001 = quá 100 dòng, 002 = upload thành công).
- **Khai báo biến trong ABAP**: khai báo tường minh `DATA lv_x TYPE <kiểu>` ở đầu method, hạn chế `DATA(...)`/`FINAL(...)` inline để tránh lỗi conversion ngầm và lỗi cú pháp. Inline CHỈ chấp nhận ở `RESULT DATA(...)`, `FAILED DATA(...)`, `REPORTED DATA(...)`, `MAPPED DATA(...)` của READ/MODIFY ENTITIES, `FIELD-SYMBOL(...)` trong READ TABLE/LOOP, và chuỗi XCO `FINAL(lo_xlsx)`. KHÔNG dùng inline trong `IMPORTING`/`RECEIVING` của method gọi bên trong biểu thức `IF`/`WHILE` (lỗi "inline declaration not possible in this position"); gọi method ra biến trước rồi mới `IF`. Ưu tiên `IF/ELSE`, `CASE` thay `COND #( )` khi gán biến có kiểu cụ thể.
- **CDS view entity**: KHÔNG dùng `@Semantics.unitOfMeasure: true` / `@Semantics.currencyCode: true` trên field unit/currency (lỗi "not allowed in view entities"); kiểu `abap.unit`/`abap.cuky` của table đã đủ. Trên field số lượng/tiền vẫn dùng `@Semantics.quantity.unitOfMeasure: 'UnitField'` / `@Semantics.amount.currencyCode: 'CurrencyField'`.
- **Comment trong source**: table DDL (`define table`) KHÔNG có comment nào, kể cả `//` cuối dòng field; chỉ dùng `@EndUserText.label`. CDS view / BDEF / MDE / abstract entity: comment `//` được nhưng chỉ ASCII (tiếng Anh, không dấu). ABAP class: comment `"` tiếng Việt được.

## Những lỗi đã gặp, đừng lặp lại

- Draft table > 16 ký tự -> activate lỗi. Dùng `ztb_d_<x>_d`, không dùng `ztb_d_<app>_<x>_d`.
- `IF get_entity( IMPORTING es_x = DATA(ls_x) ... ) = abap_false.` -> lỗi `The inline declaration "DATA(LS_X)" is not possible in this position`. Khai báo `DATA ls_x TYPE ...` rồi `lv_ok = get_entity( ... )` rồi `IF lv_ok = abap_false`.
- `@Semantics.unitOfMeasure: true` trong `define view entity` -> lỗi `Annotation Semantics.unitOfMeasure is not allowed in view entities`. Bỏ annotation, field đã là `abap.unit`.
- Comment `// ...` trên dòng field của table DDL -> lỗi `Unexpected token "/". Expected was ":"`, có dấu tiếng Việt -> thêm `Unexpected character`. Table không viết comment; giải thích cột để trong README của app.
- Không đoán tên sheet / sheet thứ 2: mỗi loại template là một FILE riêng, dữ liệu luôn ở sheet 1; loại template lấy từ radio trên dialog (`%param-TemplateType`) và lưu xuống `Root.Templatetype`.
- Không đoán tên bound action của API SAP: hỏi curl thật. Với `API_FIXEDASSET`: `SAP__self.CreateMasterFixedAsset` tạo tài sản chính, `SAP__self.CreateFixedAsset` tạo sub-number.
- Curl user gửi thường chứa `Authorization: Basic ...`, CSRF token, cookie: không chép vào code, không lặp lại trong câu trả lời, nhắc user đổi mật khẩu nếu đã lộ.
- Khi tính `Status`/`ZcountDone` của Root sau PostConfirm, DB chưa commit các dòng vừa update: phải cộng bù theo kết quả vừa merge (xem `lhc_datasub~PostConfirm` trong ví dụ).
- `MODIFY ENTITIES ... ENTITY Root UPDATE` từ action của child phải đặt `%is_draft = if_abap_behv=>mk-off` vì PostConfirm chạy trên active instance.
- Field `Sequence` giữ thứ tự dòng trong file khi API yêu cầu thứ tự (vd sub-number cấp tăng dần): `SORT ... BY <khóa cha> sequence` trước khi gọi API.

## Tài liệu kèm theo

- `reference/01-architecture.md`: luồng xử lý chi tiết, cách thêm child thứ 2.
- `reference/02-naming.md`: bảng placeholder và quy tắc đặt tên.
- `reference/03-excel-template.md`: cấu trúc template, mapping cột, helper parse.
- `reference/04-status-flow.md`: máy trạng thái Root/Child, công thức tính ZcountDone.
- `reference/05-checklist.md`: thứ tự activate, việc user làm tay, test case.
- `examples/fixed-asset/`: bộ object thật của app Mass Create Fixed Asset (2 child: Asset List, Asset Sub-number List).
- `tools/read_xlsx.py`: dump template Excel không cần openpyxl.
