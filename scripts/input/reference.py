"""Independent integer model: no DUT hierarchy or simulator-derived expectations."""
import random


def pack(values, width):
    return sum(v << (width*i) for i,v in enumerate(values))


DEFAULT = dict(ton=[256]*8, toff=[128]*8, low=[128]*8,
               high=[3840]*8, minimum=[4096]*8)
CUSTOM = dict(ton=[1,100,4095,700,2100,256,900,2],
              toff=[0,99,4094,300,2000,128,700,1],
              low=[0,100,0,350,2000,0,750,0],
              high=[1,101,4095,360,2100,4095,4090,4095],
              minimum=[1,65535,65534,4096,32768,1,257,12000])


class Keys:
    def __init__(self, active, cfg):
        self.active, self.cfg = active, cfg
        self.reset()

    def reset(self):
        self.down = [False]*8
        self.confirm = [False]*8
        self.smooth = [0]*8

    def cancel(self):
        self.confirm = [False]*8

    def process(self, raw):
        gains = [0]*8
        for i in range(self.active):
            x=(raw >> (12*i)) & 4095
            c=self.cfg
            was_down=self.down[i]
            crossing=(x <= c['toff'][i]) if was_down else (x >= c['ton'][i])
            if crossing and self.confirm[i]:
                self.down[i]=not was_down
                self.confirm[i]=False
            else:
                self.confirm[i]=crossing
            bounded=min(max(x,c['low'][i]),c['high'][i])
            target=c['minimum'][i]+((bounded-c['low'][i])*(65535-c['minimum'][i]))//(c['high'][i]-c['low'][i])
            previous=self.smooth[i] if was_down else c['minimum'][i]*256
            difference=target*256-previous
            # HDL signed / truncates toward zero, unlike Python // for negatives.
            step=(abs(difference)//4)*(1 if difference>=0 else -1)
            self.smooth[i]=(previous+step) if self.down[i] else 0
            gains[i]=max(c['minimum'][i],(self.smooth[i]+128)//256) if self.down[i] else 0
        return pack([int(x) for x in self.down],1),pack(gains,16)


def vectors(path, active, cfg):
    rng=random.Random(20261016+active)
    sequence=[]
    def add(values, repeat=1, valid=1, reset=1, cancel=0):
        for _ in range(repeat):
            sequence.append((reset,valid,cancel,pack(values,12)))
    zeros=[0]*8
    add(zeros,5,valid=0,reset=0)
    add(zeros,30,valid=0)
    # Threshold equalities, deadband, single spikes and alternating noise.
    add(zeros,30)
    add(cfg['ton']); add(zeros); add(cfg['ton']); add(cfg['ton'])
    mid=[(a+b)//2 for a,b in zip(cfg['ton'],cfg['toff'])]
    add(mid,8); add(cfg['toff']); add(cfg['ton']); add(cfg['toff'],2)
    for _ in range(30):
        add(cfg['ton']); add(zeros)
    add([4095]*8,180)
    # One key changes; others remain saturated and independently stable.
    for i in range(8):
        x=[4095]*8; x[i]=0; add(x,40)
        x[i]=cfg['ton'][i]; add(x,30)
    for x in range(4096): add([(x+137*i)%4096 for i in range(8)])
    for x in range(4095,-1,-1): add([(x+137*i)%4096 for i in range(8)])
    add([4095]*8,180); add([2000]*8,100); add([4095]*8,100)
    add(zeros,50); add([4095]*8,2); add(zeros,2); add([4095]*8,2)
    # Cancel/reset at every pipeline age, including retirement boundary.
    for age in range(20):
        add([4095]*8); add(zeros,age,valid=0)
        add(zeros,valid=1,cancel=1)
        add(zeros,30,valid=0)
        add(cfg['ton'],2); add(zeros,25,valid=0)
        add(zeros,reset=0); add(zeros,25,valid=0)
    for t in range(5000):
        add([rng.randrange(4096) for _ in range(8)],
            valid=int(rng.random()<.8),reset=int(t%997!=0),cancel=int(t%433==17))
    add(zeros,35,valid=0)
    keys=Keys(active,cfg); pipeline={}; gate=gain=raw_out=valid=0
    held_gate=held_gain=sample_gate=sample_gain=0
    lines=[]; rows=[]; published=0; cancellations=0
    for cycle,(rst,rv,cancel,raw) in enumerate(sequence):
        ce=int(cycle%3==0 or cycle%1024==0)
        # Consumer sees pre-edge data, and snapshots its previously held frame.
        if not rst:
            keys.reset(); pipeline.clear(); gate=gain=raw_out=valid=0
            held_gate=held_gain=sample_gate=sample_gain=0
        else:
            if ce: sample_gate,sample_gain=held_gate,held_gain
            if valid: held_gate,held_gain=gate,gain
            valid=0
            if cancel:
                keys.cancel(); pipeline.clear(); cancellations+=1
            else:
                if cycle in pipeline:
                    raw_out=pipeline.pop(cycle)
                    gate,gain=keys.process(raw_out); valid=1; published+=1
                if rv: pipeline[cycle+19]=raw
        row=(cycle,valid,gate,gain,raw_out,sample_gate,sample_gain)
        rows.append(row)
        lines.append(f'{rst} {rv} {cancel} {ce} {raw:024x} {valid} {gate:02x} {gain:032x} {raw_out:024x} {sample_gate:02x} {sample_gain:032x}\n')
    path.write_text(''.join(lines),encoding='ascii')
    return rows,dict(cycles=len(rows),published=published,cancellations=cancellations,
        latency_clocks=19,latency_ns=380,active_keys=active,calibration=cfg,
        coverage=['all 4096 raw codes ascending/descending per channel',
                  'threshold equality/deadband/spikes/alternating noise',
                  'independent single-key release and force change',
                  'positive/negative smoothing, saturation, long hold, rapid repeat',
                  'cancel/reset at every pipeline age 0..19',
                  'continuous valid and bubbles, old-frame sample coincidence',
                  'fixed-seed randomized traffic'])
