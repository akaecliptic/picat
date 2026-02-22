/// note: this file implements `SigV4` from aws, and will be the primary authorization method for aws api requests.
///
/// see: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html
/// see: https://github.com/aws-samples/sigv4-signing-examples
///
const std = @import("std");
const interal = @import("../internal.zig");

/// top level
//

// binding file scope
pub const SigV4 = @This();

// type aliases
const Allocator = std.mem.Allocator;

const Uri = std.Uri;
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
const HashSha256 = std.crypto.hash.sha2.Sha256;
const Header = std.http.Header;

const DateTime = interal.DateTime;
const strings = interal.strings;
const String = interal.strings.String;
const RequestOptions = interal.Client.RequestOptions;

//expected errors
pub const Error = Allocator.Error || Uri.ParseError || strings.Error || DateTime.Error;

// local structs
pub const AWSHeader = enum {
    x_amz_algorithm,
    x_amz_credential,
    x_amz_date,
    x_amz_signedheaders,
    x_amz_signature,
    x_amz_target,

    pub fn get(header: AWSHeader) []const u8 {
        return switch (header) {
            .x_amz_algorithm => "X-Amz-Algorithm",
            .x_amz_credential => "X-Amz-Credential",
            .x_amz_date => "X-Amz-Date",
            .x_amz_signedheaders => "X-Amz-SignedHeaders",
            .x_amz_signature => "X-Amz-Signature",
            .x_amz_target => "X-Amz-Target",
        };
    }
};

// input output structs
const SigV4Options = struct {
    aws_access_key_id: []const u8,
    aws_access_key_secret: []const u8,
    region: []const u8,
    service: []const u8,
};

// constants
const algorithm = "AWS4-HMAC-SHA256";
const scope_terminator = "aws4_request";
const signed_headers = "host;x-amz-date";

/// fields
//

allocator: Allocator,
datetime: DateTime,

aws_access_key_id: []const u8,
aws_access_key_secret: []const u8,
region: []const u8,
service: []const u8,

/// lifecycle
//

// entry point
pub fn init(allocator: Allocator, options: SigV4Options) DateTime.DateTimeError!SigV4 {
    const datetime = try DateTime.now();

    return .{
        .allocator = allocator,
        .datetime = datetime,

        .aws_access_key_id = options.aws_access_key_id,
        .aws_access_key_secret = options.aws_access_key_secret,
        .region = options.region,
        .service = options.service,
    };
}

/// public interface
//

// note: this function mutates the request input to attach the authorization header
//
// accepts options for aws request, adding `SigV4` authorization headers
pub fn authorize_request(self: *SigV4, request: *RequestOptions) Error!void {
    // step 0 - simplify headers from request
    const headers: []const Header = &.{
        .{
            .name = "host",
            .value = request.standard_headers.host.override,
        },
        .{
            .name = AWSHeader.get(.x_amz_date),
            .value = try self.datetime.to_string(self.allocator),
        },
    };

    // step 1 - create canonical string from request details
    const canonical_string = try self._create_canonical_string(
        request.url,
        request.payload orelse "",
        headers,
    );

    // step 2 - create string to sign, signing key, and then signature
    const string_to_sign = try self._create_string_to_sign(canonical_string);
    const signature = try self._create_signature(string_to_sign);

    // step 3 - create credential component of authorization header, and generate header
    const credential = try self._create_credential();
    const authorization_header = try strings.format(
        self.allocator,
        "{s} Credential={s}, SignedHeaders={s}, Signature={s}",
        .{
            algorithm,
            credential,
            signed_headers,
            signature,
        },
    );

    // step 4 - attach authorization header to request options
    request.standard_headers.authorization = .{ .override = authorization_header };
}

/// internal
//

// creates canonical string from request details, to be used in string to sign
fn _create_canonical_string(
    self: *SigV4,
    url: []const u8,
    payload: []const u8,
    headers: []const Header,
) Error!String {
    // step 0 - uri encode url
    const uri = try Uri.parse(url);

    // step 1 - extract canonical url (absolute path of uri)
    const encoded_path = uri.path.percent_encoded;
    const canonical_url = if (encoded_path.len == 0) "/" else encoded_path;

    // step 2 - combine headers to sing string in expected format
    var header_strings: [2][]const u8 = undefined;
    var index: u2 = 0;

    for (headers) |header| {
        const lower_case_header = try strings.lowercase(self.allocator, header.name);

        // note: from what i've tested, only these two headers are needed to create canonical headers
        if (strings.equals(lower_case_header, "host") or
            strings.equals(lower_case_header, "x-amz-date"))
        {
            header_strings[index] = try strings.format(self.allocator, "{s}:{s}\n", .{ lower_case_header, header.value });
            index += 1;
        }
    }

    const canonical_headers = try strings.concat(self.allocator, header_strings[0..]);

    // step 3 - generate hashed payload
    var buffer: [HashSha256.digest_length]u8 = undefined;
    HashSha256.hash(payload, buffer[0..], .{});
    const hashed_payload = try strings.hex_encode(self.allocator, buffer[0..]);

    // note: the canonical query string is empty because this project will only support POST requests
    return strings.join(self.allocator, "\n", &.{
        "POST",
        canonical_url,
        "", // canonical query string
        canonical_headers,
        signed_headers,
        hashed_payload,
    });
}

// creates credential used in authorization header
fn _create_credential(self: *SigV4) strings.Error!String {
    const date_string = try self.datetime.date.to_string(self.allocator);

    return strings.join(self.allocator, "/", &.{
        self.aws_access_key_id,
        date_string,
        self.region,
        self.service,
        scope_terminator,
    });
}

