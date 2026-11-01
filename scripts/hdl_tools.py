from pathlib import Path
import os,subprocess,time,json
ROOT=Path(__file__).resolve().parents[1]
LIB=Path(os.environ.get('IVL_LIB','D:/iverilog/lib/ivl'))
VVP=Path(os.environ.get('VVP_BIN','D:/iverilog/bin/vvp.exe'))
def command(name,args,timeout=1200):
 t=time.monotonic()
 env=dict(os.environ);env.pop('IVERILOG_ICONFIG',None)
 (ROOT/'sim').mkdir(exist_ok=True)
 p=subprocess.run(list(map(str,args)),cwd=ROOT,env=env,capture_output=True,text=True,errors='replace',timeout=timeout)
 (ROOT/'sim'/(name+'.log')).write_text(p.stdout+'\n'+p.stderr,encoding='utf-8')
 if p.returncode:raise RuntimeError(name+': '+str(p.returncode)+'\n'+p.stdout[-2500:]+p.stderr[-2500:])
 return p.stdout,round(time.monotonic()-t,2)
def run(name,top,files):
 out=ROOT/'sim';pre=out/(name+'.sv');cfg=out/(name+'.conf');exe=out/(name+'.vvp')
 for p in [pre,cfg,exe]:p.unlink(missing_ok=True)
 binary=lambda n:LIB/(n+'.exe') if (LIB/(n+'.exe')).exists() else LIB/n
 command(name+'_pre',[binary('ivlpp'),'-L','-o',pre,*[ROOT/f for f in files]])
 cfg.write_text('\n'.join([f'root:{top}',f'basedir:{LIB}',
  *[f'module:{LIB/(x+".vpi")}' for x in ['system','vhdl_sys','vhdl_textio','v2005_math','va_math','v2009']],
  'generation:2012','generation:no-specify','generation:assertions','generation:xtypes',
  'generation:io-range-error','generation:icarus-misc','warnings:nidRpsta',
  'ignore_missing_modules:false',f'out:{exe}','iwidth:32','widthcap:65536'])+'\n')
 command(name+'_compile',[binary('ivl'),'-C',cfg,'-C',LIB/'vvp.conf','--',pre])
 text,seconds=command(name+'_run',[VVP,exe])
 assert 'PASS' in text and 'FAIL' not in text and 'FATAL' not in text,text
 print(name+': '+text.strip(),flush=True)
 return {'status':'PASS','seconds':seconds,'output':text.strip()}
