# Ví dụ chuẩn: Mass Create Fixed Asset

App upload có **1 Root + 2 child**, mỗi child là một template Excel riêng:

| Child | Template Type | Table | View | Alias | API |
|---|---|---|---|---|---|
| Asset List | `M` | `ztb_d_mch_fa_upl` (draft `ztb_d_mch_fa_d`) | `ZI_D_MCH_FA_UPL` / `ZC_D_MCH_FA_UPL` | `Data` / `_Data` | `zcl_fa_master_asset_upload=>create_assets` -> `SAP__self.CreateMasterFixedAsset` |
| Asset Sub-number List | `S` | `ztb_d_mch_fasupl` (draft `ztb_d_fasup_d`) | `ZI_D_MCH_FASUPL` / `ZC_D_MCH_FASUPL` | `DataSub` / `_DataSub` | `zcl_fa_sub_asset_upload=>create_subnumbers` -> `SAP__self.CreateFixedAsset` |

API đích: `API_FIXEDASSET` OData V4, entity set
`/sap/opu/odata4/sap/api_fixedasset/srvd_a2x/sap/fixedasset/0001/FixedAsset`.

## File trong thư mục này

| File | Vai trò |
|---|---|
| `ztb_m_mco_fa_upl.tabl.asstruct` | table Root (bản thật trên hệ thống) |
| `ztb_d_mch_fa_upl.tabl.asstruct` | table child 1 (dùng data element chuẩn: `bukrs`, `kostl`, `prctr`, `werks_d`, `fb_segment`, `lifnr`, `anln1`) |
| `ztb_d_mch_fasupl.tabl.asstruct` | table child 2, thêm `sequence`, `master_fixed_asset : anln1`, `fixed_asset_subnumber : anln2` |
| `zcl_call_api.clas.abap` | HTTP wrapper dùng chung: URL `<tenant>-api.<domain>`, Basic auth từ `ztb_api_auth`, CSRF preflight, `code` = HTTP status (0 = lỗi transport) |
| `zr_m_mco_fa_upl.ddls.asddls` | root view, 2 composition |
| `zc_m_mco_fa_upl.ddls.asddls` | root projection, 2 redirected |
| `zc_m_mco_fa_upl.ddlx.asddlxs` | root MDE, 3 facet (Header, Asset List, Asset Sub-number List) |
| `zr_m_mco_fa_upl.bdef.asbdef` | BDEF base: Root + Data + DataSub |
| `zc_m_mco_fa_upl.bdef.asbdef` | BDEF projection |
| `zabs_file_crud_poc_n.ddls.asddls` | abstract entity uploadExcel có `templateType` |
| `zi_d_mch_fasupl.ddls.asddls`, `zc_d_mch_fasupl.ddls.asddls`, `zc_d_mch_fasupl.ddlx.asddlxs` | child 2 views + MDE (child 1 tương tự, thay MasterFixedAsset bằng AssetClass, không có Sequence) |
| `zbp_r_m_mco_fa_upl.clas.locals_imp.abap` | Local Types đầy đủ: `lhc_data`, `lhc_datasub`, `lhc_Root` (2 sheet reader) |
| `zcl_fa_sub_asset_upload.clas.abap` | API class child 2. Child 1 `zcl_fa_master_asset_upload` cùng cấu trúc: input có `asset_class` thay `master_fixed_asset`, payload gửi `AssetClass`, luôn gửi `_Ledger`, action `CreateMasterFixedAsset`, method `create_assets`, result có `fixed_asset` + `master_fixed_asset` |

Payload tối thiểu đã test OK cho sub-number (từ curl thật, không kèm `_Ledger`):

```json
{ "CompanyCode": "6710", "MasterFixedAsset": "10000000",
  "_General": { "FixedAssetDescription": "...", "AssetAdditionalDescription": "..." },
  "_AccountAssignment": { "CostCenter": "..." } }
```

Những điểm còn TODO trong ví dụ (phải chốt trước khi lên production):
`Z_FILE_MSG` message class, ledger config hardcode (0L/01/9INE, 0L/15/9INE, 2L/32/LINE), `downloadFile` rỗng, giá trị radio Template Type phải trả `'M'`/`'S'`.
