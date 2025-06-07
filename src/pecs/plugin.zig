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
    const InitFunc = *const fn (*Registry) anyerror!void;
    const DeinitFunc = *const fn (*Registry) void;

    name: []const u8,
    init_fn: InitFunc,
    deinit_fn: ?DeinitFunc = null,

    pub fn init(name: []const u8, init_fn: InitFunc) Plugin {
        return Plugin{
            .name = name,
            .init_fn = init_fn,
        };
    }

    pub fn withDeinit(self: Plugin, deinit_fn: DeinitFunc) Plugin {
        return Plugin{
            .name = self.name,
            .init_fn = self.init_fn,
            .deinit_fn = deinit_fn,
        };
    }
};
