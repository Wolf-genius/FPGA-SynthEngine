"""Recompile every job; fresh evidence, exit checks, independent math/pin checks."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import argparse, csv, hashlib, json, os, subprocess, sys
from reference import DEFAULT, CUSTOM, Keys, pack, vectors
from check_scan import verify as check_scan
from check_waveform import verify as check_spi
from check_controls import verify as check_controls

sys.stdout.reconfigure(encoding='utf-8')
root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser()
p.add_argument('--iverilog',default='D:/iverilog/bin/iverilog.exe')
p.add_argument('--vvp',default='D:/iverilog/bin/vvp.exe')
args=p.parse_args()
stamp=datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S_%f')
out=root/'sim_build/pressure_keys'/('verified_'+stamp); out.mkdir(parents=True)
ivl=Path(args.iverilog).resolve().parents[1]/'lib/ivl'
env=os.environ.copy(); env.pop('IVERILOG_ICONFIG',None)
inputs=sorted(x for folder in ['rtl/input','tb/input','scripts/input','examples/input'] for x in (root/folder).glob('*') if x.is_file() and x.suffix in ('.v','.sv','.py'))
inputs.append(root/'docs/input/four_keys/SOURCE_ORIGINS.json')
sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
hashes=lambda:{x.relative_to(root).as_posix():sha(x) for x in inputs}
m=dict(status='RUNNING',started_at=datetime.now(timezone.utc).isoformat(),
       input_sha256=hashes(),steps=[],results={},
       scope='B 10/15-18 code only: no ADSR core, physical calibration, board validation or total latency claim')
def save():
    (out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
def run(label,argv,d,expected_exit=0):
    r=subprocess.run([str(x) for x in argv],cwd=d,env=env,capture_output=True,text=True,errors='replace',timeout=60)
    log=d/(label+'.log')
    log.write_text('cwd='+str(d)+'\nargv='+json.dumps([str(x) for x in argv])+'\nexit_code='+str(r.returncode)+'\nSTDOUT:\n'+r.stdout+'\nSTDERR:\n'+r.stderr,encoding='utf-8')
    m['steps'].append(dict(label=label,argv=[str(x) for x in argv],cwd=str(d),exit_code=r.returncode,log=log.relative_to(out).as_posix()))
    save(); print(f'{d.name}/{label}: exit={r.returncode}',flush=True)
    if expected_exit==0 and r.returncode!=0: raise RuntimeError(str(log))
    return r
def compile_run(name,top,sources,marker,wrapper=None,negative=False):
    d=out/name; d.mkdir(parents=True,exist_ok=True)
    if wrapper is not None:
        (d/'wrapper.sv').write_text(wrapper,encoding='utf-8'); sources=sources+[d/'wrapper.sv']; top='test'
    pre=d/'preprocessed.sv'; cfg=d/'compile.conf'; exe=d/'checked.vvp'
    run('01_preprocess',[args.iverilog,'-g2012','-E','-o',pre,*sources],d)
    assert pre.exists() and not exe.exists()
    cfg.write_text('\n'.join([f'root:{top}',f'basedir:{ivl}',
        *[f'module:{ivl/(x+".vpi")}' for x in ['system','vhdl_sys','vhdl_textio','v2005_math','va_math','v2009']],
        'generation:2012','generation:no-specify','generation:assertions','generation:xtypes',
        'generation:io-range-error','generation:icarus-misc','warnings:nidRpsta',
        'ignore_missing_modules:false',f'out:{exe}','iwidth:32','widthcap:65536'])+'\n',encoding='utf-8')
    run('02_compile',[ivl/'ivl.exe','-C',cfg,'-C',ivl/'vvp.conf','--',pre],d)
    r=run('03_simulation',[args.vvp,exe],d,expected_exit=None if negative else 0)
    assert marker in r.stdout, f'Missing completion marker: {name}'
    assert (r.returncode!=0) if negative else ('FATAL' not in r.stdout and 'FAIL' not in r.stdout)
    return d
src=lambda names:[root/'rtl/input'/n for n in names.split()]
tb=lambda name:root/'tb/input'/name
controls=src('pressure_key_filter.v pressure_frame_controls.v')
scanner=src('adc_spi.v adc_scan_controller.v adc_scan.v')

try:
    run('iverilog_version',[args.iverilog,'-V'],out)
    run('vvp_version',[args.vvp,'-V'],out)
    # Probe the known outer-driver fault in an isolated output. Never execute it
    # on failure. All accepted jobs below use explicit staged compilation.
    probe=out/'outer_probe.v'; probe.write_text('module probe; initial $finish; endmodule\n')
    result=run('outer_probe',[args.iverilog,'-g2012','-s','probe','-o',out/'outer_probe.vvp',probe],out,expected_exit=None)
    m['outer_driver_exit_code']=result.returncode
    for name,active,c in [('one_key',1,DEFAULT),('four_keys',4,DEFAULT),('eight_custom',8,CUSTOM)]:
        d=out/name; d.mkdir()
        expected,report=vectors(d/'vectors.txt',active,c)
        parameters=[f'.ACTIVE_KEYS({active})']
        for key,width,param in [('ton',12,'TON_PACK'),('toff',12,'TOFF_PACK'),('low',12,'RAW_MIN_PACK'),('high',12,'RAW_MAX_PACK'),('minimum',16,'MIN_GAIN_PACK')]:
            parameters.append(f'.{param}({width*8}\'h{pack(c[key],width):x})')
        wrapper='module test; tb_frames #('+','.join(parameters)+') b(); endmodule\n'
        compile_run(name,'tb_frames',controls+[root/'examples/input/control_frame_receiver.v',tb('tb_frames.sv')],'PASS ALL frames',wrapper)
        actual=list(csv.DictReader((d/'actual.csv').open()))
        assert len(actual)==len(expected)
        for a,e in zip(actual,expected):
            got=tuple(int(a[k],10 if k in ('cycle','valid') else 16) for k in ['cycle','valid','gate','gain','raw','sample_gate','sample_gain'])
            assert got==e,(name,e[0],got,e)
        m['results'][name]=report; save()
    compile_run('spi','tb_adc_spi',src('adc_spi.v')+[tb('mcp3208_model.sv'),tb('tb_adc_spi.sv')],'PASS ALL')
    m['results']['spi']=check_spi(out/'spi')
    compile_run('scanner/integrated','tb_adc_scan',scanner+[tb('mcp3208_model.sv'),tb('tb_adc_scan.sv')],'PASS ALL integrated')
    compile_run('scanner/faults','tb_scan_faults',src('adc_scan_controller.v')+[tb('tb_scan_faults.sv')],'PASS ALL faults')
    m['results']['scanner']=check_scan(out/'scanner')
    d=compile_run('scan_controls','tb_scan_controls',scanner+controls+src('pressure_keys_input.v')+[tb('mcp3208_model.sv'),tb('tb_scan_controls.sv')],'PASS ALL scan_controls')
    rows=list(csv.DictReader((d/'integrated.csv').open()))
    epoch=-1; keys=None; raw_events={}; scan_events={}; previous=None; cases=[]
    for r in rows:
        e=int(r['epoch']); cycle=int(r['cycle']); t=int(r['time_ns'])
        if e!=epoch: epoch=e; keys=Keys(4,DEFAULT); previous=None
        if r['event']=='SCAN':
            if previous is not None: assert t-previous==1000000
            previous=t; scan_events[e]=t
        if r['event']=='RAW':
            raw_events[e]=(cycle,int(r['raw'],16)); assert t-scan_events[e]==408480
        if r['event']=='CONTROL':
            raw=int(r['raw'],16)
            assert raw_events[e]==(cycle-20,raw)
            g,a=keys.process(raw)
            assert (int(r['gate'],16),int(r['gain'],16))==(g,a),r
            cases.append(dict(epoch=e,cycle=cycle,time_ns=t,gate=g,gain=f'{a:032x}'))
    assert len(cases)==14 and cases[2]['gate']==15 and cases[4]['gate']==13 and cases[6]['gate']==15 and cases[10]['gate']==0
    m['results']['scan_controls']=dict(status='PASS',frames=len(cases),raw_to_control_clocks=20,
        scan_to_raw_ns=408480,scan_to_control_ns=408880,scan_period_ns=1000000,frames_checked=cases)
    compile_run('fault_handoff','tb_fault_handoff',src('adc_scan_controller.v')+controls+[tb('tb_fault_handoff.sv')],'PASS ALL fault_handoff')
    m['results']['fault_handoff']=dict(status='PASS',timeouts=2,consecutive_confirmation_restart=True)
    for name,cycles,total in [('fake_all',40,802),('fake_default',50000,12)]:
        wrapper=f'module test; tb_fake_controls #(.FRAME_CYCLES({cycles}),.TOTAL_FRAMES({total})) b(); endmodule\n'
        compile_run(name,'tb_fake_controls',[root/'examples/input/fake_four_key_controls.v',tb('tb_fake_controls.sv')],'PASS ALL fake_controls',wrapper)
        m['results'][name]=dict(status='PASS',frames=total+2,frame_cycles=cycles)
    for name,params,message in [('invalid_active','.ACTIVE_KEYS(0)','ACTIVE_KEYS must be'),('invalid_calibration',".TON_PACK(96'd0)",'Invalid pressure calibration')]:
        wrapper='module test; pressure_frame_controls #('+params+') dut(.clk(1\'b0),.rst_n(1\'b0),.raw_frame(96\'d0),.frame_valid(1\'b0),.frame_cancel(1\'b0)); endmodule\n'
        compile_run(name,'test',controls,message,wrapper,negative=True)
        m['results'][name]=dict(status='PASS expected rejection')
    m['results']['control_waveforms']=check_controls(out)
    assert hashes()==m['input_sha256'],'Source changed during run'
    origins=json.loads((root/'docs/input/four_keys/SOURCE_ORIGINS.json').read_text())
    base=root.parents[1]
    if (base/'one_key/rtl').is_dir() and root.parent.name=='voice':
        assert all(sha(base/k)==v for k,v in origins['preserved_source_sha256'].items()),'Original source modified'
        m['original_sources_preserved']=True
    else:
        m['original_sources_preserved']='Not checked: standalone extracted delivery has no original workspace'
    assert all(sha(root/k)==v['sha256'] for k,v in origins['origins'].items() if v['kind']=='unchanged copy')
    m['unchanged_dependency_copies_verified']=True
    m['status']='PASS'; m['completed_at']=datetime.now(timezone.utc).isoformat()
    m['output_sha256']={x.relative_to(out).as_posix():sha(x) for x in out.rglob('*') if x.is_file() and x.name!='manifest.json'}
    save(); print('PASS evidence='+str(out))
except Exception as ex:
    m['status']='FAILED'; m['failure']=str(ex); save(); raise
