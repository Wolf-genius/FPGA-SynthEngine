# 输入仿真

2026-10-14新增：

- `tb_controls.sv`：22,437拍独立Python参考向量与公开输出逐拍比较；4096种原始码升降遍历、滞回噪声、稳定计数、持续力度、复位、打包及接收同沿规则。
- `tb_input_examples.sv`：真实封装的外部SPI闭环（模型DOUT延迟200ns），9帧检查1ms周期、CH0命令和24拍、状态/力度、复位；同时检查假控制序列。
- `mcp3208_model.sv`：从公开SPI引脚解析命令并按通道返回数据，不读取DUT内部状态。

Windows本机使用Icarus12 devel分阶段编译，脚本清除继承的IVERILOG_ICONFIG，每步检查退出码，失败产物不执行。安装其他路径时通过参数指定：

```powershell
python scripts/input/run_controls.py --iverilog D:/iverilog/bin/iverilog.exe --vvp D:/iverilog/bin/vvp.exe
```

必须同时保留脚本、TB、examples和RTL的仓库目录结构；vectors.txt由脚本自动生成。完整证据每次新建于`sim_build/input/verified_时间戳/`（Git忽略），包括工具版本、所有命令/退出码、源码哈希、CSV及VCD。本次提交的清单和完整文本日志另见`results/`。最终两组均PASS；功能仿真不替代综合、时序或实物验收，不证明常规Icarus外层故障已恢复。TB/model不加入Gowin综合列表。

B的MCP3208模型、SPI位序/八通道、1ms扫描、完整控制帧、逐键校准/滞回/平滑、功能键同步消抖testbench。检查gate[7:0]、key_gain[127:0]顺序和controls_valid；仿真不能替代真实校准。

仿真文件不入综合。结果填[记录](../../docs/交接与验收记录.md)。
