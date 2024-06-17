// Copyright (C) 2023-2024  Lightpanda (Selecy SAS)
//
// Francis Bouvier <francis@lightpanda.io>
// Pierre Tachoire <pierre@lightpanda.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as
// published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const fspath = std.fs.path;

const FileLoader = @import("fileloader.zig").FileLoader;

const parser = @import("netsurf");

const jsruntime = @import("jsruntime");
const Loop = jsruntime.Loop;
const Env = jsruntime.Env;
const Window = @import("../html/window.zig").Window;
const storage = @import("../storage/storage.zig");

const Types = @import("../main_wpt.zig").Types;
const UserContext = @import("../main_wpt.zig").UserContext;
const Client = @import("../async/Client.zig");

// runWPT parses the given HTML file, starts a js env and run the first script
// tags containing javascript sources.
// It loads first the js libs files.
pub fn run(arena: *std.heap.ArenaAllocator, comptime dir: []const u8, f: []const u8, loader: *FileLoader) !jsruntime.JSResult {
    const alloc = arena.allocator();
    try parser.init();
    defer parser.deinit();

    // document
    const file = try std.fs.cwd().openFile(f, .{});
    defer file.close();

    const html_doc = try parser.documentHTMLParse(file.reader(), "UTF-8");

    const dirname = fspath.dirname(f[dir.len..]) orelse unreachable;

    // create JS env
    var loop = try Loop.init(alloc);
    defer loop.deinit();

    var cli = Client{ .allocator = alloc, .loop = &loop };
    defer cli.deinit();

    var js_env = try Env.init(alloc, &loop, UserContext{
        .document = html_doc,
        .httpClient = &cli,
    });
    defer js_env.deinit();

    var storageShelf = storage.Shelf.init(alloc);
    defer storageShelf.deinit();

    // load user-defined types in JS env
    var js_types: [Types.len]usize = undefined;
    try js_env.load(&js_types);

    // start JS env
    try js_env.start(alloc);
    defer js_env.stop();

    // display console logs
    defer {
        var res = evalJS(js_env, alloc, "console.join('\\n');", "console") catch unreachable;
        defer res.deinit(alloc);
        if (res.result.len > 0) {
            std.debug.print("-- CONSOLE LOG\n{s}\n--\n", .{res.result});
        }
    }

    // setup global env vars.
    var window = Window.create(null);
    window.replaceDocument(html_doc);
    window.setStorageShelf(&storageShelf);
    try js_env.bindGlobal(&window);

    // thanks to the arena, we don't need to deinit res.
    var res: jsruntime.JSResult = undefined;

    const init =
        \\console = [];
        \\console.log = function () {
        \\  console.push(...arguments);
        \\};
        \\console.debug = function () {
        \\  console.push("debug", ...arguments);
        \\};
    ;
    res = try evalJS(js_env, alloc, init, "init");
    if (!res.success) {
        return res;
    }
    res.deinit(alloc);

    // loop hover the scripts.
    const doc = parser.documentHTMLToDocument(html_doc);
    const scripts = try parser.documentGetElementsByTagName(doc, "script");
    const slen = try parser.nodeListLength(scripts);
    for (0..slen) |i| {
        const s = (try parser.nodeListItem(scripts, @intCast(i))).?;

        // If the script contains an src attribute, load it.
        if (try parser.elementGetAttribute(@as(*parser.Element, @ptrCast(s)), "src")) |src| {
            var path = src;
            if (!std.mem.startsWith(u8, src, "/")) {
                // no need to free path, thanks to the arena.
                path = try fspath.join(alloc, &.{ "/", dirname, path });
            }

            res = try evalJS(js_env, alloc, try loader.get(path), src);
            if (!res.success) {
                return res;
            }
            res.deinit(alloc);
        }

        // If the script as a source text, execute it.
        const src = try parser.nodeTextContent(s) orelse continue;
        res = try evalJS(js_env, alloc, src, "");

        // return the first failure.
        if (!res.success) {
            return res;
        }
        res.deinit(alloc);
    }

    // Mark tests as ready to run.
    const loadevt = try parser.eventCreate();
    defer parser.eventDestroy(loadevt);

    try parser.eventInit(loadevt, "load", .{});
    _ = try parser.eventTargetDispatchEvent(
        parser.toEventTarget(Window, &window),
        loadevt,
    );

    // wait for all async executions
    res = try js_env.waitTryCatch(alloc);
    if (!res.success) {
        return res;
    }
    res.deinit(alloc);

    // Check the final test status.
    res = try evalJS(js_env, alloc, "report.status;", "teststatus");
    if (!res.success) {
        return res;
    }
    res.deinit(alloc);

    // return the detailed result.
    return try evalJS(js_env, alloc, "report.log", "teststatus");
}

fn evalJS(env: jsruntime.Env, alloc: std.mem.Allocator, script: []const u8, name: ?[]const u8) !jsruntime.JSResult {
    return try env.execTryCatch(alloc, script, name);
}

// browse the path to find the tests list.
pub fn find(allocator: std.mem.Allocator, comptime path: []const u8, list: *std.ArrayList([]const u8)) !void {
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true, .no_follow = true });
    defer dir.close();

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        if (!std.mem.endsWith(u8, entry.basename, ".html") and !std.mem.endsWith(u8, entry.basename, ".htm")) {
            continue;
        }

        try list.append(try fspath.join(allocator, &.{ path, entry.path }));
    }
}
