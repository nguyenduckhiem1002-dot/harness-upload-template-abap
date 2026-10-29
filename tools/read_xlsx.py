import sys, zipfile, re, xml.etree.ElementTree as ET
NS = {'m': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main',
      'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'}
z = zipfile.ZipFile(sys.argv[1])
wb = ET.fromstring(z.read('xl/workbook.xml'))
rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
relmap = {r.get('Id'): r.get('Target') for r in rels}
shared = []
if 'xl/sharedStrings.xml' in z.namelist():
    ss = ET.fromstring(z.read('xl/sharedStrings.xml'))
    for si in ss.findall('m:si', NS):
        shared.append(''.join(t.text or '' for t in si.iter('{%s}t' % NS['m'])))
def col2num(c):
    n = 0
    for ch in c:
        n = n * 26 + ord(ch) - 64
    return n
for i, s in enumerate(wb.find('m:sheets', NS), 1):
    rid = s.get('{%s}id' % NS['r'])
    target = relmap[rid]
    path = target if target.startswith('xl/') else 'xl/' + target.lstrip('/')
    ws = ET.fromstring(z.read(path))
    rows = ws.find('m:sheetData', NS)
    print(f"=== Sheet {i}: {s.get('name')!r}  ({path})")
    cnt = 0
    for row in rows.findall('m:row', NS):
        cnt += 1
        if cnt > 10: break
        cells = {}
        for c in row.findall('m:c', NS):
            ref = re.match(r'([A-Z]+)', c.get('r')).group(1)
            v = c.find('m:v', NS)
            t = c.get('t')
            val = None
            if v is not None:
                val = shared[int(v.text)] if t == 's' else v.text
            elif t == 'inlineStr':
                val = ''.join(x.text or '' for x in c.iter('{%s}t' % NS['m']))
            cells[col2num(ref)] = val
        mx = max(cells) if cells else 0
        print(f"R{row.get('r')}: {[cells.get(k) for k in range(1, mx+1)]}")
    print(f"total rows in sheetData: {len(rows.findall('m:row', NS))}")
