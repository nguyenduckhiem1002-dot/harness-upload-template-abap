@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Root view Manage File Upload SO Schedule Line'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZR_M_SOSL_UPL
  as select from ztb_m_sosl_upl
  composition [1..*] of ZI_D_SOSL_UPL          as _Data
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
      attachment    as Attachment,
      mimetype      as Mimetype,
      filename      as Filename,
      countline     as Countline,
      createdbyuser as Createdbyuser,
      createddate   as Createddate,
      changedbyuser as Changedbyuser,
      changeddate   as Changeddate,
      /* Associations */
      _Data,
      _OverallStatus
}
