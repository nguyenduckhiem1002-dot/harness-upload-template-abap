"=====================================================================
" Local Types của zbp_r_m_sosl_upl - Upload Sales Order Schedule Line
" Theo harness rap-excel-upload: lhc_data (PostConfirm -> API), lhc_Root (upload/parse)
" Khai báo tường minh kiểu dữ liệu; inline DATA(...) chỉ dùng ở RESULT/FAILED/REPORTED
" của READ/MODIFY ENTITIES và chuỗi XCO.
"=====================================================================

CLASS lhc_data DEFINITION INHERITING FROM cl_abap_behavior_handler.

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

    TYPES tt_db_data TYPE STANDARD TABLE OF ztb_d_sosl_upl WITH EMPTY KEY.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Data RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Data RESULT result.

    METHODS PostConfirm FOR MODIFY
      IMPORTING keys FOR ACTION Data~PostConfirm RESULT result.

ENDCLASS.

CLASS lhc_data IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Data
        FIELDS ( Messagetype )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data)
      FAILED failed.

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
    DATA ls_data       TYPE ztb_d_sosl_upl.
    DATA lt_api_input  TYPE zcl_so_schedline_upload=>tt_input.
    DATA ls_api_input  TYPE zcl_so_schedline_upload=>ty_input.
    DATA lt_api_result TYPE zcl_so_schedline_upload=>tt_result.
    DATA ls_api_result TYPE zcl_so_schedline_upload=>ty_result.
    DATA lv_idx        TYPE i.
    DATA lv_uuidfile   TYPE sysuuid_x16.
    DATA lv_done       TYPE i.
    DATA lv_open       TYPE i.
    DATA lv_new_status TYPE ztb_m_sosl_upl-status.

    " ── 1. SELECT các dòng được chọn, chưa success ─────────────────────
    SELECT * FROM ztb_d_sosl_upl
      WITH PRIVILEGED ACCESS
      FOR ALL ENTRIES IN @keys
      WHERE uuid = @keys-uuid
        AND messagetype NE @file_status-success
      INTO TABLE @lt_data.

    IF lt_data IS INITIAL.
      RETURN.
    ENDIF.

    " Xử lý theo đúng thứ tự file trong cùng 1 item để schedule line insert được cấp số tăng dần
    SORT lt_data BY sales_order sales_order_item sequence.

    " ── 2. Map sang input API (row_id = index để merge ngược) ─────────
    LOOP AT lt_data INTO ls_data.
      lv_idx += 1.
      CLEAR ls_api_input.
      ls_api_input-row_id           = lv_idx.
      ls_api_input-action           = ls_data-type.          " I = insert, U = update quantity
      ls_api_input-sales_order      = ls_data-sales_order.
      ls_api_input-sales_order_item = ls_data-sales_order_item.
      ls_api_input-schedule_line    = ls_data-schedule_line.
      ls_api_input-delivery_date    = ls_data-delivery_date.
      ls_api_input-order_quantity   = ls_data-order_quantity.
      APPEND ls_api_input TO lt_api_input.
    ENDLOOP.

    " ── 3. Gọi API đồng bộ ────────────────────────────────────────────
    lt_api_result = zcl_so_schedline_upload=>process_schedule_lines( it_data = lt_api_input ).

    " ── 4. Merge kết quả theo row_id ─────────────────────────────────
    LOOP AT lt_api_result INTO ls_api_result.
      READ TABLE lt_data ASSIGNING FIELD-SYMBOL(<fs_merge>) INDEX ls_api_result-row_id.
      IF sy-subrc = 0.
        IF ls_api_result-success = abap_true.
          <fs_merge>-messagetype = file_status-success.
        ELSE.
          <fs_merge>-messagetype = file_status-error.
        ENDIF.
        <fs_merge>-message              = ls_api_result-message.
        <fs_merge>-schedule_line_result = ls_api_result-schedule_line.
        <fs_merge>-order_quantity_unit  = ls_api_result-order_quantity_unit.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Data
      UPDATE FIELDS ( Messagetype Message ScheduleLineResult OrderQuantityUnit )
      WITH VALUE #( FOR ls_upd IN lt_data (
        %tky-Uuid          = ls_upd-uuid
        %tky-Uuidfile      = ls_upd-uuidfile
        Messagetype        = ls_upd-messagetype
        Message            = ls_upd-message
        ScheduleLineResult = ls_upd-schedule_line_result
        OrderQuantityUnit  = ls_upd-order_quantity_unit
      ) )
      FAILED   DATA(lt_failed)
      REPORTED DATA(lt_reported).

    " ── 5. Tính lại Status + ZcountDone của Root trên toàn bộ dòng của file ──
    lv_uuidfile = lt_data[ 1 ]-uuidfile.

    SELECT COUNT( * ) FROM ztb_d_sosl_upl WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype = @file_status-success
      INTO @lv_done.
    SELECT COUNT( * ) FROM ztb_d_sosl_upl WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype <> @file_status-success
      INTO @lv_open.

    " các dòng vừa xử lý chưa commit DB -> bù theo kết quả vừa merge
    LOOP AT lt_data INTO ls_data WHERE messagetype = file_status-success.
      lv_done += 1.
      lv_open -= 1.
    ENDLOOP.

    IF lv_open = 0.
      lv_new_status = file_status-completed.
    ELSE.
      lv_new_status = file_status-inprocess.
    ENDIF.

    MODIFY ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Root
      UPDATE FIELDS ( Status ZcountDone )
      WITH VALUE #( (
        %tky-Uuid  = lv_uuidfile
        %is_draft  = if_abap_behv=>mk-off
        Status     = lv_new_status
        ZcountDone = lv_done
      ) )
      FAILED   DATA(lt_hdr_failed)
      REPORTED DATA(lt_hdr_reported).

    " ── 6. Trả $self ──────────────────────────────────────────────────
    result = VALUE #( FOR ls_key IN keys
      ( %tky        = ls_key-%tky
        %param-%tky = ls_key-%tky ) ).
  ENDMETHOD.

