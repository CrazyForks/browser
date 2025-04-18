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

const Env = @import("../env.zig").Env;
const Callback = Env.Callback;

const EventTarget = @import("../dom/event_target.zig").EventTarget;
const EventHandler = @import("../events/event.zig").EventHandler;

const parser = @import("../netsurf.zig");
const SessionState = @import("../env.zig").SessionState;

const log = std.log.scoped(.xhr);

pub const XMLHttpRequestEventTarget = struct {
    pub const prototype = *EventTarget;

    // Extend libdom event target for pure zig struct.
    base: parser.EventTargetTBase = parser.EventTargetTBase{},

    onloadstart_cbk: ?Callback = null,
    onprogress_cbk: ?Callback = null,
    onabort_cbk: ?Callback = null,
    onload_cbk: ?Callback = null,
    ontimeout_cbk: ?Callback = null,
    onloadend_cbk: ?Callback = null,

    fn register(
        self: *XMLHttpRequestEventTarget,
        alloc: std.mem.Allocator,
        typ: []const u8,
        cbk: Callback,
    ) !void {
        try parser.eventTargetAddEventListener(
            @as(*parser.EventTarget, @ptrCast(self)),
            alloc,
            typ,
            EventHandler,
            .{ .cbk = cbk },
            false,
        );
    }
    fn unregister(self: *XMLHttpRequestEventTarget, alloc: std.mem.Allocator, typ: []const u8, cbk: Callback) !void {
        const et = @as(*parser.EventTarget, @ptrCast(self));
        // check if event target has already this listener
        const lst = try parser.eventTargetHasListener(et, typ, false, cbk.id);
        if (lst == null) {
            return;
        }

        // remove listener
        try parser.eventTargetRemoveEventListener(et, alloc, typ, lst.?, false);
    }

    pub fn get_onloadstart(self: *XMLHttpRequestEventTarget) ?Callback {
        return self.onloadstart_cbk;
    }
    pub fn get_onprogress(self: *XMLHttpRequestEventTarget) ?Callback {
        return self.onprogress_cbk;
    }
    pub fn get_onabort(self: *XMLHttpRequestEventTarget) ?Callback {
        return self.onabort_cbk;
    }
    pub fn get_onload(self: *XMLHttpRequestEventTarget) ?Callback {
        return self.onload_cbk;
    }
    pub fn get_ontimeout(self: *XMLHttpRequestEventTarget) ?Callback {
        return self.ontimeout_cbk;
    }
    pub fn get_onloadend(self: *XMLHttpRequestEventTarget) ?Callback {
        return self.onloadend_cbk;
    }

    pub fn set_onloadstart(self: *XMLHttpRequestEventTarget, handler: Callback, state: *SessionState) !void {
        const arena = state.arena;
        if (self.onloadstart_cbk) |cbk| try self.unregister(arena, "loadstart", cbk);
        try self.register(arena, "loadstart", handler);
        self.onloadstart_cbk = handler;
    }
    pub fn set_onprogress(self: *XMLHttpRequestEventTarget, handler: Callback, state: *SessionState) !void {
        const arena = state.arena;
        if (self.onprogress_cbk) |cbk| try self.unregister(arena, "progress", cbk);
        try self.register(arena, "progress", handler);
        self.onprogress_cbk = handler;
    }
    pub fn set_onabort(self: *XMLHttpRequestEventTarget, handler: Callback, state: *SessionState) !void {
        const arena = state.arena;
        if (self.onabort_cbk) |cbk| try self.unregister(arena, "abort", cbk);
        try self.register(arena, "abort", handler);
        self.onabort_cbk = handler;
    }
    pub fn set_onload(self: *XMLHttpRequestEventTarget, handler: Callback, state: *SessionState) !void {
        const arena = state.arena;
        if (self.onload_cbk) |cbk| try self.unregister(arena, "load", cbk);
        try self.register(arena, "load", handler);
        self.onload_cbk = handler;
    }
    pub fn set_ontimeout(self: *XMLHttpRequestEventTarget, handler: Callback, state: *SessionState) !void {
        const arena = state.arena;
        if (self.ontimeout_cbk) |cbk| try self.unregister(arena, "timeout", cbk);
        try self.register(arena, "timeout", handler);
        self.ontimeout_cbk = handler;
    }
    pub fn set_onloadend(self: *XMLHttpRequestEventTarget, handler: Callback, state: *SessionState) !void {
        const arena = state.arena;
        if (self.onloadend_cbk) |cbk| try self.unregister(arena, "loadend", cbk);
        try self.register(arena, "loadend", handler);
        self.onloadend_cbk = handler;
    }

    pub fn deinit(self: *XMLHttpRequestEventTarget, state: *SessionState) void {
        const arena = state.arena;
        parser.eventTargetRemoveAllEventListeners(@as(*parser.EventTarget, @ptrCast(self)), arena) catch |e| {
            log.err("remove all listeners: {any}", .{e});
        };
    }
};
