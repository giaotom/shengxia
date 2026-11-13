var __sxReqs = {};
var __sxReqSeq = 1;
var __sxTimers = {};
var __sxTimerSeq = 1;
var __sxBuiltins = {};
var __sxGen = 0;
var __sxDone = false;
var __sxResult = null;
var __sxError = null;

function __sxText(value) {
  if (value == null) return "";
  return String(value);
}

var host = {
  platform: "ios",
  arch: "arm64",
  dir: __sxDir || "",
  dataDir: __sxDir || "",
  storage: {
    get: function (key) {
      var raw = __sxStorageGet(__sxText(key));
      if (raw == null || raw === "") return undefined;
      return JSON.parse(raw);
    },
    set: function (key, value) {
      __sxStorageSet(__sxText(key), JSON.stringify(value));
    },
    remove: function (key) {
      __sxStorageRemove(__sxText(key));
    }
  },
  language: function () { return "zh-CN"; },
  t: function (text) { return __sxTranslate(__sxText(text)); },
  setting: function (key) { return __sxSetting(__sxText(key)) || ""; },
  openURL: function (url) { __sxOpen(__sxText(url)); },
  signInPrompt: function (prompt) { __sxSignIn(JSON.stringify(prompt || {})); },
  crypto: {
    md5: function (text) { return __sxMD5(__sxText(text)); },
    aesEcbEncrypt: function (key, text) {
      var out = __sxAES(__sxText(key), __sxText(text));
      if (out.indexOf("ERR ") === 0) throw new Error(out.slice(4));
      return out;
    }
  },
  removeDataDir: function () {},
  waitForRedirect: function () {
    return Promise.reject(Object.assign(new Error("声匣不能在本机开一个登录回调端口"), { code: "unsupported" }));
  },
  webSignIn: function (options) {
    return new Promise(function (resolve, reject) {
      var id = __sxReqSeq++;
      __sxReqs[id] = {
        resolve: function (cookie) { resolve({ cookie: cookie }); },
        reject: reject
      };
      __sxWebSignIn(id, JSON.stringify(options || {}));
    });
  },
  spawn: function () {
    throw Object.assign(new Error("声匣不会启动外部程序，也不带 ffmpeg"), { code: "unsupported" });
  }
};

var console = {
  log: function () { __sxLog("log", Array.prototype.map.call(arguments, __sxText).join(" ")); },
  info: function () { __sxLog("info", Array.prototype.map.call(arguments, __sxText).join(" ")); },
  warn: function () { __sxLog("warn", Array.prototype.map.call(arguments, __sxText).join(" ")); },
  error: function () { __sxLog("error", Array.prototype.map.call(arguments, __sxText).join(" ")); }
};

function atob(input) {
  var str = String(input).replace(/=+$/, "");
  var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  if (typeof globalThis.atob === "function" && globalThis.atob !== atob) return globalThis.atob(input);
  var out = "";
  var buffer = 0;
  var bits = 0;
  for (var i = 0; i < str.length; i++) {
    var val = chars.indexOf(str.charAt(i));
    if (val < 0) continue;
    buffer = (buffer << 6) | val;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out += String.fromCharCode((buffer >> bits) & 255);
    }
  }
  return out;
}

function btoa(input) {
  var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  var str = String(input);
  var out = "";
  for (var i = 0; i < str.length; i += 3) {
    var a = str.charCodeAt(i);
    var b = i + 1 < str.length ? str.charCodeAt(i + 1) : 0;
    var c = i + 2 < str.length ? str.charCodeAt(i + 2) : 0;
    var triple = (a << 16) | (b << 8) | c;
    out += chars.charAt((triple >> 18) & 63);
    out += chars.charAt((triple >> 12) & 63);
    out += i + 1 < str.length ? chars.charAt((triple >> 6) & 63) : "=";
    out += i + 2 < str.length ? chars.charAt(triple & 63) : "=";
  }
  return out;
}

