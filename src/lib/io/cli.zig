const std = @import("std");

const meta = @import("meta");

const aws = @import("../aws.zig");
const internal = @import("../internal.zig");

/// top level
//

// type aliases
const Allocator = std.mem.Allocator;

// expected errors
const Error = Allocator.Error || FriendlyCommandErrors;
const FriendlyCommandErrors = error{
    MaxValueLimit,
    InvalidOperation,
    InvalidInFile,
    InvalidOutFile,
    ValueOptionNotSet,
    AuthOptionNotSet,
    RegionOptionNotSet,
};

// supported options, and commands
const Operations = enum {
    @"--in",
    @"--out",
    @"--truncate",
    @"--value",
    @"--file",
    @"--secret",
    @"--auth",
    @"--region",
    @"--version",
    @"--help",

    pub fn get_operation(operation: []const u8) ?Operations {
        return std.meta.stringToEnum(Operations, operation);
    }
};

// representation of application commands
pub const Command = union(enum) {
    template: struct {
        in: []const u8 = "",
        out: []const u8 = "",
        truncate: bool = false,
        value: ?union(enum) {
            value: []const u8,
            file: []const u8,
            secret: []const u8,
        } = null,
        auth: ?[]const u8 = null,
        region: ?[]const u8 = null,
    },
    version: void,
    help: void,

    pub fn version_command() Command {
        return .version;
    }

    pub fn help_command() Command {
        return .help;
    }
};

// usage message for --help command
pub const usage_message =
    \\usage: picat --in=<file> --out=<file> [options]
    \\       picat [command]
    \\  options: 
    \\      --truncate=<bool>   if true, templating overwrites out file if already exists, otherwise,
    \\                          an error is produced. bool is [true|false], and default value is false
    \\      --value=<value>     template using a json object mapping template keys to values
    \\      --file=<file>       template using a json file with object mapping template keys to values 
    \\      --secret=<id>       template using a secret from aws secret manager fetched by sectret id, 
    \\                          this depends on --auth and --region options
    \\      --auth=<method>     authorize calls to aws services, supported methods are [imdvs|env]
    \\                          if region is defined in env, --region does not need to be set
    \\      --region=<region>   set the aws region used when looking for aws resources
    \\  commands:
    \\      --version           print the current application version
    \\      --help              print this usage message
;

/// public interface
//

// read command line arguments and return command structure
pub fn parse_args(args: []const []const u8) Error!Command {
    // step 0 - check if any arguments were provided
    if (args.len < 2) return Command.help_command();

    // step 1 - prepare default command
    var command: Command = .{ .template = .{} };

    // step 2 - loop over each argument
    for (args[1..]) |arg| {
        // step 2.1 - split current argument by into name and value
        var split = std.mem.splitAny(u8, arg, "=");

        const first = split.first();
        const rest = split.rest();

        // step 2.2 - validate lenght of option value
        if (rest.len > meta.constraints.max_value_len) {
            return error.MaxValueLimit;
        }

        // step 2.3 - convert name to operation and handle accordingly
        const operation = Operations.get_operation(first);

        if (operation) |value| switch (value) {
            .@"--in" => {
                if (internal.strings.is_blank(rest)) {
                    return error.InvalidInFile;
                }

                command.template.in = rest;
            },
            .@"--out" => {
                if (internal.strings.is_blank(rest)) {
                    return error.InvalidOutFile;
                }

                command.template.out = rest;
            },
            .@"--truncate" => {
                if (internal.strings.is_blank(rest)) {
                    return error.ValueOptionNotSet;
                }

                command.template.truncate = internal.strings.equals("true", rest);
            },
            .@"--value" => {
                if (internal.strings.is_blank(rest)) {
                    return error.ValueOptionNotSet;
                }

                command.template.value = .{ .value = rest };
            },
            .@"--file" => {
                if (internal.strings.is_blank(rest)) {
                    return error.ValueOptionNotSet;
                }

                command.template.value = .{ .file = rest };
            },
            .@"--secret" => {
                if (internal.strings.is_blank(rest)) {
                    return error.ValueOptionNotSet;
                }

                command.template.value = .{ .secret = rest };
            },
            .@"--auth" => {
                command.template.auth = rest;
            },
            .@"--region" => {
                command.template.region = rest;
            },
            .@"--version" => {
                return Command.version_command();
            },
            .@"--help" => {
                return Command.help_command();
            },
        } else {
            return error.InvalidOperation;
        }
    }

    // step 3 - extra validation
    if (command == .template) {
        const cmd = command.template;

        if (internal.strings.is_blank(cmd.in)) {
            return error.InvalidInFile;
        } else if (internal.strings.is_blank(cmd.out)) {
            return error.InvalidOutFile;
        }

        if (cmd.value == null) {
            return error.ValueOptionNotSet;
        }

        switch (cmd.value.?) {
            .secret => {
                const auth = aws.model.AWSAuth.get_auth(cmd.auth orelse "");

                if (auth == null) {
                    return error.AuthOptionNotSet;
                }
            },
            else => {},
        }
    }

    // step 4 - return default command
    return command;
}
