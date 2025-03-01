const std = @import("std");
const print = std.debug.print;

pub const Node = union(enum) {
    leafNode: LeafNode,
    nonLeafNode: NonLeafNode,

    pub const LeafNode = struct {
        freq: u32,
        charValue: u8,
        pub fn speak(leafNode: LeafNode) void {
            _ = leafNode;

            std.debug.print("LeafNode speaking!\n", .{});
        }
    };

    pub const NonLeafNode = struct {
        freq: u32,
        left: *Node,
        right: *Node,
        pub fn speak(nonLeafNode: NonLeafNode) void {
            _ = nonLeafNode;

            std.debug.print("NonLeafNode speaking!\n", .{});
        }
    };

    pub fn speak(node: Node) void {
        switch (node) {
            inline else => |n| n.speak(),
        }
    }

    pub fn isLeaf(node: Node) bool {
        switch (node) {
            .leafNode => {
                return true;
            },
            .nonLeafNode => {
                return false;
            },
        }
    }
};
pub const KV = struct {
    key: u8,
    value: u32,
};

fn compare(context: void, a: KV, b: KV) std.math.Order {
    _ = context;
    return std.math.order(a.value, b.value);
}

pub const Heap = std.PriorityQueue(KV, void, compare);

test "nodetest" {
    const leafNode = Node{ .leafNode = .{ .freq = 0, .charValue = 'a' } };
    const nonLeafNode = Node{ .nonLeafNode = .{ .freq = 0, .left = undefined, .right = undefined } };

    leafNode.speak();
    nonLeafNode.speak();

    try std.testing.expect(leafNode.isLeaf());
    try std.testing.expect(!nonLeafNode.isLeaf());
}

test "heaptest" {
    var heap = Heap.init(std.testing.allocator, {});
    defer heap.deinit();

    const values = [_]u32{ 69, 10, 9, 8 };
    var kvs: [values.len]KV = undefined;
    for (0..values.len) |idx| {
        kvs[idx] = KV{ .key = undefined, .value = values[idx] };
        try heap.add(kvs[idx]);
    }
    for (heap.items) |item| {
        print("item: {d}\n", .{item.value});
    }

    try std.testing.expectEqual(8, heap.remove().value);
    try std.testing.expectEqual(9, heap.remove().value);
    try std.testing.expectEqual(10, heap.remove().value);
    try std.testing.expectEqual(69, heap.remove().value);
}
