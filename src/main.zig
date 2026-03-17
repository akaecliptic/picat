const std = @import("std");
const meta = @import("meta");

const internal = @import("lib/internal.zig");
const io = @import("lib/io.zig");
const aws = @import("lib/aws.zig");

//// top level
///
//

// type aliases allocators
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const page_allocator = std.heap.page_allocator;

// type aliases std
const Reader = std.fs.File.Reader;
const Writer = std.fs.File.Writer;

// type aliases picat
const Command = io.cli.Command;
const ValueMap = io.value.StringMap;
const Credential = aws.model.SecurityCredential;

// buffers
var buffer_cli: [2048]u8 = undefined;
var buffer_stdout: [64]u8 = undefined;

// printing
var stdout: std.fs.File = undefined;
var writer: std.fs.File.Writer = undefined;

// exit codes
const ExitCodes = enum(u8) {
    // success
    nominal = 0,

    // warnings: 1 - 50

    // user: 51 - 100
    invalid_arguments = 51,
    constraint_limit,

    // application 101 - 200
    no_confidence = 101,
    allocation_error,

    parser_error,
    value_error,
    file_error,

    strings_error,
    datetime_error,

    model_error,
    asmc_error,

    pub fn code(exit_code: ExitCodes) u8 {
        return @intCast(@intFromEnum(exit_code));
    }
};

//// functions
///
//

// entry point
pub fn main() u8 {
    // open stdout for writting
    stdout = std.fs.File.stdout();
    writer = stdout.writer(&buffer_stdout);

    defer stdout.close();
    defer flush();

    // read arguments and create command instance
    var allocator_command = FixedBufferAllocator.init(&buffer_cli);
    const command = get_command(allocator_command.allocator()) catch |err| return parse_error(err);

    // execute command
    switch (command) {
        .template => template(command) catch |err| return parse_error(err),
        .version => print("picat v{s}\n", .{meta.version}),
        .help => println(io.cli.usage_message),
    }

    return ExitCodes.code(.nominal);
}
/// errors
//

// process error: print error message and determine exit code
fn parse_error(err: anyerror) u8 {
    var exit_code: ExitCodes = undefined;

    switch (err) {
        error.MaxValueLimit, error.MaxFileLimit => {
            exit_code = .constraint_limit;
            print_error("exceeded application limit", err);
        },
        error.InvalidOperation,
        error.InvalidInFile,
        error.InvalidOutFile,
        error.ValueOptionNotSet,
        error.AuthOptionNotSet,
        error.RegionOptionNotSet,
        => {
            exit_code = .invalid_arguments;
            print_error("invalid argument provided", err);
        },
        error.SyntaxError,
        error.UnexpectedEndOfInput,
        error.BufferUnderrun,
        error.UnexpectedJsonToken,
        error.ValueTooComplex,
        => {
            exit_code = .value_error;
            print_error("error parsing template values", err);
        },
        error.MalformedTemplate, error.ValueNotFound => {
            exit_code = .parser_error;
            print_error("error parsing template file", err);
        },
        error.FileWriteFailed,
        error.PathAlreadyExists,
        error.FileNotFound,
        error.AccessDenied,
        error.BadPathName,
        => {
            exit_code = .file_error;
            print_error("error accessing file", err);
        },
        error.StringFormatFailed, error.StringifyFailed => {
            exit_code = .strings_error;
            print_error("error performing internal string operation", err);
        },
        error.InvalidDateTime => {
            exit_code = .datetime_error;
            print_error("error creating date time", err);
        },
        error.FailedParsingAWSData => {
            exit_code = .model_error;
            print_error("error creating internal representation of aws data", err);
        },
        error.InvalidHeader, error.InvalidEndpoint => {
            exit_code = .asmc_error;
            print_error("error querying aws secret manager", err);
        },
        error.OutOfMemory => {
            exit_code = .allocation_error;
            print_error("error allocating memory", err);
        },
        else => {
            exit_code = .no_confidence;
            print_error("unexpected error", err);
        },
    }

    return ExitCodes.code(exit_code);
}

/// underlying
//

