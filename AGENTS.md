# Repository Guidelines

用 Zig 0.17 复刻《Operating System in 1000 Lines》的 RISC-V 32 位裸机内核。
目标平台固定为 QEMU `virt`（RV32，S 态），由 OpenSBI 固件从 M 态下跳，内核镜像链接在 `0x80200000`。

## Project Overview

- 学习型项目：按教程章节逐步实现 引导 → SBI 输出 → 异常 → 内存分配 → 进程 → 分页 → 用户态/syscall → VirtIO 磁盘 → tar 文件系统。
- 目前止步于第 04 章（Boot）：栈初始化 + BSS 清零 + 空转主循环。**尚无任何串口/字符输出**，所以运行成功 = QEMU 打印 OpenSBI banner 后静默挂起。
- 单二进制、无 libc、无 `std` 运行时（`kernel.zig` 未 `@import("std")`）；不要引入标准库依赖假设。

## Architecture & Data Flow

```
OpenSBI (M态固件, 0x80000000)  --跳转 0x80200000-->  boot()  [.text.boot]
                                                      |  mv sp, __stack_top
                                                      v
                                                 kernel_main()
                                                      |  clearBss(__bss..__bss_end)
                                                      v
                                                  while (true) {}
```

- **链接脚本 = 契约**：`kernel.ld` 定义 `ENTRY(boot)`、基址 `0x80200000`、段排序（`.text.boot` 必须最前）、`__bss`/`__bss_end`、128 KiB 栈与 `__stack_top`。`kernel.zig` 通过 `extern const` 声明这些符号，用 `&symbol` 取地址（不要当值读取）。
- **进入内核的唯一约束**：OpenSBI 的 Domain0 Next Address 是 `0x80200000`，入口指令必须落在该地址，否则执行的是别的段数据（见下方已知问题 1）。
- 后续章节将扩展为：trap 入口（`stvec`，保存全部 31 个寄存器）→ 4 KiB 页分配器（`__free_ram`）→ `switch_context` 协作调度 → Sv32 页表 → 用户态 `sret` → `ecall` syscall 表 → VirtIO-blk（`0x10001000`）→ UStar tar。

## Key Directories

| 路径 | 用途 |
|---|---|
| `kernel.zig` | 内核全部代码（当前 33 行）。唯一源文件，新增功能按章节继续追加于此或新建模块 |
| `kernel.ld` | 链接脚本：布局、入口、BSS 边界、栈顶 |
| `build.zig` / `build.zig.zon` | 构建图；`minimum_zig_version = "0.17.0"` |
| `opensbi-riscv32-generic-fw_dynamic.bin` | 预编译 OpenSBI 固件（被 `.gitignore` 的 `*.bin` 忽略，未入库） |
| `disk/` | 教程后续章节的 VirtIO 磁盘内容（已 gitignore，仅保留 `.gitkeep`） |
| `.zig-cache/`, `zig-out/` | 构建缓存与产物，勿提交 |

## Development Commands

**构建**：

```bash
zig build          # → zig-out/bin/kernel
zig build run      # 构建并启动 QEMU
```

`build.zig` 对齐原书 §04 的 clang 选项：`--target=riscv32-unknown-elf` → `riscv32-freestanding-none` + `baseline_rv32` 减去 `f`/`d`（`-mcpu=baseline_rv32-f-d`，软浮点 `ilp32`）；`-ffreestanding -nostdlib` → freestanding；`-O2 -g3` → `.ReleaseFast`（默认不 strip）；`-fno-stack-protector` → `stack_protector = false`；`-Wl,-Tkernel.ld` → `exe.linker_script`；`-fno-entry` → `exe.entry = .disabled`；`-fno-stack-check` → `stack_check = false`；`unwind_tables = .none` → clang 的 `-fno-unwind-tables -fno-asynchronous-unwind-tables`（Zig 默认给每个函数生成 `.eh_frame`，lld 会把它排在 `.text` 之前，Entry 就变成 `0x80200074`，`kernel.ld` 里也没有对应输出段）。原书 `-Wl,-Map=kernel.map` 无对应 Build API，未生成 map 文件。

- `-mcpu=baseline_rv32-f-d` **不可省略**：`baseline_rv32` 自带 D 扩展 → ABI 为 `ilp32d`（硬浮点），内核需要软浮点 `ilp32`。

**直接运行（不经 build.zig）**：

```bash
qemu-system-riscv32 -machine virt -bios default -nographic \
  -serial mon:stdio --no-reboot -kernel zig-out/bin/kernel
```

`-bios default` 使用宿主 QEMU 自带固件（Arch: `/usr/share/qemu/opensbi-riscv32-generic-fw_dynamic.bin`）；仓库内 `.bin` 仅在需要固定固件版本时替换为 `-bios opensbi-riscv32-generic-fw_dynamic.bin`。退出 QEMU：`Ctrl-A` 然后 `X`。

