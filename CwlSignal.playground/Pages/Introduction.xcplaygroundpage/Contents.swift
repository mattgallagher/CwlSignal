/*:

# Introduction

## Build instructions

This playground requires the CwlSignal.framework built by the CwlSignal_macOS scheme. To satisfy this requirement:

1. You must open the CwlSignal.playground from inside the CwlSignal.xcodeproj (do not open this playground on its own).
2. Make certain the "CwlSignal_macOS.framework" is build by selecting the CwlSignal_macOS scheme (from the "Product" → "Scheme" menu or the scheme popup menu if it's available in your toolbar) and choose build ("Product" → "Build").
3. You may need to close and re-open any playground page before it will pick up the newly built framework. Close an already open playground page by pressing Command-Control-W (or selecting "Close Introduction.xcplaygroundpage" from the File menu) before clicking in the file tree to re-open.

Failure to follow these steps correctly will result in a "Playground execution failed: error: no such module 'CwlSignal'" error (along with a large number of stack frames) logged to the Debug Area (show with the "View" → "Debug Area" → "Show Debug Area" menu if it is not visible.

## Playground pages

1. [Basic input-signal pair](Basic%20input-signal%20pair)
2. [Serial pipelines - transform](Serial%20pipelines%20-%20transform)
3. [Serial pipelines - map](Serial%20pipelines%20-%20map)
4. [Serial pipelines - channel](Serial%20pipelines%20-%20channel)
5. [Serial pipelines - asynchronous](Serial%20pipelines%20-%20asynchronous)
6. [Parallel composition - combine](Parallel%20composition%20-%20combine)
7. [Parallel composition - merging](Parallel%20composition%20-%20merging)
8. [Advanced behaviors - continuous](Advanced%20behaviors%20-%20continuous)
9. [Advanced behaviors - lazy generation](Advanced%20behaviors%20-%20lazy%20generation)
10. [Advanced behaviors - capturing](Advanced%20behaviors%20-%20capturing)
11. [Advanced composition - nested operators](Advanced%20composition%20-%20nested%20operators)
12. [App scenario - threadsafe key-value storage](App%20scenario%20-%20threadsafe%20key-value%20storage)
13. [App scenario - dynamic view properties](App%20scenario%20-%20dynamic%20view%20properties)
14. And a [Play area](Play%20area) if you just want to goof around.

[Next: Basic channel](@next)
*/
