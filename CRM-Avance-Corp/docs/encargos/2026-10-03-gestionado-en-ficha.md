# Gestionado coherente en ficha y listados — propuesta histórica y cierre

Estado vigente: **PUBLICADO, INTEGRADO Y SESIÓN CERRADA el 03/10/2026** tras la autorización «Sí, probar y publicar todo». Build `build-20261004T025651347Z`, servidor `20261003225551`, RLS 2.823 PASS, Docker 21/21 PASS. Véase [acta final](../publicaciones/gestionado-ficha-2026-10-03.md). El SQL de abajo es la propuesta histórica; la migración final incluye validación de matrices y pre/postflight de seguridad. PR #181 fusionada a Main (`19688216`); PR #180 también fusionada. Sin aprobación pendiente.

## Resultado propuesto

Mostrar «Gestionado» en la cabecera y el progreso de la ficha, en Leads con cualquier filtro, en su tarjeta al pasar el mouse, en la búsqueda global y en el diálogo de tareas. Se calcula automáticamente: no es una etapa que el analista pueda marcar a mano. Contactos deshechos o de una asignación anterior no cuentan.

## Cambio mínimo de servidor

Agregar una consulta de solo lectura por lote de hasta 100 identificadores. La puerta `crm.gestion_vigente_fn` delega al núcleo privado; ambos son SECURITY INVOKER y conservan las policies actuales. Devuelve únicamente identificadores, titular, fecha de asignación y un booleano. No cambia clientes, actividades, etapas, tablas, policies ni datos.

Motivo: la API actual solo clasifica las columnas filtradas del Pipeline; la ficha y la lista sin filtro no reciben esa clasificación. El historial paginado y el último contacto no bastan: pueden ocultar el contacto válido o contar uno deshecho. La alternativa de lectura directa fue probada en local pero se descarta para publicación porque CLAUDE.md exige que el trabajo nuevo use puerta → núcleo.

## SQL propuesto (no aplicado; sujeto a revisión y banco)

```sql
begin;
create function private.gestion_vigente_lectura(p_lead_ids uuid[])
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_salida jsonb;
begin
  if (select auth.uid()) is null or not private.puede_acceder_crm() then
    raise exception 'No autorizado' using errcode = '42501';
  end if;
  if p_lead_ids is null or cardinality(p_lead_ids) > 100
     or array_position(p_lead_ids, null) is not null then
    raise exception 'Lista de leads inválida' using errcode = '22023';
  end if;
  select jsonb_build_object('version', 1, 'items',
    coalesce(jsonb_agg(jsonb_build_object(
      'lead_id', l.id, 'vendedor_id', l.vendedor_id,
      'tenencia_desde', l.tenencia_desde,
      'gestion_vigente', l.vendedor_id is not null
        and l.tenencia_desde is not null and exists (
          select 1 from crm.actividades a
          where a.lead_id = l.id and a.creado_en >= l.tenencia_desde
            and a.tipo in ('llamada_realizada', 'llamada_no_contestada',
              'whatsapp_enviado', 'whatsapp_recibido', 'reunion_realizada')
            and not (a.metadata ? 'deshecho_en')
        )
    ) order by l.id), '[]'::jsonb)) into v_salida
  from crm.leads l
  where l.id = any(p_lead_ids) and l.activo and l.etapa = 'nuevo';
  return v_salida;
end;
$$;
create function crm.gestion_vigente_fn(p_lead_ids uuid[])
returns jsonb language sql stable security invoker set search_path = '' as $$
  select private.gestion_vigente_lectura(p_lead_ids);
$$;
alter function private.gestion_vigente_lectura(uuid[]) owner to postgres;
alter function crm.gestion_vigente_fn(uuid[]) owner to postgres;
revoke all on function private.gestion_vigente_lectura(uuid[]) from public, anon;
revoke all on function crm.gestion_vigente_fn(uuid[]) from public, anon;
grant execute on function private.gestion_vigente_lectura(uuid[]) to authenticated;
grant execute on function crm.gestion_vigente_fn(uuid[]) to authenticated;
comment on function private.gestion_vigente_lectura(uuid[]) is
  'Lectura operativa de gestión vigente de nuevos: contacto no deshecho desde la tenencia actual; RLS del actor, lote máximo 100, sin datos de contacto.';
comment on function crm.gestion_vigente_fn(uuid[]) is
  'Puerta de lectura por lote para la etiqueta Gestionado; delega al núcleo privado y conserva RLS.';
notify pgrst, 'reload schema';
commit;
```

## Ejecución tras autorización

1. Revisar el SQL y los guardianes de nuevas puertas del proyecto; agregar declaraciones de contrato si las exigen.
2. Crear migración mediante CLI; probar en rama de Supabase, matriz RLS por rol y advisors. Regenerar tipos desde el esquema probado.
3. Conectar la pantalla a esta RPC (retirar la lectura directa de la candidata), repetir gates y comparar resultados con el filtro existente.
4. Publicar primero servidor verificado y después frontend por `$release-crm` ya autorizado. Conservar ZIP anterior.

Reversa: volver al frontend anterior antes de retirar las dos funciones nuevas en una migración separada. No hay datos que revertir.

Autorización requerida por CLAUDE.md: «Cambios en tablas, RLS, permisos o funciones de api: presentar un plan corto y esperar confirmación antes de escribir código». La habilidad release-crm autoriza frontend, no migraciones pendientes. Este documento es el plan/SQL propuesto, no una aplicación productiva.


## Pausa solicitada — 03/10/2026

Miguel autorizó «Sí, probar y publicar todo» y después solicitó pausar para continuar más tarde. **PAUSADO; la ampliación de la ficha no se publicó.**

Código y migración en `/private/tmp/avancecorp-gestionado-release-20261003`; checkpoint completo en `/private/tmp/avancecorp-gestionado-ficha-20261003/CONTINUAR.md`. Pantalla: check integral y 19/19 E2E Docker PASS con RPC. Backend aplicado solo a la branch `gestionado-ficha-20261003` (`lyhyvgpzwngmptpboupk`); seed ficticio preparado, matriz RLS y comprobaciones finales pendientes. La branch permanece activa a US$0.01344/h hasta retomar. No publicar hasta nueva instrucción.
