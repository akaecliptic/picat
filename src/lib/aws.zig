const std = @import("std");

const internal = @import("internal.zig");

pub const ASMClient = @import("aws/asmc.zig");
pub const IMDSV2Client = @import("aws/imdsv.zig");
pub const SigV4 = @import("aws/sigv.zig");

pub const model = @import("aws/model.zig");

/// testing
//

const testing = std.testing;

test {
    testing.refAllDecls(ASMClient);
    testing.refAllDecls(IMDSV2Client);

    testing.refAllDecls(SigV4);

    testing.refAllDecls(model);

    // note: the clients can't really be unit tested, or at least
    // i can't think of how to do so effectively. will focus on
    // end-to-end testing
    _ = ASMClient;
    _ = IMDSV2Client;

    _ = SigV4;

    // note: not testing, not necessary
    _ = model;
}

test SigV4 {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    // create test sigv4 instance and request
    var sigv4 = try SigV4.test_new_sigv4(allocator);
    var request: internal.Client.RequestOptions = .{
        .url = "https://secretsmanager.us-east-1.amazonaws.com",
        .method = .POST,
        .payload = "",
        .standard_headers = .{
            .host = .{ .override = "secretsmanager.us-east-1.amazonaws.com" },
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = "application/x-amz-json-1.1" },
        },
        .custom_headers = &.{
            .{
                .name = SigV4.AWSHeader.get(.x_amz_target),
                .value = "secretsmanager.GetSecretValue",
            },
            .{
                .name = SigV4.AWSHeader.get(.x_amz_date),
                .value = try sigv4.datetime.to_string(allocator),
            },
        },
    };

    // authorize request, aka attach authorization header
    try sigv4.authorize_request(&request);

    const expected =
        "AWS4-HMAC-SHA256 " ++
        "Credential=AKIEXAMPLE/20220222/us-east-1/secretsmanager/aws4_request, " ++
        "SignedHeaders=host;x-amz-date, " ++
        "Signature=5391d8017c23212e78bdeadd25b250f186cfc0f230d600354def4c3cd4ceadb3";
    const actual = request.standard_headers.authorization.override;

    try testing.expectEqualStrings(expected, actual);
}
