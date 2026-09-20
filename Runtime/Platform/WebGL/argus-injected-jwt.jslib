// Phase W — bridge into the portal-proxy injected JWT.
//
// The customer's portal page (or their server backend's HTML template)
// sets `window.argusInjectedJwt = "<jwt>"` before the WebGL build boots.
// The runtime reads it on every send so a fresh JWT minted server-side
// is picked up automatically — refresh policy is the portal's problem.
//
// API:
//   ArgusJwt_GetInjected() → IntPtr     // null-terminated UTF-8, malloc'd
//   ArgusJwt_Free(ptr)                  // free the buffer when done
//
// Returns "" (empty string) when no JWT has been injected — the C# side
// treats that as "no auth available, drop the send" + logs a one-time
// warning so the integration mistake is visible.

mergeInto(LibraryManager.library, {
  ArgusJwt_GetInjected: function() {
    var token = (typeof window !== "undefined" && window.argusInjectedJwt) || "";
    var bytes = lengthBytesUTF8(token) + 1;
    var ptr = _malloc(bytes);
    stringToUTF8(token, ptr, bytes);
    return ptr;
  },

  ArgusJwt_Free: function(ptr) {
    _free(ptr);
  },
});
