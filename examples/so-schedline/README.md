# Upload Sales Order Schedule Line

Sinh theo harness `.claude/skills/rap-excel-upload` (1 Root + 1 child, 1 template).

| Placeholder | Giá trị |
|---|---|
| APP / label | `SOSL` / Sales Order Schedule Line |
| Root | `ztb_m_sosl_upl` (draft `ztb_m_sosl_d`), `ZR_M_SOSL_UPL`, `ZC_M_SOSL_UPL`, `zbp_r_m_sosl_upl` |
| Child | `ztb_d_sosl_upl` (draft `ztb_d_sosl_d`), `ZI_D_SOSL_UPL`, `ZC_D_SOSL_UPL`, alias `Data` / `_Data` |
| Abstract entity | dùng lại `zabs_file_crud_poc_n` (upload), `zabs_file_crud_poc` (download) |
| API class | `zcl_so_schedline_upload=>process_schedule_lines` |
| Dùng chung | `zcl_call_api`, `zi_req_sta_crud_poc_vh`, `zde_attachment`, `zde_mime_type`, `zde_filename` |

## Template Excel (sheet 1)

| Cột | Tên | Field | Bắt buộc | Xử lý |
|---|---|---|---|---|
| A | Sales order | `SalesOrder` | có | `to_vbeln`: toàn số thì thêm 0 đầu đủ 10 ký tự |
| B | Sales order item | `SalesOrderItem` | có | `to_int` -> NUMC6 |
| C | Schedule line | `ScheduleLine` | không | trống -> `Type = 'I'` (insert dòng mới); có số -> `Type = 'U'` (update số lượng dòng đó) |
| D | Delivery Date | `DeliveryDate` | có | `to_date` DD.MM.YYYY |
| E | Order quantity | `OrderQuantity` | có | `to_dec`: nhận `10`, `10.5`, `10,5`, `1.000,5` |

Header: hiện đặt `c_header_rows = 2` theo ảnh mẫu (dòng 1 tên cột, dòng 2 ghi chú). Nếu file thật theo chuẩn 4 dòng của harness thì đổi hằng này.

## Luồng PostConfirm (OData V2 `API_SALES_ORDER_SRV`, đã xác nhận bằng request thật)

- Sắp xếp theo `sales_order, sales_order_item, sequence` để các dòng insert cùng item được cấp số schedule line tăng dần.
- Key V2 không có 0 đầu: `A_SalesOrderScheduleLine(SalesOrder='10001855',SalesOrderItem='30',ScheduleLine='1')`; class bỏ 0 đầu bằng `ext( )` (ALPHA = OUT), DB vẫn lưu format nội bộ.
- `Type = 'U'` (update số lượng), 2 request:
  1. `GET A_SalesOrderScheduleLine(...)` lấy `OrderQuantityUnit`, `OrderQuantitySAPUnit`, `OrderQuantityISOUnit`, `RequestedDeliveryDate` hiện tại; lỗi thì dừng dòng đó.
  2. `PATCH` cùng path, body đúng mẫu: `ScheduleLineOrderQuantity`, 3 field unit lấy từ GET, `RequestedDeliveryDate` dạng `/Date(ms)/` (cột D nếu có, không thì giữ ngày cũ). Kỳ vọng 204.
- `Type = 'I'` (insert, đã xác nhận bằng request thật): `GET A_SalesOrderItem(...)` lấy unit của item, rồi `POST A_SalesOrderItem(...)/to_ScheduleLine` với body giống PATCH (quantity, 3 unit, `RequestedDeliveryDate`), không có `SalesOrder`/`SalesOrderItem` trong body. Kỳ vọng 201, `d.ScheduleLine` ghi vào `ScheduleLineResult`.
- `x-csrf-token`: `zcl_call_api` tự GET preflight với `x-csrf-token: fetch` trước mọi PATCH/POST và gắn token vào request thật. Class truyền `iv_endpoint = path entity` để preflight GET chạy trên đúng entity vừa đọc. GET không cần token.
- Lỗi V2 đọc từ `error.message.value`; `code = 0` của wrapper (lỗi transport) đọc từ `zcl_call_api=>reason`.

## Còn phải xác nhận trước khi activate

1. Data element `vbeln_va`, `posnr_va`, `etenr` có dùng được trong môi trường không; nếu không, thay bằng `abap.char(10)`, `abap.numc(6)`, `abap.numc(4)`.
2. Message class thay cho `Z_FILE_MSG` (001 quá 100 dòng, 002 upload thành công).
3. Số dòng header của template Excel thật (hiện 2).

## Thứ tự activate

Theo `reference/05-checklist.md` của harness: data element dùng chung -> 2 table -> `ZI_D_SOSL_UPL` + `ZR_M_SOSL_UPL` -> BDEF base (quick fix tạo draft table + behavior pool) -> dán Local Types -> `zcl_so_schedline_upload` -> projection views + MDE -> BDEF projection -> service definition expose `ZC_M_SOSL_UPL`, `ZC_D_SOSL_UPL`, `zi_req_sta_crud_poc_vh` -> service binding OData V4 UI.
