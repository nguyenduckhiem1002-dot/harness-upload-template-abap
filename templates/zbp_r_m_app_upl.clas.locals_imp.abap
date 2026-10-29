"=====================================================================
" Local Types của behavior pool {{BP_CLASS}}  (RAP Excel Upload Harness)
"
" Cấu trúc cố định:
"   lhc_{{child_alias}}  : handler child  (features + PostConfirm -> API)
"   [lhc_<alias2> ...]   : mỗi child/template thêm = 1 handler copy từ lhc_{{child_alias}}
"   lhc_Root             : uploadExcel / setStatusToOpen / getExcelData / features / helper parse
"
" Quy tắc code (SKILL.md): khai báo tường minh DATA lv_x TYPE ...; inline DATA(...) chỉ ở
" RESULT/FAILED/REPORTED/MAPPED của READ/MODIFY ENTITIES, FIELD-SYMBOL(...) và chuỗi XCO.
"
" Placeholder: {{ROOT_I}} {{CHILD_ALIAS}} {{child_alias}} {{CHILD_ASSOC}} {{CHILD_TBL}} {{ROOT_TBL}}
"              {{ROOT_DRAFT}} {{API_CLASS}} {{API_METHOD}} {{MSG_CLASS}} {{BUSINESS_FIELDS}} {{RESULT_FIELDS}}
" Các dòng đánh dấu [MULTI] chỉ giữ khi app có nhiều template (Root.Templatetype); app 1 template xoá đi.
"=====================================================================

"=====================================================================
" Handler cho child {{CHILD_ALIAS}}
"=====================================================================
CLASS lhc_{{child_alias}} DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
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

    TYPES tt_db_data TYPE STANDARD TABLE OF {{CHILD_TBL}} WITH EMPTY KEY.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR {{CHILD_ALIAS}} RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR {{CHILD_ALIAS}} RESULT result.

    METHODS PostConfirm FOR MODIFY
      IMPORTING keys FOR ACTION {{CHILD_ALIAS}}~PostConfirm RESULT result.

ENDCLASS.

