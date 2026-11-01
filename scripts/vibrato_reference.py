"""Fixed-point waveform reference and independent pitch/level measurements."""
from pathlib import Path
import json, math, random

FS=50_000_000/1024
PHASE_STEP=439805
N=163840

def generate(root):
    rng=random.Random(20261025)
    samples=[]
    for i in range(N):
        if i<4096:
            samples.append([-32768,32767,0,-1,1][i%5] if i%2 else rng.randrange(-32768,32768))
        else:
            samples.append(round(12000*math.sin(2*math.pi*1000*i/FS)))
    enabled=[int(512<=i<131072) for i in range(N)]
    (root/'sim/vibrato_input.hex').write_text(''.join(f'{x&65535:04x}\n' for x in samples))
    (root/'sim/vibrato_enable.hex').write_text(''.join(f'{x:x}\n' for x in enabled))
    return samples,enabled

def solve3(matrix,rhs):
    a=[list(row)+[value] for row,value in zip(matrix,rhs)]
    for c in range(3):
        k=max(range(c,3),key=lambda i:abs(a[i][c]));a[c],a[k]=a[k],a[c]
        scale=a[c][c];assert abs(scale)>1e-12
        a[c]=[x/scale for x in a[c]]
        for r in range(3):
            if r!=c:
                scale=a[r][c];a[r]=[x-scale*y for x,y in zip(a[r],a[c])]
    return [row[3] for row in a]

def fit_pitch(times,frequencies,rate):
    s=[math.sin(2*math.pi*rate*t) for t in times]
    c=[math.cos(2*math.pi*rate*t) for t in times]
    dot=lambda a,b:sum(x*y for x,y in zip(a,b))
    rhs=[sum(frequencies),dot(s,frequencies),dot(c,frequencies)]
    coef=solve3([[len(times),sum(s),sum(c)],
                 [sum(s),dot(s,s),dot(s,c)],
                 [sum(c),dot(s,c),dot(c,c)]],rhs)
    error=sum((y-coef[0]-coef[1]*si-coef[2]*ci)**2 for y,si,ci in zip(frequencies,s,c))
    return error,coef

def analyze(root):
    samples=[int(x,16) for x in (root/'sim/vibrato_input.hex').read_text().split()]
    samples=[x-65536 if x>=32768 else x for x in samples]
    enabled=[int(x,16) for x in (root/'sim/vibrato_enable.hex').read_text().split()]
    rom=[int(x,16) for x in (root/'tables/vibrato_sine256.hex').read_text().split()]
    rom=[x-65536 if x>=32768 else x for x in rom]
    rows=[list(map(int,line.split())) for line in (root/'sim/vibrato_samples.txt').read_text().splitlines()]
    assert len(rows)==N
    actual=[];level=0;bypass=0
    for n,(index,y,mix) in enumerate(rows):
        assert index==n
        ready=n>=82
        level=min(256,level+1) if enabled[n] and ready else max(0,level-1)
        assert mix==level,(n,mix,level)
        if level:
            phase=(n*PHASE_STEP)&0xffffffff;k=phase>>24;frac=(phase>>8)&65535
            lfo=rom[k]+((rom[(k+1)&255]-rom[k])*frac//65536)
            delay=(64<<16)+lfo*32;whole=delay>>16;fraction=delay&65535
            assert 48<=whole<=80 and n-whole-1>=0
            wet=samples[n-whole]+((samples[n-whole-1]-samples[n-whole])*fraction//65536)
            expected=samples[n]+((wet-samples[n])*level//256)
        else:
            expected=samples[n];bypass+=1
        assert y==expected,(n,y,expected)
        assert -32768<=y<=32767
        actual.append(y)
    # Measure output pitch independently, without consulting delay/LFO internals.
    lo,hi=8192,131000
    crossings=[]
    for i in range(lo,hi-1):
        a,b=actual[i:i+2]
        if a<=0<b:crossings.append(i-a/(b-a))
    times=[(a+b)/(2*FS) for a,b in zip(crossings,crossings[1:])]
    frequencies=[FS/(b-a) for a,b in zip(crossings,crossings[1:])]
    rate=min((4.5+i*.005 for i in range(201)),key=lambda r:fit_pitch(times,frequencies,r)[0])
    error,coef=fit_pitch(times,frequencies,rate)
    depth=math.hypot(coef[1],coef[2])/coef[0]
    rms=lambda v:math.sqrt(sum(x*x for x in v)/len(v))
    level_ratio=rms(actual[lo:hi])/rms(samples[lo:hi])
    peaks=[max(abs(x) for x in actual[math.ceil(a):math.ceil(b)]) for a,b in zip(crossings,crossings[1:])]
    peak_spread=(max(peaks)-min(peaks))/12000
    assert 4.95<=rate<=5.05,rate
    assert 999<=coef[0]<=1001,coef
    assert .008<depth<.013,depth
    assert .98<level_ratio<1.02,level_ratio
    assert peak_spread<.01,peak_spread
    metrics={'status':'PASS','waveform_samples_bit_exact':N,'fully_bypassed_samples_bit_exact':bypass,
             'analysis_sample_rate_hz':FS,'measured_vibrato_rate_hz':round(rate,4),
             'carrier_center_hz':round(coef[0],4),'measured_pitch_swing_percent':round(depth*100,5),
             'rms_output_input_ratio':round(level_ratio,6),'cycle_peak_spread_percent':round(peak_spread*100,5),
             'note':'Frequency estimated from output zero crossings; unit simulation accelerates sample spacing. No physical audio measurement.'}
    (root/'evidence/vibrato_audio_metrics.json').write_text(json.dumps(metrics,indent=2)+'\n')
    print('PASS independent vibrato pitch analysis:',metrics,flush=True)
    return metrics
