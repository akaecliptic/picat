const std = @import("std");
const meta = @import("meta");

/// top level
//

// type aliases
const io = std.io;
const fs = std.fs;
const File = std.fs.File;

const DelimiterError = std.io.Reader.DelimiterError;

const Allocator = std.mem.Allocator;
const ArenaAlloctor = std.heap.ArenaAllocator;

// expected errors
const Error = DelimiterError || Allocator.Error || File.OpenError || error{ MaxFileLimit, FileWriteFailed };

// constants
const read_buffer_size: usize = meta.constraints.max_file_open;
const write_buffer_size: usize = 2048;

/// public interface
//

// high-level

// opens a file in read only, and returns its `File.Reader`
pub fn read_file(allocator: Allocator, path: []const u8) Error!File.Reader {
    const file = try open_file(path, false, false);
    return create_reader(allocator, file);
}

// opens a file in read write, and returns its `File.Writer`
pub fn write_file(allocator: Allocator, path: []const u8, truncate: ?bool) Error!File.Writer {
    const file = try open_file(path, true, truncate);
    return create_writer(allocator, file);
}

// read-write

// read bytes until new line or EOF is reached and returns bytes read
pub fn read_line(reader: *File.Reader) DelimiterError![]const u8 {
    return reader.interface.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.EndOfStream => {
            // note: i'll need to keep an eye on this.
            //
            // the idea is to squeeze all remaining bytes from the buffer.
            // otherwise, if the last line is not a new line character, the
            // system will skip data

            const seek = reader.interface.seek;
            const end = reader.interface.end;
            const buffer = reader.interface.buffer;

            if (seek < end) {
                const content = buffer[seek..end];
                reader.interface.toss(end - seek);
                return content;
            }

            return err;
        },
        else => return err,
    };
}

// read and retun all bytes from file
pub fn read_all(reader: *File.Reader) Error![]const u8 {
    const stats = try reader.file.stat();

    if (stats.size > meta.constraints.max_file_open) {
        return error.MaxFileLimit;
    }

    return try reader.interface.take(stats.size);
}

// writes all bytes to file, typically ended by new line
pub fn write_line(writer: *File.Writer, bytes: []const u8) Error!void {
    writer.interface.writeAll(bytes) catch return error.FileWriteFailed;
    return writer.interface.flush() catch return error.FileWriteFailed;
}

// underlying

// opens file at specified path, creating file if needed
pub fn open_file(path: []const u8, create: bool, truncate: ?bool) Error!File {
    var cwd = fs.cwd();
    var file: File = undefined;

    if (create) {
        // note: this truncate doesn't really need to be an optional, but i think i'll allow
        // users to specify more options in the future, and it aligns with usage logic
        const overwrite = if (truncate == null) false else truncate.?;

        file = try cwd.createFile(path, .{
            .read = true,
            .truncate = overwrite, // true overwrites file if exists
            .exclusive = !overwrite, // true fails to open file if it exists
            .lock = .exclusive,
        });
    } else {
        file = try cwd.openFile(path, .{
            .mode = .read_only,
            .lock = .shared,
        });
    }

    const stats = try file.stat();

    if (stats.size > meta.constraints.max_file_open) {
        file.close();
        return error.MaxFileLimit;
    }

    return file;
}

// creates a `File.Reader` for a given file
pub fn create_reader(allocator: Allocator, file: File) Allocator.Error!File.Reader {
    const buffer: []u8 = try allocator.alloc(u8, read_buffer_size);
    return file.reader(buffer);
}

// creates a `File.Writer` for a given file
pub fn create_writer(allocator: Allocator, file: File) Allocator.Error!File.Writer {
    const buffer: []u8 = try allocator.alloc(u8, write_buffer_size);
    return file.writer(buffer);
}
