"=====================================================================
" API class chuẩn cho 1 child/template: {{API_CLASS}}
" 1 dòng input = 1 request POST <entity set>/SAP__self.<bound action> qua zcl_call_api.
" Kết quả trả theo row_id để handler merge ngược vào bảng child.
" Placeholder: {{API_CLASS}} {{API_METHOD}} {{API_ENDPOINT}} {{API_ACTION}} {{BUSINESS_FIELDS}} {{RESULT_FIELDS}}
"=====================================================================
CLASS {{API_CLASS}} DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    " Input: 1 dòng = 1 record cần tạo. Kiểu ABAP đã chuẩn hoá (d, i, abap_bool), không còn string thô.
    TYPES:
      BEGIN OF ty_input,
        row_id TYPE i,                 " số dòng, chỉ dùng để merge kết quả
        " ---------- {{BUSINESS_FIELDS}} ----------
        " company_code            TYPE string,
        " post_capitalization     TYPE abap_bool,
        " order_date              TYPE d,
        " useful_life_years       TYPE i,
        " ...
      END OF ty_input,
      tt_input TYPE STANDARD TABLE OF ty_input WITH EMPTY KEY.

    " Cấu hình phụ (vd ledger/depreciation area) nếu API cần mảng con theo config; bỏ nếu không dùng.
    TYPES:
      BEGIN OF ty_ledger_area_cfg,
        ledger            TYPE string,
        depreciation_area TYPE string,
        depreciation_key  TYPE string,
      END OF ty_ledger_area_cfg,
      tt_ledger_area_cfg TYPE STANDARD TABLE OF ty_ledger_area_cfg WITH EMPTY KEY.

    " Kết quả: field tên theo property OData trả về để /ui2/cl_json deserialize thẳng (camelCase).
    TYPES:
      BEGIN OF ty_result,
        row_id      TYPE i,
        " ---------- {{RESULT_FIELDS}} (tên = property OData, snake_case) ----------
        " company_code       TYPE string,
        " fixed_asset        TYPE string,
        " master_fixed_asset TYPE string,
        description TYPE string,
        success     TYPE abap_bool,
        http_status TYPE i,
        message     TYPE string,
      END OF ty_result,
      tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    "! Entity set OData V4 (path tương đối, host/auth do zcl_call_api + ztb_api_auth lo).
    CONSTANTS gc_endpoint TYPE string VALUE '{{API_ENDPOINT}}'.

    "! Bound action (phần sau SAP__self.). Xác nhận bằng curl thật, không đoán.
    CONSTANTS gc_action TYPE string VALUE '{{API_ACTION}}'.

    "! Tạo 1 record cho mỗi dòng trong IT_DATA, gọi tuần tự, trả kết quả theo row_id.
    CLASS-METHODS {{API_METHOD}}
      IMPORTING
        it_data          TYPE tt_input
        it_ledger_cfg    TYPE tt_ledger_area_cfg OPTIONAL
      RETURNING
        VALUE(rt_result) TYPE tt_result.

  PRIVATE SECTION.
    TYPES tt_fragment TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    CLASS-METHODS build_payload
      IMPORTING
        is_data        TYPE ty_input
        it_ledger_cfg  TYPE tt_ledger_area_cfg
      RETURNING
        VALUE(rv_json) TYPE string.

    " ---- helper JSON dùng chung, copy nguyên, không sửa ----
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

    CLASS-METHODS format_date
      IMPORTING iv_date       TYPE d
      RETURNING VALUE(rv_out) TYPE string.

    CLASS-METHODS format_bool
      IMPORTING iv_bool       TYPE abap_bool
      RETURNING VALUE(rv_out) TYPE string.

    CLASS-METHODS json_escape
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_text) TYPE string.

    CLASS-METHODS parse_response
      IMPORTING
        iv_body   TYPE string
        iv_status TYPE i
      CHANGING
        cs_result TYPE ty_result.

    CLASS-METHODS extract_error_message
      IMPORTING
        iv_body        TYPE string
      RETURNING
        VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS {{API_CLASS}} IMPLEMENTATION.


  METHOD {{API_METHOD}}.
    " Khai báo tường minh, không dùng DATA(...) inline (xem SKILL.md)
    DATA ls_data    TYPE ty_input.
    DATA ls_result  TYPE ty_result.
    DATA lv_payload TYPE string.
    DATA lv_body    TYPE string.

    LOOP AT it_data INTO ls_data.
      CLEAR ls_result.
      ls_result-row_id = ls_data-row_id.
      " ls_result-description = ls_data-fixed_asset_description.

      " Validate tối thiểu trước khi gọi API (field bắt buộc mà thiếu thì API chắc chắn lỗi)
      " IF ls_data-<required_field> IS INITIAL.
      "   ls_result-success = abap_false.
      "   ls_result-message = |<Field> is required|.
      "   APPEND ls_result TO rt_result.
      "   CONTINUE.
      " ENDIF.

      lv_payload = build_payload( is_data       = ls_data
                                  it_ledger_cfg = it_ledger_cfg ).

      lv_body = zcl_call_api=>call_api(
                         iv_body        = lv_payload
                         iv_contentType = 'application/json;odata.metadata=minimal;charset=utf-8'
                         iv_endpoint    = gc_endpoint
                         iv_uri         = |{ gc_endpoint }/SAP__self.{ gc_action }|
                         iv_method      = 'POST' ).

      parse_response(
        EXPORTING
          iv_body   = lv_body
          iv_status = zcl_call_api=>code
        CHANGING
          cs_result = ls_result ).

      APPEND ls_result TO rt_result.
    ENDLOOP.
  ENDMETHOD.


  METHOD build_payload.
    DATA lt_root    TYPE tt_fragment.
    DATA lt_general TYPE tt_fragment.

    " ---------- field cấp root của payload ----------
    " APPEND field( iv_key = 'CompanyCode' iv_value = is_data-company_code ) TO lt_root.
    " field rỗng tự bị bỏ (field() trả '' và as_object() lọc), nên không cần IF cho string.
    " Boolean/number gửi raw: iv_raw = abap_true, và chỉ gửi khi có giá trị.
    " IF is_data-post_capitalization IS NOT INITIAL.
    "   APPEND field( iv_key = 'AssetIsForPostCapitalization'
    "                 iv_value = format_bool( is_data-post_capitalization ) iv_raw = abap_true ) TO lt_root.
    " ENDIF.

    " ---------- node con (vd _General) ----------
    " APPEND field( iv_key = 'FixedAssetDescription' iv_value = is_data-fixed_asset_description ) TO lt_general.
    " APPEND field( iv_key = 'FixedAssetOrderDate'   iv_value = format_date( is_data-order_date ) ) TO lt_general.
    " APPEND |"_General":{ as_object( lt_general ) }| TO lt_root.

    " ---------- node mảng theo config (vd _Ledger) chỉ khi cần ----------
    " IF it_ledger_cfg IS NOT INITIAL.
    "   APPEND |"_Ledger":[{ ... }]| TO lt_root.   " xem examples/fixed-asset/zcl_fa_sub_asset_upload build_ledger_array
    " ENDIF.

    rv_json = as_object( lt_root ).
  ENDMETHOD.


  METHOD parse_response.
    cs_result-http_status = iv_status.

    IF iv_status = 201.
      cs_result-success = abap_true.

      " body JSON của entity vừa tạo -> điền {{RESULT_FIELDS}} (camelCase -> snake_case)
      TRY.
          /ui2/cl_json=>deserialize(
            EXPORTING json = iv_body
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
            CHANGING  data = cs_result ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.

      cs_result-message = |Created|.
      " cs_result-message = COND #( WHEN cs_result-fixed_asset IS NOT INITIAL
      "                              THEN |Created - { cs_result-fixed_asset }| ELSE iv_body ).
    ELSE.
      cs_result-success = abap_false.
      cs_result-message = extract_error_message( iv_body ).
    ENDIF.
  ENDMETHOD.


  METHOD extract_error_message.
    " OData V4 error body: { "error": { "code": "...", "message": "...", "target": "..." } }
    TYPES:
      BEGIN OF ty_od_error,
        code    TYPE string,
        message TYPE string,
        target  TYPE string,
      END OF ty_od_error,
      BEGIN OF ty_od_error_wrap,
        error TYPE ty_od_error,
      END OF ty_od_error_wrap.

    DATA ls_wrap TYPE ty_od_error_wrap.

    TRY.
        /ui2/cl_json=>deserialize(
          EXPORTING json = iv_body
          CHANGING  data = ls_wrap ).
      CATCH cx_root ##NO_HANDLER.
    ENDTRY.

    IF ls_wrap-error-message IS NOT INITIAL.
      rv_text = ls_wrap-error-message.
    ELSE.
      rv_text = iv_body.
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


  METHOD format_date.
    IF iv_date IS INITIAL.
      rv_out = ``.
      RETURN.
    ENDIF.
    rv_out = |{ iv_date+0(4) }-{ iv_date+4(2) }-{ iv_date+6(2) }|.
  ENDMETHOD.


  METHOD format_bool.
    IF iv_bool = abap_true.
      rv_out = 'true'.
    ELSE.
      rv_out = 'false'.
    ENDIF.
  ENDMETHOD.


  METHOD json_escape.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN rv_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '\"'.
  ENDMETHOD.
ENDCLASS.
