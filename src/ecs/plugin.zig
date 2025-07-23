const Registry = @import("registry.zig").Registry;

/// Plugins can be used to bundle behavior.
///
/// A plugin might look as follows:
/// ```zig
/// pub const HealthPlugin = Plugin.init("Health", struct {
///     const Health = struct { current: f32, max: f32 };
///     const Damage = struct { amount: f32 };
///
///     fn init(registry: *Registry) anyerror!void {
///         try registry.registerTaggedSystem(HealthSystem, "health");
///         try registry.registerTaggedSystem(DamageSystem, "health");
///     }
///
///     // ... system implementations ...
/// }.init);
/// ```
pub const Plugin = struct {
    const InitFn = *const fn (*Registry) anyerror!void;
    const DeinitFn = *const fn (*Registry) void;

    name: []const u8,
    init_fn: InitFn,
    deinit_fn: ?DeinitFn = null,

    pub fn init(name: []const u8, init_fn: InitFn) Plugin {
        return Plugin{
            .name = name,
            .init_fn = init_fn,
        };
    }

    pub fn withDeinit(self: Plugin, deinit_fn: DeinitFn) Plugin {
        return Plugin{
            .name = self.name,
            .init_fn = self.init_fn,
            .deinit_fn = deinit_fn,
        };
    }
};
