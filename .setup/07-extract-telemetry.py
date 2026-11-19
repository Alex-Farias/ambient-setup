#!/usr/bin/env python3
# =============================================================================
# 07-extract-telemetry.py: transforma os dados brutos coletados pelo 06 em
# tabelas CSV SEM o texto das conversas (só números, nomes de modelo/ferramenta,
# horários e tamanhos).
# =============================================================================
#   Roda no HOST, com o python3 do WSL (só biblioteca padrão). Só LÊ o bruto e
#   só ESCREVE na pasta de saída. Mora no ambient-setup (não em pasta de projeto)
#   porque roda fora do jail.
#
#   USO
#     python3 -I 07-extract-telemetry.py                 # usa os padrões abaixo
#     python3 -I 07-extract-telemetry.py --raw R --out O
#
#   PADRÕES
#     --raw  ~/projects/telemetry/data/raw
#     --out  ~/projects/telemetry/data/derived
#
#   SAÍDAS (CSV)
#     messages.csv      1 linha por resposta do modelo (deduplicada por message.id):
#                       tokens de entrada/saída/cache, modelo, ferramentas usadas.
#     sessions.csv      1 linha por sessão: períodos, somas de tokens e o custo
#                       acumulado que o próprio Claude Code registrou.
#     cost_models.csv   custo/uso por modelo dentro de cada sessão (cost-state).
#     api_requests.csv  1 linha por chamada à API: modelo, origem, parâmetros.
#     prompts.csv       1 linha por prompt digitado: só horário e TAMANHO.
#
#   Lista branca de campos: nenhum texto de mensagem, prompt, resultado de
#   ferramenta ou conteúdo de arquivo é copiado.
# =============================================================================
import argparse
import collections
import csv
import datetime
import glob
import json
import os
import sys

HOME = os.path.expanduser("~")
p = argparse.ArgumentParser()
p.add_argument("--raw", default=os.path.join(HOME, "projects/telemetry/data/raw"))
p.add_argument("--out", default=os.path.join(HOME, "projects/telemetry/data/derived"))
args = p.parse_args()
RAW, OUT = args.raw, args.out
CLAUDE = os.path.join(RAW, "claude")
if not os.path.isdir(os.path.join(CLAUDE, "projects")):
    sys.exit(f"ERRO: {CLAUDE}/projects não existe. Rode o 06 antes.")


def scalar(v, maxlen=40):
    """Só valores simples e curtos: nunca texto longo."""
    if isinstance(v, bool) or isinstance(v, (int, float)):
        return v
    if isinstance(v, str) and len(v) <= maxlen:
        return v
    return ""


def num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else ""


# --- mapa pasta-de-histórico -> workspace/projeto (do repos.tsv do 06) ---------
proj_of = {}
tsv = os.path.join(RAW, "repos.tsv")
if os.path.exists(tsv):
    with open(tsv, encoding="utf-8") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 4:
                proj_of[parts[3]] = f"{parts[1]}/{parts[2]}"

msgs = {}                      # message.id -> linha
tools = collections.defaultdict(list)
cost_best = {}                 # sessionId -> registro cost-state (maior totalDuration)
api_rows = []
lines_total = bad = synth = 0

