"""Independent assertions using external scan/SPI VCD signals and CSV evidence."""
import csv
import json
import re
from pathlib import Path


def vcd_states(path):
    names, state, header = {}, {}, ""
    with path.open(encoding="ascii") as f:
        for line in f:
            header += line
            if line.startswith("$var "):
                fields=line.split(); names[fields[3]]=fields[4]
            if "$enddefinitions" in line: break
        m=re.search(r"\$timescale\s+(\d+)\s*(ns|ps|fs)\s+\$end",header)
        assert m, "VCD timescale missing"
        scale=int(m[1])*{"ns":1,"ps":.001,"fs":.000001}[m[2]]
        t,changes=0,{}
        for line in f:
            line=line.strip()
            if line.startswith("#"):
                old=state.copy(); state.update(changes)
                yield round(t*scale,3),old,state.copy(),changes
                t,changes=int(line[1:]),{}
            elif line.startswith("b"):
                value,ident=line[1:].split(); changes[names[ident]]=value
            elif line and line[0] in "01xz": changes[names[line[1:]]]=line[0]
        old=state.copy(); state.update(changes)
        yield round(t*scale,3),old,state.copy(),changes


def num(v):
    assert v is not None and not re.search("[xz]",v), f"Unknown numeric value {v}"
    return int(v,2)


def integrated(folder):
    rounds,frames,transactions,atomic=[],[],[],[]
    active_round=None; spi=None; last_round=None; last_end=None; old_frame=0
    pulse=None; scan_pulse=None; last_payload=None; periods=[]; gaps=[]; reset_count=0; publish_delays=[]
    for t,old,s,c in vcd_states(folder/"scan.vcd"):
        rise=lambda n: old.get(n)=="0" and s.get(n)=="1"
        fall=lambda n: old.get(n)=="1" and s.get(n)=="0"
        reset=s.get("rst_n")!="1" # Ignore the empty/unknown VCD initialization epoch.
        if rise("scan_start"):
            assert active_round is None and s["scan_busy"]=="1"
            if last_round is not None:
                assert t-last_round==1000000; periods.append(t-last_round)
            last_round=t; scan_pulse=t
            active_round={"round":len(rounds)+1,"start_ns":t,"expected":num(s["channel_values"]),"channels":0}
            rounds.append(active_round)
        if fall("scan_start") and not reset: assert t-scan_pulse==20
        if fall("cs_n"):
            assert not reset and spi is None and active_round is not None
            ch=active_round["channels"]; assert ch<8
            if last_end is not None:
                assert t-last_end>=2000; gaps.append(t-last_end)
            spi={"round":active_round["round"],"channel":ch,"start_ns":t,"rises":[],"falls":[],"tx":"","rx":""}
            if ch==4:
                assert num(s["raw_frame"])==old_frame, "CH4 partial frame"
                atomic.append({"round":active_round["round"],"time_ns":t,"held_frame":f"{old_frame:024X}"})
        if rise("sclk"):
            assert not reset and s["cs_n"]=="0" and spi is not None
            n=len(spi["rises"])+1
            assert t-(spi["start_ns"] if n==1 else spi["falls"][-1])==1000
            spi["rises"].append(t); spi["tx"]+=s["mosi"]
            if n<=11: assert s["miso"]=="x"
            elif n==12: assert s["miso"]=="0"
            else: spi["rx"]+=s["miso"]
        if fall("sclk") and not reset:
            assert spi is not None and t-spi["rises"][-1]==1000
            spi["falls"].append(t)
        if rise("cs_n") and spi is not None:
            spi["end_ns"]=t; spi["status"]="reset_abort" if reset else "normal"
            if not reset:
                assert len(spi["rises"])==len(spi["falls"])==24
                assert t-spi["falls"][-1]==1000 and s["sclk"]=="0"
                ch=spi["channel"]
                assert num(spi["tx"])==0x060000 | (ch<<14)
                assert num(spi["rx"])==(active_round["expected"]>>(12*ch))&0xfff
                active_round["channels"]+=1
                last_payload=t
            transactions.append(spi); spi=None; last_end=t
        if fall("rst_n"):
            reset_count+=1
            assert num(s["raw_frame"])==0 and s["frame_valid"]==s["scan_busy"]=="0"
            assert num(s["timeout_count"])==0
            active_round=None; last_round=None; old_frame=0; pulse=None
        if rise("frame_valid"):
            assert active_round is not None and active_round["channels"]==8
            assert s["scan_busy"]=="0" and s["timeout"]=="0"
            data=num(s["raw_frame"])
            assert data==active_round["expected"]
            assert t-active_round["start_ns"]<1000000
            assert t>last_payload
            publish_delays.append(t-last_payload)
            frames.append({"round":active_round["round"],"start_ns":active_round["start_ns"],
                           "publish_ns":t,"duration_ns":t-active_round["start_ns"],"raw_frame":f"{data:024X}"})
            pulse=t; old_frame=data; active_round=None
        if fall("frame_valid") and not reset: assert t-pulse==20; pulse=None
        if "raw_frame" in c and old.get("raw_frame")!=s["raw_frame"] and not reset:
            assert rise("frame_valid"), "Atomic publication violated"
        if not reset:
            assert s.get("timeout","0")=="0" and num(s["timeout_count"])==0
            if s.get("sclk")=="1": assert s["cs_n"]=="0"
            if active_round is not None: assert s["scan_busy"]=="1", "Busy cleared before full frame"
    assert len(rounds)==7 and len(frames)==6 and len(transactions)==53
    assert sum(x["status"]=="reset_abort" for x in transactions)==1 and reset_count==1
    assert frames[1]["raw_frame"]==frames[2]["raw_frame"], "Repeated identical frame case missing"
    assert len(atomic)==7
    rows=list(csv.DictReader((folder/"frames.csv").open()))
    assert len(rows)==len(frames)
    for a,b in zip(rows,frames):
        for key in ("round","start_ns","publish_ns","duration_ns"): assert int(a[key])==b[key]
        assert a["raw_frame"].upper()==a["expected_frame"].upper()==b["raw_frame"]
    rows=list(csv.DictReader((folder/"transactions.csv").open()))
    assert len(rows)==len(transactions)
    for a,b in zip(rows,transactions):
        for key in ("round","channel","start_ns","end_ns"): assert int(a[key])==b[key]
        assert a["status"]==b["status"] and int(a["rises"])==len(b["rises"]) and int(a["falls"])==len(b["falls"])
        if b["status"]=="normal": assert int(a["command"],16)==num(b["tx"]) and int(a["payload"],16)==num(b["rx"])
    return {"status":"PASS","scan_attempts":len(rounds),"published_frames":len(frames),
            "spi_transactions":len(transactions),"reset_aborted_transactions":1,
            "scan_period_ns":sorted(set(periods)),"frame_durations_ns":sorted({f["duration_ns"] for f in frames}),
            "CH7_CS_end_to_publication_ns":sorted(set(publish_delays)),
            "frame_valid_width_ns":20,"min_cs_gap_ns":min(gaps),"atomic_CH4_checks":atomic,"frames":frames}


