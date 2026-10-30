CLASS zcl_fa_sub_asset_upload DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    "===============================================================
    " Input row -> 1 row = 1 asset sub-number to create.
    " Field order follows sheet "Create_Sub asset" of the template:
    " giống sheet main nhưng cột B là MasterFixedAsset thay cho AssetClass
    " (sub-number kế thừa AssetClass từ tài sản chính).
    "===============================================================
    TYPES:
      BEGIN OF ty_sub_asset_input,
        row_id                  TYPE i,           " số dòng riêng, chỉ dùng để log kết quả
        company_code            TYPE string,      " A: CompanyCode
        master_fixed_asset      TYPE string,      " B: MasterFixedAsset (tài sản chính đã tồn tại)
        post_capitalization     TYPE abap_bool,   " C: AssetIsForPostCapitalization
        fixed_asset_description TYPE string,      " D: FixedAssetDescription
        additional_description  TYPE string,      " E: AssetAdditionalDescription
        base_unit_iso_code      TYPE string,      " F: BaseUnitISOCode
        serial_number           TYPE string,      " G: AssetSerialNumber
        order_date              TYPE d,           " H: FixedAssetOrderDate
        eval_group_1            TYPE string,      " I: YY1_EvaluationGroup1_FAA
        eval_group_2            TYPE string,      " J: YY1_EvaluationGroup2_FAA
        eval_group_3            TYPE string,      " K: YY1_EvaluationGroup3_FAA
        inventory_number        TYPE string,      " L: Inventory
        last_inventory_date     TYPE d,           " M: LastInventoryDate
        inventory_note          TYPE string,      " N: InventoryNote
        inventory_is_counted    TYPE abap_bool,   " O: InventoryIsCounted
        cost_center             TYPE string,      " P: CostCenter
        profit_center           TYPE string,      " Q: ProfitCenter
        plant                   TYPE string,      " R: Plant
        room                    TYPE string,      " S: Room
        segment                 TYPE string,      " T: Segment
        asset_location          TYPE string,      " U: AssetLocation
        supplier                TYPE string,      " V: Supplier
        asset_is_acquired_used  TYPE abap_bool,   " W: AssetIsAcquiredUsed
        manufacturer_name       TYPE string,      " X: AssetManufacturerName
        capitalization_date     TYPE d,           " Y: AssetCapitalizationDate
        deactivation_date       TYPE d,           " Z: AssetDeactivationDate
        useful_life_years       TYPE i,           " AA: PlannedUsefulLifeInYears
        useful_life_periods     TYPE i,           " AB: PlannedUsefulLifeInPeriods
        depreciation_start_date TYPE d,           " AC: DepreciationStartDate
      END OF ty_sub_asset_input,
      tt_sub_asset_input TYPE STANDARD TABLE OF ty_sub_asset_input WITH EMPTY KEY.

    " Dùng chung kiểu cấu hình ledger với class tạo tài sản chính
    TYPES tt_ledger_area_cfg TYPE zcl_fa_master_asset_upload=>tt_ledger_area_cfg.

    TYPES:
      BEGIN OF ty_result,
        row_id             TYPE i,
        company_code       TYPE string,
        master_fixed_asset TYPE string,   " tài sản chính (echo từ API)
        fixed_asset        TYPE string,   " sub-number được tạo (API trả về trong field FixedAsset)
        description        TYPE string,
        success            TYPE abap_bool,
        http_status        TYPE i,
        message            TYPE string,
      END OF ty_result,
      tt_result TYPE STANDARD TABLE OF ty_result WITH EMPTY KEY.

    "! Entity set của API_FIXEDASSET - giống class tạo tài sản chính.
    CONSTANTS gc_endpoint TYPE string VALUE
      '/sap/opu/odata4/sap/api_fixedasset/srvd_a2x/sap/fixedasset/0001/FixedAsset'.

    "! Bound action tạo sub-number: POST .../FixedAsset/SAP__self.CreateFixedAsset
    "! (CreateMasterFixedAsset tạo tài sản chính; CreateFixedAsset tạo sub-number dưới MasterFixedAsset).
    "! Payload tối thiểu đã test OK: CompanyCode + MasterFixedAsset + _General + _AccountAssignment.
    CONSTANTS gc_action_create_sub TYPE string VALUE 'CreateFixedAsset'.

    "! Tạo 1 sub-number cho mỗi dòng trong IT_SUB_DATA, gọi ZCL_CALL_API=>call_api (POST) từng dòng.
    CLASS-METHODS create_subnumbers
      IMPORTING
        it_sub_data      TYPE tt_sub_asset_input
        it_ledger_cfg    TYPE tt_ledger_area_cfg
      RETURNING
        VALUE(rt_result) TYPE tt_result.

  PRIVATE SECTION.
    TYPES tt_fragment TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    "! Tra tài sản chính trong I_FixedAsset theo CompanyCode + MasterFixedAsset.
    "! rv_found = abap_false khi không tồn tại; ev_inventory_is_counted = cờ Inventory của tài sản chính.
    CLASS-METHODS read_master_asset
      IMPORTING
        iv_company_code             TYPE string
        iv_master_fixed_asset       TYPE string
      EXPORTING
        ev_inventory_is_counted     TYPE abap_bool
      RETURNING
        VALUE(rv_found)             TYPE abap_bool.

    CLASS-METHODS build_payload
      IMPORTING
        is_sub         TYPE ty_sub_asset_input
        it_ledger_cfg  TYPE tt_ledger_area_cfg
      RETURNING
        VALUE(rv_json) TYPE string.

    CLASS-METHODS build_ledger_array
      IMPORTING
        is_sub         TYPE ty_sub_asset_input
        it_ledger_cfg  TYPE tt_ledger_area_cfg
      RETURNING
        VALUE(rv_json) TYPE string.

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



