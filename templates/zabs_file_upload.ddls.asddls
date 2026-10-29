@EndUserText.label: 'Upload file action'
@Metadata.allowExtensions: true
define abstract entity {{ABS_UPLOAD}}
{
  mimeType      : abap.string(0);
  fileName      : abap.string(0);
  fileContent   : abap.rawstring(0);
  fileExtension : abap.string(0);
  @EndUserText.label: 'Template Type'
  templateType  : abap.char(1); // 1 ký tự; 'M' = template chính (mặc định khi rỗng), các loại khác khai báo thêm: 'S' = ...
}
