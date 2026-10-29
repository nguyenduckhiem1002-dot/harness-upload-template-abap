@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Root view Manage File Upload'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZR_M_MCO_FA_UPL
  as select from ztb_m_mco_fa_upl
  composition [1..*] of ZI_D_MCH_FA_UPL        as _Data
  composition [0..*] of ZI_D_MCH_FASUPL        as _DataSub
  association [0..1] to zi_req_sta_crud_poc_vh as _OverallStatus on $projection.Status = _OverallStatus.Status
{
  key uuid          as Uuid,
      zcount        as Zcount,
      zcount_done   as ZcountDone,
      status        as Status,
      case status
      when '' then 0
      when 'P' then 2
      when 'D' then 3
      else 0
      end           as Criticality,
      templatetype  as Templatetype,
      attachment    as Attachment,
      mimetype      as Mimetype,
      filename      as Filename,
      countline     as Countline,
      createdbyuser as Createdbyuser,
      createddate   as Createddate,
      changedbyuser as Changedbyuser,
      changeddate   as Changeddate,
      _Data, // Make association public,
      _DataSub,
      _OverallStatus
}
