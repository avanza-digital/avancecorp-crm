import { createClient } from "npm:@supabase/supabase-js@2.110.2";
import { crearHandlerValoracion, type TrabajoTipoCambio } from "./handler.ts";

// Algunas ramas reciben una sb_secret en la variable reservada. El gateway
// verify_jwt exige un JWT: fijar la service_role JWT vigente en secreto propio.
const claveServicio = Deno.env.get("CRM_CAPITAL_VALORAR_SERVICE_KEY") ??
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const servicio = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  claveServicio,
  {
    auth: { persistSession: false, autoRefreshToken: false },
    global: {
      fetch: (url, opciones) =>
        fetch(url, { ...opciones, signal: AbortSignal.timeout(8_000) }),
    },
  },
);
async function dato<T>(
  consulta: PromiseLike<{ data: T; error: unknown }>,
): Promise<T> {
  const { data, error } = await consulta;
  if (error) throw error;
  return data;
}

Deno.serve(crearHandlerValoracion({
  claveServicio,
  fetch,
  ahora: () => Date.now(),
  reconciliar: () =>
    dato(
      servicio.schema("crm").rpc("reconciliar_capital_valoraciones_fn", {
        p_limite: 500,
      }),
    ),
  reevaluarCierre: () =>
    dato(servicio.schema("crm").rpc("reevaluar_cierre_capital_fn")),
  tomar: () =>
    dato(
      servicio.schema("crm").rpc("tomar_fechas_tipo_cambio_fn", {
        p_limite: 3,
      }),
    ) as Promise<TrabajoTipoCambio[]>,
  resolver: (t, evidencia, motivo) =>
    dato(
      servicio.schema("crm").rpc("resolver_fecha_tipo_cambio_fn", {
        p_fecha: t.fecha_corte,
        p_reserva: t.reserva,
        p_evidencia: evidencia,
        p_motivo: motivo,
      }),
    ),
}));