files = sorted(glob.glob(os.path.join(CLAUDE, "projects", "**", "*.jsonl"), recursive=True))
for fp in files:
    rel = os.path.relpath(fp, os.path.join(CLAUDE, "projects"))
    enc = rel.split(os.sep)[0]
    project = proj_of.get(enc, enc)
    with open(fp, encoding="utf-8", errors="replace") as f:
        for line in f:
            lines_total += 1
            try:
                o = json.loads(line)
            except ValueError:
                bad += 1
                continue
            if not isinstance(o, dict):
                continue
            t = o.get("type")
            sid = o.get("sessionId") or o.get("session_id") or ""
            if t == "assistant":
                m = o.get("message") if isinstance(o.get("message"), dict) else {}
                u = m.get("usage") if isinstance(m.get("usage"), dict) else None
                model = m.get("model")
                if u is None or model in (None, "<synthetic>"):
                    synth += 1
                    continue
                key = m.get("id") or o.get("requestId") or f"{fp}:{lines_total}"
                content = m.get("content") if isinstance(m.get("content"), list) else []
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tools[key].append(scalar(b.get("name"), 80) or "?")
                if key in msgs:
                    continue
                cc = u.get("cache_creation") if isinstance(u.get("cache_creation"), dict) else {}
                ts = o.get("timestamp") if isinstance(o.get("timestamp"), str) else ""
                msgs[key] = {
                    "message_id": m.get("id") or "",
                    "request_id": o.get("requestId") or "",
                    "session_id": sid,
                    "project": project,
                    "timestamp": ts,
                    "date_utc": ts[:10],
                    "model": model,
                    "is_sidechain": bool(o.get("isSidechain")),
                    "input_tokens": num(u.get("input_tokens")),
                    "output_tokens": num(u.get("output_tokens")),
                    "cache_creation_input_tokens": num(u.get("cache_creation_input_tokens")),
                    "cache_read_input_tokens": num(u.get("cache_read_input_tokens")),
                    "cache_5m_tokens": num(cc.get("ephemeral_5m_input_tokens")),
                    "cache_1h_tokens": num(cc.get("ephemeral_1h_input_tokens")),
                    "service_tier": scalar(u.get("service_tier")),
                    "speed": scalar(u.get("speed")),
                    "stop_reason": scalar(m.get("stop_reason")),
                }
            elif t == "cost-state":
                cur = cost_best.get(sid)
                if cur is None or (num(o.get("totalDuration")) or 0) >= (num(cur.get("totalDuration")) or 0):
                    cost_best[sid] = dict(o, _project=project)
            elif t == "api-request":
                params = o.get("params") if isinstance(o.get("params"), dict) else {}
                row = {
                    "timestamp": scalar(o.get("timestamp"), 40),
                    "session_id": sid,
                    "project": project,
                    "request_id": scalar(o.get("id"), 80),
                    "query_source": scalar(o.get("querySource"), 60),
                    "is_agent": "agentId" in o,
                    "model": scalar(params.get("model"), 80),
                    "max_tokens": num(params.get("max_tokens")),
                    "keep": num(o.get("keep")),
                }
                for grp in ("thinking", "output_config"):
                    d = params.get(grp) if isinstance(params.get(grp), dict) else {}
                    for k, v in d.items():
                        row[f"{grp}.{k}"] = scalar(v)
                api_rows.append(row)

for key, row in msgs.items():
    names = tools.get(key, [])
    row["tool_calls"] = len(names)
    row["tool_names"] = ";".join(sorted(set(names)))

# --- sessions ------------------------------------------------------------------
sess = collections.OrderedDict()
for r in msgs.values():
    s = sess.setdefault(r["session_id"], {
        "session_id": r["session_id"], "project": r["project"], "first_ts": "", "last_ts": "",
        "messages": 0, "input_tokens": 0, "output_tokens": 0,
        "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "models": set(),
    })
    s["messages"] += 1
    for k in ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"):
        s[k] += r[k] or 0
    s["models"].add(r["model"])
    if r["timestamp"] and (not s["first_ts"] or r["timestamp"] < s["first_ts"]):
        s["first_ts"] = r["timestamp"]
    if r["timestamp"] and r["timestamp"] > s["last_ts"]:
        s["last_ts"] = r["timestamp"]
COST_KEYS = ("totalCostUSD", "totalAPIDuration", "totalAPIDurationWithoutRetries", "totalToolDuration",
             "totalDuration", "totalLinesAdded", "totalLinesRemoved", "hasUnknownModelCost", "startTime")
