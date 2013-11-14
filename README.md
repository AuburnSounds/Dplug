# What's this?

dplug is an audio package that aims to allow the creation of audio plugins. 
Currently very alpha.

## License

The VST SDK translation follow the original Steinberg VST license. 
If using the VST wrapper, you must agree to this license.

Public Domain (Unlicense).



## Contents


### core/
  * **log.d** logging interface + implementations (HTML file, colored console output...)
  * **queue.d** a dead simple queue/fifo/stack/ring-buffer, with a range interface
  * **lockedqueue.d** synchronized queue for thread communication
  * **memory.d** aligned malloc/free/realloc
  * **alignedbuffer.d** aligned array-like container
  * **text.d** string utilities

### net/
  * **uri.d** URI parsing (RFC 3986)
  * **httpclient.d** HTTP client (RFC 2616)
  * **cbor.d** CBOR serialization/deserialization (RFC 7049)


### math/
  * **vector.d** small vectors for 2D and 3D
  * **matrix.d** small matrices for 2D and 3D
  * **quaternion.d** quaternions
  * **wideint.d:** 2^N bits integers (recursive implementation, covers cent/ucent)
  * **box.d** half-open intervals (for eg. AABB)
  * **fixedpoint.d** fixed-point numbers
  * **fraction.d** rational numbers
  * **statistics.d** statistical functions
  * **solver.d** polynomial solvers up to quadratic
  * **simplerng.d** random distributions: a port of SimpleRNG from John D. Cook
  * **shapes.d** segment, triangle, sphere, ray...
  * **plane.d** 3D plane
  * **frustum.d** 3D frustum
  * **funcs.d** useful math functions
  * **simplexnoise.d** Simplex noise implementation
