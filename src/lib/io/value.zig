const std = @import("std");

/// top level
//

// type aliases
pub const StringMap = std.StringHashMap([]const u8);

const Allocator = std.mem.Allocator;
const Scanner = std.json.Scanner;

// expected errors
const Error = Scanner.NextError || Allocator.Error || error{ UnexpectedJsonToken, ValueTooComplex };

/// public interface
//

// note: currently, this function only accepts 'simple' json objects.
// the criteria are strict for simplicity sake, but should be revisited.
// single strings should probably never be acceptable, can't see a reason otherwise.
//
// parses json string to `std.StringHashMap`
pub fn parse_json(allocator: Allocator, string: []const u8) Error!StringMap {
    var scanner = Scanner.initCompleteInput(allocator, string);
    var map = StringMap.init(allocator);

    while (scanner.cursor < scanner.input.len) {
        const token = try scanner.next();
        const level = scanner.stackHeight();

        if (level > 1) {
            return error.ValueTooComplex;
        }

        if (scanner.string_is_object_key and token == .string and level == 1) {
            const key: []const u8 = token.string;
            const value: []const u8 = try _get_value(&scanner, level);

            try map.put(key, value);
            continue;
        }

        switch (token) {
            .end_of_document, .object_begin, .object_end => {},
            .array_begin, .array_end => {
                return error.ValueTooComplex;
            },
            else => {
                return error.UnexpectedJsonToken;
            },
        }
    }

    return map;
}

/// internal
//

// returns next token value, asserting its an appropriate value of a key-pair
fn _get_value(scanner: *Scanner, level: usize) Error![]const u8 {
    const token = try scanner.next();

    if (scanner.stackHeight() != level) {
        return error.ValueTooComplex;
    }

    return switch (token) {
        .string => token.string,
        .number => token.number,
        .true => "true",
        .false => "false",
        .null => "null",
        .object_begin, .object_end, .array_begin, .array_end => {
            return error.ValueTooComplex;
        },
        else => {
            return error.UnexpectedJsonToken;
        },
    };
}

/// testing
//

const testing = std.testing;

test "get_value: happy" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const expected = "world";
    const string_json: []const u8 =
        \\ { "hello" : "world" }
    ;

    var scanner = Scanner.initCompleteInput(allocator, string_json);

    _ = try scanner.next(); // consume '{'
    _ = try scanner.next(); // consume "hello"

    const actual = try _get_value(&scanner, scanner.stackHeight());

    try testing.expectEqualStrings(expected, actual);
}

test "get_value: error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const expected = error.ValueTooComplex;
    const string_json: []const u8 =
        \\ { "hello" : [ "world" ] }
    ;

    var scanner = Scanner.initCompleteInput(allocator, string_json);

    _ = try scanner.next(); // consume '{'
    _ = try scanner.next(); // consume "hello"

    const actual = _get_value(&scanner, scanner.stackHeight());

    try testing.expectError(expected, actual);
}