CLASS lhc_{{child_alias}} IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY {{CHILD_ALIAS}}
        FIELDS ( Messagetype )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data)
      FAILED failed.

    " Dòng đã tạo thành công (S) thì khoá update/delete/PostConfirm
    result = VALUE #( FOR ls_data IN lt_data
      ( %tky                = ls_data-%tky
        %update             = COND #( WHEN ls_data-Messagetype = file_status-success
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
        %delete             = COND #( WHEN ls_data-Messagetype = file_status-success
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
        %action-PostConfirm = COND #( WHEN ls_data-Messagetype = file_status-success
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
      ) ).
  ENDMETHOD.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD PostConfirm.
    DATA lt_data       TYPE tt_db_data.
    DATA ls_data       TYPE {{CHILD_TBL}}.
    DATA lt_api_input  TYPE {{API_CLASS}}=>tt_input.
    DATA ls_api_input  TYPE {{API_CLASS}}=>ty_input.
    DATA lt_api_result TYPE {{API_CLASS}}=>tt_result.
    DATA ls_api_result TYPE {{API_CLASS}}=>ty_result.
    DATA lv_idx        TYPE i.
    DATA lv_uuidfile   TYPE sysuuid_x16.
    DATA lv_done       TYPE i.
    DATA lv_open       TYPE i.
    DATA lv_new_status TYPE {{ROOT_TBL}}-status.

    " ── 1. SELECT các dòng được chọn, chưa success ─────────────────────
    SELECT * FROM {{CHILD_TBL}}
      WITH PRIVILEGED ACCESS
      FOR ALL ENTRIES IN @keys
      WHERE uuid = @keys-uuid
        AND messagetype NE @file_status-success
      INTO TABLE @lt_data.

    IF lt_data IS INITIAL.
      RETURN.
    ENDIF.

    " Nếu API yêu cầu thứ tự (vd sub-number cấp tăng dần): SORT lt_data BY <khoá cha> sequence.
    SORT lt_data BY sequence.

    " ── 2. Map sang input của API class (row_id = index để merge ngược) ──
    LOOP AT lt_data INTO ls_data.
      lv_idx += 1.
      CLEAR ls_api_input.
      ls_api_input-row_id = lv_idx.
      " ---------- {{BUSINESS_FIELDS}}: snake_case table -> field API input ----------
      " ls_api_input-company_code        = ls_data-company_code.
      " ls_api_input-post_capitalization = xsdbool( ls_data-post_capitalization = 'X' ).
      " ls_api_input-order_date          = ls_data-order_date.
      APPEND ls_api_input TO lt_api_input.
    ENDLOOP.

    " ── 3. Gọi API đồng bộ (không schedule job) ───────────────────────
    lt_api_result = {{API_CLASS}}=>{{API_METHOD}}( it_data = lt_api_input ).

    " ── 4. Merge kết quả theo row_id ─────────────────────────────────
    LOOP AT lt_api_result INTO ls_api_result.
      READ TABLE lt_data ASSIGNING FIELD-SYMBOL(<fs_merge>) INDEX ls_api_result-row_id.
      IF sy-subrc = 0.
        IF ls_api_result-success = abap_true.
          <fs_merge>-messagetype = file_status-success.
        ELSE.
          <fs_merge>-messagetype = file_status-error.
        ENDIF.
        <fs_merge>-message = ls_api_result-message.
        " ---------- {{RESULT_FIELDS}} ----------
        " <fs_merge>-fixed_asset = ls_api_result-fixed_asset.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY {{CHILD_ALIAS}}
      UPDATE FIELDS ( Messagetype Message " {{RESULT_FIELDS}} vd: FixedAsset
                    )
      WITH VALUE #( FOR ls_upd IN lt_data (
        %tky-Uuid     = ls_upd-uuid
        %tky-Uuidfile = ls_upd-uuidfile
        Messagetype   = ls_upd-messagetype
        Message       = ls_upd-message
        " FixedAsset    = ls_upd-fixed_asset
      ) )
      FAILED   DATA(lt_failed)
      REPORTED DATA(lt_reported).

    " ── 5. Tính lại Status + ZcountDone của Root trên TOÀN BỘ child của file ──
    " (xem reference/04-status-flow.md; khi app có thêm child, cộng thêm COUNT của child đó ở đây)
    lv_uuidfile = lt_data[ 1 ]-uuidfile.

    SELECT COUNT( * ) FROM {{CHILD_TBL}} WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype = @file_status-success
      INTO @lv_done.
    SELECT COUNT( * ) FROM {{CHILD_TBL}} WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype <> @file_status-success
      INTO @lv_open.

    " các dòng vừa xử lý chưa commit DB -> bù theo kết quả vừa merge
    LOOP AT lt_data INTO ls_data WHERE messagetype = file_status-success.
      lv_done += 1.
      lv_open -= 1.
    ENDLOOP.

    " >>> CHILD 2: SELECT COUNT tương tự trên ztb_d_<app>_<x2> -> lv_done_2 / lv_open_2, cộng vào dưới <<<

    IF lv_open = 0. " AND lv_open_2 = 0
      lv_new_status = file_status-completed.
    ELSE.
      lv_new_status = file_status-inprocess.
    ENDIF.

    MODIFY ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY Root
      UPDATE FIELDS ( Status ZcountDone )
      WITH VALUE #( (
        %tky-Uuid  = lv_uuidfile
        %is_draft  = if_abap_behv=>mk-off
        Status     = lv_new_status
        ZcountDone = lv_done " + lv_done_2
      ) )
      FAILED   DATA(lt_hdr_failed)
      REPORTED DATA(lt_hdr_reported).

    " ── 6. Trả $self ──────────────────────────────────────────────────
    result = VALUE #( FOR ls_key IN keys
      ( %tky        = ls_key-%tky
        %param-%tky = ls_key-%tky ) ).
  ENDMETHOD.

