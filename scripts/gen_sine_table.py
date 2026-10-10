"""生成 1024 点、16 位补码、峰值 8000 的单周期正弦波表。"""

import math
from pathlib import Path


POINT_COUNT = 1024
AMPLITUDE = 8000

# 根据脚本自身的位置找到项目根目录，不依赖终端当前目录。
PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_PATH = PROJECT_ROOT / "tables" / "sine_1024_16bit.hex"


def main():
    samples = [
        round(AMPLITUDE * math.sin(2 * math.pi * k / POINT_COUNT))
        for k in range(POINT_COUNT)
    ]

    assert len(samples) == 1024
    assert [samples[k] for k in (0, 256, 512, 768)] == [0, 8000, 0, -8000]
    assert all(-32768 <= value <= 32767 for value in samples)

    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT_PATH.open("w", encoding="ascii", newline="\n") as table_file:
        for value in samples:
            # 负数按 16 位补码编码；每行恰好四个十六进制数字。
            table_file.write(f"{value & 0xFFFF:04X}\n")

    print(f"Generated: {OUTPUT_PATH}")
    print(f"Points: {POINT_COUNT}, amplitude: {AMPLITUDE}, width: 16 bits")
    for address in (0, 256, 512, 768):
        print(f"address={address:4d}, signed={samples[address]:6d}, hex={samples[address] & 0xFFFF:04X}")


if __name__ == "__main__":
    main()
