-- ============================================================================
-- 20260728044338_crm_perfiles_cuentas_no_vaciar.sql
--
-- Un CLIENTE que ya tiene cuenta bancaria no puede QUEDAR sin ninguna.
--
-- ⚠️ TOCA public.perfiles (tabla del PORTAL en producción) con OK EXPLÍCITO de
--    Miguel (2026-07-27, chat: «si al trigger»). Anotado también en el ledger.
--
-- Por qué: el blindaje del 2026-07-27 garantiza que el cliente NACE con al
-- menos una cuenta (edges crear-cliente v24 / crm-convertir-lead v6 exigen el
-- bloque bancario en el MISMO INSERT). Pero la pantalla «Corregir» del CRM es
-- un UPDATE crudo a public.perfiles bajo RLS: el asesor que creó al cliente
-- (ventana de 5 h de perfiles_analista_update) — o el propio cliente sobre su
-- fila — podía VACIAR las 14 columnas bancarias y dejar un cliente real al que
-- pagos no puede transferir. Este trigger cierra esa última puerta.
--
-- Qué SÍ se puede seguir haciendo (pedido de Miguel, sin recortes):
--   · editar número, banco, CCI, tipo, beneficiario — todo, dentro de su ventana;
--   · cambiar una cuenta por otra (full → full);
--   · agregar la segunda moneda, o quitar UNA moneda si la otra queda viva;
--   · filas legacy SIN cuenta: siguen editables igual que hoy (grandfathering —
--     por eso es un TRIGGER de transición y no un CHECK, que las rompería).
-- Lo ÚNICO bloqueado: la transición «tenía al menos una cuenta → queda sin
-- ninguna». Aplica a TODOS los roles, service_role incluido: las edges solo
-- INSERTan (no les afecta) y no existe ningún flujo legítimo que vacíe todo.
--
-- «Tiene cuenta» = banco + n° de cuenta de una moneda (lo mínimo que el área de
-- pagos necesita para transferir). CCI/tipo no entran en la definición: hay
-- legacy parcial y endurecerlos aquí cambiaría el alcance acordado.
--
-- Orden de despliegue: SERVIDOR solamente (no hay clave nueva en request ni en
-- response; el front no cambia). Sin dependencia de /release-crm.
-- ============================================================================

create or replace function public.perfiles_cuentas_no_vaciar()
returns trigger
language plpgsql
set search_path to 'public', 'pg_temp'
as $$
declare
  tenia boolean;
  queda boolean;
begin
  -- nullif(btrim(...)): '' y '   ' cuentan como VACÍO. Sin esto, un PATCH con
  -- cadenas vacías en las 4 columnas satisface `is not null` y vacía al cliente
  -- sin disparar el freno (hallazgo ALTO de la auditoría: banco/numero_cuenta
  -- no tienen CHECK de formato en la BD, así que '' entra limpio). Aplicado
  -- también a OLD: un legacy con '' no cuenta como «tenía cuenta» y sigue en
  -- grandfathering — se puede limpiar a null sin pelearse con el trigger.
  tenia := (nullif(btrim(old.banco), '') is not null and nullif(btrim(old.numero_cuenta), '') is not null)
        or (nullif(btrim(old.banco_usd), '') is not null and nullif(btrim(old.numero_cuenta_usd), '') is not null);
  queda := (nullif(btrim(new.banco), '') is not null and nullif(btrim(new.numero_cuenta), '') is not null)
        or (nullif(btrim(new.banco_usd), '') is not null and nullif(btrim(new.numero_cuenta_usd), '') is not null);

  -- OLD.rol a propósito (decisión load-bearing, NO «simplificar» a NEW.rol):
  -- este trigger corre ANTES que trg_proteger_perfiles, así que un PATCH
  -- {"rol":"comercial", bancarios en null} vería NEW.rol ya cambiado y se
  -- saltaría el freno; con OLD.rol el intento se evalúa sobre lo que la fila ES.
  if old.rol = 'cliente' and tenia and not queda then
    raise exception 'El cliente debe conservar al menos una cuenta bancaria (en soles o en dólares): corrige los datos en lugar de vaciarlos.'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

comment on function public.perfiles_cuentas_no_vaciar() is
  'Frontera de datos bancarios (2026-07-28): bloquea la transición «cliente con cuenta → cliente sin ninguna cuenta». Complemento del blindaje del alta (bancarios.mjs en las edges). No es un CHECK a propósito: las filas legacy sin cuenta siguen válidas.';

-- Dispara solo cuando el UPDATE toca las columnas que definen «tiene cuenta»;
-- un UPDATE de teléfono/nombre/etc. ni ejecuta la función.
create trigger trg_perfiles_cuentas_no_vaciar
  before update of banco, numero_cuenta, banco_usd, numero_cuenta_usd
  on public.perfiles
  for each row
  execute function public.perfiles_cuentas_no_vaciar();

comment on trigger trg_perfiles_cuentas_no_vaciar on public.perfiles is
  'Un cliente con cuenta bancaria no puede quedar sin ninguna (OK de Miguel 2026-07-27). Editar/corregir/cambiar cuentas sigue libre. Límite del UPDATE OF: si un futuro trigger BEFORE anterior mutara NEW.banco*, esas mutaciones no re-disparan este OF — hoy ningún trigger previo toca columnas bancarias.';

-- Hardening de rutina: nadie llama una función-trigger por RPC, pero el revoke
-- deja la superficie en cero igual que el resto de funciones del proyecto.
revoke all on function public.perfiles_cuentas_no_vaciar() from public, anon, authenticated;
