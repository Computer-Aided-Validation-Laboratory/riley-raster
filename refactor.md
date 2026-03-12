# REFACTOR:

## Performance / Functionality / Bug Updates
- Need to find the adaptive hull per element as part of preprocessing logic and store this for active elements only.
- Adaptive hull =
    - Project nodes onto screen in 2D
    - Check midside node is in or out
    - in: add midside node to hull
    - out: add bezier control point to hull
- Use adaptive hull for tri6, quad8 and quad9 to do early out test

- Allow configuration of save name for files.

## TODO: Mid-Term
- SIMD
- Threading
- Ask LLM to do a detailed code review, or get another LLM to do a detailed code review, CodeRabbit?

## TODO: Long-Term
- Finalise actual interface for external calls
- Create C ABI interfaces 
- Hook up to python through cython

## General Refactor
- Overlapping csv logic and parsing
- Tests! Unit tests

## meshio.zig
- Remove prints 

## textureinterp.zig
- Add sample RGB
- Rename getPx1 to just getPx
- GO THROUGH THIS IN DETAIL!
