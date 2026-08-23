#!/usr/bin/env bash
# Aplica a PRODUCCIÓN la migración 20260820190500 — el régimen documental por
# FECHA DE FIRMA: el PDF que emite el sistema es el contrato, pero solo para lo
# firmado del 19/08/2026 en adelante.
#
# ⚠️ ORDEN: la EDGE `crm-contrato-pdf-v2` va PRIMERO, antes que esta migración.
# No es un capricho. `parseEstado` exige hoy `reintentable === true` cuando el
# estado es `sin_reserva`; en cuanto el servidor empiece a responder `false` para
# un contrato antiguo, una Edge vieja descartaría la respuesta entera y devolvería
# 502. El detalle de CUALQUIER contrato antiguo se rompería. Con la Edge nueva y
# el servidor viejo no pasa nada: tolera un campo que todavía nadie envía.
#
# El frontend puede ir después: no depende de claves nuevas, solo deja de ofrecer
# el botón que fabricaba documentos para operaciones ya firmadas.
#
# ⚠️ `supabase db query` DEVUELVE SOLO FILAS Y SE TRAGA LOS AVISOS (comprobado
# el 2026-08-20 aplicando esto): los tres «POSTFLIGHT ... OK» NO se imprimen por
# esta vía, así que aquí no sirven de prueba. Lo que sí prueban es lo contrario:
# si una sonda levantara excepción, la transacción entera se echaría atrás y el
# paso 4/4 no encontraría la fila en el registro. La comprobación POSITIVA es el
# paso 3/4, que mide con SELECT exactamente lo mismo que dirían las sondas:
#   · POSTFLIGHT 1 OK · regimen nuevo=N · anterior=M   (medido el 2026-08-20:
#     nuevo=5, anterior=410 sobre 415 contratos; si sale «SIN DATOS», PARA)
#   · POSTFLIGHT 2 OK · antiguos=… · de ellos ya emitidos e intactos=21
#   · POSTFLIGHT 3 OK · las cuatro puertas consultan la fuente unica
# Si alguna dice SIN DATOS, algo va mal: PARA y revisa antes de registrar nada.
#
# Toda la migración va dentro de una transacción: si un postflight levanta
# excepción, no queda aplicada.
set -euo pipefail
cd "$(dirname "$0")"
export SUPABASE_ACCESS_TOKEN="$(security find-generic-password -s 'Supabase CLI' -w)"
S=$(mktemp -d)

echo "── 0/4 · la Edge PRIMERO ─────────────────────────────────────────────────"
echo "   Despliega crm-contrato-pdf-v2 ANTES de continuar y confirma que quedó"
echo "   ACTIVE. Si no lo has hecho, corta aquí (Ctrl-C)."
echo "   Comprobación rápida del cambio que importa: parseEstado ya NO exige"
echo "   reintentable === true para sin_reserva."
grep -q 'reintentable` NO se exige aquí' supabase/functions/crm-contrato-pdf-v2/handler.ts \
  || { echo "ERROR: el handler local no es el tolerante. PARA."; exit 1; }

echo "── 1/4 · aplicando (lee los TRES postflight: OK, nunca SIN DATOS) ────────"
npx --yes supabase@latest db query --linked \
  --file supabase/migrations/20260820190500_crm_documento_regimen_por_fecha_de_firma.sql

echo "── 2/4 · registrando en el índice ────────────────────────────────────────"
printf "insert into supabase_migrations.schema_migrations(version) values ('20260820190500') on conflict do nothing;\n" > "$S/reg.sql"
npx --yes supabase@latest db query --linked --file "$S/reg.sql"

echo "── 3/4 · comprobando EJECUTANDO, no por lo que dijo el comando ───────────"
cat > "$S/ver.sql" <<'SQL'
-- La frontera se comprueba clasificando contratos REALES y mirando lo que
-- responde el estado. Mirar el catálogo no prueba nada.
do $$
declare
  v_nuevos int; v_anteriores int;
  v_prometidos int; v_emitidos int;
  v_puertas int;
begin
  select
    count(*) filter (where private.contrato_documental_regimen(c.id) = 'nuevo'),
    count(*) filter (where private.contrato_documental_regimen(c.id) = 'anterior')
  into v_nuevos, v_anteriores
  from public.contratos c;
  if v_nuevos + v_anteriores = 0 then
    raise exception 'VERIFICACIÓN: cero contratos clasificados — la sonda no midió nada';
  end if;

  -- Ni un solo contrato antiguo sin archivo puede seguir prometiendo documento.
  select count(*) into v_prometidos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior'
    and not exists (select 1 from private.contrato_pdfs p where p.contrato_id = c.id)
    and (
      (private.contrato_pdf_estado_base(c.id)->>'estado') <> 'sin_reserva'
      or (private.contrato_pdf_estado_base(c.id)->>'reintentable')::boolean
    );
  if v_prometidos > 0 then
    raise exception 'VERIFICACIÓN: % contratos antiguos siguen prometiendo documento', v_prometidos;
  end if;

  -- Y los ya emitidos siguen sellados y descargables: esto no borra nada.
  select count(*) into v_emitidos
  from public.contratos c
  where private.contrato_documental_regimen(c.id) = 'anterior'
    and exists (select 1 from private.contrato_pdfs p where p.contrato_id = c.id)
    and (private.contrato_pdf_estado_base(c.id)->>'estado') = 'sellado';

  -- Las cuatro puertas, por la LLAMADA cualificada (una mención en un comentario
  -- aprobaría la sonda sin que nadie consulte nada).
  select count(*) into v_puertas
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname || '.' || p.proname in (
      'private.crear_job_contrato_pdf_base',
      'private.crear_revision_contrato_pdf_base',
      'private.contrato_pdf_estado_base',
      'crm.contrato_pdf_reclamar')
    and strpos(p.prosrc, 'private.contrato_documental_regimen(') > 0;
  if v_puertas <> 4 then
    raise exception 'VERIFICACIÓN: solo % de 4 puertas consultan la fuente única', v_puertas;
  end if;

  raise notice 'VIVO · nuevo=% · anterior=% · ya emitidos e intactos=% · puertas=4/4',
    v_nuevos, v_anteriores, v_emitidos;
end;
$$;

-- Los dos huérfanos del 19-ago: la fila SIGUE ahí (no se borra nada) y ya no
-- promete documento.
select c.numero_contrato,
       j.estado as trabajo,
       j.intentos,
       private.contrato_pdf_estado_base(c.id)->>'estado' as responde_la_pantalla,
       private.contrato_pdf_estado_base(c.id)->>'reintentable' as ofrece_generar
from public.contratos c
join private.contrato_pdf_jobs j on j.contrato_id = c.id
where private.contrato_documental_regimen(c.id) = 'anterior'
  and not exists (select 1 from private.contrato_pdfs p where p.contrato_id = c.id)
order by c.creado_en;
SQL
npx --yes supabase@latest db query --linked --file "$S/ver.sql"

echo "── 4/4 · el registro remoto tiene la fila ────────────────────────────────"
printf "select version from supabase_migrations.schema_migrations where version = '20260820190500';\n" > "$S/idx.sql"
npx --yes supabase@latest db query --linked --file "$S/idx.sql"

rm -rf "$S"
echo "LISTO. Falta publicar el frontend con /release-crm (lo invoca Miguel)."
