const common = @import("common.zig");
extern const __stack_top: anyopaque;

fn syscall(sysno: common.Sysno, arg0: isize, arg1: isize, arg2: isize) usize {
    return asm volatile (
        \\ecall
        : [ret] "={a0}" (-> usize),
        : [arg0] "{a0}" (arg0),
          [arg1] "{a1}" (arg1),
          [arg2] "{a2}" (arg2),
          [sysno] "{a3}" (sysno),
        : .{ .memory = true });
}

pub export fn exit() void {
    _ = syscall(.exit, 0, 0, 0);
}

pub export fn putchar(ch: u8) void {
    _ = syscall(.putchar, ch, 0, 0);
}

pub export fn getchar() isize {
    return @bitCast(syscall(.getchar, 0, 0, 0));
}

pub export fn start() linksection(".text.start") callconv(.naked) noreturn {
    asm volatile (
        \\mv sp, %[stack_top]
        \\call main
        \\call exit
        :
        : [stack_top] "r" (&__stack_top),
    );
    unreachable;
}
