const std = @import("std");
pub const Midi = @This();

format: Format,
division: Division,
tracks: []Track,

pub fn deinit(self: Midi, allocator: std.mem.Allocator) void {
    for (self.tracks) |t| {
        t.deinit(allocator);
    }
    allocator.free(self.tracks);
}

pub const Track = struct {
    events: []MtrkEvent,

    pub fn deinit(self: Track, allocator: std.mem.Allocator) void {
        for (self.events) |e| {
            switch (e.event) {
                .sysex => |s| { allocator.free(s); },
                .meta => |m| { allocator.free(m.data); },
                else => {}
            }
        }
        allocator.free(self.events);
    }
};

pub const MtrkEvent = struct {
    delta: u28, // Stored in file as a variable length value
    event: Event
};
pub const Event = union (enum) {
    pub const MidiMessage = struct {
        type: u4,
        channel: u4,
        data_len: u8,
        data: [2]u8
    };
    pub const Meta = struct {
        type: u8,
        data: []u8
    };
    midi: MidiMessage,
    sysex: []u8,
    meta: Meta
};


pub const Format = enum (u16) {
    single_track = 0,
    simultaneous_tracks = 1,
    separate_tracks = 2,
};
pub const Division = packed struct (u16) {
    const Type = enum (u1) { ticks, subdivisions};

    format: Type,
    value: u15,
};
pub const Header = struct {
    length: u32,
    format: Format,
    /// Number of track chunks,
    ntkrs: u16,
    division: Division

};
