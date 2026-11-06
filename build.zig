const std = @import("std");

const qemu = "qemu-system-riscv32";

pub fn build(b: *std.Build) void {
    const exe = b.addExecutable(.{
        .name = "kernel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("kernel.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .riscv32,
                .os_tag = .freestanding,
                .abi = .none,
                // 原书 --target=riscv32-unknown-elf: rv32i+mac, 软浮点 ilp32
                .cpu_model = .{ .explicit = &std.Target.riscv.cpu.baseline_rv32 },
                .cpu_features_sub = std.Target.riscv.featureSet(&.{ .f, .d }),
            }),
            .optimize = .ReleaseFast, // -O2
            .stack_protector = false, // -fno-stack-protector
            .stack_check = false,
            .unwind_tables = .none, // 不生成 .eh_frame，保证 .text 落在 0x80200000
        }),
    });
    exe.entry = .disabled; // -fno-entry: ENTRY(boot) in kernel.ld
    exe.linker_script = b.path("kernel.ld"); // -Wl,-Tkernel.ld
    b.installArtifact(exe);

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
        "-kernel",
    });
    run_cmd.addArtifactArg(exe);
    b.step("run", "boot kernel on qemu-riscv32 virt").dependOn(&run_cmd.step);
}
