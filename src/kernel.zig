const common = @import("common.zig");

var buf: [8]u8 = undefined;
var buf2: [8]u8 = undefined;
var s: [6]u8 = undefined;

extern const __stack_top: anyopaque;
extern const __bss: anyopaque;
extern const __bss_end: anyopaque;
extern const __free_ram: anyopaque;
extern const __free_ram_end: anyopaque;
extern const _binary_shell_bin_start: anyopaque;
extern const _binary_shell_bin_size: anyopaque;

pub const user_base = 0x1000000;
pub const sstatus_spie = 1 << 5;
const scause_ecall = 8;

const SbiRet = struct {
    err: isize,
    value: isize,
};

const procs_max = 8;

var current_proc: ?*Process = null;
var idle_proc: ?*Process = null;

pub const Process = struct {
    pid: usize = 0,
    state: enum {
        unused,
        runnable,
        exited,
    } = .unused,
    sp: common.VAddr = 0,
    page_table: [*]u32 = undefined,
    stack: [8 * 1024 / 4]u32 = undefined, // 8 KiB 内核栈
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

export fn getchar() isize {
    const ret = sbi_call(0, 0, 0, 0, 0, 0, 0, 2);
    return ret.err;
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

fn delay() void {
    var i: u32 = 0;
    while (i < 30_000_000) : (i += 1) {
        asm volatile ("nop");
    }
}

fn proc_a_entry() noreturn {
    common.printf("starting process A\n", .{});
    while (true) {
        putchar('A');
        yield();
        delay();
    }
}

fn proc_b_entry() noreturn {
    common.printf("starting process B\n", .{});
    while (true) {
        putchar('B');
        yield();
        delay();
    }
}

export fn kernel_main() callconv(.c) noreturn {
    clearBss();

    writeCsr("stvec", @intFromPtr(&kernel_entry));

    idle_proc = create_process(null, 0);
    idle_proc.?.pid = 0;
    current_proc = idle_proc;

    _ = create_process(@constCast(&_binary_shell_bin_start), @intFromPtr(&_binary_shell_bin_size));

    yield();
    common.panic(@src(), "switched to idle process", .{});
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
        \\csrrw sp, sscratch, sp
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
        \\addi a0, sp, 4 * 31
        \\csrw sscratch, a0
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

export fn handle_trap(f: *TrapFrame) void {
    const scause = readCsr("scause");
    const stval = readCsr("stval");
    var sepc = readCsr("sepc");

    switch (scause) {
        scause_ecall => {
            handle_syscall(f);
            sepc += 4;
        },
        else => {
            common.panic(@src(), "unexpected trap scause=%x, stval=%x, sepc=%x", .{ scause, stval, sepc });
        },
    }

    writeCsr("sepc", sepc);
}

fn handle_syscall(f: *TrapFrame) void {
    switch (f.a3) {
        @backingInt(common.Sysno.putchar) => {
            putchar(@truncate(f.a0));
        },
        @backingInt(common.Sysno.getchar) => {
            while (true) {
                const ch = getchar();
                if (ch >= 0) {
                    f.a0 = @intCast(ch);
                    break;
                }

                yield();
            }
        },
        @backingInt(common.Sysno.exit) => {
            common.printf("process %d exited\n", .{current_proc.?.pid});
            current_proc.?.state = .exited;
            yield();
            common.panic(@src(), "unreachable", .{});
        },
        else => common.panic(@src(), "unexpected syscall a3=%x", .{f.a3}),
    }
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

// naked 函数不能被 Zig 直接调用：导出符号，再按 extern 声明调用
extern fn switch_context(prev_sp: *u32, next_sp: *u32) void;

noinline fn switchContextNaked(prev_sp: *u32, next_sp: *u32) callconv(.naked) void {
    _ = prev_sp;
    _ = next_sp;

    asm volatile (
        \\addi sp, sp, -13 * 4
        \\sw ra,  0  * 4(sp)
        \\sw s0,  1  * 4(sp)
        \\sw s1,  2  * 4(sp)
        \\sw s2,  3  * 4(sp)
        \\sw s3,  4  * 4(sp)
        \\sw s4,  5  * 4(sp)
        \\sw s5,  6  * 4(sp)
        \\sw s6,  7  * 4(sp)
        \\sw s7,  8  * 4(sp)
        \\sw s8,  9  * 4(sp)
        \\sw s9,  10 * 4(sp)
        \\sw s10, 11 * 4(sp)
        \\sw s11, 12 * 4(sp)
        \\
        \\sw sp, (a0)
        \\lw sp, (a1)
        \\
        \\lw ra,  0  * 4(sp)
        \\lw s0,  1  * 4(sp)
        \\lw s1,  2  * 4(sp)
        \\lw s2,  3  * 4(sp)
        \\lw s3,  4  * 4(sp)
        \\lw s4,  5  * 4(sp)
        \\lw s5,  6  * 4(sp)
        \\lw s6,  7  * 4(sp)
        \\lw s7,  8  * 4(sp)
        \\lw s8,  9  * 4(sp)
        \\lw s9,  10 * 4(sp)
        \\lw s10, 11 * 4(sp)
        \\lw s11, 12 * 4(sp)
        \\addi sp, sp, 13 * 4
        \\ret
    );
}

comptime {
    @export(&switchContextNaked, .{ .name = "switch_context" });
}

pub var procs: [procs_max]Process = @splat(.{});

extern const __kernel_base: anyopaque;

fn user_entry() callconv(.naked) void {
    asm volatile (
        \\csrw sepc, %[sepc]
        \\csrw sstatus, %[sstatus]
        \\sret
        :
        : [sepc] "r" (user_base),
          [sstatus] "r" (sstatus_spie),
    );
}

fn create_process(image: ?*anyopaque, image_size: usize) *Process {
    for (&procs, 0..) |*p, i| {
        if (p.state != .unused) continue;

        // switch_context 首次恢复时按这段顺序弹出 ra 与 s0-s11
        const ctx: []u32 = p.stack[p.stack.len - 13 ..];
        @memset(ctx, 0);
        ctx[0] = @intFromPtr(&user_entry);

        const page_table: [*]u32 = @ptrFromInt(alloc_pages(1));

        var paddr: common.PAddr = @intFromPtr(@constCast(&__kernel_base));
        while (paddr < @intFromPtr(&__free_ram_end)) {
            map_page(page_table, paddr, paddr, page_r | page_w | page_x);
            paddr += common.page_size;
        }

        if (image) |valid_image| {
            const image_ptr: [*]u32 = @ptrCast(@alignCast(valid_image));
            var off: usize = 0;
            while (off < image_size) {
                const page = alloc_pages(1);
                const page_ptr: [*]u32 = @ptrFromInt(page);
                const remaining = image_size - off;
                const copy_size = if (remaining >= common.page_size) common.page_size else remaining;

                @memcpy(page_ptr, image_ptr[off .. off + copy_size]);
                map_page(
                    page_table,
                    user_base + off,
                    page,
                    page_u | page_r | page_w | page_x,
                );

                off += common.page_size;
            }
        }

        p.pid = i + 1;
        p.state = .runnable;
        p.sp = @intFromPtr(ctx.ptr);
        p.page_table = page_table;
        return p;
    }

    common.panic(@src(), "no free process slots", .{});
}

fn yield() void {
    const prev = current_proc orelse return;

    // 从当前进程之后开始轮转；一圈都没找到可运行进程就回退到 idle
    const next = for (0..procs_max) |i| {
        const proc = &procs[(prev.pid + i) % procs_max];
        if (proc.state == .runnable and proc.pid != 0) break proc;
    } else (idle_proc orelse return);

    if (next == current_proc) return;

    asm volatile (
        \\sfence.vma
        \\csrw satp, %[satp]
        \\sfence.vma
        \\csrw sscratch, %[sscratch]
        :
        : [satp] "r" (satp_sv32 | (@intFromPtr(next.page_table) / common.page_size)),
          [sscratch] "r" (&next.stack[next.stack.len - 1]),
    );

    current_proc = next;
    switch_context(&prev.sp, &next.sp);
}

const satp_sv32: usize = 1 << 31;
const page_v: usize = 1 << 0;
const page_r: usize = 1 << 1;
const page_w: usize = 1 << 2;
const page_x: usize = 1 << 3;
const page_u: usize = 1 << 4;

fn map_page(table1: [*]u32, vaddr: u32, paddr: common.PAddr, flags: u32) void {
    if (vaddr % common.page_size != 0) {
        common.panic(@src(), "unaligned vaddr %x", .{vaddr});
    }
    if (paddr % common.page_size != 0) {
        common.panic(@src(), "unaligned paddr %x", .{paddr});
    }

    const vpn1 = (vaddr >> 22) & 0x3ff;
    if (table1[vpn1] & page_v == 0) {
        const pt_paddr = alloc_pages(1);
        table1[vpn1] = (((pt_paddr / common.page_size) << 10)) | page_v;
    }

    const vpn0 = (vaddr >> 12) & 0x3ff;
    var table0: [*]u32 = @ptrFromInt((table1[vpn1] >> 10) * common.page_size);
    table0[vpn0] = ((paddr / common.page_size) << 10) | flags | page_v;
}
