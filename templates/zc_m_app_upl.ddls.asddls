@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proj.View Manage File Upload {{APP_LABEL}}'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
define root view entity {{ROOT_C}}
  provider contract transactional_query
  as projection on {{ROOT_I}}

{
  key Uuid,
      Zcount,
      ZcountDone,
      @ObjectModel.text.element: ['OverallStatusText']
      Status,
      Criticality,
      Templatetype,
      @Semantics.largeObject: {
        mimeType: 'Mimetype',
        fileName: 'Filename',
        contentDispositionPreference: #ATTACHMENT
      }
      Attachment,
      @Semantics.mimeType: true
      @EndUserText.label: 'Status'
      @Semantics.text: true
      _OverallStatus.description as OverallStatusText,
      Mimetype,
      Filename,
      Countline,
      Createdbyuser,
      Createddate,
      Changedbyuser,
      Changeddate,
      /* Associations */
      {{CHILD_ASSOC}} : redirected to composition child {{CHILD_C}}
      // , _<Alias2> : redirected to composition child ZC_D_<APP>_<X2>
}