ENDCLASS.


" >>> CHILD 2: copy toàn bộ CLASS lhc_{{child_alias}} thành lhc_<alias2>, đổi ENTITY/table/API class. <<<


"=====================================================================
" Handler Root
"=====================================================================
CLASS lhc_Root DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
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

    " Số dòng header của template (nhóm cột / tên cột / R-O / độ dài) trước dữ liệu.
    CONSTANTS c_header_rows TYPE i VALUE 4.
    " Dữ liệu luôn ở sheet 1; các sheet sau là danh mục tra cứu.
    CONSTANTS c_data_sheet_pos TYPE i VALUE 1.
    " Giới hạn dòng dữ liệu / file.
    CONSTANTS c_max_rows TYPE i VALUE 100.

    " [MULTI] Mỗi loại template = 1 file riêng, chọn bằng radio Template Type trên dialog upload
    " [MULTI] -> %param-TemplateType -> Root.Templatetype -> getExcelData rẽ nhánh.
    CONSTANTS:
      BEGIN OF template_type,
        main TYPE c LENGTH 1 VALUE '{{TEMPLATE_CODE}}', "{{CHILD_LABEL}}
        " sub  TYPE c LENGTH 1 VALUE 'S', "<Label 2>
      END OF template_type.

    " Thứ tự field PHẢI khớp thứ tự cột A, B, C... của sheet 1 (XCO map theo vị trí cột).
    TYPES: BEGIN OF ty_file_upload,
             " ---------- {{BUSINESS_FIELDS}} (tất cả TYPE string, ghi chú chữ cái cột) ----------
             " Sequence              TYPE string, "A  (nếu template có cột STT)
             " CompanyCode           TYPE string, "B
             " AssetClass            TYPE string, "C
             Dummy TYPE string, "XOÁ dòng này khi điền field thật
           END OF ty_file_upload.
    TYPES tt_file_upload TYPE STANDARD TABLE OF ty_file_upload WITH EMPTY KEY.

    " >>> CHILD 2: TYPES ty_file_upload_<x2> / tt_file_upload_<x2> theo cột template 2 <<<

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Root RESULT result.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Root RESULT result.

    METHODS downloadFile FOR MODIFY
      IMPORTING keys FOR ACTION Root~downloadFile RESULT result.

    METHODS uploadExcel FOR MODIFY
      IMPORTING keys FOR ACTION Root~uploadExcel.

    METHODS setStatusToOpen FOR DETERMINE ON MODIFY
      IMPORTING keys FOR Root~setStatusToOpen.

    METHODS getExcelData FOR DETERMINE ON SAVE
      IMPORTING keys FOR Root~getExcelData.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Root RESULT result.

    " ---- helper parse ----
    METHODS read_main_sheet
      IMPORTING iv_filecontent TYPE xstring
      RETURNING VALUE(rt_rows) TYPE tt_file_upload.
    " >>> CHILD 2: METHODS read_<x2>_sheet ... RETURNING tt_file_upload_<x2> <<<

    METHODS to_date
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE d.

    METHODS to_flag
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE abap_boolean.

    METHODS to_int
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE i.

ENDCLASS.

