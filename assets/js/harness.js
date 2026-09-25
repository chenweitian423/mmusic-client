// MusicFree 插件的宿主环境（跑在 QuickJS 里）—— M音乐 正式版
//
// 来源：`mmusic-embedded-spike/assets/js/harness.js`（可行性验证版），
// 正式版只做「加能力 + 收紧错误边界」，不改已验证过的调用形式。
//
// 设计原则：**Dart 侧代码尽量少**。网络走引擎注入的 XMLHttpRequest
// （quickjs_engine 的 enableXhr() 提供，Dart 侧用 package:http 真发请求），
// 所以这里只有一个纯 JS 的 axios 垫片，Dart 不必参与任何一次请求。
//
// ⚠️ 别改动 `require, __musicfree_require, module, exports, console, env, process`
//    这七个形参名字与顺序 —— 插件的混淆代码按位置/名字取用它们。
//
// 正式版相对 spike 版的四处改动（每一处都对应一个在 spike 里踩过的坑）：
//   ① 新增 `__callJsonSafe`：**永不 reject**，用 `{ok, value|error}` 信封返回。
//      spike 用的是 `__callJson`，插件抛错时走 handlePromise 的 completeError 分支，
//      错误文本要穿过 `JSON.stringify(getValue())` 那一层，到了 Dart 侧只剩一句
//      没有方法名的 JSON 片段 —— 排查时根本不知道是哪个调用炸的。
//   ② `__pluginMeta()` 补上 supportedSearchType，供 App 决定哪些插件能搜歌单。
//   ③ `__setEnvVars()` 让 Dart 能把用户变量（如自制源需要的 cookie）注入 env。
//   ④ `__diag()` 一次取回「依赖 / 插件 console / HTTP 记录」，失败时由 Dart 侧
//      统一落成一条可行动的错误信息。
//
// 保留的能力（都是排障用的，别删）：
//   `__scanRequires` 依赖扫描、`__setPropTrace` 属性访问追踪、`__http()` 请求流水。

var __HARNESS_VERSION = '2.0.0';

var __modules = {};
var __moduleSources = {};
var __moduleLoadLog = [];
var __requireLog = [];
var __consoleLog = [];
var __httpLog = [];
var __propLog = [];
var __traceProps = false;
var __plugin = null;

function __harnessVersion() { return __HARNESS_VERSION; }

// ---------- 依赖模块注册 ----------

function __defineModule(name, value) {
  __modules[name] = value;
  return true;
}

// ★ 只登记源码，**第一次 require 时才编译**。
//
// 为什么必须懒编译：依赖产物里 cheerio 一个就 343KB，而它只有网易在顶层 require；
// 酷我和 QQ 根本不碰它。若在装载阶段就把 6 个模块全部 `new Function(...)` 编一遍，
// 每个插件、每次冷启动都要白付几百毫秒（真机上更明显）。
// 懒编译之后，代价自动变成"谁用谁付"。
function __defineModuleSource(name, source) {
  __moduleSources[name] = source;
  return true;
}

// 加载 UMD/CJS 产物（如 he.js）：它自己会认 module/exports，我们只需提供这两个名字。
// 注意不要加 'use strict' —— UMD 通常靠 `this` 取全局对象（非严格模式下 `this` 是全局）。
function __loadUmd(source) {
  var module = { exports: {} };
  var exports = module.exports;
  var fn = new Function('module', 'exports', 'require', 'console', source);
  fn(module, exports, _require, console);
  return module.exports;
}

function __hasModule(name) {
  return Object.prototype.hasOwnProperty.call(__modules, name) ||
         Object.prototype.hasOwnProperty.call(__moduleSources, name);
}

function __requireModule(name) {
  if (Object.prototype.hasOwnProperty.call(__modules, name)) return __modules[name];
  if (Object.prototype.hasOwnProperty.call(__moduleSources, name)) {
    var t0 = (typeof Date !== 'undefined' && Date.now) ? Date.now() : 0;
    var built = __loadUmd(__moduleSources[name]);
    __modules[name] = built;
    __moduleLoadLog.push({ name: name, ms: Date.now() - t0 });
    return built;
  }
  return null;
}

