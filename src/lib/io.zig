const std = @import("std");

const internal = @import("internal.zig");

pub const TemplateParser = @import("io/parser.zig");

pub const cli = @import("io/cli.zig");
pub const file = @import("io/file.zig");
pub const value = @import("io/value.zig");

/// testing
//

const testing = std.testing;

test {
    testing.refAllDecls(TemplateParser);

    testing.refAllDecls(cli);
    testing.refAllDecls(file);
    testing.refAllDecls(value);

    _ = TemplateParser;

    _ = cli;
    _ = file;
    _ = value;
}

// TemplateParser

test "TemplateParser::next_line: happy" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var reader = try file.read_file(allocator, "test/data/env.template");
    defer reader.file.close();

    var map = value.StringMap.init(allocator);

    try map.put("api_key", "passkey_123");
    try map.put("port", "1234");
    try map.put("host", "helloworld.com");

    const expected_line_1 = "API_KEY=passkey_123\n";
    const expected_line_2 = "PORT=1234\n";
    const expected_line_3 = "HOST=helloworld.com\n";
    const expected_line_4 = "";

    var parser = TemplateParser.init(.{
        .allocator = allocator,
        .value_map = &map,
        .reader = &reader,
    });

    const actual_line_1 = try parser.next_line() orelse "";
    const actual_line_2 = try parser.next_line() orelse "";
    const actual_line_3 = try parser.next_line() orelse "";
    const actual_line_4 = try parser.next_line() orelse "";

    try testing.expectEqualStrings(expected_line_1, actual_line_1);
    try testing.expectEqualStrings(expected_line_2, actual_line_2);
    try testing.expectEqualStrings(expected_line_3, actual_line_3);
    try testing.expectEqualStrings(expected_line_4, actual_line_4);
}

test "TemplateParser::next_line: error 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var reader = try file.read_file(allocator, "test/data/env.malformed");
    defer reader.file.close();

    var map = value.StringMap.init(allocator);

    try map.put("api_key", "passkey_123");

    const expected = error.MalformedTemplate;

    var parser = TemplateParser.init(.{
        .allocator = allocator,
        .value_map = &map,
        .reader = &reader,
    });

    const actual = parser.next_line();

    try testing.expectError(expected, actual);
}

test "TemplateParser::next_line: error 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var reader = try file.read_file(allocator, "test/data/env.template");
    defer reader.file.close();

    var map = value.StringMap.init(allocator);

    try map.put("no_found", "unreachable");

    const expected = error.ValueNotFound;

    var parser = TemplateParser.init(.{
        .allocator = allocator,
        .value_map = &map,
        .reader = &reader,
    });

    const actual = parser.next_line();

    try testing.expectError(expected, actual);
}

// cli

test "cli::parse_args: validation 1" {
    const args: []const []const u8 = &.{ "picat", "--in=./env.template", "--out=./env", "--help" };
    const command = try cli.parse_args(args);

    try testing.expect(command == .help);
}

test "cli::parse_args: validation 2" {
    const expected =
        \\{ "hello": "world" }
    ;

    const args: []const []const u8 = &.{ "picat", "--in=./env.template", "--out=./env", "--value={ \"hello\": \"world\" }" };
    const command = try cli.parse_args(args);

    try testing.expect(command == .template);
    try testing.expect(command.template.value != null);

    const actual = command.template.value.?.value;

    try testing.expectEqualStrings(expected, actual);
}

test "cli::parse_args: happy 1" {
    const expected_in = "./env.template";
    const expected_out = "./env";
    const expected_region = "us-east-1";

    const args: []const []const u8 = &.{ "picat", "--in=./env.template", "--out=./env", "--region=us-east-1", "--auth=env", "--secret=marathon_api" };
    const command = try cli.parse_args(args);

    try testing.expect(command == .template);

    try testing.expectEqualStrings(command.template.in, expected_in);
    try testing.expectEqualStrings(command.template.out, expected_out);
    try testing.expectEqualStrings(command.template.region.?, expected_region);
}

test "cli::parse_args: happy 2" {
    const args: []const []const u8 = &.{ "picat", "--version" };
    const command = try cli.parse_args(args);

    try testing.expect(command == .version);
}

test "cli::parse_args: happy 3" {
    const args: []const []const u8 = &.{ "picat", "--help" };
    const command = try cli.parse_args(args);

    try testing.expect(command == .help);
}

test "cli::parse_args: error" {
    const expected = error.InvalidOperation;

    const args: []const []const u8 = &.{ "picat", "--in=./env.template", "--out=./env", "--unsupported" };
    const actual = cli.parse_args(args);

    try testing.expectError(expected, actual);
}

// file

test "file::read_file: happy" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var reader = try file.read_file(allocator, "test/data/env.template");
    defer reader.file.close();

    const stats = try reader.file.stat();
    const actual = stats.size;

    try testing.expect(reader.err == null);
    try testing.expect(actual > 0);
}

test "file::read_file: error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const expected = error.FileNotFound;
    const actual = file.read_file(allocator, "test/data/env");

    try testing.expectError(expected, actual);
}

test "file::read_all: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var reader = try file.read_file(allocator, "test/data/env.template");
    defer reader.file.close();

    const stats = try reader.file.stat();
    const expected = stats.size;

    const bytes = try file.read_all(&reader);
    const actual = bytes.len;

    try testing.expectEqual(expected, actual);
}

test "file::write_file: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var random = std.Random.DefaultPrng.init(123456789);
    const random_string = try internal.strings.stringify(allocator, random.next(), .{});
    const file_name = try internal.strings.concat(allocator, &.{ "/tmp/test_", random_string });

    var reader = try file.write_file(allocator, file_name);
    defer std.fs.cwd().deleteFile(file_name) catch {};
    defer reader.file.close();

    const stats = try reader.file.stat();
    const actual = stats.kind;

    try testing.expect(actual == .file);
}

// value

test "value::parse_json: happy" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const input =
        \\{ "id": 7, "message": "hello world", "active": true, "empty": null }
    ;

    const expected_count = 4;

    const expected_id = "7";
    const expected_message = "hello world";
    const expected_active = "true";
    const expected_empty = "null";

    const map = try value.parse_json(allocator, input);

    const actual_count = map.count();

    const actual_id = map.get("id") orelse "";
    const actual_message = map.get("message") orelse "";
    const actual_active = map.get("active") orelse "";
    const actual_empty = map.get("empty") orelse "";

    try testing.expectEqual(expected_count, actual_count);

    try testing.expectEqualStrings(expected_id, actual_id);
    try testing.expectEqualStrings(expected_message, actual_message);
    try testing.expectEqualStrings(expected_active, actual_active);
    try testing.expectEqualStrings(expected_empty, actual_empty);
}

test "value::parse_json: error 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const input =
        \\{ "id": 7, "message" "hello world" }
    ;

    const expected = error.SyntaxError;

    const actual = value.parse_json(allocator, input);

    try testing.expectError(expected, actual);
}

test "value::parse_json: error 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const input =
        \\{ "id": 7, "message": [ "hello", "world" ] }
    ;

    const expected = error.ValueTooComplex;

    const actual = value.parse_json(allocator, input);

    try testing.expectError(expected, actual);
}

test "value::parse_json: error 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    const input =
        \\"hello world"
    ;

    const expected = error.UnexpectedJsonToken;

    const actual = value.parse_json(allocator, input);

    try testing.expectError(expected, actual);
}
