const std = @import("std");
const common = @import("common.zig");

extern const __stack_top: anyopaque;
extern const __bss: anyopaque;
extern const __bss_end: anyopaque;
extern const __free_ram: anyopaque;
extern const __free_ram_end: anyopaque;
extern const _binary_shell_bin_start: anyopaque;
extern const _binary_shell_bin_size: anyopaque;

pub const user_base = 0x1000000;
pub const sstatus_spie = 1 << 5;
const sstatus_sum = 1 << 18;
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

    virtio_blk_init();
    fs_init();

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
        @backingInt(common.Sysno.readfile), @backingInt(common.Sysno.writefile) => {
            const filename = std.mem.sliceTo(@as([*]const u8, @ptrFromInt(f.a0)), 0);
            const buf: [*]u8 = @ptrFromInt(f.a1);
            var len: usize = f.a2;
            const file = fs_lookup(filename) orelse {
                common.printf("file not found: %s\n", .{filename});
                f.a0 = @bitCast(@as(i32, -1));
                return;
            };

            if (len > file.data.len) {
                len = file.size;
            }

            if (f.a3 == @as(u32, @intCast(@backingInt(common.Sysno.writefile)))) {
                _ = common.memcpy(&file.data, buf, len);
                file.size = len;
                fs_flush();
            } else {
                _ = common.memcpy(buf, &file.data, len);
            }

            f.a0 = @intCast(len);
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
          [sstatus] "r" (sstatus_spie | sstatus_sum),
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

        map_page(page_table, virtio_blk_paddr, virtio_blk_paddr, page_r | page_w);

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
const sector_size = 512;
const virtq_entry_num = 16;
const virtio_device_blk = 2;
const virtio_blk_paddr = 0x10001000;
const virtio_reg_magic = 0x00;
const virtio_reg_version = 0x04;
const virtio_reg_device_id = 0x08;
const virtio_reg_page_size = 0x28;
const virtio_reg_queue_sel = 0x30;
const virtio_reg_queue_num_max = 0x34;
const virtio_reg_queue_num = 0x38;
const virtio_reg_queue_pfn = 0x40;
const virtio_reg_queue_ready = 0x44;
const virtio_reg_queue_notify = 0x50;
const virtio_reg_device_status = 0x70;
const virtio_reg_device_config = 0x100;
const virtio_status_ack = 1;
const virtio_status_driver = 2;
const virtio_status_driver_ok = 4;
const virtq_desc_f_next = 1;
const virtq_desc_f_write = 2;
const virtq_avail_f_no_interrupt = 1;
const virtio_blk_t_in = 0;
const virtio_blk_t_out = 1;

const virtq_desc = extern struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,
};

const virtq_avail = extern struct {
    flags: u16,
    index: u16,
    ring: [virtq_entry_num]u16,
};

const virtq_used_elem = extern struct {
    id: u32,
    len: u32,
};

const virtq_used = extern struct {
    flags: u16,
    index: u16,
    ring: [virtq_entry_num]virtq_used_elem,
};

// legacy 队列布局：描述符表与 avail 环在第一页，used 环必须落在下一页起始处
const virtio_virtq = extern struct {
    descs: [virtq_entry_num]virtq_desc,
    avail: virtq_avail,
    pad: [common.page_size - @sizeOf(virtq_desc) * virtq_entry_num - @sizeOf(virtq_avail)]u8,
    used: virtq_used,
    queue_index: u32,
    last_used_index: u16,
};

const virtio_blk_req = extern struct {
    req_type: u32,
    reserved: u32,
    sector: u64,
    data: [sector_size]u8,
    status: u8,
};

var blk_request_vq: *virtio_virtq = undefined;
var blk_req: *virtio_blk_req = undefined;
var blk_req_paddr: common.PAddr = 0;
var blk_capacity: u64 = 0;

fn virtio_reg_read32(offset: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(virtio_blk_paddr + offset);
    return ptr.*;
}

fn virtio_reg_read64(offset: usize) u64 {
    const ptr: *volatile u64 = @ptrFromInt(virtio_blk_paddr + offset);
    return ptr.*;
}

fn virtio_reg_write32(offset: usize, value: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(virtio_blk_paddr + offset);
    ptr.* = value;
}

