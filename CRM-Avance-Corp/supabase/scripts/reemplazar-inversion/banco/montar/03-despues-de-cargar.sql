-- Banco reemplazo-inv (copiado de foto-sla-f2) · después de cargar volcado/esquema.sql. Ejecutar como supabase_admin.
\set ON_ERROR_STOP 1

-- 1. Restaurar los privilegios por defecto de supabase_admin en public (los mismos que tiene producción).
alter default privileges for role supabase_admin in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges for role supabase_admin in schema public grant all on sequences to postgres, anon, authenticated, service_role;

-- 2. Privilegios por defecto de postgres en public: en producción anon y authenticated reciben solo arwd en
--    tablas nuevas (el volcado solo concede; no puede quitar los Dxtm que trae la imagen).
alter default privileges for role postgres in schema public revoke truncate, references, trigger, maintain on tables from anon, authenticated;

-- 3. storage.objects VACÍA, con las 15 columnas de producción, para la única sentencia del volcado que falla:
--    la llave foránea crm.cierres_externos.comprobante_objeto_id -> storage.objects(id). Sin buckets, índices
--    ni políticas de storage (nada del SLA los usa).
create table storage.objects (
  id uuid not null default gen_random_uuid() primary key,
  bucket_id text,
  name text,
  owner uuid,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  last_accessed_at timestamptz default now(),
  metadata jsonb,
  path_tokens text[] generated always as (string_to_array(name, '/'::text)) stored,
  version text,
  owner_id text,
  user_metadata jsonb,
  archived_at timestamptz,
  is_delete_marker boolean not null default false,
  is_versioned boolean not null default false
);
alter table storage.objects owner to supabase_storage_admin;
alter table storage.objects enable row level security;
alter table only crm.cierres_externos
  add constraint cierres_externos_comprobante_objeto_id_fkey foreign key (comprobante_objeto_id) references storage.objects(id);

-- 4. Estadísticas del planificador al día (las tablas están vacías; el arnés debe repetir ANALYZE tras sembrar).
analyze;

-- 5. Privilegio por defecto de realtime igual que producción (postgres con opción de concesión en INSERT/SELECT).
alter default privileges for role supabase_admin in schema realtime grant insert, select on tables to postgres with grant option;