CLASS zcl_fa_sub_asset_upload IMPLEMENTATION.


  METHOD create_subnumbers.
    DATA ls_sub               TYPE ty_sub_asset_input.
    DATA ls_result            TYPE ty_result.
    DATA lv_master_found      TYPE abap_bool.
    DATA lv_master_inv_flag   TYPE abap_bool.
    DATA lv_payload           TYPE string.
    DATA lv_body              TYPE string.

    LOOP AT it_sub_data INTO ls_sub.
      CLEAR ls_result.
      ls_result-row_id             = ls_sub-row_id.
      ls_result-company_code       = ls_sub-company_code.
      ls_result-master_fixed_asset = ls_sub-master_fixed_asset.
      ls_result-description        = ls_sub-fixed_asset_description.

      " Sub-number bắt buộc phải có tài sản chính - chặn sớm, không gọi API
      IF ls_sub-master_fixed_asset IS INITIAL.
        ls_result-success = abap_false.
        ls_result-message = |MasterFixedAsset is required to create a sub-number|.
        APPEND ls_result TO rt_result.
        CONTINUE.
      ENDIF.

      " Tra tài sản chính trong I_FixedAsset: không có -> lỗi; có -> lấy cờ Inventory để sub-number kế thừa
      lv_master_found = read_master_asset( EXPORTING iv_company_code         = ls_sub-company_code
                                                     iv_master_fixed_asset   = ls_sub-master_fixed_asset
                                           IMPORTING ev_inventory_is_counted = lv_master_inv_flag ).
      IF lv_master_found = abap_false.
        ls_result-success = abap_false.
        ls_result-message = |Master fixed asset { ls_sub-master_fixed_asset } not found in company code { ls_sub-company_code }|.
        APPEND ls_result TO rt_result.
        CONTINUE.
      ENDIF.

      " InventoryIsCounted của sub-number = của tài sản chính, không lấy từ Excel
      ls_sub-inventory_is_counted = lv_master_inv_flag.

      lv_payload = build_payload( is_sub        = ls_sub
                                  it_ledger_cfg = it_ledger_cfg ).

      lv_body = zcl_call_api=>call_api(
                  iv_body        = lv_payload
                  iv_contentType = 'application/json;odata.metadata=minimal;charset=utf-8'
                  iv_endpoint    = gc_endpoint
                  iv_uri         = |{ gc_endpoint }/SAP__self.{ gc_action_create_sub }|
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


  METHOD read_master_asset.
    DATA lv_company_code TYPE bukrs.
    DATA lv_master       TYPE anln1.
    DATA lv_flag         TYPE abap_bool.

    CLEAR ev_inventory_is_counted.
    rv_found = abap_false.

    lv_company_code = iv_company_code.
    lv_master       = iv_master_fixed_asset.
    " Excel có thể nhập '10000000' -> I_FixedAsset lưu '000010000000'
    lv_master       = |{ lv_master ALPHA = IN }|.

    " Tài sản chính có FixedAsset (sub-number) nhỏ nhất = '0000'; ORDER BY để chắc chắn lấy đúng dòng chính
    SELECT inventoryiscounted
      FROM i_fixedasset
      WHERE companycode      = @lv_company_code
        AND masterfixedasset = @lv_master
      ORDER BY fixedasset
      INTO @lv_flag
      UP TO 1 ROWS.
      rv_found = abap_true.
      ev_inventory_is_counted = lv_flag.
    ENDSELECT.
  ENDMETHOD.


  METHOD parse_response.
    cs_result-http_status = iv_status.

    IF iv_status = 201.
      cs_result-success = abap_true.

      TRY.
          /ui2/cl_json=>deserialize(
            EXPORTING json = iv_body
            pretty_name = /ui2/cl_json=>pretty_mode-camel_case
            CHANGING  data = cs_result ).
        CATCH cx_root ##NO_HANDLER.
      ENDTRY.

      " Với sub-number, FixedAsset chính là số sub được cấp (vd '1', '2'...)
      cs_result-message = COND #( WHEN cs_result-fixed_asset IS NOT INITIAL
                                   THEN |Created - Sub-number { cs_result-fixed_asset } of { cs_result-master_fixed_asset }|
                                   ELSE iv_body ).
    ELSE.
      cs_result-success = abap_false.
      cs_result-message = extract_error_message( iv_body ).
    ENDIF.
  ENDMETHOD.


  METHOD extract_error_message.
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

    rv_text = COND #( WHEN ls_wrap-error-message IS NOT INITIAL THEN ls_wrap-error-message ELSE iv_body ).
  ENDMETHOD.


  METHOD build_payload.
    DATA lt_root    TYPE tt_fragment.
    DATA lt_general TYPE tt_fragment.
    DATA lt_acct    TYPE tt_fragment.
    DATA lt_inv     TYPE tt_fragment.
    DATA lt_origin  TYPE tt_fragment.

    " Khác tài sản chính: gửi MasterFixedAsset, KHÔNG gửi AssetClass (kế thừa từ main)
    APPEND field( iv_key = 'CompanyCode'      iv_value = is_sub-company_code )       TO lt_root.
    APPEND field( iv_key = 'MasterFixedAsset' iv_value = is_sub-master_fixed_asset ) TO lt_root.

    IF is_sub-post_capitalization IS NOT INITIAL.
      APPEND field( iv_key = 'AssetIsForPostCapitalization'
                    iv_value = format_bool( is_sub-post_capitalization ) iv_raw = abap_true ) TO lt_root.
    ENDIF.

    APPEND field( iv_key = 'YY1_EvaluationGroup1_FAA' iv_value = is_sub-eval_group_1 ) TO lt_root.
    APPEND field( iv_key = 'YY1_EvaluationGroup2_FAA' iv_value = is_sub-eval_group_2 ) TO lt_root.
    APPEND field( iv_key = 'YY1_EvaluationGroup3_FAA' iv_value = is_sub-eval_group_3 ) TO lt_root.

    " ---------- _General ----------
    APPEND field( iv_key = 'FixedAssetDescription'      iv_value = is_sub-fixed_asset_description )   TO lt_general.
    APPEND field( iv_key = 'AssetAdditionalDescription' iv_value = is_sub-additional_description )    TO lt_general.
    APPEND field( iv_key = 'BaseUnitISOCode'            iv_value = is_sub-base_unit_iso_code )        TO lt_general.
    APPEND field( iv_key = 'AssetSerialNumber'          iv_value = is_sub-serial_number )             TO lt_general.
    APPEND field( iv_key = 'FixedAssetOrderDate'        iv_value = format_date( is_sub-order_date ) ) TO lt_general.
    APPEND |"_General":{ as_object( lt_general ) }| TO lt_root.

    " ---------- _AccountAssignment ----------
    APPEND field( iv_key = 'CostCenter'    iv_value = is_sub-cost_center )    TO lt_acct.
    APPEND field( iv_key = 'ProfitCenter'  iv_value = is_sub-profit_center )  TO lt_acct.
    APPEND field( iv_key = 'Plant'         iv_value = is_sub-plant )          TO lt_acct.
    APPEND field( iv_key = 'Room'          iv_value = is_sub-room )           TO lt_acct.
    APPEND field( iv_key = 'Segment'       iv_value = is_sub-segment )        TO lt_acct.
    APPEND field( iv_key = 'AssetLocation' iv_value = is_sub-asset_location ) TO lt_acct.
    APPEND |"_AccountAssignment":{ as_object( lt_acct ) }| TO lt_root.

    " ---------- _Inventory ----------
    " Luôn gửi InventoryIsCounted (đã gán = cờ của tài sản chính trong create_subnumbers);
    " các field Inventory khác chỉ gửi khi có dữ liệu (field() tự bỏ giá trị rỗng).
    APPEND field( iv_key = 'InventoryIsCounted'
                   iv_value = format_bool( is_sub-inventory_is_counted ) iv_raw = abap_true ) TO lt_inv.
    APPEND field( iv_key = 'Inventory'         iv_value = is_sub-inventory_number ) TO lt_inv.
    APPEND field( iv_key = 'InventoryNote'     iv_value = is_sub-inventory_note ) TO lt_inv.
    APPEND field( iv_key = 'LastInventoryDate' iv_value = format_date( is_sub-last_inventory_date ) ) TO lt_inv.
    APPEND |"_Inventory":{ as_object( lt_inv ) }| TO lt_root.

    " ---------- _Origin (optional) ----------
    IF is_sub-supplier IS NOT INITIAL OR is_sub-manufacturer_name IS NOT INITIAL
       OR is_sub-asset_is_acquired_used IS NOT INITIAL.
      APPEND field( iv_key = 'Supplier' iv_value = is_sub-supplier ) TO lt_origin.
      APPEND field( iv_key = 'AssetIsAcquiredUsed'
                     iv_value = format_bool( is_sub-asset_is_acquired_used ) iv_raw = abap_true ) TO lt_origin.
      APPEND field( iv_key = 'AssetManufacturerName' iv_value = is_sub-manufacturer_name ) TO lt_origin.
      APPEND |"_Origin":{ as_object( lt_origin ) }| TO lt_root.
    ENDIF.

    " ---------- _Ledger (array) - optional với sub-number ----------
    " Curl mẫu tạo sub-number không gửi _Ledger (kế thừa từ tài sản chính).
    " Chỉ gửi khi file có dữ liệu khấu hao riêng cho sub-number.
    IF it_ledger_cfg IS NOT INITIAL
       AND ( is_sub-capitalization_date IS NOT INITIAL OR is_sub-useful_life_years IS NOT INITIAL
          OR is_sub-useful_life_periods IS NOT INITIAL OR is_sub-depreciation_start_date IS NOT INITIAL ).
      APPEND |"_Ledger":[{ build_ledger_array( is_sub = is_sub it_ledger_cfg = it_ledger_cfg ) }]| TO lt_root.
    ENDIF.

    rv_json = as_object( lt_root ).
  ENDMETHOD.


  METHOD build_ledger_array.
    DATA(lt_cfg) = it_ledger_cfg.
    SORT lt_cfg BY ledger.

    DATA lt_ledgers TYPE tt_fragment.

    LOOP AT lt_cfg ASSIGNING FIELD-SYMBOL(<cfg>)
         GROUP BY ( ledger = <cfg>-ledger )
         ASSIGNING FIELD-SYMBOL(<areas_of_ledger>).

      DATA lt_ledger_fields TYPE tt_fragment.
      DATA lt_areas         TYPE tt_fragment.
      CLEAR: lt_ledger_fields, lt_areas.

      APPEND field( iv_key = 'Ledger' iv_value = <areas_of_ledger>-ledger ) TO lt_ledger_fields.
      APPEND field( iv_key = 'AssetCapitalizationDate'
                     iv_value = format_date( is_sub-capitalization_date ) ) TO lt_ledger_fields.

      LOOP AT GROUP <areas_of_ledger> INTO DATA(ls_area).
        DATA lt_time_based TYPE tt_fragment.
        CLEAR lt_time_based.

        APPEND field( iv_key = 'ValidityStartDate' iv_value = '1900-01-01' )            TO lt_time_based.
        APPEND field( iv_key = 'DepreciationKey'   iv_value = ls_area-depreciation_key ) TO lt_time_based.
        IF is_sub-useful_life_years IS NOT INITIAL.
          APPEND field( iv_key = 'PlannedUsefulLifeInYears'
                         iv_value = |{ is_sub-useful_life_years }| ) TO lt_time_based.
        ENDIF.
        IF is_sub-useful_life_periods IS NOT INITIAL.
          APPEND field( iv_key = 'PlannedUsefulLifeInPeriods'
                         iv_value = |{ is_sub-useful_life_periods }| ) TO lt_time_based.
        ENDIF.

        DATA lt_area_fields TYPE tt_fragment.
        CLEAR lt_area_fields.
        APPEND field( iv_key = 'AssetDepreciationArea' iv_value = ls_area-depreciation_area ) TO lt_area_fields.
        APPEND field( iv_key = 'DepreciationStartDate'
                       iv_value = format_date( is_sub-depreciation_start_date ) ) TO lt_area_fields.
        APPEND |"_TimeBasedValuation":[{ as_object( lt_time_based ) }]| TO lt_area_fields.

        APPEND as_object( lt_area_fields ) TO lt_areas.
      ENDLOOP.

      APPEND |"_Valuation":[{ concat_lines_of( table = lt_areas sep = ',' ) }]| TO lt_ledger_fields.

      APPEND as_object( lt_ledger_fields ) TO lt_ledgers.
    ENDLOOP.

    rv_json = concat_lines_of( table = lt_ledgers sep = ',' ).
  ENDMETHOD.


  METHOD field.
    IF iv_value IS INITIAL AND iv_raw = abap_false.
      rv_out = ``.
      RETURN.
    ENDIF.

    rv_out = COND #( WHEN iv_raw = abap_true THEN |"{ iv_key }":{ iv_value }|
                      ELSE |"{ iv_key }":"{ json_escape( iv_value ) }"| ).
  ENDMETHOD.


  METHOD as_object.
    DATA(lt_non_blank) = VALUE tt_fragment( FOR frag IN it_fragments WHERE ( table_line IS NOT INITIAL ) ( frag ) ).
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
    rv_out = COND #( WHEN iv_bool = abap_true THEN 'true' ELSE 'false' ).
  ENDMETHOD.


  METHOD json_escape.
    rv_text = iv_text.
    REPLACE ALL OCCURRENCES OF '\' IN rv_text WITH '\\'.
    REPLACE ALL OCCURRENCES OF '"' IN rv_text WITH '\"'.
  ENDMETHOD.
ENDCLASS.
