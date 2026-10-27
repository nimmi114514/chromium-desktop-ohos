# JITFort permission status

The HAP declares both `ohos.permission.kernel.ALLOW_WRITABLE_CODE_MEMORY` and
`ohos.permission.kernel.ALLOW_USE_JITFORT_INTERFACE`. The Chromium 158 V8 port
contains a JITFort write/execute transition path. The new bundle name is
`com.example.chromium`; the previously installed `com.example.ohos.chromium`
package and its data are retained.

The JITFort ACL request and a matching signed Profile are still required before
the new package can exercise this path. The source build alone does not grant
the permission. Do not label JIT as working until the signed Profile includes
the required ACLs and device validation confirms V8 compilation and execution.

## Request draft

**Permission:** `ohos.permission.kernel.ALLOW_USE_JITFORT_INTERFACE`

**Usage scenario:** Chromium is a web browser with the V8 JavaScript engine
embedded in its renderer. When users open websites and interact with them, V8
JIT-compiles frequently used JavaScript into machine code. The browser needs
JITFort to manage the memory permission transitions for this runtime-generated
code. This is used only by the bundled V8 engine to execute web content; it is
not used for application hot updates or for adding unreviewed application
features.

**Reason for requesting the permission:** JIT compilation is part of Chromium's
normal JavaScript execution path and is needed for web compatibility and
performance. Without authorization, the browser must fall back to jitless mode,
which substantially reduces JavaScript execution performance. The permission
will only be used by the bundled browser engine for JIT execution. It will not
be used for application hot updates or to add features that have not passed
AppGallery review.