ENDCLASS.


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

    CONSTANTS:
      BEGIN OF line_action,
        insert TYPE c LENGTH 1 VALUE 'I', "Schedule line trống -> tạo mới
        update TYPE c LENGTH 1 VALUE 'U', "Có Schedule line -> update số lượng
      END OF line_action.

    " Template Schedule Line (theo ảnh mẫu): dòng 1 tên cột, dòng 2 ghi chú bắt buộc, dữ liệu từ dòng 3.
    " TODO: xác nhận lại với file template thật (harness chuẩn là 4 dòng header).
    CONSTANTS c_header_rows TYPE i VALUE 2.
    CONSTANTS c_data_sheet_pos TYPE i VALUE 1.
    CONSTANTS c_max_rows TYPE i VALUE 100.

    " App chỉ có 1 template nên không có Root.Templatetype; %param-TemplateType của dialog bị bỏ qua.

    " Thứ tự field PHẢI khớp cột A..E của sheet 1 (XCO map theo vị trí cột).
    TYPES: BEGIN OF ty_file_upload,
             SalesOrder     TYPE string, "A  Sales order         (bắt buộc)
             SalesOrderItem TYPE string, "B  Sales order item    (bắt buộc)
             ScheduleLine   TYPE string, "C  Schedule line       (trống = insert, có = update)
             DeliveryDate   TYPE string, "D  Delivery Date       (bắt buộc, DD.MM.YYYY)
             OrderQuantity  TYPE string, "E  Order quantity      (bắt buộc)
           END OF ty_file_upload.
    TYPES tt_file_upload TYPE STANDARD TABLE OF ty_file_upload WITH EMPTY KEY.

    TYPES ty_quantity TYPE ztb_d_sosl_upl-order_quantity.

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

    METHODS to_date
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE d.

    METHODS to_int
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE i.

    " text số lượng ('10', '10.5', '10,5', '1.000,5') -> dec(15,3); không parse được -> 0
    METHODS to_dec
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE ty_quantity.

    " text số chứng từ -> VBELN nội bộ (thêm 0 đầu nếu toàn số); giữ nguyên nếu có chữ
    METHODS to_vbeln
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE vbeln_va.