def faults(folder):
    attempts=[]; completed=[]; errors=[]; req_count=0; active=None; pulse=None; tp=None; last_round=None
    expected_count=0; last_frame=0; last_channel=0
    for t,old,s,c in vcd_states(folder/"faults.vcd"):
        rise=lambda n: old.get(n)=="0" and s.get(n)=="1"
        fall=lambda n: old.get(n)=="1" and s.get(n)=="0"
        if s.get("rst_n")!="1": continue
        if rise("scan_start"):
            assert active is None and s["scan_busy"]=="1"
            if last_round is not None: assert t-last_round in (1000000,2000000)
            last_round=t; active=t; last_channel=0; attempts.append(t)
        if rise("spi_start"):
            assert active is not None and s["spi_busy"]=="0" and num(s["spi_channel"])==last_channel
            last_channel+=1; req_count+=1
        if rise("frame_valid"):
            assert active is not None and last_channel==8 and s["scan_busy"]=="0"
            assert s["timeout"]=="0" and s["spi_abort"]=="0"
            completed.append(t); pulse=t; active=None; last_frame=num(s["raw_frame"])
        if fall("frame_valid"): assert t-pulse==20; pulse=None
        if rise("timeout"):
            assert active is not None and t-active==1000000
            expected_count+=1
            assert num(s["timeout_count"])==expected_count and s["spi_abort"]=="1"
            assert s["frame_valid"]==s["scan_busy"]==s["scan_start"]==s["spi_start"]=="0"
            assert num(s["raw_frame"])==last_frame
            if expected_count==3: assert old["spi_valid"]=="1" and old["spi_channel"] in ("111",), "CH7 deadline collision not exercised"
            errors.append(t); tp=t; active=None
        if fall("timeout"): assert t-tp==20; tp=None
        assert s.get("timeout")==s.get("spi_abort"), "Abort and timeout must coincide"
        if "raw_frame" in c and old.get("raw_frame")!=s["raw_frame"]: assert rise("frame_valid")
    assert len(attempts)==7 and len(completed)==4 and len(errors)==3 and expected_count==3
    assert req_count==44 # 4*8 + 4 requests in CH3 stall + 8 in deadline case.
    rows=list(csv.DictReader((folder/"fault_events.csv").open()))
    for event,ts in [("SCAN",attempts),("FRAME",completed),("TIMEOUT",errors)]:
        assert [int(r["time_ns"]) for r in rows if r["event"]==event]==ts
    return {"status":"PASS","attempts":attempts,"publications":completed,"timeouts":errors,
            "timeout_count":expected_count,"request_count":req_count,
            "timeout_pulse_width_ns":20,"deadline_collision":"CH7 valid discarded at exact 1ms deadline"}


def verify(folder):
    folder=Path(folder)
    result={"integrated":integrated(folder/"integrated"),"faults":faults(folder/"faults")}
    (folder/"waveform_report.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")
    text=["PASS independent VCD assertions and CSV cross-check"]
    for name,report in result.items():
        text.append(name.upper())
        for k,v in report.items():
            if k not in ("frames","atomic_CH4_checks"): text.append(f"{k}={v}")
    (folder/"waveform_report.txt").write_text("\n".join(text)+"\n",encoding="utf-8")
    print("\n".join(text))
    return result


if __name__=="__main__":
    import sys
    verify(sys.argv[1])
