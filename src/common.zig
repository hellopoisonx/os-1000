const std = @import("std");

extern fn putchar(ch: u8) void;

pub const PAddr = u32;
pub const VAddr = u32;

pub const page_size = 4096;

pub const Sysno = enum(usize) {
    putchar = 1,
    getchar = 2,
    exit = 3,
};

pub inline fn check_args(args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }
}

pub fn memset(buf: [*]u8, c: u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        buf[i] = c;
    }
    return buf;
}

pub fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) {
        dst[i] = src[i];
    }
    return dst;
}

pub fn strcpy(dst: [*:0]u8, src: [*:0]const u8) [*:0]u8 {
    var i: usize = 0;
    while (src[i] != 0) : (i += 1) {
        dst[i] = src[i];
    }
    dst[i] = 0;
    return dst;
}

pub fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) i32 {
    var i: usize = 0;
    while (s1[i] != 0 and s2[i] != 0) : (i += 1) {
        if (s1[i] != s2[i]) break;
    }
    return @as(i32, s1[i]) - @as(i32, s2[i]);
}

pub fn printf(comptime fmt: []const u8, args: anytype) void {
    check_args(args);

    comptime var i: usize = 0;
    comptime var arg_i: usize = 0;
    inline while (i < fmt.len) : (i += 1) {
        if (fmt[i] != '%') {
            putchar(fmt[i]);
            continue;
        }

        i += 1;
        if (i >= fmt.len) {
            putchar('%');
            break;
        }
        if (fmt[i] == '%') {
            putchar('%');
            continue;
        }

        const arg = args[arg_i];
        arg_i += 1;
        switch (fmt[i]) {
            's' => printStr(arg),
            'd' => printDec(arg),
            'x' => printHex(arg),
            else => @compileError("unsupported format specifier"),
        }
    }
}

fn printStr(s: []const u8) void {
    for (s) |ch| {
        putchar(ch);
    }
}

fn printDec(value: anytype) void {
    const v: i32 = @intCast(value);
    const magnitude: u32 = if (v < 0) @abs(v) else @intCast(v);
    if (v < 0) {
        putchar('-');
    }

    var divisor: u32 = 1;
    while (magnitude / divisor > 9) {
        divisor *= 10;
    }

    var rest = magnitude;
    while (divisor > 0) : (divisor /= 10) {
        putchar('0' + @as(u8, @intCast(rest / divisor)));
        rest %= divisor;
    }
}

fn printHex(value: anytype) void {
    const v: u32 = @intCast(value);
    var i: usize = 8;
    while (i > 0) {
        i -= 1;
        const nibble: u8 = @intCast((v >> @intCast(i * 4)) & 0xf);
        putchar("0123456789abcdef"[nibble]);
    }
}

pub inline fn panic(comptime src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) noreturn {
    printf("PANIC: %s:%d: " ++ fmt ++ "\n", .{ src.file, src.line } ++ args);
    while (true) {}
}
