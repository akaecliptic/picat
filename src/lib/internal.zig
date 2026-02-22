const std = @import("std");

pub const Client = @import("internal/http_client.zig");
pub const DateTime = @import("internal/date_time.zig");

pub const strings = @import("internal/strings.zig");

/// testing
//

const testing = std.testing;

test {
    testing.refAllDecls(Client);
    testing.refAllDecls(DateTime);

    testing.refAllDecls(strings);

    // note: relying on parent clients in `aws` for testing
    _ = Client;

    _ = DateTime;

    // note: i'm not testing strings since it's used extensively
    // in other files, and the overhead on `std.mem` is very light
    //
    // see: `aws/sigv.zig`
    _ = strings;
}

// DateTime

test "DateTime::from: happy 1" {
    // 2022 - 02 - 22 @ 22:22:22
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var datetime = try DateTime.from(2022, 2, 21, 22, 22, 22);

    const expected_datetime_string = "20220222T222222Z";
    const expected_date_string = "20220222";
    const expected_time_string = "222222";

    const actual_datetime_string = try datetime.to_string(allocator);
    const actual_date_string = try datetime.date.to_string(allocator);
    const actual_time_string = try datetime.time.to_string(allocator);

    try testing.expectEqualStrings(expected_datetime_string, actual_datetime_string);
    try testing.expectEqualStrings(expected_date_string, actual_date_string);
    try testing.expectEqualStrings(expected_time_string, actual_time_string);
}

test "DateTime::from: happy 2" {
    // 2022 - 02 - 22 @ 00:00:00
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var datetime = try DateTime.from(2022, 2, 21, null, null, null);

    const expected_datetime_string = "20220222T000000Z";
    const expected_date_string = "20220222";
    const expected_time_string = "000000";

    const actual_datetime_string = try datetime.to_string(allocator);
    const actual_date_string = try datetime.date.to_string(allocator);
    const actual_time_string = try datetime.time.to_string(allocator);

    try testing.expectEqualStrings(expected_datetime_string, actual_datetime_string);
    try testing.expectEqualStrings(expected_date_string, actual_date_string);
    try testing.expectEqualStrings(expected_time_string, actual_time_string);
}

test "DateTime::from: error 1" {
    // 2022 - 02 - 22 @ 24:00:00
    const expected = error.InvalidDateTime;
    const actual = DateTime.from(2022, 2, 21, 24, null, null);

    try testing.expectError(expected, actual);
}

test "DateTime::from: error 2" {
    // 2022 - 13 - 22 @ 00:00:00
    const expected = error.InvalidDateTime;
    const actual = DateTime.from(2022, 13, 21, null, null, null);

    try testing.expectError(expected, actual);
}
