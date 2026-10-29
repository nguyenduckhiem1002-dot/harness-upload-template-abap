# 03. Template Excel và cách parse

## Cấu trúc template chuẩn

```
Row 1  | nhóm cột (General / Account Assignment / Inventory / Depreciation ...)  -> bỏ
Row 2  | tên cột hiển thị                                                       -> bỏ
Row 3  | R / O  (Required / Optional)                                            -> bỏ
Row 4  | độ dài tối đa                                                           -> bỏ
Row 5+ | dữ liệu
Sheet 1 = dữ liệu. Sheet 2..n = danh mục tra cứu (Asset class, Cost Center, Department...) -> KHÔNG đọc.
```

Mỗi loại template là một **file riêng**, chọn bằng radio *Template Type* trên dialog upload. Không nhận diện bằng tên sheet.

## Định dạng ô

| Kiểu dữ liệu | Trong Excel | Helper | Kết quả ABAP |
|---|---|---|---|
| Text | `6710`, `Laptop Dell` | gán thẳng | `abap.char/string` |
| Ngày | `DD.MM.YYYY` (vd `01.10.2025`) | `to_date` | `abap.dats` `YYYYMMDD`; sai format -> initial |
| Cờ | `T` / `F`, `X` / rỗng, `true` / `false` | `to_flag` | `'X'` hoặc `''` (CP `'X*'` hoặc `'*true*'`) |
| Số nguyên | `5`, `60` | `to_int` | `i`; không parse được -> 0 |
| Sequence | cột A số thứ tự | `to_int`, rỗng -> index dòng | `abap.int4` |

Cột Required/Optional chỉ là thông tin cho người dùng; validate bắt buộc để API trả lỗi (message lưu vào `Message`), không chặn ở lúc parse.

## Đọc bằng XCO (chuẩn, không dùng class khác)

```abap
FINAL(lo_xlsx) = xco_cp_xlsx=>document->for_file_content( iv_file_content = iv_filecontent )->read_access( ).
FINAL(lo_worksheet) = lo_xlsx->get_workbook( )->worksheet->at_position( c_data_sheet_pos ).   " = 1
FINAL(lo_pattern)   = xco_cp_xlsx_selection=>pattern_builder->simple_from_to( )->get_pattern( ).
FINAL(lo_execute)   = lo_worksheet->select( lo_pattern )->row_stream( )->operation->write_to( REF #( lt_rows ) ).
lo_execute->set_value_transformation( xco_cp_xlsx_read_access=>value_transformation->string_value
  )->if_xco_xlsx_ra_operation~execute( ).
DO c_header_rows TIMES. DELETE lt_rows INDEX 1. ENDDO.          " c_header_rows = 4
DELETE lt_rows WHERE {{KEY_COLS_NOT_EMPTY}} IS INITIAL ...      " loại dòng trống cuối sheet
```

Quy tắc quan trọng: `write_to` map theo **vị trí cột**, không theo tên. Vì vậy `ty_file_upload_<x>` phải:

- có đúng số field = số cột trong sheet, theo đúng thứ tự A, B, C...
- mọi field `TYPE string` (chuyển kiểu sau bằng helper),
- ghi chú chữ cái cột ở cuối mỗi dòng (`"A`, `"B`...) để đối chiếu nhanh với dump.

## Quy trình đối chiếu template mới

1. Dump file:
   ```bash
   python -I -X utf8 tools/read_xlsx.py "<đường dẫn file .xlsx>" > template_dump.txt
   ```
   Output: từng sheet, từng dòng, mỗi ô dạng `A1=...`. Dùng `-X utf8` vì nhãn tiếng Việt gây lỗi cp1252.
2. Lấy dòng 2 (tên cột) của sheet 1 -> lập bảng `cột | tên cột | field CDS | kiểu | helper`.
3. Sửa `ty_file_upload_<x>` theo bảng; sửa `DELETE ... WHERE` theo cột khóa.
4. Sửa block `CREATE BY \_<Assoc> FIELDS (...)` trong `getExcelData` cho khớp field.
5. Nếu cột đổi tên nhưng không đổi vị trí: không cần sửa code parse, chỉ sửa label MDE.

## Mapping ví dụ (Asset Sub-number List, sheet "Create Sub- Asset")

| Cột | Tên cột | Field | Helper |
|---|---|---|---|
| A | Sequence | `Sequence` | `to_int` (rỗng -> index) |
| B | Company Code | `CompanyCode` | |
| C | Asset Number | `MasterFixedAsset` | |
| D | Post-capitalization | `PostCapitalization` | `to_flag` |
| E | Asset Description | `FixedAssetDescription` | |
| F | Additional Description | `AdditionalDescription` | |
| G | Base Unit | `BaseUnitIsoCode` | |
| H | Serial Number | `SerialNumber` | |
| I | Ordered On | `OrderDate` | `to_date` |
| J..L | Evaluation Group 1..3 | `EvalGroup1..3` | |
| M | Inventory Number | `InventoryNumber` | |
| N | Last Inventory On | `LastInventoryDate` | `to_date` |
| O | Inventory Note | `InventoryNote` | |
| P | Inventory Relevant | `InventoryIsCounted` | `to_flag` |
| Q..V | Cost Center, Profit Center, Plant, Room, Segment, Location | `CostCenter`..`AssetLocation` | |
| W | Supplier | `Supplier` | |
| X | Acquired Used | `AssetIsAcquiredUsed` | `to_flag` |
| Y | Manufacturer | `ManufacturerName` | |
| Z | Capitalized On | `CapitalizationDate` | `to_date` |
| AA | Deactivated On | `DeactivationDate` | `to_date` |
| AB | Useful Life Years | `UsefulLifeYears` | |
| AC | Useful Life Periods | `UsefulLifePeriods` | |
| AD | Depreciation Start | `DepreciationStartDate` | `to_date` |

Template Asset List (chính) giống bảng trên nhưng KHÔNG có cột Sequence và cột B là `AssetClass` thay cho `MasterFixedAsset` (29 cột A..AC).
