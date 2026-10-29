@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Intface.View Data Upload SO Schedule Line'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_D_SOSL_UPL
  as select from ztb_d_sosl_upl
  association        to parent ZR_M_SOSL_UPL    as _File          on $projection.Uuidfile = _File.Uuid
  association [0..1] to zi_req_sta_crud_poc_vh as _OverallStatus on $projection.Messagetype = _OverallStatus.Status

{
  key uuid                  as Uuid,
  key uuidfile              as Uuidfile,
      status                as Status,
      type                  as Type,
      sequence              as Sequence,
      sales_order           as SalesOrder,
      sales_order_item      as SalesOrderItem,
      schedule_line         as ScheduleLine,
      delivery_date         as DeliveryDate,
      @Semantics.quantity.unitOfMeasure: 'OrderQuantityUnit'
      order_quantity        as OrderQuantity,
      schedule_line_result  as ScheduleLineResult,
      @Semantics.unitOfMeasure: true
      order_quantity_unit   as OrderQuantityUnit,
      messagetype           as Messagetype,
      case messagetype when '' then 0
      when 'E' then 1
      when 'S' then 3
      else 0
      end                   as Criticality,
      message               as Message,
      created_by            as CreatedBy,
      created_at            as CreatedAt,
      last_changed_by       as LastChangedBy,
      local_last_changed_at as LocalLastChangedAt,
      last_changed_at       as LastChangedAt,
      _File,
      _OverallStatus
}
