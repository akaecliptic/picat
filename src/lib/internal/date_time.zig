const std = @import("std");
const strings = @import("strings.zig");

/// top level
//

// binding file scope
const DateTime = @This();

// type aliases
const Allocator = std.mem.Allocator;

const String = strings.String;

const EpochSeconds = std.time.epoch.EpochSeconds;
const getDaysInMonth = std.time.epoch.getDaysInMonth;
const getDaysInYear = std.time.epoch.getDaysInYear;

const epoch_year = std.time.epoch.epoch_year;
const s_per_min = std.time.s_per_min;
const s_per_hour = std.time.s_per_hour;
const s_per_day = std.time.s_per_day;

// expected errors
pub const Error = strings.Error || DateTimeError;
pub const DateTimeError = error{InvalidDateTime};

/// datetime components
//

pub const Date = struct {
    year: u16, // given year
    month: u4, // jan = 1, dec = 12
    day: u5, // 1 - 31 days

    // coverts date instance to string
    pub fn to_string(self: *Date, allocator: Allocator) strings.Error!String {
        const year = try strings.stringify(allocator, self.year, .{ .width = 2 });
        const month = try strings.stringify(allocator, self.month, .{ .width = 2 });
        const day = try strings.stringify(allocator, self.day, .{ .width = 2 });

        return strings.concat(allocator, &.{ year, month, day });
    }
};

// this ignores the concept of leap seconds
pub const Time = struct {
    hour: u5, // 0 - 23 hour
    minute: u6, // 0 - 59 minute
    second: u6, // 0 - 59 second

    // coverts time instance to string
    pub fn to_string(self: *Time, allocator: Allocator) strings.Error!String {
        const hour = try strings.stringify(allocator, self.hour, .{ .width = 2 });
        const minute = try strings.stringify(allocator, self.minute, .{ .width = 2 });
        const second = try strings.stringify(allocator, self.second, .{ .width = 2 });

        return strings.concat(allocator, &.{ hour, minute, second });
    }
};

/// fields
//

epoch: u64,
date: Date,
time: Time,

/// lifecycle
//

// entry point
pub fn now() DateTimeError!DateTime {
    const timestamp = std.time.timestamp();

    // note: it's not really in scope of this project to support dates before epoch,
    // as such, i'd rather not consider the work to handle such cases
    if (timestamp < 0) {
        return error.InvalidDateTime;
    }

    const epoch_seconds = EpochSeconds{ .secs = @intCast(timestamp) };

    const epoch_day = epoch_seconds.getEpochDay();
    const day_seconds = epoch_seconds.getDaySeconds();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    return .{
        .epoch = epoch_seconds.secs,
        .date = .{
            .year = year_day.year,
            .month = month_day.month.numeric(),
            .day = month_day.day_index + 1,
        },
        .time = .{
            .hour = day_seconds.getHoursIntoDay(),
            .minute = day_seconds.getMinutesIntoHour(),
            .second = day_seconds.getSecondsIntoMinute(),
        },
    };
}

// note: time components are optional, null values are interpreted as 0
// meaning if all time components are null, the final date's time is midnight
//
// confusingly, the `day` parameter here, is the day index i.e. 0 is the 1st.
// this is done to match `std.time.epoch` structures, and epoch second calculations.
// the day index, does get converted to day when creating date component of datetime.
//
// create date from values passed
pub fn from(
    year: u16,
    month: u4,
    day: u5,
    hour: ?u5,
    minute: ?u6,
    second: ?u6,
) DateTimeError!DateTime {
    if (year < epoch_year or month > 12 or getDaysInMonth(year, @enumFromInt(month)) <= day) {
        return error.InvalidDateTime;
    }

    const epoch = try _calculate_epoch(
        year,
        month,
        day,
        hour,
        minute,
        second,
    );

    return .{
        .epoch = epoch,
        .date = .{
            .year = year,
            .month = month,
            .day = day + 1,
        },
        .time = .{
            .hour = hour orelse 0,
            .minute = minute orelse 0,
            .second = second orelse 0,
        },
    };
}

// coverts datetime instance to string
pub fn to_string(self: *DateTime, allocator: Allocator) strings.Error!String {
    const date_string = try self.date.to_string(allocator);
    const time_string = try self.time.to_string(allocator);

    return strings.concat(allocator, &.{ date_string, "T", time_string, "Z" });
}

/// interal
//

// calculates epoch second from datetime components
fn _calculate_epoch(
    year: u16,
    month: u4,
    day: u5,
    hour: ?u5,
    minute: ?u6,
    second: ?u6,
) DateTimeError!u64 {
    // step 0 - validate date components
    if (year < epoch_year or month > 12 or getDaysInMonth(year, @enumFromInt(month)) <= day) {
        // note: again, i don't want to (or need to) work with negative epoch dates, for now
        return error.InvalidDateTime;
    }

    // step 1 - validate time components

    // values are cast to u64 early for easier multiplication later
    const hours: u64 = @intCast(hour orelse 0);
    const minutes: u64 = @intCast(minute orelse 0);
    const seconds: u64 = @intCast(second orelse 0);

    if (hours > 23 or minutes > 60 or seconds > 60) {
        return error.InvalidDateTime;
    }

    // step 3 - calculate years and months as days
    var days: u64 = @intCast(day);

    for (1..month) |current| {
        days += getDaysInMonth(year, @enumFromInt(current));
    }

    for (epoch_year..year) |current| {
        days += getDaysInYear(@intCast(current));
    }

    // step 4 - multiply everything together
    return (s_per_day * days) + (s_per_hour * hours) + (s_per_min * minutes) + seconds;
}

/// testing
//

const testing = std.testing;

test "calculate_epoch: happy 1" {
    // 2022 - 02 - 22 @ 22:22:22
    const expected = 1645568542;
    const actual = try _calculate_epoch(2022, 2, 21, 22, 22, 22);

    try testing.expectEqual(expected, actual);
}

test "calculate_epoch: happy 2" {
    // 2022 - 02 - 22 @ 00:00:00
    const expected = 1645488000;
    const actual = try _calculate_epoch(2022, 2, 21, null, null, null);

    try testing.expectEqual(expected, actual);
}

test "calculate_epoch: error 1" {
    // 222 - 02 - 22 @ 22:22:22
    const expected = error.InvalidDateTime;
    const actual = _calculate_epoch(222, 2, 21, null, null, null);

    try testing.expectError(expected, actual);
}

test "calculate_epoch: error 2" {
    // 2022 - 02 - 22 @ 24:00:00
    const expected = error.InvalidDateTime;
    const actual = _calculate_epoch(2022, 2, 21, 24, null, null);

    try testing.expectError(expected, actual);
}

test "calculate_epoch: error 3" {
    // 2022 - 13 - 22 @ 00:00:00
    const expected = error.InvalidDateTime;
    const actual = _calculate_epoch(2022, 13, 21, null, null, null);

    try testing.expectError(expected, actual);
}

test "calculate_epoch: error 4" {
    // 2022 - 02 - 29 @ 00:00:00
    const expected = error.InvalidDateTime;
    const actual = _calculate_epoch(2022, 2, 28, null, null, null);

    try testing.expectError(expected, actual);
}
