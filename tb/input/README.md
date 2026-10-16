# 输入仿真

## 四键输入仓库版回归（2026-10-16）

保留原一键测试，新加入tb_frames、tb_scan_controls、tb_fault_handoff、tb_fake_controls，以及SPI/扫描专项TB和公开引脚ADC模型。Python脚本位于scripts/input，按仓库根目录加载rtl/input、tb/input、examples/input，不依赖解压ZIP。完整输出保存在Git忽略的sim_build目录。

```powershell
python scripts/input/run_all.py --iverilog D:/iverilog/bin/iverilog.exe --vvp D:/iverilog/bin/vvp.exe
python scripts/input/run_four_keys_synthesis.py --gw-sh C:/Gowin/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe
```

运行需要Python3.9+、本机Icarus及Gowin（路径可以参数指定）。Icarus常规外层异常由独立探测记录，失败产物不执行；正式测试使用预处理器/ivl/vvp分阶段，逐步检查退出码。预期10项正常测试及2项非法参数拒绝全部通过，另做外部VCD断言和CSV独立整数参考比较。综合脚本只跑四/八键输入综合，不执行PnR、不生成FS。

版本来源清单见docs/input/four_keys/SOURCE_ORIGINS.json；原始包路径已映射到仓库路径，同版ADC/模型/接收器直接复用。12项回归和四/八键综合在本次仓库布局下重新执行，提交摘要/哈希/完整文本日志见results/20261016_four_keys/；原始ZIP保留独立可重跑版本。

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
