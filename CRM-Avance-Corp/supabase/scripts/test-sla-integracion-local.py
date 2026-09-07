#!/usr/bin/env python3
"""Banco local SLA con esquema CRM completo y fixtures sinteticos.
No acepta URL de conexion. Restaura exclusivamente un dump schema-only local.
Nunca modifica autoridad, veto o writers CRM para conseguir que una prueba pase.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

PG = Path(os.environ.get('SLA_PG_BIN', '/opt/homebrew/opt/postgresql@17/bin'))
BASE = Path(__file__).resolve().parents[1]


def quote(value):
    if value is None: return 'null'
    if isinstance(value, bool): return str(value).lower()
    if isinstance(value, (int,float)): return str(value)
    return "'"+str(value).replace("'", "''")+"'"


class Bank:
    def __init__(self):
        self.root=Path(tempfile.mkdtemp(prefix='sla-integracion-',dir='/private/tmp'))
        self.env=os.environ.copy()
        self.env.update(PGHOST=str(self.root),PGPORT='55485',PGUSER='postgres',PGDATABASE='sla_integracion',PGCONNECT_TIMEOUT='3')
        self.running=False
        self.manifest={'socket':str(self.root),'port':55485,'database':'sla_integracion','user':'postgres',
                       'tcp':False,'omissions':[], 'adjustments':[]}
        (self.root/'LOCAL-SLA-BANK').write_text('Cluster desechable creado por test-sla-integracion-local.py\n')

    def command(self,name,args,**kwargs):
        return subprocess.run([str(PG/name),*args],env=self.env,text=True,capture_output=True,**kwargs)

    def sql(self,source,db='sla_integracion',error=False):
        result=self.command('psql',['-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-d',db],input=source)
        if not error and result.returncode:
            raise RuntimeError(result.stderr)
        return result if error else result.stdout.strip()

    def start(self, schema, metadata):
        result=self.command('initdb',['-D',str(self.root/'data'),'-U','postgres','-A','trust','--no-locale','-E','UTF8'])
        if result.returncode: raise RuntimeError(result.stderr)
        result=self.command('pg_ctl',['-D',str(self.root/'data'),'-l',str(self.root/'postgres.log'),'-o',f"-k {self.root} -p 55485 -c listen_addresses=''",'-w','start'])
        if result.returncode: raise RuntimeError(result.stderr)
        self.running=True
        for role in metadata['roles']:
            if role['name']=='postgres': continue
            opts=('SUPERUSER ' if role['super'] else 'NOSUPERUSER ')+('BYPASSRLS ' if role['bypass'] else 'NOBYPASSRLS ')+('INHERIT' if role['inherit'] else 'NOINHERIT')
            self.sql('create role "'+role['name'].replace('"','""')+'" NOLOGIN '+opts+';',db='postgres')
        self.sql('create database sla_integracion;',db='postgres')
        native=('pgcrypto','uuid-ossp','btree_gist','unaccent','pg_trgm')
        self.sql('create schema extensions;\n'+'\n'.join('create extension "'+e+'" with schema extensions;' for e in native))
        content=schema.read_text()
        self.manifest['schema_sha256']=hashlib.sha256(schema.read_bytes()).hexdigest()
        # El cluster ya aporta public; extensions aloja las extensiones nativas.
        for name in ('public','extensions'):
            content=content.replace('CREATE SCHEMA '+name+';', 'CREATE SCHEMA IF NOT EXISTS '+name+';')
        self.manifest['adjustments'].append('CREATE SCHEMA public/extensions usa IF NOT EXISTS; estructuras y funciones CRM intactas')
        self.manifest['native_extensions']=list(native)
        self.manifest['managed_extensions_not_installed']=[e for e in metadata['extensions'] if e not in native and e!='plpgsql']
        result=self.sql(content,error=True)
        (self.root/'restore.stdout.log').write_text(result.stdout)
        (self.root/'restore.stderr.log').write_text(result.stderr)
        if result.returncode:
            self.save_manifest()
            raise RuntimeError('Restauracion incompleta: '+result.stderr[-5000:])
        self.manifest['postgres']=self.sql('select version();')
        self.manifest['schema_restored']=True
        self.save_manifest()

    def load_governance(self, path):
        data=json.loads(path.read_text())
        assert data['fuente']=='cwkiejoaqadcnaieghnf' and data['solo_lectura'] is True
        def ident(value): return '"'+value.replace('"','""')+'"'
        existing_functions=set(json.loads(self.sql("set search_path='';select jsonb_agg(p.oid::regprocedure::text) from pg_proc p;")))
        existing_relations=set(json.loads(self.sql("set search_path='';select jsonb_agg(c.oid::regclass::text) from pg_class c;")))
        commands=['begin;']
        missing=[]
        for item in data['owners_funciones']:
            if item['firma'] not in existing_functions:
                assert item['firma'].startswith('extensions.'), 'Falta funcion de negocio: '+item['firma']
                missing.append(item['firma'])
                continue
            if item['owner']!='postgres':
                commands.append('alter function '+item['firma']+' owner to '+ident(item['owner'])+';')
        linked_sequences=set(json.loads(self.sql("set search_path='';select coalesce(jsonb_agg(c.oid::regclass::text),'[]'::jsonb) from pg_class c where c.relkind='S' and exists(select 1 from pg_depend d where d.objid=c.oid and d.classid='pg_class'::regclass and d.deptype in ('a','i'));")))
        for item in data['owners_relaciones']:
            if item['objeto'] in linked_sequences:
                continue # Cambia junto con el owner de su tabla real.
            if item['objeto'] not in existing_relations:
                assert item['objeto'].startswith('extensions.'), 'Falta relacion de negocio: '+item['objeto']
                missing.append(item['objeto'])
                continue
            if item['owner']!='postgres':
                kind={'S':'sequence','v':'view','m':'materialized view'}.get(item['kind'],'table')
                commands.append('alter '+kind+' '+item['objeto']+' owner to '+ident(item['owner'])+';')
        for item in data['membresias']:
            for key in ('admin','inherit','set'):
                commands.append('grant '+ident(item['rol'])+' to '+ident(item['miembro'])+' with '+key+' '+str(item[key]).lower()+';')
        for table, rows in data['tablas'].items():
            commands.append('insert into '+table+' select * from jsonb_populate_recordset(null::'+table+','+quote(json.dumps(rows))+'::jsonb);')
        # El scheduler no existe en PG nativo. Se restaura SU METADATA, sin
        # worker ni ejecucion HTTP, para ejecutar los gates reales sin falsearlos.
        commands.append('create schema cron;')
        for table in ('job','job_run_details'):
            cols=[c for c in data['cron_columnas'] if c['tabla']==table]
            commands.append('create table cron.'+table+' ('+','.join(ident(c['columna'])+' '+c['tipo'] for c in cols)+');')
        jobs=data['cron_jobs']
        for item in jobs:
            item['database']='sla_integracion'
        commands.append('insert into cron.job select * from jsonb_populate_recordset(null::cron.job,'+quote(json.dumps(jobs))+'::jsonb);')
        commands.append('commit;')
        result=self.sql('\n'.join(commands),error=True)
        (self.root/'governance.stderr.log').write_text(result.stderr)
        if result.returncode:
            raise RuntimeError('Gobernanza no restaurada; revisar log privado '+str(self.root/'governance.stderr.log'))
        self.manifest['omissions']=missing
        self.manifest['governance_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        self.manifest['managed_metadata_only']=['cron.job','cron.job_run_details (vacia; no se inventan ejecuciones)']
        self.manifest['adjustments'].append('Metadata cron.database referencia el nombre del banco local; scheduler ausente')
        checks={}
        for function in ('assert_analista_vigencia','assert_analitica_leads_citas','assert_auditoria','assert_f7_piezas_cerradas'):
            result=self.sql('select private.'+function+'();',error=True)
            checks[function]={'ok':result.returncode==0,'salida':result.stdout.strip(),'error':result.stderr.strip()}
        self.manifest['gates_baseline']=checks
        self.save_manifest()
        return checks

    def prepare(self):
        # F7 es el schema de partida. Dos cuerpos operativos de producción ya
        # divergen: overlay local de fuentes exactas exportadas SOLO en lectura.
        expected = {
            'crm.conversion_mensual_sin_cartera_fn(date)': 'bb80938ccc6bd0f1e48a5f14706c0f01',
            'crm.cerrar_periodo(date)': 'a3fe78f62b637412f780835c9cd9a0db',
        }
        snapshot = json.loads((BASE/'tests/sla-integracion/fuentes-analitica-previas.json').read_text())
        changes=[]
        for f in snapshot['funciones']:
            current=self.sql("select md5(pg_get_functiondef("+quote(f['firma'])+"::regprocedure));")
            if current==f['def_md5']: continue
            if current!=expected.get(f['firma']):
                raise RuntimeError('Fuente baseline distinta: '+f['firma'])
            self.sql(f['definition']+';')
            changes.append({'firma':f['firma'],'f7_def_md5':current,'prod_def_md5':f['def_md5']})
        self.manifest['overlay_prod']=changes
        for suffix in ('crm_sla_prerrequisito_gobernanza','crm_sla_nucleo_operativo_lectura'):
            files=list((BASE/'migrations').glob('*_'+suffix+'.sql'))
            if len(files)!=1: raise RuntimeError('Migracion ambigua: '+suffix)
            self.sql(files[0].read_text())
            self.manifest.setdefault('migraciones',[]).append({'archivo':files[0].name,'sha256':hashlib.sha256(files[0].read_bytes()).hexdigest()})
        for name in ('actores.sql','politica-base.sql'):
            self.sql((BASE/'tests/sla-integracion'/name).read_text())
        self.manifest['fixture']='Actores sintéticos 1001..1007, política v1, sin leads reales'
        self.manifest['gates_finales']={name:self.sql('select private.'+name+'();') for name in ('assert_analista_vigencia','assert_analitica_leads_citas','assert_auditoria','assert_f7_piezas_cerradas')}
        self.manifest['template_n1_listo']=True
        self.save_manifest()

    def install_commands(self):
        for suffix in ('crm_sla_nucleo_operativo_escritura','crm_sla_comandos_recibos','crm_sla_cierre_reconstruccion_contextos'):
            files=list((BASE/'migrations').glob('*_'+suffix+'.sql'))
            if len(files)!=1: raise RuntimeError('Migracion ambigua: '+suffix)
            self.sql(files[0].read_text())
            self.manifest['migraciones'].append({'archivo':files[0].name,'sha256':hashlib.sha256(files[0].read_bytes()).hexdigest()})
        self.manifest['gate_n2']=self.sql('select private.assert_sla_operacion();')
        self.manifest['gate_n3']=self.sql('select private.assert_sla_comandos();')
        self.manifest['template_n3_listo']=True
        self.save_manifest()

    def test_prerequisite(self):
        db='sla_prerrequisito_'+uuid.uuid4().hex[:10]
        self.sql('create database '+db+' template sla_integracion;',db='postgres')
        checks={}
        names=('assert_analista_vigencia','assert_analitica_leads_citas','assert_auditoria','assert_f7_piezas_cerradas')
        try:
            self.sql('update cron.job set database=current_database();',db=db)
            snap=json.loads((BASE/'tests/sla-integracion/fuentes-gobernanza-previas.json').read_text())
            sources=[f for f in snap['funciones'] if f['firma'].startswith(('crear_contrato(', 'private.bloquear_leads_nowait(', 'private.fusion_bloqueos(', 'crm.fusion_previsualizar_fn(', 'crm.corregir_documento_inversionista_fn('))]
            after={f['firma']:self.sql('select md5(pg_get_functiondef('+quote(f['firma'])+'::regprocedure));',db=db) for f in sources}
            self.sql((BASE/'scripts/rollback-sla-nucleo-lectura.sql').read_text(),db=db)
            self.sql((BASE/'scripts/rollback-sla-prerrequisito-gobernanza.sql').read_text(),db=db)
            checks['rollback_sources_exact']=all(self.sql('select md5(pg_get_functiondef('+quote(f['firma'])+'::regprocedure));',db=db)==f['def_md5'] for f in sources)
            checks['rollback_restores_four_baseline_reds']=all(self.sql('select private.'+name+'();',db=db,error=True).returncode!=0 for name in names)
            # ROW_COUNT preserva NULL, vacio, duplicados y cardinalidad del lote;
            # la RPC real crea el lead con todas sus fuentes/guards activos.
            lead=str(uuid.uuid4())
            self.sql("set role authenticated;set request.jwt.claim.sub='00000000-0000-0000-0000-000000001004';select crm.crear_lead_si_disponible('SINTETICO PREREQUISITO','+51955554444','oficina',1000,'PEN',p_id=>"+quote(lead)+",p_etapa=>'contactado',p_vendedor_id=>'00000000-0000-0000-0000-000000001001');",db=db)
            probes=["null::uuid[]","'{}'::uuid[]","array["+quote(lead)+"::uuid,"+quote(lead)+"::uuid]","array["+quote(lead)+"::uuid,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid]"]
            before_locks=[self.sql('select private.bloquear_leads_nowait('+probe+');',db=db) for probe in probes]
            file=next((BASE/'migrations').glob('*_crm_sla_prerrequisito_gobernanza.sql'))
            self.sql(file.read_text(),db=db)
            checks['reapply_sources_exact']=all(self.sql('select md5(pg_get_functiondef('+quote(f['firma'])+'::regprocedure));',db=db)==after[f['firma']] for f in sources)
            checks['lock_row_count_equivalent']=[self.sql('select private.bloquear_leads_nowait('+probe+');',db=db) for probe in probes]==before_locks==['0','0','1','1']
            checks['final_gates_green']=all(self.sql('select private.'+name+'();',db=db,error=True).returncode==0 for name in names)
            checks['private_providers_not_exposed']=self.sql("set role authenticated;select private.fusion_impacto(null,null);",db=db,error=True).returncode!=0
            if not all(checks.values()): raise RuntimeError('Fallo roundtrip prerrequisito: '+json.dumps(checks))
        finally:
            self.sql('drop database '+db+';',db='postgres')
        self.manifest['prerequisite_roundtrip']=checks
        self.save_manifest()
        return checks

    def save_manifest(self):
        (self.root/'manifest.json').write_text(json.dumps(self.manifest,ensure_ascii=False,indent=2)+'\n')

    def stop(self):
        if self.running:
            result=self.command('pg_ctl',['-D',str(self.root/'data'),'-m','fast','-w','stop'])
            if result.returncode: raise RuntimeError(result.stderr)
            self.running=False
            self.manifest['stopped']=True
            self.save_manifest()


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--schema',type=Path,required=True)
    parser.add_argument('--metadata',type=Path,required=True)
    parser.add_argument('--governance',type=Path,help='Export allowlist de gobernanza, owners y cron metadata')
    parser.add_argument('--prepare-sla',action='store_true',help='Aplicar prerrequisito real y N1; sembrar actores/política sintéticos')
    parser.add_argument('--test-prerequisite',action='store_true',help='Rollback/reaplicar y comprobar fuentes, gates y locks en clon desechable')
    parser.add_argument('--all-sla',action='store_true',help='Tras preparar N1, instalar N2/N3/cierre y conservar política legado')
    parser.add_argument('--keep',action='store_true',help='Conservar servidor local para pruebas coordinadas; emitir conexion local')
    args=parser.parse_args()
    bank=Bank()
    try:
        bank.start(args.schema,json.loads(args.metadata.read_text()))
        if args.governance: bank.load_governance(args.governance)
        if args.prepare_sla:
            if not args.governance: raise RuntimeError('--prepare-sla requiere --governance')
            bank.prepare()
        if args.test_prerequisite: bank.test_prerequisite()
        if args.all_sla:
            if not args.prepare_sla: raise RuntimeError('--all-sla requiere --prepare-sla')
            bank.install_commands()
        print(json.dumps(bank.manifest,ensure_ascii=False,indent=2))
    finally:
        print('Evidencia: '+str(bank.root))
        if not args.keep: bank.stop()
