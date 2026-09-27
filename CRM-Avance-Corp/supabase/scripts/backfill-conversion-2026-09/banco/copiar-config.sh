#!/usr/bin/env bash
# Copia al banco Docker local SOLO la configuración de producción (cero datos de personas).
# Uso: desde CRM-Avance-Corp/, con el banco ya cargado con el esquema de prod.
set -euo pipefail
DIR=$(mktemp -d)
export PGPASSWORD=postgres
for T in crm.multiempresa_flags crm.conversion_pesos crm.empresas crm.productos_inversion crm.sla_politicas \
  crm.sla_politica_etapas crm.sla_politica_etapas_operacion crm.sla_operacion_control crm.enfriamiento_politica \
  crm.politica_rentabilidad crm.politica_abandono crm.politica_gestion_diaria crm.piloto_f8_control crm.meta_periodos \
  crm.control_citas_versiones crm.control_citas_aplicaciones crm.rentabilidad_hitos private.analista_vigencia_tope \
  private.analitica_leads_citas_tope private.auditoria_condicionada private.auditoria_sello private.analitica_lc_sello \
  private.auditoria_exenciones private.analista_vigencia_exenciones private.analitica_leads_citas_exenciones \
  private.f7_piezas_en_observacion private.pares_autoridad; do
  supabase db query --linked -o json "select coalesce(json_agg(t),'[]'::json)::text j from $T t" 2>/dev/null \
    | jq -r '.rows[0].j' > "$DIR/$T.json"
  psql -h 127.0.0.1 -p 55322 -U postgres -d postgres -v ON_ERROR_STOP=1 -At -v j="$(cat "$DIR/$T.json")" <<SQL
set session_replication_role = replica;
insert into $T select * from json_populate_recordset(null::$T, :'j'::json) on conflict do nothing;
SQL
  echo "$T prod=$(jq length "$DIR/$T.json")"
done
rm -rf "$DIR"
