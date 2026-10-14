"""Independent integer reference vectors + staged Icarus + checked evidence."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import subprocess, os, hashlib, json, random, csv, argparse, shutil

parser=argparse.ArgumentParser()
parser.add_argument('--iverilog',default=shutil.which('iverilog') or 'D:/iverilog/bin/iverilog.exe')
parser.add_argument('--vvp',default=shutil.which('vvp') or 'D:/iverilog/bin/vvp.exe')
args=parser.parse_args()

root = Path(__file__).resolve().parents[2]
out = root/'sim_build'/'input'/('verified_'+datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S_%f'))
out.mkdir(parents=True, exist_ok=False)
sources = [root/'rtl/input/pressure_ch0_controls.v', root/'examples/input/control_frame_receiver.v', root/'tb/input/tb_controls.sv']
example_sources = [root/'rtl/input/pressure_ch0_controls.v',root/'rtl/input/adc_spi.v',root/'rtl/input/pressure_ch0_input.v',root/'examples/input/fake_ch0_controls.v',root/'tb/input/mcp3208_model.sv',root/'tb/input/tb_input_examples.sv']
inputs = list(dict.fromkeys(sources + example_sources + [Path(__file__).resolve()]))
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
hashes = lambda: {str(p.relative_to(root)):sha(p) for p in inputs}
m = dict(status='INCOMPLETE', started_at=datetime.now(timezone.utc).isoformat(),
         input_sha256=hashes(), steps=[], scope='CH0 processing, receiver, real SPI integration and fake source; no board/Gowin')
env=os.environ.copy(); env.pop('IVERILOG_ICONFIG',None)
def save():
    (out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n',encoding='utf-8')
def run(label,args):
    p=subprocess.run([str(x) for x in args],cwd=out,env=env,capture_output=True,text=True,errors='replace',timeout=120)
    (out/(label+'.log')).write_text(f'argv={json.dumps([str(x) for x in args])}\ncwd={out}\nexit_code={p.returncode}\nSTDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}',encoding='utf-8')
    m['steps'].append(dict(step=label,exit_code=p.returncode)); save()
    if p.returncode: raise RuntimeError(label+' failed')
    print(label+': exit=0',flush=True)
    return p.stdout

try:
    # Generate clock-by-clock oracle without reading DUT state.
    g=confirm=q=valid=gain=held_g=held_gain=sample_g=sample_gain=0
    rows=[]; categories={}; rng=random.Random(20261014)
    def step(raw=0,v=0,r=1,ce=0):
        global g,confirm,q,valid,gain,held_g,held_gain,sample_g,sample_gain
        if not r:
            g=confirm=q=valid=gain=held_g=held_gain=sample_g=sample_gain=0
        else:
            if ce: sample_g,sample_gain=held_g,held_gain
            if valid: held_g,held_gain=g,gain
            valid=v
            if v:
                old_g=g
                crossing=(raw>=256 if not g else raw<=128)
                if crossing:
                    if confirm: g=1-g; confirm=0
                    else: confirm=1
                else: confirm=0
                target=4096 if raw<=128 else 65535 if raw>=3840 else 4096+(raw-128)*61439//3712
                base=q if old_g else 4096*256
                diff=target*256-base
                # Verilog signed division truncates toward zero.
                q=(base+(1 if diff>=0 else -1)*(abs(diff)//4)) if g else 0
                gain=max(4096,(q+128)//256) if g else 0
        rows.append(tuple(map(int,(r,v,raw,ce,g,gain,valid,sample_g,sample_gain))))
    def feed(raw):
        step(raw,1,ce=1); step(rng.randrange(4096),0,ce=1)
    def section(name,fn):
        start=len(rows); fn(); categories[name]=[start,len(rows)-1]
    section('reset_and_no_valid',lambda: [step(4095,0,r=i>=2,ce=1) for i in range(12)])
    section('threshold_noise_and_single_spikes',lambda: [feed(x) for x in [256,255,256,129,4095,0,256,256,129,128,129,128,128]])
    section('all_4096_codes_up_and_down',lambda: [feed(x) for x in [*range(4096),*range(4095,-1,-1)]])
    section('held_gain_steps_and_repress',lambda: [feed(x) for x in [*[4095]*100,*[257]*100,*[129]*100,128,129,*[128]*100,4095,4095,*[3840]*100]])
    section('reset_discards_first_confirmation',lambda: [step(raw,v,r,1) for raw,v,r in [(0,0,0),(256,1,1),(4095,0,0),(256,1,1),(0,1,1),(256,1,1),(256,1,1)]])
    section('valid_bursts_and_random_resets',lambda: [step(rng.randrange(4096),int(rng.random()<0.65),int(rng.random()>0.01),int(rng.random()<0.4)) for _ in range(5000)])
    # Model sanity conditions independent of per-cycle equality.
    assert any(row[4:6]==(1,65535) for row in rows)
    assert all(4096 <= row[5] <= 65535 if row[4] else row[5]==0 for row in rows)
    (out/'vectors.txt').write_text(''.join(' '.join(map(str,row))+'\n' for row in rows),encoding='ascii')
    m['coverage']=dict(cycles=len(rows),sections=categories,seed=20261014); save()
    ivl=Path(args.iverilog).resolve().parents[1]/'lib/ivl'; exe=out/'checked.vvp'; pre=out/'preprocessed.sv'; cfg=out/'compile.conf'
    run('iverilog_version',[args.iverilog,'-V'])
    run('vvp_version',[args.vvp,'-V'])
    run('01_preprocess',[args.iverilog,'-g2012','-E','-o',pre,*sources])
    cfg.write_text('\n'.join(['root:tb_controls',f'basedir:{ivl}',*[f'module:{ivl/(x+".vpi")}' for x in ('system','vhdl_sys','vhdl_textio','v2005_math','va_math','v2009')],
        'generation:2012','generation:no-specify','generation:assertions','generation:xtypes','generation:io-range-error','generation:icarus-misc',
        'warnings:nidRpsta','ignore_missing_modules:false',f'out:{exe}','iwidth:32','widthcap:65536'])+'\n',encoding='ascii')
    assert not exe.exists()
    run('02_compile',[ivl/'ivl.exe','-C',cfg,'-C',ivl/'vvp.conf','--',pre])
    stdout=run('03_simulation',[args.vvp,exe])
    assert f'PASS ALL controls cycles={len(rows)}' in stdout
    with (out/'actual.csv').open() as f: actual=list(csv.DictReader(f))
    assert len(actual)==len(rows)
    for i,(expected,a) in enumerate(zip(rows,actual)):
        assert tuple(int(a[k]) for k in ('gate','gain','valid','sample_gate','sample_gain'))==expected[4:], i
    ex_pre=out/'examples_preprocessed.sv'; ex_exe=out/'examples.vvp'; ex_cfg=out/'examples_compile.conf'
    run('04_examples_preprocess',[args.iverilog,'-g2012','-E','-o',ex_pre,*example_sources])
    ex_cfg.write_text(cfg.read_text().replace('root:tb_controls','root:tb_input_examples').replace(str(exe),str(ex_exe)),encoding='ascii')
    assert not ex_exe.exists()
    run('05_examples_compile',[ivl/'ivl.exe','-C',ex_cfg,'-C',ivl/'vvp.conf','--',ex_pre])
    ex_stdout=run('06_examples_simulation',[args.vvp,ex_exe])
    assert 'PASS ALL examples' in ex_stdout
    assert hashes()==m['input_sha256']
    m.update(status='PASS',completed_at=datetime.now(timezone.utc).isoformat(),trace_checked_cycles=len(actual))
    m['output_sha256']={str(p.relative_to(out)):sha(p) for p in out.iterdir() if p.is_file() and p.name!='manifest.json'}
    save(); print('PASS evidence='+str(out))
except Exception as e:
    m.update(status='FAILED',failure=str(e)); save(); raise
