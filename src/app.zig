const std = @import("std");
const Allocator = std.mem.Allocator;

const js = @import("runtime/js.zig");
const Loop = @import("runtime/loop.zig").Loop;
const HttpClient = @import("http/client.zig").Client;
const Telemetry = @import("telemetry/telemetry.zig").Telemetry;
const Notification = @import("notification.zig").Notification;

const log = std.log.scoped(.app);

// Container for global state / objects that various parts of the system
// might need.
pub const App = struct {
    loop: *Loop,
    config: Config,
    allocator: Allocator,
    telemetry: Telemetry,
    http_client: HttpClient,
    app_dir_path: ?[]const u8,
    notification: *Notification,

    pub const RunMode = enum {
        help,
        fetch,
        serve,
        version,
    };

    pub const Config = struct {
        run_mode: RunMode,
        gc_hints: bool = false,
        tls_verify_host: bool = true,
    };

    pub fn init(allocator: Allocator, config: Config) !*App {
        const app = try allocator.create(App);
        errdefer allocator.destroy(app);

        const loop = try allocator.create(Loop);
        errdefer allocator.destroy(loop);

        loop.* = try Loop.init(allocator);
        errdefer loop.deinit();

        const notification = try Notification.init(allocator, null);
        errdefer notification.deinit();

        const app_dir_path = getAndMakeAppDir(allocator);

        app.* = .{
            .loop = loop,
            .allocator = allocator,
            .telemetry = undefined,
            .app_dir_path = app_dir_path,
            .notification = notification,
            .http_client = try HttpClient.init(allocator, 5, .{
                .tls_verify_host = config.tls_verify_host,
            }),
            .config = config,
        };
        app.telemetry = Telemetry.init(app, config.run_mode);
        try app.telemetry.register(app.notification);

        return app;
    }

    pub fn deinit(self: *App) void {
        const allocator = self.allocator;
        if (self.app_dir_path) |app_dir_path| {
            allocator.free(app_dir_path);
        }
        self.telemetry.deinit();
        self.loop.deinit();
        allocator.destroy(self.loop);
        self.http_client.deinit();
        self.notification.deinit();
        allocator.destroy(self);
    }
};

fn getAndMakeAppDir(allocator: Allocator) ?[]const u8 {
    if (@import("builtin").is_test) {
        return allocator.dupe(u8, "/tmp") catch unreachable;
    }
    const app_dir_path = std.fs.getAppDataDir(allocator, "lightpanda") catch |err| {
        log.warn("failed to get lightpanda data dir: {}", .{err});
        return null;
    };

    std.fs.cwd().makePath(app_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => return app_dir_path,
        else => {
            allocator.free(app_dir_path);
            log.warn("failed to create lightpanda data dir: {}", .{err});
            return null;
        },
    };
    return app_dir_path;
}
