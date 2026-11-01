from pathlib import Path
import json,hashlib,xml.etree.ElementTree as ET,re
from hdl_tools import ROOT,run
from vibrato_reference import generate,analyze
generate(ROOT)
report={'status':'RUNNING','Gowin_synthesis':'NOT_RUN','PnR':'NOT_RUN','hardware_verified':False,'tests':{},'input_sha256':{}}
for d in ['rtl','tb','scripts','tables','constraints']:
 for p in (ROOT/d).rglob('*'):
  if p.is_file() and p.suffix in ['.v','.sv','.py','.hex','.cst','.sdc']:report['input_sha256'][p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in (ROOT/'sim').iterdir():
 if p.is_file() and (p.suffix=='.hex' or p.name.endswith('_count.txt')):report['input_sha256'][p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
def save():(ROOT/'evidence/test_report.json').write_text(json.dumps(report,indent=2)+'\n')
try:
 save()
 formal=(ROOT/'rtl_instrument.f').read_text().splitlines()
 listed=[x.attrib['path'] for x in ET.parse(ROOT/'eight_key_instrument_display.gprj').findall('.//File') if x.attrib['type']=='file.verilog']
 assert formal==listed and len(set(formal))==len(formal)
 report['tests']['project']={'status':'PASS','formal_modules':len(formal)}
 report['tests']['press_advance']=run('press_advance','press_advance_tb',['rtl/teaching/teach_ctrl.v','tb/press_advance_tb.sv']);save()
 base=['rtl/bluetooth/'+n+'.v' for n in ['uart_rx','uart_tx','score_command_parser','score_reply_uart','download_score_store']]+['rtl/teaching/teach_ctrl.v','rtl/teaching/led_driver.v','rtl/control/bluetooth_teach_control.v']
 report['tests']['vibrato_unit']=run('vibrato_unit','audio_vibrato_tb',['rtl/audio/audio_vibrato.v','tb/audio_vibrato_tb.sv']);save()
 report['tests']['vibrato_pitch_analysis']=analyze(ROOT);save()
 report['tests']['vibrato_commands']=run('vibrato_commands','vibrato_commands_tb',base+['tb/vibrato_commands_tb.sv']);save()
 fx_expected=['PONG','VIBRATO OFF','OK VIBON','VIBRATO ON','STATUS EMPTY','OK VIBOFF','VIBRATO OFF',
 'OK BEGIN','OK VIBON','OK NOTE','VIBRATO ON','OK VIBOFF','OK END','OK TEACH','OK VIBON','VIBRATO ON',
 'OK VIBOFF','VIBRATO OFF','DONE','STATUS READY','OK TEACH','OK VIBON','OK STOP','VIBRATO ON','OK VIBOFF',
 'ERR FORMAT','ERR FORMAT','ERR FORMAT','VIBRATO OFF','STATUS EMPTY']
 actual=(ROOT/'sim/vibrato_uart.txt').read_bytes()
 assert actual==(''.join(x+'\r\n' for x in fx_expected)).encode(),actual
 report['tests']['vibrato_uart_decode']={'status':'PASS','responses':len(fx_expected),'bytes':len(actual)};save()
 report['tests']['restart_completion_race']=run('restart_done','restart_done_tb',['rtl/bluetooth/download_score_store.v','tb/restart_done_tb.sv']);save()
 report['tests']['download_teach']=run('teach','download_teach_tb',base+['tb/download_teach_tb.sv']);save()
 expected=['PONG','STATUS EMPTY','ERR STATE','ERR FORMAT','ERR FORMAT','ERR FORMAT','OK BEGIN','ERR STATE','OK NOTE','ERR CRC',
 'OK BEGIN']+['OK NOTE']*7+['OK END','OK TEACH','STATUS TEACH','ERR STATE','OK STOP','OK TEACH','DONE','STATUS READY',
 'OK TEACH','OK STOP','OK BEGIN']+['OK NOTE']*256+['OK END','OK TEACH','DONE','STATUS READY','OK TEACH','ERR STATE','OK BEGIN','OK NOTE','OK STOP','STATUS EMPTY']
 actual=(ROOT/'sim/teach_uart.txt').read_bytes()
 assert actual==(''.join(x+'\r\n' for x in expected)).encode(),(actual,expected)
 report['tests']['independent_tx_decode']={'status':'PASS','responses':len(expected),'bytes':len(actual)}
 report['tests']['real_hardware_timing']=run('real_timing','real_timing_tb',base+['tb/real_timing_tb.sv']);save()
 expected_real=['PONG','OK BEGIN','OK NOTE','OK NOTE','OK NOTE','OK END','OK TEACH','DONE']
 assert (ROOT/'sim/real_uart.txt').read_bytes()==(''.join(x+'\r\n' for x in expected_real)).encode()
 report['tests']['full_top']=run('full_top','full_teach_top_tb',formal+['tb/full_teach_top_tb.sv']);save()
 expected_top=['PONG','VIBRATO OFF','OK VIBON','VIBRATO ON','OK VIBOFF','VIBRATO OFF','OK VIBON','OK VIBOFF',
 'OK BEGIN']+['OK NOTE']*4+['OK END','OK TEACH','OK VIBON','VIBRATO ON','DONE','OK VIBOFF','STATUS READY',
 'OK TEACH','OK STOP','OK TEACH','STATUS EMPTY','ERR STATE']
 assert (ROOT/'sim/full_uart.txt').read_bytes()==(''.join(x+'\r\n' for x in expected_top)).encode()
 report['tests']['full_top_uart_decode']={'status':'PASS','responses':len(expected_top)};save()
 for n,h in report['input_sha256'].items():assert hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h,n
 report['status']='PASS';save()
except Exception as e:
 report['status']='FAIL';report['error']=repr(e);save();raise
