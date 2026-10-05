import tomllib

def load(f):
    c = f.read() if hasattr(f, 'read') else f
    return tomllib.loads(c.decode('utf-8') if isinstance(c, bytes) else c)

def loads(s):
    return tomllib.loads(s.decode('utf-8') if isinstance(s, bytes) else s)

def _fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(_fmt(i) for i in v) + "]"
    return str(v)

def _emit(data, prefix, out):
    scalars = {k: v for k, v in data.items() if not isinstance(v, dict)}
    tables = {k: v for k, v in data.items() if isinstance(v, dict)}
    if prefix and (scalars or not tables):
        out.append(f"[{prefix}]")
    for k, v in scalars.items():
        out.append(f"{k} = {_fmt(v)}")
    if scalars or prefix:
        out.append("")
    for k, v in tables.items():
        _emit(v, f"{prefix}.{k}" if prefix else k, out)

def dumps(data):
    out = []
    _emit(data, "", out)
    return "\n".join(out)

def dump(data, f):
    f.write(dumps(data))