function _require(name) {
  __requireLog.push(name);
  if (!__hasModule(name)) {
    // 报错要说清"缺哪个模块"，否则混淆代码抛出来的堆栈完全看不懂
    throw new Error('宿主未提供模块: ' + name);
  }
  var m = __requireModule(name);
  // ★ 关键互操作：插件是 TypeScript 编出来的，`import axios from 'axios'` 会被编译成
  //   `(0x0, axios_1['default'])(...)` —— 也就是**要求模块自带 default 属性**。
  //   只注册一个函数/对象而不补 default，插件会在第一行就抛 "TypeError: not a function"，
  //   堆栈只指向一个混淆过的列号，极难定位（spike 就在这里栽过一次）。
  if (m && (typeof m === 'function' || typeof m === 'object') && !m.default) {
    try { m.default = m; } catch (e) {}
  }
  return m;
}

// ---------- 属性访问追踪（排障利器）----------
//
// 插件崩了、堆栈只指向一个混淆列号时，最想知道的是「它到底按什么路径读响应」。
// 把 axios 的 response 包成 Proxy 就能把每一次属性访问记下来，连值的类型一起 ——
// 于是「response.data 是对象还是字符串」这类问题一次就能看清。
function __setPropTrace(on) { __traceProps = !!on; return true; }
function __clearPropLog() { __propLog = []; return true; }
function __propAccessLog() { return JSON.stringify(__propLog); }

function __traceValue(v, depth) {
  if (!__traceProps || depth > 6) return v;
  if (v === null || typeof v !== 'object') return v;
  return new Proxy(v, {
    get: function (t, k) {
      if (typeof k === 'symbol') return t[k];
      var val = t[k];
      var desc;
      if (val === undefined) desc = 'undefined';
      else if (val === null) desc = 'null';
      else if (typeof val === 'object') desc = Array.isArray(val) ? 'array' : 'object';
      else desc = typeof val + ' ' + String(val).slice(0, 60);
      __propLog.push(String(k) + ' -> ' + desc);
      return __traceValue(val, depth + 1);
    }
  });
}

// ---------- JSON 宽松修复 ----------
//
// 为什么需要它：中转站在紧凑格式下会把歌词里的**真实换行**直接塞进 JSON 字符串，
// 产出的是**非法 JSON**（`Bad control character in string literal`）。
// 严格解析失败后，axios 会把 data 留成字符串，插件接着写 `resp.data.data.url`
// 就崩成 "cannot read property 'url' of undefined" —— 堆栈只有混淆列号，
// 看起来像插件坏了或引擎不行，其实是上游数据不合法。
//
// 只做这一种修复，因为它**无歧义**：JSON 标准本来就不允许字符串里出现裸控制字符，
// 所以修复不会改变任何合法 JSON 的解析结果，只在"本来就会失败"的输入上生效。
function __repairJson(raw) {
  var out = '';
  var inStr = false;
  var esc = false;
  for (var i = 0; i < raw.length; i++) {
    var c = raw.charAt(i);
    var code = raw.charCodeAt(i);
    if (inStr) {
      if (esc) { out += c; esc = false; continue; }
      if (c === '\\') { out += c; esc = true; continue; }
      if (c === '"') { out += c; inStr = false; continue; }
      if (code < 0x20) {
        out += (c === '\n') ? '\\n'
             : (c === '\r') ? '\\r'
             : (c === '\t') ? '\\t'
             : '\\u' + ('000' + code.toString(16)).slice(-4);
        continue;
      }
      out += c;
      continue;
    }
    if (c === '"') { inStr = true; }
    out += c;
  }
  return out;
}

// ---------- axios 垫片 ----------

function __axiosSerializeParams(params) {
  var parts = [];
  for (var k in params) {
    if (!Object.prototype.hasOwnProperty.call(params, k)) continue;
    var v = params[k];
    if (v === undefined || v === null) continue;
    if (typeof v === 'object') v = JSON.stringify(v);
    parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(String(v)));
  }
  return parts.join('&');
}

function __axiosError(message, config, response) {
  var e = new Error(message);
  e.config = config;
  if (response) e.response = response;
  e.isAxiosError = true;
  return e;
}

