@EndUserText.label: 'Upload file action'
@Metadata.allowExtensions: true
define abstract entity {{ABS_UPLOAD}}
{
  mimeType      : abap.string(0);
  fileName      : abap.string(0);
  fileContent   : abap.rawstring(0);
  fileExtension : abap.string(0);
  @EndUserText.label: 'Template Type'
  templateType  : abap.char(1); // 'M' = main template (default when empty); add others, e.g. 'S'
}