CLASS lhc_Root IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD downloadFile.
    " TODO: build file kết quả từ child table và trả về qua abstract entity download
  ENDMETHOD.

  METHOD uploadExcel.
    DATA lt_mn_root        TYPE TABLE FOR CREATE {{ROOT_I}}.
    DATA ls_mn_root        LIKE LINE OF lt_mn_root.
    DATA lv_filecontent    TYPE xstring.
    DATA lv_template_type  TYPE {{ROOT_TBL}}-templatetype.   " [MULTI]
    DATA lt_rows           TYPE tt_file_upload.
    DATA lv_total_lines    TYPE i.
    FIELD-SYMBOLS <k>      LIKE LINE OF keys.

    READ TABLE keys ASSIGNING <k> INDEX 1.
    CHECK sy-subrc = 0.

    IF <k>-%param-FileContent IS INITIAL.
      RETURN.
    ENDIF.

    lv_filecontent = <k>-%param-FileContent.

    " [MULTI] loại template từ radio trên dialog; rỗng -> template chính (tương thích record cũ)
    IF <k>-%param-TemplateType IS INITIAL.
      lv_template_type = template_type-main.
    ELSE.
      lv_template_type = <k>-%param-TemplateType.
    ENDIF.

    ls_mn_root-Attachment   = lv_filecontent.
    ls_mn_root-Filename     = <k>-%param-FileName.
    ls_mn_root-Mimetype     = <k>-%param-MimeType.
    ls_mn_root-Templatetype = lv_template_type.   " [MULTI]

    " đếm dòng dữ liệu theo đúng loại template
    CASE lv_template_type.
      " WHEN template_type-sub.                        " [MULTI]
      "   lv_total_lines = lines( read_<x2>_sheet( lv_filecontent ) ).
      WHEN OTHERS.
        lt_rows        = read_main_sheet( lv_filecontent ).
        lv_total_lines = lines( lt_rows ).
    ENDCASE.

    IF lv_total_lines > c_max_rows.
      APPEND VALUE #( %cid = <k>-%cid
                       %msg = new_message( id       = '{{MSG_CLASS}}'
                                            number   = '001'   " File vượt quá &1 dòng
                                            severity = if_abap_behv_message=>severity-error ) )
        TO reported-root.
      RETURN.
    ENDIF.

    ls_mn_root-Countline = lv_total_lines.
    APPEND ls_mn_root TO lt_mn_root.

    MODIFY ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY Root
      CREATE AUTO FILL CID FIELDS (
                        Status
                        Attachment
                        Mimetype
                        Filename
                        Templatetype    " [MULTI]
                        Countline
                        Createdbyuser
                        Createddate
                        Changedbyuser
                        Changeddate
                      ) WITH lt_mn_root
      MAPPED   DATA(lt_mapped_create)
      REPORTED DATA(lt_reported_create)
      FAILED   DATA(lt_failed_create).

    APPEND VALUE #( %cid = <k>-%cid
                     %msg = new_message( id       = '{{MSG_CLASS}}'
                                          number   = '002'   " Upload thành công
                                          severity = if_abap_behv_message=>severity-success ) )
      TO reported-root.
  ENDMETHOD.

  METHOD setStatusToOpen.
    DATA lv_cnt1 TYPE i.
    DATA lv_cnt2 TYPE i.
    DATA lv_next TYPE i.

    READ ENTITIES OF {{ROOT_I}} IN LOCAL MODE
     ENTITY Root
       FIELDS ( Status )
       WITH CORRESPONDING #( keys )
     RESULT DATA(lt_root).

    DELETE lt_root WHERE Status IS NOT INITIAL.
    CHECK lt_root IS NOT INITIAL.

    SELECT SINGLE MAX( zcount ) FROM {{ROOT_TBL}}
      WHERE createdbyuser = @sy-uname INTO @lv_cnt1.
    SELECT SINGLE MAX( zcount ) FROM {{ROOT_DRAFT}}
      WHERE createdbyuser = @sy-uname INTO @lv_cnt2.

    IF lv_cnt1 >= lv_cnt2.
      lv_next = lv_cnt1 + 1.
    ELSE.
      lv_next = lv_cnt2 + 1.
    ENDIF.

    MODIFY ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY Root
        UPDATE FIELDS ( Status Zcount )
        WITH VALUE #( FOR ls_root IN lt_root ( %tky   = ls_root-%tky
                                                Status = file_status-open
                                                Zcount = lv_next ) ).
  ENDMETHOD.

  METHOD getExcelData.
    DATA lv_filecontent TYPE xstring.
    DATA lt_file        TYPE tt_file_upload.
    DATA ls_file        TYPE ty_file_upload.
    DATA lt_file_c      TYPE TABLE FOR CREATE {{ROOT_I}}\{{CHILD_ASSOC}}.
    DATA ls_file_c      LIKE LINE OF lt_file_c.
    DATA lv_index       TYPE i.
    " DATA lt_file_2      TYPE tt_file_upload_<x2>.   " >>> CHILD 2

    " ── 1. Đọc Root ───────────────────────────────────────────────────
    READ ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY Root
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_record).

    IF lt_record IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE lt_record ASSIGNING FIELD-SYMBOL(<f_root>) INDEX 1.
    lv_filecontent = <f_root>-Attachment.
    CHECK lv_filecontent IS NOT INITIAL.

    " ── 2. [MULTI] Rẽ nhánh theo loại template đã lưu ở Root; app 1 template chỉ gọi read_main_sheet ──
    CASE <f_root>-Templatetype.
      " WHEN template_type-sub.
      "   lt_file_2 = read_<x2>_sheet( lv_filecontent ).
      WHEN OTHERS.
        lt_file = read_main_sheet( lv_filecontent ).
    ENDCASE.

    " ── 3. Build create table cho child {{CHILD_ALIAS}} ──────────────
    LOOP AT lt_file INTO ls_file.
      lv_index += 1.

      CLEAR ls_file_c.
      ls_file_c = VALUE #(
          %tky    = <f_root>-%tky
          %target = VALUE #( (
            %cid     = |CID_D_{ lv_index }|
            Type     = 'I'                    " template Mass Create; Mass Change dùng 'U'
            Sequence = lv_index               " hoặc to_int( ls_file-Sequence ) nếu template có cột STT
            " ---------- {{BUSINESS_FIELDS}}: string -> kiểu đích bằng helper ----------
            " CompanyCode           = ls_file-CompanyCode
            " PostCapitalization    = to_flag( ls_file-PostCapitalization )
            " OrderDate             = to_date( ls_file-OrderDate )
            " UsefulLifeYears       = to_int( ls_file-UsefulLifeYears )
            Status   = file_status-open
          ) )
      ).

      APPEND ls_file_c TO lt_file_c.
    ENDLOOP.

    IF lt_file_c IS NOT INITIAL.
      MODIFY ENTITIES OF {{ROOT_I}} IN LOCAL MODE
        ENTITY Root
        CREATE BY \{{CHILD_ASSOC}}
        FIELDS (
          Type
          Sequence
          " ---------- {{BUSINESS_FIELDS}} ----------
          Status
        )
        WITH lt_file_c
        MAPPED   DATA(lt_mapped_create)
        REPORTED DATA(lt_mapped_reported)
        FAILED   DATA(lt_failed_create).
    ENDIF.

    " >>> CHILD 2: LOOP AT lt_file_2 ... CREATE BY \_<Alias2> FIELDS (...) tương tự khối trên,
    "     %cid = |CID_S_{ idx }| để không trùng cid với child 1. <<<
  ENDMETHOD.

  METHOD read_main_sheet.
    DATA lt_rows TYPE tt_file_upload.

    CHECK iv_filecontent IS NOT INITIAL.

    FINAL(lo_xlsx) = xco_cp_xlsx=>document->for_file_content(
                       iv_file_content = iv_filecontent
                     )->read_access( ).
    FINAL(lo_worksheet) = lo_xlsx->get_workbook( )->worksheet->at_position( c_data_sheet_pos ).
    FINAL(lo_selection_pattern) = xco_cp_xlsx_selection=>pattern_builder->simple_from_to( )->get_pattern( ).
    FINAL(lo_execute) = lo_worksheet->select( lo_selection_pattern
      )->row_stream(
      )->operation->write_to( REF #( lt_rows ) ).

    lo_execute->set_value_transformation(
      xco_cp_xlsx_read_access=>value_transformation->string_value
    )->if_xco_xlsx_ra_operation~execute( ).

    " bỏ các dòng header
    IF lt_rows IS NOT INITIAL.
      DO c_header_rows TIMES.
        DELETE lt_rows INDEX 1.
      ENDDO.
    ENDIF.

    " bỏ dòng trống cuối sheet: {{KEY_COLS_NOT_EMPTY}}
    " DELETE lt_rows WHERE CompanyCode IS INITIAL AND AssetClass IS INITIAL.

    rt_rows = lt_rows.
  ENDMETHOD.

  " >>> CHILD 2: METHOD read_<x2>_sheet: copy read_main_sheet, đổi kiểu bảng + điều kiện DELETE <<<

  METHOD to_int.
    DATA lv_text TYPE string.
    DATA lv_rest TYPE string.

    lv_text = condense( iv_text ).
    CHECK lv_text IS NOT INITIAL.
    " Excel có thể trả '10.0' cho ô số -> bỏ phần thập phân
    SPLIT lv_text AT '.' INTO lv_text lv_rest.
    TRY.
        rv_out = lv_text.
      CATCH cx_sy_conversion_error.
        rv_out = 0.
    ENDTRY.
  ENDMETHOD.

  METHOD to_flag.
    " 'X', 'T', 'true' -> 'X'; còn lại -> ''
    IF iv_text CP 'X*' OR iv_text CP 'T*' OR iv_text CP '*true*'.
      rv_out = 'X'.
    ELSE.
      rv_out = ''.
    ENDIF.
  ENDMETHOD.

  METHOD to_date.
    " "DD.MM.YYYY" -> abap.dats (YYYYMMDD); rỗng/sai format/không phải ngày thật -> initial date
    DATA lt_part          TYPE TABLE OF string.
    DATA lv_day           TYPE i.
    DATA lv_month         TYPE i.
    DATA lv_year          TYPE i.
    DATA lv_days_in_month TYPE i.
    DATA lv_is_leap       TYPE abap_bool.

    CHECK iv_text IS NOT INITIAL.

    SPLIT iv_text AT '.' INTO TABLE lt_part.
    CHECK lines( lt_part ) = 3.

    TRY.
        lv_day   = lt_part[ 1 ].
        lv_month = lt_part[ 2 ].
        lv_year  = lt_part[ 3 ].
      CATCH cx_sy_conversion_error.
        RETURN.
    ENDTRY.

    CHECK lv_year  BETWEEN 1000 AND 9999.
    CHECK lv_month BETWEEN 1 AND 12.
    CHECK lv_day   BETWEEN 1 AND 31.

    IF lv_year MOD 4 = 0 AND ( lv_year MOD 100 <> 0 OR lv_year MOD 400 = 0 ).
      lv_is_leap = abap_true.
    ELSE.
      lv_is_leap = abap_false.
    ENDIF.

    CASE lv_month.
      WHEN 4 OR 6 OR 9 OR 11.
        lv_days_in_month = 30.
      WHEN 2.
        IF lv_is_leap = abap_true.
          lv_days_in_month = 29.
        ELSE.
          lv_days_in_month = 28.
        ENDIF.
      WHEN OTHERS.
        lv_days_in_month = 31.
    ENDCASE.

    CHECK lv_day <= lv_days_in_month.

    rv_out = |{ lv_year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ lv_month WIDTH = 2 ALIGN = RIGHT PAD = '0' }{ lv_day WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD get_instance_features.
    READ ENTITIES OF {{ROOT_I}} IN LOCAL MODE
      ENTITY Root
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_root)
      FAILED failed.

    " File đã Done thì khoá update/delete
    result = VALUE #( FOR ls_root IN lt_root
      ( %tky    = ls_root-%tky
        %delete = COND #( WHEN ls_root-Status = file_status-completed
                           THEN if_abap_behv=>fc-o-disabled
                           ELSE if_abap_behv=>fc-o-enabled )
        %update = COND #( WHEN ls_root-Status = file_status-completed
                           THEN if_abap_behv=>fc-o-disabled
                           ELSE if_abap_behv=>fc-o-enabled )
      ) ).
  ENDMETHOD.

ENDCLASS.
