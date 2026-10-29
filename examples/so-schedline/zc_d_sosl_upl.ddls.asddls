@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proj.View Data Upload SO Schedule Line'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
define view entity ZC_D_SOSL_UPL
  as projection on ZI_D_SOSL_UPL
{
  key Uuid,
  key Uuidfile,
      Status,
      Type,
      Sequence,
      SalesOrder,
      SalesOrderItem,
      ScheduleLine,
      DeliveryDate,
      OrderQuantity,
      ScheduleLineResult,
      OrderQuantityUnit,
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
      _File : redirected to parent ZC_M_SOSL_UPL
}
