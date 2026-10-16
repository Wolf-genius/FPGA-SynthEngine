"""External-signal VCD assertions, independently of TB and the integer model."""
from pathlib import Path
import json
from check_scan import vcd_states, num


def unit(folder):
    pending={}; count=0; cancels=0; resets=0
    for t,old,s,changes in vcd_states(Path(folder)/'frames.vcd'):
        # At VCD #0 the initially asserted reset has not yet had an active
        # clock/delta to initialize registers. Check every later reset epoch.
        if t==0: continue
        if s.get('rst_n')=='0':
            pending.clear()
            if old.get('rst_n')=='1': resets+=1
            assert all(num(s[n])==0 for n in ('gate','key_gain','controls_valid','control_raw_frame'))
            continue
        if old.get('clk')!='0' or s.get('clk')!='1': continue
        if old['frame_cancel']=='1':
            pending.clear(); cancels+=1
            assert s['controls_valid']=='0'
        else:
            due=pending.pop(t,None)
            assert num(s['controls_valid'])==int(due is not None),(t,'valid latency')
            if due is not None:
                assert num(s['control_raw_frame'])==due,(t,'raw alignment')
                count+=1
            if old['frame_valid']=='1': pending[t+380]=num(old['raw_frame'])
        if s['controls_valid']=='0':
            for n in ('gate','key_gain','control_raw_frame'):
                assert s[n]==old[n],(t,'changed outside valid',n)
    assert count>8000 and cancels>=20 and resets>=20
    return dict(status='PASS',publications=count,cancel_pulses=cancels,resets=resets,
                raw_accept_to_control_ns=380,no_partial_updates=True)


def integrated(folder):
    pending={}; pulse=None; count=0; widths=[]
    for t,old,s,changes in vcd_states(Path(folder)/'integrated.vcd'):
        if s.get('rst_n')!='1': pending.clear(); pulse=None; continue
        rise=lambda n:old.get(n)=='0' and s.get(n)=='1'
        fall=lambda n:old.get(n)=='1' and s.get(n)=='0'
        if rise('frame_valid'): pending[t+400]=num(s['raw_frame'])
        if rise('controls_valid'):
            assert t in pending and num(s['control_raw_frame'])==pending.pop(t)
            assert num(s['gate'])<16 and num(s['key_gain'])>>64==0
            count+=1; pulse=t
        if fall('controls_valid'):
            assert pulse is not None and t-pulse==20
            widths.append(t-pulse); pulse=None
        for n in ('gate','key_gain','control_raw_frame'):
            if n in changes and old.get(n)!=s[n]: assert rise('controls_valid'),(t,n)
    assert count==14 and len(widths)==14
    return dict(status='PASS',publications=count,raw_publication_to_control_ns=400,
                control_valid_width_ns=20,atomic=True,disabled_keys_zero=True)


def verify(folder):
    folder=Path(folder)
    r={name:unit(folder/name) for name in ['one_key','four_keys','eight_custom']}
    r['scan_controls']=integrated(folder/'scan_controls')
    (folder/'controls_waveform_report.json').write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    print('PASS independent control VCD assertions')
    return r


if __name__=='__main__':
    import sys
    verify(sys.argv[1])
