const std = @import("std");

/// top level
//

// type aliases
const Allocator = std.mem.Allocator;
const EnvMap = std.process.EnvMap;
const json = std.json;

const JsonString = []const u8;

// expected errors
pub const JsonParseError = error{FailedParsingAWSData};

/// models
//

pub const SecurityCredential = struct {
    pub const env_name_access_id = "AWS_ACCESS_KEY_ID";
    pub const env_name_secret_key = "AWS_SECRET_ACCESS_KEY";

    AccessKeyId: JsonString,
    SecretAccessKey: JsonString,

    // optionals
    Token: ?JsonString = null,
    Type: ?JsonString = null,
    Code: ?JsonString = null,
    LastUpdated: ?JsonString = null,
    Expiration: ?JsonString = null,

    const ParsedSecurityCredential = json.Parsed(@This());

    pub fn from_string(allocator: Allocator, string: []const u8) JsonParseError!ParsedSecurityCredential {
        return json.parseFromSlice(SecurityCredential, allocator, string, .{
            .parse_numbers = false,
            .ignore_unknown_fields = true,
        }) catch return error.FailedParsingAWSData;
    }

    pub fn from_env(envs: EnvMap) SecurityCredential {
        return .{
            .AccessKeyId = envs.get(env_name_access_id) orelse "",
            .SecretAccessKey = envs.get(env_name_secret_key) orelse "",
        };
    }
};

pub const ASMSecret = struct {
    ARN: JsonString,
    Name: JsonString,
    SecretString: JsonString,

    // note: three fields are purposefully excluded
    // `CreatedDate`, `VersionId`, and `VersionStages`
    // i have no use for them currently, so they will not be add

    const ParsedASMSecret = json.Parsed(@This());

    pub fn from_string(allocator: Allocator, string: []const u8) JsonParseError!ParsedASMSecret {
        return json.parseFromSlice(ASMSecret, allocator, string, .{
            .parse_numbers = false,
            .ignore_unknown_fields = true,
        }) catch return error.FailedParsingAWSData;
    }
};

pub const AWSRegion = enum {
    pub const env_name_region = "AWS_DEFAULT_REGION";

    // eu
    eu_west_1,
    eu_west_2,
    eu_central_1,

    // us
    us_west_1,
    us_west_2,
    us_east_1,
    us_east_2,

    // note: while very useful, i'm not a fan of this syntax
    // so yes, i'm wasting space here

    // ugos
    @"eu-west-1",
    @"eu-west-2",
    @"eu-central-1",

    @"us-west-1",
    @"us-west-2",
    @"us-east-1",
    @"us-east-2",

    pub fn get_string(region: AWSRegion) []const u8 {
        return switch (region) {
            .eu_west_1, .@"eu-west-1" => "eu-west-1",
            .eu_west_2, .@"eu-west-2" => "eu-west-2",
            .eu_central_1, .@"eu-central-1" => "eu-central-1",
            .us_west_1, .@"us-west-1" => "us-west-1",
            .us_west_2, .@"us-west-2" => "us-west-2",
            .us_east_1, .@"us-east-1" => "us-east-1",
            .us_east_2, .@"us-east-2" => "us-east-2",
        };
    }

    pub fn get_region(region: []const u8) ?AWSRegion {
        return std.meta.stringToEnum(AWSRegion, region);
    }

    pub fn from_env(envs: EnvMap) ?AWSRegion {
        return get_region(envs.get(env_name_region) orelse "");
    }
};

pub const AWSAuth = enum {
    env,
    imdvs,

    pub fn get_string(auth: AWSRegion) []const u8 {
        return switch (auth) {
            .env => "env",
            .imdvs => "imdvs",
        };
    }

    pub fn get_auth(auth: []const u8) ?AWSAuth {
        return std.meta.stringToEnum(AWSAuth, auth);
    }
};
