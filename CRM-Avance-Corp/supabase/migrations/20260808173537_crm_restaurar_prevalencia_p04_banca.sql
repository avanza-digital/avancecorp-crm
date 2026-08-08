-- Restaura la prevalencia P04 en el guard bancario.
--
-- Reconciliación del gate F0 (2026-08-08, autorizada por Miguel). Arqueología:
--   · 20260804144555 (P04 banca, gate verde 2026-08-04): el guard
--     private.puede_gestionar_cuentas_cliente exigía
--     `and (select private.puede_acceder_crm())` ANTES de cualquier poder de
--     portal — «una fila revocada en crm.equipo prevalece sobre es_admin /
--     es_analista».
--   · 20260807123000 (gerencia operativa): conservó esa línea.
--   · 20260807235933 (catálogo de productos, aplicada a prod 2026-08-08):
--     REESCRIBIÓ el guard y la línea desapareció. Efecto: un analista o admin
--     del portal con membresía CRM REVOCADA volvía a listar/crear/corregir
--     cuentas bancarias (PII bancaria) por su poder de portal. La matriz
--     «banca P04» del gate lo detectó el mismo día: «no lista cuentas
--     contractuales: la operacion fue aceptada».
--
-- Esta migración reaplica EXACTAMENTE esa línea sobre la forma vigente del
-- guard (se conservan las ramas nuevas de vendedor/supervisor/gerencia del
-- catálogo). Con las funciones base de hoy («rol CRM efectivo»,
-- 20260807203740), la semántica resultante es: todo poder bancario del CRM
-- exige actor CRM efectivo (membresía activa o lector global Directorio);
-- admin/superadmin del portal sin membresía CRM quedan fuera — coherente con
-- el comment de es_lector_global: «Admin/Superadmin Portal no heredan lectura
-- operativa».
--
-- ⚠️ EFECTO SOBRE EL CANAL LEGACY DEL PORTAL (hallazgo del auditor-rls): esta
-- migración no contiene statements sobre `public`, pero desde el catálogo
-- `public.crear_contrato` — el RPC de las páginas legacy admin/analista — es
-- LLAMADOR del guard para todo actor. Restaurar la línea condiciona también el
-- alta legacy a membresía CRM efectiva. Impacto verificado en prod 2026-08-08:
-- los 20 analistas del portal tienen membresía CRM activa (nada cambia para
-- ellos); pierden banca/alta solo `gloria@` (admin sin fila en crm.equipo) y
-- `AdminCorp@` (superadmin) — los mismos actores que el diseño «rol CRM
-- efectivo» (20260807203740) declara fuera de la operación. Si alguno debe
-- operar, la vía es darle membresía CRM (acto operativo, no de esquema).
--
-- Deuda conocida que esta migración NO cierra (tocaría `public`, exige OK de
-- Miguel): la rama admin de `public.actualizar_contrato` (20260807235933:294)
-- no consulta el guard — un admin del portal sin membresía aún puede corregir
-- TÉRMINOS de contratos (no cuentas). Registrada en el ledger.

begin;

set local lock_timeout = '10s';

-- Preflight de dependencias (patrón del proyecto).
do $$
begin
  if to_regprocedure('private.puede_acceder_crm()') is null
     or to_regprocedure('private.rol_crm(uuid)') is null
     or to_regprocedure('private.vendedor_ids_visibles(uuid)') is null
     or to_regprocedure('public.es_admin()') is null
     or to_regprocedure('public.es_analista()') is null then
    raise exception 'Falta una dependencia del guard bancario';
  end if;
end;
$$;

create or replace function private.puede_gestionar_cuentas_cliente(
  p_cliente_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select (select auth.uid()) is not null
    -- Prevalencia P04 restaurada (2026-08-08): sin actor CRM efectivo no hay
    -- banca, sea cual sea el rol de portal. Una membresía revocada prevalece.
    and (select private.puede_acceder_crm())
    and exists (
      select 1
      from public.perfiles cli
      where cli.id = p_cliente_id
        and cli.rol = 'cliente'
        and cli.activo is true
        and (
          -- Poder del portal, ya condicionado por el gate P04 de arriba.
          (select public.es_admin())
          or (
            (select public.es_analista())
            and (
              cli.asesor_perfil_id = (select auth.uid())
              or (
                cli.asesor_perfil_id is null
                and cli.creado_por = (select auth.uid())
              )
            )
          )
          or (
            private.rol_crm((select auth.uid())) in (
              'vendedor', 'supervisor', 'gerencia'
            )
            and (
              private.rol_crm((select auth.uid())) = 'gerencia'
              or cli.asesor_perfil_id in (
                select private.vendedor_ids_visibles((select auth.uid()))
              )
            )
          )
        )
    );
$function$;

comment on function private.puede_gestionar_cuentas_cliente(uuid) is
  'Autoriza banca contractual. Prevalencia P04 (restaurada 2026-08-08): exige actor CRM efectivo antes de cualquier poder de portal; una membresía revocada prevalece. Helper interno de las RPC definer, sin EXECUTE directo.';

-- ACL del helper interno, idéntico al patrón P04 original.
revoke all on function private.puede_gestionar_cuentas_cliente(uuid)
  from public, anon, authenticated, service_role;

commit;
