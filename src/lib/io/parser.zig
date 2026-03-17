const std = @import("std");

const file = @import("file.zig");

/// top level
//

// binding file scope
const TemplateParser = @This();

// type aliases
const Allocator = std.mem.Allocator;
const Reader = std.fs.File.Reader;
const StringMap = @import("value.zig").StringMap;
const DelimiterError = std.io.Reader.DelimiterError;

// expected errors
const Error = DelimiterError || Allocator.Error || LineParserError || TemplateParserError;
const LineParserError = error{MalformedTemplate};
const TemplateParserError = error{ValueNotFound};

// local structs

// note: i don't like specifying the allocator with every method call,
// and there are so many methods, this wrapper helps narrow down what
// i actually use
//
// basic wrapper for ArrayList, collecting and managing dynamic byte array
const ByteArray = struct {
    const ArrayList = std.ArrayList(u8);

    allocator: Allocator,
    array: ArrayList,

    // entry point
    pub fn init(allocator: Allocator, size: usize) Allocator.Error!ByteArray {
        const array = try ArrayList.initCapacity(allocator, size);
        return .{
            .allocator = allocator,
            .array = array,
        };
    }

    // appends a single byte to array list
    pub fn append(self: *ByteArray, byte: u8) Allocator.Error!void {
        try self.array.append(self.allocator, byte);
    }

    // appends a slice of bytes to array list
    pub fn append_slice(self: *ByteArray, byte: []const u8) Allocator.Error!void {
        try self.array.appendSlice(self.allocator, byte);
    }

    // returns a slice of currently allocated bytes, aka a string
    pub fn to_string(self: *ByteArray) []const u8 {
        const items = self.array.items;
        return items[0..items.len];
    }
};

// note: this inner struct allows me to collect parsing operations
// for a single line. because of how the file is implemented, each
// template file is intended to be processed line by line, this is
// the inner, more granular, byte-level, parser
//
// is it ideal? probably not
//
// an encapsulation of line parsing operations
const LineParser = struct {
    line: []const u8,
    c: usize,

    // entry point
    fn init(line: []const u8) LineParser {
        return .{
            .line = line,
            .c = 0,
        };
    }

    // checks if there is a next char available
    fn next(self: *LineParser) bool {
        const look_ahead = self.c + 1;

        if (look_ahead >= self.line.len) {
            return false;
        }

        return true;
    }

    // note: i'm pretty sure i have at least two more methods
    // than i actually need, will combine them later

    // moves cursor forward by n places
    fn advance_n(self: *LineParser, n: usize) void {
        self.c += n;
    }

    // moves cursor forward by one place
    fn advance(self: *LineParser) void {
        self.advance_n(1);
    }

    // returns the current char under cursor
    fn char(self: *LineParser) ?u8 {
        if (self.c >= self.line.len) {
            return null;
        }

        return self.line[self.c];
    }

    // returns the next char after cursor, if available
    // null is returned if there is no next char
    fn peek(self: *LineParser) ?u8 {
        if (self.next()) {
            return self.line[self.c + 1];
        }

        return null;
    }

    // note: this method assumes the cursor is currently on the first
    // opening template char
    //
    // return whether the next char completes the open template
    // if found, the cursor is placed after both open template chars
    fn match_open(self: *LineParser) bool {
        if (self.char() == null) {
            return false;
        }

        const look_ahead = if (self.peek()) |value| value else return false;

        if (look_ahead == '<') {
            self.advance_n(2);
            return true;
        }

        return false;
    }

    // note: this method assumes the cursor is before the first closing
    // template char. the cursor is left in place for easier calculations
    // of substrings within line
    //
    // return whether the next char sequence completes the close template
    // if found, the cursor is left in place
    fn expect_close(self: *LineParser) LineParserError!bool {
        if (self.char() == null) {
            return false;
        }

        const current = if (self.char()) |value| value else return error.MalformedTemplate;

        if (current == '>') {
            const look_ahead = if (self.peek()) |value| value else return error.MalformedTemplate;

            if (look_ahead == '\n') {
                return error.MalformedTemplate;
            } else if (look_ahead == '>') {
                return true;
            }
        }

        return false;
    }
};

// input output structs
const ParserOptions = struct {
    allocator: Allocator,
    value_map: *StringMap,
    reader: *Reader,
};

/// fields
//

allocator: Allocator,
value_map: *StringMap,
reader: *Reader,

/// lifecycle
//

// entry point
pub fn init(options: ParserOptions) TemplateParser {
    return .{
        .allocator = options.allocator,
        .value_map = options.value_map,
        .reader = options.reader,
    };
}

/// public interface
//

// template next line from file
pub fn next_line(self: *TemplateParser) Error!?[]const u8 {
    // step 0 - read line into memory
    const line = file.read_line(self.reader) catch |err| switch (err) {
        error.EndOfStream => return null,
        else => return err,
    };
    // std.debug.print("{s}", .{line});

    // step 1 - set up data structures
    var byte_list = try ByteArray.init(self.allocator, line.len);
    var line_parser = LineParser.init(line);

    // step 2 - iterate over bytes in line
    var c = line_parser.char();
    while (line_parser.next()) : (c = line_parser.char()) {
        if (c == null) break;

        // step 2.1 - check if open template pattern
        if (c == '<' and line_parser.match_open()) {
            // mark start of substring
            const start = line_parser.c;

            // step 2.2 - consume tokens until closing template pattern is found
            inner: while (true) {
                // note: if end of line is reached, an error is produced
                const closed = try line_parser.expect_close();
                if (closed) break :inner;
                line_parser.advance();
            }

            // mark end of substring
            const end = line_parser.c;

            // step 2.3 - create key from trimmed substring, and get value from map
            const raw_key = line[start..end];
            const key = std.mem.trim(u8, raw_key, " ");
            const optional = self.value_map.get(key);

            // step 2.4 - if present append value to byte array, otherwise produce error
            if (optional) |value| {
                try byte_list.append_slice(value[0..]);

                // note: the parser cursor is currently before the closing template pattern,
                // as such, the parser cursor needs to be moved after the pattern (two places)
                line_parser.advance_n(2);
                continue;
            } else {
                // note: might have this be configuration in the future
                return error.ValueNotFound;
            }
        }

        // step 3 - append current char to byte array and advance parser cursor
        try byte_list.append(c.?);
        line_parser.advance();
    }

    // step 4 - append last byte
    if (c) |last| {
        try byte_list.append(last);
    }

    // step 5 - return slice of byte array as string
    return byte_list.to_string();
}
