// Argus WebGL ↔ Editor WebSocket bridge — browser-side glue.
//
// Unity calls these functions via [DllImport("__Internal")] from
// WebGLBridgeTransport.cs. We wrap the browser's native WebSocket API
// with a queue of inbound binary messages that Unity can drain on each
// frame (polling, since Unity's main thread can't be woken from JS).
//
// One global socket per Unity instance (only one game runs per page).
// If reconnect is needed, Unity calls ArgusWS_Close then ArgusWS_Connect
// again with a fresh URL.

var ArgusWebSocketBridge = {

  $ArgusWS_State: {
    socket: null,
    incoming: [],   // queue of Uint8Array messages waiting to be drained
    isOpen: false,
    errorMessage: null,
  },

  // Open a connection. Returns 1 on success (socket constructor accepted),
  // 0 on immediate failure. The socket is async — Unity polls IsOpen
  // separately to know when the handshake completed.
  //
  // urlPtr: pointer to UTF-8 null-terminated string in WASM memory
  ArgusWS_Connect: function (urlPtr, subprotoPtr) {
    var url = UTF8ToString(urlPtr);
    var subproto = UTF8ToString(subprotoPtr);
    try {
      ArgusWS_State.errorMessage = null;
      ArgusWS_State.isOpen = false;
      ArgusWS_State.incoming.length = 0;
      // Use the subprotocol so the server can version-check the wire format.
      ArgusWS_State.socket = subproto && subproto.length > 0
        ? new WebSocket(url, subproto)
        : new WebSocket(url);
      ArgusWS_State.socket.binaryType = 'arraybuffer';
      ArgusWS_State.socket.onopen = function () {
        ArgusWS_State.isOpen = true;
      };
      ArgusWS_State.socket.onclose = function (ev) {
        ArgusWS_State.isOpen = false;
        ArgusWS_State.errorMessage = 'closed code=' + ev.code;
      };
      ArgusWS_State.socket.onerror = function () {
        // Browser doesn't expose detailed error info to JS for security;
        // the close event with code 1006 follows.
        ArgusWS_State.errorMessage = 'transport error';
      };
      ArgusWS_State.socket.onmessage = function (ev) {
        // ev.data is ArrayBuffer (because binaryType=arraybuffer).
        ArgusWS_State.incoming.push(new Uint8Array(ev.data));
      };
      return 1;
    } catch (e) {
      ArgusWS_State.errorMessage = String(e);
      return 0;
    }
  },

  // Is the socket in OPEN state? Polled by Unity each frame to detect
  // when the handshake finishes + when the connection drops.
  ArgusWS_IsOpen: function () {
    return ArgusWS_State.isOpen ? 1 : 0;
  },

  // Send a binary frame. dataPtr → WASM heap; length is the byte count.
  // Returns 1 on success, 0 on failure (socket not open or send threw).
  ArgusWS_Send: function (dataPtr, length) {
    if (!ArgusWS_State.socket || !ArgusWS_State.isOpen) return 0;
    try {
      // Copy out of the WASM heap — the underlying memory could be reused
      // before the browser actually flushes the socket.
      var slice = HEAPU8.subarray(dataPtr, dataPtr + length);
      var copy = new Uint8Array(slice);
      ArgusWS_State.socket.send(copy);
      return 1;
    } catch (e) {
      ArgusWS_State.errorMessage = String(e);
      return 0;
    }
  },

  // Pull one queued message into the buffer Unity provides. Returns the
  // number of bytes written, 0 if no messages queued, -1 if the next
  // message is larger than outBufferLen (caller should resize + retry).
  ArgusWS_PollIncoming: function (outBufferPtr, outBufferLen) {
    if (ArgusWS_State.incoming.length === 0) return 0;
    var msg = ArgusWS_State.incoming[0];
    if (msg.length > outBufferLen) {
      // Tell Unity to grow its buffer. Stays at head of queue.
      return -1;
    }
    HEAPU8.set(msg, outBufferPtr);
    ArgusWS_State.incoming.shift();
    return msg.length;
  },

  // Close the socket + clear state. Safe to call when nothing's open.
  ArgusWS_Close: function () {
    if (ArgusWS_State.socket) {
      try { ArgusWS_State.socket.close(); } catch (e) { /* ignore */ }
    }
    ArgusWS_State.socket = null;
    ArgusWS_State.isOpen = false;
    ArgusWS_State.incoming.length = 0;
  },

  // Returns the last error string (or empty string). Unity copies + uses
  // for log messages. Returns a pointer to a JS-allocated UTF-8 string;
  // Unity is expected to copy + free promptly via _free.
  ArgusWS_GetLastError: function () {
    var msg = ArgusWS_State.errorMessage || '';
    var bufferSize = lengthBytesUTF8(msg) + 1;
    var buffer = _malloc(bufferSize);
    stringToUTF8(msg, buffer, bufferSize);
    return buffer;
  },
};

autoAddDeps(ArgusWebSocketBridge, '$ArgusWS_State');
mergeInto(LibraryManager.library, ArgusWebSocketBridge);
