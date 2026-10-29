# 01. Kiến trúc và luồng xử lý

## Luồng end-to-end

```
(1) User bấm "Upload Excel" trên List Report
    -> dialog từ abstract entity zabs_file_upload: file (mimeType/fileName/fileContent) + radio templateType
(2) static action Root~uploadExcel (lhc_Root)
    -> đọc %param, parse sheet 1 theo templateType để ĐẾM dòng (<= 100)
    -> MODIFY ENTITIES Root CREATE AUTO FILL CID (Attachment, Mimetype, Filename, Templatetype, Countline)
(3) determination setStatusToOpen on modify {create}
    -> Status = 'M', Zcount = MAX(zcount)+1 của user (xét cả bảng active + draft)
(4) determination getExcelData on save {field Filename}
    -> READ Root (Attachment, Templatetype)
    -> IF Templatetype = 'S' read_sub_sheet ELSE read_main_sheet
    -> CREATE BY \_Data hoặc \_DataSub, mỗi dòng Excel = 1 child, Status = 'M', Type = 'I'
(5) User mở Object Page, chọn dòng child, bấm "Post Confirm"
    -> action Child~PostConfirm (lhc_<child>)
    -> SELECT child table WITH PRIVILEGED ACCESS các uuid được chọn, messagetype <> 'S'
    -> map sang API input (row_id = index), gọi zcl_<app>_<x>_upload=>create_*
    -> merge kết quả theo row_id -> MODIFY child UPDATE (Messagetype, Message, <result fields>)
    -> tính lại Root.Status / ZcountDone trên toàn bộ child của file -> MODIFY Root UPDATE (%is_draft = off)
    -> result = $self
(6) API class: 1 dòng = 1 POST .../<EntitySet>/SAP__self.<BoundAction> qua zcl_call_api=>call_api
    -> 201: success, parse body lấy key sinh ra (vd FixedAsset); khác 201: lấy error.message
```

## Vai trò từng lớp

| Lớp | Nhiệm vụ | KHÔNG làm |
|---|---|---|
| `lhc_Root` | nhận file, đếm dòng, parse Excel -> child, đánh số Zcount, khoá Root khi Done | gọi API |
| `lhc_<child>` | khoá dòng đã success, PostConfirm: map -> API -> merge -> cập nhật Root | parse Excel |
| `zcl_<app>_<x>_upload` | build JSON, gọi `zcl_call_api`, parse response, trả `tt_result` theo `row_id` | đọc/ghi DB RAP |
| `zcl_call_api` | CSRF fetch + POST với Basic auth từ `ztb_api_auth`, expose `code` (HTTP status) | nghiệp vụ |

## Hợp đồng với `zcl_call_api` (dùng chung, không sửa trong từng app)

```abap
DATA(lv_body) = zcl_call_api=>call_api(
                   iv_body        = lv_json
                   iv_contentType = 'application/json;odata.metadata=minimal;charset=utf-8'
                   iv_endpoint    = gc_endpoint                              " path entity set, dùng để build URL gốc
                   iv_uri         = |{ gc_endpoint }/SAP__self.{ gc_action }|  " path thực sự được gọi
                   iv_method      = 'POST' ).
DATA(lv_status) = zcl_call_api=>code.   " 201 = created; 0 = lỗi transport/local, reason ở zcl_call_api=>reason
```

- Host = `cl_abap_context_info=>get_system_url( )` đổi thành `<tenant>-api.<domain>`; không hardcode host trong API class.
- Non-GET: class tự GET preflight lấy `x-csrf-token`; nếu preflight lỗi thì `code`/body là của preflight (vd 404 khi path sai).
- PATCH/PUT/DELETE: tự lấy `ETag` (header hoặc `@odata.etag` trong body) gắn `If-Match`.
- `code = 0` không phải HTTP status: API class phải coi là lỗi và ghi `reason` vào `Message`.
- Chỉ một dòng cấu hình trong `ztb_api_auth`; nếu có nhiều API user, mở rộng bằng key `api_name` và truyền `iv_apiName`.

## Vì sao tách mỗi template thành một child riêng

- Cột khác nhau -> bảng khác nhau, tránh bảng "to" với nhiều cột rỗng.
- API đích khác nhau (bound action khác, payload khác) -> API class riêng, handler riêng.
- UI: mỗi child là một facet/table riêng trên Object Page, lọc tự nhiên theo file.
- Root vẫn là một: một danh sách file upload duy nhất, lọc được theo `Templatetype`.

## Thêm child thứ 2 (hoặc thứ N) vào app đã có

Làm đúng các bước này, mỗi bước có chỗ sửa cụ thể trong `examples/fixed-asset/`:

1. Table `ztb_d_<app>_<x2>` (+ draft `ztb_d_<x2>_d`), view `ZI_D_<APP>_<X2>`, projection `ZC_D_<APP>_<X2>`, MDE.
2. Root view `ZR_M_<APP>_UPL`: thêm `composition [0..*] of ZI_D_<APP>_<X2> as _<Alias2>` và expose `_<Alias2>`.
   Child thứ 2 trở đi dùng `[0..*]` (child đầu tiên giữ `[1..*]` nếu app cũ đã vậy).
3. Projection `ZC_M_<APP>_UPL`: `_<Alias2> : redirected to composition child ZC_D_<APP>_<X2>`.
4. BDEF base: `association _<Alias2> { create; with draft; }` trong Root + block `define behavior for ZI_D_<APP>_<X2> alias <Alias2>` (copy block child đầu, đổi table/draft/mapping).
5. BDEF projection: `use association _<Alias2> { create; with draft; }` + block `define behavior for ZC_D_<APP>_<X2> alias <Alias2>`.
6. MDE Root: thêm facet `#LINEITEM_REFERENCE` với `targetElement: '_<Alias2>'`.
7. Abstract entity upload: giữ `templateType : abap.char(1)`; thêm giá trị mới vào comment (vd `'S'`).
8. Behavior pool:
   - thêm hằng vào `template_type` (vd `sub 'S'`),
   - thêm `ty_file_upload_<x2>` + `read_<x2>_sheet` theo cột template mới,
   - `uploadExcel`: đếm dòng theo `lv_template_type`,
   - `getExcelData`: rẽ nhánh theo `<f_root>-Templatetype`, thêm block `CREATE BY \_<Alias2>`,
   - thêm class `lhc_<alias2>` (copy `lhc_datasub` trong ví dụ).
9. API class `zcl_<app>_<x2>_upload` từ template.
10. Service definition: expose `ZC_D_<APP>_<X2>`; không cần binding mới, publish lại.
11. Khi tính Root.Status/ZcountDone trong MỌI `lhc_<child>~PostConfirm`: cộng cả child mới (xem `04-status-flow.md`).

## Những điểm cố ý giữ đơn giản

- Không schedule background job cho PostConfirm: chạy đồng bộ trong action, 100 dòng/file là đủ nhỏ.
- JSON build tay (`field`/`as_object`) thay vì serialize struct: kiểm soát được tên field OData và bỏ field rỗng.
- Ledger/depreciation config hiện hardcode trong handler; khi nhiều Company Code thì chuyển thành bảng config `ztb_<app>_ledger_cfg` và đọc trong PostConfirm.
- `downloadFile` để trống (TODO): khi cần, build lại file kết quả từ child table và trả qua abstract entity.
