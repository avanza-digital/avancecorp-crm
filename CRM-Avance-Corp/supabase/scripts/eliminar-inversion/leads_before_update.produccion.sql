CREATE OR REPLACE FUNCTION private.leads_before_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'crm', 'public'
AS $function$
declare
  v_priv boolean := coalesce(current_setting('crm.op_privilegiada', true) = 'on', false);
begin
  -- Columnas inmutables: restaurar siempre desde OLD.
  new.id := old.id;
  new.creado_por := old.creado_por;
  new.alta_manual := old.alta_manual;
  new.creado_en := old.creado_en;
  new.actualizado_en := now();

  -- Conversión y enlace al portal: SOLO desde una RPC privilegiada
  -- (que fija crm.op_privilegiada='on'). Un cliente API no puede convertir
  -- ni enlazar perfil_id/contrato_id a mano.
  if not v_priv then
    if new.etapa = 'convertido' and old.etapa <> 'convertido' then
      raise exception 'La conversión a cliente solo se hace vía la operación de conversión';
    end if;
    new.perfil_id := old.perfil_id;
    new.contrato_id := old.contrato_id;
    new.convertido_en := old.convertido_en;

    -- ── SELLO DEL ORIGEN (migración D, 2026-08-11) ────────────────────────
    -- El origen se elige al ALTA y no se vuelve a mover. Lo que esto protege
    -- NO es un mes ya contado —el snapshot `lead_asignaciones.origen` ya era
    -- inmutable por `trg_lead_asignaciones_00_inmutables`— sino dos cosas del
    -- presente y del futuro:
    --   · el origen que copiará `private.trg_leads_asignaciones` al abrir el
    --     PRÓXIMO episodio de este lead (y ése sí sale del divisor del mes en
    --     curso si dice 'referido');
    --   · el bloque `referidos.dados_de_alta`, único número del payload que
    --     lee esta columna viva, agrupado por el mes de ALTA del lead.
    -- Se avisa con EXCEPCIÓN en vez de restaurar en silencio porque el store
    -- del front es optimista: un 200 mudo dejaría al usuario convencido de
    -- que corrigió.
    -- Va DENTRO de `if not v_priv`, a propósito: encima del gate el dato
    -- quedaría incorregible para siempre y el único remedio sería
    -- `disable trigger` en producción, que CLAUDE.md prohíbe.
    -- `is distinct from` (y no `<>`) hace que un UPDATE de payload completo que
    -- reenvía el MISMO valor no lance nada: es el caso de seed-demo.mjs y de
    -- test-rls.mjs, los dos únicos escritores que mandan `origen` en un UPDATE.
    if new.origen is distinct from old.origen then
      raise exception using
        errcode = 'P0409',
        message = 'El origen de un lead no se cambia despues del alta',
        detail  = pg_catalog.format(
          'lead %s: origen actual %L, intento %L',
          old.id, old.origen, new.origen),
        hint    = 'El origen se elige al crear el lead (crm.crear_lead_si_disponible). '
                  'La conversion mensual lee la FOTO del episodio, que ya es inmutable: '
                  'cambiar la ficha no mueve ningun mes ya contado, pero si moveria el '
                  'origen de los episodios FUTUROS de este lead y el bloque de referidos '
                  'dados de alta de su mes de creacion.';
    end if;
  end if;

  -- ── P4 RELAJADA (migración cierres externos, 2026-08-12) ────────────────
  -- Invariante de negocio en la transición (no como CHECK de tabla). Antes:
  -- «convertido ⇒ perfil_id no nulo». Ahora un convertido puede carecer de
  -- perfil SI Y SOLO SI tiene cierre externo (invirtió en una cooperativa y
  -- el portal no lo conoce). El EXISTS corre solo en la rama rara (convertido
  -- sin perfil) y lo sirve el UNIQUE de lead_id. Nótese que P2 sigue intacta:
  -- sin válvula no hay transición a convertido, con o sin cierre.
  if new.etapa = 'convertido' and new.perfil_id is null
     and not exists (
       select 1 from crm.cierres_externos ce where ce.lead_id = new.id and ce.es_cierre_inicial
     ) then
    raise exception 'Un lead convertido debe estar enlazado a un perfil de cliente';
  end if;

  return new;
end;
$function$

;
