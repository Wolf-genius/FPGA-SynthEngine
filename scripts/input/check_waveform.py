"""Independent assertions over external-pin VCD, with dynamically resolved IDs."""
import csv
import json
import re
from pathlib import Path


def verify(folder):
    folder = Path(folder)
    source = folder / "adc_spi.vcd"
    names, state, frames, valids = {}, {}, [], []
    pending = None
    active = None
    awaiting = None
    last_cs_end = None
    last_mosi = 0
    last_rise = None
    last_clk = None
    last_fall = None
    min_setup, min_hold, delays = [], [], set()
    pulse = None
    canceled = []
    reset_count = 0
    scale_ns = None

    def number(v):
        assert v is not None and not re.search("[xz]", v), f"Unknown numeric value {v}"
        return int(v, 2)

    def flush(t, changes):
        nonlocal pending, active, awaiting, last_cs_end, last_mosi, last_rise
        nonlocal last_clk, last_fall, pulse, reset_count
        old = state.copy()
        state.update(changes)
        ns = t * scale_ns
        # VCD time steps here are integral nanoseconds, including async resets.
        assert ns == int(ns), f"Unexpected sub-ns event {ns}"
        ns = int(ns)
        rise = lambda name: old.get(name) == "0" and state.get(name) == "1"
        fall = lambda name: old.get(name) == "1" and state.get(name) == "0"
        reset = state.get("rst_n") == "0"

        if rise("clk"):
            if last_clk is not None:
                assert ns-last_clk == 20, "Main clock period"
            last_clk = ns
            if old.get("rst_n") == "1" and old.get("start") == "1" and old.get("busy") == "0":
                assert pending is None, "Overlapping request"
                pending = {"channel": number(old["channel"]), "request_ns": ns}

        if fall("cs_n"):
            assert not reset and state["busy"] == "1" and state["sclk"] == "0"
            assert pending is not None, "CS without accepted request"
            gap = None if last_cs_end is None else ns-last_cs_end
            assert gap is None or gap >= 2000, f"CS high gap {gap}ns"
            active = {"id": len(frames)+1, "start_ns": ns, "gap_ns": gap,
                      "channel": pending["channel"], "rises": [], "falls": [],
                      "mosi": "", "miso": "", "prefix": "", "published": False}
            last_fall = None

        if rise("sclk"):
            assert not reset and state["cs_n"] == "0" and active is not None
            n = len(active["rises"])+1
            if n == 1:
                assert ns-active["start_ns"] == 1000, "CS setup"
            else:
                assert ns-active["falls"][-1] == 1000, "SCLK low half"
            assert state["mosi"] in ("0", "1")
            assert ns-last_mosi >= 50, "MOSI setup"
            min_setup.append(ns-last_mosi)
            active["rises"].append(ns)
            active["mosi"] += state["mosi"]
            if n <= 11:
                assert state["miso"] == "x", "Unknown prefix must be ignored"
                active["prefix"] += "x"
            elif n == 12:
                assert state["miso"] == "0", "Null bit"
            else:
                assert state["miso"] in ("0", "1"), "Unknown data bit"
                active["miso"] += state["miso"]
            last_rise = ns

        if fall("sclk") and not reset:
            assert active is not None and state["cs_n"] == "0"
            assert ns-active["rises"][-1] == 1000, "SCLK high half"
            active["falls"].append(ns)
            last_fall = ns

        if "mosi" in changes and old.get("mosi") != state["mosi"]:
            if not reset and active is not None:
                assert state["sclk"] == "0", "MOSI change while SCLK high"
                if last_rise is not None:
                    assert ns-last_rise >= 50, "MOSI hold"
                    min_hold.append(ns-last_rise)
            last_mosi = ns

        if "miso" in changes and old.get("miso") != state["miso"]:
            if not reset and active is not None and state["cs_n"] == "0" and last_fall is not None:
                actual = ns-last_fall
                assert actual == number(state["dout_delay_ns"]), f"DOUT delay {actual}"
                delays.add(actual)

        if rise("cs_n") and active is not None:
            active["end_ns"] = ns
            active["status"] = "reset_abort" if reset else "normal"
            if not reset:
                assert len(active["rises"]) == len(active["falls"]) == 24, "24 complete clocks"
                assert state["sclk"] == "0"
                assert ns-active["falls"][-1] == 1000, "Final CS hold"
                cmd = number(active["mosi"])
                assert cmd == 0x060000 | (active["channel"] << 14), "MOSI command/channel latch"
                active["command"] = f"{cmd:06X}"
                active["payload"] = f"{number(active['miso']):03X}"
                awaiting = active
            frames.append(active)
            active = None
            last_cs_end = ns

        if fall("rst_n"):
            reset_count += 1
            if awaiting is not None:
                canceled.append(awaiting["id"])
                awaiting = None
            pending = None
            assert all(state.get(n) == "0" for n in ("sclk", "mosi", "busy", "valid"))
            assert state["cs_n"] == "1" and number(state["data"]) == 0

        if rise("valid"):
            assert awaiting is not None and pending is not None, "Unmatched valid"
            assert state["busy"] == "0" and state["cs_n"] == "1" and state["sclk"] == "0"
            assert ns-awaiting["end_ns"] == 2000, "Publication after CS-high gap"
            assert number(state["data"]) == number(awaiting["miso"]), "Published payload"
            awaiting["published"] = True
            pulse = {"frame": awaiting["id"], "time_ns": ns,
                     "data": f"{number(state['data']):03X}"}
            valids.append(pulse)
            awaiting = None
            pending = None
        if fall("valid") and not reset:
            assert pulse is not None and ns-pulse["time_ns"] == 20, "valid width"
            pulse["width_ns"] = ns-pulse["time_ns"]
            pulse = None

        if "data" in changes and old.get("data") != state["data"] and not reset:
            assert rise("valid"), "data changed without publication"
        if not reset and state.get("sclk") == "1":
            assert state["cs_n"] == "0", "Clock outside selected transaction"
        if not reset and pending is not None:
            assert state["busy"] == "1", "busy dropped before completion"

    with source.open(encoding="ascii") as stream:
        header = ""
        for line in stream:
            header += line
            if line.startswith("$var "):
                parts = line.split()
                names[parts[3]] = parts[4]
            if "$enddefinitions" in line:
                break
        m = re.search(r"\$timescale\s+(\d+)\s*(s|ms|us|ns|ps|fs)\s+\$end", header)
        assert m, "Missing timescale"
        scale_ns = int(m[1])*{"s":1e9,"ms":1e6,"us":1e3,"ns":1,"ps":.001,"fs":.000001}[m[2]]
        assert set(names.values()) >= {"clk","rst_n","start","channel","miso","cs_n","sclk","mosi","busy","data","valid","dout_delay_ns"}
        t, changes = 0, {}
        for line in stream:
            line = line.strip()
            if line.startswith("#"):
                flush(t, changes)
                t, changes = int(line[1:]), {}
            elif line.startswith("b"):
                value, ident = line[1:].split()
                changes[names[ident]] = value
            elif line and line[0] in "01xz":
                changes[names[line[1:]]] = line[0]
        flush(t, changes)

    rows = list(csv.DictReader((folder/"transactions.csv").open(encoding="utf-8")))
    assert len(rows) == len(frames) == 37
    for row, frame in zip(rows, frames):
        assert int(row["id"]) == frame["id"]
        assert row["status"] == frame["status"]
        assert int(row["start_ns"]) == frame["start_ns"] and int(row["end_ns"]) == frame["end_ns"]
        assert int(row["rises"]) == len(frame["rises"])
        # Reset may force SCLK low immediately; it is not a protocol falling edge.
        assert int(row["falls"]) == len(frame["falls"])
        if frame["status"] == "normal":
            assert row["command"].upper() == frame["command"]
            assert row["miso_payload"].upper() == frame["payload"]
    assert pending is None and active is None and awaiting is None and pulse is None
    assert len(valids) == 31 and canceled == [30] and reset_count == 6
    assert sum(f["status"] == "reset_abort" for f in frames) == 5
    assert delays == {0,199,200,800}
    report = {
        "status":"PASS", "source":"adc_spi.vcd (external pins only)",
        "transactions":len(frames), "complete_spi_frames":32,
        "reset_aborted_spi_frames":5, "gap_reset_canceled_frame_ids":canceled,
        "published_results":len(valids), "valid_width_ns":sorted({v["width_ns"] for v in valids}),
        "main_clock_period_ns":20, "sclk_half_period_ns":1000, "sclk_frequency_hz":500000,
        "cs_setup_ns":1000, "cs_final_hold_ns":1000,
        "min_cs_high_gap_ns":min(f["gap_ns"] for f in frames if f["gap_ns"] is not None),
        "mosi_setup_min_ns":min(min_setup), "mosi_hold_min_ns":min(min_hold),
        "observed_dout_transition_delays_ns":sorted(delays),
        "frames":frames, "valid_pulses":valids
    }
    (folder/"waveform_report.json").write_text(json.dumps(report, indent=2)+"\n", encoding="utf-8")
    lines = ["PASS independent VCD assertions and CSV cross-check",
             *[f"{k}={v}" for k,v in report.items() if k not in ("frames","valid_pulses")],
             "FRAMES: id status channel command payload start_ns end_ns gap_ns published"]
    for f in frames:
        lines.append(f"{f['id']} {f['status']} CH{f['channel']} {f.get('command','partial')} {f.get('payload','partial')} {f['start_ns']} {f['end_ns']} {f['gap_ns']} {f['published']}")
    (folder/"waveform_report.txt").write_text("\n".join(lines)+"\n", encoding="utf-8")
    print("\n".join(lines[:21]))
    return report


if __name__ == "__main__":
    import sys
    verify(sys.argv[1] if len(sys.argv)>1 else ".")
