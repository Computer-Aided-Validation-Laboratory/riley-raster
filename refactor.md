# REFACTOR:
- TESTS!

## General todo
- Overlapping csv logic and parsing

## Performance / Functionality Updates
- Add tessalated guess back into quad4newton and quad89 kernel, otherwise fall back to center?
    - Should be able to bias guess based on where the tessalated guess returns?
- Check calcInvZ for Newton and ClipPxM implementations - could be a bug

- Also calcInvZ and loadNodes all look the same - should be able to take out of kernel

- Is target_x, target_y in all ClipPxM kernels always subtracting x_off, y_off? Can we just bake this into the coord transform at the start? - Maybe not, cropping?

- Allow configuration of save name for files.
- Threading

## meshio.zig
- Remove prints 

## textureinterp.zig
- Add sample RGB
- Rename getPx1 to just getPx
- GO THROUGH THIS IN DETAIL!