// creates the string to be signed by signing key
fn _create_string_to_sign(self: *SigV4, canonical_string: []const u8) strings.Error!String {
    const datetime_string = try self.datetime.to_string(self.allocator);
    const scope = try self._create_scope();

    var buffer: [HashSha256.digest_length]u8 = undefined;
    HashSha256.hash(canonical_string, buffer[0..], .{});
    const hash_canonical = try strings.hex_encode(self.allocator, buffer[0..]);

    return strings.join(self.allocator, "\n", &.{
        algorithm,
        datetime_string,
        scope,
        hash_canonical,
    });
}

// creates request scope
fn _create_scope(self: *SigV4) strings.Error!String {
    const date_string = try self.datetime.date.to_string(self.allocator);

    return strings.join(self.allocator, "/", &.{
        date_string,
        self.region,
        self.service,
        scope_terminator,
    });
}

// creates the key used to sign signature
fn _create_signing_key(self: *SigV4) Error!String {
    const date_string = try self.datetime.date.to_string(self.allocator);
    const aws_secret = try strings.concat(self.allocator, &.{ "AWS4", self.aws_access_key_secret });

    var date_key: [HashSha256.digest_length]u8 = undefined;
    HmacSha256.create(date_key[0..], date_string, aws_secret);

    var date_region_key: [HashSha256.digest_length]u8 = undefined;
    HmacSha256.create(date_region_key[0..], self.region, date_key[0..]);

    var date_region_service_key: [HashSha256.digest_length]u8 = undefined;
    HmacSha256.create(date_region_service_key[0..], self.service, date_region_key[0..]);

    var signing_key: []u8 = try self.allocator.alloc(u8, HashSha256.digest_length);
    HmacSha256.create(signing_key[0..][0..HashSha256.digest_length], scope_terminator, date_region_service_key[0..]);

    return signing_key;
}

// create the final signed string, aka signature, used in authization header
fn _create_signature(self: *SigV4, string: []const u8) Error!String {
    const signing_key = try self._create_signing_key();

    var hash: [HashSha256.digest_length]u8 = undefined;
    HmacSha256.create(hash[0..], string, signing_key);

    return strings.hex_encode(self.allocator, hash[0..]);
}

/// testing
//

const testing = std.testing;

// note: online hashing tool - https://emn178.github.io/online-tools/sha256.html
//
// intermediate keys for test_expected_signing_key:
//  63c759c9760554276662c319e123db9186acf1fc9eef62d4a82224f358a99d60 - date_key
//  827ad8d90c117f718a7eb9832d9581b9ed5be39ddada2635bce902f43050effd - date_region_key
//  815ba345f1b3bc72b1a5f7a707873f18c438b690bdbefd7e2bf1a52413665066 - date_region_service_key
//
// constants
const test_expected_canonical =
    \\POST
    \\/
    \\
    \\host:secretsmanager.us-east-1.amazonaws.com
    \\x-amz-date:20220222T000000Z
    \\
    \\host;x-amz-date
    \\e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
;
const test_expected_string_to_sign =
    \\AWS4-HMAC-SHA256
    \\20220222T000000Z
    \\20220222/us-east-1/secretsmanager/aws4_request
    \\ae30fc679fbad0c68a89d71b27a5602fae4bd16f049b1ff3a7ca333e8184c300
;
const test_expected_scope = "20220222/us-east-1/secretsmanager/aws4_request";
const test_expected_credential = "AKIEXAMPLE/20220222/us-east-1/secretsmanager/aws4_request";
const test_expected_signing_key = "e9d4c88685b498e497c917eb0edc11b6f58c7e5481d8b9166acb873c36c7db5f";
const test_expected_signature = "5391d8017c23212e78bdeadd25b250f186cfc0f230d600354def4c3cd4ceadb3";

// auxil functions
pub fn test_new_sigv4(allocator: Allocator) !SigV4 {
    var sigv4 = try SigV4.init(allocator, .{
        .aws_access_key_id = "AKIEXAMPLE",
        .aws_access_key_secret = "AWSSECRET",
        .region = "us-east-1",
        .service = "secretsmanager",
    });
    sigv4.datetime = try DateTime.from(2022, 2, 21, null, null, null);

    return sigv4;
}

// cases

test "create_canonical: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var sigv4 = try test_new_sigv4(allocator);

    const actual = try sigv4._create_canonical_string(
        "https://secretsmanager.us-east-1.amazonaws.com",
        "",
        &.{
            .{
                .name = "host",
                .value = "secretsmanager.us-east-1.amazonaws.com",
            },
            .{
                .name = AWSHeader.get(.x_amz_date),
                .value = try sigv4.datetime.to_string(allocator),
            },
        },
    );

    try testing.expectEqualStrings(test_expected_canonical, actual);
}

test "create_scope: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var sigv4 = try test_new_sigv4(allocator);

    const actual = try sigv4._create_scope();

    try testing.expectEqualStrings(test_expected_scope, actual);
}

test "create_credential: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var sigv4 = try test_new_sigv4(allocator);

    const actual = try sigv4._create_credential();

    try testing.expectEqualStrings(test_expected_credential, actual);
}

test "create_signing_key: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var sigv4 = try test_new_sigv4(allocator);

    const bytes = try sigv4._create_signing_key();
    const actual = try strings.hex_encode(allocator, bytes[0..]);

    try testing.expectEqualStrings(test_expected_signing_key, actual);
}

test "create_string_to_sign: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var sigv4 = try test_new_sigv4(allocator);

    const actual = try sigv4._create_string_to_sign(test_expected_canonical);

    try testing.expectEqualStrings(test_expected_string_to_sign, actual);
}

test "create_signature: validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var sigv4 = try test_new_sigv4(allocator);

    const actual = try sigv4._create_signature(test_expected_string_to_sign);

    try testing.expectEqualStrings(test_expected_signature, actual);
}
