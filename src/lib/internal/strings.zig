/// note: this file is essentially a light wrapper for `std.mem`.
/// it used to do a lot more, and then i found out `std.mem` existed...
///
/// also, this file assumes all charaters are ascii, even though zig supports utf-8.
/// please do not try to use none-ascii characters with this, i don't know what would happen,
/// but it wouldn't be good
///
const std = @import("std");

/// top level
//

// type aliases
const Allocator = std.mem.Allocator;
const Writer = std.io.Writer;

pub const String = []const u8;

// expected errors
pub const Error = Allocator.Error || error{ StringFormatFailed, StringifyFailed };

// input output structs
const StringifyOptions = struct {
    width: ?u2 = null,
};

// constants
const hex_charset = "0123456789abcdef";
const max_stringify = 32;
const max_format = 512;

/// public interface
//

// concatinate two or more stirngs
pub fn concat(allocator: Allocator, strings: []const []const u8) Error!String {
    return std.mem.concat(allocator, u8, strings);
}

// joins two or more strings using a separator
pub fn join(allocator: Allocator, separator: []const u8, strings: []const []const u8) Error!String {
    return std.mem.join(allocator, separator, strings);
}

// converts integers to strings
pub fn stringify(allocator: Allocator, number: anytype, options: StringifyOptions) Error!String {
    var buffer: [max_stringify]u8 = undefined;
    var writer = Writer.fixed(buffer[0..]);

    const width: ?usize = if (options.width) |value| @intCast(value) else null;
    writer.printInt(
        number,
        10,
        .lower,
        .{ .fill = '0', .width = width },
    ) catch return error.StringifyFailed;

    const out = try allocator.alloc(u8, writer.end);
    @memcpy(out[0..], buffer[0..writer.end]);

    return out;
}

// return lowercase representation of ascii string
pub fn lowercase(allocator: Allocator, string: []const u8) Error!String {
    const buffer: []u8 = try allocator.alloc(u8, string.len);
    _ = std.ascii.lowerString(buffer, string);
    return buffer;
}

// returns a hex encode string from input
pub fn hex_encode(allocator: Allocator, string: []const u8) Error!String {
    var buffer: []u8 = try allocator.alloc(u8, string.len * 2);

    for (string, 0..) |b, i| {
        buffer[i * 2 + 0] = hex_charset[b >> 4];
        buffer[i * 2 + 1] = hex_charset[b & 15];
    }

    return buffer;
}

// formats arguments to a specified pattern
pub fn format(allocator: Allocator, comptime fmt: []const u8, args: anytype) Error!String {
    var buffer: [max_format]u8 = undefined;
    var writer = Writer.fixed(buffer[0..]);

    writer.print(fmt, args) catch return error.StringFormatFailed;

    const out = try allocator.alloc(u8, writer.end);
    @memcpy(out[0..], buffer[0..writer.end]);

    return out;
}

// compares two strings
pub fn equals(one: []const u8, two: []const u8) bool {
    return std.mem.eql(u8, one, two);
}

// returns whether a string is blank, i.e. has length of 0, is all white space
pub fn is_blank(string: []const u8) bool {
    if (string.len == 0) return true;
    const index_none_space = std.mem.indexOfNonePos(u8, string, 0, " ");
    return index_none_space == null;
}
