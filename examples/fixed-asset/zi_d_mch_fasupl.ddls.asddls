@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Intface.View Data Upload Asset Sub-number'
@Metadata.ignorePropagatedAnnotations: true
define view entity ZI_D_MCH_FASUPL
  as select from ztb_d_mch_fasupl
  association        to parent ZR_M_MCO_FA_UPL as _File          on $projection.Uuidfile = _File.Uuid
  association [0..1] to zi_req_sta_crud_poc_vh as _OverallStatus on $projection.Messagetype = _OverallStatus.Status

{
  key uuid                    as Uuid,
  key uuidfile                as Uuidfile,
      status                  as Status,
      type                    as Type,
      sequence                as Sequence,
      company_code            as CompanyCode,
      master_fixed_asset      as MasterFixedAsset,
      post_capitalization     as PostCapitalization,
      fixed_asset_description as FixedAssetDescription,
      additional_description  as AdditionalDescription,
      base_unit_iso_code      as BaseUnitIsoCode,
      serial_number           as SerialNumber,
      order_date              as OrderDate,
      eval_group_1            as EvalGroup1,
      eval_group_2            as EvalGroup2,
      eval_group_3            as EvalGroup3,
      inventory_number        as InventoryNumber,
      last_inventory_date     as LastInventoryDate,
      inventory_note          as InventoryNote,
      inventory_is_counted    as InventoryIsCounted,
      cost_center             as CostCenter,
      profit_center           as ProfitCenter,
      plant                   as Plant,
      room                    as Room,
      segment                 as Segment,
      asset_location          as AssetLocation,
      supplier                as Supplier,
      asset_is_acquired_used  as AssetIsAcquiredUsed,
      manufacturer_name       as ManufacturerName,
      capitalization_date     as CapitalizationDate,
      deactivation_date       as DeactivationDate,
      useful_life_years       as UsefulLifeYears,
      useful_life_periods     as UsefulLifePeriods,
      depreciation_start_date as DepreciationStartDate,
      fixed_asset             as FixedAsset,
      fixed_asset_subnumber   as FixedAssetSubnumber,
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
      _File, // Make association public
      _OverallStatus
}
