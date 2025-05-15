const std = @import("std");
const serve_static_file = @import("serve_static_file.zig").serve_static_file;

const PORT = 8080;
const ROOT_DIRECTORY = "./public/";

pub fn main() !void {
    const address = try std.net.Address.parseIp4("127.0.0.1", PORT);
    var server = try address.listen(.{});
    defer server.deinit();

    std.log.info("Listening on port {d}", .{address.getPort()});

    var pool: std.Thread.Pool = undefined;
    const allocator = std.heap.page_allocator;
    try std.Thread.Pool.init(&pool, .{ .allocator = allocator, .n_jobs = 16 });
    defer pool.deinit();

    while (true) {
        const client = try server.accept();
        _ = try pool.spawn(testing, .{client});
    }
}

fn testing(client: std.net.Server.Connection) void {
    handle_client(client) catch |err| {
        std.log.err("Error handling client: {}", .{err});
    };
}

fn handle_client(client: std.net.Server.Connection) !void {
    defer client.stream.close();

    var bodyContentLength: usize = 0;

    var first_line_buffer: [2048]u8 = undefined;
    var line_buffer: [2048]u8 = undefined;

    // Reading the first line
    const first_line = client.stream.reader().readUntilDelimiter(&first_line_buffer, '\n') catch |err| {
        std.log.info("Error reading first line: {}", .{err});
        return err;
    };

    var splitFirstLine = std.mem.splitSequence(u8, first_line, " ");
    const method = splitFirstLine.next().?;
    var path = splitFirstLine.next().?;

    // Trimming path
    if (path.len > 0 and path[0] == '/') {
        path = path[1..];
    }

    if (path.len > 0 and path[path.len - 1] == '/') {
        path = path[0 .. path.len - 1];
    }

    if (path.len == 0) {
        path = "index.html"; // Default to index.html
    }

    std.log.info("Accepting request: {s} {s}", .{ method, path });

    // Reading all headers
    while (true) {
        const line = client.stream.reader().readUntilDelimiter(&line_buffer, '\n') catch |err| {
            std.log.err("Error reading line: {}", .{err});
            return err;
        };

        if (line.len == 0) break; // End of headers
        if (line[0] == '\r') break; // End of headers

        if (std.mem.startsWith(u8, line, "Content-Length: ")) {
            bodyContentLength = try std.fmt.parseInt(usize, line[16..], 10);
        }
    }

    // Reading body
    if (bodyContentLength > 0) {
        client.stream.reader().skipBytes(bodyContentLength, .{}) catch |err| {
            std.log.err("Error reading body: {}", .{err});
            return err;
        };
    }

    // Responding to the client
    if (std.mem.eql(u8, method, "GET")) {
        handle_get(client, path) catch |err| {
            std.log.err("Error handling GET request: {}", .{err});
            return;
        };
    } else {
        std.log.info("Unsupported method: {s}\n", .{method});
        try client.stream.writeAll("HTTP/1.1 405 Method Not Allowed\r\n\r\n");
    }
}

fn handle_get(client: std.net.Server.Connection, path: []const u8) !void {
    const resolved_path = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ ROOT_DIRECTORY, path });
    defer std.heap.page_allocator.free(resolved_path);
    try serve_static_file(client, resolved_path);
}
