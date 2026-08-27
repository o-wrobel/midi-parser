const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Track = @This();

events: []TimedEvent,

pub fn deinit(self: Track, allocator: Allocator) void {
    for (self.events) |e| {
        switch (e.event) {
            .sysex => |s| { allocator.free(s); },
            .meta => |m| { allocator.free(m.data); },
            else => {}
        }
    }
    allocator.free(self.events);
}

pub const TimedEvent = struct {
    delta: u28, // Stored in file as a variable length value
    event: Event
};

pub const Event = union (enum) {
    pub const MidiMessage = struct {
        pub const Type = enum (u4) {
            note_off = 0b1000,
            note_on = 0b1001,
            control_change = 0b1011,
            program_change = 0b1100,
            _,
        };
        type: Type,
        channel: u4,
        data_len: u8,
        data: [2]u8
    };
    pub const MetaMessage = struct {
        const Type = enum (u8) {
            sequence_number = 0x00,
            text,
            copyright_notice,
            track_name,
            instrument_name,
            lyrics,
            marker,
            cue_point,
            channel_prefix,
            end_track = 0x2f,

            set_tempo = 0x51,
            time_signature = 0x58,
            key_signature = 0x59,
            sequencer_specific = 0x7F,
            _
        };
        type: Type,
        data: []u8
    };
    midi: MidiMessage,
    sysex: []u8,
    meta: MetaMessage
};
