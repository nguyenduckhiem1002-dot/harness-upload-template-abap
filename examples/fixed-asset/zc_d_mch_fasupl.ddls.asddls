@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proj.View Data Upload Asset Sub-number'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
define view entity ZC_D_MCH_FASUPL
  as projection on ZI_D_MCH_FASUPL
{
  key Uuid,
  key Uuidfile,
      Status,
      Type,
      Sequence,
      CompanyCode,
      MasterFixedAsset,
      PostCapitalization,
      FixedAssetDescription,
      AdditionalDescription,
      BaseUnitIsoCode,
      SerialNumber,
      OrderDate,
      EvalGroup1,
      EvalGroup2,
      EvalGroup3,
      InventoryNumber,
      LastInventoryDate,
      InventoryNote,
      InventoryIsCounted,
      CostCenter,
      ProfitCenter,
      Plant,
      Room,
      Segment,
      AssetLocation,
      Supplier,
      AssetIsAcquiredUsed,
      ManufacturerName,
      CapitalizationDate,
      DeactivationDate,
      UsefulLifeYears,
      UsefulLifePeriods,
      DepreciationStartDate,
      FixedAsset,
      FixedAssetSubnumber,
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
      _File : redirected to parent ZC_M_MCO_FA_UPL
}
