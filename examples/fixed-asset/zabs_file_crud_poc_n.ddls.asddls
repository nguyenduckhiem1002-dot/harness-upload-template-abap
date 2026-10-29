@EndUserText.label: 'Upload file action'
@Metadata.allowExtensions: true
define abstract entity zabs_file_crud_poc_n
{
  mimeType      : abap.string(0);
  fileName      : abap.string(0);
  fileContent   : abap.rawstring(0);
  fileExtension : abap.string(0);
  @EndUserText.label: 'Template Type'
  templateType  : abap.char(1); // 'M' = Asset List, 'S' = Asset Sub-number List
}