**校验产物**（无需 QEMU 启动）：

```bash
riscv64-linux-gnu-readelf -h zig-out/bin/kernel | grep -E "Entry|Flags"  # 0x80200000 + soft-float ABI
riscv64-linux-gnu-objdump -d zig-out/bin/kernel | sed -n '1,10p'       # boot 应是 lui/addi/mv sp/j
```

## Code Conventions & Common Patterns

- **Zig 0.17 语法**：`@intFromPtr`（非 `@ptrToInt`）、`@memset`/`@memcpy`、`@ptrCast(@constCast(...))` 组合才能把 `*const anyopaque` 转成可写 `[*]u8`。写新 API 前先查 `skill://zig-0-17-docs` 或 `/usr/lib/zig/std`。
- **入口/导出**：`export fn` + C ABI（`kernel_main`），`boot` 用 `linksection(".text.boot") callconv(.naked)` 钉在 `.text.boot` 且不生成序言（`callconv(.naked)` 必须写在 `linksection` 之后）；跨汇编调用的函数保持 `export` 以免被裁掉。
- **`noreturn` 语义严格**：发散函数体必须以 `unreachable` / 无限循环 / `asm` 后的 `unreachable` 收尾，Zig 0.17 会在编译期拒绝隐式落底（`error: function declared 'noreturn' implicitly returns`）。
- **地址常量只有一种写法**：`extern const __sym: anyopaque;` + `&__sym`。不要给它真实类型，长度未知。
- **内联汇编**：`asm volatile (... : /*outputs*/ : [x] "r" (value));`，模板用 `\\` 逐行续写，RISC-V 指令直接写。修改 `sp`/CSR 的 asm 需要显式处理 clobber 与不返回路径。
- **按章节增量落地**：每个新机制（trap、paging）通常同时改 `kernel.ld`（新符号/段）与 `kernel.zig`（`extern` 声明 + 初始化），两边必须同步。
- 格式化一律 `zig fmt .`；无 `std` 运行时，不要写依赖分配器/线程的代码。

## Important Files

| 文件 | 作用 |
|---|---|
| `kernel.zig:26` | `boot()` — 唯一入口，`callconv(.naked)` 设置 `sp` 后跳 `kernel_main` |
| `kernel.zig:20` | `kernel_main()` — 内核主循环 |
| `kernel.zig:5` | `clearBss()` — 清零 `__bss..__bss_end` |
| `kernel.ld:5` | `. = 0x80200000`，与 OpenSBI 跳转地址耦合 |
| `kernel.ld:19-27` | `__bss`/`__bss_end`/`__stack_top` 定义；除栈顶 `ALIGN(16)`（psABI 要求 `sp` 16 字节对齐）外与原书一致，`boot` 落在 `0x80200000` 由 `unwind_tables = .none` 保证 |
| `build.zig:5-44` | 内核构建（目标/优化/链接脚本）与 QEMU 启动命令，新增设备（`-drive`/`-device virtio-blk-device`）在此扩展 |

## Runtime/Tooling Preferences

- Zig **0.17.0**（`/usr/bin/zig`），QEMU **11.1.3** `qemu-system-riscv32`，两者均已安装；版本不匹配会直接编译失败，改代码前先 `zig version`。
- 反汇编/查看符号：`riscv64-linux-gnu-objdump`、`riscv64-linux-gnu-readelf`、`llvm-objdump --arch-name=riscv32`。
- **没有 `gdb-multiarch`**：想用 `qemu -s -S` 调试需先安装；否则只能靠 `objdump` + OpenSBI 输出的 `-d unimplemented` 日志。
- 构建系统就是 `build.zig`（不是 Make/ninja），不要新增 Makefile 作为第二条构建路径。

## Testing & QA

- 无测试框架、无 CI、无覆盖率要求——这是裸机项目，验证方式是**启动 QEMU 观察行为**。
- 每次改动的最低验收：
  1. `zig build` 零错误、零警告；
  2. `readelf -h` 的 Entry 必须是 `0x80200000`；
  3. `zig build run` 启动后 OpenSBI banner 正常、无重复 reset / illegal instruction。
- 有输出后，验收改为比对串口文本；触发异常可用 `unimp`（`0x0000`）指令验证 trap 通路。
- 调试技巧：加 `-d guest_errors,unimp,int,cpu_reset -D qemu.log` 观察异常；`--no-reboot` 防止三重异常静默重启掩盖问题。

## Known Issues（截至当前提交，已验证）

1. `disk/`、`opensbi-*.bin` 在 `.gitignore` 中被忽略：固件与磁盘镜像不入库，换机器需重新获取。
