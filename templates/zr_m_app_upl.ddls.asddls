@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Root view Manage File Upload {{APP_LABEL}}'
@Metadata.ignorePropagatedAnnotations: true
define root view entity {{ROOT_I}}
  as select from {{ROOT_TBL}}
  // child đầu tiên [1..*]; mỗi child thêm sau là một composition [0..*] riêng
  composition [1..*] of {{CHILD_I}}            as {{CHILD_ASSOC}}
  // composition [0..*] of ZI_D_<APP>_<X2>        as _<Alias2>
  association [0..1] to {{STATUS_VH}}           as _OverallStatus on $projection.Status = _OverallStatus.Status
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
      templatetype  as Templatetype,
      /* Associations */
      {{CHILD_ASSOC}},
      // _<Alias2>,
      _OverallStatus
}
