# 04. Máy trạng thái

## Hằng số dùng chung (khai báo trong mọi `lhc_*`)

```abap
CONSTANTS:
  BEGIN OF file_status,
    open      TYPE c LENGTH 1 VALUE 'M', "Not processed
    accepted  TYPE c LENGTH 1 VALUE 'A', "Accepted
    rejected  TYPE c LENGTH 1 VALUE 'X', "Rejected
    completed TYPE c LENGTH 1 VALUE 'D', "Done
    inprocess TYPE c LENGTH 1 VALUE 'P', "In process
    error     TYPE c LENGTH 1 VALUE 'E', "Error
    success   TYPE c LENGTH 1 VALUE 'S', "Success
  END OF file_status.
```

Value help / text của status lấy từ view dùng chung `{{STATUS_VH}}` (`zi_req_sta_crud_poc_vh`), join trên cột `Status`.

## Root.Status

```
          uploadExcel + setStatusToOpen
 (none) ─────────────────────────────────> M (open)
                                            │ PostConfirm bất kỳ child, còn dòng chưa S
                                            v
                                           P (in process)  <──┐ PostConfirm, vẫn còn dòng chưa S
                                            │                 │
                                            │ PostConfirm, mọi dòng ở MỌI child đều S
                                            v
                                           D (done)  -> khoá update/delete Root (get_instance_features)
```

Criticality Root: `'' -> 0 (neutral)`, `P -> 2 (critical/vàng)`, `D -> 3 (positive/xanh)`. `M` cố ý không tô màu.

## Child.Status và Child.Messagetype

- `Status` của child = `'M'` khi tạo từ Excel, giữ nguyên (dự phòng cho workflow duyệt A/X sau này).
- `Type` = `'I'` (Insert) cho template Mass Create; template Mass Change dùng `'U'`.
- `Messagetype`: `''` chưa gọi API, `'S'` API trả 201, `'E'` API lỗi (message lưu `Message`).
- Criticality child: `'' -> 0, E -> 1 (đỏ), S -> 3 (xanh)`.
- Dòng `Messagetype = 'S'` bị khoá update/delete/PostConfirm; dòng `'E'` được sửa và PostConfirm lại.

## Công thức cập nhật Root sau PostConfirm (bắt buộc trong mọi `lhc_<child>~PostConfirm`)

Tính trên **toàn bộ child table của file** (uuidfile), không chỉ các dòng vừa xử lý:

```abap
" done_X / open_X: COUNT(*) WITH PRIVILEGED ACCESS theo uuidfile, messagetype = 'S' / <> 'S', cho MỖI child table
" các dòng vừa xử lý trong handler này chưa commit DB -> bù lại:
LOOP AT lt_processed INTO ls WHERE messagetype = 'S'.
  lv_done_<this> += 1.  lv_open_<this> -= 1.
ENDLOOP.

Status     = COND #( WHEN lv_open_child1 = 0 AND lv_open_child2 = 0 ... THEN file_status-completed
                     ELSE file_status-inprocess ).
ZcountDone = lv_done_child1 + lv_done_child2 + ...
```

`MODIFY ENTITIES ... ENTITY Root UPDATE FIELDS ( Status ZcountDone )` với `%is_draft = if_abap_behv=>mk-off`.

Khi thêm child mới: sửa khối tính này trong TẤT CẢ handler child đã có, không chỉ handler mới.

## Zcount (STT file theo user)

`setStatusToOpen`: `MAX(zcount)` của `createdbyuser = sy-uname` trên cả bảng active và draft, lấy max + 1. Chỉ set khi `Status` còn trống (tránh chạy lại khi update).