// parse command line arguments
fn get_command(allocator: Allocator) !Command {
    const arg_iterator = try std.process.argsAlloc(allocator);
    return io.cli.parse_args(arg_iterator);
}

// template entry point
fn template(command: Command) !void {
    // create backing allocator for file io
    var allocator_io = std.heap.ArenaAllocator.init(page_allocator);
    defer allocator_io.deinit();

    // extract template command for easier use
    const cmd = command.template;

    // open in file
    var in = try io.file.read_file(allocator_io.allocator(), cmd.in);

    defer in.file.close();

    // parse values
    switch (cmd.value.?) {
        .value => |value| try from_value(allocator_io.allocator(), &in, command, value),
        .file => |file| try from_file(allocator_io.allocator(), &in, command, file),
        .secret => |secret| try from_secret(allocator_io.allocator(), &in, command, secret),
    }
}

// populate template file from value string
fn from_value(allocator: Allocator, in: *Reader, command: Command, value: []const u8) !void {
    // parse values and create template parser instnce
    var value_map: ValueMap = try io.value.parse_json(allocator, value);
    var template_parser = io.TemplateParser.init(.{
        .allocator = allocator,
        .reader = in,
        .value_map = &value_map,
    });

    // read first line
    var line: ?[]const u8 = try template_parser.next_line();

    // the double validition is to create the out file as late as possible
    if (line == null) return;

    // create and open out file
    var out = try io.file.write_file(allocator, command.template.out, command.template.truncate);
    defer out.file.close();

    // write lines with data to file
    while (line != null) : (line = try template_parser.next_line()) {
        if (line) |bytes| try io.file.write_line(&out, bytes);
    }
}

// populate template file from file
fn from_file(allocator: Allocator, in: *Reader, command: Command, file: []const u8) !void {
    // open value file
    var json = try io.file.read_file(allocator, file);
    defer json.file.close();

    // load entire file into memory and use as value
    const value = try io.file.read_all(&json);
    try from_value(allocator, in, command, value);
}

// populate template file from aws secrets manager
fn from_secret(allocator: Allocator, in: *Reader, command: Command, secret: []const u8) !void {
    // create backing allocator aws
    var allocator_aws = std.heap.ArenaAllocator.init(page_allocator);
    defer allocator_aws.deinit();

    // extra template command and create map from env variables
    const cmd = command.template;
    const envs = try std.process.getEnvMap(allocator_aws.allocator());

    // try and parse region from different sources, return error if can't be found
    const region = aws.model.AWSRegion.get_region(cmd.region orelse "") orelse aws.model.AWSRegion.from_env(envs);
    if (region == null) {
        return error.RegionOptionNotSet;
    }

    // locate aws credentials
    const auth = aws.model.AWSAuth.get_auth(cmd.auth orelse "");
    var credential: Credential = undefined;

    switch (auth.?) {
        .env => credential = Credential.from_env(envs),
        .imdvs => {
            var imdvs2 = aws.IMDSV2Client.init(allocator_aws.allocator(), .{});
            defer imdvs2.deinit();

            const token = try imdvs2.generate_token();
            const profile = try imdvs2.get_profile(token);

            credential = try imdvs2.get_credentials(token, profile);
        },
    }

    // create client for secrets manager
    var asmc = try aws.ASMClient.init(allocator_aws.allocator(), .{ .region = region.?.get_string() });
    defer asmc.deinit();

    // fetch secret and use as value
    const asm_secret = try asmc.get_secret_value(secret, credential);

    const value = asm_secret.SecretString;
    try from_value(allocator, in, command, value);
}

/// printing
//

// flush stdout buffer
fn flush() void {
    if (@typeInfo(@TypeOf(writer)) != .undefined) {
        writer.interface.flush() catch {};
    }
}

// print string with new line to stdout
fn println(string: []const u8) void {
    print("{s}\n", .{string});
}

// note: this should probably be writing to stderr?
//
// print string with new line to stdout
fn print_error(message: []const u8, err: anyerror) void {
    print("{s}: {t}\n", .{ message, err });
}

// print format to stdout
fn print(comptime fmt: []const u8, args: anytype) void {
    writer.interface.print(fmt, args) catch {
        // note: if this is reached, this application has bigger problems
        unreachable;
    };
}
