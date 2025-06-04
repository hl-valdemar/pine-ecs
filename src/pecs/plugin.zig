const Registry = @import("registry.zig").Registry;

/// Plugins can be used to bundle behavior.
///
/// A plugin might look as follows:
/// ```zig
/// pub const HealthPlugin = Plugin.init("Health", struct {
///     const Health = struct { current: f32, max: f32 };
///     const Damage = struct { amount: f32 };
///
///     fn init(registry: *Registry) !void {
///         try registry.registerTaggedSystem(HealthSystem, "health");
///         try registry.registerTaggedSystem(DamageSystem, "health");
///     }
///
///     // ... system implementations ...
/// }.init);
/// ```
pub const Plugin = struct {
    name: []const u8,
    init_fn: *const fn (*Registry) anyerror!void,
    deinit_fn: ?*const fn (*Registry) void = null,

    pub fn init(name: []const u8, init_fn: *const fn (*Registry) anyerror!void) Plugin {
        return Plugin{
            .name = name,
            .init_fn = init_fn,
        };
    }

    pub fn withDeinit(self: Plugin, deinit_fn: *const fn (*Registry) void) Plugin {
        return Plugin{
            .name = self.name,
            .init_fn = self.init_fn,
            .deinit_fn = deinit_fn,
        };
    }
};
