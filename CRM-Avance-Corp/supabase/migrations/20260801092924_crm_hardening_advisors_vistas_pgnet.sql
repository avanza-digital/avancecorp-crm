-- Hardening tras auditoría de advisors 2026-08-01 (47 seguridad + 24 rendimiento).
-- 4 fixes reales; el resto quedó triado como intencional o diferido.

-- 1) Vistas del CRM a security_invoker.
--    La autorización NO vive en la vista sino en las *_fn() internas
--    (SECURITY DEFINER con filtro por rol vía private.rol_crm /
--    private.vendedor_ids_visibles). authenticated ya tiene EXECUTE sobre
--    las _fn, así que el cambio no altera filas visibles: solo limpia el
--    ERROR security_definer_view del linter.
alter view crm.contratos_cartera set (security_invoker = true);
alter view crm.clientes_basicos  set (security_invoker = true);

-- 2) contrato_tiene_pagos: era la ÚNICA de las 41 RPC expuestas sin guardia.
--    Cualquier authenticated (incluidos clientes del portal) podía sondear
--    si un contrato ajeno tiene pagos conociendo el UUID. puede_ver_contrato
--    cubre admin, cliente dueño y analista de cartera; para un no autorizado
--    devuelve false (sin excepción). DOS llamadores (hallazgo auditor-rls):
--    (a) public_html/js/admin/contratos.js (pantalla admin) — no cambia;
--    (b) la policy DELETE de public.contratos: es_superadmin() OR (es_admin()
--        AND NOT contrato_tiene_pagos(id)). Equivalencia probada: la policy
--        solo evalúa el helper con es_admin()=true, y en ese caso
--        puede_ver_contrato ≡ true (primera rama del OR), así que el predicado
--        del DELETE queda idéntico. El predicado de pagos se conserva carácter
--        a carácter contra el def de prod (verificado por pg_get_functiondef).
create or replace function public.contrato_tiene_pagos(p_contrato_id uuid)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $$
  select public.puede_ver_contrato(p_contrato_id)
     and exists (
       select 1 from public.cronograma_pagos cp
       where cp.contrato_id = p_contrato_id
         and (cp.estado = 'pagado' or cp.monto_pagado is not null)
     );
$$;

-- 3) pg_net: anon, authenticated y PUBLIC tienen USAGE sobre net y EXECUTE
--    sobre net.http_get/http_post (SSRF latente). ⚠️ REALIDAD (verificada en
--    el branch): esos grants los concedió supabase_admin y nuestro rol
--    postgres NO puede revocarlos — estos statements son NO-OP en Supabase
--    gestionado (el ACL queda intacto). Se dejan como declaración de intención:
--    aplican si el runner tiene privilegios (shadow DB local/CI) o si la
--    plataforma cambia el grantor. Mitigación real hoy: (1) el esquema net no
--    está en los Exposed schemas de la API (config de plataforma — confirmar
--    en dashboard), (2) los únicos usos legítimos (jobs pg_cron
--    recordatorio-cuotas-3d y ciclo-contratos-diario — hallazgo auditor-rls)
--    corren como postgres (verificado en cron.job.username).
revoke execute on all functions in schema net from anon, authenticated;
revoke usage on schema net from anon, authenticated;

-- 4) Índices para las 3 FKs sin cubrir (lint 0001). Tablas chicas: el costo
--    es nulo y evita seq scans en los cierres/renovaciones de contratos.
create index if not exists idx_contratos_cerrado_por
  on public.contratos (cerrado_por);
create index if not exists idx_contratos_renovado_a_id
  on public.contratos (renovado_a_id);
create index if not exists idx_contrato_titulares_creado_por
  on public.contrato_titulares (creado_por);