for sid, c in cost_best.items():
    s = sess.setdefault(sid, {"session_id": sid, "project": c["_project"], "first_ts": "", "last_ts": "",
                              "messages": 0, "input_tokens": 0, "output_tokens": 0,
                              "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0, "models": set()})
    for k in COST_KEYS:
        s[k] = scalar(c.get(k))
for s in sess.values():
    s["models"] = ";".join(sorted(m for m in s["models"] if m))

# --- cost_models ---------------------------------------------------------------
cm_rows = []
for sid, c in cost_best.items():
    mu = c.get("modelUsage") if isinstance(c.get("modelUsage"), dict) else {}
    for model, d in mu.items():
        row = {"session_id": sid, "project": c["_project"], "model": scalar(model, 80)}
        if isinstance(d, dict):
            for k, v in d.items():
                row[k] = num(v)
        cm_rows.append(row)

# --- prompts (só horário e tamanho) --------------------------------------------
pr_rows = []
hp = os.path.join(CLAUDE, "history.jsonl")
if os.path.exists(hp):
    with open(hp, encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if not isinstance(o, dict):
                continue
            ts = o.get("timestamp")
            iso = ""
            if isinstance(ts, (int, float)) and not isinstance(ts, bool):
                secs = ts / 1000.0 if ts > 1e11 else ts
                iso = datetime.datetime.fromtimestamp(secs, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            disp = o.get("display")
            pc = o.get("pastedContents")
            pr_rows.append({
                "timestamp": iso or scalar(ts),
                "project": scalar(o.get("project"), 200),
                "session_id": scalar(o.get("sessionId"), 80),
                "chars": len(disp) if isinstance(disp, str) else "",
                "pasted_items": len(pc) if isinstance(pc, (dict, list)) else "",
            })


def write(name, rows, preferred):
    cols = list(preferred)
    for r in rows:
        for k in r:
            if k not in cols:
                cols.append(k)
    path = os.path.join(OUT, name)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)
    os.chmod(path, 0o600)
    return len(rows)


os.makedirs(OUT, exist_ok=True)
os.chmod(OUT, 0o700)
n_msg = write("messages.csv", list(msgs.values()),
              ["timestamp", "date_utc", "session_id", "project", "model", "is_sidechain", "input_tokens",
               "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "cache_5m_tokens",
               "cache_1h_tokens", "tool_calls", "tool_names", "service_tier", "speed", "stop_reason",
               "message_id", "request_id"])
n_ses = write("sessions.csv", list(sess.values()),
              ["session_id", "project", "first_ts", "last_ts", "messages", "models", "input_tokens",
               "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"])
n_cm = write("cost_models.csv", cm_rows, ["session_id", "project", "model"])
n_api = write("api_requests.csv", api_rows, ["timestamp", "session_id", "project", "request_id", "query_source",
                                              "is_agent", "model", "max_tokens", "keep"])
n_pr = write("prompts.csv", pr_rows, ["timestamp", "project", "session_id", "chars", "pasted_items"])

by_model = collections.Counter()
for r in msgs.values():
    by_model[r["model"]] += (r["input_tokens"] or 0) + (r["output_tokens"] or 0)
cost = sum(s.get("totalCostUSD") or 0 for s in sess.values() if isinstance(s.get("totalCostUSD"), (int, float)))
print(f"arquivos .jsonl lidos : {len(files)} | linhas: {lines_total} | inválidas: {bad}")
print(f"respostas do modelo   : {n_msg} (deduplicadas) | sintéticas ignoradas: {synth}")
print(f"sessões               : {n_ses} | cost_models: {n_cm} | api_requests: {n_api} | prompts: {n_pr}")
print("tokens (entrada+saída) por modelo:")
for m, v in by_model.most_common():
    print(f"  {v:12d}  {m}")
print(f"custo acumulado (soma de totalCostUSD das sessões): US$ {cost:.2f}")
print(f"saída: {OUT}")