fn virtio_reg_fetch_and_or32(offset: usize, value: u32) void {
    virtio_reg_write32(offset, virtio_reg_read32(offset) | value);
}

fn virtq_init(index: u32) *virtio_virtq {
    const pages = (@sizeOf(virtio_virtq) + common.page_size - 1) / common.page_size;
    const vq_paddr = alloc_pages(pages);
    const vq: *virtio_virtq = @ptrFromInt(vq_paddr);
    vq.queue_index = index;
    virtio_reg_write32(virtio_reg_queue_sel, index);
    virtio_reg_write32(virtio_reg_queue_num, virtq_entry_num);
    virtio_reg_write32(virtio_reg_queue_pfn, vq_paddr / common.page_size);
    return vq;
}

fn virtio_blk_init() void {
    if (virtio_reg_read32(virtio_reg_magic) != 0x74726976) {
        common.panic(@src(), "virtio: invalid magic value", .{});
    }
    if (virtio_reg_read32(virtio_reg_version) != 1) {
        common.panic(@src(), "virtio: invalid version", .{});
    }
    if (virtio_reg_read32(virtio_reg_device_id) != virtio_device_blk) {
        common.panic(@src(), "virtio: invalid device id", .{});
    }

    virtio_reg_write32(virtio_reg_device_status, 0);
    virtio_reg_fetch_and_or32(virtio_reg_device_status, virtio_status_ack);
    virtio_reg_fetch_and_or32(virtio_reg_device_status, virtio_status_driver);
    virtio_reg_write32(virtio_reg_page_size, common.page_size);
    blk_request_vq = virtq_init(0);
    virtio_reg_write32(virtio_reg_device_status, virtio_status_driver_ok);

    blk_capacity = virtio_reg_read64(virtio_reg_device_config) * sector_size;
    common.printf("virtio-blk: capacity is %d bytes\n", .{blk_capacity});

    blk_req_paddr = alloc_pages(1);
    blk_req = @ptrFromInt(blk_req_paddr);
}

fn virtq_kick(vq: *virtio_virtq, desc_index: u16) void {
    vq.avail.ring[vq.avail.index % virtq_entry_num] = desc_index;
    vq.avail.index +%= 1;
    asm volatile ("fence" ::: .{ .memory = true });
    virtio_reg_write32(virtio_reg_queue_notify, vq.queue_index);
    vq.last_used_index +%= 1;
}

fn virtq_is_busy(vq: *virtio_virtq) bool {
    const used_index: *volatile u16 = @ptrFromInt(@intFromPtr(&vq.used.index));
    return vq.last_used_index != used_index.*;
}

fn read_write_disk(buf: [*]u8, sector: u32, is_write: bool) void {
    if (sector >= blk_capacity / sector_size) {
        common.printf("virtio: tried to read/write sector=%d, but capacity is %d\n", .{ sector, blk_capacity / sector_size });
        return;
    }

    blk_req.sector = sector;
    blk_req.req_type = if (is_write) virtio_blk_t_out else virtio_blk_t_in;
    if (is_write) {
        _ = common.memcpy(&blk_req.data, buf, sector_size);
    }

    const vq = blk_request_vq;
    vq.descs[0] = .{
        .addr = blk_req_paddr,
        .len = @offsetOf(virtio_blk_req, "data"),
        .flags = virtq_desc_f_next,
        .next = 1,
    };
    vq.descs[1] = .{
        .addr = blk_req_paddr + @offsetOf(virtio_blk_req, "data"),
        .len = sector_size,
        .flags = virtq_desc_f_next | (if (is_write) @as(u16, 0) else virtq_desc_f_write),
        .next = 2,
    };
    vq.descs[2] = .{
        .addr = blk_req_paddr + @offsetOf(virtio_blk_req, "status"),
        .len = 1,
        .flags = virtq_desc_f_write,
        .next = 0,
    };

    virtq_kick(vq, 0);
    while (virtq_is_busy(vq)) {}

    if (blk_req.status != 0) {
        common.printf("virtio: warn: failed to read/write sector=%d status=%d\n", .{ sector, blk_req.status });
        return;
    }

    if (!is_write) {
        _ = common.memcpy(buf, &blk_req.data, sector_size);
    }
}

const files_max = 2;

