#!/usr/bin/env python3
"""Prepara SQL para el operador; jamás abre una conexión ni ejecuta SQL.
Entrada: objeto `foto` de 01-foto-pendientes.sql, guardado privadamente.
Salida privada nueva: snapshot exacto+SHA, lotes<=200 y verificación agregada.
"""
import argparse,hashlib,json,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parent/'sla-stock'
p=argparse.ArgumentParser();p.add_argument('--foto',type=Path,required=True);p.add_argument('--salida',type=Path,required=True);a=p.parse_args()
photo=json.loads(a.foto.read_text());assert isinstance(photo,dict) and isinstance(photo.get('lead_ids'),list) and isinstance(photo.get('tareas'),list)
ids=[str(uuid.UUID(x)) for x in photo['lead_ids']];assert len(set(ids))==len(ids)
seen=set();leads=set()
for task in photo['tareas']:
 tid=str(uuid.UUID(task['tarea_id']));lid=str(uuid.UUID(task['lead_id']));assert tid not in seen;seen.add(tid);leads.add(lid)
 assert type(task['ciclo_n']) is int and task['ciclo_n']>=1
assert set(ids)==leads
assert photo['control']['modo']=='legado','Reconstrucción sólo en legado, antes de R4'
out=a.salida.resolve();assert str(out).startswith('/private/tmp/'),'Salida debe ser privada en /private/tmp'
out.mkdir(mode=0o700,exist_ok=False)
raw=a.foto.read_bytes();(out/'foto-original.json').write_bytes(raw)
sha=hashlib.sha256(raw).hexdigest()
def literal(x):return json.dumps(x,separators=(',',':'),ensure_ascii=False).replace("'","''")
files=[]
for i,start in enumerate(range(0,len(ids),200),1):
 f=out/f'lote-{i:03}.sql';f.write_text((ROOT/'02-reconstruir-lote.template.sql').read_text().replace('__LEAD_IDS_JSON__',literal(ids[start:start+200])));files.append(f.name)
(out/'verificar-original.sql').write_text((ROOT/'03-verificar-foto.template.sql').read_text().replace('__FOTO_JSON__',literal(photo)))
summary={'foto_sha256':sha,'leads':len(ids),'tareas':len(seen),'lotes':len(files),'max_leads_por_lote':200,'archivos':files,'nota':'Preparado, NO ejecutado. No sobrescribir foto original.'}
(out/'manifest.json').write_text(json.dumps(summary,indent=2)+'\n')
for f in out.iterdir():f.chmod(0o600)
print(json.dumps({'carpeta':str(out),**summary},indent=2))
