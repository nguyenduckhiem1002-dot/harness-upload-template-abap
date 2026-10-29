@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Proj.View Mangae File Upload'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true
define root view entity ZC_M_MCO_FA_UPL
  provider contract transactional_query
  as projection on ZR_M_MCO_FA_UPL

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
      _Data    : redirected to composition child ZC_D_MCH_FA_UPL,
      _DataSub : redirected to composition child ZC_D_MCH_FASUPL
}
