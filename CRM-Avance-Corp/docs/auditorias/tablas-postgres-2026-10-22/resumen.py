import re, json
src = open('esquema-prod-20261022.sql', encoding='utf-8').read()
stmts, buf, i, n = [], [], 0, len(src); in_dollar=None
while i < n:
    if in_dollar:
        j = src.find(in_dollar, i)
        if j < 0: buf.append(src[i:]); break
        buf.append(src[i:j+len(in_dollar)]); i = j+len(in_dollar); in_dollar=None; continue
    m = re.match(r'\$[A-Za-z0-9_]*\$', src[i:i+64])
    if m: in_dollar = m.group(0); buf.append(in_dollar); i += len(in_dollar); continue
    c = src[i]
    if c == "'":
        j = i+1
        while j < n:
            if src[j] == "'" and src[j+1:j+2] == "'": j += 2; continue
            if src[j] == "'": break
            j += 1
        buf.append(src[i:j+1]); i = j+1; continue
    if c == '-' and src[i:i+2] == '--':
        j = src.find('\n', i); j = n if j<0 else j; i = j; continue
    if c == ';': buf.append(';'); stmts.append(''.join(buf).strip()); buf=[]; i+=1; continue
    buf.append(c); i += 1
keep_re = re.compile(r'^(CREATE (UNLOGGED )?TABLE|ALTER TABLE|CREATE (UNIQUE )?INDEX|CREATE POLICY|CREATE (OR REPLACE )?TRIGGER|COMMENT ON (TABLE|COLUMN|CONSTRAINT|INDEX|TRIGGER|POLICY|VIEW)|CREATE TYPE|CREATE DOMAIN|CREATE SEQUENCE|CREATE (OR REPLACE )?VIEW|CREATE MATERIALIZED VIEW|GRANT|REVOKE|CREATE SCHEMA|CREATE RULE)', re.I)
def ruido(s):
    u = s.upper()
    if ('ON FUNCTION' in u or 'ON ALL FUNCTIONS' in u or 'ON PROCEDURE' in u) and (u.startswith('GRANT') or u.startswith('REVOKE')): return True
    if u.startswith('ALTER') and ' OWNER TO ' in u: return True
    return False
kept = [s for s in stmts if keep_re.match(s.lstrip()) and not ruido(s.lstrip())]
open('catalogo-estructura.sql','w',encoding='utf-8').write('\n\n'.join(kept)+'\n')
WS = re.compile(r'\s+')
def one(x): return WS.sub(' ', x).rstrip(';').replace('"','')
T = {}
def tab(sch, name): return T.setdefault(f'{sch}.{name}', dict(columnas=[], constraints=[], indices=[], rls=False, force_rls=False, policies=[], triggers=[], comentario_tabla=False, comentarios_columna=[], grants=[]))
q = r'"?([a-z_]+)"?\."?([a-z_0-9]+)"?'
for s in kept:
    u = s.lstrip()
    m = re.match(r'CREATE (?:UNLOGGED )?TABLE (?:IF NOT EXISTS )?'+q+r'\s*\((.*)\)\s*;?$', u, re.S|re.I)
    if m:
        t = tab(m.group(1), m.group(2)); body = m.group(3)
        depth=0; cur=''; parts=[]
        for ch in body:
            if ch=='(': depth+=1
            if ch==')': depth-=1
            if ch==',' and depth==0: parts.append(cur.strip()); cur=''; continue
            cur+=ch
        if cur.strip(): parts.append(cur.strip())
        for p in parts:
            p1 = one(p)
            if re.match(r'(CONSTRAINT|PRIMARY KEY|UNIQUE|CHECK|FOREIGN KEY)', p1, re.I): t['constraints'].append(p1)
            else: t['columnas'].append(p1)
        continue
    m = re.match(r'ALTER TABLE (?:ONLY )?'+q+r'\s+(.*);?$', u, re.S|re.I)
    if m:
        t = tab(m.group(1), m.group(2)); rest = one(m.group(3))
        if 'ENABLE ROW LEVEL SECURITY' in rest.upper(): t['rls']=True
        elif 'FORCE ROW LEVEL SECURITY' in rest.upper(): t['force_rls']=True
        elif rest.upper().startswith('ADD CONSTRAINT'): t['constraints'].append(rest[4:])
        else: t['constraints'].append(rest)
        continue
    m = re.match(r'CREATE (UNIQUE )?INDEX (?:IF NOT EXISTS )?"?([a-z_0-9]+)"? ON (?:ONLY )?'+q+r'\s+(.*);?$', u, re.S|re.I)
    if m:
        tab(m.group(3), m.group(4))['indices'].append(('UNIQUE ' if m.group(1) else '')+m.group(2)+' '+one(m.group(5))); continue
    m = re.match(r'CREATE POLICY "?([^"\s]+)"? ON '+q+r'\s+(.*);?$', u, re.S|re.I)
    if m:
        tab(m.group(2), m.group(3))['policies'].append(m.group(1)+' '+one(m.group(4))); continue
    m = re.match(r'CREATE (?:OR REPLACE )?TRIGGER "?([a-z_0-9]+)"? (.*?) ON '+q+r'\s+(.*);?$', u, re.S|re.I)
    if m:
        tab(m.group(3), m.group(4))['triggers'].append(m.group(1)+' '+one(m.group(2))+' '+one(m.group(5))); continue
    m = re.match(r'COMMENT ON TABLE '+q, u, re.I)
    if m: tab(m.group(1), m.group(2))['comentario_tabla']=True; continue
    m = re.match(r'COMMENT ON COLUMN '+q+r'\."?([a-z_0-9]+)"?', u, re.I)
    if m: tab(m.group(1), m.group(2))['comentarios_columna'].append(m.group(3)); continue
    m = re.match(r'(GRANT|REVOKE) (.*?) ON (?:TABLE )?'+q+r'\s+(TO|FROM) (.*);?$', u, re.S|re.I)
    if m:
        k = m.group(3)+'.'+m.group(4)
        if k in T: T[k]['grants'].append(m.group(1)+' '+one(m.group(2))+' '+m.group(5)+' '+one(m.group(6)))
        continue
json.dump(T, open('resumen-tablas.json','w'), ensure_ascii=False, indent=1)
print('tablas', len(T))
print('sin PK:', [k for k,v in T.items() if not any('PRIMARY KEY' in c.upper() for c in v['constraints'])])
print('RLS on sin policies:', len([k for k,v in T.items() if v['rls'] and not v['policies']]))
print('con FORCE RLS:', len([k for k,v in T.items() if v['force_rls']]))
print('sin comentario de tabla:', len([k for k,v in T.items() if not v['comentario_tabla']]))
print('sin ningun trigger:', len([k for k,v in T.items() if not v['triggers']]))
print('sin ningun grant:', len([k for k,v in T.items() if not v['grants']]))
