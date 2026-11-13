// Turns the MyGo ESM subset into one script. Named exports, relative imports.
function bundle(files, entry) {
  const keyOf = (p) => p.replace(/\\/g, "/").replace(/^\.\//, "");
  const map = new Map();
  for (const [k, v] of files) map.set(keyOf(k), v);

  function lookup(fromFile, spec) {
    if (!spec.startsWith(".")) throw new Error("只支持相对导入：" + spec);
    const base = fromFile.split("/").slice(0, -1);
    const acc = [...base];
    for (const part of spec.split("/")) {
      if (part === "." || part === "") continue;
      if (part === "..") acc.pop();
      else acc.push(part);
    }
    const rel = acc.join("/");
    const stems = [rel];
    if (!rel.endsWith(".js") && !rel.endsWith(".ts")) stems.push(rel + ".js", rel + ".ts");
    if (rel.endsWith(".js")) stems.push(rel.replace(/\.js$/, ".ts"));
    for (const c of stems) if (map.has(c)) return c;
    throw new Error("找不到 " + spec + "（" + fromFile + "）");
  }

  const order = [];
  const seen = new Set();
  function walk(file) {
    if (seen.has(file)) return;
    seen.add(file);
    const src = map.get(file);
    if (src == null) throw new Error("缺少 " + file);
    for (const spec of localImports(src)) walk(lookup(file, spec));
    order.push(file);
  }
  walk(resolveEntry(map, entry));

  let out = "var __sxModules = {};\nvar __sxCache = {};\n";
  out += "function __sxRequire(id) {\n";
  out += "  var hit = __sxCache[id];\n";
  out += "  if (hit) return hit.exports;\n";
  out += "  var module = { exports: {} };\n";
  out += "  __sxCache[id] = module;\n";
  out += "  __sxModules[id](module, module.exports);\n";
  out += "  return module.exports;\n}\n";
  for (const file of order) {
    const body = transformModule(map.get(file), (spec) => lookup(file, spec));
    out += "__sxModules[" + JSON.stringify(file) + "] = function(module, exports) {\n" + body + "\n};\n";
  }
  out += "var __sxExports = __sxRequire(" + JSON.stringify(order[order.length - 1] === resolveEntry(map, entry) ? resolveEntry(map, entry) : resolveEntry(map, entry)) + ");\n";
  return out;
}

function resolveEntry(map, entry) {
  const key = entry.replace(/\\/g, "/").replace(/^\.\//, "");
  if (map.has(key)) return key;
  throw new Error("没有入口 " + entry);
}

function localImports(src) {
  const specs = [];
  for (const st of statements(src)) {
    if (st.type === "import" && st.spec.startsWith(".")) specs.push(st.spec);
    if (st.type === "export-from" && st.spec.startsWith(".")) specs.push(st.spec);
  }
  return specs;
}

function transformModule(src, resolve) {
  const pieces = [];
  let cursor = 0;
  for (const st of statements(src)) {
    pieces.push(src.slice(cursor, st.start));
    pieces.push(rewrite(src, st, resolve));
    cursor = st.end;
  }
  pieces.push(src.slice(cursor));
  return pieces.join("");
}

function rewrite(src, st, resolve) {
  if (st.type === "import") {
    const id = JSON.stringify(resolve(st.spec));
    if (st.clause.kind === "side") return "__sxRequire(" + id + ");";
    if (st.clause.kind === "namespace") return "var " + st.clause.local + " = __sxRequire(" + id + ");";
    if (st.clause.kind === "default") {
      let line = "var " + st.clause.local + " = __sxRequire(" + id + ").default;";
      if (st.clause.named) line += "\nvar { " + binding(st.clause.named) + " } = __sxRequire(" + id + ");";
      if (st.clause.ns) line += "\nvar " + st.clause.ns + " = __sxRequire(" + id + ");";
      return line;
    }
    return "var { " + binding(st.clause.names) + " } = __sxRequire(" + id + ");";
  }
  if (st.type === "export-from") {
    const id = JSON.stringify(resolve(st.spec));
    if (st.all) return "Object.assign(exports, __sxRequire(" + id + "));";
    return st.names.map((n) => "exports[" + JSON.stringify(n.exported) + "] = __sxRequire(" + id + ")[" + JSON.stringify(n.imported) + "];").join("\n");
  }
  if (st.type === "export-list") {
    return st.names.map((n) => "exports[" + JSON.stringify(n.exported) + "] = " + n.local + ";").join("\n");
  }
  if (st.type === "export-decl") {
    if (st.defaultExport) {
      const rest = src.slice(st.keywordEnd, st.end);
      if (st.names[0] && st.names[0] !== "default") {
        return rest + "\nexports[" + JSON.stringify("default") + "] = " + st.names[0] + ";\n";
      }
      return "exports[" + JSON.stringify("default") + "] = " + rest.replace(/;\s*$/, "") + ";\n";
    }
    const rest = src.slice(st.keywordEnd, st.end);
    const assign = st.names.map((n) => "exports[" + JSON.stringify(n) + "] = " + n + ";").join("\n");
    return rest + "\n" + assign + "\n";
  }
  return src.slice(st.start, st.end);
}

function binding(names) {
  return names.map((n) => n.imported === n.local ? n.local : n.imported + ": " + n.local).join(", ");
}

function statements(src) {
  const out = [];
  const n = src.length;
  let i = 0;
  let brace = 0, paren = 0, bracket = 0;
  let expect = "operand"; // operand | operator. regex vs division.
  while (i < n) {
    const c = src[i];
    if (c === "'" || c === '"') { i = skipString(src, i); expect = "operator"; continue; }
    if (c === "`") { i = skipTemplate(src, i); expect = "operator"; continue; }
    if (c === "/" && src[i + 1] === "/") { i += 2; while (i < n && src[i] !== "\n") i++; continue; }
    if (c === "/" && src[i + 1] === "*") { i += 2; while (i < n && !(src[i] === "*" && src[i + 1] === "/")) i++; i += 2; continue; }
    if (c === "/" && expect === "operand") { i = skipRegex(src, i); expect = "operator"; continue; }
    if (c === "{") { brace++; i++; expect = "operand"; continue; }
    if (c === "}") {
      brace = Math.max(0, brace - 1);
      i++;
      expect = brace === 0 && paren === 0 && bracket === 0 ? "operand" : "operator";
      continue;
    }
    if (c === "(") { paren++; i++; expect = "operand"; continue; }
    if (c === ")") { paren = Math.max(0, paren - 1); i++; expect = "operator"; continue; }
    if (c === "[") { bracket++; i++; expect = "operand"; continue; }
    if (c === "]") { bracket = Math.max(0, bracket - 1); i++; expect = "operator"; continue; }
    if (isWord(src, i, "import") && depth0(brace, paren, bracket) && expect === "operand") {
      const start = i;
      const parsed = parseImport(src, i + "import".length);
      out.push({ type: "import", start, end: parsed.end, spec: parsed.spec, clause: parsed.clause });
      i = parsed.end;
      expect = "operand";
      continue;
    }
    if (isWord(src, i, "export") && depth0(brace, paren, bracket) && expect === "operand") {
      const start = i;
      const parsed = parseExport(src, i + "export".length);
      parsed.start = start;
      parsed.keywordEnd = i + "export".length;
      out.push(parsed);
      i = parsed.end;
      expect = "operand";
      continue;
    }
    if (/[A-Za-z0-9_$]/.test(c)) {
      const id = readIdentMaybe(src, i);
      if (id) {
        i = id.end;
        if (["return", "throw", "case", "typeof", "void", "delete", "new", "in", "of", "instanceof", "await", "yield"].includes(id.value)) expect = "operand";
        else expect = "operator";
        continue;
      }
    }
    if (c === "\n" && depth0(brace, paren, bracket)) { i++; expect = "operand"; continue; }
    if (/\s/.test(c)) { i++; continue; }
    if ("=,:?".includes(c) || "+-!~<>|&*%^".includes(c)) { i++; expect = "operand"; continue; }
    if (c === "." && !/\d/.test(src[i + 1] || "")) { i++; expect = "operand"; continue; }
    if (c === ";") { i++; expect = "operand"; continue; }
    i++;
    expect = "operator";
  }
  return out;
}

function depth0(b, p, k) { return b === 0 && p === 0 && k === 0; }

function parseImport(src, i) {
  const n = src.length;
  const sp = () => { while (i < n && /\s/.test(src[i])) i++; };
  sp();
  if (src[i] === "(") throw new Error("dynamic import() 暂不支持");
  let clause;
  if (src[i] === "'" || src[i] === '"') {
    const spec = readString(src, i); i = spec.end; sp(); if (src[i] === ";") i++;
    return { end: i, spec: spec.value, clause: { kind: "side" } };
  }
  if (src[i] === "*") {
    i++; sp(); i = expectWord(src, i, "as"); sp();
    const local = readIdent(src, i); i = local.end;
    clause = { kind: "namespace", local: local.value };
  } else if (src[i] === "{") {
    const names = readNameList(src, i); i = names.end;
    clause = { kind: "named", names: names.names };
  } else {
    const local = readIdent(src, i); i = local.end; sp();
    clause = { kind: "default", local: local.value };
    if (src[i] === ",") {
      i++; sp();
      if (src[i] === "{") { const names = readNameList(src, i); i = names.end; clause.named = names.names; }
      else if (src[i] === "*") { i++; sp(); i = expectWord(src, i, "as"); sp(); const ns = readIdent(src, i); i = ns.end; clause.ns = ns.value; }
    }
  }
  sp();
  i = expectWord(src, i, "from"); sp();
  const spec = readString(src, i); i = spec.end; sp(); if (src[i] === ";") i++;
  return { end: i, spec: spec.value, clause };
}

function parseExport(src, i) {
  const n = src.length;
  const sp = () => { while (i < n && /\s/.test(src[i])) i++; };
  const keywordEnd = i;
  sp();
  if (src[i] === "{") {
    const names = readNameList(src, i); i = names.end; sp();
    const mapped = names.names.map((n) => ({ imported: n.imported, local: n.imported, exported: n.local }));
    if (src.startsWith("from", i) && !/[A-Za-z0-9_$]/.test(src[i + 4] || "")) {
      i += 4; sp();
      const spec = readString(src, i); i = spec.end; sp(); if (src[i] === ";") i++;
      return { type: "export-from", end: i, spec: spec.value, names: mapped, all: false };
    }
    if (src[i] === ";") i++;
    return { type: "export-list", end: i, names: mapped };
  }
  if (src[i] === "*") {
    i++; sp();
    i = expectWord(src, i, "from"); sp();
    const spec = readString(src, i); i = spec.end; sp(); if (src[i] === ";") i++;
    return { type: "export-from", end: i, spec: spec.value, all: true, names: [] };
  }
  let defaultExport = false;
  let names = [];
  if (src.startsWith("default", i) && !/[A-Za-z0-9_$]/.test(src[i + 7] || "")) {
    defaultExport = true;
    i += 7; sp();
    if (src.startsWith("function", i) || src.startsWith("class", i) || (src.startsWith("async", i) && /\s/.test(src[i + 5] || ""))) {
      const id = declaredName(src, i);
      names = [id || "default"];
    } else names = ["default"];
    const end = statementEnd(src, i);
    return { type: "export-decl", end, keywordEnd, names, defaultExport };
  }
  const id = declaredName(src, i);
  if (!id) throw new Error("不认识的 export：" + src.slice(i, i + 48).replace(/\s+/g, " "));
  if (src.startsWith("const", i) || src.startsWith("let", i) || src.startsWith("var", i)) names = bindingNames(src, i);
  else names = [id];
  const end = statementEnd(src, i);
  return { type: "export-decl", end, keywordEnd, names, defaultExport };
}

function declaredName(src, i) {
  let j = i;
  if (src.startsWith("async", j) && /\s/.test(src[j + 5] || "")) { j += 5; while (/\s/.test(src[j] || "")) j++; }
  if (src.startsWith("function", j) || src.startsWith("class", j)) {
    while (j < src.length && /[A-Za-z]/.test(src[j])) j++;
    while (/\s/.test(src[j] || "")) j++;
    if (!/[A-Za-z_$]/.test(src[j] || "")) return null;
    return readIdent(src, j).value;
  }
  if (src.startsWith("const", j) || src.startsWith("let", j) || src.startsWith("var", j)) {
    const k = src.startsWith("const", j) ? 5 : 3;
    j += k; while (/\s/.test(src[j] || "")) j++;
    if (src[j] === "{") { var first = readNameList(src, j).names[0]; return first ? first.local : null; }
    if (!/[A-Za-z_$]/.test(src[j] || "")) return null;
    return readIdent(src, j).value;
  }
  return null;
}

function bindingNames(src, i) {
  let j = i;
  const k = src.startsWith("const", j) ? 5 : 3;
  j += k; while (/\s/.test(src[j] || "")) j++;
  if (src[j] === "{") return readNameList(src, j).names.map((n) => n.local);
  return [readIdent(src, j).value];
}

function statementEnd(src, i) {
  let brace = 0, paren = 0, bracket = 0;
  let expect = "operand";
  while (i < src.length) {
    const c = src[i];
    if (c === "'" || c === '"') { i = skipString(src, i); expect = "operator"; continue; }
    if (c === "`") { i = skipTemplate(src, i); expect = "operator"; continue; }
    if (c === "/" && src[i + 1] === "/") { i += 2; while (i < src.length && src[i] !== "\n") i++; continue; }
    if (c === "/" && src[i + 1] === "*") { i += 2; while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) i++; i += 2; continue; }
    if (c === "/" && expect === "operand") { i = skipRegex(src, i); expect = "operator"; continue; }
    if (c === "{") { brace++; i++; expect = "operand"; continue; }
    if (c === "}") {
      brace--;
      i++;
      if (brace === 0 && paren === 0 && bracket === 0) {
        // function/class body ended. Stop unless this is an object in an expression that continues.
        const rest = src.slice(i).match(/^\s*/);
        const k = i + (rest ? rest[0].length : 0);
        if (src[k] === ";" || src[k] === "\n" || src[k] === undefined || src.startsWith("export", k) || src.startsWith("function", k) || src.startsWith("class", k) || src.startsWith("const", k) || src.startsWith("let", k) || src.startsWith("var", k) || src.startsWith("async", k)) return src[k] === ";" ? k + 1 : i;
      }
      expect = "operator";
      continue;
    }
    if (c === "(") { paren++; i++; expect = "operand"; continue; }
    if (c === ")") { paren--; i++; expect = "operator"; continue; }
    if (c === "[") { bracket++; i++; expect = "operand"; continue; }
    if (c === "]") { bracket--; i++; expect = "operator"; continue; }
    if (c === ";" && brace === 0 && paren === 0 && bracket === 0) return i + 1;
    if (c === "\n" && brace === 0 && paren === 0 && bracket === 0 && expect === "operator") return i;
    if (/[A-Za-z0-9_$]/.test(c)) {
      const id = readIdentMaybe(src, i);
      if (id) { i = id.end; expect = ["return","throw","case","typeof","void","new","await"].includes(id.value) ? "operand" : "operator"; continue; }
    }
    if (/\s/.test(c)) { i++; continue; }
    i++;
    expect = "operand";
  }
  return i;
}

function readNameList(src, i) {
  if (src[i] !== "{") throw new Error("需要 {");
  i++;
  const names = [];
  while (i < src.length) {
    while (/\s/.test(src[i] || "") || src[i] === ",") i++;
    if (src[i] === "}") return { names, end: i + 1 };
    const left = readIdent(src, i); i = left.end;
    while (/\s/.test(src[i] || "")) i++;
    let local = left.value;
    if (src.startsWith("as", i) && !/[A-Za-z0-9_$]/.test(src[i + 2] || "")) {
      i += 2; while (/\s/.test(src[i] || "")) i++;
      const right = readIdent(src, i); i = right.end;
      local = right.value;
    }
    names.push({ imported: left.value, local });
  }
  throw new Error("名单没有结束");
}

function expectWord(src, i, word) {
  if (!src.startsWith(word, i) || /[A-Za-z0-9_$]/.test(src[i + word.length] || "")) throw new Error("需要 " + word);
  return i + word.length;
}
function readIdent(src, i) {
  const m = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(src.slice(i));
  if (!m) throw new Error("需要标识符，却是 " + JSON.stringify(src.slice(i, i + 24)));
  return { value: m[0], end: i + m[0].length };
}
function readIdentMaybe(src, i) {
  const m = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(src.slice(i));
  if (!m) return null;
  return { value: m[0], end: i + m[0].length };
}
function isWord(src, i, word) {
  if (!src.startsWith(word, i)) return false;
  const prev = i > 0 ? src[i - 1] : "";
  const next = src[i + word.length] || "";
  return !/[A-Za-z0-9_$]/.test(prev) && !/[A-Za-z0-9_$]/.test(next);
}
function readString(src, i) {
  const q = src[i];
  let j = i + 1, v = "";
  while (j < src.length) {
    if (src[j] === "\\") { v += src[j + 1] === "n" ? "\n" : src[j + 1]; j += 2; continue; }
    if (src[j] === q) return { value: v, end: j + 1 };
    v += src[j]; j++;
  }
  throw new Error("字符串没结束");
}
function skipString(src, i) {
  const q = src[i]; i++;
  while (i < src.length) {
    if (src[i] === "\\") { i += 2; continue; }
    if (src[i] === q) return i + 1;
    i++;
  }
  return i;
}
function skipTemplate(src, i) {
  i++;
  while (i < src.length) {
    if (src[i] === "\\") { i += 2; continue; }
    if (src[i] === "`") return i + 1;
    if (src[i] === "$" && src[i + 1] === "{") {
      i += 2; let d = 1;
      while (i < src.length && d) {
        if (src[i] === "'" || src[i] === '"') { i = skipString(src, i); continue; }
        if (src[i] === "`") { i = skipTemplate(src, i); continue; }
        if (src[i] === "{") d++;
        else if (src[i] === "}") d--;
        if (d) i++;
      }
      continue;
    }
    i++;
  }
  return i;
}
function skipRegex(src, i) {
  i++;
  while (i < src.length) {
    if (src[i] === "\\") { i += 2; continue; }
    if (src[i] === "[") { i++; while (i < src.length && src[i] !== "]") { if (src[i] === "\\") i += 2; else i++; } i++; continue; }
    if (src[i] === "/") { i++; while (i < src.length && /[a-z]/i.test(src[i])) i++; return i; }
    i++;
  }
  return i;
}


function sxBundle(fileObject, entry) {
  var files = new Map();
  var keys = Object.keys(fileObject);
  for (var i = 0; i < keys.length; i++) files.set(keys[i], fileObject[keys[i]]);
  return bundle(files, entry);
}
