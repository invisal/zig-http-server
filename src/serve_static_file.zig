const std = @import("std");
const builtin = @import("builtin");

pub fn serve_static_file(client: std.net.Server.Connection, path: []u8) !void {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        std.debug.print("Error opening file: {}\n", .{err});
        try client.stream.writeAll("HTTP/1.1 404 Not Found\r\n\r\n");
        return err;
    };
    defer file.close();

    // Get the file extension
    const ext = std.fs.path.extension(path);
    var contentType: []const u8 = "application/octet-stream"; // Default content type

    if (std.mem.eql(u8, ext, ".html")) {
        contentType = "text/html";
    } else if (std.mem.eql(u8, ext, ".css")) {
        contentType = "text/css";
    } else if (std.mem.eql(u8, ext, ".js")) {
        contentType = "application/javascript";
    } else if (std.mem.eql(u8, ext, ".png")) {
        contentType = "image/png";
    } else if (std.mem.eql(u8, ext, ".jpg") or std.mem.eql(u8, ext, ".jpeg")) {
        contentType = "image/jpeg";
    } else if (std.mem.eql(u8, ext, ".gif")) {
        contentType = "image/gif";
    } else if (std.mem.eql(u8, ext, ".svg")) {
        contentType = "image/svg+xml";
    } else if (std.mem.eql(u8, ext, ".ico")) {
        contentType = "image/x-icon";
    } else if (std.mem.eql(u8, ext, ".txt")) {
        contentType = "text/plain";
    } else if (std.mem.eql(u8, ext, ".json")) {
        contentType = "application/json";
    }

    const fileSize = try file.getEndPos();

    // Write HTTP headers in separate parts to avoid formatting overhead
    try client.stream.writeAll("HTTP/1.1 200 OK\r\n");
    try client.stream.writeAll("Content-Type: ");
    try client.stream.writeAll(contentType);
    try client.stream.writeAll("\r\nConnection: close\r\n");
    try client.stream.writeAll("Content-Length: ");

    // Convert fileSize to string
    var sizeBuf: [20]u8 = undefined; // Large enough for any file size
    const sizeStr = try std.fmt.bufPrint(&sizeBuf, "{d}", .{fileSize});
    try client.stream.writeAll(sizeStr);
    try client.stream.writeAll("\r\n\r\n");

    var buffer: [16384]u8 = undefined;
    while (true) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read == 0) break; // EOF
        try client.stream.writeAll(buffer[0..bytes_read]);
    }
}

// if (builtin.os.tag == .linux) {
//     // Linux sendfile implementation
//     const os = std.os;
//     const fd = file.handle;
//     const sock_fd = client.stream.handle;

//     var offset: i64 = 0;
//     var remaining = fileSize;

//     while (remaining > 0) {
//         const sent = os.linux.sendfile(sock_fd, fd, &offset, remaining);

//         if (sent < 1) break;

//         remaining -= sent;
//         if (remaining == 0) break;
//     }
// } else {
