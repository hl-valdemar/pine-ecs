const std = @import("std");

const log = std.log.scoped(.pine_ecs);

pub const err = log.err;
pub const debug = log.debug;
pub const info = log.info;
pub const warn = log.warn;

pub fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const stderr = std.io.getStdErr().writer();
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    // consistent prefix with level and scope
    const prefix = "[" ++ comptime message_level.asText() ++ "] (" ++ @tagName(scope) ++ "): ";
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}