ENDCLASS.

CLASS lhc_Root IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_global_authorizations.
  ENDMETHOD.

  METHOD downloadFile.
    " TODO: build file kết quả từ ztb_d_sosl_upl và trả về qua zabs_file_crud_poc
  ENDMETHOD.

  METHOD uploadExcel.
    DATA lt_mn_root      TYPE TABLE FOR CREATE zr_m_sosl_upl.
    DATA ls_mn_root      LIKE LINE OF lt_mn_root.
    DATA lv_filecontent  TYPE xstring.
    DATA lt_rows         TYPE tt_file_upload.
    DATA lv_total_lines  TYPE i.
    FIELD-SYMBOLS <k>    LIKE LINE OF keys.

    READ TABLE keys ASSIGNING <k> INDEX 1.
    CHECK sy-subrc = 0.

    IF <k>-%param-FileContent IS INITIAL.
      RETURN.
    ENDIF.

    lv_filecontent = <k>-%param-FileContent.

    ls_mn_root-Attachment = lv_filecontent.
    ls_mn_root-Filename   = <k>-%param-FileName.
    ls_mn_root-Mimetype   = <k>-%param-MimeType.

    lt_rows        = read_main_sheet( lv_filecontent ).
    lv_total_lines = lines( lt_rows ).

    IF lv_total_lines > c_max_rows.
      APPEND VALUE #( %cid = <k>-%cid
                       %msg = new_message( id       = 'Z_FILE_MSG'   " TODO: message class thật
                                            number   = '001'         " File vượt quá 100 dòng
                                            severity = if_abap_behv_message=>severity-error ) )
        TO reported-root.
      RETURN.
    ENDIF.

    ls_mn_root-Countline = lv_total_lines.
    APPEND ls_mn_root TO lt_mn_root.

    MODIFY ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Root
      CREATE AUTO FILL CID FIELDS (
                        Status
                        Attachment
                        Mimetype
                        Filename
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
                     %msg = new_message( id       = 'Z_FILE_MSG'   " TODO: message class thật
                                          number   = '002'         " Upload thành công
                                          severity = if_abap_behv_message=>severity-success ) )
      TO reported-root.
  ENDMETHOD.

  METHOD setStatusToOpen.
    DATA lv_cnt1 TYPE i.
    DATA lv_cnt2 TYPE i.
    DATA lv_next TYPE i.

    READ ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
     ENTITY Root
       FIELDS ( Status )
       WITH CORRESPONDING #( keys )
     RESULT DATA(lt_root).

    DELETE lt_root WHERE Status IS NOT INITIAL.
    CHECK lt_root IS NOT INITIAL.

    SELECT SINGLE MAX( zcount ) FROM ztb_m_sosl_upl
      WHERE createdbyuser = @sy-uname INTO @lv_cnt1.
    SELECT SINGLE MAX( zcount ) FROM ztb_m_sosl_d
      WHERE createdbyuser = @sy-uname INTO @lv_cnt2.

    IF lv_cnt1 >= lv_cnt2.
      lv_next = lv_cnt1 + 1.
    ELSE.
      lv_next = lv_cnt2 + 1.
    ENDIF.

    MODIFY ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Root
        UPDATE FIELDS ( Status Zcount )
        WITH VALUE #( FOR ls_root IN lt_root ( %tky   = ls_root-%tky
                                                Status = file_status-open
                                                Zcount = lv_next ) ).
  ENDMETHOD.

  METHOD getExcelData.
    DATA lv_filecontent   TYPE xstring.
    DATA lt_file          TYPE tt_file_upload.
    DATA ls_file          TYPE ty_file_upload.
    DATA lt_file_c        TYPE TABLE FOR CREATE zr_m_sosl_upl\_Data.
    DATA ls_file_c        LIKE LINE OF lt_file_c.
    DATA lv_index         TYPE i.
    DATA lv_schedule_line TYPE i.
    DATA lv_type          TYPE ztb_d_sosl_upl-type.

    " ── 1. Đọc Root ───────────────────────────────────────────────────
    READ ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Root
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_record).

    IF lt_record IS INITIAL.
      RETURN.
    ENDIF.

    READ TABLE lt_record ASSIGNING FIELD-SYMBOL(<f_root>) INDEX 1.
    lv_filecontent = <f_root>-Attachment.
    CHECK lv_filecontent IS NOT INITIAL.

    " ── 2. Parse sheet 1 ─────────────────────────────────────────────
    lt_file = read_main_sheet( lv_filecontent ).

    " ── 3. Build create table cho child Data ─────────────────────────
    LOOP AT lt_file INTO ls_file.
      lv_index += 1.

      " Schedule line trống -> insert dòng mới; có số -> update số lượng dòng đó
      lv_schedule_line = to_int( ls_file-ScheduleLine ).
      IF lv_schedule_line = 0.
        lv_type = line_action-insert.
      ELSE.
        lv_type = line_action-update.
      ENDIF.

      CLEAR ls_file_c.
      ls_file_c = VALUE #(
          %tky    = <f_root>-%tky
          %target = VALUE #( (
            %cid           = |CID_D_{ lv_index }|
            Sequence       = lv_index
            Type           = lv_type
            SalesOrder     = to_vbeln( ls_file-SalesOrder )
            SalesOrderItem = to_int( ls_file-SalesOrderItem )     " int -> NUMC6 tự thêm 0 đầu
            ScheduleLine   = lv_schedule_line                     " 0 -> '0000' = initial của NUMC4 = trống
            DeliveryDate   = to_date( ls_file-DeliveryDate )
            OrderQuantity  = to_dec( ls_file-OrderQuantity )
            Status         = file_status-open
          ) )
      ).

      APPEND ls_file_c TO lt_file_c.
    ENDLOOP.

    IF lt_file_c IS NOT INITIAL.
      MODIFY ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
        ENTITY Root
        CREATE BY \_Data
        FIELDS (
          Type
          Sequence
          SalesOrder
          SalesOrderItem
          ScheduleLine
          DeliveryDate
          OrderQuantity
          Status
        )
        WITH lt_file_c
        MAPPED   DATA(lt_mapped_create)
        REPORTED DATA(lt_mapped_reported)
        FAILED   DATA(lt_failed_create).
    ENDIF.
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

    IF lt_rows IS NOT INITIAL.
      DO c_header_rows TIMES.
        DELETE lt_rows INDEX 1.
      ENDDO.
    ENDIF.

    " bỏ dòng trống cuối sheet
    DELETE lt_rows WHERE SalesOrder IS INITIAL AND SalesOrderItem IS INITIAL.

    rt_rows = lt_rows.
  ENDMETHOD.

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

  METHOD to_dec.
    DATA lv_text TYPE string.

    lv_text = condense( iv_text ).
    CHECK lv_text IS NOT INITIAL.

    " '1.000,5' (VN) -> '1000.5'; '10,5' -> '10.5'; '10.5' giữ nguyên
    IF lv_text CS ','.
      REPLACE ALL OCCURRENCES OF '.' IN lv_text WITH ''.
      REPLACE ',' IN lv_text WITH '.'.
    ENDIF.

    TRY.
        rv_out = lv_text.
      CATCH cx_sy_conversion_error.
        rv_out = 0.
    ENDTRY.
  ENDMETHOD.

  METHOD to_vbeln.
    DATA lv_text TYPE string.
    DATA lv_rest TYPE string.

    lv_text = condense( iv_text ).
    CHECK lv_text IS NOT INITIAL.

    " ô số trong Excel có thể trả '1234567.0'
    SPLIT lv_text AT '.' INTO lv_text lv_rest.

    rv_out = lv_text.
    IF lv_text CO '0123456789'.
      " toàn số -> thêm 0 đầu cho đủ 10 ký tự (format nội bộ VBELN)
      SHIFT rv_out RIGHT DELETING TRAILING space.
      OVERLAY rv_out WITH '0000000000'.
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
    READ ENTITIES OF zr_m_sosl_upl IN LOCAL MODE
      ENTITY Root
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_root)
      FAILED failed.

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
