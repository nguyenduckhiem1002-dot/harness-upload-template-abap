@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proj.View Manage File Upload SO Schedule Line'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
define root view entity ZC_M_SOSL_UPL
  provider contract transactional_query
  as projection on ZR_M_SOSL_UPL

{
  key Uuid,
      Zcount,
      ZcountDone,
      @ObjectModel.text.element: ['OverallStatusText']
      Status,
      Criticality,
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
      _Data : redirected to composition child ZC_D_SOSL_UPL
}
