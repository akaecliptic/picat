const std = @import("std");

/// top level
//

// binding file scope
const Client = @This();

// type aliases
const ArenaAllocator = std.heap.ArenaAllocator;
const AllocationError = std.mem.Allocator.Error;

const http = std.http;
const Writer = std.io.Writer;

const FetchError = std.http.Client.FetchError;
const ParseError = std.Uri.ParseError;

// expected errors
pub const Error = ParseError || FetchError || AllocationError;

// input output structs
pub const RequestOptions = struct {
    url: []const u8,

    method: ?http.Method = null,
    payload: ?[]const u8 = null,

    custom_headers: []const http.Header = &.{},
    standard_headers: http.Client.Request.Headers = .{},

    response_buffer_size: ?usize = null,
};

pub const RequestData = struct {
    // the last index of the response buffer
    end: usize,
    // the error status if request is unsuccessful
    err: ?[]const u8,
};

// constants
const default_buffer_size: usize = 8192;

/// fields
//

allocator: ArenaAllocator,
client: http.Client,

/// lifecycle
//

// entry point
pub fn init() Client {
    const allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    return .{
        .allocator = allocator,
        .client = http.Client{
            .allocator = allocator.child_allocator,
        },
    };
}

// release resources, must be called when done with client
pub fn deinit(self: *Client) void {
    self.allocator.deinit();
    self.client.deinit();
}

/// requests
///
/// note: all allocations are owned by client, response is copied into `out_buffer`
/// however, orginal resources are only freed with the deinitialisation of client
//

// wrapper for `Client.fetch`, basic once off request to specified url
pub fn fetch(self: *Client, out_buffer: []u8, options: RequestOptions) Error!RequestData {
    // step 0 - create writer
    var writer = try _create_writer(self, options.response_buffer_size);

    // step 1 - make request and return early if result is not success
    const response = try http.Client.fetch(&self.client, .{
        .location = .{
            .url = options.url,
        },
        .method = options.method,
        .payload = options.payload,
        .headers = options.standard_headers,
        .extra_headers = options.custom_headers,
        .response_writer = &writer,
    });

    // step 2 - check out buffer size vs read bytes, return early if out buffer is too small
    const read_bytes = writer.end;
    const writer_buffer = writer.buffer;

    // return an error if is large than buffer size,
    if (read_bytes >= out_buffer.len) {
        return error.OutOfMemory;
    }

    // step 3 - check response status and assign response err
    var status = response.status;
    const err = if (status.class() == .client_error or status.class() == .server_error) status.phrase() else null;

    // step 4 - copy bytes to out buffer and return read bytes
    @memcpy(out_buffer[0..read_bytes], writer_buffer[0..read_bytes]);

    return .{
        .end = read_bytes,
        .err = err,
    };
}

/// internal
//

// creates response writer for http requests
fn _create_writer(client: *Client, buffer_size: ?usize) AllocationError!Writer {
    // step 0 - assign allocator and buffer size
    var allocator = client.allocator.allocator();
    const writer_buffer_size = buffer_size orelse default_buffer_size;

    // step 1 - initialise writer used to collect http response
    const writer_buffer = try allocator.alloc(u8, writer_buffer_size);
    return Writer.fixed(writer_buffer);
}
