"""Fresh Gowin synthesis-only projects. No pins, PnR, bitstream or download."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse, hashlib, json, subprocess, sys

sys.stdout.reconfigure(encoding='utf-8')
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--gw-sh',default='C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe')
args=p.parse_args()
out=root/'sim_build/pressure_keys_synthesis'/('verified_'+datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir(parents=True)
sources=[root/p.strip() for p in (root/'rtl/input/pressure_keys.f').read_text().splitlines() if p.strip()]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
hashes=lambda:{p.relative_to(root).as_posix():sha(p) for p in sources}
m=dict(status='RUNNING',input_sha256=hashes(),started_at=datetime.now(timezone.utc).isoformat(),
       scope='Synthesis only for B input; no CST, PnR, physical timing, bitstream or board proof',jobs=[])
def save(): (out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
save()
try:
    for active in [4,8]:
        d=out/('keys'+str(active)); d.mkdir()
        wrapper=d/'synthesis_top.v'
        wrapper.write_text('''module synthesis_top(input wire clk,rst_n,miso,
output wire cs_n,sclk,mosi,output wire [7:0] gate,
output wire [127:0] key_gain,output wire controls_valid,
output wire [95:0] raw_frame,control_raw_frame,
output wire frame_valid,scan_start,scan_busy,timeout,
output wire [31:0] timeout_count);
pressure_keys_input #(.ACTIVE_KEYS('''+str(active)+''')) dut(.*);
endmodule
''',encoding='utf-8')
        sdc=d/'clock.sdc'; sdc.write_text('create_clock -name clk -period 20 [get_ports {clk}]\n')
        files='\n'.join(f'<File path="{p.as_posix()}" type="file.verilog" enable="1"/>' for p in sources+[wrapper])
        project=d/'pressure_input.gprj'
        project.write_text('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE gowin-fpga-project>\n<Project>\n<Template>FPGA</Template><Version>5</Version>\n<Device name="GW5AT-60B" pn="GW5AT-LV60PG484AC1/I0">gw5at60b-002</Device>\n<FileList>'+files+f'\n<File path="{sdc.as_posix()}" type="file.sdc" enable="1"/>\n</FileList></Project>\n',encoding='utf-8')
        tcl=d/'run.tcl'
        tcl.write_text(f'open_project {{{project.as_posix()}}}\nset_option -top_module synthesis_top\nset_option -verilog_std sysv2017\nrun syn\n',encoding='utf-8')
        argv=[args.gw_sh,str(tcl)]
        r=subprocess.run(argv,cwd=d,capture_output=True,timeout=600)
        (d/'build.log').write_bytes(r.stdout+b'\nSTDERR:\n'+r.stderr)
        text=(r.stdout+r.stderr).decode('utf-8',errors='replace')
        reports=[p for p in (d/'impl').rglob('*') if p.is_file()]
        errors=[line for line in text.splitlines() if line.startswith('ERROR')]
        warnings=[line for line in text.splitlines() if 'WARN' in line]
        entry=dict(active_keys=active,argv=argv,cwd=str(d),exit_code=r.returncode,
            errors=errors,warnings=warnings,project_sha256=sha(project),
            wrapper_sha256=sha(wrapper),tcl_sha256=sha(tcl),
            artifacts={p.relative_to(d).as_posix():sha(p) for p in reports})
        m['jobs'].append(entry); save()
        assert r.returncode==0 and not errors and reports,'Synthesis failed: '+str(d)
        assert any(p.suffix=='.vg' for p in reports),'Missing synthesized netlist'
        print(f'PASS synthesis active_keys={active} evidence={d}',flush=True)
    assert hashes()==m['input_sha256'],'RTL changed during synthesis'
    m['status']='PASS_SYNTHESIS_ONLY'; m['completed_at']=datetime.now(timezone.utc).isoformat(); save()
    print('PASS evidence='+str(out))
except Exception as ex:
    m['status']='FAILED'; m['failure']=str(ex); save(); raise
