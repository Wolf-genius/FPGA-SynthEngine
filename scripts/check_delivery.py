from pathlib import Path
import hashlib,json,re,shutil,xml.etree.ElementTree as ET
from hdl_tools import ROOT
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
t=json.loads((ROOT/'evidence/test_report.json').read_text());assert t['status']=='PASS'
for n,h in t['input_sha256'].items():assert sha(ROOT/n)==h,('Stale simulation',n)
preserved=json.loads((ROOT/'evidence/source_preservation.json').read_text())
for n,h in preserved['unchanged_files'].items():assert sha(ROOT/n)==h,('Unexpected source change',n)
name='eight_key_instrument_display';pnr=ROOT/'impl/pnr';fs=pnr/(name+'.fs')
if not fs.exists():raise SystemExit('Run Synthesize and Place & Route for THIS project first; no new FS exists.')
log=(pnr/(name+'.log')).read_text(errors='replace')
assert 'Bitstream generation completed' in log and not re.search(r'\bERROR\b',log)
timing=(pnr/(name+'_tr_content.html')).read_text(errors='replace')
violations={k:int(re.search('Numbers of '+k+r' Violated Endpoints</td>\s*<td>(\d+)',timing).group(1)) for k in ['Setup','Hold']}
assert violations=={'Setup':0,'Hold':0},violations
pins=(pnr/(name+'.pin.html')).read_text(errors='replace')
cst=(ROOT/'constraints/eight_key_instrument_display.cst').read_text()
mapping=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',cst))
assert len(mapping)==26 and len(set(mapping.values()))==26
for port,pin in mapping.items():assert re.search(r'<td class="label">'+re.escape(port)+r'</td>\s*<td>-</td>\s*<td>'+pin+r'/\d+</td>',pins),(port,pin)
formal=(ROOT/'rtl_instrument.f').read_text().splitlines()
listed=[x.attrib['path'] for x in ET.parse(ROOT/(name+'.gprj')).findall('.//File') if x.attrib['type']=='file.verilog']
assert formal==listed
for f in formal+['constraints/eight_key_instrument_display.cst','constraints/eight_key_full.sdc']:
 assert (ROOT/f).stat().st_mtime<=fs.stat().st_mtime,('Source newer than FS',f)
resources={};usage=(pnr/(name+'.rpt.txt')).read_text(errors='replace')
for key in ['Logic','Register','BSRAM','DSP','CLS']:
 m=re.search(r'^\s*'+key+r'\s*\|\s*([\d.]+)/(\d+)',usage,re.M)
 if m:
  used,total=map(float,m.groups());assert used<=total;resources[key]={'used':used,'available':int(total)}
download=ROOT/'download'/(ROOT.name+'.fs');download.parent.mkdir(exist_ok=True)
shutil.copy2(fs,download);assert sha(download)==sha(fs)
report={'status':'PASS','hardware_verified':False,'download':str(download),'bitstream_sha256':sha(fs),
 'test_report_sha256':sha(ROOT/'evidence/test_report.json'),'violations':violations,'resources':resources,
 'pin_mapping':mapping,'warnings':sorted(set(re.findall(r'WARN\s+\((\w+)\)',log))),
 'source_sha256':{f.relative_to(ROOT).as_posix():sha(f) for d in ['rtl','tables','constraints','songs'] for f in (ROOT/d).rglob('*') if f.is_file()}}
(ROOT/'evidence/delivery_report.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS new PnR, internal timing, pins, source checks and FS:',download)
