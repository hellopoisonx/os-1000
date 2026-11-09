const user = @import("user.zig");
const common = @import("common.zig");

comptime {
    _ = &user.start;
    _ = &user.exit;
    _ = &user.putchar;
    _ = &user.getchar;
}

export fn main() void {
    outer: while (true) {
        common.printf("> ", .{});
        var cmdline: [128:0]u8 = undefined;
        var i: usize = 0;
        while (true) : (i += 1) {
            // C's `char ch = getchar()` truncates the return value.
            const ch: u8 = @truncate(@as(usize, @bitCast(user.getchar())));
            user.putchar(ch);
            if (i == cmdline.len - 1) {
                common.printf("command line too long\n", .{});
                continue :outer;
            } else if (ch == '\r') {
                common.printf("\n", .{});
                cmdline[i] = 0;
                break;
            } else {
                cmdline[i] = ch;
            }
        }

        if (common.strcmp(&cmdline, "hello") == 0)
            common.printf("Hello world from shell!\n", .{})
        else if (common.strcmp(&cmdline, "exit") == 0)
            user.exit()
        else
            common.printf("unknown command: %s\n", .{cmdline[0..i :0]});
    }
}
