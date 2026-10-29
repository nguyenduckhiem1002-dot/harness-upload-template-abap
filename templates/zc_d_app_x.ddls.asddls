@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proj.View Data Upload {{CHILD_LABEL}}'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
define view entity {{CHILD_C}}
  as projection on {{CHILD_I}}
{
  key Uuid,
  key Uuidfile,
      Status,
      Type,
      Sequence,

      // ---------- {{BUSINESS_FIELDS}} ----------
      // CompanyCode,
      // AssetClass,
      // ...

      // ---------- {{RESULT_FIELDS}} ----------
      // FixedAsset,
      // MasterFixedAsset,

      @ObjectModel.text.element: ['OverallStatusText']
      Messagetype,
      Criticality,
      @EndUserText.label: 'Status'
      @Semantics.text: true
      _OverallStatus.description as OverallStatusText,
      Message,
      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LocalLastChangedAt,
      LastChangedAt,
      /* Associations */
      _File : redirected to parent {{ROOT_C}}
}
