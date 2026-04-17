zig test src-unified/test_gold_simple_all.zig -lc -O ReleaseFast
zig test src-unified/test_gold_small_all.zig -lc -O ReleaseFast

zig test src-unified/test_gold_simple.zig -lc -O ReleaseFast
zig test src-unified/test_gold_small.zig -lc -O ReleaseFast

zig test src-unified/test_gold_simple.zig -lc -O ReleaseFast --test-filter "Gold Simple Suite"
zig test src-unified/test_gold_small.zig -lc -O ReleaseFast --test-filter "Gold Small Suite"

zig test src-unified/test_gold_simple.zig -lc -O ReleaseFast
zig test src-unified/test_gold_small.zig -lc -O ReleaseFast
