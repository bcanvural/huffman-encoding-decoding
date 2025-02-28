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

test "nodetest" {
    const leafNode = Node{ .leafNode = .{ .freq = 0, .charValue = 'a' } };
    const nonLeafNode = Node{ .nonLeafNode = .{ .freq = 0, .left = undefined, .right = undefined } };

    leafNode.speak();
    nonLeafNode.speak();

    try std.testing.expect(leafNode.isLeaf());
    try std.testing.expect(!nonLeafNode.isLeaf());
}