const TarHeader = extern struct {
    name: [100]u8,
    mode: [8]u8,
    uid: [8]u8,
    gid: [8]u8,
    size: [12]u8,
    mtime: [12]u8,
    checksum: [8]u8,
    typ: u8,
    linkname: [100]u8,
    magic: [6]u8,
    version: [2]u8,
    uname: [32]u8,
    gname: [32]u8,
    devmajor: [8]u8,
    devminor: [8]u8,
    prefix: [155]u8,
    padding: [12]u8,
};

const File = struct {
    in_use: bool = false,
    name: [100]u8 = @splat(0),
    data: [1024]u8 = @splat(0),
    size: usize = 0,
};

const disk_max_size = alignUp(@sizeOf(File) * files_max, sector_size);

var files: [files_max]File = @splat(.{});
var disk: [disk_max_size]u8 = @splat(0);

inline fn alignUp(value: usize, alignment: usize) usize {
    return (value + alignment - 1) / alignment * alignment;
}

// tar 头里的数字是八进制字符串
fn oct2int(oct: []const u8) usize {
    var value: usize = 0;
    for (oct) |ch| {
        if (ch < '0' or ch > '7') break;
        value = value * 8 + (ch - '0');
    }
    return value;
}

fn fs_init() void {
    var sector: usize = 0;
    while (sector < disk_max_size / sector_size) : (sector += 1) {
        read_write_disk(disk[sector * sector_size ..].ptr, @intCast(sector), false);
    }

    var off: usize = 0;
    for (&files) |*file| {
        const header: *TarHeader = @ptrCast(&disk[off]);
        if (header.name[0] == 0) break;
        if (!std.mem.eql(u8, &header.magic, "ustar\x00")) {
            common.panic(@src(), "invalid tar header", .{});
        }

        const name = std.mem.sliceTo(&header.name, 0);
        const filesz = oct2int(&header.size);
        if (filesz > file.data.len) {
            common.panic(@src(), "file too large: %s", .{name});
        }

        @memcpy(file.name[0..name.len], name);
        @memcpy(file.data[0..filesz], disk[off + @sizeOf(TarHeader) ..][0..filesz]);
        file.size = filesz;
        file.in_use = true;
        common.printf("file: %s, size=%d\n", .{ name, filesz });

        off += alignUp(@sizeOf(TarHeader) + filesz, sector_size);
    }
}

fn fs_lookup(filename: []const u8) ?*File {
    for (&files) |*file| {
        if (!file.in_use) continue;
        if (std.mem.eql(u8, std.mem.sliceTo(&file.name, 0), filename)) return file;
    }
    return null;
}

fn fs_flush() void {
    @memset(&disk, 0);

    var off: usize = 0;
    for (&files) |*file| {
        if (!file.in_use) continue;
        if (off + @sizeOf(TarHeader) + file.size > disk_max_size) {
            common.panic(@src(), "disk image is full", .{});
        }

        const header: *TarHeader = @ptrCast(&disk[off]);
        @memcpy(&header.name, &file.name);
        @memcpy(header.mode[0..6], "000644");
        @memcpy(&header.magic, "ustar\x00");
        @memcpy(&header.version, "00");
        header.typ = '0';

        var filesz = file.size;
        var i = header.size.len;
        while (i > 0) {
            i -= 1;
            header.size[i] = @intCast(filesz % 8 + '0');
            filesz /= 8;
        }

        // 校验和字段此时为 0，按全空格语义先加 8 个空格
        var checksum: usize = ' ' * header.checksum.len;
        for (std.mem.asBytes(header)) |byte| checksum += byte;
        i = header.checksum.len - 2;
        while (i > 0) {
            i -= 1;
            header.checksum[i] = @intCast(checksum % 8 + '0');
            checksum /= 8;
        }

        @memcpy(disk[off + @sizeOf(TarHeader) ..][0..file.size], file.data[0..file.size]);
        off += alignUp(@sizeOf(TarHeader) + file.size, sector_size);
    }

    var sector: usize = 0;
    while (sector < disk_max_size / sector_size) : (sector += 1) {
        read_write_disk(disk[sector * sector_size ..].ptr, @intCast(sector), true);
    }

    common.printf("wrote %d bytes to disk\n", .{disk_max_size});
}

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
