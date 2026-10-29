"=====================================================================
" Shared HTTP wrapper (dùng chung mọi app upload, KHÔNG sinh lại từng app).
" - URL = https://<tenant>-api.<domain><iv_endpoint>, path thực = iv_uri
" - Basic auth đọc từ ztb_api_auth (1 dòng cấu hình)
" - Non-GET: GET preflight lấy x-csrf-token (+ ETag/If-Match cho PATCH/PUT/DELETE)
" - Kết quả: body text; HTTP status ở CLASS-DATA code (0 = lỗi transport/local)
"=====================================================================
CLASS zcl_call_api DEFINITION
  PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-DATA code TYPE i.
    CLASS-DATA reason TYPE string.
    " Separate from HTTP outcome: a write may already have succeeded.
    CLASS-DATA cleanup_error TYPE string.
    CLASS-METHODS call_api
      IMPORTING
                iv_body          TYPE string
                iv_contentType   TYPE string OPTIONAL
                iv_filter        TYPE string OPTIONAL
                iv_uri           TYPE string OPTIONAL
                iv_endpoint      TYPE string
                iv_actualUrl     TYPE string OPTIONAL
                iv_apiName       TYPE string OPTIONAL
                iv_method        TYPE string
      RETURNING VALUE(rv_result) TYPE string.
ENDCLASS.