function __axios(config) {
  if (typeof config === 'string') config = { url: config };
  config = config || {};

  var method = String(config.method || 'get').toUpperCase();
  var url = String(config.url || '');
  var params = config.params;
  if (params && typeof params === 'object') {
    var qs = __axiosSerializeParams(params);
    if (qs) url += (url.indexOf('?') >= 0 ? '&' : '?') + qs;
  }

  return new Promise(function (resolve, reject) {
    var xhr;
    try {
      xhr = new XMLHttpRequest();
    } catch (e) {
      reject(__axiosError('XMLHttpRequest 不可用（引擎的 enableXhr() 没生效?）', config, null));
      return;
    }

    try {
      xhr.open(method, url);

      var headers = config.headers || {};
      for (var h in headers) {
        if (!Object.prototype.hasOwnProperty.call(headers, h)) continue;
        if (headers[h] === undefined || headers[h] === null) continue;
        xhr.setRequestHeader(h, String(headers[h]));
      }

      var body = config.data;
      if (body !== undefined && body !== null && typeof body === 'object') {
        var hasCt = false;
        for (var hk in headers) {
          if (String(hk).toLowerCase() === 'content-type') hasCt = true;
        }
        if (!hasCt) xhr.setRequestHeader('Content-Type', 'application/json');
        body = JSON.stringify(body);
      }

      // 记录"发送时刻"。只有完成时刻的记录会让诊断有歧义：
      // 日志为空既可能是"根本没发出去"，也可能是"发出去了但一直没回来" ——
      // 这两种的排查方向完全相反。
      __httpLog.push({ phase: 'send', m: method, url: url, t: Date.now() });

      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) return;

        var raw = xhr.responseText;
        // 把每一次请求都记下来：排查"插件解析失败"时，第一时间要看的
        // 不是插件代码，而是"服务端到底回了什么"。
        __httpLog.push({
          phase: 'done',
          m: method,
          url: url,
          status: xhr.status,
          len: (raw === null || raw === undefined) ? -1 : String(raw).length,
          head: (raw === null || raw === undefined) ? '' : String(raw).substring(0, 160)
        });

        var data = raw;
        // axios 默认会把 JSON 文本解析成对象；这里按内容试探，失败就保留原文。
        //
        // ★ 失败原因必须记下来。spike 早期这里写的是 `catch (e) { data = raw; }` ——
        //   于是解析失败时插件拿到一个字符串，`response.data.data.url` 直接崩成
        //   "cannot read property 'url' of undefined"，堆栈只有混淆列号。
        //   静默吞掉异常是同一个老毛病：省掉一行日志，赔上半天排查。
        if (typeof raw === 'string' && raw.length) {
          var t = raw.replace(/^\s+/, '');
          if (t.charAt(0) === '{' || t.charAt(0) === '[') {
            try {
              data = JSON.parse(raw);
            } catch (pe) {
              // 严格解析失败 → 试一次宽松修复（见 __repairJson 的说明）。
              var fixed = null;
              try { fixed = JSON.parse(__repairJson(raw)); } catch (pe2) { fixed = null; }
              if (fixed !== null) {
                data = fixed;
                __httpLog.push({
                  phase: 'parse-repair',
                  url: url,
                  len: raw.length,
                  error: String(pe && pe.message ? pe.message : pe)
                });
              } else {
                data = raw;
                __httpLog.push({
                  phase: 'parse-fail',
                  url: url,
                  len: raw.length,
                  error: String(pe && pe.message ? pe.message : pe),
                  at: raw.length > 200 ? raw.slice(0, 120) + ' …尾部: ' + raw.slice(-60) : raw
                });
              }
            }
          }
        }

        var response = {
          data: data,
          status: xhr.status,
          statusText: xhr.statusText || '',
          headers: {},
          config: config,
          request: {}
        };

        var ok = (typeof config.validateStatus === 'function')
          ? config.validateStatus(xhr.status)
          : (xhr.status >= 200 && xhr.status < 300);

        if (ok) {
          resolve(__traceProps ? __traceValue(response, 0) : response);
        } else {
          reject(__axiosError('Request failed with status code ' + xhr.status, config, response));
        }
      };
      xhr.onerror = function () {
        __httpLog.push({ phase: 'error', m: method, url: url, error: 'onerror' });
        reject(__axiosError('Network Error', config, null));
      };
      // 引擎注入的 XHR 支持 ontimeout 钩子（见扩展 xhr.dart）
      xhr.ontimeout = function () {
        __httpLog.push({ phase: 'timeout', m: method, url: url });
        reject(__axiosError('timeout of ' + (config.timeout || 0) + 'ms exceeded', config, null));
      };
      if (config.timeout) {
        try { xhr.timeout = config.timeout; } catch (e) {}
      }
      // ★ 没设超时也要给一个默认值。上游挂起（限流/网络抖动）时，没有超时就会一路
      //   挂到宿主那层的超时，日志里只剩一句"没回来"，分不清是发不出去还是收不到。
      //   20s 够真实请求跑完（实测一次搜索 1.7s），超了就明确记为 timeout。
      try { if (!xhr.timeout) xhr.timeout = 20000; } catch (e) {}

      xhr.send(body === undefined || body === null ? null : body);
    } catch (e) {
      reject(__axiosError('axios 垫片异常: ' + (e && e.message ? e.message : e), config, null));
    }
  });
}

