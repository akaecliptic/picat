/// note: this file implements a client for the aws secret manager's rest api.
/// requests are authorized via a personal implementation of `SigV4` as specified by aws.
///
/// see: `sigv.zig`
/// see: https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
/// see: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html
///
const std = @import("std");

const interal = @import("../internal.zig");

const sigv = @import("sigv.zig");
const model = @import("model.zig");

/// top level
//

// binding file scope
pub const ASMClient = @This();

// type aliases
const Allocator = std.mem.Allocator;

const Client = interal.Client;
const strings = interal.strings;

const AWSHeader = sigv.AWSHeader;

const SecurityCredential = model.SecurityCredential;

// expected errors
const Error = model.JsonParseError || sigv.Error || Client.Error || error{ InvalidHeader, InvalidEndpoint };

// input output structs
pub const ASMClientOptions = struct {
    region: []const u8,
};

// constants
const service = "secretsmanager";
const domain = "amazonaws.com";
const buffer_response_size = 2048;

/// fields
//

allocator: Allocator,
client: Client,
region: []const u8,

/// lifecycle
//

// entry point
pub fn init(allocator: Allocator, options: ASMClientOptions) Error!ASMClient {
    return .{
        .allocator = allocator,
        .client = Client.init(),
        .region = options.region,
    };
}

// release resources, must be called when done with client
pub fn deinit(self: *ASMClient) void {
    self.client.deinit();
}

/// requests
///
/// note: this client only supports one operation, `GetSecretValue`, that's it.
/// that's all that was planned, but this may change in the future
//

// note: underlying memory allocations for secrets fetched by this client are owned by this client.
// meaning, unless memory is moved, or copied, all secrets' lifetimes are tied to instance of client
// used to get their value
//
// gets a secrets value from secrets manager by secret id
pub fn get_secret_value(self: *ASMClient, secret_id: []const u8, credential: SecurityCredential) Error!model.ASMSecret {
    // step 0 - prepare request strings
    const payload = try strings.format(self.allocator, "{{ \"SecretId\":\"{s}\" }}", .{secret_id});
    const host = try strings.format(self.allocator, "{s}.{s}.{s}", .{ service, self.region, domain });
    const url = try strings.concat(self.allocator, &.{ "https://", host });

    // step 1 - initialize sigv4 module
    var sigv4 = try sigv.SigV4.init(self.allocator, .{
        .aws_access_key_id = credential.AccessKeyId,
        .aws_access_key_secret = credential.SecretAccessKey,
        .region = self.region,
        .service = service,
    });

    // step 2 - define request options
    var request: Client.RequestOptions = .{
        .url = url,
        .method = .POST,
        .payload = payload,
        .standard_headers = .{
            .host = .{ .override = host },
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = "application/x-amz-json-1.1" },
        },
        .custom_headers = &.{
            .{
                .name = AWSHeader.get(.x_amz_target),
                .value = "secretsmanager.GetSecretValue",
            },
            .{
                .name = AWSHeader.get(.x_amz_date),
                .value = try sigv4.datetime.to_string(self.allocator),
            },
        },
    };

    // step 3 - authorize request with sigv4
    try sigv4.authorize_request(&request);

    // step 4 - allocate buffer with clients allocator
    var buffer: [buffer_response_size]u8 = undefined;
    const response = try self.client.fetch(
        buffer[0..],
        request,
    );

    // step 5 - parse result to `ASMSecret` model and return value
    const json = try model.ASMSecret.from_string(
        self.allocator,
        buffer[0..response.end],
    );

    return json.value;
}