CLASS ZCL_CALL_API IMPLEMENTATION.


  METHOD call_api.
    CLEAR: code, reason, cleanup_error, rv_result.

    DATA lv_http_method TYPE if_web_http_client=>method.
    DATA(lv_method) = to_upper( iv_method ).
    CASE lv_method.
      WHEN 'GET'.
        lv_http_method = if_web_http_client=>get.
      WHEN 'POST'.
        lv_http_method = if_web_http_client=>post.
      WHEN 'PUT'.
        lv_http_method = if_web_http_client=>put.
      WHEN 'PATCH'.
        lv_http_method = if_web_http_client=>patch.
      WHEN 'DELETE'.
        lv_http_method = if_web_http_client=>delete.
      WHEN OTHERS.
        reason = |Unsupported HTTP method: { iv_method }|.
        rv_result = reason.
        RETURN.
    ENDCASE.

    DATA lo_http_client TYPE REF TO if_web_http_client.
    DATA lo_response TYPE REF TO if_web_http_response.
    DATA lv_suffix TYPE string.

    TRY.
        " Preserve existing tenant URL convention and routing headers.
        DATA(lv_host) = cl_abap_context_info=>get_system_url( ).
        SPLIT lv_host AT '.' INTO lv_host lv_suffix.
        lv_host = |{ lv_host }-api.{ lv_suffix }|.
        DATA(lv_url) = |https://{ lv_host }{ iv_endpoint }|.

        " Existing configuration assumes exactly one applicable auth row.
        SELECT SINGLE api_user, api_password
          FROM ztb_api_auth
          INTO @DATA(ls_auth).
        IF sy-subrc <> 0.
          reason = `No API authentication configuration found`.
          rv_result = reason.
          RETURN. " No HTTP client has been created yet.
        ENDIF.

        DATA(lo_destination) = cl_http_destination_provider=>create_by_url(
          i_url = lv_url ).
        lo_http_client = cl_web_http_client_manager=>create_by_http_destination(
          i_destination = lo_destination ).
        lo_http_client->accept_cookies( i_allow = abap_true ).
        DATA(lo_request) = lo_http_client->get_http_request( ).

        lo_request->set_header_fields( VALUE #(
          ( name = 'DataServiceVersion' value = '2.0' )
          ( name = 'config_authType' value = 'Basic' )
          ( name = 'Accept' value = 'application/json' ) ) ).
        IF iv_actualUrl IS NOT INITIAL.
          lo_request->set_header_field(
            i_name = 'config_actualUrl' i_value = iv_actualUrl ).
        ENDIF.
        IF iv_apiName IS NOT INITIAL.
          lo_request->set_header_field(
            i_name = 'config_apiName' i_value = iv_apiName ).
        ENDIF.



        " Retained for compatibility with the existing routing setup.
        lo_request->set_header_field(
          i_name = 'username' i_value = CONV string( ls_auth-api_user ) ).
        lo_request->set_header_field(
          i_name = 'password' i_value = CONV string( ls_auth-api_password ) ).
        lo_request->set_authorization_basic(
          i_username = CONV string( ls_auth-api_user )
          i_password = CONV string( ls_auth-api_password ) ).
        lo_request->set_version(
          version = if_web_http_request=>co_protocol_version_1_1 ).
        lo_request->set_content_type( COND string(
          WHEN iv_contentType IS NOT INITIAL THEN iv_contentType
          ELSE `application/json` ) ).

        DATA(lv_send_request) = abap_true.
        IF lv_method <> 'GET'.
          lo_request->set_header_field(
            i_name = 'x-csrf-token' i_value = 'fetch' ).
          DATA(lo_preflight) = lo_http_client->execute(
            i_method = if_web_http_client=>get ).
          DATA(ls_preflight_status) = lo_preflight->get_status( ).

          IF ls_preflight_status-code < 200 OR ls_preflight_status-code >= 300.
            " Preserve the actual preflight error, including 404 for text upsert.
            lo_response = lo_preflight.
            lv_send_request = abap_false.
          ELSE.
            DATA(lv_token) = lo_preflight->get_header_field(
              i_name = 'x-csrf-token' ).
            lo_request->set_header_field(
              i_name = 'x-csrf-token' i_value = lv_token ).
            " The client manages response cookies; do not send Set-Cookie.

            IF lv_method = 'PATCH' OR lv_method = 'PUT' OR lv_method = 'DELETE'.
              DATA(lv_etag) = lo_preflight->get_header_field( i_name = 'ETag' ).
              IF lv_etag IS INITIAL.
                DATA(lv_preflight_body) = lo_preflight->get_text( ).
                FIND REGEX '"@odata\.etag"\s*:\s*"((?:[^"\\]|\\.)*)"'
                  IN lv_preflight_body SUBMATCHES lv_etag.
                IF sy-subrc = 0.
                  REPLACE ALL OCCURRENCES OF '\"' IN lv_etag WITH '"'.
                ENDIF.
              ENDIF.
              IF lv_etag IS NOT INITIAL.
                lo_request->set_header_field(
                  i_name = 'If-Match' i_value = lv_etag ).
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.

        lo_request->set_uri_path(
  EXPORTING
    i_uri_path = iv_uri
*            multivalue = 0
*          RECEIVING
*            r_value    =
).
*        CATCH cx_web_message_error.

        IF lv_send_request = abap_true.
          lo_request->set_text( iv_body ).
          IF iv_filter IS NOT INITIAL.
            lo_request->set_form_field( i_name = '$filter' i_value = iv_filter ).
          ENDIF.
          lo_response = lo_http_client->execute( i_method = lv_http_method ).
        ENDIF.

        DATA(ls_status) = lo_response->get_status( ).
        code = ls_status-code.
        reason = ls_status-reason.
        rv_result = lo_response->get_text( ).
        IF rv_result IS INITIAL AND ( code < 200 OR code >= 300 ).
          rv_result = |HTTP { code }: { reason }|.
        ENDIF.

      CATCH cx_root INTO DATA(lx_error).
        " Compatibility boundary: callers use code/body rather than exceptions.
        " Zero means a local/transport failure, not an HTTP status.
        code = 0.
        reason = lx_error->get_text( ).
        rv_result = reason.
    ENDTRY.

    " Runs after success and every caught exception. No RETURN after creation.
    IF lo_http_client IS BOUND.
      TRY.
          lo_http_client->close( ).
        CATCH cx_web_http_client_error INTO DATA(lx_close).
          cleanup_error = lx_close->get_text( ).
          " Do not misreport an already successful remote write as failed.
          reason = |{ reason }; HTTP client close failed: { cleanup_error }|.
      ENDTRY.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
