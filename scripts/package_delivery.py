from pathlib import Path
import json,hashlib,zipfile
from hdl_tools import ROOT
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
t=json.loads((ROOT/'evidence/test_report.json').read_text());assert t['status']=='PASS'
for n,h in t['input_sha256'].items():assert sha(ROOT/n)==h,n
d=json.loads((ROOT/'evidence/delivery_report.json').read_text());built=d['status']=='PASS'
if built:
 assert sha(ROOT/'evidence/test_report.json')==d['test_report_sha256']
 assert sha(Path(d['download']))==d['bitstream_sha256']
 for n,h in d['source_sha256'].items():assert sha(ROOT/n)==h,n
else:assert d['status']=='NOT_BUILT'
files=[]
for p in ROOT.rglob('*'):
 if not p.is_file():continue
 rel=p.relative_to(ROOT)
 if '__pycache__' in rel.parts or p.name=='SHA256SUMS.json' or p.name.endswith('.gprj.user'):continue
 if rel.parts[0]=='sim' and not (p.suffix=='.hex' or p.name.endswith('_count.txt')):continue
 if rel.parts[0]=='impl':
  if len(rel.parts)==2 and p.suffix=='.json':pass
  elif built and len(rel.parts)>2 and rel.parts[1]=='pnr' and p.suffix in ['.fs','.html','.txt','.log','.timing_paths','.do','.cfg']:pass
  else:continue
 if p.suffix in ['.vvp','.vcd','.pyc','.p','.pr','.db','.vg','.bin','.binx']:continue
 if p.suffix=='.fs' and not built:continue
 files.append(p)
manifest={f.relative_to(ROOT).as_posix():sha(f) for f in sorted(files)}
(ROOT/'SHA256SUMS.json').write_text(json.dumps(manifest,indent=2)+'\n');files.append(ROOT/'SHA256SUMS.json')
z=ROOT.with_suffix('.zip')
with zipfile.ZipFile(z,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as out:
 for f in sorted(files):out.write(f,Path(ROOT.name)/f.relative_to(ROOT))
with zipfile.ZipFile(z) as inp:
 assert inp.testzip() is None
 assert len(inp.namelist())==len(set(inp.namelist()))
 for n,h in manifest.items():assert hashlib.sha256(inp.read(ROOT.name+'/'+n)).hexdigest()==h,n
print('PASS ZIP',z,'bytes',z.stat().st_size,'files',len(files),'new_FS_included',built)
