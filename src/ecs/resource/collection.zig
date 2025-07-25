const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TypeErasedCollection = struct {
    allocator: Allocator,
    ptr: *anyopaque,
    vtable: *const CollectionVTable,

    pub fn init(allocator: Allocator, comptime R: type) !TypeErasedCollection {
        const collection_ptr = try allocator.create(CollectionStorage(R));
        collection_ptr.* = CollectionStorage(R).init(allocator);

        return TypeErasedCollection{
            .allocator = allocator,
            .ptr = collection_ptr,
            .vtable = &comptime makeCollectionVTable(R),
        };
    }

    pub fn deinit(self: *const TypeErasedCollection) void {
        self.vtable.deinit(self.allocator, self.ptr);
    }

    pub fn clear(self: *const TypeErasedCollection) void {
        self.vtable.clear(self.ptr);
    }

    pub fn remove(self: *const TypeErasedCollection, index: usize) void {
        self.vtable.remove(self.ptr, index);
    }

    /// Cast a type erased collection to a CollectionStorage(R) of type R.
    ///
    /// Note: casting to an inappropriate type *will* lead to undefined behavior.
    pub fn cast(type_erased_ptr: *anyopaque, comptime R: type) *CollectionStorage(R) {
        return @alignCast(@ptrCast(type_erased_ptr));
    }
};

pub const CollectionVTable = struct {
    deinit: *const fn (Allocator, *anyopaque) void,
    clear: *const fn (*anyopaque) void,
    remove: *const fn (*anyopaque, usize) void,
};

pub fn makeCollectionVTable(comptime R: type) CollectionVTable {
    return CollectionVTable{
        .deinit = struct {
            fn func(allocator: Allocator, type_erased_ptr: *anyopaque) void {
                const storage = TypeErasedCollection.cast(type_erased_ptr, R);
                storage.deinit();
                allocator.destroy(storage);
            }
        }.func,
        .clear = struct {
            fn func(type_erased_ptr: *anyopaque) void {
                const storage = TypeErasedCollection.cast(type_erased_ptr, R);
                storage.clear();
            }
        }.func,
        .remove = struct {
            fn func(type_erased_ptr: *anyopaque, index: usize) void {
                const storage = TypeErasedCollection.cast(type_erased_ptr, R);
                _ = storage.remove(index);
            }
        }.func,
    };
}

pub fn CollectionStorage(comptime R: type) type {
    return struct {
        const Self = @This();

        collection: std.ArrayList(R),

        pub fn init(allocator: Allocator) Self {
            return Self{
                .collection = std.ArrayList(R).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // deinit resources if necessary
            if (@hasDecl(R, "deinit")) {
                for (self.collection.items) |*resource| {
                    resource.deinit();
                }
            }
            self.collection.deinit();
        }

        pub fn clear(self: *Self) void {
            self.collection.clearRetainingCapacity();
        }

        pub fn remove(self: *Self, index: usize) R {
            return self.collection.orderedRemove(index);
        }

        pub fn swapRemove(self: *Self, index: usize) void {
            return self.collection.swapRemove(index);
        }
    };
}