function __sxBytesFromBase64(text) {
  var binary = atob(text || "");
  var bytes = new Uint8Array(binary.length);
  for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function __sxUtf8FromBytes(bytes) {
  var out = "";
  for (var i = 0; i < bytes.length; i++) {
    var c = bytes[i];
    if (c < 128) out += String.fromCharCode(c);
    else if (c < 224) {
      out += String.fromCharCode(((c & 31) << 6) | (bytes[++i] & 63));
    } else if (c < 240) {
      out += String.fromCharCode(((c & 15) << 12) | ((bytes[++i] & 63) << 6) | (bytes[++i] & 63));
    } else {
      var u = ((c & 7) << 18) | ((bytes[++i] & 63) << 12) | ((bytes[++i] & 63) << 6) | (bytes[++i] & 63);
      u -= 0x10000;
      out += String.fromCharCode(0xD800 + (u >> 10), 0xDC00 + (u & 1023));
    }
  }
  return out;
}

function __sxBytesFromUtf8(text) {
  var str = String(text);
  var bytes = [];
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63));
    else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < str.length) {
      var c2 = str.charCodeAt(++i);
      var u = ((c - 0xD800) << 10) + (c2 - 0xDC00) + 0x10000;
      bytes.push(0xF0 | (u >> 18), 0x80 | ((u >> 12) & 63), 0x80 | ((u >> 6) & 63), 0x80 | (u & 63));
    } else bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return new Uint8Array(bytes);
}

if (typeof TextEncoder === "undefined") {
  function TextEncoder() {}
  TextEncoder.prototype.encode = function (text) { return __sxBytesFromUtf8(text); };
}
if (typeof TextDecoder === "undefined") {
  function TextDecoder() {}
  TextDecoder.prototype.decode = function (bytes) { return __sxUtf8FromBytes(bytes || new Uint8Array()); };
}
if (typeof AbortController === "undefined") {
  function AbortController() {
    this.signal = { aborted: false, addEventListener: function () {}, removeEventListener: function () {} };
  }
  AbortController.prototype.abort = function () { this.signal.aborted = true; };
}
if (typeof URLSearchParams === "undefined") {
  function URLSearchParams(init) {
    this._pairs = [];
    if (typeof init === "string") {
      var query = init.charAt(0) === "?" ? init.slice(1) : init;
      if (query) {
        var parts = query.split("&");
        for (var i = 0; i < parts.length; i++) {
          var cut = parts[i].indexOf("=");
          var k = cut < 0 ? parts[i] : parts[i].slice(0, cut);
          var v = cut < 0 ? "" : parts[i].slice(cut + 1);
          this._pairs.push([decodeURIComponent(k), decodeURIComponent(v)]);
        }
      }
    }
  }
  URLSearchParams.prototype.append = function (k, v) { this._pairs.push([String(k), String(v)]); };
  URLSearchParams.prototype.set = function (k, v) {
    this._pairs = this._pairs.filter(function (pair) { return pair[0] !== String(k); });
    this.append(k, v);
  };
  URLSearchParams.prototype.get = function (k) {
    for (var i = 0; i < this._pairs.length; i++) if (this._pairs[i][0] === String(k)) return this._pairs[i][1];
    return null;
  };
  URLSearchParams.prototype.toString = function () {
    return this._pairs.map(function (pair) {
      return encodeURIComponent(pair[0]) + "=" + encodeURIComponent(pair[1]);
    }).join("&");
  };
}

function BufferFrom(input, encoding) {
  var bytes;
  if (typeof input === "string") {
    if (encoding === "hex") {
      var clean = input.replace(/\s+/g, "");
      bytes = new Uint8Array(clean.length / 2);
      for (var i = 0; i < bytes.length; i++) bytes[i] = parseInt(clean.substr(i * 2, 2), 16);
    } else if (encoding === "base64") bytes = __sxBytesFromBase64(input);
    else bytes = __sxBytesFromUtf8(input);
  } else if (input instanceof Uint8Array) bytes = new Uint8Array(input);
  else if (Array.isArray(input)) bytes = new Uint8Array(input);
  else bytes = new Uint8Array(Number(input) || 0);
  bytes.toString = function (enc) {
    if (enc === "hex") {
      var hex = "";
      for (var j = 0; j < bytes.length; j++) hex += (bytes[j] < 16 ? "0" : "") + bytes[j].toString(16);
      return hex;
    }
    if (enc === "base64") {
      var binary = "";
      for (var k = 0; k < bytes.length; k++) binary += String.fromCharCode(bytes[k]);
      return btoa(binary);
    }
    return __sxUtf8FromBytes(bytes);
  };
  return bytes;
}

