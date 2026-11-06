const common = @import("common.zig");

var buf: [8]u8 = undefined;
var buf2: [8]u8 = undefined;
var s: [6]u8 = undefined;

extern const __stack_top: anyopaque;
extern const __bss: anyopaque;
extern const __bss_end: anyopaque;
extern const __free_ram: anyopaque;
extern const __free_ram_end: anyopaque;

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

export fn putchar(ch: u8) void {
    _ = sbi_call(ch, 0, 0, 0, 0, 0, 0, 1);
}

inline fn clearBss() void {
    const start_addr = @intFromPtr(&__bss);
    const end_addr = @intFromPtr(&__bss_end);
    const bss_len = end_addr - start_addr;

    if (bss_len == 0) {
        return;
    }

    const bss_ptr: [*]u8 = @ptrCast(@constCast(&__bss));
    _ = common.memset(bss_ptr, 0, bss_len);
}

export fn kernel_main() callconv(.c) noreturn {
    clearBss();

    const paddr0 = alloc_pages(2);
    const paddr1 = alloc_pages(1);
    common.printf("alloc_page test: paddr0=%x\n", .{paddr0});
    common.printf("alloc_page test: paddr1=%x\n", .{paddr1});

    writeCsr("stvec", @intFromPtr(&kernel_entry));
    asm volatile ("unimp");

    common.printf("\n\nHello %s!\n", .{"World"});
    common.printf("1 + 2 = %d, %x\n", .{ 1 + 2, 0x1234abcd });

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

export fn kernel_entry() align(4) callconv(.naked) void {
    asm volatile (
        \\csrw sscratch, sp
        \\addi sp, sp, -4 * 31
        \\sw ra,  4 * 0(sp)
        \\sw gp,  4 * 1(sp)
        \\sw tp,  4 * 2(sp)
        \\sw t0,  4 * 3(sp)
        \\sw t1,  4 * 4(sp)
        \\sw t2,  4 * 5(sp)
        \\sw t3,  4 * 6(sp)
        \\sw t4,  4 * 7(sp)
        \\sw t5,  4 * 8(sp)
        \\sw t6,  4 * 9(sp)
        \\sw a0,  4 * 10(sp)
        \\sw a1,  4 * 11(sp)
        \\sw a2,  4 * 12(sp)
        \\sw a3,  4 * 13(sp)
        \\sw a4,  4 * 14(sp)
        \\sw a5,  4 * 15(sp)
        \\sw a6,  4 * 16(sp)
        \\sw a7,  4 * 17(sp)
        \\sw s0,  4 * 18(sp)
        \\sw s1,  4 * 19(sp)
        \\sw s2,  4 * 20(sp)
        \\sw s3,  4 * 21(sp)
        \\sw s4,  4 * 22(sp)
        \\sw s5,  4 * 23(sp)
        \\sw s6,  4 * 24(sp)
        \\sw s7,  4 * 25(sp)
        \\sw s8,  4 * 26(sp)
        \\sw s9,  4 * 27(sp)
        \\sw s10, 4 * 28(sp)
        \\sw s11, 4 * 29(sp)
        \\
        \\csrr a0, sscratch
        \\sw a0, 4 * 30(sp)
        \\
        \\mv a0, sp
        \\call handle_trap
        \\
        \\lw ra,  4 * 0(sp)
        \\lw gp,  4 * 1(sp)
        \\lw tp,  4 * 2(sp)
        \\lw t0,  4 * 3(sp)
        \\lw t1,  4 * 4(sp)
        \\lw t2,  4 * 5(sp)
        \\lw t3,  4 * 6(sp)
        \\lw t4,  4 * 7(sp)
        \\lw t5,  4 * 8(sp)
        \\lw t6,  4 * 9(sp)
        \\lw a0,  4 * 10(sp)
        \\lw a1,  4 * 11(sp)
        \\lw a2,  4 * 12(sp)
        \\lw a3,  4 * 13(sp)
        \\lw a4,  4 * 14(sp)
        \\lw a5,  4 * 15(sp)
        \\lw a6,  4 * 16(sp)
        \\lw a7,  4 * 17(sp)
        \\lw s0,  4 * 18(sp)
        \\lw s1,  4 * 19(sp)
        \\lw s2,  4 * 20(sp)
        \\lw s3,  4 * 21(sp)
        \\lw s4,  4 * 22(sp)
        \\lw s5,  4 * 23(sp)
        \\lw s6,  4 * 24(sp)
        \\lw s7,  4 * 25(sp)
        \\lw s8,  4 * 26(sp)
        \\lw s9,  4 * 27(sp)
        \\lw s10, 4 * 28(sp)
        \\lw s11, 4 * 29(sp)
        \\lw sp,  4 * 30(sp)
        \\sret
    );
}

export fn handle_trap(f: *TrapFrame) noreturn {
    _ = f;

    const scause = readCsr("scause");
    const stval = readCsr("stval");
    const sepc = readCsr("sepc");

    common.panic(@src(), "unexpected trap scause=%x, stval=%x, sepc=%x", .{ scause, stval, sepc });
}

const TrapFrame = packed struct {
    ra: u32,
    gp: u32,
    tp: u32,
    t0: u32,
    t1: u32,
    t2: u32,
    t3: u32,
    t4: u32,
    t5: u32,
    t6: u32,
    a0: u32,
    a1: u32,
    a2: u32,
    a3: u32,
    a4: u32,
    a5: u32,
    a6: u32,
    a7: u32,
    s0: u32,
    s1: u32,
    s2: u32,
    s3: u32,
    s4: u32,
    s5: u32,
    s6: u32,
    s7: u32,
    s8: u32,
    s9: u32,
    s10: u32,
    s11: u32,
    sp: u32,
};

inline fn readCsr(comptime reg: []const u8) u32 {
    return asm ("csrr %[ret], " ++ reg
        : [ret] "=r" (-> u32),
    );
}

inline fn writeCsr(comptime reg: []const u8, value: u32) void {
    asm volatile ("csrw " ++ reg ++ ", %[value]"
        :
        : [value] "r" (value),
    );
}

fn alloc_pages(n: u32) common.PAddr {
    const S = struct {
        var next_paddr: ?usize = null;
    };

    if (S.next_paddr == null) {
        S.next_paddr = @intFromPtr(&__free_ram);
    }

    const free_ram_end = @intFromPtr(&__free_ram_end);
    const paddr: [*]u8 = @ptrFromInt(S.next_paddr.?);
    S.next_paddr.? += n * common.page_size;

    if (S.next_paddr.? > free_ram_end) {
        common.panic(@src(), "out of memory", .{});
    }

    _ = common.memset(paddr, 0, n * common.page_size);

    return @intFromPtr(paddr);
}