// 实测这三个插件都没用过 .get()/.post()，但留着兜底，免得换个插件就撞墙
function __axiosGet(url, cfg) {
  var c = cfg ? JSON.parse(JSON.stringify(cfg)) : {};
  c.url = url;
  c.method = 'get';
  return __axios(c);
}
function __axiosPost(url, data, cfg) {
  var c = cfg ? JSON.parse(JSON.stringify(cfg)) : {};
  c.url = url;
  c.data = data;
  c.method = 'post';
  return __axios(c);
}
__axios.get = __axiosGet;
__axios.post = __axiosPost;
__axios.put = __axiosPost;
__axios.delete = __axiosGet;
__axios.head = __axiosGet;
__axios.defaults = { headers: { common: {} } };
__axios.create = function () { return __axios; };

// ---------- 宿主环境桩 ----------

var __userVariables = {};

// Dart 侧注入用户变量（自制源可能靠它拿 cookie / token）。
// 入参是 JSON 字符串：跨语言边界只传字符串，少一层隐式转换少一类坑。
function __setEnvVars(json) {
  try {
    var v = JSON.parse(json || '{}');
    __userVariables = (v && typeof v === 'object') ? v : {};
  } catch (e) {
    __userVariables = {};
  }
  return true;
}

function __getUserVariables() { return __userVariables; }

var __env = {
  getUserVariables: __getUserVariables,
  os: 'android',
  appVersion: '1.0.0',
  lang: 'zh-CN'
};

var __process = {
  platform: 'android',
  version: '1.0.0',
  env: __env,
  ensurePluginInitialized: Promise.resolve()
};

function __setPlatform(os) {
  if (os) {
    __env.os = String(os);
    __process.platform = String(os);
  }
  return true;
}

function __setAppVersion(v) {
  if (v) {
    __env.appVersion = String(v);
    __process.version = String(v);
  }
  return true;
}

// 插件自己的 console 输出要单独收着：混淆代码里那几行 log 往往是最直接的自证，
// 而引擎自带的 console 会直接打到宿主 stdout（release 包里看不到）。
var __consoleShim = {
  log: function () { __recordConsole('log', arguments); },
  info: function () { __recordConsole('info', arguments); },
  warn: function () { __recordConsole('warn', arguments); },
  error: function () { __recordConsole('error', arguments); },
  debug: function () { __recordConsole('debug', arguments); }
};

function __recordConsole(level, args) {
  var parts = [];
  for (var i = 0; i < args.length; i++) {
    var a = args[i];
    try {
      parts.push(typeof a === 'object' ? JSON.stringify(a) : String(a));
    } catch (e) {
      parts.push('[不可序列化]');
    }
  }
  __consoleLog.push(level + ': ' + parts.join(' '));
  if (__consoleLog.length > 200) __consoleLog.splice(0, 100);
}

// ---------- 插件加载 ----------

function __loadPlugin(code) {
  __requireLog = [];
  var module = { exports: {} };
  var exports = module.exports;
  var fn = new Function(
    "'use strict'; return function(require, __musicfree_require, module, exports, console, env, process){" +
    code + "}"
  )();
  fn(_require, _require, module, exports, __consoleShim, __env, __process);
  __plugin = module.exports.default || module.exports;

  return __pluginMeta();
}

