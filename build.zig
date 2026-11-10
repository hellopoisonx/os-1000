const std = @import("std");

const qemu = "qemu-system-riscv32";

pub fn build(b: *std.Build) void {
    const riscv32 = b.resolveTargetQuery(.{
        .cpu_arch = .riscv32,
        .os_tag = .freestanding,
        .abi = .none,
        // 原书 --target=riscv32-unknown-elf: rv32i+mac, 软浮点 ilp32
        .cpu_model = .{ .explicit = &std.Target.riscv.cpu.baseline_rv32 },
        .cpu_features_sub = std.Target.riscv.featureSet(&.{ .f, .d }),
    });

    const opt: std.builtin.OptimizeMode = .ReleaseFast;

    // ---- shell (user application) ----
    const shell = b.addExecutable(.{
        .name = "shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shell.zig"),
            .target = riscv32,
            .optimize = opt,
            .stack_protector = false,
            .stack_check = false,
            .unwind_tables = .none,
        }),
    });
    shell.entry = .disabled; // ENTRY(start) in user.ld
    shell.linker_script = b.path("user.ld");

    const shell_check = b.addExecutable(.{
        .name = "shell",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shell.zig"),
            .target = riscv32,
            .optimize = opt,
            .stack_protector = false,
            .stack_check = false,
            .unwind_tables = .none,
        }),
    });
    shell_check.entry = .disabled; // ENTRY(start) in user.ld
    shell_check.linker_script = b.path("user.ld");

    // shell.elf → shell.bin（原始二进制，从 0x1000000 展开的实际内存内容）
    const objcopy_bin = b.addSystemCommand(&.{
        "llvm-objcopy",
        "--set-section-flags",
        ".bss=alloc,contents",
        "-O",
        "binary",
    });
    objcopy_bin.addArtifactArg(shell);
    const shell_bin = objcopy_bin.addOutputFileArg("shell.bin");

    // shell.bin → shell.bin.o（可链接的 ELF 对象，导出 _binary_shell_bin_* 符号）
    // setCwd 到 shell.bin 所在目录，使 llvm-objcopy 生成相对路径符号名
    const objcopy_obj = b.addSystemCommand(&.{
        "llvm-objcopy",
        "-I",
        "binary",
        "-O",
        "elf32-littleriscv",
    });
    objcopy_obj.setCwd(shell_bin.dirname());
    objcopy_obj.addArg("shell.bin"); // 相对路径输入
    const shell_bin_o = objcopy_obj.addOutputFileArg("shell.bin.o");

    // ---- kernel ----
    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel.zig"),
            .target = riscv32,
            .optimize = opt,
            .stack_protector = false,
            .stack_check = false,
            .unwind_tables = .none,
        }),
    });
    exe.entry = .disabled; // ENTRY(boot) in kernel.ld
    exe.linker_script = b.path("kernel.ld"); // -Wl,-Tkernel.ld
    exe.root_module.addObjectFile(shell_bin_o);
    b.installArtifact(exe);

    const exe_check = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/kernel.zig"),
            .target = riscv32,
            .optimize = opt,
            .stack_protector = false,
            .stack_check = false,
            .unwind_tables = .none,
        }),
    });
    exe_check.entry = .disabled; // ENTRY(boot) in kernel.ld
    exe_check.linker_script = b.path("kernel.ld");
    exe_check.root_module.addObjectFile(shell_bin_o);

    // keep intermediates inspectable: shell.elf (symbols) + shell.bin + shell.bin.o
    b.installArtifact(shell);
    const install_shell_bin = b.addInstallFile(shell_bin, "bin/shell.bin");
    const install_shell_bin_o = b.addInstallFile(shell_bin_o, "bin/shell.bin.o");
    b.getInstallStep().dependOn(&install_shell_bin.step);
    b.getInstallStep().dependOn(&install_shell_bin_o.step);

    // disk/ → disk.tar（ustar，QEMU 以 raw 格式挂到 virtio-blk）
    const tar_disk = b.addSystemCommand(&.{
        "sh",
        "-c",
        "cd disk && tar cf ../disk.tar --format=ustar *.txt",
    });

    const run_cmd = b.addSystemCommand(&.{
        qemu,
        "-machine",
        "virt",
        "-bios",
        "default",
        "-nographic",
        "-serial",
        "mon:stdio",
        "--no-reboot",
        "-d",
        "unimp,guest_errors,int,cpu_reset",
        "-D",
        "qemu.log",
        "-drive",
        "id=drive0,file=disk.tar,format=raw,if=none",
        "-device",
        "virtio-blk-device,drive=drive0,bus=virtio-mmio-bus.0",
        "-kernel",
    });
    run_cmd.addArtifactArg(exe);
    run_cmd.step.dependOn(&tar_disk.step);
    b.step("run", "boot kernel on qemu-riscv32 virt").dependOn(&run_cmd.step);

    exe_check.step.dependOn(&shell_check.step);

    const check = b.step("check", "check if too compoiles");
    check.dependOn(&exe_check.step);
}
