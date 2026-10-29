"=====================================================================
" API class: Sales Order Schedule Line (OData V2 API_SALES_ORDER_SRV)
" 1 dòng input = 1 lượt xử lý:
"   action 'U' (có Schedule line):
"       GET   A_SalesOrderScheduleLine(SalesOrder='..',SalesOrderItem='..',ScheduleLine='..')   -> lấy unit + ngày hiện tại
"       PATCH cùng path, body { ScheduleLineOrderQuantity, OrderQuantityUnit, OrderQuantitySAPUnit,
"                               OrderQuantityISOUnit, RequestedDeliveryDate }                 -> 204
"   action 'I' (Schedule line trống):
"       GET   A_SalesOrderItem(SalesOrder='..',SalesOrderItem='..')                             -> lấy unit của item
"       POST  A_SalesOrderItem(...)/to_ScheduleLine                                             -> 201, d.ScheduleLine
"       TODO: luồng insert chưa được test bằng curl, chỉ luồng update đã xác nhận.
"
" x-csrf-token: zcl_call_api tự GET preflight với 'x-csrf-token: fetch' trước mọi PATCH/POST
" và gắn token vào request thật. Truyền iv_endpoint = path entity để preflight GET đúng entity.
" Key V2 KHÔNG có 0 đầu: SalesOrder='10001855', SalesOrderItem='30', ScheduleLine='1'.
" Ngày V2 trong JSON: "/Date(1761177600000)/" (ms từ 1970-01-01 UTC).
"=====================================================================
CLASS zcl_so_schedline_upload DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    CONSTANTS:
      BEGIN OF action,
        insert TYPE c LENGTH 1 VALUE 'I',
        update TYPE c LENGTH 1 VALUE 'U',
      END OF action.

    TYPES ty_quantity TYPE p LENGTH 8 DECIMALS 3.

    TYPES:
      BEGIN OF ty_input,
        row_id           TYPE i,              " số dòng, chỉ dùng để merge kết quả
        action           TYPE c LENGTH 1,     " I = insert, U = update quantity
        sales_order      TYPE vbeln_va,       " A  (format nội bộ có 0 đầu, class tự bỏ khi build URL)
        sales_order_item TYPE posnr_va,       " B
        schedule_line    TYPE etenr,          " C  (rỗng khi insert)
        delivery_date    TYPE d,              " D  -> RequestedDeliveryDate
        order_quantity   TYPE ty_quantity,    " E  -> ScheduleLineOrderQuantity
      END OF ty_input,
      tt_input TYPE STANDARD TABLE OF ty_input WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_result,
        row_id              TYPE i,
        sales_order         TYPE string,
        sales_order_item    TYPE string,
        schedule_line       TYPE string,     " số schedule line (API cấp khi insert / echo khi update)
        order_quantity_unit TYPE string,
        success             TYPE abap_bool,
        http_status         TYPE i,
        message             TYPE string,
      END OF ty_result,
      tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    "! Service root OData V2 (đã xác nhận bằng request thật).
    CONSTANTS gc_service TYPE string VALUE '/sap/opu/odata/sap/API_SALES_ORDER_SRV'.

    "! Insert/update từng dòng, trả kết quả theo row_id.
    CLASS-METHODS process_schedule_lines
      IMPORTING
        it_data          TYPE tt_input
      RETURNING
        VALUE(rt_result) TYPE tt_result.

  PRIVATE SECTION.
    TYPES tt_fragment TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    " Entity V2 (cả A_SalesOrderItem lẫn A_SalesOrderScheduleLine đều có các field này).
    " Tên field snake_case; /ui2/cl_json camel_case so khớp không phân biệt hoa thường
    " nên OrderQuantityISOUnit <-> order_quantity_iso_unit vẫn map được.
    TYPES:
      BEGIN OF ty_entity,
        sales_order                  TYPE string,
        sales_order_item             TYPE string,
        schedule_line                TYPE string,
        requested_delivery_date      TYPE string,   " "/Date(ms)/"
        order_quantity_unit          TYPE string,
        order_quantity_sap_unit      TYPE string,
        order_quantity_iso_unit      TYPE string,
        schedule_line_order_quantity TYPE string,
      END OF ty_entity,
      BEGIN OF ty_v2_single,
        d TYPE ty_entity,
      END OF ty_v2_single.

    " OData V2 error body: { "error": { "code": "...", "message": { "lang": "en", "value": "..." } } }
    TYPES:
      BEGIN OF ty_v2_msg,
        lang  TYPE string,
        value TYPE string,
      END OF ty_v2_msg,
      BEGIN OF ty_v2_error,
        code    TYPE string,
        message TYPE ty_v2_msg,
      END OF ty_v2_error,
      BEGIN OF ty_v2_error_wrap,
        error TYPE ty_v2_error,
      END OF ty_v2_error_wrap.

    CONSTANTS gc_content_type TYPE string VALUE 'application/json'.

    CLASS-METHODS validate
      IMPORTING
        is_data        TYPE ty_input
      RETURNING
        VALUE(rv_text) TYPE string.

    CLASS-METHODS item_path
      IMPORTING
        is_data        TYPE ty_input
      RETURNING
        VALUE(rv_path) TYPE string.

    CLASS-METHODS schedline_path
      IMPORTING
        is_data        TYPE ty_input
      RETURNING
        VALUE(rv_path) TYPE string.

    "! GET 1 entity V2, parse phần "d". rv_ok = abap_false khi status <> 200.
    CLASS-METHODS get_entity
      IMPORTING
        iv_path      TYPE string
      EXPORTING
        es_entity    TYPE ty_entity
        ev_status    TYPE i
        ev_error     TYPE string
      RETURNING
        VALUE(rv_ok) TYPE abap_bool.

    CLASS-METHODS do_update
      IMPORTING
        is_data   TYPE ty_input
      CHANGING
        cs_result TYPE ty_result.

    CLASS-METHODS do_insert
      IMPORTING
        is_data   TYPE ty_input
      CHANGING
        cs_result TYPE ty_result.

    CLASS-METHODS build_quantity_fragments
      IMPORTING
        is_data        TYPE ty_input
        is_ref         TYPE ty_entity
      RETURNING
        VALUE(rt_frag) TYPE tt_fragment.

    CLASS-METHODS ext
      IMPORTING
        iv_value      TYPE clike
      RETURNING
        VALUE(rv_out) TYPE string.

    CLASS-METHODS format_qty
      IMPORTING
        iv_qty        TYPE ty_quantity
      RETURNING
        VALUE(rv_out) TYPE string.

    "! abap.dats -> "/Date(ms)/" theo chuẩn OData V2 JSON
    CLASS-METHODS format_date_v2
      IMPORTING iv_date       TYPE d
      RETURNING VALUE(rv_out) TYPE string.

    " ---- helper JSON dùng chung (harness) ----
    CLASS-METHODS field
      IMPORTING
        iv_key        TYPE string
        iv_value      TYPE string
        iv_raw        TYPE abap_bool DEFAULT abap_false
      RETURNING
        VALUE(rv_out) TYPE string.

    CLASS-METHODS as_object
      IMPORTING
        it_fragments  TYPE tt_fragment
      RETURNING
        VALUE(rv_out) TYPE string.

    CLASS-METHODS json_escape
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS extract_error_message
      IMPORTING
        iv_body        TYPE string
        iv_status      TYPE i
      RETURNING
        VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS zcl_so_schedline_upload IMPLEMENTATION.


  METHOD process_schedule_lines.
    DATA ls_data   TYPE ty_input.
    DATA ls_result TYPE ty_result.
    DATA lv_error  TYPE string.

    LOOP AT it_data INTO ls_data.
      CLEAR ls_result.
      ls_result-row_id           = ls_data-row_id.
      ls_result-sales_order      = ext( ls_data-sales_order ).
      ls_result-sales_order_item = ext( ls_data-sales_order_item ).
      ls_result-schedule_line    = ext( ls_data-schedule_line ).

      " Chặn sớm các dòng thiếu dữ liệu bắt buộc, không gọi API
      lv_error = validate( ls_data ).
      IF lv_error IS NOT INITIAL.
        ls_result-success = abap_false.
        ls_result-message = lv_error.
        APPEND ls_result TO rt_result.
        CONTINUE.
      ENDIF.

      IF ls_data-action = action-update.
        do_update( EXPORTING is_data = ls_data CHANGING cs_result = ls_result ).
      ELSE.
        do_insert( EXPORTING is_data = ls_data CHANGING cs_result = ls_result ).
      ENDIF.

      APPEND ls_result TO rt_result.
    ENDLOOP.
  ENDMETHOD.


  METHOD validate.
    IF is_data-sales_order IS INITIAL.
      rv_text = |Sales order is required|.
    ELSEIF is_data-sales_order_item IS INITIAL.
      rv_text = |Sales order item is required|.
    ELSEIF is_data-order_quantity IS INITIAL.
      rv_text = |Order quantity is required|.
    ELSEIF is_data-action = action-insert AND is_data-delivery_date IS INITIAL.
      rv_text = |Delivery date is required (DD.MM.YYYY)|.
    ELSEIF is_data-action = action-update AND is_data-schedule_line IS INITIAL.
      rv_text = |Schedule line is required for update|.
    ENDIF.
  ENDMETHOD.


  METHOD do_update.
    DATA lv_path       TYPE string.
    DATA ls_current    TYPE ty_entity.
    DATA lv_get_status TYPE i.
    DATA lv_get_error  TYPE string.
    DATA lv_ok         TYPE abap_bool.
    DATA lv_payload    TYPE string.
    DATA lv_body       TYPE string.
    DATA lv_status     TYPE i.

    lv_path = schedline_path( is_data ).

    " ── 1. GET schedule line hiện tại: kiểm tra tồn tại + lấy unit/ngày ──
    lv_ok = get_entity( EXPORTING iv_path   = lv_path
                        IMPORTING es_entity = ls_current
                                  ev_status = lv_get_status
                                  ev_error  = lv_get_error ).
    IF lv_ok = abap_false.
      cs_result-success     = abap_false.
      cs_result-http_status = lv_get_status.
      cs_result-message     = |GET schedule line failed: { lv_get_error }|.
      RETURN.
    ENDIF.

    " ── 2. PATCH số lượng (unit lấy từ GET, ngày: Excel nếu có, không thì giữ ngày hiện tại) ──
    lv_payload = as_object( build_quantity_fragments( is_data = is_data is_ref = ls_current ) ).

    " iv_endpoint = iv_uri = path entity -> preflight GET (x-csrf-token: fetch) chạy trên đúng entity
    lv_body = zcl_call_api=>call_api(
                iv_body        = lv_payload
                iv_contentType = gc_content_type
                iv_endpoint    = lv_path
                iv_uri         = lv_path
                iv_method      = 'PATCH' ).
    lv_status = zcl_call_api=>code.

    cs_result-http_status         = lv_status.
    cs_result-order_quantity_unit = ls_current-order_quantity_unit.

    CASE lv_status.
      WHEN 204 OR 200.
        cs_result-success = abap_true.
        cs_result-message = |Updated - Schedule line { cs_result-schedule_line } quantity { format_qty( is_data-order_quantity ) } { ls_current-order_quantity_unit }|.
      WHEN OTHERS.
        cs_result-success = abap_false.
        cs_result-message = extract_error_message( iv_body = lv_body iv_status = lv_status ).
    ENDCASE.
  ENDMETHOD.


  METHOD do_insert.
    DATA lv_item_path  TYPE string.
    DATA ls_item       TYPE ty_entity.
    DATA lv_get_status TYPE i.
    DATA lv_get_error  TYPE string.
    DATA lv_ok         TYPE abap_bool.
    DATA lt_frag       TYPE tt_fragment.
    DATA lv_payload    TYPE string.
    DATA lv_body       TYPE string.
    DATA lv_status     TYPE i.
    DATA ls_created    TYPE ty_v2_single.

    lv_item_path = item_path( is_data ).

    " ── 1. GET item: kiểm tra tồn tại + lấy unit của item ──
    lv_ok = get_entity( EXPORTING iv_path   = lv_item_path
                        IMPORTING es_entity = ls_item
                                  ev_status = lv_get_status
                                  ev_error  = lv_get_error ).
    IF lv_ok = abap_false.
      cs_result-success     = abap_false.
      cs_result-http_status = lv_get_status.
      cs_result-message     = |GET sales order item failed: { lv_get_error }|.
      RETURN.
    ENDIF.

    " ── 2. POST schedule line mới qua navigation to_ScheduleLine ──
    " TODO: chưa test bằng curl. Nếu API không cho POST, thay bằng deep PATCH item hoặc báo lỗi rõ.
    lt_frag = build_quantity_fragments( is_data = is_data is_ref = ls_item ).
    INSERT field( iv_key = 'SalesOrderItem' iv_value = ext( is_data-sales_order_item ) ) INTO lt_frag INDEX 1.
    INSERT field( iv_key = 'SalesOrder'     iv_value = ext( is_data-sales_order ) )      INTO lt_frag INDEX 1.
    lv_payload = as_object( lt_frag ).

    lv_body = zcl_call_api=>call_api(
                iv_body        = lv_payload
                iv_contentType = gc_content_type
                iv_endpoint    = lv_item_path
                iv_uri         = |{ lv_item_path }/to_ScheduleLine|
                iv_method      = 'POST' ).
    lv_status = zcl_call_api=>code.

    cs_result-http_status         = lv_status.
    cs_result-order_quantity_unit = ls_item-order_quantity_unit.

    CASE lv_status.
      WHEN 201.
        cs_result-success = abap_true.
        TRY.
            /ui2/cl_json=>deserialize(
              EXPORTING json        = lv_body
                        pretty_name = /ui2/cl_json=>pretty_mode-camel_case
              CHANGING  data        = ls_created ).
          CATCH cx_root ##NO_HANDLER.
        ENDTRY.
        cs_result-schedule_line = ls_created-d-schedule_line.
        cs_result-message       = |Created - Schedule line { cs_result-schedule_line } quantity { format_qty( is_data-order_quantity ) } { ls_item-order_quantity_unit }|.
      WHEN OTHERS.
        cs_result-success = abap_false.
        cs_result-message = extract_error_message( iv_body = lv_body iv_status = lv_status ).
    ENDCASE.
  ENDMETHOD.


  METHOD get_entity.
    DATA lv_body TYPE string.
    DATA ls_wrap TYPE ty_v2_single.
    DATA lx_json TYPE REF TO cx_root.

    CLEAR: es_entity, ev_error.

    lv_body = zcl_call_api=>call_api(
                iv_body        = ``
                iv_contentType = gc_content_type
                iv_endpoint    = gc_service
                iv_uri         = iv_path
                iv_method      = 'GET' ).
    ev_status = zcl_call_api=>code.

    IF ev_status <> 200.
      ev_error = extract_error_message( iv_body = lv_body iv_status = ev_status ).
      rv_ok = abap_false.
      RETURN.
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json        = lv_body
                    pretty_name = /ui2/cl_json=>pretty_mode-camel_case
          CHANGING  data        = ls_wrap ).
      CATCH cx_root INTO lx_json.
        ev_error = |Cannot parse response: { lx_json->get_text( ) }|.
        rv_ok = abap_false.
        RETURN.
    ENDTRY.

    es_entity = ls_wrap-d.
    rv_ok = abap_true.
  ENDMETHOD.


  METHOD build_quantity_fragments.
    DATA lv_date TYPE string.

    " Payload PATCH đã xác nhận bằng request thật:
    " { "ScheduleLineOrderQuantity": "20", "OrderQuantityUnit": "VIE", "OrderQuantitySAPUnit": "VIE",
    "   "OrderQuantityISOUnit": "VIE", "RequestedDeliveryDate": "/Date(1761177600000)/" }
    APPEND field( iv_key = 'ScheduleLineOrderQuantity' iv_value = format_qty( is_data-order_quantity ) ) TO rt_frag.
    APPEND field( iv_key = 'OrderQuantityUnit'         iv_value = is_ref-order_quantity_unit )           TO rt_frag.
    APPEND field( iv_key = 'OrderQuantitySAPUnit'      iv_value = is_ref-order_quantity_sap_unit )       TO rt_frag.
    APPEND field( iv_key = 'OrderQuantityISOUnit'      iv_value = is_ref-order_quantity_iso_unit )       TO rt_frag.

    " Ngày giao: cột D nếu có, không thì giữ nguyên ngày đang có trên schedule line
    IF is_data-delivery_date IS NOT INITIAL.
      lv_date = format_date_v2( is_data-delivery_date ).
    ELSE.
      lv_date = is_ref-requested_delivery_date.
    ENDIF.
    APPEND field( iv_key = 'RequestedDeliveryDate' iv_value = lv_date ) TO rt_frag.
  ENDMETHOD.


  METHOD item_path.
    rv_path = |{ gc_service }/A_SalesOrderItem(SalesOrder='{ ext( is_data-sales_order ) }',SalesOrderItem='{ ext( is_data-sales_order_item ) }')|.
  ENDMETHOD.


  METHOD schedline_path.
    rv_path = |{ gc_service }/A_SalesOrderScheduleLine(SalesOrder='{ ext( is_data-sales_order ) }',SalesOrderItem='{ ext( is_data-sales_order_item ) }',ScheduleLine='{ ext( is_data-schedule_line ) }')|.
  ENDMETHOD.


  METHOD ext.
    " bỏ 0 đầu để đưa vào key V2: '0010001855' -> '10001855', '000030' -> '30', '0001' -> '1'
    rv_out = |{ iv_value ALPHA = OUT }|.
    rv_out = condense( rv_out ).
  ENDMETHOD.


  METHOD format_qty.
    " p -> '20.000' dấu chấm thập phân, không dấu nhóm nghìn (API nhận "20")
    rv_out = |{ iv_qty DECIMALS = 3 }|.
    rv_out = condense( rv_out ).
  ENDMETHOD.


  METHOD format_date_v2.
    DATA lv_epoch TYPE d VALUE '19700101'.
    DATA lv_days  TYPE i.
    DATA lv_ms    TYPE int8.

    IF iv_date IS INITIAL.
      rv_out = ``.
      RETURN.
    ENDIF.
    " số ngày từ 1970-01-01 * 86.400.000 ms; ví dụ 2025-10-23 -> /Date(1761177600000)/
    lv_days = iv_date - lv_epoch.
    lv_ms   = lv_days.
    lv_ms   = lv_ms * 86400000.
    rv_out  = |/Date({ lv_ms })/|.
  ENDMETHOD.


  METHOD extract_error_message.
    DATA ls_wrap TYPE ty_v2_error_wrap.

    IF iv_status = 0.
      " lỗi transport/local trong zcl_call_api, không phải HTTP status
      IF zcl_call_api=>reason IS NOT INITIAL.
        rv_text = zcl_call_api=>reason.
      ELSE.
        rv_text = iv_body.
      ENDIF.
      RETURN.
    ENDIF.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json = iv_body
          CHANGING  data = ls_wrap ).
      CATCH cx_root ##NO_HANDLER.
    ENDTRY.

    IF ls_wrap-error-message-value IS NOT INITIAL.
      rv_text = ls_wrap-error-message-value.
    ELSEIF iv_body IS NOT INITIAL.
      rv_text = iv_body.
    ELSE.
      rv_text = |HTTP { iv_status }|.
    ENDIF.
  ENDMETHOD.


  METHOD field.
    IF iv_value IS INITIAL AND iv_raw = abap_false.
      rv_out = ``.
      RETURN.
    ENDIF.

    IF iv_raw = abap_true.
      rv_out = |"{ iv_key }":{ iv_value }|.
    ELSE.
      rv_out = |"{ iv_key }":"{ json_escape( iv_value ) }"|.
    ENDIF.
  ENDMETHOD.


  METHOD as_object.
    DATA lt_non_blank TYPE tt_fragment.
    DATA lv_frag      TYPE string.

    LOOP AT it_fragments INTO lv_frag WHERE table_line IS NOT INITIAL.
      APPEND lv_frag TO lt_non_blank.
    ENDLOOP.
    rv_out = |\{{ concat_lines_of( table = lt_non_blank sep = ',' ) }\}|.
  ENDMETHOD.


  METHOD json_escape.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN rv_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '\"'.
  ENDMETHOD.
ENDCLASS.