var Buffer = {
  from: BufferFrom,
  alloc: function (size) { return BufferFrom(new Uint8Array(size || 0)); },
  concat: function (list) {
    var total = 0;
    for (var i = 0; i < list.length; i++) total += list[i].length;
    var out = new Uint8Array(total);
    var offset = 0;
    for (var j = 0; j < list.length; j++) { out.set(list[j], offset); offset += list[j].length; }
    return BufferFrom(out);
  },
  isBuffer: function (value) { return value instanceof Uint8Array; }
};

function setTimeout(fn, ms) {
  var id = ++__sxTimerSeq;
  __sxTimers[id] = function () { delete __sxTimers[id]; fn(); };
  __sxSchedule(id, ms || 0);
  return id;
}
function clearTimeout(id) { delete __sxTimers[id]; }
function setInterval(fn, ms) {
  var id = ++__sxTimerSeq;
  var delay = ms || 0;
  function tick() {
    if (!__sxTimers[id]) return;
    fn();
    if (__sxTimers[id]) __sxSchedule(id, delay);
  }
  __sxTimers[id] = tick;
  __sxSchedule(id, delay);
  return id;
}
function clearInterval(id) { delete __sxTimers[id]; }
function __sxFire(id) {
  var fn = __sxTimers[id];
  if (typeof fn === "function") fn();
}

function __sxHeaderObject(headers) {
  var out = {};
  if (!headers) return out;
  if (typeof headers.forEach === "function") {
    headers.forEach(function (value, key) { out[key] = value; });
    return out;
  }
  var keys = Object.keys(headers);
  for (var i = 0; i < keys.length; i++) out[keys[i]] = String(headers[keys[i]]);
  return out;
}

function fetch(input, init) {
  init = init || {};
  var url = typeof input === "string" ? input : (input && input.url) || String(input);
  if (init.signal && init.signal.aborted) return Promise.reject(new Error("aborted"));
  var method = (init.method || "GET").toUpperCase();
  var headers = __sxHeaderObject(init.headers);
  var body = null;
  if (init.body != null) {
    if (typeof init.body === "string") body = init.body;
    else if (typeof init.body.toString === "function" && init.body.constructor && init.body.constructor.name === "URLSearchParams") body = init.body.toString();
    else body = String(init.body);
  }
  return new Promise(function (resolve, reject) {
    var id = __sxReqSeq++;
    __sxReqs[id] = { resolve: resolve, reject: reject, url: url };
    __sxFetch(id, JSON.stringify({ url: url, method: method, headers: headers, body: body }));
  });
}

function __sxFinish(id, status, headersJson, bodyBase64, error) {
  var pending = __sxReqs[id];
  delete __sxReqs[id];
  if (!pending) return;
  if (error) {
    pending.reject(new Error(error));
    return;
  }
  var bytes = __sxBytesFromBase64(bodyBase64 || "");
  var headerMap = {};
  try { headerMap = JSON.parse(headersJson || "{}"); } catch (e) { headerMap = {}; }
  var response = {
    ok: status >= 200 && status < 300,
    status: status,
    url: pending.url,
    headers: {
      get: function (name) {
        var want = String(name).toLowerCase();
        var keys = Object.keys(headerMap);
        for (var i = 0; i < keys.length; i++) if (keys[i].toLowerCase() === want) return headerMap[keys[i]];
        return null;
      }
    },
    text: function () { return Promise.resolve(__sxUtf8FromBytes(bytes)); },
    json: function () { return this.text().then(function (text) { return JSON.parse(text); }); },
    arrayBuffer: function () {
      var copy = new Uint8Array(bytes);
      return Promise.resolve(copy.buffer);
    }
  };
  pending.resolve(response);
}

function __sxInstallBuiltin(name, source, extra) {
  var module = { exports: {} };
  var exports = module.exports;
  var fn = new Function("module", "exports", "require", source + "\n" + (extra || "") + "\nreturn module.exports;");
  __sxBuiltins[name] = fn(module, exports, require);
}

function require(name) {
  if (Object.prototype.hasOwnProperty.call(__sxBuiltins, name)) return __sxBuiltins[name];
  var src = __sxBuiltin(name);
  if (!src) {
    var err = new Error("声匣没有这个模块：" + name);
    err.code = "unsupported";
    throw err;
  }
  var extra = "";
  if (name === "big-integer") extra = "module.exports = bigInt;";
  __sxInstallBuiltin(name, src, extra);
  return __sxBuiltins[name];
}

