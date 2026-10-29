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

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Data RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Data RESULT result.

    METHODS PostConfirm FOR MODIFY
      IMPORTING keys FOR ACTION Data~PostConfirm RESULT result.

ENDCLASS.

CLASS lhc_data IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Data
        FIELDS ( Messagetype )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data)
      FAILED failed.

    result = VALUE #( FOR ls_data IN lt_data
      ( %tky        = ls_data-%tky

        " Không cho update khi Status = 'D'
        %update     = COND #( WHEN ls_data-Messagetype = 'S'
                               THEN if_abap_behv=>fc-o-disabled
                               ELSE if_abap_behv=>fc-o-enabled )

         %delete     = COND #( WHEN ls_data-Messagetype = 'S'
                               THEN if_abap_behv=>fc-o-disabled
                               ELSE if_abap_behv=>fc-o-enabled )

        " Không cho gọi action PostConfirm khi đã Status = 'D'
        %action-PostConfirm = COND #( WHEN ls_data-Messagetype = 'S'
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
      ) ).
  ENDMETHOD.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD PostConfirm.
    DATA: lv_status TYPE char1.
    lv_status = 'S'.
    " ── 1. SELECT toàn bộ record cần xử lý ─────────────────────────
    SELECT * FROM ztb_d_mch_fa_upl
      WITH PRIVILEGED ACCESS
      FOR ALL ENTRIES IN @keys
      WHERE uuid = @keys-uuid
        AND messagetype NE @lv_status
      INTO TABLE @DATA(lt_data).

    IF lt_data IS INITIAL.
      RETURN.
    ENDIF.

    " ── 2. Map sang input của ZCL_FA_MASTER_ASSET_UPLOAD ────────────
    DATA(lt_asset_input) = VALUE zcl_fa_master_asset_upload=>tt_asset_input(
      FOR ls_data IN lt_data INDEX INTO lv_idx (
        row_id                  = lv_idx
        company_code            = ls_data-company_code
        asset_class             = ls_data-asset_class
        post_capitalization     = xsdbool( ls_data-post_capitalization = 'X' )
        fixed_asset_description = ls_data-fixed_asset_description
        additional_description  = ls_data-additional_description
        base_unit_iso_code      = ls_data-base_unit_iso_code
        serial_number           = ls_data-serial_number
        order_date              = ls_data-order_date
        eval_group_1            = ls_data-eval_group_1
        eval_group_2            = ls_data-eval_group_2
        eval_group_3            = ls_data-eval_group_3
        inventory_number        = ls_data-inventory_number
        last_inventory_date     = ls_data-last_inventory_date
        inventory_note          = ls_data-inventory_note
        inventory_is_counted    = xsdbool( ls_data-inventory_is_counted = 'X' )
        cost_center             = ls_data-cost_center
        profit_center           = ls_data-profit_center
        plant                   = ls_data-plant
        room                    = ls_data-room
        segment                 = ls_data-segment
        asset_location          = ls_data-asset_location
        supplier                = ls_data-supplier
        asset_is_acquired_used  = xsdbool( ls_data-asset_is_acquired_used = 'X' )
        manufacturer_name       = ls_data-manufacturer_name
        capitalization_date     = ls_data-capitalization_date
        deactivation_date       = ls_data-deactivation_date
        useful_life_years       = ls_data-useful_life_years
        useful_life_periods     = ls_data-useful_life_periods
        depreciation_start_date = ls_data-depreciation_start_date
      ) ).

    " TODO: cấu hình ledger/vùng khấu hao/khóa khấu hao thực tế theo công ty -
    " tạm hardcode giống curl mẫu ban đầu, thay bằng config thật khi cần dùng nhiều Company Code.
    DATA(lt_ledger_cfg) = VALUE zcl_fa_master_asset_upload=>tt_ledger_area_cfg(
      ( ledger = '0L' depreciation_area = '01' depreciation_key = '9INE' )
      ( ledger = '0L' depreciation_area = '15' depreciation_key = '9INE' )
      ( ledger = '2L' depreciation_area = '32' depreciation_key = 'LINE' ) ).

    " ── 3. Gọi API tạo tài sản - CHẠY ĐỒNG BỘ, không schedule job ────
    DATA(lt_api_result) = zcl_fa_master_asset_upload=>create_assets(
                             it_asset_data = lt_asset_input
                             it_ledger_cfg = lt_ledger_cfg ).

    " ── 4. Merge kết quả API ngược lại vào lt_data theo row_id ───────
    LOOP AT lt_api_result INTO DATA(ls_api_result).
      READ TABLE lt_data ASSIGNING FIELD-SYMBOL(<fs_merge>) INDEX ls_api_result-row_id.
      IF sy-subrc = 0.
        <fs_merge>-messagetype        = COND #( WHEN ls_api_result-success = abap_true THEN 'S' ELSE 'E' ).
        <fs_merge>-message            = ls_api_result-message.
        <fs_merge>-fixed_asset        = ls_api_result-fixed_asset.
        <fs_merge>-master_fixed_asset = ls_api_result-master_fixed_asset.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Data
      UPDATE FIELDS ( Messagetype Message FixedAsset MasterFixedAsset )
      WITH VALUE #( FOR ls_data IN lt_data (
        %tky-Uuid        = ls_data-uuid
        %tky-Uuidfile    = ls_data-uuidfile
        Messagetype      = ls_data-messagetype
        Message          = ls_data-message
        FixedAsset       = ls_data-fixed_asset
        MasterFixedAsset = ls_data-master_fixed_asset
      ) )
      FAILED   DATA(lt_failed)
      REPORTED DATA(lt_reported).

    " ── 5. Cập nhật status + ZcountDone của header ────────────────────
    DATA(lv_all_success) = abap_true.
    DATA(lv_count_done) = 0.
    LOOP AT lt_data INTO DATA(ls_child).
      IF ls_child-messagetype <> 'S'.
        lv_all_success = abap_false.
      ELSE.
        lv_count_done += 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_new_status) = COND #(
      WHEN lv_all_success = abap_true THEN file_status-completed
      ELSE file_status-inprocess ).

    MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Root
      UPDATE FIELDS ( Status ZcountDone )
      WITH VALUE #( (
        %tky-Uuid  = lt_data[ 1 ]-uuidfile
        %is_draft  = if_abap_behv=>mk-off
        Status     = lv_new_status
        ZcountDone = lv_count_done
      ) )
      FAILED   DATA(lt_hdr_failed)
      REPORTED DATA(lt_hdr_reported).

    " ── 6. Trả result trỏ về Root để UI navigate lại header ───────────
    result = VALUE #( FOR ls_key IN keys
      ( %tky        = ls_key-%tky
        %param-%tky = VALUE #( Uuid = lt_data[ 1 ]-uuid ) ) ).
  ENDMETHOD.

ENDCLASS.


"=====================================================================
" [+] Handler cho entity DataSub (ZI_D_MCH_FASUPL) - Asset Sub-number
"=====================================================================
CLASS lhc_datasub DEFINITION INHERITING FROM cl_abap_behavior_handler.

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

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR DataSub RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR DataSub RESULT result.

    METHODS PostConfirm FOR MODIFY
      IMPORTING keys FOR ACTION DataSub~PostConfirm RESULT result.

ENDCLASS.

CLASS lhc_datasub IMPLEMENTATION.

  METHOD get_instance_features.
    READ ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY DataSub
        FIELDS ( Messagetype )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_sub)
      FAILED failed.

    result = VALUE #( FOR ls_sub IN lt_sub
      ( %tky                = ls_sub-%tky
        %update             = COND #( WHEN ls_sub-Messagetype = file_status-success
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
        %delete             = COND #( WHEN ls_sub-Messagetype = file_status-success
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
        %action-PostConfirm = COND #( WHEN ls_sub-Messagetype = file_status-success
                                       THEN if_abap_behv=>fc-o-disabled
                                       ELSE if_abap_behv=>fc-o-enabled )
      ) ).
  ENDMETHOD.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD PostConfirm.
    " ── 1. SELECT các sub-number chưa tạo thành công ──────────────────
    SELECT * FROM ztb_d_mch_fasupl
      WITH PRIVILEGED ACCESS
      FOR ALL ENTRIES IN @keys
      WHERE uuid = @keys-uuid
        AND messagetype NE @file_status-success
      INTO TABLE @DATA(lt_sub).

    IF lt_sub IS INITIAL.
      RETURN.
    ENDIF.

    " Xử lý theo đúng thứ tự Sequence trong file để sub-number được cấp tăng dần
    SORT lt_sub BY master_fixed_asset sequence.

    " ── 2. Map sang input của ZCL_FA_SUB_ASSET_UPLOAD ─────────────────
    DATA(lt_sub_input) = VALUE zcl_fa_sub_asset_upload=>tt_sub_asset_input(
      FOR ls_sub IN lt_sub INDEX INTO lv_idx (
        row_id                  = lv_idx
        company_code            = ls_sub-company_code
        master_fixed_asset      = ls_sub-master_fixed_asset
        post_capitalization     = xsdbool( ls_sub-post_capitalization = 'X' )
        fixed_asset_description = ls_sub-fixed_asset_description
        additional_description  = ls_sub-additional_description
        base_unit_iso_code      = ls_sub-base_unit_iso_code
        serial_number           = ls_sub-serial_number
        order_date              = ls_sub-order_date
        eval_group_1            = ls_sub-eval_group_1
        eval_group_2            = ls_sub-eval_group_2
        eval_group_3            = ls_sub-eval_group_3
        inventory_number        = ls_sub-inventory_number
        last_inventory_date     = ls_sub-last_inventory_date
        inventory_note          = ls_sub-inventory_note
        inventory_is_counted    = xsdbool( ls_sub-inventory_is_counted = 'X' )
        cost_center             = ls_sub-cost_center
        profit_center           = ls_sub-profit_center
        plant                   = ls_sub-plant
        room                    = ls_sub-room
        segment                 = ls_sub-segment
        asset_location          = ls_sub-asset_location
        supplier                = ls_sub-supplier
        asset_is_acquired_used  = xsdbool( ls_sub-asset_is_acquired_used = 'X' )
        manufacturer_name       = ls_sub-manufacturer_name
        capitalization_date     = ls_sub-capitalization_date
        deactivation_date       = ls_sub-deactivation_date
        useful_life_years       = ls_sub-useful_life_years
        useful_life_periods     = ls_sub-useful_life_periods
        depreciation_start_date = ls_sub-depreciation_start_date
      ) ).

    " TODO: dùng chung cấu hình ledger với lhc_data~PostConfirm (hiện hardcode giống curl mẫu)
    DATA(lt_ledger_cfg) = VALUE zcl_fa_sub_asset_upload=>tt_ledger_area_cfg(
      ( ledger = '0L' depreciation_area = '01' depreciation_key = '9INE' )
      ( ledger = '0L' depreciation_area = '15' depreciation_key = '9INE' )
      ( ledger = '2L' depreciation_area = '32' depreciation_key = 'LINE' ) ).

    " ── 3. Gọi API tạo sub-number - đồng bộ ───────────────────────────
    DATA(lt_api_result) = zcl_fa_sub_asset_upload=>create_subnumbers(
                             it_sub_data   = lt_sub_input
                             it_ledger_cfg = lt_ledger_cfg ).

    " ── 4. Merge kết quả API ngược lại theo row_id ────────────────────
    " API trả FixedAsset = số sub-number vừa cấp, MasterFixedAsset = tài sản chính
    LOOP AT lt_api_result INTO DATA(ls_api_result).
      READ TABLE lt_sub ASSIGNING FIELD-SYMBOL(<fs_merge>) INDEX ls_api_result-row_id.
      IF sy-subrc = 0.
        <fs_merge>-messagetype           = COND #( WHEN ls_api_result-success = abap_true
                                                    THEN file_status-success ELSE file_status-error ).
        <fs_merge>-message               = ls_api_result-message.
        <fs_merge>-fixed_asset           = ls_api_result-master_fixed_asset.
        <fs_merge>-fixed_asset_subnumber = ls_api_result-fixed_asset.
      ENDIF.
    ENDLOOP.

    MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY DataSub
      UPDATE FIELDS ( Messagetype Message FixedAsset FixedAssetSubnumber )
      WITH VALUE #( FOR ls_sub IN lt_sub (
        %tky-Uuid           = ls_sub-uuid
        %tky-Uuidfile       = ls_sub-uuidfile
        Messagetype         = ls_sub-messagetype
        Message             = ls_sub-message
        FixedAsset          = ls_sub-fixed_asset
        FixedAssetSubnumber = ls_sub-fixed_asset_subnumber
      ) )
      FAILED   DATA(lt_failed)
      REPORTED DATA(lt_reported).

    " ── 5. Cập nhật status + ZcountDone của header ────────────────────
    " Tính trên CẢ HAI bảng con (main + sub) của file, không chỉ các dòng vừa xử lý,
    " để status 'D' chỉ set khi toàn bộ file đã xong.
    DATA(lv_uuidfile) = lt_sub[ 1 ]-uuidfile.

    DATA lv_done_main   TYPE i.
    DATA lv_done_sub    TYPE i.
    DATA lv_open_main   TYPE i.
    DATA lv_open_sub    TYPE i.

    SELECT COUNT( * ) FROM ztb_d_mch_fa_upl WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype = @file_status-success
      INTO @lv_done_main.
    SELECT COUNT( * ) FROM ztb_d_mch_fa_upl WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype <> @file_status-success
      INTO @lv_open_main.

    " dùng kết quả vừa merge cho bảng sub (DB chưa commit tại thời điểm này)
    SELECT COUNT( * ) FROM ztb_d_mch_fasupl WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype = @file_status-success
      INTO @lv_done_sub.
    SELECT COUNT( * ) FROM ztb_d_mch_fasupl WITH PRIVILEGED ACCESS
      WHERE uuidfile = @lv_uuidfile AND messagetype <> @file_status-success
      INTO @lv_open_sub.

    LOOP AT lt_sub INTO DATA(ls_chk).
      " các dòng vừa xử lý: DB vẫn đang là chưa-success, bù lại theo kết quả mới
      IF ls_chk-messagetype = file_status-success.
        lv_done_sub += 1.
        lv_open_sub -= 1.
      ENDIF.
    ENDLOOP.

    DATA(lv_new_status) = COND #(
      WHEN lv_open_main = 0 AND lv_open_sub = 0 THEN file_status-completed
      ELSE file_status-inprocess ).

    MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Root
      UPDATE FIELDS ( Status ZcountDone )
      WITH VALUE #( (
        %tky-Uuid  = lv_uuidfile
        %is_draft  = if_abap_behv=>mk-off
        Status     = lv_new_status
        ZcountDone = lv_done_main + lv_done_sub
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

    " Số dòng header trong template Excel (title/desc + R/O + length) trước khi tới dữ liệu.
    " CẦN xác nhận lại đúng theo template thực tế Tool_tạo_mới_và_thay_đổi_tài_sản_hàng_loạt.
    CONSTANTS c_header_rows TYPE i VALUE 4.

    " [+] Template main và template sub-number là 2 FILE RIÊNG, dữ liệu đều nằm ở sheet 1
    " (các sheet sau của file sub chỉ là danh mục tra cứu: Asset class, Cost Center, Department).
    " Loại file do user chọn ở radio "Template Type" trên dialog Upload -> %param-TemplateType,
    " được lưu xuống Root.Templatetype để getExcelData (on save) biết đổ vào _Data hay _DataSub.
    CONSTANTS c_data_sheet_pos TYPE i VALUE 1.
    CONSTANTS:
      BEGIN OF template_type,
        main TYPE c LENGTH 1 VALUE 'M', "Asset List
        sub  TYPE c LENGTH 1 VALUE 'S', "Asset Sub-number List
      END OF template_type.

    " Thứ tự field ở đây PHẢI khớp đúng thứ tự cột A->AC trong sheet "Create_Main asset",
    " vì XCO xlsx map theo VỊ TRÍ CỘT, không phải theo tên header.
    TYPES: BEGIN OF ty_file_upload,
             CompanyCode           TYPE string, "A
             AssetClass            TYPE string, "B
             PostCapitalization    TYPE string, "C
             FixedAssetDescription TYPE string, "D
             AdditionalDescription TYPE string, "E
             BaseUnitIsoCode       TYPE string, "F
             SerialNumber          TYPE string, "G
             OrderDate             TYPE string, "H
             EvalGroup1            TYPE string, "I
             EvalGroup2            TYPE string, "J
             EvalGroup3            TYPE string, "K
             InventoryNumber       TYPE string, "L
             LastInventoryDate     TYPE string, "M
             InventoryNote         TYPE string, "N
             InventoryIsCounted    TYPE string, "O
             CostCenter            TYPE string, "P
             ProfitCenter          TYPE string, "Q
             Plant                 TYPE string, "R
             Room                  TYPE string, "S
             Segment               TYPE string, "T
             AssetLocation         TYPE string, "U
             Supplier              TYPE string, "V
             AssetIsAcquiredUsed   TYPE string, "W
             ManufacturerName      TYPE string, "X
             CapitalizationDate    TYPE string, "Y
             DeactivationDate      TYPE string, "Z
             UsefulLifeYears       TYPE string, "AA
             UsefulLifePeriods     TYPE string, "AB
             DepreciationStartDate TYPE string, "AC
           END OF ty_file_upload.
    TYPES tt_file_upload TYPE STANDARD TABLE OF ty_file_upload WITH EMPTY KEY.

    " [+] Sheet 'Create Sub- Asset' (template Asset Sub-number List): 30 cột A->AD.
    " Khác sheet main: cột A là Sequence, cột C là Asset Number (MasterFixedAsset) thay cho AssetClass.
    TYPES: BEGIN OF ty_file_upload_sub,
             Sequence              TYPE string, "A  Sequence (STT dòng, chỉ để đối chiếu)
             CompanyCode           TYPE string, "B  Company Code
             MasterFixedAsset      TYPE string, "C  Asset Number (tài sản chính)
             PostCapitalization    TYPE string, "D  T/F
             FixedAssetDescription TYPE string, "E
             AdditionalDescription TYPE string, "F
             BaseUnitIsoCode       TYPE string, "G
             SerialNumber          TYPE string, "H
             OrderDate             TYPE string, "I  DD.MM.YYYY
             EvalGroup1            TYPE string, "J
             EvalGroup2            TYPE string, "K
             EvalGroup3            TYPE string, "L
             InventoryNumber       TYPE string, "M
             LastInventoryDate     TYPE string, "N  DD.MM.YYYY
             InventoryNote         TYPE string, "O
             InventoryIsCounted    TYPE string, "P  T/F
             CostCenter            TYPE string, "Q
             ProfitCenter          TYPE string, "R
             Plant                 TYPE string, "S
             Room                  TYPE string, "T
             Segment               TYPE string, "U
             AssetLocation         TYPE string, "V
             Supplier              TYPE string, "W
             AssetIsAcquiredUsed   TYPE string, "X  T/F
             ManufacturerName      TYPE string, "Y
             CapitalizationDate    TYPE string, "Z  DD.MM.YYYY
             DeactivationDate      TYPE string, "AA DD.MM.YYYY
             UsefulLifeYears       TYPE string, "AB
             UsefulLifePeriods     TYPE string, "AC
             DepreciationStartDate TYPE string, "AD DD.MM.YYYY
           END OF ty_file_upload_sub.
    TYPES tt_file_upload_sub TYPE STANDARD TABLE OF ty_file_upload_sub WITH EMPTY KEY.

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

    " ---- helper: convert 'DD.MM.YYYY' text cell -> abap.dats ('YYYYMMDD') ----
    METHODS to_date
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE d.

    " [+] helper: 'X' / 'true' -> 'X', còn lại -> ''
    METHODS to_flag
      IMPORTING iv_text       TYPE string
      RETURNING VALUE(rv_out) TYPE abap_boolean.

    " [+] helper: đọc sheet 1 của template MAIN -> bảng dòng dữ liệu đã bỏ header + dòng trống.
    METHODS read_main_sheet
      IMPORTING iv_filecontent TYPE xstring
      RETURNING VALUE(rt_main) TYPE tt_file_upload.

    " [+] helper: đọc sheet 1 của template SUB-NUMBER -> bảng dòng dữ liệu đã bỏ header + dòng trống.
    METHODS read_sub_sheet
      IMPORTING iv_filecontent TYPE xstring
      RETURNING VALUE(rt_sub)  TYPE tt_file_upload_sub.

    " [+] helper: text -> integer, không parse được -> 0
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
    " TODO: build lại file (log/kết quả) từ dữ liệu hiện có để trả về result
  ENDMETHOD.

  METHOD uploadExcel.
    DATA: lt_mn_root TYPE TABLE FOR CREATE zr_m_mco_fa_upl,
          ls_mn_root LIKE LINE OF lt_mn_root.

    READ TABLE keys ASSIGNING FIELD-SYMBOL(<k>) INDEX 1.
    CHECK sy-subrc = 0.

    IF <k>-%param-FileContent IS INITIAL.
      RETURN.
    ENDIF.

    " [+] loại template từ radio trên dialog; rỗng -> coi là Asset List (tương thích cũ)
    DATA(lv_template_type) = COND #( WHEN <k>-%param-TemplateType IS INITIAL
                                       THEN template_type-main
                                       ELSE <k>-%param-TemplateType ).

    ls_mn_root-Attachment   = <k>-%param-FileContent.
    ls_mn_root-Filename     = <k>-%param-FileName.
    ls_mn_root-Mimetype     = <k>-%param-MimeType.
    ls_mn_root-Templatetype = lv_template_type.

    FINAL(lv_filecontent) = <k>-%param-FileContent.

    " [+] parse đúng sheet theo loại template để đếm số dòng
    DATA(lv_total_lines) = COND i(
      WHEN lv_template_type = template_type-sub THEN lines( read_sub_sheet( lv_filecontent ) )
      ELSE lines( read_main_sheet( lv_filecontent ) ) ).

    IF lv_total_lines > 100.
      APPEND VALUE #( %cid = <k>-%cid
                       %msg = new_message( id       = 'Z_FILE_MSG'      " TODO: đổi thành message class thực tế
                                            number   = '001'            " TODO: đổi thành số message thực tế
                                            severity = if_abap_behv_message=>severity-error ) )
        TO reported-root.
      RETURN.
    ENDIF.

    ls_mn_root-Countline = lv_total_lines.
    APPEND ls_mn_root TO lt_mn_root.

    IF lt_mn_root IS NOT INITIAL.
      MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
        ENTITY Root
        CREATE AUTO FILL CID FIELDS (
                          Status
                          Attachment
                          Mimetype
                          Filename
                          Templatetype
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
                       %msg = new_message( id       = 'Z_FILE_MSG'      " TODO: đổi thành message class thực tế
                                            number   = '002'            " TODO: đổi thành số message thực tế
                                            severity = if_abap_behv_message=>severity-success ) )
        TO reported-root.
    ENDIF.
  ENDMETHOD.

  METHOD setStatusToOpen.
    READ ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
     ENTITY Root
       FIELDS ( Status )
       WITH CORRESPONDING #( keys )
     RESULT DATA(lt_root).

    " Nếu Status đã set thì bỏ qua
    DELETE lt_root WHERE Status IS NOT INITIAL.

    CHECK lt_root IS NOT INITIAL.

    DATA lv_cnt1 TYPE i.
    DATA lv_cnt2 TYPE i.
    DATA lv_next TYPE i.

    SELECT SINGLE MAX( zcount )
      FROM ztb_m_mco_fa_upl
      WHERE createdbyuser = @sy-uname
      INTO @lv_cnt1.

    SELECT SINGLE MAX( zcount )
      FROM ztb_m_mco_fa_d
      WHERE createdbyuser = @sy-uname
      INTO @lv_cnt2.

    lv_next = COND i( WHEN lv_cnt1 >= lv_cnt2 THEN lv_cnt1 + 1 ELSE lv_cnt2 + 1 ).

    MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Root
        UPDATE FIELDS ( Status Zcount )
        WITH VALUE #( FOR ls_root IN lt_root ( %tky   = ls_root-%tky
                                                Status = file_status-open
                                                Zcount = lv_next ) ).
  ENDMETHOD.

  METHOD getExcelData.
    " ── 1. Read parent instance ───────────────────────────────────
    READ ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Root
      ALL FIELDS WITH
      CORRESPONDING #( keys )
      RESULT FINAL(lt_record).

    IF lt_record IS INITIAL.
      RETURN.
    ENDIF.

    FINAL(lv_filecontent) = lt_record[ 1 ]-Attachment.
    CHECK sy-subrc = 0.

    READ TABLE lt_record ASSIGNING FIELD-SYMBOL(<f_root>) INDEX 1.

    " ── 2. [+] Rẽ nhánh theo loại template đã lưu ở Root ───────────
    IF <f_root>-Templatetype = template_type-sub.
      " file Asset Sub-number List -> chỉ đổ vào _DataSub
      DATA(lt_sub) = read_sub_sheet( lv_filecontent ).
    ELSE.
      " file Asset List (hoặc record cũ chưa có Templatetype) -> chỉ đổ vào _Data
      DATA(lt_file) = read_main_sheet( lv_filecontent ).
    ENDIF.

    " ── 3. Build lt_file_c để create Data theo association _Data ───
    DATA lt_file_c TYPE TABLE FOR CREATE zr_m_mco_fa_upl\_Data.
    DATA ls_file_c LIKE LINE OF lt_file_c.
    DATA lv_index TYPE i.

    LOOP AT lt_file INTO DATA(ls_file).
      lv_index = lv_index + 1.

      ls_file_c = VALUE #(
          %tky    = <f_root>-%tky
          %target = VALUE #( (
            %cid                   = |CID_D_{ lv_index }|

            " TODO: template hiện là Mass CREATE - mặc định Type = 'I' (Insert).
            Type                   = 'I'

            CompanyCode            = ls_file-CompanyCode
            AssetClass             = ls_file-AssetClass
            PostCapitalization     = to_flag( ls_file-PostCapitalization )
            FixedAssetDescription  = ls_file-FixedAssetDescription
            AdditionalDescription  = ls_file-AdditionalDescription
            BaseUnitIsoCode        = ls_file-BaseUnitIsoCode
            SerialNumber           = ls_file-SerialNumber
            OrderDate              = to_date( ls_file-OrderDate )
            EvalGroup1             = ls_file-EvalGroup1
            EvalGroup2             = ls_file-EvalGroup2
            EvalGroup3             = ls_file-EvalGroup3
            InventoryNumber        = ls_file-InventoryNumber
            LastInventoryDate      = to_date( ls_file-LastInventoryDate )
            InventoryNote          = ls_file-InventoryNote
            InventoryIsCounted     = to_flag( ls_file-InventoryIsCounted )
            CostCenter             = ls_file-CostCenter
            ProfitCenter           = ls_file-ProfitCenter
            Plant                  = ls_file-Plant
            Room                   = ls_file-Room
            Segment                = ls_file-Segment
            AssetLocation          = ls_file-AssetLocation
            Supplier               = ls_file-Supplier
            AssetIsAcquiredUsed    = to_flag( ls_file-AssetIsAcquiredUsed )
            ManufacturerName       = ls_file-ManufacturerName
            CapitalizationDate     = to_date( ls_file-CapitalizationDate )
            DeactivationDate       = to_date( ls_file-DeactivationDate )
            UsefulLifeYears        = ls_file-UsefulLifeYears
            UsefulLifePeriods      = ls_file-UsefulLifePeriods
            DepreciationStartDate  = to_date( ls_file-DepreciationStartDate )

            Status                 = file_status-open
          ) )
      ).

      APPEND ls_file_c TO lt_file_c.
      CLEAR ls_file_c.
    ENDLOOP.

    " ── 4. Create Data records qua composition _Data ────────────────
    IF lt_file_c IS NOT INITIAL.
      MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
        ENTITY Root
        CREATE BY \_Data
        FIELDS (
          Type
          CompanyCode
          AssetClass
          PostCapitalization
          FixedAssetDescription
          AdditionalDescription
          BaseUnitIsoCode
          SerialNumber
          OrderDate
          EvalGroup1
          EvalGroup2
          EvalGroup3
          InventoryNumber
          LastInventoryDate
          InventoryNote
          InventoryIsCounted
          CostCenter
          ProfitCenter
          Plant
          Room
          Segment
          AssetLocation
          Supplier
          AssetIsAcquiredUsed
          ManufacturerName
          CapitalizationDate
          DeactivationDate
          UsefulLifeYears
          UsefulLifePeriods
          DepreciationStartDate
          Status
        )
        WITH lt_file_c
        MAPPED   DATA(lt_mapped_create)
        REPORTED DATA(lt_mapped_reported)
        FAILED   DATA(lt_failed_create).
    ENDIF.

    " ── 5. [+] File sub-number -> create DataSub qua composition _DataSub ──
    DATA lt_sub_c TYPE TABLE FOR CREATE zr_m_mco_fa_upl\_DataSub.
    DATA ls_sub_c LIKE LINE OF lt_sub_c.
    DATA lv_sub_index TYPE i.

    LOOP AT lt_sub INTO DATA(ls_sub).
      lv_sub_index = lv_sub_index + 1.

      " Sequence lấy từ cột A của template; ô trống/không phải số -> dùng STT dòng
      DATA(lv_sequence) = to_int( ls_sub-Sequence ).
      IF lv_sequence = 0.
        lv_sequence = lv_sub_index.
      ENDIF.

      ls_sub_c = VALUE #(
          %tky    = <f_root>-%tky
          %target = VALUE #( (
            %cid                   = |CID_S_{ lv_sub_index }|

            Type                   = 'I'
            Sequence               = lv_sequence

            CompanyCode            = ls_sub-CompanyCode
            MasterFixedAsset       = ls_sub-MasterFixedAsset
            PostCapitalization     = to_flag( ls_sub-PostCapitalization )
            FixedAssetDescription  = ls_sub-FixedAssetDescription
            AdditionalDescription  = ls_sub-AdditionalDescription
            BaseUnitIsoCode        = ls_sub-BaseUnitIsoCode
            SerialNumber           = ls_sub-SerialNumber
            OrderDate              = to_date( ls_sub-OrderDate )
            EvalGroup1             = ls_sub-EvalGroup1
            EvalGroup2             = ls_sub-EvalGroup2
            EvalGroup3             = ls_sub-EvalGroup3
            InventoryNumber        = ls_sub-InventoryNumber
            LastInventoryDate      = to_date( ls_sub-LastInventoryDate )
            InventoryNote          = ls_sub-InventoryNote
            InventoryIsCounted     = to_flag( ls_sub-InventoryIsCounted )
            CostCenter             = ls_sub-CostCenter
            ProfitCenter           = ls_sub-ProfitCenter
            Plant                  = ls_sub-Plant
            Room                   = ls_sub-Room
            Segment                = ls_sub-Segment
            AssetLocation          = ls_sub-AssetLocation
            Supplier               = ls_sub-Supplier
            AssetIsAcquiredUsed    = to_flag( ls_sub-AssetIsAcquiredUsed )
            ManufacturerName       = ls_sub-ManufacturerName
            CapitalizationDate     = to_date( ls_sub-CapitalizationDate )
            DeactivationDate       = to_date( ls_sub-DeactivationDate )
            UsefulLifeYears        = ls_sub-UsefulLifeYears
            UsefulLifePeriods      = ls_sub-UsefulLifePeriods
            DepreciationStartDate  = to_date( ls_sub-DepreciationStartDate )

            Status                 = file_status-open
          ) )
      ).

      APPEND ls_sub_c TO lt_sub_c.
      CLEAR ls_sub_c.
    ENDLOOP.

    IF lt_sub_c IS NOT INITIAL.
      MODIFY ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
        ENTITY Root
        CREATE BY \_DataSub
        FIELDS (
          Type
          Sequence
          CompanyCode
          MasterFixedAsset
          PostCapitalization
          FixedAssetDescription
          AdditionalDescription
          BaseUnitIsoCode
          SerialNumber
          OrderDate
          EvalGroup1
          EvalGroup2
          EvalGroup3
          InventoryNumber
          LastInventoryDate
          InventoryNote
          InventoryIsCounted
          CostCenter
          ProfitCenter
          Plant
          Room
          Segment
          AssetLocation
          Supplier
          AssetIsAcquiredUsed
          ManufacturerName
          CapitalizationDate
          DeactivationDate
          UsefulLifeYears
          UsefulLifePeriods
          DepreciationStartDate
          Status
        )
        WITH lt_sub_c
        MAPPED   DATA(lt_sub_mapped)
        REPORTED DATA(lt_sub_reported)
        FAILED   DATA(lt_sub_failed).
    ENDIF.
  ENDMETHOD.

  METHOD read_main_sheet.
    DATA lt_main TYPE tt_file_upload.

    CHECK iv_filecontent IS NOT INITIAL.

    FINAL(lo_xlsx) = xco_cp_xlsx=>document->for_file_content(
                       iv_file_content = iv_filecontent
                     )->read_access( ).
    FINAL(lo_worksheet) = lo_xlsx->get_workbook( )->worksheet->at_position( c_data_sheet_pos ).
    FINAL(lo_selection_pattern) = xco_cp_xlsx_selection=>pattern_builder->simple_from_to( )->get_pattern( ).
    FINAL(lo_execute) = lo_worksheet->select( lo_selection_pattern
      )->row_stream(
      )->operation->write_to( REF #( lt_main ) ).

    lo_execute->set_value_transformation(
      xco_cp_xlsx_read_access=>value_transformation->string_value
    )->if_xco_xlsx_ra_operation~execute( ).

    " Bỏ các dòng header (title/desc + R/O + length)
    IF lt_main IS NOT INITIAL.
      DO c_header_rows TIMES.
        DELETE lt_main INDEX 1.
      ENDDO.
    ENDIF.

    DELETE lt_main WHERE CompanyCode IS INITIAL AND AssetClass IS INITIAL.

    rt_main = lt_main.
  ENDMETHOD.

  METHOD read_sub_sheet.
    DATA lt_sub TYPE tt_file_upload_sub.

    CHECK iv_filecontent IS NOT INITIAL.

    FINAL(lo_xlsx) = xco_cp_xlsx=>document->for_file_content(
                       iv_file_content = iv_filecontent
                     )->read_access( ).
    FINAL(lo_worksheet) = lo_xlsx->get_workbook( )->worksheet->at_position( c_data_sheet_pos ).
    FINAL(lo_selection_pattern) = xco_cp_xlsx_selection=>pattern_builder->simple_from_to( )->get_pattern( ).
    FINAL(lo_execute) = lo_worksheet->select( lo_selection_pattern
      )->row_stream(
      )->operation->write_to( REF #( lt_sub ) ).

    lo_execute->set_value_transformation(
      xco_cp_xlsx_read_access=>value_transformation->string_value
    )->if_xco_xlsx_ra_operation~execute( ).

    " Template sub-number cũng có 4 dòng header: nhóm cột / tên cột / R-O / độ dài
    IF lt_sub IS NOT INITIAL.
      DO c_header_rows TIMES.
        DELETE lt_sub INDEX 1.
      ENDDO.
    ENDIF.

    DELETE lt_sub WHERE CompanyCode IS INITIAL AND MasterFixedAsset IS INITIAL.

    rt_sub = lt_sub.
  ENDMETHOD.

  METHOD to_int.
    DATA lv_text TYPE string.
    lv_text = condense( iv_text ).
    CHECK lv_text IS NOT INITIAL.
    TRY.
        rv_out = lv_text.
      CATCH cx_sy_conversion_error.
        rv_out = 0.
    ENDTRY.
  ENDMETHOD.

  METHOD to_flag.
    rv_out = COND #( WHEN iv_text CP 'X*' OR iv_text CP '*true*' THEN 'X' ELSE '' ).
  ENDMETHOD.

  METHOD to_date.
    " chuyển "DD.MM.YYYY" -> abap.dats (YYYYMMDD); rỗng/không đúng format/không phải ngày thật -> initial date
    DATA lt_part TYPE TABLE OF string.
    DATA lv_day   TYPE i.
    DATA lv_month TYPE i.
    DATA lv_year  TYPE i.
    DATA lv_days_in_month TYPE i.
    DATA lv_is_leap TYPE abap_bool.

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

    " ---- validate thuần ABAP, không gọi FM/class bị hạn chế ----
    CHECK lv_year  BETWEEN 1000 AND 9999.
    CHECK lv_month BETWEEN 1 AND 12.
    CHECK lv_day   BETWEEN 1 AND 31.

    lv_is_leap = COND #( WHEN lv_year MOD 4 = 0 AND ( lv_year MOD 100 <> 0 OR lv_year MOD 400 = 0 )
                          THEN abap_true ELSE abap_false ).

    lv_days_in_month = SWITCH #( lv_month
      WHEN 4 OR 6 OR 9 OR 11 THEN 30
      WHEN 2 THEN COND #( WHEN lv_is_leap = abap_true THEN 29 ELSE 28 )
      ELSE 31 ).

    CHECK lv_day <= lv_days_in_month.

    rv_out = |{ lv_year WIDTH = 4 ALIGN = RIGHT PAD = '0' }{ lv_month WIDTH = 2 ALIGN = RIGHT PAD = '0' }{ lv_day WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.

  METHOD get_instance_features.
    " Đọc field Status của các instance root được yêu cầu check feature
    READ ENTITIES OF zr_m_mco_fa_upl IN LOCAL MODE
      ENTITY Root
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_root)
      FAILED failed.

    result = VALUE #( FOR ls_root IN lt_root
      ( %tky    = ls_root-%tky

      %delete = COND #( WHEN ls_root-Status = 'D'
                           THEN if_abap_behv=>fc-o-disabled
                           ELSE if_abap_behv=>fc-o-enabled )

        " Không cho update khi Status = 'D'
        %update = COND #( WHEN ls_root-Status = 'D'
                           THEN if_abap_behv=>fc-o-disabled
                           ELSE if_abap_behv=>fc-o-enabled )

      ) ).
  ENDMETHOD.

ENDCLASS.
