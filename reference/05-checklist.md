# 05. Checklist bàn giao

## Thứ tự tạo và activate trên ADT

1. Data element dùng chung (nếu chưa có): `zde_attachment` (rawstring), `zde_mime_type`, `zde_filename`.
2. Table Root `ztb_m_<app>_upl`, các table child `ztb_d_<app>_<x>`.
3. Interface view child `ZI_D_<APP>_<X>` (association to parent chưa resolve được, activate cùng lúc với Root view).
4. Root view `ZR_M_<APP>_UPL` (activate chung với các `ZI_D_*`).
5. Abstract entity upload (`zabs_file_upload` / `zabs_file_crud_poc_n`) và abstract entity download.
6. BDEF base `ZR_M_<APP>_UPL`: sau khi activate, dùng **quick fix** trên dòng `draft table` để tạo `ztb_m_<app>_d`, `ztb_d_<x>_d`; dùng quick fix trên `implementation in class` để sinh `zbp_r_m_<app>_upl` + skeleton Local Types.
7. Dán Local Types từ template vào `zbp_r_m_<app>_upl` (Local Types tab). Activate.
8. API class `zcl_<app>_<x>_upload` (cần `zcl_call_api`, `/ui2/cl_json`).
9. Projection view `ZC_M_<APP>_UPL`, `ZC_D_<APP>_<X>`; MDE tương ứng.
10. BDEF projection `ZC_M_<APP>_UPL`.
11. Service definition expose `ZC_M_<APP>_UPL`, `ZC_D_<APP>_<X>`, `{{STATUS_VH}}`; service binding OData V4 UI, publish.
12. Message class: tạo 2 message (001 quá 100 dòng, 002 upload thành công) và thay `Z_FILE_MSG` trong handler.
13. Fiori launchpad: app list report; dialog uploadExcel tự sinh từ abstract entity, radio Template Type cần MDE/annotation `@UI.selectionField`/value help nếu muốn hiển thị dạng radio thay vì input text.

## Việc user phải quyết định (không tự suy)

- Giá trị radio Template Type khớp hằng `template_type` (`'M'` / `'S'`), hoặc đổi hằng cho khớp UI.
- Ledger / depreciation area / depreciation key theo Company Code (hiện hardcode trong PostConfirm).
- Bound action và payload tối thiểu của API đích (xác nhận bằng curl chạy thật).
- Có gửi `_Ledger` cho sub-number hay để kế thừa từ tài sản chính.
- Giới hạn 100 dòng/file có đủ không.

## Test tối thiểu trước khi bàn giao

| # | Case | Kỳ vọng |
|---|---|---|
| 1 | Upload file template chính, 3 dòng hợp lệ | Root Status M, Countline 3, 3 dòng `_Data`, Messagetype rỗng |
| 2 | Upload file template phụ (radio = S) | dữ liệu vào `_DataSub`, `_Data` trống, Templatetype = S |
| 3 | Upload file > 100 dòng | message lỗi 001, không tạo Root |
| 4 | Upload file có dòng trống cuối sheet | dòng trống không được tạo |
| 5 | Ô ngày sai format (`2025-10-01`) | field ngày initial, không dump |
| 6 | PostConfirm 1 dòng hợp lệ | Messagetype S, field kết quả có giá trị, Root Status P, ZcountDone +1 |
| 7 | PostConfirm dòng thiếu field bắt buộc | Messagetype E, Message = error.message của OData, Root vẫn P |
| 8 | Sửa dòng E rồi PostConfirm lại | thành S |
| 9 | PostConfirm dòng cuối cùng còn lại | Root Status D, Root khoá update/delete |
| 10 | Chọn dòng S bấm PostConfirm | nút disabled (instance feature) |
| 11 | App có 2 child: 1 child xong hết, child kia còn dòng | Root vẫn P |

## Khi review code upload theo chuẩn

Kiểm tra nhanh các điểm sau, báo lệch chuẩn thay vì sửa ngầm:

- [ ] Draft table <= 16 ký tự, có `with draft`, `strict ( 2 )`, `lock dependent by _File`, `authorization dependent by _File`.
- [ ] Root `field ( readonly ) Mimetype, Filename, Status, Zcount, Countline, ZcountDone, Templatetype`.
- [ ] Child `field ( readonly ) Uuidfile, Message, Messagetype`; `PostConfirm ... result [1] $self` với `features : instance`.
- [ ] `getExcelData` rẽ nhánh theo `Templatetype`; `uploadExcel` lưu `Templatetype`; rỗng -> `'M'`.
- [ ] `ty_file_upload_*` khớp thứ tự cột template; `c_header_rows = 4`; `c_data_sheet_pos = 1`.
- [ ] PostConfirm `SELECT ... WITH PRIVILEGED ACCESS ... messagetype NE 'S'`, merge theo `row_id`, cập nhật Root với `%is_draft = mk-off`, tính trên mọi child table.
- [ ] API class không chứa credential; endpoint/action là constant; 201 = success; lỗi lấy `error.message`.
- [ ] Không có TODO về tên action/ledger còn sót khi bàn giao production.