function __sxAxiosRequest(config) {
  config = config || {};
  var method = (config.method || "GET").toUpperCase();
  var url = config.url || "";
  if (config.baseURL && url.indexOf("http") !== 0) url = String(config.baseURL).replace(/\/$/, "") + "/" + String(url).replace(/^\//, "");
  var headers = Object.assign({}, config.headers || {});
  var body = config.data;
  if (body != null && typeof body !== "string") {
    if (!headers["Content-Type"] && !headers["content-type"]) headers["Content-Type"] = "application/json";
    body = JSON.stringify(body);
  }
  return fetch(url, { method: method, headers: headers, body: method === "GET" || method === "HEAD" ? undefined : body }).then(function (response) {
    return response.text().then(function (text) {
      var data = text;
      var ctype = response.headers.get("content-type") || "";
      if (config.responseType !== "text" && (ctype.indexOf("json") >= 0 || (text && (text.charAt(0) === "{" || text.charAt(0) === "[")))) {
        try { data = JSON.parse(text); } catch (e) { data = text; }
      }
      var result = { data: data, status: response.status, headers: {}, config: config, request: null };
      if (response.status >= 400) {
        var error = new Error("Request failed with status code " + response.status);
        error.response = result;
        throw error;
      }
      return result;
    });
  });
}

function __sxAxios(config) {
  if (typeof config === "string") return __sxAxiosRequest({ url: config });
  return __sxAxiosRequest(config);
}
__sxAxios.get = function (url, config) { return __sxAxiosRequest(Object.assign({}, config, { url: url, method: "GET" })); };
__sxAxios.post = function (url, data, config) { return __sxAxiosRequest(Object.assign({}, config, { url: url, data: data, method: "POST" })); };
__sxAxios.create = function (defaults) {
  var instance = function (config) { return __sxAxiosRequest(Object.assign({}, defaults || {}, config)); };
  instance.get = function (url, config) { return __sxAxiosRequest(Object.assign({}, defaults, config, { url: url, method: "GET" })); };
  instance.post = function (url, data, config) { return __sxAxiosRequest(Object.assign({}, defaults, config, { url: url, data: data, method: "POST" })); };
  return instance;
};
__sxBuiltins.axios = __sxAxios;

function __sxParseHTML(html) {
  var root = { tag: "root", attrs: {}, children: [], text: "" };
  var stack = [root];
  var rest = String(html || "");
  var pattern = /<!--[\s\S]*?-->|<\/([A-Za-z0-9]+)\s*>|<([A-Za-z0-9]+)([^>]*?)(\/?)>|([^<]+)/g;
  var match;
  while ((match = pattern.exec(rest))) {
    if (match[1]) {
      var name = match[1].toLowerCase();
      while (stack.length > 1 && stack[stack.length - 1].tag !== name) stack.pop();
      if (stack.length > 1) stack.pop();
    } else if (match[2]) {
      var node = { tag: match[2].toLowerCase(), attrs: {}, children: [], text: "", html: match[0] };
      var attrText = match[3] || "";
      var attr = /([:@A-Za-z0-9_-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s"'>]+))/g;
      var found;
      while ((found = attr.exec(attrText))) node.attrs[found[1]] = found[3] || found[4] || found[5] || "";
      stack[stack.length - 1].children.push(node);
      if (!match[4] && !/^(br|img|hr|meta|link|input|source)$/.test(node.tag)) stack.push(node);
    } else if (match[5]) {
      stack[stack.length - 1].children.push({ tag: "#text", attrs: {}, children: [], text: match[5] });
    }
  }
  return root;
}

function __sxNodeText(node) {
  if (!node) return "";
  if (node.tag === "#text") return node.text || "";
  return (node.children || []).map(__sxNodeText).join("");
}

function __sxMatch(node, selector) {
  if (!node || node.tag === "#text" || node.tag === "root") return false;
  var sel = String(selector).trim();
  if (sel.charAt(0) === "#") return node.attrs.id === sel.slice(1);
  if (sel.charAt(0) === ".") return (" " + (node.attrs.class || "") + " ").indexOf(" " + sel.slice(1) + " ") >= 0;
  var attr = sel.match(/^([A-Za-z0-9]*)\[([^\]]+)\]$/);
  if (attr) {
    var tagOk = !attr[1] || node.tag === attr[1].toLowerCase();
    var body = attr[2];
    var eq = body.match(/^([^~|^$*]+)\s*(?:[~|^$*])?=\s*["']?([^"']*)["']?$/);
    if (eq) return tagOk && node.attrs[eq[1]] === eq[2];
    return tagOk && Object.prototype.hasOwnProperty.call(node.attrs, body);
  }
  return node.tag === sel.toLowerCase();
}

function __sxFind(nodes, selector) {
  var found = [];
  function walk(node) {
    (node.children || []).forEach(function (child) {
      if (__sxMatch(child, selector)) found.push(child);
      walk(child);
    });
  }
  nodes.forEach(walk);
  return found;
}

function __sxWrap(nodes) {
  return {
    length: nodes.length,
    text: function () { return nodes.map(__sxNodeText).join(""); },
    html: function () { return nodes.map(function (node) { return node.html || __sxNodeText(node); }).join(""); },
    attr: function (name) { return nodes[0] && nodes[0].attrs ? nodes[0].attrs[name] : undefined; },
    find: function (selector) { return __sxWrap(__sxFind(nodes, selector)); },
    eq: function (index) { return __sxWrap(nodes[index] ? [nodes[index]] : []); },
    first: function () { return this.eq(0); },
    each: function (fn) { nodes.forEach(function (node, index) { fn.call(node, index, __sxWrap([node])); }); return this; }
  };
}

__sxBuiltins.cheerio = {
  load: function (html) { return __sxWrap([__sxParseHTML(html)]); }
};

function __sxJoinURL(base, path) {
  if (!path) return base;
  if (/^https?:\/\//i.test(path)) return path;
  return String(base || "").replace(/\/$/, "") + "/" + String(path).replace(/^\//, "");
}

__sxBuiltins.webdav = {
  createClient: function (base, options) {
    options = options || {};
    var auth = options.username ? "Basic " + btoa(String(options.username) + ":" + String(options.password || "")) : "";
    function request(method, path, body, headers) {
      var extra = Object.assign({}, headers || {});
      if (auth) extra.Authorization = auth;
      return fetch(__sxJoinURL(base, path), { method: method, headers: extra, body: body });
    }
    return {
      getFileContents: function (path, opts) {
        return request("GET", path).then(function (response) {
          if (!response.ok) throw new Error("webdav " + response.status);
          if (opts && opts.format === "text") return response.text();
          return response.arrayBuffer().then(function (buffer) { return new Uint8Array(buffer); });
        });
      },
      putFileContents: function (path, data) {
        var body = typeof data === "string" ? data : __sxUtf8FromBytes(data);
        return request("PUT", path, body).then(function (response) {
          if (!response.ok) throw new Error("webdav " + response.status);
        });
      },
      getDirectoryContents: function (path) {
        return request("PROPFIND", path || "/", null, { Depth: "1" }).then(function (response) {
          return response.text().then(function (text) {
            var names = [];
            var match;
            var pattern = /<[^>]*href[^>]*>([^<]+)</gi;
            while ((match = pattern.exec(text))) names.push(match[1]);
            return names.map(function (href) { return { filename: href, href: href }; });
          });
        });
      }
    };
  }
};

function __sxInvoke(name, json) {
  var gen = ++__sxGen;
  __sxDone = false;
  __sxResult = null;
  __sxError = null;
  Promise.resolve().then(function () {
    var fn = __sxExports[name];
    if (typeof fn !== "function") {
      var missing = new Error("这个插件没有「" + name + "」");
      missing.code = "unsupported";
      throw missing;
    }
    return fn(json ? JSON.parse(json) : undefined);
  }).then(function (value) {
    if (gen !== __sxGen) return;
    __sxResult = JSON.stringify(value === undefined ? null : value);
    __sxDone = true;
  }, function (error) {
    if (gen !== __sxGen) return;
    __sxError = JSON.stringify({
      message: String(error && (error.message || error) || error),
      code: (error && error.code) || ""
    });
    __sxDone = true;
  });
}

function __sxCommonJS(source) {
  var module = { exports: {} };
  var exports = module.exports;
  var fn = new Function("module", "exports", "require", source);
  fn(module, exports, require);
  __sxExports = module.exports || {};
}
