extern const __stack_top: anyopaque;
extern const __bss: anyopaque;
extern const __bss_end: anyopaque;

const SbiRet = struct {
    err: isize,
    value: isize,
};

fn sbi_call(
    arg0: isize,
    arg1: isize,
    arg2: isize,
    arg3: isize,
    arg4: isize,
    arg5: isize,
    fid: isize,
    eid: isize,
) SbiRet {
    var err: isize = undefined;
    var value: isize = undefined;

    asm volatile ("ecall"
        : [err] "={a0}" (err),
          [value] "={a1}" (value),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [arg3] "{a3}" (arg3),
          [arg4] "{a4}" (arg4),
          [arg5] "{a5}" (arg5),
          [fid] "{a6}" (fid),
          [eid] "{a7}" (eid),
        : .{ .memory = true });

    return .{ .err = err, .value = value };
}

fn putchar(ch: u8) void {
    _ = sbi_call(ch, 0, 0, 0, 0, 0, 0, 1);
}

fn clearBss() void {
    const start_addr = @intFromPtr(&__bss);
    const end_addr = @intFromPtr(&__bss_end);
    const bss_len = end_addr - start_addr;

    if (bss_len == 0) {
        return;
    }

    const bss_ptr: [*]u8 = @ptrCast(@constCast(&__bss));
    const bss_slice = bss_ptr[0..bss_len];

    @memset(bss_slice, 0);
}

export fn kernel_main() callconv(.c) noreturn {
    clearBss();

    const s = "\n\nHello World!\n";

    for (s) |ch| {
        putchar(ch);
    }

    while (true) {
        asm volatile ("wfi");
    }
}

export fn boot() linksection(".text.boot") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top]
        \\j kernel_main
        :
        : [stack_top] "r" (&__stack_top),
    );
    unreachable;
}