function __pluginMeta() {
  if (!__plugin) return JSON.stringify({ loaded: false });

  var methods = [];
  for (var k in __plugin) {
    if (typeof __plugin[k] === 'function') methods.push(k);
  }
  // supportedSearchType 官方契约是数组（'music' / 'sheet' / 'album' / 'artist' …）。
  // 缺省按 ['music'] 处理：绝大多数插件只支持搜歌，这个默认值最安全。
  var types = __plugin.supportedSearchType;
  if (!types) types = ['music'];
  if (typeof types === 'string') types = [types];

  return JSON.stringify({
    loaded: true,
    platform: __plugin.platform || null,
    version: __plugin.version || null,
    author: __plugin.author || null,
    srcUrl: __plugin.srcUrl || null,
    methods: methods,
    supportedSearchType: types,
    requiredModules: __requireLog
  });
}

// ---------- 调用 ----------

// 注意：第二个参数是 **JS 数组**，不是 JSON 字符串。
// 早期写成 `JSON.parse(argsJson)` 时，Dart 侧传数组字面量进来会先被隐式转成
// `晴天,1,music` 再解析，报出 "Unexpected token '晴' in JSON" —— 看起来像插件或
// 引擎的问题，其实是包装层自己的类型错。
function __call(method, args) {
  if (!__plugin) throw new Error('插件尚未加载');
  if (typeof __plugin[method] !== 'function') {
    throw new Error('插件没有实现方法: ' + method);
  }
  return __plugin[method].apply(__plugin, args || []);
}

// ★ 跨语言边界上只传字符串。
//
// 为什么不让 Dart 直接取返回值：quickjs_engine 的 Promise 桥会把 JS 值转成
// **Dart 对象**，而 handle_promises 扩展拿到后再做 `"$res"` —— 也就是 Dart 的
// toString()。于是 Map 会变成 `{isEnd: false, data: [...]}` 这种**没有引号的**
// 伪 JSON，拿 jsonDecode 一解析就报 "Unexpected character"。
// 在 JS 侧先 JSON.stringify 成字符串，边界上就只剩 String，toString 是恒等的。
function __callJson(method, args) {
  return Promise.resolve(__call(method, args)).then(function (v) {
    var s = JSON.stringify(v);
    return s === undefined ? 'null' : s;
  });
}

// ★ 正式版的主入口：**永不 reject**，永远 resolve 一个信封
//   `{"ok":true,"value":...}` 或 `{"ok":false,"error":"...","kind":"..."}`。
//
// 为什么必须这样：走 handlePromise 的 completeError 分支时，错误值会先被
// `JSON.stringify(getValue())` 转一道，到 Dart 侧只剩一个不带方法名的 JSON 片段，
// 排查时根本不知道是哪一步炸的。信封里带上 method 与 kind，Dart 侧才能给出
// "取直链失败：插件抛错 …" 这种可行动的文案（而且不会把整个 JS 堆栈铺到界面上）。
function __callJsonSafe(method, args) {
  return Promise.resolve()
    .then(function () { return __call(method, args); })
    .then(function (v) {
      var s;
      try {
        s = JSON.stringify(v);
      } catch (e) {
        return JSON.stringify({
          ok: false,
          method: method,
          kind: 'unserializable',
          error: '插件返回值无法序列化: ' + (e && e.message ? e.message : e)
        });
      }
      return JSON.stringify({
        ok: true,
        method: method,
        value: s === undefined ? null : JSON.parse(s)
      });
    })
    .catch(function (e) {
      var msg = (e && e.message) ? String(e.message) : String(e);
      var kind = 'plugin-error';
      if (/not a function/i.test(msg)) kind = 'not-a-function';
      else if (/Network Error|status code \d+/i.test(msg)) kind = 'network';
      else if (/timeout/i.test(msg)) kind = 'timeout';
      else if (/宿主未提供模块/.test(msg)) kind = 'missing-module';
      else if (/没有实现方法/.test(msg)) kind = 'no-such-method';
      return JSON.stringify({ ok: false, method: method, kind: kind, error: msg });
    });
}

