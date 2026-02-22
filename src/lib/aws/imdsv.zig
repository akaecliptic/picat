/// note: this file implements `IMDSv2` from aws, and will be the main authentication method supported by this project,
/// mostly to avoid the use of third-party libraries, or tools.
///
/// this also means that iam roles are the primary method of authorization supported.
///
/// see: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html
/// see: https://github.com/aws/amazon-ec2-metadata-mock
///
const std = @import("std");

const interal = @import("../internal.zig");

const model = @import("model.zig");

/// top level
//

// binding file scope
pub const IMDSV2Client = @This();

// type aliases
const Allocator = std.mem.Allocator;

const Client = interal.Client;
const strings = interal.strings;
const String = interal.strings.String;

// expected errors
const Error = Client.Error || Allocator.Error || strings.Error || model.JsonParseError;

// local structs
const Endpoint = enum {
    api_token,
    meta_data,

    iam_info,
    iam_credentials,

    pub fn get(endpoint: Endpoint) []const u8 {
        return switch (endpoint) {
            .api_token => "api/token/",
            .meta_data => "meta-data/",
            .iam_info => "meta-data/iam/info/",
            .iam_credentials => "meta-data/iam/security-credentials/",
        };
    }
};

const Header = enum {
    create_metadata_token,
    use_metadata_token,

    pub fn get(header: Header) []const u8 {
        return switch (header) {
            .create_metadata_token => "X-aws-ec2-metadata-token-ttl-seconds",
            .use_metadata_token => "X-aws-ec2-metadata-token",
        };
    }
};

// input output structs
const ClientOptions = struct {
    base_url: []const u8 = default_base_url,
    version: []const u8 = default_version,
    token_ttl: []const u8 = default_token_ttl,
    response_size: usize = defaul_response_size,
};

// constants
const default_base_url = "http://169.254.169.254/";
const default_version = "latest/";
const default_token_ttl = "3600";
const defaul_response_size = 2048;

const buffer_token_size = 128;
const buffer_profile_size = 256;
const buffer_credential_size = 1024;

/// fields
//

allocator: Allocator,
client: Client,

base_url: []const u8,
version: []const u8,
response_size: usize,
token_ttl: []const u8,

/// lifecycle
//

// entry point
pub fn init(allocator: Allocator, options: ClientOptions) IMDSV2Client {
    return .{
        .allocator = allocator,
        .client = Client.init(),

        .base_url = options.base_url,
        .version = options.version,
        .response_size = options.response_size,
        .token_ttl = options.token_ttl,
    };
}

// release resources, must be called when done with client
pub fn deinit(self: *IMDSV2Client) void {
    self.client.deinit();
}

/// requests
//

// generate api token to communicate with `IMDSv2` api
pub fn generate_token(self: *IMDSV2Client) Error!String {
    const header = Header.get(.create_metadata_token);
    const endpoint = Endpoint.get(.api_token);
    const url = try strings.concat(self.allocator, &.{ self.base_url, self.version, endpoint });

    var buffer: []u8 = try self.allocator.alloc(u8, buffer_token_size);

    const response = try self.client.fetch(buffer, .{
        .url = url,
        .method = .PUT,
        .payload = "",
        .custom_headers = &.{.{
            .name = header,
            .value = self.token_ttl,
        }},
        .response_buffer_size = self.response_size,
    });

    return buffer[0..response.end];
}

// gets iam profile for the current ec2 instance
pub fn get_profile(self: *IMDSV2Client, token: []const u8) Error!String {
    const header = Header.get(.use_metadata_token);
    const endpoint = Endpoint.get(.iam_credentials);
    const url = try strings.concat(self.allocator, &.{ self.base_url, self.version, endpoint });

    var buffer: []u8 = try self.allocator.alloc(u8, buffer_profile_size);

    const response = try self.client.fetch(buffer, .{
        .url = url,
        .method = .GET,
        .custom_headers = &.{.{
            .name = header,
            .value = token,
        }},
        .response_buffer_size = self.response_size,
    });

    return buffer[0..response.end];
}

// get aws credentials associate with a specified profile
pub fn get_credentials(self: *IMDSV2Client, token: []const u8, profile: []const u8) Error!model.SecurityCredential {
    const header = Header.get(.use_metadata_token);
    const endpoint = Endpoint.get(.iam_credentials);
    const url = try strings.concat(self.allocator, &.{ self.base_url, self.version, endpoint, profile });

    var buffer: []u8 = try self.allocator.alloc(u8, buffer_credential_size);

    const response = try self.client.fetch(buffer, .{
        .url = url,
        .method = .GET,
        .custom_headers = &.{.{
            .name = header,
            .value = token,
        }},
        .response_buffer_size = self.response_size,
    });

    const json = try model.SecurityCredential.from_string(
        self.allocator,
        buffer[0..response.end],
    );

    return json.value;
}
