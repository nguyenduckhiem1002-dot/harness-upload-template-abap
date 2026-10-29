@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Intface.View Data Upload {{CHILD_LABEL}}'
@Metadata.ignorePropagatedAnnotations: true
define view entity {{CHILD_I}}
  as select from {{CHILD_TBL}}
  association        to parent {{ROOT_I}}  as _File          on $projection.Uuidfile = _File.Uuid
  association [0..1] to {{STATUS_VH}}      as _OverallStatus on $projection.Messagetype = _OverallStatus.Status

{
  key uuid                    as Uuid,
  key uuidfile                as Uuidfile,
      status                  as Status,
      type                    as Type,
      sequence                as Sequence,

      // ---------- {{BUSINESS_FIELDS}} (snake_case -> CamelCase, Excel column order) ----------
      // company_code            as CompanyCode,
      // asset_class             as AssetClass,
      // post_capitalization     as PostCapitalization,
      // fixed_asset_description as FixedAssetDescription,
      // ...

      // ---------- {{RESULT_FIELDS}} ----------
      // fixed_asset             as FixedAsset,
      // master_fixed_asset      as MasterFixedAsset,

      messagetype             as Messagetype,
      case messagetype when '' then 0
      when 'E' then 1
      when 'S' then 3
      else 0
      end                     as Criticality,
      message                 as Message,
      created_by              as CreatedBy,
      created_at              as CreatedAt,
      last_changed_by         as LastChangedBy,
      local_last_changed_at   as LocalLastChangedAt,
      last_changed_at         as LastChangedAt,
      _File,
      _OverallStatus
}