// ---------- 依赖扫描 ----------
//
// 一次性问出「这个插件到底 require 了哪些模块」。
//
// 为什么需要它：插件是混淆过的，静态 grep 只能靠猜（模块名会和普通字符串混在
// 一起，像 `he` 这种两字母名会命中一堆无关标识符，实测 网易.js 里 grep 'he'
// 有 39 次，但其中绝大多数是别的词的子串）。而逐个"跑一次→看缺哪个→补→再跑"
// 一轮要 1~2 分钟，5 个模块就是十几分钟。
//
// 做法：把 require 换成「记录名字 + 返回万能桩」，跑一次就拿到完整清单。
//   桩用 Proxy：任何属性取用都返回自身，自身可调用、可 new、可链式，
//   于是插件的顶层代码不会因缺依赖而崩，require 名单被完整记录下来。
//   `then` 特意返回 undefined —— 否则桩会被 Promise 当成 thenable 而挂住。
//
// 返回值里 error 非空只说明"顶层执行到某步失败"（很正常，桩毕竟不是真模块），
// **required 名单仍然是可信的**。
function __scanRequires(code) {
  __requireLog = [];

  var stubCache = {};
  function makeStub(name) {
    if (Object.prototype.hasOwnProperty.call(stubCache, name)) {
      return stubCache[name];
    }
    var p;
    var fn = function () { return p; };
    p = new Proxy(fn, {
      get: function (t, k) {
        if (typeof k === 'symbol') return undefined;
        if (k === 'default') return p;
        if (k === '__esModule') return true;
        if (k === 'then') return undefined;
        if (k === 'toString' || k === 'valueOf') {
          return function () { return '[stub ' + name + ']'; };
        }
        return p;
      },
      has: function () { return true; },
      apply: function () { return p; },
      construct: function () { return p; }
    });
    stubCache[name] = p;
    return p;
  }

  function looseRequire(name) {
    __requireLog.push(String(name));
    if (Object.prototype.hasOwnProperty.call(__modules, name)) {
      return __modules[name];
    }
    return makeStub(name);
  }

  var err = null;
  try {
    var module = { exports: {} };
    var exports = module.exports;
    var fn = new Function(
      "'use strict'; return function(require, __musicfree_require, module, exports, console, env, process){" +
      code + "}"
    )();
    fn(looseRequire, looseRequire, module, exports, __consoleShim, __env, __process);
  } catch (e) {
    err = String(e && e.message ? e.message : e);
  }

  var uniq = [];
  var needHost = [];
  for (var i = 0; i < __requireLog.length; i++) {
    var n = __requireLog[i];
    if (uniq.indexOf(n) < 0) uniq.push(n);
    if (!__hasModule(n) && needHost.indexOf(n) < 0) {
      needHost.push(n);
    }
  }

  return JSON.stringify({
    required: uniq,
    callCount: __requireLog.length,
    needHost: needHost,
    error: err
  });
}

// ---------- 诊断与自检 ----------

function __resetRequireLog() { __requireLog = []; return true; }
function __clearHttpLog() { __httpLog = []; return true; }
function __http() { return JSON.stringify(__httpLog); }

function __diag() {
  return JSON.stringify({
    harness: __HARNESS_VERSION,
    loaded: !!__plugin,
    requiredModules: __requireLog,
    compiled: __moduleLoadLog,
    consoleLog: __consoleLog.slice(-30),
    httpLog: __httpLog.slice(-12)
  });
}

function __engineProbe() {
  var out = {
    quickjs: typeof __VERSION__ !== 'undefined' ? __VERSION__ : null,
    hasFunction: typeof Function === 'function',
    hasXHR: typeof XMLHttpRequest === 'function',
    hasSymbol: typeof Symbol === 'function',
    hasProxy: typeof Proxy === 'function',
    hasBigInt: typeof BigInt === 'function',
    hasWeakMap: typeof WeakMap === 'function',
    hasPromise: typeof Promise === 'function',
    es2020_optionalChaining: null,
    es2020_nullish: null,
    textDecoder: typeof TextDecoder !== 'undefined',
    atob: typeof atob === 'function',
    btoa: typeof btoa === 'function'
  };
  try { out.es2020_optionalChaining = eval('({}).x?.y === undefined'); }
  catch (e) { out.es2020_optionalChaining = 'ERROR: ' + e.message; }
  try { out.es2020_nullish = eval('(null ?? 1) === 1'); }
  catch (e) { out.es2020_nullish = 'ERROR: ' + e.message; }
  return JSON.stringify(out);
}
