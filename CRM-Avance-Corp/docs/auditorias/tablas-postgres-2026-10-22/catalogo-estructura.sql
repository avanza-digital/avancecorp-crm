CREATE SCHEMA IF NOT EXISTS "crm";

CREATE SCHEMA IF NOT EXISTS "private";

CREATE TYPE "crm"."nivel_potencial" AS ENUM (
    'frio',
    'tibio',
    'estrella'
);

CREATE TABLE IF NOT EXISTS "crm"."meta_periodos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "periodo" "date" NOT NULL,
    "revision" integer NOT NULL,
    "revision_anterior_id" "uuid",
    "publicada_por" "uuid" NOT NULL,
    "publicada_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "meta_periodos_primer_dia_mes" CHECK (("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp with time zone))::"date")),
    CONSTRAINT "meta_periodos_revision_check" CHECK (("revision" > 0))
);

COMMENT ON TABLE "crm"."meta_periodos" IS 'Publicaciones mensuales inmutables. La revision mayor del periodo es la vigente.';

CREATE TABLE IF NOT EXISTS "crm"."sla_politicas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version" integer NOT NULL,
    "version_anterior_id" "uuid",
    "vigente_desde" timestamp with time zone NOT NULL,
    "zona_horaria" "text" NOT NULL,
    "tipo_reloj" "text" NOT NULL,
    "primera_gestion_minutos" integer NOT NULL,
    "primer_contacto_minutos" integer NOT NULL,
    "publicada_por" "uuid",
    "publicada_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "sla_contacto_despues_gestion" CHECK (("primer_contacto_minutos" >= "primera_gestion_minutos")),
    CONSTRAINT "sla_politicas_primer_contacto_minutos_check" CHECK ((("primer_contacto_minutos" >= 1) AND ("primer_contacto_minutos" <= 43200))),
    CONSTRAINT "sla_politicas_primera_gestion_minutos_check" CHECK ((("primera_gestion_minutos" >= 1) AND ("primera_gestion_minutos" <= 43200))),
    CONSTRAINT "sla_politicas_tipo_reloj_check" CHECK (("tipo_reloj" = 'corrido'::"text")),
    CONSTRAINT "sla_politicas_version_check" CHECK (("version" > 0)),
    CONSTRAINT "sla_politicas_zona_horaria_check" CHECK (("zona_horaria" = 'America/Lima'::"text"))
);

COMMENT ON TABLE "crm"."sla_politicas" IS 'Versiones SLA globales inmutables. Se aplica la mayor vigente_desde no posterior al evento.';

COMMENT ON COLUMN "crm"."sla_politicas"."primera_gestion_minutos" IS 'Primer intento: llamada realizada/no contestada, WhatsApp enviado/recibido o reunion realizada.';

COMMENT ON COLUMN "crm"."sla_politicas"."primer_contacto_minutos" IS 'Contacto efectivo: llamada realizada, WhatsApp recibido o reunion realizada.';

CREATE TABLE IF NOT EXISTS "crm"."cierre_mes_vendedor" (
    "periodo" "date" NOT NULL,
    "vendedor_id" "uuid" NOT NULL,
    "nombre_completo" "text" NOT NULL,
    "supervisor_id" "uuid" NOT NULL,
    "supervisor_nombre" "text" NOT NULL,
    "divisor" integer NOT NULL,
    "divisor_aproximado" integer DEFAULT 0 NOT NULL,
    "divisor_por_motivo" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "cierres_no_referidos" integer NOT NULL,
    "cierres_referidos" integer NOT NULL,
    "cierres_de_arrastre" integer NOT NULL,
    "numerador" numeric NOT NULL,
    "conversion_pct" numeric,
    "estado" "text" NOT NULL,
    "referidos_recibidos" integer NOT NULL,
    "referidos_dados_de_alta" integer NOT NULL,
    "referidos_aporta_pct" numeric,
    "procedencia" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "ajuste_numerador" numeric DEFAULT 0 NOT NULL,
    "ajuste_pen" numeric DEFAULT 0 NOT NULL,
    "ajuste_usd" numeric DEFAULT 0 NOT NULL,
    "conversion_objetivo" numeric NOT NULL,
    "detalles" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "cartera" "jsonb" DEFAULT "jsonb_build_object"('conversiones_clientes', 0, 'conversiones_renovacion', 0, 'conversiones_upgrade', 0, 'operaciones_renovacion', 0, 'operaciones_upgrade', 0, 'capital_renovado_pen', 0, 'capital_renovado_usd', 0, 'capital_adicional_pen', 0, 'capital_adicional_usd', 0, 'renovaciones_sin_desglose', 0) NOT NULL,
    "origenes_ranking" "jsonb",
    "cartera_ranking" "jsonb",
    CONSTRAINT "cierre_mes_vendedor_ajuste_numerador_finito" CHECK ((("ajuste_numerador" <> 'NaN'::numeric) AND ("ajuste_numerador" <> 'Infinity'::numeric) AND ("ajuste_numerador" <> '-Infinity'::numeric))),
    CONSTRAINT "cierre_mes_vendedor_ajuste_pen_finito" CHECK ((("ajuste_pen" <> 'NaN'::numeric) AND ("ajuste_pen" <> 'Infinity'::numeric) AND ("ajuste_pen" <> '-Infinity'::numeric))),
    CONSTRAINT "cierre_mes_vendedor_ajuste_usd_finito" CHECK ((("ajuste_usd" <> 'NaN'::numeric) AND ("ajuste_usd" <> 'Infinity'::numeric) AND ("ajuste_usd" <> '-Infinity'::numeric))),
    CONSTRAINT "cierre_mes_vendedor_cartera_objeto_check" CHECK (("jsonb_typeof"("cartera") = 'object'::"text")),
    CONSTRAINT "cierre_mes_vendedor_conversion_objetivo_finito" CHECK ((("conversion_objetivo" IS NULL) OR (("conversion_objetivo" <> 'NaN'::numeric) AND ("conversion_objetivo" <> 'Infinity'::numeric) AND ("conversion_objetivo" <> '-Infinity'::numeric)))),
    CONSTRAINT "cierre_mes_vendedor_conversion_pct_finito" CHECK ((("conversion_pct" IS NULL) OR (("conversion_pct" <> 'NaN'::numeric) AND ("conversion_pct" <> 'Infinity'::numeric) AND ("conversion_pct" <> '-Infinity'::numeric)))),
    CONSTRAINT "cierre_mes_vendedor_numerador_finito" CHECK ((("numerador" <> 'NaN'::numeric) AND ("numerador" <> 'Infinity'::numeric) AND ("numerador" <> '-Infinity'::numeric))),
    CONSTRAINT "cierre_mes_vendedor_referidos_aporta_pct_finito" CHECK ((("referidos_aporta_pct" IS NULL) OR (("referidos_aporta_pct" <> 'NaN'::numeric) AND ("referidos_aporta_pct" <> 'Infinity'::numeric) AND ("referidos_aporta_pct" <> '-Infinity'::numeric))))
);

COMMENT ON TABLE "crm"."cierre_mes_vendedor" IS 'Foto por (mes, vendedor) de todo lo que decidio pago: conversion, cumplimiento de meta y capital. Es el registro de lo que se pago, asi que congela tambien el NOMBRE: el asesor puede irse del equipo. Deny-by-default: se lee solo via las funciones del esquema crm.';

COMMENT ON COLUMN "crm"."cierre_mes_vendedor"."nombre_completo" IS 'Congelado al sellar. Sin el, la foto de un mes pagado dependeria de que la ficha del asesor siga existiendo.';

COMMENT ON COLUMN "crm"."cierre_mes_vendedor"."detalles" IS 'El array `detalles` publicado: capital y contratos, objetivo y real, por categoria y moneda.';

COMMENT ON COLUMN "crm"."cierre_mes_vendedor"."cartera" IS 'Foto inmutable de private.metricas_cartera_por_vendedor al sellar: conversiones y operaciones de renovacion/upgrade, capital renovado/adicional y faltantes de desglose. Nunca se recalcula para un mes cerrado.';

CREATE TABLE IF NOT EXISTS "crm"."tareas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid",
    "perfil_id" "uuid",
    "vendedor_id" "uuid",
    "asignado_supervisor_id" "uuid",
    "tipo" "text" NOT NULL,
    "titulo" "text" NOT NULL,
    "nota" "text",
    "vence_en" timestamp with time zone NOT NULL,
    "duracion_min" smallint,
    "estado" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "resultado_actividad_id" "uuid",
    "reagendada_de" "uuid",
    "confirmada_en" timestamp with time zone,
    "reprogramaciones" smallint DEFAULT 0 NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cancelada_por" "text",
    "cancelada_por_id" "uuid",
    "modalidad_reunion" "text",
    "ubicacion_reunion" "text",
    "enlace_reunion" "text",
    "resultado_reunion" "text",
    "motivo_no_realizada" "text",
    "detalle_cierre_reunion" "text",
    "inversionista_id" "uuid",
    "postventa_revision" integer,
    CONSTRAINT "tareas_cancelada_por_id_valida" CHECK (
CASE
    WHEN ("cancelada_por" = 'asesor'::"text") THEN true
    ELSE ("cancelada_por_id" IS NULL)
END),
    CONSTRAINT "tareas_cancelada_por_valida" CHECK (
CASE
    WHEN ("estado" = 'cancelada'::"text") THEN (("cancelada_por" IS NOT NULL) AND ("cancelada_por" = ANY (ARRAY['asesor'::"text", 'sistema'::"text"])))
    ELSE ("cancelada_por" IS NULL)
END),
    CONSTRAINT "tareas_cierre_coherente" CHECK ((("estado" <> 'pendiente'::"text") OR ("resultado_actividad_id" IS NULL))),
    CONSTRAINT "tareas_cierre_reunion_coherente" CHECK (((("tipo" <> 'reunion'::"text") AND ("resultado_reunion" IS NULL) AND ("motivo_no_realizada" IS NULL) AND ("detalle_cierre_reunion" IS NULL)) OR (("tipo" = 'reunion'::"text") AND ((("estado" = 'pendiente'::"text") AND ("resultado_reunion" IS NULL) AND ("motivo_no_realizada" IS NULL)) OR (("estado" = 'completada'::"text") AND ("resultado_reunion" IS NOT NULL) AND ("motivo_no_realizada" IS NULL)) OR (("estado" = 'no_show'::"text") AND ("resultado_reunion" IS NULL) AND ("motivo_no_realizada" = 'cliente_no_asistio'::"text")) OR (("estado" = 'cancelada'::"text") AND ("resultado_reunion" IS NULL) AND ("motivo_no_realizada" = ANY (ARRAY['cancelada_cliente'::"text", 'cancelada_empresa'::"text", 'otro'::"text"])) AND (("motivo_no_realizada" <> 'otro'::"text") OR (NULLIF("btrim"(COALESCE("detalle_cierre_reunion", ''::"text")), ''::"text") IS NOT NULL))) OR (("estado" = 'reprogramada'::"text") AND ("resultado_reunion" IS NULL) AND ("motivo_no_realizada" = 'reprogramada'::"text")))))),
    CONSTRAINT "tareas_destino_reunion_coherente" CHECK (((("tipo" <> 'reunion'::"text") AND ("ubicacion_reunion" IS NULL) AND ("enlace_reunion" IS NULL)) OR (("tipo" = 'reunion'::"text") AND ((("modalidad_reunion" = 'presencial'::"text") AND ("ubicacion_reunion" IS NOT NULL) AND ("enlace_reunion" IS NULL)) OR (("modalidad_reunion" = 'virtual'::"text") AND ("ubicacion_reunion" IS NULL)) OR (("modalidad_reunion" = 'sin_clasificar'::"text") AND ("ubicacion_reunion" IS NULL) AND ("enlace_reunion" IS NULL)))))),
    CONSTRAINT "tareas_detalle_cierre_reunion_valido" CHECK ((("detalle_cierre_reunion" IS NULL) OR ("length"("detalle_cierre_reunion") <= 2000))),
    CONSTRAINT "tareas_duracion_valida" CHECK ((("duracion_min" IS NULL) OR (("duracion_min" >= 5) AND ("duracion_min" <= 480)))),
    CONSTRAINT "tareas_enlace_reunion_valido" CHECK (((("tipo" = 'reunion'::"text") AND (("enlace_reunion" IS NULL) OR (("length"("enlace_reunion") <= 1000) AND ("enlace_reunion" ~* '^https://[a-z0-9.-]+(:[0-9]{1,5})?([/?#][^[:space:]]*)?$'::"text")))) OR (("tipo" <> 'reunion'::"text") AND ("enlace_reunion" IS NULL)))),
    CONSTRAINT "tareas_estado_valido" CHECK (("estado" = ANY (ARRAY['pendiente'::"text", 'completada'::"text", 'cancelada'::"text", 'no_show'::"text", 'reprogramada'::"text"]))),
    CONSTRAINT "tareas_modalidad_reunion_valida" CHECK (((("tipo" = 'reunion'::"text") AND ("modalidad_reunion" = ANY (ARRAY['presencial'::"text", 'virtual'::"text", 'sin_clasificar'::"text"]))) OR (("tipo" <> 'reunion'::"text") AND ("modalidad_reunion" IS NULL)))),
    CONSTRAINT "tareas_motivo_no_realizada_valido" CHECK ((("motivo_no_realizada" IS NULL) OR ("motivo_no_realizada" = ANY (ARRAY['cliente_no_asistio'::"text", 'cancelada_cliente'::"text", 'cancelada_empresa'::"text", 'reprogramada'::"text", 'otro'::"text"])))),
    CONSTRAINT "tareas_nota_valida" CHECK ((("nota" IS NULL) OR ("length"("nota") <= 2000))),
    CONSTRAINT "tareas_reprogramaciones_validas" CHECK (("reprogramaciones" >= 0)),
    CONSTRAINT "tareas_resultado_reunion_valido" CHECK ((("resultado_reunion" IS NULL) OR ("resultado_reunion" = ANY (ARRAY['interesado'::"text", 'seguimiento'::"text", 'propuesta'::"text", 'inicia_registro'::"text", 'no_interesado'::"text", 'sin_clasificar'::"text"])))),
    CONSTRAINT "tareas_revision_postventa" CHECK (((("inversionista_id" IS NULL) AND ("postventa_revision" IS NULL)) OR (("inversionista_id" IS NOT NULL) AND ("postventa_revision" IS NOT NULL) AND ("postventa_revision" >= 1)))),
    CONSTRAINT "tareas_tipo_valido" CHECK (("tipo" = ANY (ARRAY['llamada'::"text", 'whatsapp'::"text", 'reunion'::"text", 'tarea'::"text"]))),
    CONSTRAINT "tareas_titulo_valido" CHECK ((("length"("btrim"("titulo")) >= 1) AND ("length"("btrim"("titulo")) <= 200))),
    CONSTRAINT "tareas_ubicacion_reunion_valida" CHECK (((("tipo" = 'reunion'::"text") AND (("ubicacion_reunion" IS NULL) OR (("length"("btrim"("ubicacion_reunion")) >= 1) AND ("length"("btrim"("ubicacion_reunion")) <= 300)))) OR (("tipo" <> 'reunion'::"text") AND ("ubicacion_reunion" IS NULL)))),
    CONSTRAINT "tareas_un_solo_sujeto" CHECK (("num_nonnulls"("lead_id", "perfil_id", "inversionista_id") = 1)),
    CONSTRAINT "tareas_vence_en_cuerda" CHECK ((("vence_en" >= '2026-01-01 00:00:00+00'::timestamp with time zone) AND ("vence_en" < '2100-01-01 00:00:00+00'::timestamp with time zone)))
);

COMMENT ON TABLE "crm"."tareas" IS 'Agenda comercial: acciones FUTURAS mutables (el pasado vive en crm.actividades, log inmutable). Vencida se deriva (pendiente + vence_en < now()); cierre por crm.cerrar_tarea().';

COMMENT ON COLUMN "crm"."tareas"."vendedor_id" IS 'Tenencia espejo del lead (mantenida por trigger): null = bandeja del supervisor (lead parkeado). En tareas de perfil (postventa) es el dueno directo.';

COMMENT ON COLUMN "crm"."tareas"."vence_en" IS 'Cuando toca la accion. Aviso, no deadline: vencida = pendiente AND vence_en < now(). La ventana legal peruana (L-S 07:00-20:00, Ley 29571) la aplica la UI al proponer fechas.';

COMMENT ON COLUMN "crm"."tareas"."reagendada_de" IS 'Tarea previa cerrada en no_show que esta reagenda. La metrica de no-shows cuenta filas en estado no_show.';

COMMENT ON COLUMN "crm"."tareas"."confirmada_en" IS 'Anti no-show: momento en que el cliente confirmo la cita respondiendo al recordatorio.';

COMMENT ON COLUMN "crm"."tareas"."cancelada_por" IS 'Autoría de la cancelación, sellada por los BEFORE triggers (el cliente nunca la escribe, ni en INSERT ni en UPDATE). asesor = una PERSONA con sesión la anuló por crm.cerrar_tarea() porque ya no hacía falta. sistema = la canceló private.trg_leads_sync_tareas al convertirse/descartarse/darse de baja el lead, o un proceso sin sesión (service_role, seeds, cron). Dice CÓMO entró la cancelación; QUIÉN la firmó vive desde 20260727 en cancelada_por_id. En el denominador de pct_completadas solo entran las de asesor firmadas por el PROPIO vendedor de la tarea: las del sistema y las que ordena un tercero (supervisor o gerencia) quedan fuera — decisión de Miguel, 2026-07-26.';

COMMENT ON COLUMN "crm"."tareas"."cancelada_por_id" IS 'QUIÉN firmó la anulación: el perfil con sesión que llamó a crm.cerrar_tarea(). Sellada por los BEFORE triggers (jamás llega del payload), null cuando cancelada_por = ''sistema'' porque ahí no hay persona a la que atribuir. Se compara contra vendedor_id para saber si la anulación fue PROPIA (pesa en el % de esa persona) o AJENA — el jefe anulándole la tarea a su vendedor — que NO pesa. Sin FK a public.perfiles a propósito: con on delete set null, dar de baja a un supervisor reescribiría hacia atrás el % de sus vendedores.';

COMMENT ON COLUMN "crm"."tareas"."modalidad_reunion" IS 'Modalidad de la reunion: presencial, virtual o sin_clasificar para historia anterior a 2026-08-05.';

COMMENT ON COLUMN "crm"."tareas"."resultado_reunion" IS 'Resultado comercial obligatorio al marcar una reunion realizada. El contrato/capital real se mide desde crm.leads y public.contratos, no desde esta declaracion.';

COMMENT ON COLUMN "crm"."tareas"."motivo_no_realizada" IS 'Motivo estructurado para no_show, cancelacion humana o reprogramacion.';

COMMENT ON COLUMN "crm"."tareas"."detalle_cierre_reunion" IS 'Contexto libre del cierre; no sustituye el estado ni los catalogos estructurados.';

COMMENT ON CONSTRAINT "tareas_destino_reunion_coherente" ON "crm"."tareas" IS 'Presencial exige ubicación; virtual permite enlace HTTPS opcional; otras tareas no admiten destino.';

CREATE TABLE IF NOT EXISTS "crm"."inversionista_datos_contacto" (
    "inversionista_id" "uuid" NOT NULL,
    "nombre_completo" "text" NOT NULL,
    "telefono" "text",
    "domicilio" "text",
    "revision" integer DEFAULT 1 NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "actualizado_por" "uuid" NOT NULL,
    CONSTRAINT "inversionista_datos_contacto_domicilio_check" CHECK ((("domicilio" IS NULL) OR ("length"("domicilio") <= 500))),
    CONSTRAINT "inversionista_datos_contacto_nombre_completo_check" CHECK ((("length"("btrim"("nombre_completo")) >= 2) AND ("length"("btrim"("nombre_completo")) <= 200))),
    CONSTRAINT "inversionista_datos_contacto_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "inversionista_datos_contacto_telefono_check" CHECK ((("telefono" IS NULL) OR (("length"("telefono") >= 6) AND ("length"("telefono") <= 32))))
);

CREATE TABLE IF NOT EXISTS "crm"."politica_gestion_diaria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version" integer NOT NULL,
    "version_anterior_id" "uuid",
    "vigente_desde" timestamp with time zone NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "creado_por" "uuid" DEFAULT "auth"."uid"(),
    "motivo" "text" NOT NULL,
    "cortes_activos" boolean DEFAULT false NOT NULL,
    "corte_1_hora" time without time zone DEFAULT '11:30:00'::time without time zone NOT NULL,
    "corte_1_minimo" integer DEFAULT 3 NOT NULL,
    "corte_2_hora" time without time zone DEFAULT '16:00:00'::time without time zone NOT NULL,
    "corte_2_incremento_pct" numeric DEFAULT 150 NOT NULL,
    "corte_2_piso" integer DEFAULT 8 NOT NULL,
    "corte_2_techo" integer DEFAULT 30 NOT NULL,
    "sabado_minimo" integer DEFAULT 3 NOT NULL,
    "bien_min_pct" numeric DEFAULT 45 NOT NULL,
    "atencion_min_pct" numeric DEFAULT 25 NOT NULL,
    "minimo_llamadas_utiles" integer DEFAULT 5 NOT NULL,
    "tasa_baja_diferencia_pp" numeric,
    CONSTRAINT "politica_gestion_diaria_bien_min_pct_check" CHECK ((("bien_min_pct" > (0)::numeric) AND ("bien_min_pct" <= (100)::numeric))),
    CONSTRAINT "politica_gestion_diaria_check" CHECK ((("corte_2_techo" >= "corte_2_piso") AND ("corte_2_techo" <= 500))),
    CONSTRAINT "politica_gestion_diaria_check1" CHECK ((("atencion_min_pct" >= (0)::numeric) AND ("atencion_min_pct" < "bien_min_pct"))),
    CONSTRAINT "politica_gestion_diaria_check2" CHECK ((("corte_1_hora" > '09:00:00'::time without time zone) AND ("corte_1_hora" < '13:00:00'::time without time zone) AND ("corte_2_hora" > "corte_1_hora") AND ("corte_2_hora" < '18:00:00'::time without time zone))),
    CONSTRAINT "politica_gestion_diaria_check3" CHECK (((("version" = 1) AND ("version_anterior_id" IS NULL) AND ("creado_por" IS NULL) AND ("vigente_desde" = '-infinity'::timestamp with time zone) AND (NOT "cortes_activos")) OR (("version" > 1) AND ("version_anterior_id" IS NOT NULL) AND ("creado_por" IS NOT NULL) AND "isfinite"("vigente_desde") AND ("vigente_desde" = (((("vigente_desde" AT TIME ZONE 'America/Lima'::"text"))::"date")::timestamp without time zone AT TIME ZONE 'America/Lima'::"text"))))),
    CONSTRAINT "politica_gestion_diaria_corte_1_minimo_check" CHECK ((("corte_1_minimo" >= 1) AND ("corte_1_minimo" <= 500))),
    CONSTRAINT "politica_gestion_diaria_corte_2_incremento_pct_check" CHECK ((("corte_2_incremento_pct" >= (0)::numeric) AND ("corte_2_incremento_pct" <= (1000)::numeric))),
    CONSTRAINT "politica_gestion_diaria_corte_2_piso_check" CHECK ((("corte_2_piso" >= 1) AND ("corte_2_piso" <= 500))),
    CONSTRAINT "politica_gestion_diaria_minimo_llamadas_utiles_check" CHECK ((("minimo_llamadas_utiles" >= 1) AND ("minimo_llamadas_utiles" <= 500))),
    CONSTRAINT "politica_gestion_diaria_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 3) AND ("length"("btrim"("motivo")) <= 500))),
    CONSTRAINT "politica_gestion_diaria_sabado_minimo_check" CHECK ((("sabado_minimo" >= 1) AND ("sabado_minimo" <= 500))),
    CONSTRAINT "politica_gestion_diaria_tasa_baja_diferencia_pp_check" CHECK ((("tasa_baja_diferencia_pp" >= (0)::numeric) AND ("tasa_baja_diferencia_pp" <= (100)::numeric))),
    CONSTRAINT "politica_gestion_diaria_version_check" CHECK (("version" > 0))
);

COMMENT ON TABLE "crm"."politica_gestion_diaria" IS 'F4: política inmutable al inicio del día Lima; v1 histórica OFF. Sin escritura API hasta etapa 5.';

CREATE TABLE IF NOT EXISTS "crm"."politica_rentabilidad" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version" integer NOT NULL,
    "version_anterior_id" "uuid",
    "vigente_desde" timestamp with time zone NOT NULL,
    "tasa_base_nueva" numeric NOT NULL,
    "regla_renovacion" "text" DEFAULT 'heredada'::"text" NOT NULL,
    "regla_upgrade" "text" DEFAULT 'heredada'::"text" NOT NULL,
    "tope_tecnico" numeric DEFAULT 50 NOT NULL,
    "vigencia_solicitud_dias" integer DEFAULT 7 NOT NULL,
    "modo" "text" DEFAULT 'observacion'::"text" NOT NULL,
    "nota" "text",
    "publicada_por" "uuid",
    "publicada_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "politica_rentabilidad_modo_check" CHECK (("modo" = ANY (ARRAY['observacion'::"text", 'enforcement'::"text"]))),
    CONSTRAINT "politica_rentabilidad_nota_check" CHECK ((("nota" IS NULL) OR (("length"("btrim"("nota")) >= 1) AND ("length"("btrim"("nota")) <= 500)))),
    CONSTRAINT "politica_rentabilidad_regla_renovacion_check" CHECK (("regla_renovacion" = 'heredada'::"text")),
    CONSTRAINT "politica_rentabilidad_regla_upgrade_check" CHECK (("regla_upgrade" = 'heredada'::"text")),
    CONSTRAINT "politica_rentabilidad_tasa_base_nueva_check" CHECK ((("tasa_base_nueva" > (0)::numeric) AND ("tasa_base_nueva" <= (50)::numeric))),
    CONSTRAINT "politica_rentabilidad_tope_sobre_base" CHECK (("tope_tecnico" >= "tasa_base_nueva")),
    CONSTRAINT "politica_rentabilidad_tope_tecnico_check" CHECK ((("tope_tecnico" > (0)::numeric) AND ("tope_tecnico" <= (50)::numeric))),
    CONSTRAINT "politica_rentabilidad_version_check" CHECK (("version" > 0)),
    CONSTRAINT "politica_rentabilidad_vigencia_solicitud_dias_check" CHECK ((("vigencia_solicitud_dias" >= 1) AND ("vigencia_solicitud_dias" <= 30)))
);

COMMENT ON TABLE "crm"."politica_rentabilidad" IS 'Rentabilidad R1. Política VERSIONADA e inmutable de la tasa anual: base para primera inversión, herencia en renovación/upgrade, tope técnico, vigencia de solicitudes y modo (observacion: no bloquea; enforcement: R4). Solo Gerencia publica (crm.publicar_politica_rentabilidad_fn). La lee UN solo núcleo: private.resolver_tasa.';

COMMENT ON COLUMN "crm"."politica_rentabilidad"."tasa_base_nueva" IS 'Tasa anual (%) de una PRIMERA inversión (D1: también para un cliente existente que abre inversión nueva).';

COMMENT ON COLUMN "crm"."politica_rentabilidad"."tope_tecnico" IS 'Defensa técnica del servidor (D5). El tope comercial lo fija Gerencia en cada solicitud.';

COMMENT ON COLUMN "crm"."politica_rentabilidad"."vigencia_solicitud_dias" IS 'Días que vive una solicitud/autorización sin consumirse (D6: 7).';

COMMENT ON COLUMN "crm"."politica_rentabilidad"."modo" IS 'observacion: se registra la divergencia sin bloquear (R2). enforcement: la puerta impone la tasa resuelta (R4). En R1 solo se admite observacion.';

CREATE TABLE IF NOT EXISTS "crm"."cierres_externos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid",
    "cooperativa" "text" NOT NULL,
    "monto" numeric(14,2) NOT NULL,
    "moneda" "text" NOT NULL,
    "documento_tipo" "text" NOT NULL,
    "documento" "text" NOT NULL,
    "nombre_completo" "text" NOT NULL,
    "numero_transaccion" "text" NOT NULL,
    "referencia_externa" "text",
    "vence_en" "date",
    "nota" "text",
    "vendedor_id" "uuid" NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "anulado_en" timestamp with time zone,
    "anulado_por" "uuid",
    "motivo_anulacion" "text",
    "inversionista_id" "uuid",
    "es_cierre_inicial" boolean DEFAULT true NOT NULL,
    "fecha_comercial" "date",
    "fecha_imputacion" "date",
    "comprobante_objeto_id" "uuid",
    "plazo_meses" integer,
    "tasa_anual" numeric,
    "base_plazo" "text" DEFAULT 'dias_360'::"text" NOT NULL,
    CONSTRAINT "cierres_coopac_base_plazo" CHECK (("base_plazo" = ANY (ARRAY['calendario'::"text", 'dias_360'::"text"]))),
    CONSTRAINT "cierres_coopac_condiciones_completas" CHECK (((("plazo_meses" IS NULL) AND ("tasa_anual" IS NULL)) OR (("plazo_meses" IS NOT NULL) AND ("tasa_anual" IS NOT NULL) AND ("base_plazo" = ANY (ARRAY['calendario'::"text", 'dias_360'::"text"])) AND (("plazo_meses" >= 1) AND ("plazo_meses" <= 1200)) AND ("tasa_anual" <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric])) AND ("tasa_anual" > (0)::numeric) AND ("tasa_anual" = "trunc"("tasa_anual", 2)) AND ("vence_en" IS NOT NULL) AND "isfinite"("vence_en") AND ("vence_en" =
CASE "base_plazo"
    WHEN 'calendario'::"text" THEN ((COALESCE("fecha_comercial", (("creado_en" AT TIME ZONE 'America/Lima'::"text"))::"date") + "make_interval"("months" => "plazo_meses")))::"date"
    WHEN 'dias_360'::"text" THEN (COALESCE("fecha_comercial", (("creado_en" AT TIME ZONE 'America/Lima'::"text"))::"date") + ("plazo_meses" * 30))
    ELSE NULL::"date"
END)))),
    CONSTRAINT "cierres_externos_anulacion_completa" CHECK (((("anulado_en" IS NULL) AND ("anulado_por" IS NULL) AND ("motivo_anulacion" IS NULL)) OR (("anulado_en" IS NOT NULL) AND ("anulado_por" IS NOT NULL) AND ("motivo_anulacion" IS NOT NULL) AND ("btrim"("motivo_anulacion") <> ''::"text") AND ("length"("btrim"("motivo_anulacion")) <= 300)))),
    CONSTRAINT "cierres_externos_cooperativa_check" CHECK (("cooperativa" = ANY (ARRAY['qorilazo'::"text", 'prodelco'::"text"]))),
    CONSTRAINT "cierres_externos_documento_formato" CHECK (
CASE "documento_tipo"
    WHEN 'DNI'::"text" THEN ("documento" ~ '^[0-9]{8}$'::"text")
    WHEN 'CE'::"text" THEN ("documento" ~ '^[0-9]{9,12}$'::"text")
    ELSE ("documento" ~ '^[A-Z0-9]{6,12}$'::"text")
END),
    CONSTRAINT "cierres_externos_documento_tipo_check" CHECK (("documento_tipo" = ANY (ARRAY['DNI'::"text", 'CE'::"text", 'PASAPORTE'::"text"]))),
    CONSTRAINT "cierres_externos_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "cierres_externos_monto_check" CHECK ((("monto" <> 'NaN'::numeric) AND ("monto" > (0)::numeric))),
    CONSTRAINT "cierres_externos_nombre_completo_check" CHECK (("btrim"("nombre_completo") <> ''::"text")),
    CONSTRAINT "cierres_externos_numero_transaccion_check" CHECK ((("btrim"("numero_transaccion") <> ''::"text") AND ("length"("btrim"("numero_transaccion")) <= 64))),
    CONSTRAINT "cierres_externos_referencia_externa_check" CHECK ((("referencia_externa" IS NULL) OR (("btrim"("referencia_externa") <> ''::"text") AND ("length"("btrim"("referencia_externa")) <= 64)))),
    CONSTRAINT "cierres_f4_datos_completos" CHECK (("es_cierre_inicial" OR (("inversionista_id" IS NOT NULL) AND ("fecha_comercial" IS NOT NULL) AND ("fecha_imputacion" IS NOT NULL) AND ("comprobante_objeto_id" IS NOT NULL) AND ("referencia_externa" IS NOT NULL)))),
    CONSTRAINT "cierres_f4_fechas_validas" CHECK (((("fecha_comercial" IS NULL) AND ("fecha_imputacion" IS NULL)) OR (("fecha_comercial" IS NOT NULL) AND ("fecha_imputacion" IS NOT NULL) AND "isfinite"("fecha_comercial") AND "isfinite"("fecha_imputacion") AND ("fecha_comercial" <= "fecha_imputacion") AND ("fecha_imputacion" <= (("creado_en" AT TIME ZONE 'America/Lima'::"text"))::"date")))),
    CONSTRAINT "cierres_iniciales_requieren_lead" CHECK (((NOT "es_cierre_inicial") OR ("lead_id" IS NOT NULL)))
);

COMMENT ON TABLE "crm"."cierres_externos" IS 'Cierres de inversion en cooperativas (COOPAC Qorilazo / COOPAC Prodelco). El inversionista NO existe en el portal (sin perfil, sin correo): vive como lead convertido + esta fila. RLS ON, cero policies y cero grants (deny-by-default absoluto); se escribe SOLO via crm.convertir_lead_externo / crm.corregir_cierre_externo y se lee SOLO via crm.cierres_externos_fn.';

COMMENT ON COLUMN "crm"."cierres_externos"."lead_id" IS 'Lead convertido que respalda este cierre. UNIQUE: un cierre externo por lead, en linea con el indice «una conversion por lead» del ledger.';

COMMENT ON COLUMN "crm"."cierres_externos"."cooperativa" IS 'Donde invirtio: qorilazo | prodelco. Es el distintivo que ve el vendedor en Mi cartera.';

COMMENT ON COLUMN "crm"."cierres_externos"."monto" IS 'Monto REAL invertido (no el estimado del lead). Es lo que suma a la cuota del mes via cumplimiento_metas_fn.';

COMMENT ON COLUMN "crm"."cierres_externos"."moneda" IS 'PEN o USD. Que monedas admite CADA cooperativa lo dice crm.empresas.monedas, no esta columna: Prodelco registra PEN y USD desde el 17/09/2026 y Qorilazo solo PEN. La lectura, el capital y la cuota agrupan por moneda; PEN y USD jamas se suman.';

COMMENT ON COLUMN "crm"."cierres_externos"."documento_tipo" IS 'DNI | CE | PASAPORTE — mismas reglas que public.perfiles.tipo_documento.';

COMMENT ON COLUMN "crm"."cierres_externos"."documento" IS 'Numero de documento, FOTO de lo que la cooperativa registro. No es espejo del lead: crm.leads.dni solo admite DNI de 8 digitos.';

COMMENT ON COLUMN "crm"."cierres_externos"."nombre_completo" IS 'Nombre al momento del cierre (foto, editable solo hasta confirmar).';

COMMENT ON COLUMN "crm"."cierres_externos"."numero_transaccion" IS 'Numero de operacion del deposito del inversionista. OBLIGATORIO y UNICO EN TODA LA TABLA (no por cooperativa: la cooperativa la elige el mismo vendedor, asi que no sirve de namespace): es la unica prueba de que se movio plata de verdad, y lo que impide cobrar dos veces un mismo cierre. Solo gerencia lo corrige.';

COMMENT ON COLUMN "crm"."cierres_externos"."referencia_externa" IS 'Numero/codigo del contrato o certificado que emitio la cooperativa. OPCIONAL, para papeleo: la prueba del cierre es numero_transaccion, no esto (un codigo de certificado no lo contrasta nadie).';

COMMENT ON COLUMN "crm"."cierres_externos"."vence_en" IS 'Vencimiento de la inversion en la coop. Opcional; insumo del futuro recordatorio de renovacion.';

COMMENT ON COLUMN "crm"."cierres_externos"."vendedor_id" IS 'FOTO de quien cobro el cierre (el vendedor asignado del lead al convertir). Reasignaciones posteriores no mueven la comision.';

COMMENT ON COLUMN "crm"."cierres_externos"."creado_en" IS 'Fecha del cierre. Automatica (now()), sin retro-datar: el mes de la cuota y de la conversion es el mes real del cierre.';

COMMENT ON COLUMN "crm"."cierres_externos"."anulado_en" IS 'Anulado por gerencia (fraude o error). Un cierre anulado NO cuenta ni en la cuota (cumplimiento_metas_fn) ni en la conversion mensual (private.conversion_mensual_por_vendedor), pero la fila SIGUE existiendo: el lead quedo convertido y esta fila es su ancla de legalidad (P4). Es de una sola direccion: no se des-anula.';

COMMENT ON COLUMN "crm"."cierres_externos"."motivo_anulacion" IS 'Por que se anulo, en palabras de gerencia. Obligatorio: un cierre deja de pagarle a una persona y esa persona merece una razon.';

COMMENT ON COLUMN "crm"."cierres_externos"."inversionista_id" IS 'F1 multiempresa: enlace cierre->persona (obligatorio al cierre en F3). El cierre deja de depender de lead.perfil_id para identificar a la persona.';

COMMENT ON COLUMN "crm"."cierres_externos"."es_cierre_inicial" IS 'Distingue la conversión inicial del lead de una inversión posterior. No determina elegibilidad de renovaciones/upgrades.';

COMMENT ON COLUMN "crm"."cierres_externos"."fecha_comercial" IS 'Fecha propia de la inversión F4. NULL conserva exactamente la fecha histórica de creado_en.';

COMMENT ON COLUMN "crm"."cierres_externos"."fecha_imputacion" IS 'Fecha usada por Capital. Igual a fecha_comercial en mes abierto; día de registro para un ajuste de mes ya sellado. creado_en conserva el instante de registro.';

COMMENT ON COLUMN "crm"."cierres_externos"."plazo_meses" IS 'Plazo pactado en meses enteros. NULL en registros anteriores sin condición documentada.';

COMMENT ON COLUMN "crm"."cierres_externos"."tasa_anual" IS 'Porcentaje anual pactado ingresado manualmente; 12 significa 12% anual. No es una tasa mensual ni una comisión.';

COMMENT ON COLUMN "crm"."cierres_externos"."base_plazo" IS 'Convención del plazo, fijada al registrar: calendario en históricos; dias_360 en nuevas inversiones (30 días por mes). Se conserva al corregir. No altera importes ni rentabilidad.';

COMMENT ON CONSTRAINT "cierres_coopac_condiciones_completas" ON "crm"."cierres_externos" IS 'Plazo, tasa y vencimiento coherentes según la convención persistida. Conserva fechas históricas y exige 30 días por mes en nuevas altas.';

CREATE TABLE IF NOT EXISTS "crm"."inversionistas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "estado" "text" DEFAULT 'activo'::"text" NOT NULL,
    "perfil_id" "uuid",
    "responsable_relacion_id" "uuid",
    "no_contactar" boolean DEFAULT false NOT NULL,
    "no_contactar_en" timestamp with time zone,
    "no_contactar_por" "uuid",
    "inversionista_canonico_id" "uuid",
    "fusionado_en" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "inversionistas_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "inversionistas_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversionistas_estado_check" CHECK (("estado" = ANY (ARRAY['activo'::"text", 'fusionado'::"text", 'bloqueado'::"text"]))),
    CONSTRAINT "inversionistas_fusion_coherente" CHECK ((("estado" = 'fusionado'::"text") = (("inversionista_canonico_id" IS NOT NULL) AND ("fusionado_en" IS NOT NULL)))),
    CONSTRAINT "inversionistas_fusionado_en_check" CHECK ((("fusionado_en" IS NULL) OR "isfinite"("fusionado_en"))),
    CONSTRAINT "inversionistas_no_autofusion" CHECK (("inversionista_canonico_id" IS DISTINCT FROM "id")),
    CONSTRAINT "inversionistas_no_contactar_en_check" CHECK ((("no_contactar_en" IS NULL) OR "isfinite"("no_contactar_en"))),
    CONSTRAINT "inversionistas_nocontactar_auditado" CHECK ((("no_contactar" = false) OR ("no_contactar_en" IS NOT NULL)))
);

COMMENT ON TABLE "crm"."inversionistas" IS 'F1 multiempresa: ancla estable de la persona (una fila por persona confirmada). NO duplica nombre/telefono/correo (el contacto se proyecta desde fuentes vigentes en la Ficha 360). perfil_id enlaza opcional y unicamente al Portal Avance SIN tocar public. Fusion append-only: la perdedora apunta a canonica y se marca fusionado, jamas se borra. RLS activa, sin grants a la Data API: acceso solo por RPC definer (F3+).';

CREATE TABLE IF NOT EXISTS "crm"."lead_potencial" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "nivel" "crm"."nivel_potencial" NOT NULL,
    "origen" "text" NOT NULL,
    "marcado_por" "uuid" NOT NULL,
    "marcado_en" timestamp with time zone NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lead_potencial_fechas_finitas" CHECK (("isfinite"("marcado_en") AND "isfinite"("creado_en") AND "isfinite"("actualizado_en"))),
    CONSTRAINT "lead_potencial_origen_check" CHECK (("origen" = ANY (ARRAY['manual'::"text", 'caducidad'::"text"])))
);

COMMENT ON TABLE "crm"."lead_potencial" IS 'Nivel VIGENTE de potencial de cada lead (una fila por lead). Solo se escribe por crm.marcar_potencial_lead_fn (y, desde la fase 2, por la caducidad diaria). Tabla propia para no disparar los ~20 disparadores de crm.leads ni reordenar la cartera. Sin grants para la API: se lee por puertas.';

COMMENT ON COLUMN "crm"."lead_potencial"."id" IS 'Identificador de la fila.';

COMMENT ON COLUMN "crm"."lead_potencial"."lead_id" IS 'Lead marcado. Único: la marca es del lead y viaja con él si se reasigna.';

COMMENT ON COLUMN "crm"."lead_potencial"."nivel" IS 'Nivel vigente: frio, tibio o estrella.';

COMMENT ON COLUMN "crm"."lead_potencial"."origen" IS 'Quién fijó el nivel vigente: manual (analista o supervisor) o caducidad (bajada automática por días sin gestión, fase 2).';

COMMENT ON COLUMN "crm"."lead_potencial"."marcado_por" IS 'Perfil de la última persona que marcó el lead (no cambia con la caducidad).';

COMMENT ON COLUMN "crm"."lead_potencial"."marcado_en" IS 'Última marca humana. Junto con la última gestión arranca el reloj de la caducidad.';

COMMENT ON COLUMN "crm"."lead_potencial"."creado_en" IS 'Primera marca del lead.';

COMMENT ON COLUMN "crm"."lead_potencial"."actualizado_en" IS 'Último cambio de la fila (marca o caducidad).';

CREATE TABLE IF NOT EXISTS "crm"."alertas_reconocimientos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "perfil_id" "uuid" NOT NULL,
    "alerta_id" "text" NOT NULL,
    "accion" "text" NOT NULL,
    "miembros" "text"[] NOT NULL,
    "severidad" "text" NOT NULL,
    "hasta" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "secuencia" bigint NOT NULL,
    "solicitud_corte_id" "uuid",
    CONSTRAINT "alertas_reconocimientos_accion_check" CHECK (("accion" = ANY (ARRAY['reconocer'::"text", 'posponer'::"text"]))),
    CONSTRAINT "alertas_reconocimientos_alerta_id_check" CHECK (((("alerta_id" COLLATE "C") ~ '^grupo:(por_repartir|tarea_vencida|lead_sin_responder|sin_proxima_accion):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'::"text") OR (("alerta_id" COLLATE "C") ~ '^grupo:corte_(manana|tarde):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9]{4}-[0-9]{2}-[0-9]{2}$'::"text"))),
    CONSTRAINT "alertas_reconocimientos_check" CHECK (((("accion" = 'posponer'::"text") = ("hasta" IS NOT NULL)) AND (("hasta" IS NULL) OR "isfinite"("hasta")))),
    CONSTRAINT "alertas_reconocimientos_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "alertas_reconocimientos_miembros_check" CHECK (((("cardinality"("miembros") >= 1) AND ("cardinality"("miembros") <= 2000)) AND ("array_ndims"("miembros") = 1))),
    CONSTRAINT "alertas_reconocimientos_severidad_check" CHECK (("severidad" = ANY (ARRAY['critica'::"text", 'atencion'::"text"])))
);

COMMENT ON TABLE "crm"."alertas_reconocimientos" IS 'F4 «Hoy del supervisor, sin ruido»: libro INMUTABLE (solo INSERT) de reconocimientos de las alertas agrupadas de la campana del supervisor. Reconocer atenúa (no borra) y descuenta del badge; posponer oculta hasta una fecha (tope 7 días); AMBOS ceden si el grupo EMPEORA — el front compara los miembros actuales contra la foto guardada aquí y un miembro nuevo o una severidad mayor reviven la alerta. El último asiento por alerta_id manda (por `secuencia`, el orden total del libro — creado_en puede empatar al microsegundo). Owner-only para escribir (solo el supervisor dueño del id); gerencia LEE todo (decisión de Miguel 2026-08-23: el reconocimiento es un compromiso con trazabilidad, no un botón de silencio). Traza viva 90 días (pg_cron crm-alertas-reconocimientos-caducidad); el rastro permanente queda en public.audit_log. CANDADO ACOTADO (Codex F4.1 #1): el servidor valida FORMA de la foto y de la severidad, no su VERDAD (esa vive en el front que deriva los grupos). Por eso NINGÚN reconocimiento vige más de 7 DÍAS: el front lo caduca por creado_en —que sella el servidor y el cliente no puede fechar—, mismo tope que posponer. Una foto inflada tampoco frena el revive por miembros (los ids reales futuros son aleatorios: no están en ninguna foto inventada); declarar severidad en falso solo compra, como máximo, esos 7 días, a la vista de gerencia. La regla de vigencia es CONTRATO de F4.2.';

COMMENT ON COLUMN "crm"."alertas_reconocimientos"."alerta_id" IS 'Id del grupo de lib/alertas.ts (grupo:<tipo>:<uuid supervisor>). El trigger exige que el uuid final sea el del actor: nadie reconoce alertas ajenas.';

COMMENT ON COLUMN "crm"."alertas_reconocimientos"."miembros" IS 'Foto de ids (leads/vendedores) del grupo al reconocer — sin nombres. Base del «reaparece si empeora».';

COMMENT ON COLUMN "crm"."alertas_reconocimientos"."hasta" IS 'Solo posponer: hasta cuándo se oculta. Futura y con tope de 7 días (trigger, reloj de pared); finita por CHECK.';

CREATE TABLE IF NOT EXISTS "crm"."actividad_ciclo_contexto" (
    "actividad_id" "uuid" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "ciclo_n" integer,
    "estado_ciclo" "text" NOT NULL,
    "registrado_en" timestamp with time zone NOT NULL,
    "gesto_oficina_id" "uuid",
    "oficina_tarea_id" "uuid",
    CONSTRAINT "actividad_ciclo_contexto_check" CHECK ((("gesto_oficina_id" IS NULL) = ("oficina_tarea_id" IS NULL))),
    CONSTRAINT "actividad_ciclo_contexto_check1" CHECK (((("estado_ciclo" = 'ciclo'::"text") AND ("ciclo_n" IS NOT NULL)) OR (("estado_ciclo" = ANY (ARRAY['base_sin_ciclo'::"text", 'sin_ciclo'::"text"])) AND ("ciclo_n" IS NULL)))),
    CONSTRAINT "actividad_ciclo_contexto_ciclo_n_check" CHECK (("ciclo_n" > 0)),
    CONSTRAINT "actividad_ciclo_contexto_estado_ciclo_check" CHECK (("estado_ciclo" = ANY (ARRAY['ciclo'::"text", 'base_sin_ciclo'::"text", 'sin_ciclo'::"text"]))),
    CONSTRAINT "actividad_ciclo_contexto_registrado_en_check" CHECK ("isfinite"("registrado_en"))
);

COMMENT ON TABLE "crm"."actividad_ciclo_contexto" IS 'Clave causal inmutable 1:1 de actividades. El hecho sigue en actividades; no se aceptan ciclos, horas ni marcas de oficina desde metadata del cliente.';

CREATE TABLE IF NOT EXISTS "crm"."actividades" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "detalle" "text",
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "actividades_creado_en_finito" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "actividades_intento_base_forma" CHECK (((COALESCE(("metadata" ->> 'evento'::"text"), ''::"text") <> 'intento_base'::"text") OR ((COALESCE(("metadata" ->> 'resultado'::"text"), ''::"text") = ANY (ARRAY['no_contesto'::"text", 'volver_a_llamar'::"text", 'agendo_reunion'::"text", 'no_interesado'::"text", 'numero_errado'::"text", 'no_es_la_persona'::"text", 'pide_otro_producto'::"text"])) AND (COALESCE(("metadata" ->> 'intento_n'::"text"), ''::"text") ~ '^[1-9][0-9]{0,5}$'::"text") AND (COALESCE(("metadata" ->> 'ciclo_n'::"text"), ''::"text") ~ '^[1-9][0-9]{0,5}$'::"text") AND ((("metadata" ->> 'submotivo'::"text") IS NULL) OR (("metadata" ->> 'submotivo'::"text") = ANY (ARRAY['sin_fondos_ahora'::"text", 'ya_invirtio_con_otro'::"text", 'desconfianza'::"text", 'no_le_interesa_invertir'::"text", 'prestamo'::"text", 'credito'::"text", 'otro'::"text"]))) AND ((COALESCE(("metadata" ->> 'resultado'::"text"), ''::"text") <> 'volver_a_llamar'::"text") OR (COALESCE(("metadata" ->> 'proxima_llamada_en'::"text"), ''::"text") ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2}(\.[0-9]+)?)?([+-][0-9]{2}:?[0-9]{2}|Z)$'::"text"))))),
    CONSTRAINT "actividades_resultado_llamada_forma" CHECK (((COALESCE(("metadata" ->> 'evento'::"text"), ''::"text") <> 'resultado_llamada'::"text") OR ((("metadata" ->> 'resultado'::"text") = ANY (ARRAY['no_contesto'::"text", 'volver_a_llamar'::"text", 'agendo_reunion'::"text", 'no_interesado'::"text", 'numero_errado'::"text", 'no_es_la_persona'::"text", 'pide_otro_producto'::"text"])) AND ((("metadata" ->> 'submotivo'::"text") IS NULL) OR (("metadata" ->> 'submotivo'::"text") = ANY (ARRAY['sin_fondos_ahora'::"text", 'ya_invirtio_con_otro'::"text", 'desconfianza'::"text", 'no_le_interesa_invertir'::"text", 'prestamo'::"text", 'credito'::"text", 'otro'::"text"])))))),
    CONSTRAINT "actividades_tipo_check" CHECK (("tipo" = ANY (ARRAY['llamada_realizada'::"text", 'llamada_no_contestada'::"text", 'whatsapp_enviado'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text", 'nota'::"text", 'cambio_etapa'::"text", 'reasignacion'::"text", 'conversion'::"text"])))
);

COMMENT ON TABLE "crm"."actividades" IS 'Log inmutable de auditoría comercial: sin UPDATE ni DELETE para clientes API.';

COMMENT ON CONSTRAINT "actividades_creado_en_finito" ON "crm"."actividades" IS 'Anti-veneno infinity (hermano del anti-NaN de dinero): creado_en entra en max() de payloads de verificación y un infinito rompía el contrato del front. Auditoría F2-front 2026-08-17.';

COMMENT ON CONSTRAINT "actividades_intento_base_forma" ON "crm"."actividades" IS 'Base para gestión (B1/B1b): toda actividad con evento=intento_base trae resultado del MISMO catálogo cerrado de 7 valores de Gestión Diaria, intento_n y ciclo_n enteros >= 1, submotivo del catálogo si viene, y proxima_llamada_en (ISO-8601 con zona) cuando el resultado es volver_a_llamar. De forma, no de presencia: el núcleo construye la clave con to_jsonb(timestamptz) (nunca ::text) y castea a timestamptz antes de escribir crm.leads.proxima_llamada_en; la agenda se lee de crm.leads, no de la metadata.';

COMMENT ON CONSTRAINT "actividades_resultado_llamada_forma" ON "crm"."actividades" IS 'Gestión Diaria F2: toda actividad con evento=resultado_llamada trae un resultado del catálogo cerrado (7) y, si hay submotivo, uno de los 7. De forma, no de presencia; acotado al evento propio para no vetar metadata ajena.';

CREATE TABLE IF NOT EXISTS "crm"."actividades_cliente" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "vendedor_id" "uuid",
    "tarea_id" "uuid",
    "tipo" "text" NOT NULL,
    "detalle" "text",
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "actividades_cliente_detalle_check" CHECK ((("detalle" IS NULL) OR ("length"("detalle") <= 2000))),
    CONSTRAINT "actividades_cliente_responsable_check" CHECK ((("vendedor_id" IS NOT NULL) OR ("tipo" = 'reasignacion'::"text"))),
    CONSTRAINT "actividades_cliente_tipo_check" CHECK (("tipo" = ANY (ARRAY['llamada_realizada'::"text", 'llamada_no_contestada'::"text", 'whatsapp_enviado'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text", 'nota'::"text", 'reasignacion'::"text"])))
);

COMMENT ON TABLE "crm"."actividades_cliente" IS 'Timeline comercial postventa de clientes. Separado de crm.actividades porque esa tabla pertenece al SLA y etapa de leads.';

COMMENT ON COLUMN "crm"."actividades_cliente"."vendedor_id" IS 'Identificador técnico legado del responsable del hecho. Solo una reasignación puede carecer de responsable.';

CREATE TABLE IF NOT EXISTS "crm"."agenda_ics" (
    "perfil_id" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "rotado_en" timestamp with time zone
);

COMMENT ON TABLE "crm"."agenda_ics" IS 'Token secreto por miembro para la suscripción ICS de su agenda (edge crm-agenda-ics). Rotable; sin fila no hay feed.';

COMMENT ON COLUMN "crm"."agenda_ics"."token" IS 'Secreto del feed. Rotarlo (UPDATE) invalida el enlace anterior de inmediato.';

CREATE TABLE IF NOT EXISTS "crm"."ajustes_mes_cerrado" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "vendedor_id" "uuid" NOT NULL,
    "periodo_origen" "date" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "numerador" numeric NOT NULL,
    "capital_pen" numeric DEFAULT 0 NOT NULL,
    "capital_usd" numeric DEFAULT 0 NOT NULL,
    "detalle" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "pendiente_numerador" numeric NOT NULL,
    "pendiente_pen" numeric DEFAULT 0 NOT NULL,
    "pendiente_usd" numeric DEFAULT 0 NOT NULL,
    "pendiente_detalle" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "saldado_en" timestamp with time zone,
    CONSTRAINT "ajustes_mes_cerrado_capital_pen_check" CHECK (("capital_pen" >= (0)::numeric)),
    CONSTRAINT "ajustes_mes_cerrado_capital_pen_finito" CHECK ((("capital_pen" <> 'NaN'::numeric) AND ("capital_pen" <> 'Infinity'::numeric) AND ("capital_pen" <> '-Infinity'::numeric))),
    CONSTRAINT "ajustes_mes_cerrado_capital_usd_check" CHECK (("capital_usd" >= (0)::numeric)),
    CONSTRAINT "ajustes_mes_cerrado_capital_usd_finito" CHECK ((("capital_usd" <> 'NaN'::numeric) AND ("capital_usd" <> 'Infinity'::numeric) AND ("capital_usd" <> '-Infinity'::numeric))),
    CONSTRAINT "ajustes_mes_cerrado_motivo_check" CHECK ((("motivo" IS NOT NULL) AND ("btrim"("motivo") <> ''::"text") AND ("length"("btrim"("motivo")) <= 300))),
    CONSTRAINT "ajustes_mes_cerrado_numerador_check" CHECK (("numerador" > (0)::numeric)),
    CONSTRAINT "ajustes_mes_cerrado_numerador_finito" CHECK ((("numerador" <> 'NaN'::numeric) AND ("numerador" <> 'Infinity'::numeric) AND ("numerador" <> '-Infinity'::numeric))),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_check" CHECK ((("pendiente_numerador" <= "numerador") AND ("pendiente_pen" <= "capital_pen") AND ("pendiente_usd" <= "capital_usd"))),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_numerador_check" CHECK (("pendiente_numerador" >= (0)::numeric)),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_numerador_finito" CHECK ((("pendiente_numerador" <> 'NaN'::numeric) AND ("pendiente_numerador" <> 'Infinity'::numeric) AND ("pendiente_numerador" <> '-Infinity'::numeric))),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_pen_check" CHECK (("pendiente_pen" >= (0)::numeric)),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_pen_finito" CHECK ((("pendiente_pen" <> 'NaN'::numeric) AND ("pendiente_pen" <> 'Infinity'::numeric) AND ("pendiente_pen" <> '-Infinity'::numeric))),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_usd_check" CHECK (("pendiente_usd" >= (0)::numeric)),
    CONSTRAINT "ajustes_mes_cerrado_pendiente_usd_finito" CHECK ((("pendiente_usd" <> 'NaN'::numeric) AND ("pendiente_usd" <> 'Infinity'::numeric) AND ("pendiente_usd" <> '-Infinity'::numeric))),
    CONSTRAINT "ajustes_mes_cerrado_periodo_mes_check" CHECK (("periodo_origen" = ("date_trunc"('month'::"text", ("periodo_origen")::timestamp with time zone))::"date")),
    CONSTRAINT "ajustes_mes_cerrado_saldado_check" CHECK ((("saldado_en" IS NULL) OR (("pendiente_numerador" = (0)::numeric) AND ("pendiente_pen" = (0)::numeric) AND ("pendiente_usd" = (0)::numeric))))
);

COMMENT ON TABLE "crm"."ajustes_mes_cerrado" IS 'Deudas que nacen al anular un cierre de un mes YA CERRADO. El mes pagado no se reescribe: el descuento se aplica al mes vivo y lo que no cabe se arrastra hasta saldarse. PEN y USD se saldan por separado.';

COMMENT ON COLUMN "crm"."ajustes_mes_cerrado"."numerador" IS 'Lo que ese cierre valia en la conversion: 1 si no era referido, el peso del mes si lo era. Sellado al anular porque el peso puede cambiar despues.';

COMMENT ON COLUMN "crm"."ajustes_mes_cerrado"."pendiente_numerador" IS 'Lo que queda por descontar. Solo lo mueve crm.cerrar_periodo al saldar.';

ALTER TABLE "crm"."alertas_reconocimientos" ALTER COLUMN "secuencia" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "crm"."alertas_reconocimientos_secuencia_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE OR REPLACE VIEW "crm"."alertas_reconocimientos_vigentes" WITH ("security_invoker"='true') AS
 SELECT "id",
    "alerta_id",
    "accion",
    "miembros",
    "severidad",
    "hasta",
    "creado_en",
    "secuencia"
   FROM ( SELECT DISTINCT ON ("alertas_reconocimientos"."alerta_id") "alertas_reconocimientos"."id",
            "alertas_reconocimientos"."alerta_id",
            "alertas_reconocimientos"."accion",
            "alertas_reconocimientos"."miembros",
            "alertas_reconocimientos"."severidad",
            "alertas_reconocimientos"."hasta",
            "alertas_reconocimientos"."creado_en",
            "alertas_reconocimientos"."secuencia"
           FROM "crm"."alertas_reconocimientos"
          WHERE ("alertas_reconocimientos"."creado_en" > ("now"() - "make_interval"("days" => 7)))
          ORDER BY "alertas_reconocimientos"."alerta_id", "alertas_reconocimientos"."secuencia" DESC) "ultimo"
  WHERE (("hasta" IS NULL) OR ("hasta" > "now"()));

COMMENT ON VIEW "crm"."alertas_reconocimientos_vigentes" IS 'F4.2/F4.4 «Hoy del supervisor, sin ruido»: el asiento que AÚN gobierna cada alerta — se elige PRIMERO el último por alerta_id (secuencia desc, dentro de la ventana de 7 días del candado acotado de F4.1) y DESPUÉS se evalúa su vigencia (hasta > now() en posposiciones). Así un posponer VENCIDO, siendo el último, bloquea a los asientos anteriores en vez de dejarlos resucitar (bloqueante Codex F4.4 B1): la alerta queda sin gobierno y suena entera. A lo sumo UNA fila por alerta_id. El corte lo hace el reloj de POSTGRES (el front no puede alargar un silencio con un reloj atrasado — Codex F4.2 #2). security_invoker: misma RLS que la tabla (dueño supervisor; gerencia lee todo). La comparación de «reaparece si empeora» sigue en el front: necesita el estado ACTUAL de los grupos, que el servidor no conoce. ⚠️ REGLA (auditor RLS #2): todo CREATE OR REPLACE de esta vista DEBE repetir WITH (security_invoker = true) — en PG17 el replace SUSTITUYE las reloptions y un replace sin WITH la vuelve definer EN SILENCIO, exponiendo el libro completo a cualquier authenticated. Sonda post-cambio: pg_class.reloptions debe contener security_invoker=true.';

CREATE TABLE IF NOT EXISTS "crm"."backfill_multiempresa_mapa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fuente" "text" NOT NULL,
    "fila_id" "uuid" NOT NULL,
    "inversionista_id" "uuid",
    "clase" "text" NOT NULL,
    "regla" "text" NOT NULL,
    "confianza" "text" DEFAULT 'alta'::"text" NOT NULL,
    "revisor" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "backfill_multiempresa_mapa_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "backfill_multiempresa_mapa_clase_check" CHECK (("clase" = ANY (ARRAY['A'::"text", 'B'::"text", 'C'::"text", 'D'::"text", 'E'::"text", 'F'::"text"]))),
    CONSTRAINT "backfill_multiempresa_mapa_confianza_check" CHECK (("confianza" = ANY (ARRAY['alta'::"text", 'media'::"text", 'revision'::"text"]))),
    CONSTRAINT "backfill_multiempresa_mapa_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "backfill_multiempresa_mapa_fuente_check" CHECK (("fuente" = ANY (ARRAY['perfil'::"text", 'cierre'::"text", 'lead'::"text"])))
);

COMMENT ON TABLE "crm"."backfill_multiempresa_mapa" IS 'F2 multiempresa: mapa auditable del backfill. Una fila por origen (perfil/cierre/lead) con la identidad asignada, la clase (A-F), la regla y la confianza. Fuente de la reversa y de la revision de las clases E. Sin grants a la Data API.';

CREATE TABLE IF NOT EXISTS "crm"."base_carga_leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "base_id" "uuid" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "procedencia" "text" NOT NULL,
    "analista_id" "uuid",
    "asignado_en" timestamp with time zone,
    "asignado_por" "uuid",
    "agregado_por" "uuid" NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "base_carga_leads_asignacion_coherente" CHECK (((("analista_id" IS NULL) = ("asignado_en" IS NULL)) AND (("analista_id" IS NULL) = ("asignado_por" IS NULL)))),
    CONSTRAINT "base_carga_leads_fechas_finitas" CHECK (("isfinite"("creado_en") AND "isfinite"("actualizado_en") AND (("asignado_en" IS NULL) OR "isfinite"("asignado_en")))),
    CONSTRAINT "base_carga_leads_procedencia_check" CHECK (("procedencia" = ANY (ARRAY['archivo'::"text", 'crm'::"text"])))
);

COMMENT ON TABLE "crm"."base_carga_leads" IS 'Bases cargadas (B7): qué lead está en qué base y a quién se repartió. Un lead una sola vez por base y en UNA sola base viva a la vez (índice único parcial sobre lead_id con activo). Sin grants para la API; sin DELETE (soft-delete con activo).';

COMMENT ON COLUMN "crm"."base_carga_leads"."id" IS 'Identificador de la fila.';

COMMENT ON COLUMN "crm"."base_carga_leads"."base_id" IS 'Base a la que pertenece el lead.';

COMMENT ON COLUMN "crm"."base_carga_leads"."lead_id" IS 'Lead de la base. Solo puede estar en una base viva a la vez.';

COMMENT ON COLUMN "crm"."base_carga_leads"."procedencia" IS 'Cómo entró a la base: archivo (contacto nuevo creado desde el archivo, origen base_cargada) o crm (lead que ya existía, armado desde el CRM).';

COMMENT ON COLUMN "crm"."base_carga_leads"."analista_id" IS 'Analista al que se repartió; NULL = sin repartir. Va junto con asignado_en y asignado_por (los tres NULL o los tres con valor).';

COMMENT ON COLUMN "crm"."base_carga_leads"."asignado_en" IS 'Cuándo se repartió al analista; NULL = sin repartir.';

COMMENT ON COLUMN "crm"."base_carga_leads"."asignado_por" IS 'Quién repartió (supervisor o Gerencia); NULL = sin repartir.';

COMMENT ON COLUMN "crm"."base_carga_leads"."agregado_por" IS 'Perfil que agregó el lead a la base (quien cargó o armó).';

COMMENT ON COLUMN "crm"."base_carga_leads"."activo" IS 'Soft-delete: false = el lead salió de la base (y puede entrar a otra).';

COMMENT ON COLUMN "crm"."base_carga_leads"."creado_en" IS 'Cuándo entró el lead a la base.';

COMMENT ON COLUMN "crm"."base_carga_leads"."actualizado_en" IS 'Último cambio de la fila (reparto, recogida, retiro).';

CREATE TABLE IF NOT EXISTS "crm"."base_carga_operaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor" "uuid" NOT NULL,
    "operacion_id" "uuid" NOT NULL,
    "base_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "pedido_md5" "text" NOT NULL,
    "respuesta" "jsonb" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "base_carga_operaciones_creado_en_finito" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "base_carga_operaciones_pedido_md5_valido" CHECK (("pedido_md5" ~ '^[0-9a-f]{32}$'::"text")),
    CONSTRAINT "base_carga_operaciones_respuesta_valida" CHECK ((("jsonb_typeof"("respuesta") = 'object'::"text") AND ("octet_length"(("respuesta")::"text") <= 65536))),
    CONSTRAINT "base_carga_operaciones_tipo_check" CHECK (("tipo" = ANY (ARRAY['crear'::"text", 'cargar_lote'::"text", 'armar'::"text", 'repartir'::"text", 'recoger'::"text"])))
);

COMMENT ON TABLE "crm"."base_carga_operaciones" IS 'Bases cargadas (B7): recibos INMUTABLES de cada operación de las puertas (crear, cargar_lote, armar, repartir, recoger), para la idempotencia (único por actor e id de operación) y el rastro (el cambio de analista de un descartado no escribe en lead_asignaciones). Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. Sin grants para la API.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."id" IS 'Identificador del recibo.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."actor" IS 'Perfil que hizo la operación.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."operacion_id" IS 'Id de operación que manda la pantalla; con el actor, único: repetirlo devuelve el mismo recibo.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."base_id" IS 'Base sobre la que se operó.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."tipo" IS 'Operación: crear, cargar_lote, armar, repartir o recoger.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."pedido_md5" IS 'md5 (32 hexadecimales en minúscula) del pedido normalizado: el mismo id con otro pedido se rechaza.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."respuesta" IS 'Respuesta devuelta (objeto JSON de hasta 64 KB) SIN datos personales: conteos, ids y motivos; nunca nombres, teléfonos ni DNI.';

COMMENT ON COLUMN "crm"."base_carga_operaciones"."creado_en" IS 'Momento de la operación.';

CREATE TABLE IF NOT EXISTS "crm"."bases_carga" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre" "text" NOT NULL,
    "origen" "text" NOT NULL,
    "supervisor_id" "uuid" NOT NULL,
    "creada_por" "uuid" NOT NULL,
    "operacion_id" "uuid" NOT NULL,
    "archivo_nombre" "text",
    "filas_recibidas" integer DEFAULT 0 NOT NULL,
    "cargadas" integer DEFAULT 0 NOT NULL,
    "ya_existian" integer DEFAULT 0 NOT NULL,
    "no_contactar" integer DEFAULT 0 NOT NULL,
    "invalidas" integer DEFAULT 0 NOT NULL,
    "repetidas" integer DEFAULT 0 NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "bases_carga_archivo_coherente" CHECK ((("origen" = 'archivo'::"text") = ("archivo_nombre" IS NOT NULL))),
    CONSTRAINT "bases_carga_archivo_nombre_valido" CHECK ((("archivo_nombre" IS NULL) OR (("char_length"("archivo_nombre") >= 1) AND ("char_length"("archivo_nombre") <= 255)))),
    CONSTRAINT "bases_carga_fechas_finitas" CHECK (("isfinite"("creado_en") AND "isfinite"("actualizado_en"))),
    CONSTRAINT "bases_carga_nombre_valido" CHECK ((("nombre" = "btrim"("nombre")) AND (("char_length"("nombre") >= 1) AND ("char_length"("nombre") <= 80)))),
    CONSTRAINT "bases_carga_origen_check" CHECK (("origen" = ANY (ARRAY['archivo'::"text", 'crm'::"text"]))),
    CONSTRAINT "bases_carga_totales_cuadran" CHECK ((((((("cargadas")::bigint + ("ya_existian")::bigint) + ("no_contactar")::bigint) + ("invalidas")::bigint) + ("repetidas")::bigint) <= ("filas_recibidas")::bigint)),
    CONSTRAINT "bases_carga_totales_no_negativos" CHECK ((("filas_recibidas" >= 0) AND ("cargadas" >= 0) AND ("ya_existian" >= 0) AND ("no_contactar" >= 0) AND ("invalidas" >= 0) AND ("repetidas" >= 0)))
);

COMMENT ON TABLE "crm"."bases_carga" IS 'Bases cargadas (B7, 04/10/2026): una base antigua que un supervisor carga desde un archivo o arma con leads del CRM, para repartirla a sus analistas y seguir si se trabaja. Sin grants para la API: solo las puertas DEFINER de B8–B10 la escriben y la leen. Sin DELETE (soft-delete con activo).';

COMMENT ON COLUMN "crm"."bases_carga"."id" IS 'Identificador de la base.';

COMMENT ON COLUMN "crm"."bases_carga"."nombre" IS 'Nombre visible de la base (p. ej. «Feria 2025»): 1 a 80 caracteres, sin espacios al borde; único por supervisor entre las bases vivas, sin distinguir mayúsculas.';

COMMENT ON COLUMN "crm"."bases_carga"."origen" IS 'De dónde salió: archivo (Excel/CSV subido) o crm (armada con descartados elegibles del CRM, E12).';

COMMENT ON COLUMN "crm"."bases_carga"."supervisor_id" IS 'Supervisor dueño de la base: sus contactos quedan en su bandeja y él la reparte a su equipo (E4). Si la carga Gerencia, elige este supervisor (E11).';

COMMENT ON COLUMN "crm"."bases_carga"."creada_por" IS 'Perfil que creó la base (el supervisor o alguien de Gerencia).';

COMMENT ON COLUMN "crm"."bases_carga"."operacion_id" IS 'Id de la operación que creó la base (idempotencia: un doble clic no crea dos). Único.';

COMMENT ON COLUMN "crm"."bases_carga"."archivo_nombre" IS 'Nombre del archivo subido (1 a 255 caracteres); obligatorio con origen archivo y vacío con origen crm.';

COMMENT ON COLUMN "crm"."bases_carga"."filas_recibidas" IS 'Informe: filas recibidas del archivo (o candidatos evaluados al armar). Entero ≥ 0.';

COMMENT ON COLUMN "crm"."bases_carga"."cargadas" IS 'Informe: filas que quedaron como lead de la base. Entero ≥ 0.';

COMMENT ON COLUMN "crm"."bases_carga"."ya_existian" IS 'Informe: filas saltadas porque el contacto ya existía (mismo teléfono o DNI: de otro analista o ya cliente, E2). Entero ≥ 0.';

COMMENT ON COLUMN "crm"."bases_carga"."no_contactar" IS 'Informe: filas saltadas porque la persona tiene «No contactar» (E2). Entero ≥ 0.';

COMMENT ON COLUMN "crm"."bases_carga"."invalidas" IS 'Informe: filas sin nombre o sin teléfono válido (E5). Entero ≥ 0.';

COMMENT ON COLUMN "crm"."bases_carga"."repetidas" IS 'Informe: filas repetidas dentro del mismo archivo. Entero ≥ 0. La suma de cargadas, ya_existian, no_contactar, invalidas y repetidas no pasa de filas_recibidas.';

COMMENT ON COLUMN "crm"."bases_carga"."activo" IS 'Soft-delete: false = base retirada. Al retirarla, su puerta debe retirar también sus filas de crm.base_carga_leads (el lead queda libre para otra base).';

COMMENT ON COLUMN "crm"."bases_carga"."creado_en" IS 'Cuándo se creó la base.';

COMMENT ON COLUMN "crm"."bases_carga"."actualizado_en" IS 'Último cambio de la fila (totales, retiro).';

CREATE TABLE IF NOT EXISTS "crm"."busquedas_cliente_existente" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "consultado_por" "uuid" NOT NULL,
    "criterio" "text" NOT NULL,
    "tipo_documento" "text",
    "valor_consultado" "text" NOT NULL,
    "lead_id" "uuid",
    "veredicto" "text" NOT NULL,
    "inversionista_id" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "busqueda_cliente_criterio_valido" CHECK (("criterio" = ANY (ARRAY['documento'::"text", 'telefono'::"text", 'lead'::"text"]))),
    CONSTRAINT "busqueda_cliente_documento_coherente" CHECK ((("criterio" = 'documento'::"text") = ("tipo_documento" IS NOT NULL))),
    CONSTRAINT "busqueda_cliente_lead_coherente" CHECK ((("criterio" = 'lead'::"text") = ("lead_id" IS NOT NULL))),
    CONSTRAINT "busqueda_cliente_persona_coherente" CHECK (((("veredicto" = 'encontrado'::"text") AND ("inversionista_id" IS NOT NULL)) OR ("veredicto" = 'no_operable'::"text") OR (("veredicto" <> ALL (ARRAY['encontrado'::"text", 'no_operable'::"text"])) AND ("inversionista_id" IS NULL)))),
    CONSTRAINT "busqueda_cliente_tipo_valido" CHECK (("tipo_documento" = ANY (ARRAY['DNI'::"text", 'CE'::"text", 'PASAPORTE'::"text"]))),
    CONSTRAINT "busqueda_cliente_valor_acotado" CHECK ((("length"("valor_consultado") >= 1) AND ("length"("valor_consultado") <= 64))),
    CONSTRAINT "busqueda_cliente_veredicto_valido" CHECK (("veredicto" = ANY (ARRAY['encontrado'::"text", 'no_encontrado'::"text", 'ambiguo'::"text", 'conflicto'::"text", 'no_operable'::"text", 'limite'::"text", 'invalido'::"text"])))
);

COMMENT ON TABLE "crm"."busquedas_cliente_existente" IS 'Venta cruzada: bitácora inmutable de cada búsqueda exacta de un cliente existente (documento, teléfono o lead). Rastro anti-pesca para Gerencia y llave de la puerta de preparación. Sin lectura directa: solo funciones security definer. Contiene datos personales (valor_consultado), también de personas que no son clientes.';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."id" IS 'Identificador de la búsqueda. La solicitud de venta cruzada lo guarda en busqueda_id como su llave.';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."consultado_por" IS 'Perfil del miembro del CRM que hizo la búsqueda (auth.uid() de la puerta).';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."criterio" IS 'Cómo se buscó: documento (exacto y normalizado), telefono (normalizado +51...) o lead (un lead del ámbito del actor).';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."tipo_documento" IS 'DNI, CE o PASAPORTE. Solo cuando criterio = documento.';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."valor_consultado" IS 'DATO PERSONAL. Valor buscado ya normalizado: documento, teléfono o id del lead (1 a 64 caracteres; la puerta trunca). La auditoría lo enmascara.';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."lead_id" IS 'Lead desde el que se buscó. Solo cuando criterio = lead.';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."veredicto" IS 'encontrado, no_encontrado, ambiguo (varias personas), conflicto (identidades discordantes), no_operable (existe pero hoy no admite inversiones), limite (tope por hora) o invalido (valor mal formado).';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."inversionista_id" IS 'Persona canónica hallada. Obligatoria si el veredicto es encontrado; opcional si es no_operable; nula en el resto.';

COMMENT ON COLUMN "crm"."busquedas_cliente_existente"."creado_en" IS 'Momento de la búsqueda. La puerta de preparación exige una búsqueda de las últimas 2 horas.';

CREATE TABLE IF NOT EXISTS "crm"."cambio_cuenta_avisos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "reserva" "uuid",
    "reclamado_en" timestamp with time zone,
    "novedad_en" timestamp with time zone,
    "correo_en" timestamp with time zone,
    "superada_en" timestamp with time zone,
    "intentos" integer DEFAULT 0 NOT NULL,
    "ultimo_error" "text",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cambio_cuenta_avisos_error_corto" CHECK ((("ultimo_error" IS NULL) OR ("length"("ultimo_error") <= 500))),
    CONSTRAINT "cambio_cuenta_avisos_intentos_validos" CHECK (("intentos" >= 0))
);

COMMENT ON TABLE "crm"."cambio_cuenta_avisos" IS 'Estado del aviso al cliente por solicitud de cambio de cuenta de pago: reserva de envío con token (10 min), canales entregados, superado por un cambio posterior, intentos y último error. No se borra.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."id" IS 'Identificador.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."solicitud_id" IS 'Solicitud de crm.contrato_cuenta_pago_cambios.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."reserva" IS 'Token de la reserva en curso: confirmar exige el mismo token.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."reclamado_en" IS 'Inicio de la reserva en curso (se libera al confirmar o a los 10 minutos).';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."novedad_en" IS 'Cuándo se publicó la novedad en el portal del cliente.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."correo_en" IS 'Cuándo se envió el correo al cliente.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."superada_en" IS 'El cambio quedó superado por otro posterior: no se avisa.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."intentos" IS 'Reservas de envío realizadas.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."ultimo_error" IS 'Último error de envío (para la pantalla).';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."creado_en" IS 'Primera reserva.';

COMMENT ON COLUMN "crm"."cambio_cuenta_avisos"."actualizado_en" IS 'Último cambio de estado.';

CREATE TABLE IF NOT EXISTS "crm"."capital_cortes_valorados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "periodo" "date" NOT NULL,
    "corte" "date" NOT NULL,
    "revision" integer NOT NULL,
    "meta_periodo_id" "uuid",
    "meta_revision" integer DEFAULT 0 NOT NULL,
    "base" "jsonb" NOT NULL,
    "produccion" "jsonb" NOT NULL,
    "facturacion" "jsonb" NOT NULL,
    "metas" "jsonb" NOT NULL,
    "personas" "jsonb" NOT NULL,
    "huella" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "capital_cortes_valorados_base_check" CHECK (("jsonb_typeof"("base") = 'array'::"text")),
    CONSTRAINT "capital_cortes_valorados_check" CHECK ((("corte" >= "periodo") AND ("corte" < (("periodo" + '1 mon'::interval))::"date"))),
    CONSTRAINT "capital_cortes_valorados_facturacion_check" CHECK (("jsonb_typeof"("facturacion") = 'array'::"text")),
    CONSTRAINT "capital_cortes_valorados_metas_check" CHECK (("jsonb_typeof"("metas") = 'array'::"text")),
    CONSTRAINT "capital_cortes_valorados_periodo_check" CHECK (("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp with time zone))::"date")),
    CONSTRAINT "capital_cortes_valorados_personas_check" CHECK (("jsonb_typeof"("personas") = 'array'::"text")),
    CONSTRAINT "capital_cortes_valorados_produccion_check" CHECK (("jsonb_typeof"("produccion") = 'array'::"text")),
    CONSTRAINT "capital_cortes_valorados_revision_check" CHECK (("revision" > 0))
);

COMMENT ON TABLE "crm"."capital_cortes_valorados" IS 'Publicaciones completas e inmutables de capital por operación. Incluyen importes, cantidades y metas del mismo corte; la conversión comercial sigue su núcleo independiente.';

CREATE TABLE IF NOT EXISTS "crm"."capital_mes_sellos" (
    "periodo" "date" NOT NULL,
    "corte_id" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL
);

COMMENT ON TABLE "crm"."capital_mes_sellos" IS 'Extensión inmutable del sello mensual. Conserva el corte, las valoraciones de origen, metas e importes exactos sin ampliar el contrato estricto de las RPC v1.';

CREATE TABLE IF NOT EXISTS "crm"."capital_valoracion_politica" (
    "id" boolean DEFAULT true NOT NULL,
    "vigente_desde" "date" DEFAULT '2026-10-01'::"date" NOT NULL,
    "activa" boolean DEFAULT false NOT NULL,
    "politica" "text" DEFAULT 'sbs_punto_medio_7d_v1'::"text" NOT NULL,
    "activada_en" timestamp with time zone,
    "bundle_compatible" "text",
    "censo_huella" "text",
    CONSTRAINT "capital_valoracion_politica_id_check" CHECK ("id"),
    CONSTRAINT "capital_valoracion_politica_politica_check" CHECK (("politica" = 'sbs_punto_medio_7d_v1'::"text")),
    CONSTRAINT "capital_valoracion_politica_vigente_desde_check" CHECK (("vigente_desde" = '2026-10-01'::"date"))
);

CREATE TABLE IF NOT EXISTS "crm"."capital_valoraciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fuente" "text" NOT NULL,
    "fuente_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "anterior_id" "uuid",
    "firma_fuente" "text" NOT NULL,
    "fecha_comercial" "date" NOT NULL,
    "monto" numeric(20,2) NOT NULL,
    "moneda" "text" NOT NULL,
    "fecha_tc" "date",
    "politica_tc" "text",
    "tasa" numeric(14,4) NOT NULL,
    "equivalente_pen" numeric(24,2) NOT NULL,
    "motivo" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "capital_valoraciones_check" CHECK (((("moneda" = 'PEN'::"text") AND ("tasa" = (1)::numeric) AND ("fecha_tc" IS NULL) AND ("politica_tc" IS NULL) AND ("equivalente_pen" = "monto")) OR (("moneda" = 'USD'::"text") AND ("fecha_tc" IS NOT NULL) AND ("politica_tc" IS NOT NULL) AND ("equivalente_pen" = "round"(("monto" * "tasa"), 2))))),
    CONSTRAINT "capital_valoraciones_equivalente_pen_check" CHECK ((("equivalente_pen" >= (0)::numeric) AND ("equivalente_pen" < 'Infinity'::numeric))),
    CONSTRAINT "capital_valoraciones_fuente_check" CHECK (("fuente" = ANY (ARRAY['contrato'::"text", 'cierre_externo'::"text"]))),
    CONSTRAINT "capital_valoraciones_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "capital_valoraciones_monto_check" CHECK ((("monto" >= (0)::numeric) AND ("monto" < 'Infinity'::numeric))),
    CONSTRAINT "capital_valoraciones_motivo_check" CHECK (("motivo" = ANY (ARRAY['historica'::"text", 'nueva'::"text", 'correccion'::"text", 'reconstruida_legada'::"text"]))),
    CONSTRAINT "capital_valoraciones_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "capital_valoraciones_tasa_check" CHECK ((("tasa" > (0)::numeric) AND ("tasa" < 'Infinity'::numeric)))
);

COMMENT ON TABLE "crm"."capital_valoraciones" IS 'Equivalente comercial por operación y revisión, inmutable. No sustituye la fuente financiera ni su atribución.';

CREATE TABLE IF NOT EXISTS "crm"."cartera_lecturas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "inversionista_id" "uuid",
    "tipo" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "cartera_lecturas_tipo_check" CHECK (("tipo" = ANY (ARRAY['lista'::"text", 'ficha'::"text", 'cuentas'::"text", 'documento'::"text"])))
);

CREATE TABLE IF NOT EXISTS "crm"."celulares_asignaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "etiqueta" "text" NOT NULL,
    "analista_id" "uuid" NOT NULL,
    "credencial_hash" "text" NOT NULL,
    "vigente_desde" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vigente_hasta" timestamp with time zone,
    "motivo_cierre" "text",
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "celulares_asignaciones_cierre_coherente" CHECK ((("vigente_hasta" IS NULL) = ("motivo_cierre" IS NULL))),
    CONSTRAINT "celulares_asignaciones_credencial_hash_valido" CHECK (("credencial_hash" ~ '^[0-9a-f]{64}$'::"text")),
    CONSTRAINT "celulares_asignaciones_etiqueta_valida" CHECK (("etiqueta" ~ '^C[1-9][0-9]{0,2}$'::"text")),
    CONSTRAINT "celulares_asignaciones_motivo_cierre_valido" CHECK ((("motivo_cierre" IS NULL) OR ("motivo_cierre" = ANY (ARRAY['rotacion'::"text", 'baja_analista'::"text", 'extravio'::"text", 'reemplazo'::"text", 'otro'::"text"])))),
    CONSTRAINT "celulares_asignaciones_vigencia_coherente" CHECK ((("vigente_hasta" IS NULL) OR ("vigente_hasta" > "vigente_desde")))
);

COMMENT ON TABLE "crm"."celulares_asignaciones" IS 'Qué analista tenía cada celular corporativo (C1, C2…) y en qué periodo. Actor histórico de las llamadas: no se sobrescribe; rotar = cerrar la vigencia y abrir otra fila. Una sola vigencia por etiqueta (índice parcial + exclusión por rango). DATO SENSIBLE: credencial_hash (hash de la credencial de ingesta; la clave en claro nunca se guarda). Sin columna de tenant: CRM de una sola empresa.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."id" IS 'Identificador de la asignación.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."etiqueta" IS 'Etiqueta del celular en el piloto: C1, C2… (C + número).';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."analista_id" IS 'Analista que tenía el celular (crm.equipo). Histórico e inmutable.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."credencial_hash" IS 'sha256 en hex de la credencial que el celular presenta al ingerir (F3). Única. DATO SENSIBLE: enmascarado en la auditoría.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."vigente_desde" IS 'Inicio de la vigencia.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."vigente_hasta" IS 'Fin de la vigencia; null = vigente. Se fija una sola vez.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."motivo_cierre" IS 'Por qué se cerró: rotacion, baja_analista, extravio, reemplazo u otro. Obligatorio al cerrar.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."creado_por" IS 'Quién asignó el celular (gerencia). FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."creado_en" IS 'Alta de la fila.';

COMMENT ON COLUMN "crm"."celulares_asignaciones"."actualizado_en" IS 'Último cambio (solo el cierre).';

CREATE TABLE IF NOT EXISTS "crm"."cierres_avance_anulados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "acreditado_a" "uuid",
    "motivo" "text" NOT NULL,
    "anulado_por" "uuid" NOT NULL,
    "anulado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cierres_avance_anulados_motivo_check" CHECK ((("motivo" IS NOT NULL) AND ("btrim"("motivo") <> ''::"text") AND ("length"("btrim"("motivo")) <= 300)))
);

COMMENT ON TABLE "crm"."cierres_avance_anulados" IS 'Cierres de Avance que gerencia anulo por error de gestion o mala practica. NO mueve dinero real: el contrato y el cliente siguen en public intactos. Lo unico que cambia es que ese cierre deja de acreditarle al vendedor en su cuota y en su conversion. Deny-by-default absoluto: RLS ON, cero policies, cero grants; se escribe SOLO via crm.anular_cierre_avance.';

COMMENT ON COLUMN "crm"."cierres_avance_anulados"."lead_id" IS 'El lead cuyo cierre deja de contar. UNIQUE: una anulacion por lead, sin des-anular.';

COMMENT ON COLUMN "crm"."cierres_avance_anulados"."motivo" IS 'Obligatorio: esto le quita merito a una persona y esa persona merece una razon escrita, no un registro mudo.';

CREATE OR REPLACE VIEW "crm"."clientes_basicos" WITH ("security_invoker"='true') AS
 SELECT "id",
    "nombres",
    "apellidos",
    "nombre_completo",
    "dni",
    "correo",
    "telefono",
    "asesor_perfil_id",
    "activo",
    "creado_en",
    "tipo_documento",
    "creado_por"
   FROM "crm"."clientes_basicos_fn"() "clientes_basicos_fn"("id", "nombres", "apellidos", "nombre_completo", "dni", "correo", "telefono", "asesor_perfil_id", "activo", "creado_en", "tipo_documento", "creado_por");

COMMENT ON VIEW "crm"."clientes_basicos" IS 'Clientes del portal sin columnas bancarias, scopeados por private.cliente_ids_visibles_crm. Vista security_invoker sobre una función definer gateada.';

CREATE TABLE IF NOT EXISTS "crm"."configuracion_reparto" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "singleton" boolean DEFAULT true NOT NULL,
    "coordinacion_libre" boolean DEFAULT false NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "actualizado_por" "uuid",
    CONSTRAINT "configuracion_reparto_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "configuracion_reparto_singleton_check" CHECK ("singleton")
);

ALTER TABLE ONLY "crm"."configuracion_reparto" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "crm"."configuracion_reparto" IS 'Permiso global de reparto libre para Coordinación. Solo Gerencia lo modifica mediante RPC; sin acceso directo.';

CREATE TABLE IF NOT EXISTS "crm"."contrato_cuenta_pago_asignaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "cuenta_bancaria_id" "uuid" NOT NULL,
    "vinculo_id" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "asignado_por" "uuid" NOT NULL,
    "asignado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "contrato_cuenta_pago_asignaciones_motivo_valido" CHECK ((("motivo" = "regexp_replace"("motivo", '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$'::"text", ''::"text", 'g'::"text")) AND ("length"("regexp_replace"("motivo", '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]'::"text", ''::"text", 'g'::"text")) >= 5) AND ("length"("motivo") <= 500)))
);

COMMENT ON TABLE "crm"."contrato_cuenta_pago_asignaciones" IS 'Constancia inmutable de cada asignación de la PRIMERA cuenta de pago a un contrato que no tenía ninguna (02/10/2026): quién, cuándo, a qué cuenta y por qué. No es un cambio pedido por el cliente (eso es crm.contrato_cuenta_pago_cambios). Sin claves foráneas a propósito: sobrevive a contratos, cliente, cuentas y personas. No se borra ni se modifica. DATOS SENSIBLES por referencia.';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."id" IS 'Identificador de la asignación.';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."solicitud_id" IS 'Id de la operación (idempotencia): un reintento con la misma solicitud no se aplica dos veces.';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."contrato_id" IS 'Contrato al que se asignó la cuenta de pago (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."cliente_id" IS 'Cliente titular del contrato en ese momento (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."cuenta_bancaria_id" IS 'Cuenta de crm.cuentas_bancarias asignada (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."vinculo_id" IS 'Fila de crm.contrato_cuentas_pago que creó la asignación (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."motivo" IS 'Motivo escrito por administración (5 a 500 caracteres).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."asignado_por" IS 'Administrador que asignó (id de perfil, sin FK: sobrevive a la eliminación del usuario).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_asignaciones"."asignado_en" IS 'Momento de la asignación (hora de la transacción).';

CREATE TABLE IF NOT EXISTS "crm"."contrato_cuenta_pago_cambios" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "cuenta_anterior_id" "uuid" NOT NULL,
    "cuenta_nueva_id" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "respaldo_ruta" "text" NOT NULL,
    "cambiado_por" "uuid" NOT NULL,
    "cambiado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notificado_en" timestamp with time zone,
    CONSTRAINT "contrato_cuenta_pago_cambios_cuentas_distintas" CHECK (("cuenta_anterior_id" <> "cuenta_nueva_id")),
    CONSTRAINT "contrato_cuenta_pago_cambios_motivo_valido" CHECK ((("motivo" = "regexp_replace"("motivo", '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$'::"text", ''::"text", 'g'::"text")) AND ("length"("regexp_replace"("motivo", '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]'::"text", ''::"text", 'g'::"text")) >= 5) AND ("length"("motivo") <= 500))),
    CONSTRAINT "contrato_cuenta_pago_cambios_respaldo_valido" CHECK (("respaldo_ruta" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$'::"text"))
);

COMMENT ON TABLE "crm"."contrato_cuenta_pago_cambios" IS 'Historial inmutable de cambios de cuenta de pago de contratos por pedido del cliente (F3, 26/09/2026). Solo notificado_en pasa una vez de NULL a fecha; nada se borra. Sin claves foráneas a propósito: la constancia sobrevive a contratos, cliente, cuentas y personas. DATOS SENSIBLES: motivo y respaldo (correo del cliente).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."id" IS 'Identificador del cambio.';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."solicitud_id" IS 'Id de la operación (idempotencia): un cambio de varios contratos comparte solicitud.';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."contrato_id" IS 'Contrato cuya cuenta de pago cambió (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."cliente_id" IS 'Cliente titular del contrato (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."cuenta_anterior_id" IS 'Cuenta de pago antes del cambio (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."cuenta_nueva_id" IS 'Cuenta de pago desde el cambio (sin FK).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."motivo" IS 'Motivo escrito por administración (5 a 500 caracteres).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."respaldo_ruta" IS 'Ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente que pide el cambio; respalda una sola solicitud. DATO SENSIBLE.';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."cambiado_por" IS 'Administrador que hizo el cambio (id de perfil, sin FK: sobrevive a la eliminación del usuario).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."cambiado_en" IS 'Momento del cambio (hora de la transacción).';

COMMENT ON COLUMN "crm"."contrato_cuenta_pago_cambios"."notificado_en" IS 'Aviso al cliente completo (todos sus canales entregados).';

CREATE TABLE IF NOT EXISTS "crm"."contrato_cuentas_pago" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "cuenta_bancaria_id" "uuid" NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);

COMMENT ON TABLE "crm"."contrato_cuentas_pago" IS 'Cuenta bancaria fija para todos los desembolsos del contrato (intereses, devoluciones y retorno de capital). Una fila por contrato.';

CREATE OR REPLACE VIEW "crm"."contratos_cartera" WITH ("security_invoker"='true') AS
 SELECT "id",
    "numero_contrato",
    "cliente_id",
    "cliente_nombre",
    "asesor_perfil_id",
    "capital",
    "moneda",
    "tasa_anual",
    "modalidad",
    "tipo_interes",
    "categoria",
    "estado",
    "fecha_inicio",
    "fecha_vencimiento",
    "notas_internas",
    "creado_por",
    "creado_en",
    "producto_condicion_id",
    "producto_id",
    "producto_codigo",
    "producto_version_id",
    "producto_version",
    "producto_nombre",
    "producto_version_estado",
    "fecha_cierre_comercial"
   FROM "crm"."contratos_cartera_v2_fn"() "contratos_cartera_v2_fn"("id", "numero_contrato", "cliente_id", "cliente_nombre", "asesor_perfil_id", "capital", "moneda", "tasa_anual", "modalidad", "tipo_interes", "categoria", "estado", "fecha_inicio", "fecha_vencimiento", "notas_internas", "creado_por", "creado_en", "producto_condicion_id", "producto_id", "producto_codigo", "producto_version_id", "producto_version", "producto_nombre", "producto_version_estado", "fecha_cierre_comercial");

COMMENT ON VIEW "crm"."contratos_cartera" IS 'Cartera contractual scopeada con FK, código, nombre y versión del producto; preserva snapshots retirados/legacy para corrección y auditoría.';

CREATE TABLE IF NOT EXISTS "crm"."contratos_eliminados_auditoria" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "eliminado_por" "uuid" NOT NULL,
    "eliminado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "snapshot" "jsonb" NOT NULL,
    "archivos" "jsonb" NOT NULL,
    CONSTRAINT "contratos_eliminados_auditoria_archivos_check" CHECK (("jsonb_typeof"("archivos") = 'array'::"text")),
    CONSTRAINT "contratos_eliminados_auditoria_snapshot_check" CHECK (("jsonb_typeof"("snapshot") = 'object'::"text"))
);

COMMENT ON TABLE "crm"."contratos_eliminados_auditoria" IS 'Copia privada inmutable del contrato, cuotas (incluidos pagos), titulares, cuentas, PDF y relaciones al eliminar. Sin FK al contrato eliminado. Los archivos privados referenciados se conservan; no son objetos huérfanos para limpieza.';

CREATE TABLE IF NOT EXISTS "crm"."control_citas_aplicaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version" integer NOT NULL,
    "mes_inicio" "date" NOT NULL,
    "aplicado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "aplicado_por" "uuid" NOT NULL,
    CONSTRAINT "control_citas_aplicaciones_mes_inicio_check" CHECK (("mes_inicio" = ("date_trunc"('month'::"text", ("mes_inicio")::timestamp with time zone))::"date"))
);

CREATE TABLE IF NOT EXISTS "crm"."control_citas_versiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version" integer NOT NULL,
    "configuracion" "jsonb" NOT NULL,
    "estado" "text" DEFAULT 'borrador'::"text" NOT NULL,
    "guardado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "guardado_por" "uuid" NOT NULL,
    "nota" "text",
    CONSTRAINT "control_citas_versiones_configuracion_check" CHECK ("private"."control_citas_config_valida"("configuracion")),
    CONSTRAINT "control_citas_versiones_estado_check" CHECK (("estado" = 'borrador'::"text")),
    CONSTRAINT "control_citas_versiones_nota_check" CHECK (("char_length"("nota") <= 500)),
    CONSTRAINT "control_citas_versiones_version_check" CHECK (("version" > 0))
);

COMMENT ON TABLE "crm"."control_citas_versiones" IS 'Borradores inmutables del control de Citas. Ningún lector de métricas los aplica todavía.';

CREATE TABLE IF NOT EXISTS "crm"."conversion_acreditaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "episodio_id" "uuid" NOT NULL,
    "inversionista_id" "uuid",
    "analista_id" "uuid",
    "origen" "text" NOT NULL,
    "fuente_tipo" "text" NOT NULL,
    "fuente_id" "uuid" NOT NULL,
    "fecha_comercial" "date" NOT NULL,
    "confirmado_en" timestamp with time zone NOT NULL,
    "vinculado_en" timestamp with time zone NOT NULL,
    "acreditado_en" timestamp with time zone NOT NULL,
    "periodo_comercial" "date" NOT NULL,
    "plazo_hasta" timestamp with time zone NOT NULL,
    "estado" "text" NOT NULL,
    "sellado_en" timestamp with time zone,
    "incluida_en_sello" boolean,
    "politica_desde" "date" DEFAULT '2026-09-01'::"date" NOT NULL,
    "motivo" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "ajuste_anulacion_en_sello" numeric,
    CONSTRAINT "conversion_acreditaciones_check" CHECK ((("sellado_en" IS NULL) = ("incluida_en_sello" IS NULL))),
    CONSTRAINT "conversion_acreditaciones_check1" CHECK (("periodo_comercial" = ("date_trunc"('month'::"text", ("fecha_comercial")::timestamp without time zone))::"date")),
    CONSTRAINT "conversion_acreditaciones_check2" CHECK (("acreditado_en" = GREATEST("confirmado_en", "vinculado_en"))),
    CONSTRAINT "conversion_acreditaciones_estado_check" CHECK (("estado" = ANY (ARRAY['acreditada'::"text", 'fuera_de_plazo'::"text", 'mes_sellado'::"text", 'fecha_futura'::"text", 'fuente_demo'::"text", 'operacion_cartera'::"text"]))),
    CONSTRAINT "conversion_acreditaciones_fuente_tipo_check" CHECK (("fuente_tipo" = ANY (ARRAY['contrato'::"text", 'cierre_externo'::"text"]))),
    CONSTRAINT "conversion_acreditaciones_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 5) AND ("length"("btrim"("motivo")) <= 300))),
    CONSTRAINT "conversion_acreditaciones_plazo_minimo_check" CHECK (("plazo_hasta" >= "private"."conversion_plazo_base"("periodo_comercial"))),
    CONSTRAINT "conversion_acreditaciones_politica_desde_check" CHECK (("politica_desde" = '2026-09-01'::"date")),
    CONSTRAINT "conversion_ajuste_sellado_valido" CHECK ((("ajuste_anulacion_en_sello" IS NULL) OR (("sellado_en" IS NOT NULL) AND ("ajuste_anulacion_en_sello" >= (0)::numeric))))
);

COMMENT ON COLUMN "crm"."conversion_acreditaciones"."ajuste_anulacion_en_sello" IS 'Descuento congelado al sellar desde octubre 2026. Para referidos guarda la reducción marginal del límite agregado al anular uno (15 % con peso 1), independientemente de su posición de admisión. Otros cierres guardan su aporte. NULL para fotos históricas previas y hechos aún no sellados. Sin acceso directo por API.';

COMMENT ON CONSTRAINT "conversion_acreditaciones_plazo_minimo_check" ON "crm"."conversion_acreditaciones" IS 'El plazo guardado nunca es anterior a la base del mes. Desde el 14/10/2026 el plazo es variable (decisión de Gerencia), así que ya no se exige igualdad con el plazo vigente: la fila guarda el plazo con el que se decidió.';

CREATE TABLE IF NOT EXISTS "crm"."conversion_pesos" (
    "vigente_desde" "date" NOT NULL,
    "peso_referido" numeric(4,3) NOT NULL,
    "nota" "text",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "peso_renovacion" numeric DEFAULT 0 NOT NULL,
    "tope_referidos_pct" numeric(5,2),
    CONSTRAINT "conversion_pesos_peso_referido_check" CHECK ((("peso_referido" >= (0)::numeric) AND ("peso_referido" <= (1)::numeric))),
    CONSTRAINT "conversion_pesos_peso_renovacion_rango" CHECK ((("peso_renovacion" >= (0)::numeric) AND ("peso_renovacion" <= (1)::numeric))),
    CONSTRAINT "conversion_pesos_referido_con_tope" CHECK ((("peso_referido" <= 0.150) OR ("tope_referidos_pct" IS NOT NULL))),
    CONSTRAINT "conversion_pesos_tope_referidos_pct_check" CHECK ((("tope_referidos_pct" IS NULL) OR (("tope_referidos_pct" >= (0)::numeric) AND ("tope_referidos_pct" <= (100)::numeric)))),
    CONSTRAINT "conversion_pesos_vigente_desde_check" CHECK (("vigente_desde" = ("date_trunc"('month'::"text", ("vigente_desde")::timestamp with time zone))::"date")),
    CONSTRAINT "conversion_renovacion_cero_desde_octubre" CHECK ((("vigente_desde" < '2026-10-01'::"date") OR ("peso_renovacion" = (0)::numeric)))
);

COMMENT ON TABLE "crm"."conversion_pesos" IS 'Peso del cierre de un REFERIDO en el numerador de la conversion mensual, versionado por mes. Se lee solo desde private.peso_referido_conversion (SECURITY DEFINER): RLS ON, cero policies y cero grants.';

COMMENT ON COLUMN "crm"."conversion_pesos"."vigente_desde" IS 'Primer dia del mes desde el que rige este peso. El vigente para un mes M es el mayor vigente_desde <= M.';

COMMENT ON COLUMN "crm"."conversion_pesos"."peso_referido" IS 'Fracción con la que un cierre de referido suma al numerador. 0,150 hasta septiembre de 2026; desde 2026-10-01 vale 1,000 y está acotado por tope_referidos_pct (cuentan hasta el tope; el resto vale 0). El referido NO entra en el divisor.';

COMMENT ON COLUMN "crm"."conversion_pesos"."nota" IS 'Quien acordo el peso y cuando. Es el rastro que permite explicar un mes pasado sin adivinar.';

COMMENT ON COLUMN "crm"."conversion_pesos"."peso_renovacion" IS 'Peso de una RENOVACION de cartera en el numerador de la conversion. Separado del peso del referido el 23/09/2026: hasta entonces la renovacion reutilizaba peso_referido, asi que mover el incentivo del referido movia tambien el de la renovacion. Nace en 0.15, que es lo que valia por esa reutilizacion, para no reescribir el pasado. Cambiarlo es una decision comercial, igual que el del referido.';

COMMENT ON COLUMN "crm"."conversion_pesos"."tope_referidos_pct" IS 'Desde octubre 2026: límite del aporte conjunto de referidos, como porcentaje del TOTAL de sus cierres válidos por analista/mes, sin redondeo a entero. NULL conserva la ponderación histórica sin tope.';

COMMENT ON CONSTRAINT "conversion_pesos_referido_con_tope" ON "crm"."conversion_pesos" IS 'Un peso de referido mayor que 0,150 exige un tope (tope_referidos_pct no nulo): quitar el tope exige bajar también el peso, nunca ocurre por olvido.';

COMMENT ON CONSTRAINT "conversion_renovacion_cero_desde_octubre" ON "crm"."conversion_pesos" IS 'Miguel 12/10/2026: renovación no suma conversión desde octubre 2026. No puede reactivarse por omisión ni explícitamente; reactivarla exige otra migración. El histórico anterior conserva sus pesos.';

CREATE TABLE IF NOT EXISTS "crm"."conversion_politica" (
    "unica" boolean DEFAULT true NOT NULL,
    "vigente_desde" "date" DEFAULT '2026-09-01'::"date" NOT NULL,
    "activada_en" timestamp with time zone,
    "manifiesto_huella" "text",
    "resultado" "jsonb",
    CONSTRAINT "conversion_politica_check" CHECK (((("activada_en" IS NULL) AND ("manifiesto_huella" IS NULL) AND ("resultado" IS NULL)) OR (("activada_en" IS NOT NULL) AND ("manifiesto_huella" IS NOT NULL) AND ("resultado" IS NOT NULL)))),
    CONSTRAINT "conversion_politica_unica_check" CHECK ("unica"),
    CONSTRAINT "conversion_politica_vigente_desde_check" CHECK (("vigente_desde" = '2026-09-01'::"date"))
);

CREATE TABLE IF NOT EXISTS "crm"."conversion_reservas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "reservado_por" "uuid" NOT NULL,
    "reservado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expira_en" timestamp with time zone NOT NULL,
    "efectos_iniciados_en" timestamp with time zone,
    "vence_absoluto_en" timestamp with time zone NOT NULL,
    "inversionista_id" "uuid",
    "claim_id" "uuid",
    "hash_payload" "text",
    "condiciones_tasa" "jsonb"
);

COMMENT ON TABLE "crm"."conversion_reservas" IS 'Reserva DURABLE de la conversion de un lead. La toma la edge crm-convertir-lead ANTES de crear Auth/perfil/correo; crm.convertir_lead_externo rechaza mientras siga viva. Existe porque la conversion Avance no es transaccional y sin esto una carrera dejaba un inversionista de cooperativa con cuenta de portal. RLS ON, cero policies, cero grants.';

COMMENT ON COLUMN "crm"."conversion_reservas"."expira_en" IS 'La reserva caduca sola (la edge puede morir a medias). Mientras no caduque, el cierre en cooperativa se rechaza indicando cuando reintentar.';

COMMENT ON COLUMN "crm"."conversion_reservas"."inversionista_id" IS 'F2.b b4: la PERSONA reservada (identidad, nunca documento). Solo con resolver_en_puertas.';

COMMENT ON COLUMN "crm"."conversion_reservas"."claim_id" IS 'F2.b b4: claim de la saga de Auth (crm.multiempresa_idempotencia).';

COMMENT ON COLUMN "crm"."conversion_reservas"."hash_payload" IS 'F2.b b4: huella canónica del alta (sin documento).';

COMMENT ON COLUMN "crm"."conversion_reservas"."condiciones_tasa" IS 'Intención contractual validada antes de efectos; forma parte del payload idempotente de la conversión.';

CREATE TABLE IF NOT EXISTS "crm"."conversion_ventas_recuperadas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "acreditacion_id" "uuid" NOT NULL,
    "fuente_borrada_id" "uuid" NOT NULL,
    "contrato_vigente_id" "uuid" NOT NULL,
    "cierre_avance_anulado_id" "uuid",
    "inversion_eliminada_id" "uuid",
    "fecha_comercial_antes" "date" NOT NULL,
    "fecha_comercial_despues" "date" NOT NULL,
    "motivo" "text" NOT NULL,
    "autorizado_por" "text" NOT NULL,
    "respaldo" "jsonb" NOT NULL,
    "transaccion" "xid8" DEFAULT "pg_current_xact_id"() NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "conversion_ventas_recuperadas_anulacion_completa" CHECK ((("cierre_avance_anulado_id" IS NULL) = ("inversion_eliminada_id" IS NULL))),
    CONSTRAINT "conversion_ventas_recuperadas_autorizado_por_check" CHECK ((("char_length"("btrim"("autorizado_por")) >= 3) AND ("char_length"("btrim"("autorizado_por")) <= 200))),
    CONSTRAINT "conversion_ventas_recuperadas_motivo_check" CHECK ((("char_length"("btrim"("motivo")) >= 5) AND ("char_length"("btrim"("motivo")) <= 300)))
);

COMMENT ON TABLE "crm"."conversion_ventas_recuperadas" IS 'Ventas de leads recuperadas tras borrar y recargar su contrato (migración 20261018032400, decisión de Miguel del 17/10/2026). Una fila por venta, solo inserción, sin API. Si rehabilita una anulación, private.cierre_anulado, crm.cierres_estado_fn, crm.altas_nuevas_por_analista_fn y crm.anular_cierre_avance dejan de tratar esa fila exacta como vigente.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."id" IS 'Identificador de la fila.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."lead_id" IS 'Lead cuya venta se recuperó (sin FK a propósito: no entra a los registros de dependencias de leads).';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."acreditacion_id" IS 'Acreditación de la venta (crm.conversion_acreditaciones), la misma fila antes y después (sin FK a propósito; la valida el trigger al insertar).';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."fuente_borrada_id" IS 'Contrato borrado al que apuntaba la venta (ya no existe).';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."contrato_vigente_id" IS 'Contrato vivo, recargado, al que pasa la venta (sin FK a propósito: no entra al registro de dependencias de contratos).';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."cierre_avance_anulado_id" IS 'Anulación de Avance que esta fila rehabilita (la anulación queda; deja de contar).';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."inversion_eliminada_id" IS 'Copia de «Eliminar inversión» con la venta anulada que esta fila rehabilita.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."fecha_comercial_antes" IS 'Fecha comercial del contrato vivo antes de la corrección.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."fecha_comercial_despues" IS 'Fecha comercial del contrato vivo después (igual si no se corrigió).';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."motivo" IS 'Por qué se recuperó.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."autorizado_por" IS 'Quién lo decidió.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."respaldo" IS 'Cómo estaban la acreditación, el lead y el contrato antes de la corrección.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."transaccion" IS 'Transacción que la registró.';

COMMENT ON COLUMN "crm"."conversion_ventas_recuperadas"."creado_en" IS 'Cuándo se registró.';

CREATE TABLE IF NOT EXISTS "crm"."correcciones_categoria_contrato" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "categoria_anterior" "text",
    "categoria_nueva" "text" NOT NULL,
    "motivo" "text" NOT NULL,
    "transaccion" bigint DEFAULT "txid_current"() NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "correcciones_categoria_contrato_categoria_anterior_check" CHECK (("categoria_anterior" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"]))),
    CONSTRAINT "correcciones_categoria_contrato_categoria_nueva_check" CHECK (("categoria_nueva" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"]))),
    CONSTRAINT "correcciones_categoria_contrato_check" CHECK (("categoria_anterior" IS DISTINCT FROM "categoria_nueva")),
    CONSTRAINT "correcciones_categoria_contrato_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 5) AND ("length"("btrim"("motivo")) <= 300)))
);

CREATE TABLE IF NOT EXISTS "crm"."correcciones_correo_acceso" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "por" "uuid" NOT NULL,
    "correo_anterior" "text" NOT NULL,
    "correo_nuevo" "text" NOT NULL,
    "motivo" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "auth_confirmado_en" timestamp with time zone,
    "transaccion_confirmada" "xid8",
    CONSTRAINT "correcciones_correo_acceso_motivo_check" CHECK ((("length"("motivo") >= 3) AND ("length"("motivo") <= 500)))
);

ALTER TABLE ONLY "crm"."correcciones_correo_acceso" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "crm"."correcciones_correo_acceso" IS 'Correcciones de acceso de clientes. auth_confirmado_en se sella dentro de la transacción de Auth que actualiza el perfil; NULL es un intento pendiente o rechazado, nunca un éxito.';

CREATE TABLE IF NOT EXISTS "crm"."cuentas_bancarias" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "moneda" "text" NOT NULL,
    "banco" "text" NOT NULL,
    "tipo_cuenta" "text" NOT NULL,
    "numero_cuenta" "text" NOT NULL,
    "cci" "text" NOT NULL,
    "titular_distinto" boolean DEFAULT false NOT NULL,
    "beneficiario_nombre" "text",
    "beneficiario_dni" "text",
    "activa" boolean DEFAULT true NOT NULL,
    "origen" "text" NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "desactivada_por" "uuid",
    "desactivada_en" timestamp with time zone,
    CONSTRAINT "cuentas_bancarias_banco_valido" CHECK ((("banco" = "btrim"("banco")) AND (("length"("banco") >= 1) AND ("length"("banco") <= 100)))),
    CONSTRAINT "cuentas_bancarias_beneficiario_coherente" CHECK (((("titular_distinto" = false) AND ("beneficiario_nombre" IS NULL) AND ("beneficiario_dni" IS NULL)) OR (("titular_distinto" = true) AND ("beneficiario_nombre" IS NOT NULL) AND ("beneficiario_nombre" = "btrim"("beneficiario_nombre")) AND (("length"("beneficiario_nombre") >= 1) AND ("length"("beneficiario_nombre") <= 200)) AND ("beneficiario_dni" IS NOT NULL) AND ("beneficiario_dni" ~ '^[0-9]{8,12}$'::"text")))),
    CONSTRAINT "cuentas_bancarias_cci_valido" CHECK (("cci" ~ '^[0-9]{20}$'::"text")),
    CONSTRAINT "cuentas_bancarias_desactivacion_coherente" CHECK (((("activa" = true) AND ("desactivada_por" IS NULL) AND ("desactivada_en" IS NULL)) OR (("activa" = false) AND ("desactivada_en" IS NOT NULL)))),
    CONSTRAINT "cuentas_bancarias_moneda_valida" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "cuentas_bancarias_numero_valido" CHECK (("numero_cuenta" ~ '^[A-Za-z0-9-]{1,30}$'::"text")),
    CONSTRAINT "cuentas_bancarias_origen_valido" CHECK (("origen" = ANY (ARRAY['perfil'::"text", 'contrato'::"text", 'portal'::"text"]))),
    CONSTRAINT "cuentas_bancarias_tipo_valido" CHECK (("tipo_cuenta" = ANY (ARRAY['ahorros'::"text", 'corriente'::"text"])))
);

COMMENT ON TABLE "crm"."cuentas_bancarias" IS 'Versiones reutilizables de cuentas bancarias del cliente. Sin verificacion: una cuenta nueva nace activa. Sus datos son inmutables; corregir crea otra version.';

COMMENT ON COLUMN "crm"."cuentas_bancarias"."activa" IS 'Ciclo de vida, no verificacion. False impide elegirla en contratos futuros; los contratos historicos conservan la referencia.';

CREATE TABLE IF NOT EXISTS "crm"."cuentas_bancarias_retiros" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "cuenta_id" "uuid" NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "moneda" "text" NOT NULL,
    "motivo" "text" NOT NULL,
    "respaldo_ruta" "text",
    "retirado_por" "uuid" NOT NULL,
    "retirado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cuentas_bancarias_retiros_moneda_valida" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "cuentas_bancarias_retiros_motivo_valido" CHECK ((("motivo" = "regexp_replace"("motivo", '^[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+|[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]+$'::"text", ''::"text", 'g'::"text")) AND ("length"("regexp_replace"("motivo", '[[:space:]\u00a0\u1680\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]'::"text", ''::"text", 'g'::"text")) >= 5) AND ("length"("motivo") <= 500))),
    CONSTRAINT "cuentas_bancarias_retiros_respaldo_valido" CHECK ((("respaldo_ruta" IS NULL) OR ("respaldo_ruta" ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.(pdf|jpg|jpeg|png)$'::"text")))
);

COMMENT ON TABLE "crm"."cuentas_bancarias_retiros" IS 'Constancia inmutable de cada retiro de una cuenta bancaria del cliente (F4, 26/09/2026): la cuenta pasa a activa = false y aquí queda el motivo, el respaldo opcional, quién y cuándo. Sin claves foráneas a propósito: sobrevive a cuentas, clientes y personas. No se modifica ni se borra. DATOS SENSIBLES: motivo y respaldo (correo del cliente).';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."id" IS 'Identificador del retiro.';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."solicitud_id" IS 'Id de la operación (idempotencia ante doble clic).';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."cuenta_id" IS 'Cuenta de crm.cuentas_bancarias retirada (sin FK). Una versión se retira una sola vez.';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."cliente_id" IS 'Cliente dueño de la cuenta (sin FK).';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."moneda" IS 'Moneda de la cuenta retirada.';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."motivo" IS 'Motivo escrito por administración: hasta 500 caracteres, al menos 5 visibles, sin espacios de ningún tipo en los bordes.';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."respaldo_ruta" IS 'Opcional: ruta en el bucket privado respaldos-cambio-cuenta del correo del cliente. DATO SENSIBLE.';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."retirado_por" IS 'Administrador que retiró la cuenta (id de perfil, sin FK).';

COMMENT ON COLUMN "crm"."cuentas_bancarias_retiros"."retirado_en" IS 'Momento del retiro (hora de la transacción; igual a desactivada_en de la cuenta).';

CREATE TABLE IF NOT EXISTS "crm"."cuotas_cuenta_pagada" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cuota_id" "uuid" NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "cuenta_bancaria_id" "uuid" NOT NULL,
    "origen" "text" NOT NULL,
    "sellada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "cuotas_cuenta_pagada_origen_valido" CHECK (("origen" = ANY (ARRAY['registro'::"text", 'declarado'::"text", 'inferido'::"text"])))
);

COMMENT ON TABLE "crm"."cuotas_cuenta_pagada" IS 'Constancia: cuenta bancaria a la que se pagó cada cuota. origen=registro: la vigente en la fecha del pago, sellada al registrarlo (corregir la fecha re-sella); origen=inferido: backfill con la cuenta contractual (el enlace nació el 25/09 desde el perfil). Solo vale mientras la cuota esté en pagado. Sin claves foráneas a propósito: sobrevive a las eliminaciones auditadas. No se borra. DATOS SENSIBLES por referencia.';

COMMENT ON COLUMN "crm"."cuotas_cuenta_pagada"."id" IS 'Identificador del sello.';

COMMENT ON COLUMN "crm"."cuotas_cuenta_pagada"."cuota_id" IS 'Cuota de public.cronograma_pagos (sin FK; ver la tabla). Un sello por cuota.';

COMMENT ON COLUMN "crm"."cuotas_cuenta_pagada"."contrato_id" IS 'Contrato de la cuota (sin FK).';

COMMENT ON COLUMN "crm"."cuotas_cuenta_pagada"."cuenta_bancaria_id" IS 'Cuenta de crm.cuentas_bancarias a la que se pagó (sin FK).';

COMMENT ON COLUMN "crm"."cuotas_cuenta_pagada"."origen" IS 'declarado = quien registró dijo a qué cuenta depositó (CCI del Excel o cuenta del modal); registro = deducida de la fecha del pago al registrarlo; inferido = backfill desde la cuenta contractual.';

COMMENT ON COLUMN "crm"."cuotas_cuenta_pagada"."sellada_en" IS 'Cuándo se selló o re-selló.';

CREATE TABLE IF NOT EXISTS "crm"."depositos_reclamados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "numero_norm" "text" NOT NULL,
    "cierre_id" "uuid" NOT NULL,
    "reclamado_por" "uuid" NOT NULL,
    "reclamado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);

COMMENT ON TABLE "crm"."depositos_reclamados" IS 'Memoria historica de numeros de operacion ya declarados. Append-only absoluto: corregir el numero de un cierre liberaba el anterior del indice vivo y permitia cobrarlo otra vez en otro lead. Aqui no se libera nunca.';

CREATE TABLE IF NOT EXISTS "crm"."dispositivos_push_tasa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "perfil_id" "uuid" NOT NULL,
    "sesion_id" "uuid" NOT NULL,
    "endpoint" "text" NOT NULL,
    "p256dh" "text" NOT NULL,
    "auth" "text" NOT NULL,
    "revision" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "habilitado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ultima_prueba_en" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "dispositivos_push_tasa_auth_check" CHECK (("auth" ~ '^[A-Za-z0-9_-]{22}$'::"text")),
    CONSTRAINT "dispositivos_push_tasa_endpoint_check" CHECK ((("length"("endpoint") >= 20) AND ("length"("endpoint") <= 2048))),
    CONSTRAINT "dispositivos_push_tasa_p256dh_check" CHECK (("p256dh" ~ '^[A-Za-z0-9_-]{87}$'::"text"))
);

CREATE TABLE IF NOT EXISTS "crm"."empresas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "clave" "text" NOT NULL,
    "nombre_legal" "text" NOT NULL,
    "nombre_visible" "text" NOT NULL,
    "activa" boolean DEFAULT true NOT NULL,
    "monedas" "text"[] DEFAULT ARRAY['PEN'::"text"] NOT NULL,
    "crea_contrato_avance" boolean DEFAULT false NOT NULL,
    "requiere_portal" boolean DEFAULT false NOT NULL,
    "exige_numero_transaccion" boolean DEFAULT false NOT NULL,
    "fuente_capital" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "empresas_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "empresas_clave_check" CHECK ((("clave" COLLATE "C") ~ '^[a-z][a-z0-9_]{1,30}$'::"text")),
    CONSTRAINT "empresas_contrato_implica_fuente" CHECK (((NOT "crea_contrato_avance") OR ("fuente_capital" = 'contratos'::"text"))),
    CONSTRAINT "empresas_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "empresas_fuente_capital_check" CHECK (("fuente_capital" = ANY (ARRAY['contratos'::"text", 'cierres_externos'::"text"]))),
    CONSTRAINT "empresas_monedas_check" CHECK (((("cardinality"("monedas") >= 1) AND ("cardinality"("monedas") <= 5)) AND ("monedas" <@ ARRAY['PEN'::"text", 'USD'::"text"]) AND ("array_ndims"("monedas") = 1))),
    CONSTRAINT "empresas_nombre_legal_check" CHECK ((("length"("btrim"("nombre_legal")) >= 2) AND ("length"("btrim"("nombre_legal")) <= 200))),
    CONSTRAINT "empresas_nombre_visible_check" CHECK ((("length"("btrim"("nombre_visible")) >= 2) AND ("length"("btrim"("nombre_visible")) <= 120))),
    CONSTRAINT "empresas_portal_implica_fuente" CHECK (((NOT "requiere_portal") OR ("fuente_capital" = 'contratos'::"text")))
);

COMMENT ON TABLE "crm"."empresas" IS 'F1 multiempresa: catalogo ampliable de empresas de inversion. Claves estables (avance/qorilazo/prodelco); una cuarta empresa se agrega con una fila, no con codigo. monedas/reglas por empresa son la FUENTE DE VERDAD que consultan los escritores: abrir o cerrar una moneda a una empresa es un UPDATE de esta fila (Prodelco abrio USD el 17/09/2026). fuente_capital dice de que tabla lee Capital para esta empresa; NO nace una segunda calculadora. Sin grants a la Data API.';

COMMENT ON COLUMN "crm"."empresas"."fuente_capital" IS 'De donde lee Capital esta empresa: contratos (Avance) o cierres_externos (cooperativas). Dimension para el nucleo, no una suma nueva.';

CREATE TABLE IF NOT EXISTS "crm"."enfriamiento_politica" (
    "motivo" "text" NOT NULL,
    "dias" integer NOT NULL,
    "actualizado_por" "uuid",
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "enfriamiento_politica_base_cargada_dias_positivos" CHECK ((("motivo" <> 'base_cargada'::"text") OR ("dias" > 0))),
    CONSTRAINT "enfriamiento_politica_dias_check" CHECK (("dias" >= 0)),
    CONSTRAINT "enfriamiento_politica_motivo_check" CHECK (("motivo" = ANY (ARRAY['sin_interes'::"text", 'sin_fondos'::"text", 'competencia'::"text", 'no_responde'::"text", 'datos_invalidos'::"text", 'pide_credito'::"text", 'otro'::"text", 'base_cargada'::"text"])))
);

COMMENT ON TABLE "crm"."enfriamiento_politica" IS 'Días de espera antes de que una persona descartada pueda reingresarse como lead, según motivo de descarte. Editable solo por gerencia.';

COMMENT ON CONSTRAINT "enfriamiento_politica_base_cargada_dias_positivos" ON "crm"."enfriamiento_politica" IS 'Bases cargadas (B8 r1, auditor-rls P3): el enfriamiento base_cargada es siempre de más de 0 días. Con 0, el alta de un teléfono recién cargado vería «libre» 24 h (rama de carencia del verificador) y crearía un duplicado (E2). Gerencia puede cambiar los días por la API (policy enfriamiento_update): este CHECK la frena.';

COMMENT ON CONSTRAINT "enfriamiento_politica_motivo_check" ON "crm"."enfriamiento_politica" IS 'Motivos con política de enfriamiento: los mismos de leads_motivo_descarte_check (base_cargada desde B7, 30 días).';

CREATE TABLE IF NOT EXISTS "crm"."envios_push_tasa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "dispositivo_id" "uuid" NOT NULL,
    "revision" "uuid" NOT NULL,
    "estado" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "intentos" integer DEFAULT 0 NOT NULL,
    "disponible_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "reserva" "uuid",
    "reservado_hasta" timestamp with time zone,
    "codigo_http" integer,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "enviado_en" timestamp with time zone,
    CONSTRAINT "envios_push_tasa_estado_check" CHECK (("estado" = ANY (ARRAY['pendiente'::"text", 'enviando'::"text", 'enviado'::"text", 'cancelado'::"text", 'fallido'::"text"]))),
    CONSTRAINT "envios_push_tasa_intentos_check" CHECK ((("intentos" >= 0) AND ("intentos" <= 8)))
);

CREATE TABLE IF NOT EXISTS "crm"."equipo" (
    "perfil_id" "uuid" NOT NULL,
    "rol_crm" "text" NOT NULL,
    "supervisor_id" "uuid",
    "activo" boolean DEFAULT true NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "capacidad_leads_objetivo" smallint,
    CONSTRAINT "equipo_capacidad_leads_objetivo_positiva" CHECK ((("capacidad_leads_objetivo" IS NULL) OR (("capacidad_leads_objetivo" >= 1) AND ("capacidad_leads_objetivo" <= 1000)))),
    CONSTRAINT "equipo_capacidad_leads_solo_analista" CHECK ((("capacidad_leads_objetivo" IS NULL) OR ("rol_crm" = ANY (ARRAY['vendedor'::"text", 'supervisor'::"text"])))),
    CONSTRAINT "equipo_no_autosupervision" CHECK ((("supervisor_id" IS NULL) OR ("supervisor_id" <> "perfil_id"))),
    CONSTRAINT "equipo_rol_crm_check" CHECK (("rol_crm" = ANY (ARRAY['vendedor'::"text", 'supervisor'::"text", 'gerencia'::"text", 'coordinador'::"text", 'directorio'::"text"])))
);

COMMENT ON TABLE "crm"."equipo" IS 'Jerarquía comercial del CRM: vendedor → supervisor → gerencia. El directorio queda fuera (lectura global por rol del portal).';

COMMENT ON COLUMN "crm"."equipo"."capacidad_leads_objetivo" IS 'Cantidad objetivo de leads activos que puede gestionar el analista. NULL = aun no configurada.';

CREATE TABLE IF NOT EXISTS "crm"."gestion_diaria_control_avisos" (
    "version" integer NOT NULL,
    "habilitados" boolean NOT NULL,
    "motivo" "text" NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "gestion_diaria_control_avisos_check" CHECK (((("version" = 1) AND ("creado_por" IS NULL)) OR (("version" > 1) AND ("creado_por" IS NOT NULL)))),
    CONSTRAINT "gestion_diaria_control_avisos_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 3) AND ("length"("btrim"("motivo")) <= 500))),
    CONSTRAINT "gestion_diaria_control_avisos_version_check" CHECK (("version" > 0))
);

COMMENT ON TABLE "crm"."gestion_diaria_control_avisos" IS 'F4: canal de avisos con control de emergencia versionado. No activa cortes ni reescribe políticas históricas.';

CREATE TABLE IF NOT EXISTS "crm"."gestion_diaria_entregas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "perfil_id" "uuid" NOT NULL,
    "alerta_id" "text" NOT NULL,
    "entrega" integer NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "gestion_diaria_entregas_entrega_check" CHECK (("entrega" = ANY (ARRAY[0, 1])))
);

COMMENT ON TABLE "crm"."gestion_diaria_entregas" IS 'F4: entrega única del popup por supervisor, jornada/corte y reaviso; cerrar no reconoce ni resuelve. Sin escrituras API directas.';

CREATE TABLE IF NOT EXISTS "crm"."inversion_ajustes_mes_cerrado" (
    "inversion_id" "uuid" NOT NULL,
    "periodo_origen" "date" NOT NULL,
    "fecha_imputacion" "date" NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "inversion_ajustes_mes_cerrado_check" CHECK (("fecha_imputacion" > "periodo_origen")),
    CONSTRAINT "inversion_ajustes_mes_cerrado_periodo_origen_check" CHECK (("periodo_origen" = ("date_trunc"('month'::"text", ("periodo_origen")::timestamp with time zone))::"date"))
);

COMMENT ON TABLE "crm"."inversion_ajustes_mes_cerrado" IS 'Rastro append-only de inversiones registradas después del sello de su mes. No copia monto, moneda, comisión ni conversión: remite a la inversión y a su fuente.';

CREATE TABLE IF NOT EXISTS "crm"."inversion_backfill_lotes" (
    "id" "uuid" NOT NULL,
    "hash_mapa" "text" NOT NULL,
    "mapa" "jsonb" NOT NULL,
    "resultado" "jsonb",
    "operador" "name" DEFAULT SESSION_USER NOT NULL,
    "creado_xid" "xid8" DEFAULT "pg_current_xact_id"() NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "finalizado_en" timestamp with time zone,
    CONSTRAINT "inversion_backfill_lotes_check" CHECK ((("resultado" IS NULL) = ("finalizado_en" IS NULL))),
    CONSTRAINT "inversion_backfill_lotes_hash_mapa_check" CHECK (("hash_mapa" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "inversion_backfill_lotes_mapa_check" CHECK (("jsonb_typeof"("mapa") = 'array'::"text")),
    CONSTRAINT "inversion_backfill_lotes_resultado_check" CHECK ((("resultado" IS NULL) OR ("jsonb_typeof"("resultado") = 'object'::"text")))
);

COMMENT ON TABLE "crm"."inversion_backfill_lotes" IS 'Lotes acotados de vinculación histórica F4: mapa previo, huellas y resultado. No copia dinero ni documentos. Un lote completo es inmutable y no amplía permisos de usuario.';

CREATE TABLE IF NOT EXISTS "crm"."inversion_cotitular_origenes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_titular_id" "uuid" NOT NULL,
    "inversion_id" "uuid" NOT NULL,
    "persona_origen_id" "uuid" NOT NULL,
    "identificador_origen_id" "uuid" NOT NULL,
    "fuente_snapshot" "jsonb" NOT NULL,
    "identificador_snapshot" "jsonb" NOT NULL,
    "hash_fuente" "text" NOT NULL,
    "vinculado_por" "uuid",
    "origen_registro" "text" NOT NULL,
    "operador_sql" "text" DEFAULT SESSION_USER NOT NULL,
    "vinculado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "inversion_cotitular_origenes_origen_registro_check" CHECK (("origen_registro" = ANY (ARRAY['alta'::"text", 'conciliacion'::"text", 'administracion'::"text"])))
);

CREATE TABLE IF NOT EXISTS "crm"."inversion_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversion_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "motivo" "text",
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "inversion_eventos_tipo_check" CHECK (("tipo" = ANY (ARRAY['registro'::"text", 'correccion'::"text", 'anulacion'::"text"])))
);

CREATE TABLE IF NOT EXISTS "crm"."inversion_solicitud_correcciones" (
    "id" "uuid" NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "revision_anterior" integer NOT NULL,
    "revision" integer NOT NULL,
    "hash_peticion" "text" NOT NULL,
    "hash_anterior" "text" NOT NULL,
    "hash_nuevo" "text" NOT NULL,
    "datos_anteriores" "jsonb" NOT NULL,
    "datos_nuevos" "jsonb" NOT NULL,
    "motivo" "text" NOT NULL,
    "corregido_por" "uuid" NOT NULL,
    "corregido_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "inversion_solicitud_correcciones_check" CHECK (("revision" = ("revision_anterior" + 1))),
    CONSTRAINT "inversion_solicitud_correcciones_revision_anterior_check" CHECK (("revision_anterior" >= 0))
);

CREATE TABLE IF NOT EXISTS "crm"."inversion_solicitud_origenes" (
    "solicitud_id" "uuid" NOT NULL,
    "fuente_id" "uuid" NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "tipo" "text" DEFAULT 'reinversion'::"text" NOT NULL,
    CONSTRAINT "inversion_solicitud_origenes_tipo_check" CHECK (("tipo" = ANY (ARRAY['reinversion'::"text", 'upgrade'::"text"])))
);

COMMENT ON COLUMN "crm"."inversion_solicitud_origenes"."tipo" IS 'Operación de continuidad inmutable. Upgrade = aporte adicional a una inversión vigente. Los vínculos anteriores siguen siendo reinversión.';

CREATE TABLE IF NOT EXISTS "crm"."inversion_solicitud_revisiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitud_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "responsable_anterior_id" "uuid" NOT NULL,
    "responsable_nuevo_id" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "revisado_por" "uuid" NOT NULL,
    "transaccion" "xid8" DEFAULT "pg_current_xact_id"() NOT NULL,
    "revisado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "inversion_solicitud_revisiones_check" CHECK (("responsable_anterior_id" <> "responsable_nuevo_id")),
    CONSTRAINT "inversion_solicitud_revisiones_revision_check" CHECK (("revision" > 0))
);

CREATE TABLE IF NOT EXISTS "crm"."inversion_solicitudes" (
    "id" "uuid" NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "responsable_esperado_id" "uuid" NOT NULL,
    "auth_claim_id" "uuid",
    "auth_contexto" "jsonb",
    "hash_payload" "text" NOT NULL,
    "datos" "jsonb" NOT NULL,
    "revision_datos" integer DEFAULT 0 NOT NULL,
    "estado" "text" DEFAULT 'preparada'::"text" NOT NULL,
    "inversion_id" "uuid",
    "resultado" "jsonb",
    "creado_por" "uuid" NOT NULL,
    "confirmado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "lead_origen_id" "uuid",
    "bienvenida" "jsonb",
    "puerta" "text" DEFAULT 'cartera'::"text" NOT NULL,
    "analista_cierre_id" "uuid",
    "motivo_atribucion" "text",
    "busqueda_id" "uuid",
    "recorrido_confirmado" "jsonb",
    "cancelacion_motivo" "text",
    "cancelacion_detalle" "jsonb",
    CONSTRAINT "inversion_solicitud_atribucion_coherente" CHECK (((("puerta" = 'cartera'::"text") AND ("analista_cierre_id" IS NULL) AND ("motivo_atribucion" IS NULL) AND ("busqueda_id" IS NULL)) OR (("puerta" = 'cliente_existente'::"text") AND ("lead_origen_id" IS NULL) AND ("analista_cierre_id" IS NOT NULL) AND ("analista_cierre_id" = "creado_por") AND ("busqueda_id" IS NOT NULL) AND ("motivo_atribucion" IS NOT NULL) AND (("char_length"("btrim"("motivo_atribucion", ' 	
'::"text")) >= 10) AND ("char_length"("btrim"("motivo_atribucion", ' 	
'::"text")) <= 500))))),
    CONSTRAINT "inversion_solicitud_auth_contexto" CHECK (((("auth_claim_id" IS NULL) AND ("auth_contexto" IS NULL)) OR (("auth_claim_id" IS NOT NULL) AND ("auth_contexto" IS NOT NULL) AND ("jsonb_typeof"("auth_contexto") = 'object'::"text")))),
    CONSTRAINT "inversion_solicitud_cancelacion_coherente" CHECK (((("cancelacion_motivo" IS NULL) AND ("cancelacion_detalle" IS NULL)) OR (("estado" = 'cancelada'::"text") AND ("cancelacion_motivo" IS NOT NULL) AND ("cancelacion_detalle" IS NOT NULL) AND ("jsonb_typeof"("cancelacion_detalle") = 'object'::"text")))),
    CONSTRAINT "inversion_solicitud_cancelacion_motivo_valido" CHECK ((("cancelacion_motivo" IS NULL) OR ("cancelacion_motivo" = ANY (ARRAY['numero_contrato_usado'::"text", 'sin_movimiento'::"text"])))),
    CONSTRAINT "inversion_solicitud_confirmada" CHECK ((("estado" = 'confirmada'::"text") = (("inversion_id" IS NOT NULL) AND ("resultado" IS NOT NULL) AND ("confirmado_por" IS NOT NULL)))),
    CONSTRAINT "inversion_solicitud_origen_coherente" CHECK (((("lead_origen_id" IS NULL) AND (NOT ("datos" ? 'lead_id'::"text"))) OR (("lead_origen_id" IS NOT NULL) AND (("datos" ->> 'lead_id'::"text") IS NOT NULL) AND (("datos" ->> 'lead_id'::"text") = ("lead_origen_id")::"text")))),
    CONSTRAINT "inversion_solicitud_puerta_valida" CHECK (("puerta" = ANY (ARRAY['cartera'::"text", 'cliente_existente'::"text"]))),
    CONSTRAINT "inversion_solicitudes_datos_check" CHECK (("jsonb_typeof"("datos") = 'object'::"text")),
    CONSTRAINT "inversion_solicitudes_estado_check" CHECK (("estado" = ANY (ARRAY['preparada'::"text", 'confirmada'::"text", 'cancelada'::"text"]))),
    CONSTRAINT "inversion_solicitudes_hash_payload_check" CHECK (("hash_payload" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "inversion_solicitudes_recorrido_confirmado_check" CHECK ((("recorrido_confirmado" IS NULL) OR ("jsonb_typeof"("recorrido_confirmado") = 'object'::"text"))),
    CONSTRAINT "inversion_solicitudes_revision_datos_check" CHECK (("revision_datos" >= 0))
);

COMMENT ON COLUMN "crm"."inversion_solicitudes"."lead_origen_id" IS 'Conversión inicial explícita; NULL conserva el registro de Cartera. Nunca cambia al corregir datos.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."puerta" IS 'Por dónde nació la solicitud: cartera (flujo del responsable y conversión de lead, regla de siempre) o cliente_existente (venta cruzada). Inmutable.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."analista_cierre_id" IS 'Venta cruzada: analista al que pertenecerá la inversión; siempre igual a creado_por (quien la registró). NULL en cartera, donde la atribución sigue saliendo del responsable. Inmutable.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."motivo_atribucion" IS 'Venta cruzada: por qué registra la inversión alguien que no es el responsable del cliente (10 a 500 caracteres). Texto libre: se enmascara en public.audit_log. Inmutable.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."busqueda_id" IS 'Venta cruzada: búsqueda propia, por documento, «encontrado», de esta misma persona y de las últimas 2 horas que abrió la puerta. Inmutable.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."recorrido_confirmado" IS 'Hechos y revisión de la regla al confirmar la primera conversión. Referencias sin PII, calculadas por trigger e inmutables. No backfill histórico.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."cancelacion_motivo" IS 'Por qué la canceló el CRM solo (bloque 2.15; D-58, D-59, D-63): numero_contrato_usado (el número de contrato de la solicitud ya lo usa otro contrato) o sin_movimiento (30 días sin confirmarse ni corregirse). NULL en las cancelaciones de la pantalla (crm.cancelar_solicitud_inversion_fn). Solo con estado = cancelada.';

COMMENT ON COLUMN "crm"."inversion_solicitudes"."cancelacion_detalle" IS 'Detalle de la cancelación automática (objeto): via (alta | tarea), contrato_id y numero_contrato (con cuál), corrida_id (la corrida de la tarea), dias y ultimo_movimiento (sin movimiento), corte, cancelada_en. NULL si no la canceló el CRM.';

CREATE TABLE IF NOT EXISTS "crm"."inversion_titulares" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversion_id" "uuid" NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "rol" "text" DEFAULT 'principal'::"text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "inversion_titulares_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversion_titulares_rol_check" CHECK (("rol" = ANY (ARRAY['principal'::"text", 'cotitular'::"text"])))
);

COMMENT ON TABLE "crm"."inversion_titulares" IS 'F1 multiempresa: titular principal (uno) y cotitulares (N) de una inversion. Ser cotitular NO concede Auth/Portal/banca ni duplica Capital (eso se respeta en la lectura del nucleo). Modelo relacional apagado en F1.';

CREATE TABLE IF NOT EXISTS "crm"."inversiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "empresa_id" "uuid" NOT NULL,
    "contrato_id" "uuid",
    "cierre_externo_id" "uuid",
    "estado" "text" DEFAULT 'vigente'::"text" NOT NULL,
    "fecha_comercial" "date",
    "es_primera_conversion" boolean DEFAULT false NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "inversiones_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "inversiones_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversiones_estado_check" CHECK (("estado" = ANY (ARRAY['vigente'::"text", 'anulada'::"text"]))),
    CONSTRAINT "inversiones_una_fuente" CHECK ((((("contrato_id" IS NOT NULL))::integer + (("cierre_externo_id" IS NOT NULL))::integer) = 1))
);

COMMENT ON TABLE "crm"."inversiones" IS 'F1 multiempresa: registro RELACIONAL de inversiones (NO fuente de dinero). Une persona<->empresa<->fuente economica (un contrato Avance O un cierre de cooperativa, exactamente una). El monto/moneda se leen de la fuente por private.capital_episodios; aqui no se copian. fecha_comercial es propia (decision 9); "nunca futura" lo valida la puerta de escritura de F4. APAGADO en F1: ninguna puerta escribe aqui todavia.';

COMMENT ON COLUMN "crm"."inversiones"."fecha_comercial" IS 'Fecha comercial propia de la inversion (decision 9): <= registro, nunca futura; en mes sellado -> ajuste posterior. Validacion de "no futura" en la puerta de escritura (F4), no en CHECK.';

CREATE TABLE IF NOT EXISTS "crm"."inversiones_eliminadas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fuente_tipo" "text" NOT NULL,
    "fuente_id" "uuid" NOT NULL,
    "inversion_id" "uuid",
    "empresa" "text" NOT NULL,
    "inversionista_id" "uuid",
    "lead_id" "uuid",
    "es_conversion" boolean NOT NULL,
    "conversion_anulada" boolean NOT NULL,
    "anulacion" "jsonb",
    "motivo" "text" NOT NULL,
    "eliminado_por" "uuid" NOT NULL,
    "rol_actor" "text" NOT NULL,
    "eliminado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "contrato_auditoria_id" "uuid",
    "snapshot" "jsonb" NOT NULL,
    "archivos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "valvula" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "transaccion" "xid8" DEFAULT "pg_current_xact_id"() NOT NULL,
    "reemplazada_por" "uuid",
    CONSTRAINT "inversiones_eliminadas_anulacion_check" CHECK ((("anulacion" IS NULL) OR ("jsonb_typeof"("anulacion") = 'object'::"text"))),
    CONSTRAINT "inversiones_eliminadas_archivos_check" CHECK (("jsonb_typeof"("archivos") = 'array'::"text")),
    CONSTRAINT "inversiones_eliminadas_check" CHECK ((("fuente_tipo" = 'contrato'::"text") = ("contrato_auditoria_id" IS NOT NULL))),
    CONSTRAINT "inversiones_eliminadas_check1" CHECK ((("fuente_tipo" = 'contrato'::"text") = ("empresa" = 'avance'::"text"))),
    CONSTRAINT "inversiones_eliminadas_check2" CHECK (((NOT "conversion_anulada") OR "es_conversion")),
    CONSTRAINT "inversiones_eliminadas_check3" CHECK (((NOT "es_conversion") OR ("lead_id" IS NOT NULL))),
    CONSTRAINT "inversiones_eliminadas_empresa_check" CHECK (("empresa" = ANY (ARRAY['avance'::"text", 'prodelco'::"text", 'qorilazo'::"text"]))),
    CONSTRAINT "inversiones_eliminadas_fuente_tipo_check" CHECK (("fuente_tipo" = ANY (ARRAY['contrato'::"text", 'cierre_externo'::"text"]))),
    CONSTRAINT "inversiones_eliminadas_motivo_check" CHECK ((("motivo" = "private"."motivo_normalizado"("motivo")) AND (("length"("motivo") >= 5) AND ("length"("motivo") <= 300)))),
    CONSTRAINT "inversiones_eliminadas_reemplazo_check" CHECK ((("reemplazada_por" IS NULL) OR ((NOT "conversion_anulada") AND ("reemplazada_por" <> "fuente_id")))),
    CONSTRAINT "inversiones_eliminadas_rol_actor_check" CHECK (("rol_actor" = ANY (ARRAY['admin'::"text", 'superadmin'::"text", 'gerencia'::"text"]))),
    CONSTRAINT "inversiones_eliminadas_snapshot_check" CHECK (("jsonb_typeof"("snapshot") = 'object'::"text"))
);

COMMENT ON TABLE "crm"."inversiones_eliminadas" IS 'Copia privada e inmutable de cada inversión eliminada por admin o gerencia (crm.eliminar_inversion_fn, 05/10/2026). Una fila por fuente (contrato de Avance o cierre externo de cooperativa). Sin políticas ni grants: solo la leen funciones del servidor. Contiene datos personales (documento y nombre del cliente en la copia). Los archivos referenciados se conservan en Storage como evidencia.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."id" IS 'Identificador de la copia (acuse que recibe la pantalla).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."fuente_tipo" IS 'contrato (Avance) o cierre_externo (Prodelco, Qorilazo).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."fuente_id" IS 'Id del contrato o del cierre eliminado (sin FK: ya no existe).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."inversion_id" IS 'Id de crm.inversiones si la fuente tenía inversión (sin FK: ya no existe).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."empresa" IS 'Empresa de la inversión: avance, prodelco o qorilazo.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."inversionista_id" IS 'Persona de la cartera a la que pertenecía la inversión, si se conocía.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."lead_id" IS 'Lead cuya conversión era esta inversión (solo si es_conversion).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."es_conversion" IS 'La inversión era la conversión (cierre inicial) de un lead.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."conversion_anulada" IS 'La conversión quedó anulada. private.cierre_anulado lo consulta: la anulación sobrevive a la eliminación del cierre.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."anulacion" IS 'Respuesta de la puerta de anulación si esta operación anuló la conversión; NULL si no hizo falta.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."motivo" IS 'Motivo escrito por quien elimina (5 a 300 caracteres).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."eliminado_por" IS 'Perfil que eliminó (auth.uid() resuelto en el servidor).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."rol_actor" IS 'Rol con el que eliminó: gerencia (CRM), admin o superadmin (portal).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."eliminado_en" IS 'Momento de la eliminación.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."contrato_auditoria_id" IS 'Avance: copia completa en crm.contratos_eliminados_auditoria.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."snapshot" IS 'Copia de lo eliminado. Cooperativas: cierre, inversión, depósitos, eventos, titulares, solicitudes y acreditaciones. Avance: referencia a la copia del contrato y la inversión. Dato personal: no sale de la base.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."archivos" IS 'Objetos de Storage que se conservan como evidencia (comprobante, PDF).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."valvula" IS 'Llave de un solo uso con la que los candados dejaron borrar las filas de ESTA copia; tras el commit no abre nada (exige además la misma transacción y filas idénticas a la copia).';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."transaccion" IS 'Transacción que creó la copia; la válvula solo vale dentro de ella.';

COMMENT ON COLUMN "crm"."inversiones_eliminadas"."reemplazada_por" IS 'Reemplazo (17/10/2026): contrato que quedó en lugar de esta inversión (alta correcta o la otra inversión del mismo cliente cargada dos veces). Nula en una eliminación de siempre. La venta del lead pasó a ese contrato SIN anularse. Sin llave foránea a propósito: la copia es inmutable y no debe impedir eliminar después ese contrato por su puerta.';

COMMENT ON CONSTRAINT "inversiones_eliminadas_reemplazo_check" ON "crm"."inversiones_eliminadas" IS 'Un reemplazo nunca es una conversión anulada ni se reemplaza por sí mismo.';

CREATE TABLE IF NOT EXISTS "crm"."inversionista_fusiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "canonico_id" "uuid" NOT NULL,
    "fusionado_id" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "impacto" "jsonb",
    "por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inv_fusiones_distintas" CHECK (("canonico_id" <> "fusionado_id")),
    CONSTRAINT "inversionista_fusiones_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversionista_fusiones_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 3) AND ("length"("btrim"("motivo")) <= 500)))
);

COMMENT ON TABLE "crm"."inversionista_fusiones" IS 'F1 multiempresa: libro append-only de fusiones de identidad. Gana la canonica; la perdedora se marca fusionado (nunca se borra) y solo se reorientan enlaces operativos vivos. Nunca reescribe un mes sellado.';

CREATE TABLE IF NOT EXISTS "crm"."inversionista_gestiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "tarea_id" "uuid",
    "empresa" "text",
    "tipo" "text" NOT NULL,
    "detalle" "text" NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "inversionista_gestiones_detalle_check" CHECK ((("length"("btrim"("detalle")) >= 1) AND ("length"("btrim"("detalle")) <= 2000))),
    CONSTRAINT "inversionista_gestiones_empresa_check" CHECK (("empresa" = ANY (ARRAY['avance'::"text", 'qorilazo'::"text", 'prodelco'::"text"]))),
    CONSTRAINT "inversionista_gestiones_metadata_check" CHECK (("jsonb_typeof"("metadata") = 'object'::"text")),
    CONSTRAINT "inversionista_gestiones_tipo_check" CHECK (("tipo" = ANY (ARRAY['agenda'::"text", 'cierre'::"text", 'reprogramacion'::"text", 'confirmacion'::"text", 'veto'::"text", 'levantar_veto'::"text", 'responsable'::"text", 'fusion'::"text", 'retiro'::"text", 'reinversion'::"text", 'correccion_contacto'::"text", 'correccion_coopac'::"text", 'upgrade'::"text"])))
);

CREATE TABLE IF NOT EXISTS "crm"."inversionista_identificadores" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "tipo_documento" "text" NOT NULL,
    "documento_normalizado" "text" NOT NULL,
    "documento_original" "text",
    "estado" "text" DEFAULT 'vigente'::"text" NOT NULL,
    "verificado" boolean DEFAULT false NOT NULL,
    "fuente" "text",
    "vigente_desde" timestamp with time zone DEFAULT "now"() NOT NULL,
    "vigente_hasta" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "identificador_documento_por_tipo" CHECK (((("tipo_documento" = 'DNI'::"text") AND (("documento_normalizado" COLLATE "C") ~ '^[0-9]{8}$'::"text")) OR (("tipo_documento" = 'CE'::"text") AND (("documento_normalizado" COLLATE "C") ~ '^[0-9]{9,12}$'::"text")) OR (("tipo_documento" = 'PASAPORTE'::"text") AND (("documento_normalizado" COLLATE "C") ~ '^[A-Z0-9]{6,12}$'::"text")))),
    CONSTRAINT "inversionista_identificadores_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversionista_identificadores_estado_check" CHECK (("estado" = ANY (ARRAY['vigente'::"text", 'historico'::"text"]))),
    CONSTRAINT "inversionista_identificadores_tipo_documento_check" CHECK (("tipo_documento" = ANY (ARRAY['DNI'::"text", 'CE'::"text", 'PASAPORTE'::"text"]))),
    CONSTRAINT "inversionista_identificadores_vigente_desde_check" CHECK ("isfinite"("vigente_desde")),
    CONSTRAINT "inversionista_identificadores_vigente_hasta_check" CHECK ((("vigente_hasta" IS NULL) OR "isfinite"("vigente_hasta")))
);

COMMENT ON TABLE "crm"."inversionista_identificadores" IS 'F1 multiempresa: documentos de la persona (DNI/CE/PASAPORTE). Solo un identificador VIGENTE, verificado y no fusionado resuelve identidad automaticamente. Corregir un documento marca el anterior como historico (no reescribe hechos). Telefono/correo/nombre NO son identificadores fuertes y NUNCA fusionan. El documento no viaja a logs genericos.';

CREATE TABLE IF NOT EXISTS "crm"."inversionista_leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "rol" "text" DEFAULT 'canonico'::"text" NOT NULL,
    "desde" timestamp with time zone DEFAULT "now"() NOT NULL,
    "hasta" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "inversionista_leads_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversionista_leads_desde_check" CHECK ("isfinite"("desde")),
    CONSTRAINT "inversionista_leads_hasta_check" CHECK ((("hasta" IS NULL) OR "isfinite"("hasta"))),
    CONSTRAINT "inversionista_leads_rol_check" CHECK (("rol" = ANY (ARRAY['canonico'::"text", 'historico'::"text"])))
);

COMMENT ON TABLE "crm"."inversionista_leads" IS 'F1 multiempresa: puente persona<->lead. Conserva el lead CANONICO (rol=canonico, uno por persona) y todos los leads historicos. La reinversion NUNCA crea otro lead: reutiliza el canonico. El enlace vivo esta ademas en crm.leads.inversionista_id.';

CREATE TABLE IF NOT EXISTS "crm"."inversionista_operaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "tipo" "text" NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "lead_id" "uuid",
    "identificador_anterior_id" "uuid",
    "identificador_nuevo_id" "uuid",
    "motivo" "text" NOT NULL,
    "detalle" "jsonb",
    "por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inversionista_operaciones_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversionista_operaciones_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 3) AND ("length"("btrim"("motivo")) <= 500))),
    CONSTRAINT "inversionista_operaciones_tipo_check" CHECK (("tipo" = ANY (ARRAY['correccion'::"text", 'enlace'::"text"])))
);

COMMENT ON TABLE "crm"."inversionista_operaciones" IS 'F2.b b5: libro append-only de operaciones de Gerencia sobre identidades (correccion de documento, enlace de lead suelto). Guarda ids y motivo; NUNCA el documento en claro. RLS activa, sin grants a la Data API. Se conserva en la reversa.';

CREATE TABLE IF NOT EXISTS "crm"."inversionista_responsables" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "responsable_id" "uuid" NOT NULL,
    "desde" timestamp with time zone DEFAULT "now"() NOT NULL,
    "hasta" timestamp with time zone,
    "motivo" "text",
    "por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "inv_responsables_rango" CHECK ((("hasta" IS NULL) OR ("hasta" >= "desde"))),
    CONSTRAINT "inversionista_responsables_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "inversionista_responsables_desde_check" CHECK ("isfinite"("desde")),
    CONSTRAINT "inversionista_responsables_hasta_check" CHECK ((("hasta" IS NULL) OR "isfinite"("hasta")))
);

COMMENT ON TABLE "crm"."inversionista_responsables" IS 'F1 multiempresa: historial de responsable de relacion. Cambiar el responsable NO mueve atribuciones historicas de venta. Un solo tramo abierto (hasta is null) por persona.';

CREATE TABLE IF NOT EXISTS "crm"."lead_asignacion_sla_hitos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_asignacion_id" "uuid" NOT NULL,
    "primera_gestion_en" timestamp with time zone,
    "primer_contacto_en" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "lead_asignacion_sla_hitos_orden" CHECK ((("primer_contacto_en" IS NULL) OR (("primera_gestion_en" IS NOT NULL) AND ("primer_contacto_en" >= "primera_gestion_en"))))
);

COMMENT ON TABLE "crm"."lead_asignacion_sla_hitos" IS 'Primer intento y contacto efectivo inmutables por episodio de responsabilidad.';

CREATE TABLE IF NOT EXISTS "crm"."lead_asignaciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "ciclo_n" integer NOT NULL,
    "episodio_n" integer NOT NULL,
    "analista_id" "uuid" NOT NULL,
    "motivo_apertura" "text" NOT NULL,
    "asignado_en" timestamp with time zone NOT NULL,
    "asignado_por" "uuid",
    "supervisor_origen_id" "uuid",
    "monto_estimado" numeric(12,2),
    "moneda" "text" NOT NULL,
    "origen" "text" NOT NULL,
    "categoria_interes" "text",
    "finalizado_en" timestamp with time zone,
    "finalizado_por" "uuid",
    "motivo_cierre" "text",
    "analista_destino_id" "uuid",
    "supervisor_destino_id" "uuid",
    "resultado" "text",
    "resultado_en" timestamp with time zone,
    "motivo_descarte_cierre" "text",
    "aproximado" boolean DEFAULT false NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sla_global_iniciado_en" timestamp with time zone NOT NULL,
    "sla_global_aproximado" boolean DEFAULT false NOT NULL,
    "sla_politica_asignacion_id" "uuid" NOT NULL,
    "primera_gestion_limite_en" timestamp with time zone NOT NULL,
    "primer_contacto_limite_en" timestamp with time zone NOT NULL,
    CONSTRAINT "lead_asignaciones_ciclo_n_check" CHECK (("ciclo_n" > 0)),
    CONSTRAINT "lead_asignaciones_cierre_consistente" CHECK (((("finalizado_en" IS NULL) AND ("finalizado_por" IS NULL) AND ("motivo_cierre" IS NULL) AND ("analista_destino_id" IS NULL) AND ("supervisor_destino_id" IS NULL) AND ("resultado" IS NULL) AND ("resultado_en" IS NULL) AND ("motivo_descarte_cierre" IS NULL)) OR (("finalizado_en" IS NOT NULL) AND ("motivo_cierre" IS NOT NULL) AND ((("motivo_cierre" = 'transferido'::"text") AND ("analista_destino_id" IS NOT NULL) AND ("supervisor_destino_id" IS NULL) AND ("resultado" IS NULL) AND ("resultado_en" IS NULL) AND ("motivo_descarte_cierre" IS NULL)) OR (("motivo_cierre" = 'parqueado'::"text") AND ("analista_destino_id" IS NULL) AND ("resultado" IS NULL) AND ("resultado_en" IS NULL) AND ("motivo_descarte_cierre" IS NULL)) OR (("motivo_cierre" = 'convertido'::"text") AND ("analista_destino_id" IS NULL) AND ("supervisor_destino_id" IS NULL) AND ("resultado" = 'convertido'::"text") AND ("resultado_en" = "finalizado_en") AND ("motivo_descarte_cierre" IS NULL)) OR (("motivo_cierre" = 'descartado'::"text") AND ("analista_destino_id" IS NULL) AND ("supervisor_destino_id" IS NULL) AND ("resultado" = 'descartado'::"text") AND ("resultado_en" = "finalizado_en") AND ("motivo_descarte_cierre" IS NOT NULL)) OR (("motivo_cierre" = 'desactivado'::"text") AND ("analista_destino_id" IS NULL) AND ("supervisor_destino_id" IS NULL) AND ("resultado" IS NULL) AND ("resultado_en" IS NULL) AND ("motivo_descarte_cierre" IS NULL)))))),
    CONSTRAINT "lead_asignaciones_cierre_no_trivaluado" CHECK (((("resultado" IS NULL) = ("resultado_en" IS NULL)) AND ((NOT ("motivo_cierre" IS DISTINCT FROM 'convertido'::"text")) = (NOT ("resultado" IS DISTINCT FROM 'convertido'::"text"))) AND ((NOT ("motivo_cierre" IS DISTINCT FROM 'descartado'::"text")) = (NOT ("resultado" IS DISTINCT FROM 'descartado'::"text"))) AND (("resultado" IS NULL) OR (("resultado_en" IS NOT NULL) AND ("finalizado_en" IS NOT NULL) AND ("resultado_en" = "finalizado_en"))))),
    CONSTRAINT "lead_asignaciones_episodio_n_check" CHECK (("episodio_n" > 0)),
    CONSTRAINT "lead_asignaciones_intervalo_valido" CHECK ((("finalizado_en" IS NULL) OR ("finalizado_en" >= "asignado_en"))),
    CONSTRAINT "lead_asignaciones_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "lead_asignaciones_monto_estimado_check" CHECK ((("monto_estimado" IS NULL) OR ("monto_estimado" >= (0)::numeric))),
    CONSTRAINT "lead_asignaciones_motivo_apertura_check" CHECK (("motivo_apertura" = ANY (ARRAY['ingreso'::"text", 'asignado'::"text", 'reasignado'::"text", 'reabierto'::"text", 'reactivado'::"text", 'backfill_estado_actual'::"text"]))),
    CONSTRAINT "lead_asignaciones_motivo_cierre_check" CHECK (("motivo_cierre" = ANY (ARRAY['transferido'::"text", 'parqueado'::"text", 'convertido'::"text", 'descartado'::"text", 'desactivado'::"text"]))),
    CONSTRAINT "lead_asignaciones_resultado_check" CHECK (("resultado" = ANY (ARRAY['convertido'::"text", 'descartado'::"text"]))),
    CONSTRAINT "lead_asignaciones_sla_global_orden_valido" CHECK (("sla_global_iniciado_en" <= "asignado_en")),
    CONSTRAINT "lead_asignaciones_sla_versionado_limites" CHECK ((("primera_gestion_limite_en" >= "asignado_en") AND ("primer_contacto_limite_en" >= "primera_gestion_limite_en")))
);

COMMENT ON TABLE "crm"."lead_asignaciones" IS 'Ledger inmutable de episodios de responsabilidad analitica por lead.';

COMMENT ON COLUMN "crm"."lead_asignaciones"."aproximado" IS 'True solo para el estado vigente reconstruido al instalar 0C; nunca para episodios capturados hacia adelante.';

COMMENT ON COLUMN "crm"."lead_asignaciones"."sla_global_iniciado_en" IS 'Inicio del SLA global del ciclo, compartido por todos sus episodios de asignacion.';

COMMENT ON CONSTRAINT "lead_asignaciones_cierre_no_trivaluado" ON "crm"."lead_asignaciones" IS 'Complemento BIVALUADO de lead_asignaciones_cierre_consistente, que se escribio con `=` sobre columnas nullables: alli `resultado = ''convertido''` con resultado NULL da NULL, el CHECK entero da NULL y PASA (un CHECK solo rechaza en FALSE). Aqui todo termino usa `is null` o `is not distinct from`, que nunca devuelven NULL. Efecto: resultado y resultado_en van juntos siempre, motivo_cierre=convertido <=> resultado=convertido (idem descartado) y el resultado se fecha en el instante del cierre. Sin esto puede existir un episodio con motivo_cierre=convertido y resultado NULL, que el numerador de la conversion mensual (where resultado = ''convertido'') NO ve: 0 % donde la verdad es 100 %.';

CREATE TABLE IF NOT EXISTS "crm"."lead_potencial_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "orden" bigint NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "nivel_anterior" "crm"."nivel_potencial",
    "nivel_nuevo" "crm"."nivel_potencial" NOT NULL,
    "motivo" "text" NOT NULL,
    "por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "lead_potencial_eventos_autor_check" CHECK ((("motivo" = 'manual'::"text") = ("por" IS NOT NULL))),
    CONSTRAINT "lead_potencial_eventos_creado_en_finito" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "lead_potencial_eventos_motivo_check" CHECK (("motivo" = ANY (ARRAY['manual'::"text", 'caducidad'::"text"])))
);

COMMENT ON TABLE "crm"."lead_potencial_eventos" IS 'Historial INMUTABLE de la marca de potencial: cada marca y cada bajada automática. Solo INSERT; UPDATE, DELETE y TRUNCATE se rechazan. No es una gestión: no vive en crm.actividades. Sin grants para la API.';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."id" IS 'Identificador del evento.';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."orden" IS 'Orden total de inserción. creado_en empata dentro de una misma transacción; el historial se ordena por esta columna.';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."lead_id" IS 'Lead al que pertenece el evento.';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."nivel_anterior" IS 'Nivel antes del cambio; null en la primera marca.';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."nivel_nuevo" IS 'Nivel después del cambio (igual al anterior si se volvió a confirmar).';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."motivo" IS 'manual (una persona marcó) o caducidad (bajó sola por días sin gestión).';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."por" IS 'Perfil que marcó; null solo cuando el motivo es caducidad (lo hizo el sistema).';

COMMENT ON COLUMN "crm"."lead_potencial_eventos"."creado_en" IS 'Momento del cambio.';

ALTER TABLE "crm"."lead_potencial_eventos" ALTER COLUMN "orden" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "crm"."lead_potencial_eventos_orden_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "crm"."lead_sla_ciclos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "ciclo_n" integer NOT NULL,
    "politica_id" "uuid" NOT NULL,
    "iniciado_en" timestamp with time zone NOT NULL,
    "primera_gestion_limite_en" timestamp with time zone NOT NULL,
    "primer_contacto_limite_en" timestamp with time zone NOT NULL,
    "primera_gestion_en" timestamp with time zone,
    "primer_contacto_en" timestamp with time zone,
    "aproximado" boolean DEFAULT false NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "lead_sla_ciclos_ciclo_n_check" CHECK (("ciclo_n" > 0)),
    CONSTRAINT "lead_sla_ciclos_limites" CHECK ((("primera_gestion_limite_en" >= "iniciado_en") AND ("primer_contacto_limite_en" >= "primera_gestion_limite_en") AND (("primera_gestion_en" IS NULL) OR ("primera_gestion_en" >= "iniciado_en")) AND (("primer_contacto_en" IS NULL) OR ("primer_contacto_en" >= "iniciado_en")) AND (("primer_contacto_en" IS NULL) OR (("primera_gestion_en" IS NOT NULL) AND ("primer_contacto_en" >= "primera_gestion_en")))))
);

COMMENT ON TABLE "crm"."lead_sla_ciclos" IS 'SLA global por ciclo: politica/deadlines inmutables y primer intento/contacto sellados desde actividades.';

CREATE TABLE IF NOT EXISTS "crm"."lead_sla_etapa_ajustes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "etapa_sla_id" "uuid" NOT NULL,
    "origen_actividad_id" "uuid" NOT NULL,
    "secuencia" integer NOT NULL,
    "minutos_reales" integer NOT NULL,
    "limite_antes" timestamp with time zone NOT NULL,
    "limite_despues" timestamp with time zone NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "lead_sla_etapa_ajustes_check" CHECK (("limite_despues" = ("limite_antes" + (("minutos_reales")::double precision * '00:01:00'::interval)))),
    CONSTRAINT "lead_sla_etapa_ajustes_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "lead_sla_etapa_ajustes_limite_antes_check" CHECK ("isfinite"("limite_antes")),
    CONSTRAINT "lead_sla_etapa_ajustes_limite_despues_check" CHECK ("isfinite"("limite_despues")),
    CONSTRAINT "lead_sla_etapa_ajustes_minutos_reales_check" CHECK (("minutos_reales" > 0)),
    CONSTRAINT "lead_sla_etapa_ajustes_secuencia_check" CHECK (("secuencia" > 0))
);

COMMENT ON TABLE "crm"."lead_sla_etapa_ajustes" IS 'SLA-R2: hechos de prorroga con causa. N1 no concede ni captura ajustes.';

CREATE TABLE IF NOT EXISTS "crm"."lead_sla_etapas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "ciclo_n" integer NOT NULL,
    "episodio_n" integer NOT NULL,
    "etapa" "text" NOT NULL,
    "politica_id" "uuid" NOT NULL,
    "iniciado_en" timestamp with time zone NOT NULL,
    "limite_en" timestamp with time zone NOT NULL,
    "finalizado_en" timestamp with time zone,
    "motivo_cierre" "text",
    "aproximado" boolean DEFAULT false NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "lead_sla_etapas_ciclo_n_check" CHECK (("ciclo_n" > 0)),
    CONSTRAINT "lead_sla_etapas_episodio_n_check" CHECK (("episodio_n" > 0)),
    CONSTRAINT "lead_sla_etapas_etapa_check" CHECK (("etapa" = ANY (ARRAY['nuevo'::"text", 'contactado'::"text", 'reunion_agendada'::"text", 'propuesta_enviada'::"text"]))),
    CONSTRAINT "lead_sla_etapas_intervalo" CHECK ((("limite_en" >= "iniciado_en") AND (("finalizado_en" IS NULL) OR ("finalizado_en" >= "iniciado_en")) AND (("finalizado_en" IS NULL) = ("motivo_cierre" IS NULL)))),
    CONSTRAINT "lead_sla_etapas_motivo_cierre_check" CHECK (("motivo_cierre" = ANY (ARRAY['cambio_etapa'::"text", 'cierre_terminal'::"text", 'reapertura'::"text", 'desactivacion'::"text"])))
);

COMMENT ON TABLE "crm"."lead_sla_etapas" IS 'Episodios por etapa con politica y deadline fotografiados al entrar.';

CREATE TABLE IF NOT EXISTS "crm"."leads" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "nombre_completo" "text" NOT NULL,
    "telefono" "text" NOT NULL,
    "correo" "text",
    "dni" "text",
    "distrito" "text",
    "origen" "text" NOT NULL,
    "etapa" "text" DEFAULT 'nuevo'::"text" NOT NULL,
    "motivo_descarte" "text",
    "monto_estimado" numeric,
    "moneda" "text" DEFAULT 'PEN'::"text" NOT NULL,
    "categoria_interes" "text",
    "vendedor_id" "uuid",
    "asignado_supervisor_id" "uuid",
    "perfil_id" "uuid",
    "contrato_id" "uuid",
    "convertido_en" timestamp with time zone,
    "nota" "text",
    "activo" boolean DEFAULT true NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "ciclo_actual" integer DEFAULT 1 NOT NULL,
    "genero" "text",
    "fecha_nacimiento" "date",
    "no_contactar" boolean DEFAULT false NOT NULL,
    "consentimiento_en" timestamp with time zone,
    "consentimiento_fuente" "text",
    "sla_global_iniciado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "sla_global_aproximado" boolean DEFAULT false NOT NULL,
    "clasificacion_auto" "text",
    "descartado_en" timestamp with time zone,
    "descartado_por" "uuid",
    "tenencia_desde" timestamp with time zone,
    "telefono_alternativo" "text",
    "telefono_alternativo_crudo" "text",
    "alta_manual" boolean DEFAULT false NOT NULL,
    "inversionista_id" "uuid",
    "reactivado_en" timestamp with time zone,
    "enfriado_hasta" "date",
    "proxima_llamada_en" timestamp with time zone,
    "campania_origen" "text",
    CONSTRAINT "descartado_requiere_motivo" CHECK ((("etapa" <> 'descartado'::"text") OR ("motivo_descarte" IS NOT NULL))),
    CONSTRAINT "leads_campania_origen_valida" CHECK ((("campania_origen" IS NULL) OR (("campania_origen" = "btrim"("campania_origen")) AND (("char_length"("campania_origen") >= 1) AND ("char_length"("campania_origen") <= 80)) AND ("campania_origen" !~ '[[:cntrl:]]'::"text") AND (("lower"("campania_origen") <> 'formulario 3'::"text") OR ("campania_origen" = 'Formulario 3'::"text"))))),
    CONSTRAINT "leads_categoria_interes_check" CHECK (("categoria_interes" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"]))),
    CONSTRAINT "leads_ciclo_actual_positivo" CHECK (("ciclo_actual" > 0)),
    CONSTRAINT "leads_clasificacion_auto_valida" CHECK ((("clasificacion_auto" IS NULL) OR ("clasificacion_auto" = 'posible_credito'::"text"))),
    CONSTRAINT "leads_consentimiento_fuente_valida" CHECK ((("consentimiento_fuente" IS NULL) OR ("length"("consentimiento_fuente") <= 80))),
    CONSTRAINT "leads_dni_check" CHECK ((("dni" IS NULL) OR ("dni" ~ '^[0-9]{8}$'::"text"))),
    CONSTRAINT "leads_etapa_check" CHECK (("etapa" = ANY (ARRAY['nuevo'::"text", 'contactado'::"text", 'reunion_agendada'::"text", 'propuesta_enviada'::"text", 'convertido'::"text", 'descartado'::"text"]))),
    CONSTRAINT "leads_fecha_nacimiento_valida" CHECK ((("fecha_nacimiento" IS NULL) OR (("fecha_nacimiento" >= '1900-01-01'::"date") AND ("fecha_nacimiento" < '2100-01-01'::"date")))),
    CONSTRAINT "leads_formulario3_campania_check" CHECK ((("origen" <> 'formulario_3'::"text") OR ("campania_origen" IS NULL) OR ("campania_origen" = 'Formulario 3'::"text"))),
    CONSTRAINT "leads_genero_valido" CHECK ((("genero" IS NULL) OR ("genero" = ANY (ARRAY['F'::"text", 'M'::"text"])))),
    CONSTRAINT "leads_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "leads_monto_estimado_valido" CHECK (((("monto_estimado" IS NULL) AND ("origen" = 'base_cargada'::"text") AND ("etapa" = 'descartado'::"text")) OR (("monto_estimado" IS NOT NULL) AND ("monto_estimado" > (0)::numeric) AND ("monto_estimado" <= 9999999999.99) AND ("monto_estimado" = "trunc"("monto_estimado", 2))))),
    CONSTRAINT "leads_motivo_descarte_check" CHECK (("motivo_descarte" = ANY (ARRAY['sin_interes'::"text", 'sin_fondos'::"text", 'competencia'::"text", 'no_responde'::"text", 'datos_invalidos'::"text", 'pide_credito'::"text", 'otro'::"text", 'base_cargada'::"text"]))),
    CONSTRAINT "leads_origen_check" CHECK (("origen" = ANY (ARRAY['referido'::"text", 'landing'::"text", 'formulario'::"text", 'formulario_3'::"text", 'oficina'::"text", 'otro'::"text", 'web'::"text", 'campania'::"text", 'whatsapp'::"text", 'base_cargada'::"text"]))),
    CONSTRAINT "leads_telefono_alternativo_crudo_cordura" CHECK ((("telefono_alternativo_crudo" IS NULL) OR (("btrim"("telefono_alternativo_crudo") <> ''::"text") AND ("length"("telefono_alternativo_crudo") <= 40)))),
    CONSTRAINT "leads_telefono_alternativo_excluyentes" CHECK ((("telefono_alternativo" IS NULL) OR ("telefono_alternativo_crudo" IS NULL))),
    CONSTRAINT "leads_telefono_alternativo_formato" CHECK ((("telefono_alternativo" IS NULL) OR ("telefono_alternativo" ~ '^\+(51(9[0-9]{8}|[1-8][0-9]{7})|(?!51)[1-9][0-9]{7,14})$'::"text"))),
    CONSTRAINT "leads_tenencia_exclusiva" CHECK ((("vendedor_id" IS NULL) OR ("asignado_supervisor_id" IS NULL)))
);

COMMENT ON TABLE "crm"."leads" IS 'Lead de inversión. vendedor_id null = parkeado al supervisor de turno. La conversión (etapa=convertido + perfil_id/contrato_id) SOLO ocurre vía RPC privilegiada.';

COMMENT ON COLUMN "crm"."leads"."monto_estimado" IS 'Capital que el lead estima invertir: mayor que 0, máximo 9999999999.99 y hasta 2 decimales; clasificado siempre junto con moneda. Obligatorio, salvo en un contacto de base cargada DORMIDO (origen base_cargada y etapa descartado, B7 04/10/2026, E8): si su archivo no traía capital nace sin él y no sale del descarte sin capital por ninguna vía (CHECK leads_monto_estimado_valido; se pide al reactivar). Un capital que existe no se vacía (trg_leads_000_base_cargada_solo_puerta).';

COMMENT ON COLUMN "crm"."leads"."genero" IS 'Genero del lead (F/M), opcional. Decide la silueta del avatar; sin dato el frontend cae a iniciales.';

COMMENT ON COLUMN "crm"."leads"."fecha_nacimiento" IS 'Fecha de nacimiento del lead, opcional. Solo rango de cordura en la base; la mayoria de edad se valida en el formulario.';

COMMENT ON COLUMN "crm"."leads"."no_contactar" IS 'Flag DURO tipo "No Insista": apaga toda sugerencia de outreach del motor de la agenda. La UI lo respeta; no borra el lead.';

COMMENT ON COLUMN "crm"."leads"."consentimiento_en" IS 'Cuando el lead consintio ser contactado (registro para INDECOPI).';

COMMENT ON COLUMN "crm"."leads"."consentimiento_fuente" IS 'De donde salio el consentimiento (formulario web, referido, oficina...).';

COMMENT ON COLUMN "crm"."leads"."sla_global_iniciado_en" IS 'Inicio inmutable del SLA principal para el ciclo actual; no cambia al asignar, transferir o parquear.';

COMMENT ON COLUMN "crm"."leads"."sla_global_aproximado" IS 'True solo cuando el inicio del ciclo historico no pudo reconstruirse desde un evento estructurado.';

COMMENT ON COLUMN "crm"."leads"."clasificacion_auto" IS 'Veredicto AUTOMÁTICO del clasificador sobre el comentario del cliente, sellado en el INSERT y luego inmutable. Es una MARCA para que el coordinador priorice: NUNCA descarta por sí sola. null = el código no detectó nada. Catálogo extensible por migración.';

COMMENT ON COLUMN "crm"."leads"."descartado_en" IS 'Cuándo se cerró el lead como descartado (sello del trigger, no del cliente API). Se limpia al reabrir: describe el cierre VIGENTE; el histórico vive en public.audit_log y crm.actividades.';

COMMENT ON COLUMN "crm"."leads"."descartado_por" IS 'Quién descartó el lead (perfil del actor con sesión). null en un lead descartado significaría cierre sin sesión humana. Junto a motivo_descarte responde quién y por qué, sin parsear texto.';

COMMENT ON COLUMN "crm"."leads"."tenencia_desde" IS 'Instante en que el VENDEDOR ACTUAL recibio este lead; null si no esta en tenencia operativa (sin dueno, inactivo o en etapa terminal). Proyeccion fiel de crm.lead_asignaciones.asignado_en del episodio ABIERTO: el trigger private.trg_leads_tenencia_desde espeja la misma condicion y el mismo statement que el escritor del ledger, asi que no pueden divergir. Se reinicia al cambiar de dueno, al reabrir un descartado y al reactivar; editar, mover de etapa dentro de lo operativo o registrar actividad NO lo tocan. Es el reloj que mide al ASESOR; el reloj del CLIENTE es creado_en/sla_global_iniciado_en. INMUTABLE PARA EL CLIENTE POR EL TRIGGER, no por los grants: el ACL de crm.leads es de TABLA (authenticated=arw), de modo que un revoke por columna seria no-op; el trigger reimpone el valor anterior en todo UPDATE que no abra un episodio.';

COMMENT ON COLUMN "crm"."leads"."telefono_alternativo" IS 'Segundo canal de contacto del lead, si es distinto del principal: celular peruano (+519########), fijo peruano (+51 + ocho digitos nacionales) o numero internacional en E.164. Es informativo: telefono sigue siendo la identidad usada por el dedup, el reparto y la conversion.';

COMMENT ON COLUMN "crm"."leads"."telefono_alternativo_crudo" IS 'El segundo numero TAL COMO LO ESCRIBIO la persona, cuando no se pudo entender como telefono. Existe para que nada se pierda en silencio (decision de Miguel 2026-08-26). Excluyente con telefono_alternativo: si el numero se pudo canonizar vive alli y este queda null. No es marcable — la ficha lo muestra como «sin validar» para que un humano lo lea y lo corrija.';

COMMENT ON COLUMN "crm"."leads"."alta_manual" IS 'Procedencia inmutable del alta: true solo cuando el lead nació mediante crm.crear_lead_si_disponible; false para el puente automático y registros históricos. Junto con origen landing/formulario excluye únicamente el divisor mensual, no el numerador ni otras métricas.';

COMMENT ON COLUMN "crm"."leads"."inversionista_id" IS 'F1 multiempresa: enlace vivo lead->persona (nullable en captacion; obligatorio al convertir en F3). UNICO cuando no es null: impide un segundo lead de la misma persona. El historial completo vive en crm.inversionista_leads.';

COMMENT ON COLUMN "crm"."leads"."reactivado_en" IS 'Base para gestión (B1, D9): cuándo el analista reactivó este lead descartado desde su base. Lo sella el núcleo de reactivación; NULL si nunca. No sustituye a `origen` (inmutable, canal de llegada).';

COMMENT ON COLUMN "crm"."leads"."enfriado_hasta" IS 'Base para gestión (B1, D8): fecha Lima hasta la que el lead descansa fuera de la base del analista tras agotar los intentos (constantes en private.base_gestion_constantes). La escribe el trigger de enfriamiento; Gerencia la ajusta solo por su puerta. NULL = sin enfriamiento.';

COMMENT ON COLUMN "crm"."leads"."proxima_llamada_en" IS 'Base para gestión (B1b, D7-bis/D11): próxima rellamada acordada desde la base (máximo 10 días adelante; constantes en private.base_gestion_constantes). La escribe el núcleo del intento con resultado volver_a_llamar; una nueva la sustituye, el siguiente intento la consume, reactivar o vetar la limpia. NULL = sin rellamada. Es la agenda PROPIA de la base: no es una tarea ni entra en la cola diaria ni en el SLA.';

COMMENT ON COLUMN "crm"."leads"."campania_origen" IS 'Campaña de la primera importación; NULL en históricos. El canal origen conserva las reglas comerciales.';

COMMENT ON CONSTRAINT "leads_monto_estimado_valido" ON "crm"."leads" IS 'Capital válido (mayor que 0, máximo 9999999999.99, hasta 2 decimales) o vacío SOLO en un contacto de base cargada dormido: origen base_cargada y etapa descartado (B7, E8). Toda vía que lo saque del descarte sin capital falla aquí con 23514. La rama válida exige monto_estimado is not null: sin ella un NULL pasaría el CHECK en cualquier origen y etapa.';

COMMENT ON CONSTRAINT "leads_motivo_descarte_check" ON "crm"."leads" IS 'Motivos de descarte. base_cargada (B7): contacto de base cargada que nace «dormido» en la bandeja del supervisor (E7); solo lo pone la carga de bases (trg_leads_000_base_cargada_solo_puerta), nadie lo elige al descartar.';

CREATE TABLE IF NOT EXISTS "crm"."leads_eliminados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "eliminado_por" "uuid" NOT NULL,
    "rol_actor" "text" NOT NULL,
    "eliminado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "copia" "jsonb" NOT NULL,
    "filas" "jsonb" NOT NULL,
    "transaccion" "xid8" DEFAULT "pg_current_xact_id"() NOT NULL,
    CONSTRAINT "leads_eliminados_copia_check" CHECK ((("jsonb_typeof"("copia") = 'object'::"text") AND ("jsonb_typeof"(("copia" -> 'lead'::"text")) = 'object'::"text"))),
    CONSTRAINT "leads_eliminados_filas_check" CHECK (("jsonb_typeof"("filas") = 'object'::"text")),
    CONSTRAINT "leads_eliminados_motivo_check" CHECK ((("motivo" = "private"."motivo_normalizado"("motivo")) AND (("char_length"("motivo") >= 10) AND ("char_length"("motivo") <= 500)))),
    CONSTRAINT "leads_eliminados_rol_actor_check" CHECK (("rol_actor" = ANY (ARRAY['gerencia'::"text", 'admin'::"text", 'superadmin'::"text"])))
);

COMMENT ON TABLE "crm"."leads_eliminados" IS 'Copia inmutable de cada lead eliminado por error de carga (crm.eliminar_lead_error_carga, 14/10/2026): el lead y todas sus filas hijas, tal como estaban al borrarlas. RLS sin políticas y sin grants: nadie la modifica ni la borra; gerencia la consulta con crm.listar_leads_eliminados(). Contiene datos personales del lead (nombre, teléfono, documento) dentro de la copia.';

COMMENT ON COLUMN "crm"."leads_eliminados"."id" IS 'Identificador de la copia.';

COMMENT ON COLUMN "crm"."leads_eliminados"."lead_id" IS 'Lead eliminado (ya no existe en crm.leads; sin llave foránea a propósito).';

COMMENT ON COLUMN "crm"."leads_eliminados"."motivo" IS 'Motivo escrito por quien eliminó (10 a 500 caracteres).';

COMMENT ON COLUMN "crm"."leads_eliminados"."eliminado_por" IS 'Perfil que eliminó (auth.uid() resuelto en el servidor).';

COMMENT ON COLUMN "crm"."leads_eliminados"."rol_actor" IS 'Rol que habilitó la eliminación: gerencia (CRM), admin o superadmin (portal).';

COMMENT ON COLUMN "crm"."leads_eliminados"."eliminado_en" IS 'Momento de la eliminación.';

COMMENT ON COLUMN "crm"."leads_eliminados"."copia" IS 'DATOS PERSONALES. Copia jsonb: lead y un arreglo por tabla hija (tareas, actividades, asignaciones, SLA, recibos, potencial, base cargada, llamadas del celular) y, desde la versión 2, sus fichas de inversionista con identificadores (documento), datos de contacto, responsables, gestiones, lecturas, solicitudes de inversión canceladas (datos del registro) y de tasa. Enmascarada en public.audit_log.';

COMMENT ON COLUMN "crm"."leads_eliminados"."filas" IS 'Cuántas filas se copiaron y borraron, por tabla.';

COMMENT ON COLUMN "crm"."leads_eliminados"."transaccion" IS 'Transacción que copió y borró; los candados solo abren el DELETE dentro de ella (private.borrado_lead_error_autoriza).';

CREATE TABLE IF NOT EXISTS "crm"."ledger_rentabilidad" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "numero_contrato" "text" NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "categoria" "text",
    "contrato_origen_id" "uuid",
    "politica_id" "uuid",
    "solicitud_id" "uuid",
    "tasa_base" numeric NOT NULL,
    "tasa_final" numeric NOT NULL,
    "tasa_recibida" numeric,
    "regla" "text" NOT NULL,
    "origen" "text" NOT NULL,
    "divergente" boolean GENERATED ALWAYS AS (("tasa_final" <> "tasa_base")) STORED NOT NULL,
    "actor_id" "uuid",
    "registrado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "detalle" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "secuencia" bigint NOT NULL,
    CONSTRAINT "ledger_rentabilidad_categoria_check" CHECK ((("categoria" IS NULL) OR ("categoria" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"])))),
    CONSTRAINT "ledger_rentabilidad_detalle_check" CHECK (("jsonb_typeof"("detalle") = 'object'::"text")),
    CONSTRAINT "ledger_rentabilidad_origen_check" CHECK (("origen" = ANY (ARRAY['backfill_legacy'::"text", 'observacion'::"text", 'enforcement'::"text"]))),
    CONSTRAINT "ledger_rentabilidad_regla_check" CHECK (("regla" = ANY (ARRAY['primera_inversion'::"text", 'heredada_renovacion'::"text", 'heredada_upgrade'::"text", 'historica_legacy'::"text", 'sin_regla'::"text"]))),
    CONSTRAINT "ledger_rentabilidad_tasa_base_check" CHECK ((("tasa_base" > (0)::numeric) AND ("tasa_base" <= (50)::numeric))),
    CONSTRAINT "ledger_rentabilidad_tasa_final_check" CHECK ((("tasa_final" > (0)::numeric) AND ("tasa_final" <= (50)::numeric))),
    CONSTRAINT "ledger_rentabilidad_tasa_recibida_check" CHECK ((("tasa_recibida" IS NULL) OR (("tasa_recibida" > (0)::numeric) AND ("tasa_recibida" <= (50)::numeric))))
);

COMMENT ON TABLE "crm"."ledger_rentabilidad" IS 'Rentabilidad R1. Libro APPEND-ONLY de la tasa de cada contrato: base (lo que dice la política/núcleo), final (lo que quedó en el contrato), recibida (lo que mandó el navegador), regla y origen. Los contratos anteriores al 06/09/2026 entran como historica_legacy (base = final; su historia no se reescribe). R2 escribe origen=observacion; R4 origen=enforcement. Sin FK a public.contratos a propósito: la eliminación de un contrato no borra su historia.';

COMMENT ON COLUMN "crm"."ledger_rentabilidad"."divergente" IS 'true cuando la tasa final no coincide con la base: en observación (R2) es el margen cedido sin autorización o con ella (ver solicitud_id).';

COMMENT ON COLUMN "crm"."ledger_rentabilidad"."secuencia" IS 'R2: orden monotónico de inserción (la observación diferida se inserta al commit): la revisión efectiva de un contrato es la de mayor secuencia.';

ALTER TABLE "crm"."ledger_rentabilidad" ALTER COLUMN "secuencia" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "crm"."ledger_rentabilidad_secuencia_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "crm"."llamadas_celular_enlaces" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "evento_id" "uuid" NOT NULL,
    "actividad_id" "uuid",
    "lead_id" "uuid" NOT NULL,
    "enlazado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "via" "text" DEFAULT 'manual'::"text" NOT NULL,
    CONSTRAINT "llamadas_celular_enlaces_via_valida" CHECK (("via" = ANY (ARRAY['al_colgar'::"text", 'pestana'::"text", 'manual'::"text"])))
);

COMMENT ON TABLE "crm"."llamadas_celular_enlaces" IS 'Enlace uno a uno entre una llamada del celular y la actividad de llamada que la encuesta registró (tipo llamada_*, metadata.evento = resultado_llamada, mismo lead). Si ese resultado se deshace (metadata.deshecho_en) el enlace puede moverse al resultado corregido; nunca se desenlaza ni se borra a mano. Sin columna de tenant: CRM de una sola empresa.';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."id" IS 'Identificador del enlace.';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."evento_id" IS 'La llamada enlazada (única: un evento tiene a lo sumo un enlace).';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."actividad_id" IS 'La actividad registrada por la encuesta (única entre enlaces). null solo si la actividad se eliminó.';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."lead_id" IS 'Lead de la llamada y de la actividad (coinciden por trigger).';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."enlazado_por" IS 'Quién registró el resultado que creó o movió el enlace (con ámbito sobre el lead en ese momento). FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."creado_en" IS 'Cuándo se enlazó por primera vez.';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."actualizado_en" IS 'Último movimiento del enlace (lo sella el trigger).';

COMMENT ON COLUMN "crm"."llamadas_celular_enlaces"."via" IS 'Por dónde se hizo el enlace: al_colgar (encuesta abierta por la URL de la macro), pestana (desde «Llamadas del celular») o manual (crm.enlazar_llamada_celular). Mide «encuesta abierta al colgar» por celular. Inmutable.';

CREATE TABLE IF NOT EXISTS "crm"."llamadas_celular_eventos" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asignacion_id" "uuid" NOT NULL,
    "analista_id" "uuid" NOT NULL,
    "evento_origen_id" "text" NOT NULL,
    "numero_canonico" "text",
    "direccion" "text" DEFAULT 'desconocida'::"text" NOT NULL,
    "estado_tecnico" "text" DEFAULT 'desconocido'::"text" NOT NULL,
    "duracion_seg" integer,
    "ocurrio_en" timestamp with time zone,
    "recibido_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "calidad" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "identificacion" "text" NOT NULL,
    "atencion" "text" NOT NULL,
    "lead_id" "uuid",
    "metodo_asociacion" "text",
    "asociado_por" "uuid",
    "asociado_en" timestamp with time zone,
    "motivo_descarte" "text",
    "motivo_descarte_detalle" "text",
    "descartado_por" "uuid",
    "descartado_en" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "llamadas_celular_eventos_asociacion_coherente" CHECK (((("lead_id" IS NULL) = ("metodo_asociacion" IS NULL)) AND (("lead_id" IS NULL) = ("asociado_en" IS NULL)) AND (("metodo_asociacion" IS NULL) OR ("metodo_asociacion" = 'exacto'::"text") OR ("asociado_por" IS NOT NULL)))),
    CONSTRAINT "llamadas_celular_eventos_atencion_coherente" CHECK (((("atencion" = ANY (ARRAY['requiere_resultado'::"text", 'registrado'::"text"])) AND ("identificacion" = 'identificado'::"text")) OR (("atencion" = 'requiere_devolucion'::"text") AND ("identificacion" = 'identificado'::"text") AND ("direccion" = 'entrante'::"text")) OR ("atencion" = ANY (ARRAY['por_revisar'::"text", 'descartado_con_motivo'::"text"])))),
    CONSTRAINT "llamadas_celular_eventos_atencion_valida" CHECK (("atencion" = ANY (ARRAY['por_revisar'::"text", 'requiere_resultado'::"text", 'requiere_devolucion'::"text", 'registrado'::"text", 'descartado_con_motivo'::"text"]))),
    CONSTRAINT "llamadas_celular_eventos_calidad_acotada" CHECK ((("jsonb_typeof"("calidad") = 'object'::"text") AND ("length"(("calidad")::"text") <= 2000))),
    CONSTRAINT "llamadas_celular_eventos_descarte_coherente" CHECK (((("atencion" = 'descartado_con_motivo'::"text") = ("motivo_descarte" IS NOT NULL)) AND (("atencion" = 'descartado_con_motivo'::"text") = ("descartado_en" IS NOT NULL)) AND (("motivo_descarte" IS DISTINCT FROM 'otro'::"text") OR ("length"("btrim"(COALESCE("motivo_descarte_detalle", ''::"text"))) >= 3)))),
    CONSTRAINT "llamadas_celular_eventos_detalle_acotado" CHECK ((("motivo_descarte_detalle" IS NULL) OR ("length"("motivo_descarte_detalle") <= 300))),
    CONSTRAINT "llamadas_celular_eventos_direccion_valida" CHECK (("direccion" = ANY (ARRAY['saliente'::"text", 'entrante'::"text", 'desconocida'::"text"]))),
    CONSTRAINT "llamadas_celular_eventos_duracion_valida" CHECK ((("duracion_seg" IS NULL) OR (("duracion_seg" >= 0) AND ("duracion_seg" <= 86400)))),
    CONSTRAINT "llamadas_celular_eventos_estado_tecnico_valido" CHECK (("estado_tecnico" = ANY (ARRAY['conectada'::"text", 'no_atendida'::"text", 'rechazada'::"text", 'cancelada'::"text", 'desconocido'::"text"]))),
    CONSTRAINT "llamadas_celular_eventos_identificacion_valida" CHECK (("identificacion" = ANY (ARRAY['sin_identificar'::"text", 'ambiguo'::"text", 'identificado'::"text"]))),
    CONSTRAINT "llamadas_celular_eventos_identificado_con_lead" CHECK ((("identificacion" = 'identificado'::"text") = ("lead_id" IS NOT NULL))),
    CONSTRAINT "llamadas_celular_eventos_metodo_valido" CHECK ((("metodo_asociacion" IS NULL) OR ("metodo_asociacion" = ANY (ARRAY['exacto'::"text", 'manual'::"text", 'propuesto_confirmado'::"text"])))),
    CONSTRAINT "llamadas_celular_eventos_motivo_descarte_valido" CHECK ((("motivo_descarte" IS NULL) OR ("motivo_descarte" = ANY (ARRAY['no_comercial'::"text", 'personal'::"text", 'numero_de_prueba'::"text", 'error_captura'::"text", 'otro'::"text"])))),
    CONSTRAINT "llamadas_celular_eventos_numero_e164" CHECK ((("numero_canonico" IS NULL) OR ("numero_canonico" ~ '^\+[1-9][0-9]{7,14}$'::"text"))),
    CONSTRAINT "llamadas_celular_eventos_ocurrio_en_cuerdo" CHECK ((("ocurrio_en" IS NULL) OR (("ocurrio_en" >= '2026-01-01 00:00:00+00'::timestamp with time zone) AND ("ocurrio_en" < '2100-01-01 00:00:00+00'::timestamp with time zone)))),
    CONSTRAINT "llamadas_celular_eventos_origen_valido" CHECK (("evento_origen_id" ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$'::"text"))
);

COMMENT ON TABLE "crm"."llamadas_celular_eventos" IS 'Evidencia de cada llamada saliente hecha desde un celular corporativo a un número de lead candidato (F2, corregida en 20261005143843). Payload inmutable (celular, id, número E.164, cuándo según el celular y el servidor, dirección, estado técnico, duración). Aparte, lo que cambia con transiciones vigiladas: identificación, atención, lead, método de asociación y descarte motivado. Visibilidad y gestión siguen al lead (quien hoy lo tiene; el lead tiene que estar activo); analista_id conserva quién marcó. DATO PERSONAL: numero_canonico (enmascarado en la auditoría; retención por crm.llamadas_celular_politica, las registradas se conservan). Sin columna de tenant: CRM de una sola empresa.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."id" IS 'Identificador del evento.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."asignacion_id" IS 'Asignación de celular vigente cuando se recibió (crm.celulares_asignaciones).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."analista_id" IS 'Analista que tenía el celular en ese momento (resuelto de la asignación). Histórico: no cambia aunque el lead se reasigne (decisiones 5 y 7).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."evento_origen_id" IS 'Id de la llamada generado por la macro al colgar: C<n>-<segundos del reloj del celular>, con la etiqueta de la asignación. Único (rotar la clave ya no duplica). No puede llevar un teléfono. F4 encuentra la llamada por este id completo.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."numero_canonico" IS 'Número marcado en E.164 (las dos reglas canónicas del CRM); null si el celular no lo entregó o no es un teléfono. DATO PERSONAL.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."direccion" IS 'saliente, entrante o desconocida. En el piloto solo salientes (perilla entrantes_activas).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."estado_tecnico" IS 'conectada, no_atendida, rechazada, cancelada o desconocido: lo que el celular supo decir; nunca se infiere del cero.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."duracion_seg" IS 'Duración en segundos si el celular la entregó; null = desconocida (cero no prueba nada).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."ocurrio_en" IS 'Hora de la llamada según el celular (decisión 5); null si no vino. recibido_en la contrasta.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."recibido_en" IS 'Hora del servidor al recibir el evento. SLA y retención se miden con esta.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."calidad" IS 'Observaciones acotadas de la ingesta (número inválido u oculto, reloj desfasado…). Objeto JSON ≤ 2000 caracteres.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."identificacion" IS 'sin_identificar (ningún lead; solo si la perilla lo permite), ambiguo (varios leads vivos con el número) o identificado (lead_id fijado). Solo avanza.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."atencion" IS 'por_revisar, requiere_resultado, requiere_devolucion, registrado o descartado_con_motivo. Las dos últimas son finales; la elegibilidad real se re-evalúa al leer (decisión 1).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."lead_id" IS 'Lead al que se asoció la llamada; se fija una vez y solo se corrige mientras está por atender. Se va con el lead si este se elimina.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."metodo_asociacion" IS 'exacto (match por número al ingerir), manual (el analista eligió) o propuesto_confirmado (sugerencia aceptada).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."asociado_por" IS 'Quién asoció manualmente o confirmó la propuesta; null en el match exacto. FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."asociado_en" IS 'Cuándo quedó asociada al lead.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."motivo_descarte" IS 'Catálogo cerrado (decisión 3): no_comercial, personal, numero_de_prueba, error_captura u otro (con detalle).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."motivo_descarte_detalle" IS 'Texto del motivo cuando es otro (≥ 3 caracteres visibles); opcional en los demás.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."descartado_por" IS 'Quién descartó la llamada. FK con RESTRICT: la baja de usuarios detecta el historial y conserva la identidad.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."descartado_en" IS 'Cuándo se descartó; a partir de aquí corre dias_retencion_descartados.';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."creado_en" IS 'Alta de la fila (igual a recibido_en salvo cargas históricas).';

COMMENT ON COLUMN "crm"."llamadas_celular_eventos"."actualizado_en" IS 'Último cambio de identificación o atención (lo sella el trigger).';

CREATE TABLE IF NOT EXISTS "crm"."llamadas_celular_politica" (
    "singleton" boolean DEFAULT true NOT NULL,
    "guardar_sin_identificar" boolean DEFAULT false NOT NULL,
    "entrantes_activas" boolean DEFAULT false NOT NULL,
    "dias_retencion_descartados" integer DEFAULT 30 NOT NULL,
    "dias_retencion_sin_resolver" integer DEFAULT 30 NOT NULL,
    "dias_retencion_sin_identificar" integer DEFAULT 30 NOT NULL,
    "actualizado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "limite_envios_minuto" integer DEFAULT 30 NOT NULL,
    "limite_envios_dia" integer DEFAULT 600 NOT NULL,
    CONSTRAINT "llamadas_celular_politica_descartados_rango" CHECK ((("dias_retencion_descartados" >= 1) AND ("dias_retencion_descartados" <= 365))),
    CONSTRAINT "llamadas_celular_politica_entrantes_bloqueadas" CHECK ((NOT "entrantes_activas")),
    CONSTRAINT "llamadas_celular_politica_limite_dia_rango" CHECK ((("limite_envios_dia" >= 1) AND ("limite_envios_dia" <= 20000))),
    CONSTRAINT "llamadas_celular_politica_limite_minuto_rango" CHECK ((("limite_envios_minuto" >= 1) AND ("limite_envios_minuto" <= 600))),
    CONSTRAINT "llamadas_celular_politica_limites_coherentes" CHECK (("limite_envios_minuto" <= "limite_envios_dia")),
    CONSTRAINT "llamadas_celular_politica_sin_identificar_rango" CHECK ((("dias_retencion_sin_identificar" >= 1) AND ("dias_retencion_sin_identificar" <= 365))),
    CONSTRAINT "llamadas_celular_politica_sin_resolver_rango" CHECK ((("dias_retencion_sin_resolver" >= 1) AND ("dias_retencion_sin_resolver" <= 365))),
    CONSTRAINT "llamadas_celular_politica_unica" CHECK ("singleton")
);

COMMENT ON TABLE "crm"."llamadas_celular_politica" IS 'Perillas del contrato de llamadas desde el celular (F2, decisiones provisionales de Jhosep 30/09/2026, pendientes de Miguel). Fila única. Solo gerencia la ajusta, por puerta (F2-c). Sin columna de tenant: CRM de una sola empresa (excepción documentada).';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."singleton" IS 'Siempre true: garantiza una sola fila.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."guardar_sin_identificar" IS 'false (decisión 3): una llamada a un número que no es de ningún lead no se guarda; la ingesta responde «ignorado». true: se guarda como sin_identificar y vive dias_retencion_sin_identificar (lo que pide F5 del plan).';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."entrantes_activas" IS 'Siempre false: entrantes bloqueadas por el CHECK llamadas_celular_politica_entrantes_bloqueadas y por la puerta (decisión 2 de Miguel, 03/10). La ingesta ignora toda llamada que no sea saliente.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."dias_retencion_descartados" IS 'Días que vive una llamada descartada con motivo antes de la purga (30, decisión 6).';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."dias_retencion_sin_resolver" IS 'Días que vive una llamada sin resolver desde recibido_en: identificada sin enlace (pide resultado o está por revisar) o ambigua (30, decisión 4 de Miguel del 03/10). Las registradas no caducan: son historial del lead.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."dias_retencion_sin_identificar" IS 'Días que vive una llamada sin identificar, solo si guardar_sin_identificar está encendida.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."actualizado_por" IS 'Quién ajustó la política por última vez (perfil de gerencia). FK con RESTRICT: la baja de usuarios (private.usuario_tiene_historial) detecta el historial y conserva la identidad; nunca SET NULL.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."creado_en" IS 'Sembrada por la migración.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."actualizado_en" IS 'Último ajuste (lo sella el trigger).';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."limite_envios_minuto" IS 'Envíos que acepta un celular por minuto de reloj (30, decisión 2 de F3, provisional de Jhosep 01/10). Lo comparten las llamadas y los latidos; al pasarse, P0429 con la espera.';

COMMENT ON COLUMN "crm"."llamadas_celular_politica"."limite_envios_dia" IS 'Envíos que acepta un celular por día de Lima (600, decisión 2 de F3). No menor que limite_envios_minuto.';

COMMENT ON CONSTRAINT "llamadas_celular_politica_entrantes_bloqueadas" ON "crm"."llamadas_celular_politica" IS 'Entrantes bloqueadas (fallo 3, decisión 2 de Miguel del 03/10): la #14 llega después, como paso propio, y retira este CHECK.';

CREATE TABLE IF NOT EXISTS "crm"."metas_vendedor" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "meta_periodo_id" "uuid" NOT NULL,
    "vendedor_id" "uuid" NOT NULL,
    "supervisor_id" "uuid" NOT NULL,
    "conversion_objetivo" numeric(5,2) NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "metas_vendedor_conversion_objetivo_check" CHECK ((("conversion_objetivo" >= (0)::numeric) AND ("conversion_objetivo" <= (100)::numeric))),
    CONSTRAINT "metas_vendedor_personas_distintas" CHECK (("vendedor_id" <> "supervisor_id"))
);

COMMENT ON TABLE "crm"."metas_vendedor" IS 'Meta individual inmutable. supervisor_id es snapshot de atribucion; RLS usa jerarquia vigente.';

CREATE TABLE IF NOT EXISTS "crm"."metas_vendedor_detalle" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "meta_vendedor_id" "uuid" NOT NULL,
    "categoria" "text" NOT NULL,
    "moneda" "text" NOT NULL,
    "capital_objetivo" numeric(14,2) NOT NULL,
    "contratos_objetivo" integer NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "metas_vendedor_detalle_capital_objetivo_check" CHECK ((("capital_objetivo" >= (0)::numeric) AND ("capital_objetivo" <= (100000000)::numeric))),
    CONSTRAINT "metas_vendedor_detalle_categoria_check" CHECK (("categoria" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"]))),
    CONSTRAINT "metas_vendedor_detalle_contratos_objetivo_check" CHECK ((("contratos_objetivo" >= 0) AND ("contratos_objetivo" <= 1000))),
    CONSTRAINT "metas_vendedor_detalle_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"])))
);

COMMENT ON TABLE "crm"."metas_vendedor_detalle" IS 'Seis dimensiones por vendedor: Nuevo/Renovacion/Upgrade x PEN/USD. No existe suma monetaria mixta.';

CREATE TABLE IF NOT EXISTS "crm"."multiempresa_flags" (
    "nombre" "text" NOT NULL,
    "activo" boolean DEFAULT false NOT NULL,
    "descripcion" "text",
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_por" "uuid",
    CONSTRAINT "multiempresa_flags_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "multiempresa_flags_nombre_check" CHECK ((("nombre" COLLATE "C") ~ '^[a-z][a-z0-9_]{2,60}$'::"text"))
);

COMMENT ON TABLE "crm"."multiempresa_flags" IS 'F1 multiempresa: banderas de rollout. TODAS apagadas en F1. Encienden comportamiento en F3+ (resolver en puertas, escritura de inversiones, Ficha 360). Solo Gerencia/servidor las mueve; sin grants a la Data API.';

CREATE TABLE IF NOT EXISTS "crm"."multiempresa_idempotencia" (
    "clave" "text" NOT NULL,
    "tipo" "text" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "hash_payload" "text" NOT NULL,
    "resultado" "jsonb",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "creado_por" "uuid",
    CONSTRAINT "multiempresa_idempotencia_clave_check" CHECK ((("length"("clave") >= 8) AND ("length"("clave") <= 200))),
    CONSTRAINT "multiempresa_idempotencia_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "multiempresa_idempotencia_hash_payload_check" CHECK ((("hash_payload" COLLATE "C") ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "multiempresa_idempotencia_tipo_check" CHECK ((("length"("tipo") >= 2) AND ("length"("tipo") <= 80))),
    CONSTRAINT "multiempresa_idempotencia_version_check" CHECK (("version" >= 1))
);

COMMENT ON TABLE "crm"."multiempresa_idempotencia" IS 'F1 multiempresa: almacen de idempotencia de las puertas (clave, tipo, version, hash SHA-256 del payload canonico, resultado). Misma clave+hash devuelve resultado; misma clave+hash distinto = conflicto. Usado por F3/F4; apagado en F1.';

CREATE TABLE IF NOT EXISTS "crm"."objetivos_legacy_archivo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "periodo" "date" NOT NULL,
    "rol" "text" NOT NULL,
    "capital_objetivo" numeric(14,2) DEFAULT 0 NOT NULL,
    "ventas_objetivo" smallint DEFAULT 0 NOT NULL,
    "conversion_objetivo" numeric(5,2) DEFAULT 0 NOT NULL,
    "actualizado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "objetivos_capital_valido" CHECK ((("capital_objetivo" >= (0)::numeric) AND ("capital_objetivo" <= (100000000)::numeric))),
    CONSTRAINT "objetivos_conversion_valida" CHECK ((("conversion_objetivo" >= (0)::numeric) AND ("conversion_objetivo" <= (100)::numeric))),
    CONSTRAINT "objetivos_periodo_cuerdo" CHECK ((("periodo" >= '2026-01-01'::"date") AND ("periodo" < '2100-01-01'::"date"))),
    CONSTRAINT "objetivos_periodo_primer_dia" CHECK ((EXTRACT(day FROM "periodo") = (1)::numeric)),
    CONSTRAINT "objetivos_rol_valido" CHECK (("rol" = ANY (ARRAY['vendedor'::"text", 'supervisor'::"text", 'gerencia'::"text"]))),
    CONSTRAINT "objetivos_ventas_validas" CHECK ((("ventas_objetivo" >= 0) AND ("ventas_objetivo" <= 1000)))
);

COMMENT ON TABLE "crm"."objetivos_legacy_archivo" IS 'ARCHIVO NO CANONICO: metas antiguas por rol, imposibles de repartir por vendedor/categoria/moneda sin inventar datos.';

COMMENT ON COLUMN "crm"."objetivos_legacy_archivo"."periodo" IS 'Primer dia del mes de la meta (mes calendario de America/Lima; la UI calcula el periodo vigente en Lima).';

COMMENT ON COLUMN "crm"."objetivos_legacy_archivo"."capital_objetivo" IS 'Meta de capital cerrado del mes, SIEMPRE en PEN (los montos USD se comparan convertidos con el TC semanal; jamas se suman monedas).';

COMMENT ON COLUMN "crm"."objetivos_legacy_archivo"."conversion_objetivo" IS 'Meta de conversion en porcentaje (0-100).';

CREATE TABLE IF NOT EXISTS "crm"."objetivos_vendedores_legacy_archivo" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "periodo" "date" NOT NULL,
    "vendedor_id" "uuid" NOT NULL,
    "supervisor_id" "uuid" NOT NULL,
    "capital_objetivo" numeric(14,2) DEFAULT 0 NOT NULL,
    "ventas_objetivo" integer DEFAULT 0 NOT NULL,
    "conversion_objetivo" numeric(5,2) DEFAULT 0 NOT NULL,
    "actualizado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "objetivos_vendedores_capital_rango" CHECK ((("capital_objetivo" >= (0)::numeric) AND ("capital_objetivo" <= (100000000)::numeric))),
    CONSTRAINT "objetivos_vendedores_conversion_rango" CHECK ((("conversion_objetivo" >= (0)::numeric) AND ("conversion_objetivo" <= (100)::numeric))),
    CONSTRAINT "objetivos_vendedores_periodo_mes" CHECK (("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp with time zone))::"date")),
    CONSTRAINT "objetivos_vendedores_personas_distintas" CHECK (("vendedor_id" <> "supervisor_id")),
    CONSTRAINT "objetivos_vendedores_ventas_rango" CHECK ((("ventas_objetivo" >= 0) AND ("ventas_objetivo" <= 1000)))
);

COMMENT ON TABLE "crm"."objetivos_vendedores_legacy_archivo" IS 'ARCHIVO NO CANONICO: metas individuales previas sin categoria ni USD. La fuente vigente es meta_periodos/metas_vendedor/metas_vendedor_detalle.';

COMMENT ON COLUMN "crm"."objetivos_vendedores_legacy_archivo"."supervisor_id" IS 'Supervisor resuelto desde crm.equipo por la RPC al guardar; el cliente no lo decide.';

CREATE TABLE IF NOT EXISTS "crm"."operaciones_cartera" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "vendedor_id" "uuid" NOT NULL,
    "tipo" "text" NOT NULL,
    "contrato_origen_id" "uuid",
    "contrato_nuevo_id" "uuid" NOT NULL,
    "fecha_operacion" "date" NOT NULL,
    "periodo" "date" NOT NULL,
    "moneda" "text" NOT NULL,
    "capital_renovado" numeric,
    "capital_adicional" numeric,
    "elegible_conversion" boolean NOT NULL,
    "desglose_completo" boolean DEFAULT true NOT NULL,
    "fuente" "text" NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "operaciones_cartera_forma" CHECK (((("tipo" = 'renovacion'::"text") AND (("desglose_completo" AND ("contrato_origen_id" IS NOT NULL) AND ("capital_renovado" > (0)::numeric) AND ("capital_adicional" >= (0)::numeric)) OR ((NOT "desglose_completo") AND ("fuente" = 'backfill_agosto_2026'::"text") AND ("contrato_origen_id" IS NULL) AND ("capital_renovado" IS NULL) AND ("capital_adicional" IS NULL)))) OR (("tipo" = 'upgrade'::"text") AND ("contrato_origen_id" IS NULL) AND ("capital_renovado" IS NULL) AND ("capital_adicional" IS NULL) AND "desglose_completo"))),
    CONSTRAINT "operaciones_cartera_fuente_check" CHECK (("fuente" = ANY (ARRAY['flujo_cartera'::"text", 'backfill_agosto_2026'::"text"]))),
    CONSTRAINT "operaciones_cartera_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "operaciones_cartera_periodo_check" CHECK (("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp with time zone))::"date")),
    CONSTRAINT "operaciones_cartera_periodo_fecha" CHECK (("periodo" = ("date_trunc"('month'::"text", ("fecha_operacion")::timestamp with time zone))::"date")),
    CONSTRAINT "operaciones_cartera_renovacion_convierte" CHECK ((("tipo" <> 'renovacion'::"text") OR "elegible_conversion")),
    CONSTRAINT "operaciones_cartera_tipo_check" CHECK (("tipo" = ANY (ARRAY['renovacion'::"text", 'upgrade'::"text"])))
);

COMMENT ON TABLE "crm"."operaciones_cartera" IS 'Ledger de renovaciones y upgrades. Congela asesor, periodo y desglose económico. Una fila es una operación; la conversión deduplica por (cliente, mes).';

COMMENT ON COLUMN "crm"."operaciones_cartera"."capital_adicional" IS 'Capital extra aportado al renovar. Se reporta/paga por separado y jamás agrega otra conversión.';

COMMENT ON COLUMN "crm"."operaciones_cartera"."elegible_conversion" IS 'Renovación=true. Upgrade=true solo si su periodo es posterior al mes del primer contrato del cliente.';

CREATE TABLE IF NOT EXISTS "crm"."origenes_capital_confirmados" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid",
    "cierre_externo_id" "uuid",
    "origen" "text" NOT NULL,
    "motivo" "text" NOT NULL,
    "confirmado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "fecha_comercial" "date" NOT NULL,
    CONSTRAINT "origenes_capital_confirmados_check" CHECK (("num_nonnulls"("contrato_id", "cierre_externo_id") = 1)),
    CONSTRAINT "origenes_capital_confirmados_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 10) AND ("length"("btrim"("motivo")) <= 500))),
    CONSTRAINT "origenes_capital_confirmados_origen_check" CHECK (("origen" = ANY (ARRAY['landing'::"text", 'formulario'::"text", 'formulario_3'::"text", 'referido'::"text", 'oficina'::"text"])))
);

COMMENT ON TABLE "crm"."origenes_capital_confirmados" IS 'Confirmaciones administrativas de canal para fuentes sin lead. SQL de mantenimiento autorizado, RLS deny-by-default; lectura exclusiva desde el ranking. No acredita conversiones ni altera el contrato.';

COMMENT ON COLUMN "crm"."origenes_capital_confirmados"."fecha_comercial" IS 'Fecha verificada de la fuente al confirmar, inmutable; determina el mes cuyo sello protege altas y desactivaciones.';

CREATE TABLE IF NOT EXISTS "crm"."periodos_cerrados" (
    "periodo" "date" NOT NULL,
    "cerrado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "cerrado_por" "uuid",
    "automatico" boolean DEFAULT true NOT NULL,
    "ponderacion_referido" numeric NOT NULL,
    "meta_revision" integer NOT NULL,
    "cobertura" "jsonb" NOT NULL,
    "ponderacion_renovacion" numeric,
    "tope_referidos_pct" numeric(5,2),
    CONSTRAINT "periodos_cerrados_automatico_check" CHECK ((("automatico" AND ("cerrado_por" IS NULL)) OR ((NOT "automatico") AND ("cerrado_por" IS NOT NULL)))),
    CONSTRAINT "periodos_cerrados_periodo_mes_check" CHECK (("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp with time zone))::"date")),
    CONSTRAINT "periodos_cerrados_ponderacion_referido_finito" CHECK ((("ponderacion_referido" IS NULL) OR (("ponderacion_referido" <> 'NaN'::numeric) AND ("ponderacion_referido" <> 'Infinity'::numeric) AND ("ponderacion_referido" <> '-Infinity'::numeric)))),
    CONSTRAINT "periodos_cerrados_ponderacion_renovacion_rango" CHECK ((("ponderacion_renovacion" IS NULL) OR (("ponderacion_renovacion" >= (0)::numeric) AND ("ponderacion_renovacion" <= (1)::numeric)))),
    CONSTRAINT "periodos_cerrados_tope_referidos_pct_check" CHECK ((("tope_referidos_pct" IS NULL) OR (("tope_referidos_pct" >= (0)::numeric) AND ("tope_referidos_pct" <= (100)::numeric))))
);

COMMENT ON TABLE "crm"."periodos_cerrados" IS 'Meses cerrados: a partir del sello, el resultado del mes deja de recalcularse y se sirve la foto. Append-only y SIN operacion de reabrir, por decision de Miguel (2026-08-14): un mes pagado no se reescribe; lo que haya que corregir se descuenta en el mes vivo.';

COMMENT ON COLUMN "crm"."periodos_cerrados"."cerrado_por" IS 'NULL cuando lo cerro el ciclo automatico del dia 10 (el camino normal).';

COMMENT ON COLUMN "crm"."periodos_cerrados"."automatico" IS 'true = se sello sin sesion de usuario, que es como llega el ciclo diario (y como llegaria cualquier proceso con service_role). No es prueba de que lo hiciera el cron; para autoria humana, cerrado_por.';

COMMENT ON COLUMN "crm"."periodos_cerrados"."cobertura" IS 'La cobertura publicada ese mes (medible / motivo / suelo). Se sella porque forma parte de como se leyo el numero.';

COMMENT ON COLUMN "crm"."periodos_cerrados"."ponderacion_renovacion" IS 'Peso de la RENOVACION con el que se calculo esta foto mensual. Se guarda desde el 23/09/2026; antes solo se guardaba ponderacion_referido y el de renovacion se reconstruia a partir de el, lo que dejaba de ser cierto en cuanto los dos pesos se separaron. NULL = foto sellada antes de que existiera esta columna, que no es lo mismo que un peso de cero: quien lea decide el respaldo. Una foto NO se reescribe.';

COMMENT ON COLUMN "crm"."periodos_cerrados"."tope_referidos_pct" IS 'Tope de referidos con el que se calculó el mes al sellarlo (la foto es la memoria de la regla con la que se pagó). NULL = el mes se selló sin tope.';

CREATE TABLE IF NOT EXISTS "crm"."piloto_f8_control" (
    "singleton" boolean DEFAULT true NOT NULL,
    "activo" boolean DEFAULT false NOT NULL,
    "revision" bigint DEFAULT 0 NOT NULL,
    "inicia_en" timestamp with time zone,
    "vence_en" timestamp with time zone,
    "motivo" "text",
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "actualizado_por" "uuid",
    CONSTRAINT "piloto_f8_control_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "piloto_f8_control_check" CHECK (((("inicia_en" IS NULL) AND ("vence_en" IS NULL)) OR (("inicia_en" IS NOT NULL) AND ("vence_en" IS NOT NULL) AND ("inicia_en" < "vence_en")))),
    CONSTRAINT "piloto_f8_control_motivo_check" CHECK ((("motivo" IS NULL) OR (("length"("btrim"("motivo")) >= 8) AND ("length"("btrim"("motivo")) <= 500)))),
    CONSTRAINT "piloto_f8_control_revision_check" CHECK (("revision" >= 0)),
    CONSTRAINT "piloto_f8_control_singleton_check" CHECK ("singleton")
);

COMMENT ON TABLE "crm"."piloto_f8_control" IS 'F8: interruptor administrativo único del piloto económico. Nace OFF; sin permisos Data API. El apagado detiene capacidades nuevas y conserva todos los hechos.';

CREATE TABLE IF NOT EXISTS "crm"."piloto_f8_miembros" (
    "perfil_id" "uuid" NOT NULL,
    "rol_esperado" "text" NOT NULL,
    "activo" boolean DEFAULT true NOT NULL,
    "habilitado_desde" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "vence_en" timestamp with time zone NOT NULL,
    "motivo" "text" NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "actualizado_por" "uuid",
    CONSTRAINT "piloto_f8_miembros_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "piloto_f8_miembros_check" CHECK ((("habilitado_desde" < "vence_en") AND (("vence_en" - "habilitado_desde") <= '30 days'::interval))),
    CONSTRAINT "piloto_f8_miembros_habilitado_desde_check" CHECK ("isfinite"("habilitado_desde")),
    CONSTRAINT "piloto_f8_miembros_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 8) AND ("length"("btrim"("motivo")) <= 500))),
    CONSTRAINT "piloto_f8_miembros_rol_esperado_check" CHECK (("rol_esperado" = ANY (ARRAY['gerencia'::"text", 'supervisor'::"text", 'vendedor'::"text"]))),
    CONSTRAINT "piloto_f8_miembros_vence_en_check" CHECK ("isfinite"("vence_en"))
);

COMMENT ON TABLE "crm"."piloto_f8_miembros" IS 'F8: cuatro participantes nominales y temporales del piloto (Gerencia, un supervisor y dos vendedores). La membresía CRM vigente se revalida en cada llamada.';

CREATE TABLE IF NOT EXISTS "crm"."plazos_carga_mes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "periodo" "date" NOT NULL,
    "ultimo_dia" "date" NOT NULL,
    "plazo_hasta" timestamp with time zone NOT NULL,
    "motivo" "text" NOT NULL,
    "decidido_por" "uuid" NOT NULL,
    "decidido_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "reapertura_id" "uuid",
    CONSTRAINT "plazos_carga_mes_motivo_check" CHECK ((("motivo" = "private"."motivo_normalizado"("motivo")) AND (("char_length"("motivo") >= 5) AND ("char_length"("motivo") <= 300)))),
    CONSTRAINT "plazos_carga_mes_periodo_check" CHECK (("isfinite"("periodo") AND ("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp without time zone))::"date"))),
    CONSTRAINT "plazos_carga_mes_plazo_check" CHECK (("plazo_hasta" = ((("ultimo_dia" + 1))::timestamp without time zone AT TIME ZONE 'America/Lima'::"text"))),
    CONSTRAINT "plazos_carga_mes_plazo_minimo_check" CHECK (("plazo_hasta" >= "private"."conversion_plazo_base"("periodo"))),
    CONSTRAINT "plazos_carga_mes_ultimo_dia_check" CHECK ("isfinite"("ultimo_dia"))
);

COMMENT ON TABLE "crm"."plazos_carga_mes" IS 'Decisiones de Gerencia sobre el plazo de carga de un mes (crm.fijar_plazo_carga_mes). Vale la última por mes (private.conversion_plazo_hasta); sin decisión, la base (día 11 del mes siguiente, 00:00 de Lima). Append-only, sin grants ni políticas. Sin negocio_id: el cierre de mes del CRM no tiene inquilino (igual que crm.periodos_cerrados).';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."id" IS 'Identificador de la decisión.';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."periodo" IS 'Mes al que se fija el plazo (primer día del mes).';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."ultimo_dia" IS 'Último día incluido en el plazo (fecha de Lima).';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."plazo_hasta" IS 'Fin del plazo, extremo EXCLUIDO: 00:00 de Lima del día siguiente a ultimo_dia. Nunca antes de la base del mes.';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."motivo" IS 'Motivo escrito por Gerencia (5 a 300 caracteres, sin blancos en los extremos).';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."decidido_por" IS 'Perfil de Gerencia que decidió (auth.uid() de la sesión, nunca un parámetro).';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."decidido_en" IS 'Cuándo se decidió; ordena las decisiones (vale la última).';

COMMENT ON COLUMN "crm"."plazos_carga_mes"."reapertura_id" IS 'Reapertura que acompañó a la decisión, si el mes estaba sellado (mismo mes).';

CREATE TABLE IF NOT EXISTS "crm"."politica_abandono" (
    "singleton" boolean DEFAULT true NOT NULL,
    "dias_abandono" integer NOT NULL,
    "dias_auto_bolsa" integer NOT NULL,
    "actualizado_por" "uuid",
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "politica_abandono_dias_abandono_check" CHECK ((("dias_abandono" >= 1) AND ("dias_abandono" <= 365))),
    CONSTRAINT "politica_abandono_dias_auto_bolsa_check" CHECK ((("dias_auto_bolsa" >= 1) AND ("dias_auto_bolsa" <= 365))),
    CONSTRAINT "politica_abandono_singleton_check" CHECK ("singleton")
);

COMMENT ON TABLE "crm"."politica_abandono" IS 'Perillas del plan lead libre, editables solo por gerencia. dias_abandono (Y): días sin CONVERSACIÓN real (TIPOS_CONVERSACION) medidos ante el dueño ACTUAL — greatest(última conversación, tenencia_desde) — para considerar abandonado un lead tomado. dias_auto_bolsa (X): días de alerta de abandono ignorada antes de que el barrido lo baje a la bolsa. El motor que las consume llega en F4/F5; nacen antes para que la fuente sea única.';

COMMENT ON COLUMN "crm"."politica_abandono"."dias_abandono" IS 'Y — el reloj JAMÁS se resetea con intentos (llamada no contestada, whatsapp enviado): solo conversaciones reales. Decisión de Miguel 2026-08-16.';

COMMENT ON COLUMN "crm"."politica_abandono"."dias_auto_bolsa" IS 'X — «confirmar seguimiento» del supervisor NO lo detiene: solo una conversación real posterior. Decisión de Miguel 2026-08-16.';

CREATE TABLE IF NOT EXISTS "crm"."postventa_escrituras" (
    "transaccion" "xid8" NOT NULL,
    "tarea_id" "uuid" NOT NULL
);

CREATE TABLE IF NOT EXISTS "crm"."postventa_operaciones" (
    "actor_id" "uuid" NOT NULL,
    "clave" "uuid" NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "comando" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "respuesta" "jsonb",
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "postventa_operaciones_payload_check" CHECK (("jsonb_typeof"("payload") = 'object'::"text"))
);

CREATE TABLE IF NOT EXISTS "crm"."postventa_retiros" (
    "id" "uuid" NOT NULL,
    "inversionista_id" "uuid" NOT NULL,
    "fuente_id" "uuid" NOT NULL,
    "empresa" "text" NOT NULL,
    "estado" "text" DEFAULT 'solicitada'::"text" NOT NULL,
    "motivo" "text" NOT NULL,
    "resolucion" "text",
    "revision" integer DEFAULT 1 NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "revisado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "postventa_retiros_empresa_check" CHECK (("empresa" = ANY (ARRAY['qorilazo'::"text", 'prodelco'::"text"]))),
    CONSTRAINT "postventa_retiros_estado_check" CHECK (("estado" = ANY (ARRAY['solicitada'::"text", 'en_revision'::"text", 'revisada'::"text", 'rechazada'::"text", 'cancelada'::"text"]))),
    CONSTRAINT "postventa_retiros_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 3) AND ("length"("btrim"("motivo")) <= 2000))),
    CONSTRAINT "postventa_retiros_resolucion_check" CHECK ((("length"("btrim"("resolucion")) >= 3) AND ("length"("btrim"("resolucion")) <= 2000))),
    CONSTRAINT "postventa_retiros_revision_check" CHECK (("revision" >= 1))
);

CREATE TABLE IF NOT EXISTS "crm"."producto_condiciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "version_id" "uuid" NOT NULL,
    "orden" integer NOT NULL,
    "categoria" "text",
    "moneda" "text" NOT NULL,
    "plazo_meses" integer,
    "modalidad" "text" NOT NULL,
    "tipo_interes" "text" NOT NULL,
    "capital_minimo" numeric(14,2) NOT NULL,
    "capital_maximo" numeric(14,2) NOT NULL,
    "tasa_referencia" numeric(7,4) NOT NULL,
    "tasa_minima" numeric(7,4) NOT NULL,
    "tasa_maxima" numeric(7,4) NOT NULL,
    "activa" boolean DEFAULT true NOT NULL,
    "es_legacy" boolean DEFAULT false NOT NULL,
    "legacy_contrato_id" "uuid",
    "fecha_inicio_legacy" "date",
    "fecha_vencimiento_legacy" "date",
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "retirada_por" "uuid",
    "retirada_en" timestamp with time zone,
    CONSTRAINT "producto_condiciones_activa_check" CHECK ((("activa" AND ("retirada_en" IS NULL) AND ("retirada_por" IS NULL)) OR ((NOT "activa") AND ("retirada_en" IS NOT NULL)))),
    CONSTRAINT "producto_condiciones_capital_check" CHECK (((("capital_minimo" >= (100)::numeric) AND ("capital_minimo" <= (100000000)::numeric)) AND (("capital_maximo" >= "capital_minimo") AND ("capital_maximo" <= (100000000)::numeric)))),
    CONSTRAINT "producto_condiciones_categoria_check" CHECK (("categoria" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"]))),
    CONSTRAINT "producto_condiciones_compuesto_cronograma_check" CHECK (("es_legacy" OR ("tipo_interes" = 'simple'::"text") OR (("modalidad" = 'anual'::"text") AND ("plazo_meses" >= 12) AND (("plazo_meses" % 12) = 0)))),
    CONSTRAINT "producto_condiciones_legacy_check" CHECK ((("es_legacy" AND ("legacy_contrato_id" IS NOT NULL) AND ("plazo_meses" IS NULL) AND ("fecha_inicio_legacy" IS NOT NULL) AND ("fecha_vencimiento_legacy" IS NOT NULL)) OR ((NOT "es_legacy") AND ("legacy_contrato_id" IS NULL) AND ("categoria" IS NOT NULL) AND (("plazo_meses" >= 1) AND ("plazo_meses" <= 600)) AND ("fecha_inicio_legacy" IS NULL) AND ("fecha_vencimiento_legacy" IS NULL)))),
    CONSTRAINT "producto_condiciones_modalidad_check" CHECK (("modalidad" = ANY (ARRAY['mensual'::"text", 'trimestral'::"text", 'semestral'::"text", 'anual'::"text"]))),
    CONSTRAINT "producto_condiciones_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "producto_condiciones_orden_check" CHECK (("orden" > 0)),
    CONSTRAINT "producto_condiciones_tasa_check" CHECK ((("tasa_minima" > (0)::numeric) AND ("tasa_minima" <= "tasa_referencia") AND ("tasa_referencia" <= "tasa_maxima") AND ("tasa_maxima" <= (50)::numeric))),
    CONSTRAINT "producto_condiciones_tipo_interes_check" CHECK (("tipo_interes" = ANY (ARRAY['simple'::"text", 'compuesto'::"text"])))
);

COMMENT ON TABLE "crm"."producto_condiciones" IS 'Combinaciones normalizadas de categoría, moneda, plazo, modalidad, capital y tasa. Las retiradas se conservan.';

COMMENT ON COLUMN "crm"."producto_condiciones"."tasa_referencia" IS 'Referencia comercial; el contrato conserva por separado la tasa efectiva pactada.';

CREATE TABLE IF NOT EXISTS "crm"."producto_versiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "producto_id" "uuid" NOT NULL,
    "numero_version" integer NOT NULL,
    "estado" "text" DEFAULT 'borrador'::"text" NOT NULL,
    "nombre" "text" NOT NULL,
    "descripcion" "text",
    "vigente_desde" "date" NOT NULL,
    "vigente_hasta" "date",
    "revision" bigint DEFAULT 1 NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_por" "uuid",
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "publicada_por" "uuid",
    "publicada_en" timestamp with time zone,
    "retirada_por" "uuid",
    "retirada_en" timestamp with time zone,
    CONSTRAINT "producto_versiones_descripcion_check" CHECK ((("descripcion" IS NULL) OR ("length"("descripcion") <= 2000))),
    CONSTRAINT "producto_versiones_estado_check" CHECK (("estado" = ANY (ARRAY['borrador'::"text", 'publicada'::"text", 'retirada'::"text"]))),
    CONSTRAINT "producto_versiones_estado_coherente" CHECK (((("estado" = 'borrador'::"text") AND ("publicada_en" IS NULL) AND ("publicada_por" IS NULL) AND ("retirada_en" IS NULL) AND ("retirada_por" IS NULL)) OR (("estado" = 'publicada'::"text") AND ("publicada_en" IS NOT NULL) AND ("retirada_en" IS NULL) AND ("retirada_por" IS NULL)) OR (("estado" = 'retirada'::"text") AND ("retirada_en" IS NOT NULL)))),
    CONSTRAINT "producto_versiones_nombre_check" CHECK ((("length"("btrim"("nombre")) >= 3) AND ("length"("btrim"("nombre")) <= 160))),
    CONSTRAINT "producto_versiones_numero_version_check" CHECK (("numero_version" > 0)),
    CONSTRAINT "producto_versiones_revision_check" CHECK (("revision" > 0)),
    CONSTRAINT "producto_versiones_vigencia_check" CHECK ((("vigente_hasta" IS NULL) OR ("vigente_hasta" >= "vigente_desde")))
);

COMMENT ON TABLE "crm"."producto_versiones" IS 'Versión comercial. Solo borrador puede editarse; publicada y retirada son snapshots inmutables.';

CREATE TABLE IF NOT EXISTS "crm"."productos_inversion" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "codigo" "text" NOT NULL,
    "estado" "text" DEFAULT 'activo'::"text" NOT NULL,
    "revision" bigint DEFAULT 1 NOT NULL,
    "es_legacy" boolean DEFAULT false NOT NULL,
    "permite_altas_legacy" boolean DEFAULT false NOT NULL,
    "creado_por" "uuid",
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_por" "uuid",
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "archivado_por" "uuid",
    "archivado_en" timestamp with time zone,
    CONSTRAINT "productos_inversion_archivo_coherente" CHECK (((("estado" = 'activo'::"text") AND ("archivado_en" IS NULL) AND ("archivado_por" IS NULL)) OR (("estado" = 'archivado'::"text") AND ("archivado_en" IS NOT NULL)))),
    CONSTRAINT "productos_inversion_codigo_formato" CHECK ((("codigo" = "upper"("btrim"("codigo"))) AND ("codigo" ~ '^[A-Z0-9][A-Z0-9._-]{1,39}$'::"text"))),
    CONSTRAINT "productos_inversion_compatibilidad_check" CHECK (((NOT "permite_altas_legacy") OR "es_legacy")),
    CONSTRAINT "productos_inversion_estado_check" CHECK (("estado" = ANY (ARRAY['activo'::"text", 'archivado'::"text"]))),
    CONSTRAINT "productos_inversion_legacy_archivado" CHECK (((NOT "es_legacy") OR ("estado" = 'archivado'::"text"))),
    CONSTRAINT "productos_inversion_revision_check" CHECK (("revision" > 0))
);

COMMENT ON TABLE "crm"."productos_inversion" IS 'Identidad estable de un producto de inversión. Se archiva; nunca se borra ni se recicla su código.';

COMMENT ON COLUMN "crm"."productos_inversion"."revision" IS 'Control optimista del agregado producto para RPCs expected_revision.';

COMMENT ON COLUMN "crm"."productos_inversion"."es_legacy" IS 'Producto técnico ocultable usado únicamente para snapshots de contratos sin catálogo previo.';

COMMENT ON COLUMN "crm"."productos_inversion"."permite_altas_legacy" IS 'Puente temporal e irreversible: permite callers antiguos sin condición hasta que CRM y portal migren a los wrappers catalogados.';

CREATE TABLE IF NOT EXISTS "crm"."reaperturas_mes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "periodo" "date" NOT NULL,
    "motivo" "text" NOT NULL,
    "decidido_por" "uuid" NOT NULL,
    "reabierto_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "transaccion" "xid8" DEFAULT "pg_current_xact_id"() NOT NULL,
    "respaldo" "jsonb" NOT NULL,
    "resumen" "jsonb" NOT NULL,
    CONSTRAINT "reaperturas_mes_motivo_check" CHECK ((("motivo" = "private"."motivo_normalizado"("motivo")) AND (("char_length"("motivo") >= 5) AND ("char_length"("motivo") <= 300)))),
    CONSTRAINT "reaperturas_mes_periodo_check" CHECK (("isfinite"("periodo") AND ("periodo" = ("date_trunc"('month'::"text", ("periodo")::timestamp without time zone))::"date"))),
    CONSTRAINT "reaperturas_mes_respaldo_check" CHECK ((("jsonb_typeof"("respaldo") = 'object'::"text") AND ("respaldo" ?& ARRAY['sello'::"text", 'foto'::"text", 'acreditaciones'::"text", 'rastros_tardios'::"text", 'cierres_externos'::"text"]))),
    CONSTRAINT "reaperturas_mes_resumen_check" CHECK (("jsonb_typeof"("resumen") = 'object'::"text"))
);

COMMENT ON TABLE "crm"."reaperturas_mes" IS 'Reaperturas de un mes sellado decididas por Gerencia (crm.fijar_plazo_carga_mes → private.reabrir_mes). Una fila por reapertura con el respaldo completo de lo que se retiró o cambió. Append-only, sin grants ni políticas. La fila ES la autorización de los candados del cierre (private.reapertura_autoriza), solo para su mes y su transacción. Sin negocio_id: el cierre de mes del CRM no tiene inquilino (igual que crm.periodos_cerrados).';

COMMENT ON COLUMN "crm"."reaperturas_mes"."id" IS 'Identificador de la reapertura.';

COMMENT ON COLUMN "crm"."reaperturas_mes"."periodo" IS 'Mes reabierto (primer día del mes).';

COMMENT ON COLUMN "crm"."reaperturas_mes"."motivo" IS 'Motivo escrito por Gerencia (5 a 300 caracteres, sin blancos en los extremos).';

COMMENT ON COLUMN "crm"."reaperturas_mes"."decidido_por" IS 'Perfil de Gerencia que reabrió el mes (auth.uid() de la sesión, nunca un parámetro).';

COMMENT ON COLUMN "crm"."reaperturas_mes"."reabierto_en" IS 'Cuándo se reabrió: el instante de inicio de la transacción que reabrió (lo fija el trigger; parte de la llave).';

COMMENT ON COLUMN "crm"."reaperturas_mes"."transaccion" IS 'Transacción que reabrió el mes (la fija el trigger, no quien inserta): con reabierto_en, la llave de private.reapertura_autoriza. La pareja (transaccion, reabierto_en) es única: una reapertura por transacción superior.';

COMMENT ON COLUMN "crm"."reaperturas_mes"."respaldo" IS 'Estado ANTES de reabrir: sello, foto[], acreditaciones[] del mes, rastros_tardios[] retirados y cierres_externos[] devueltos (estos SIN documento ni nombre del cliente). Queda también en public.audit_log.';

COMMENT ON COLUMN "crm"."reaperturas_mes"."resumen" IS 'Resumen de la reapertura: foto retirada, acreditaciones respaldadas/liberadas/incluidas, rastros retirados y ventas devueltas.';

CREATE TABLE IF NOT EXISTS "crm"."reasignaciones_analista" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "analista_de" "uuid",
    "analista_a" "uuid" NOT NULL,
    "motivo" "text" NOT NULL,
    "reasignado_por" "uuid" NOT NULL,
    "reasignado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "reasignaciones_cambia_de_verdad" CHECK (("analista_de" IS DISTINCT FROM "analista_a")),
    CONSTRAINT "reasignaciones_motivo_no_vacio" CHECK ((("btrim"("motivo") <> ''::"text") AND ("length"("motivo") <= 300)))
);

COMMENT ON TABLE "crm"."reasignaciones_analista" IS 'Rastro de cada cambio de atribucion de una venta (P-055 Fase 3). Append-only: quien la tenia, quien la tiene, por que y quien lo hizo.';

CREATE TABLE IF NOT EXISTS "crm"."recordatorios_disponibilidad" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "perfil_id" "uuid" NOT NULL,
    "telefono" "text" NOT NULL,
    "dni" "text",
    "recordar_en" timestamp with time zone NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "recordatorios_disponibilidad_creado_en_check" CHECK ("isfinite"("creado_en")),
    CONSTRAINT "recordatorios_disponibilidad_dni_check" CHECK (("dni" ~ '^[0-9]{8}$'::"text")),
    CONSTRAINT "recordatorios_disponibilidad_recordar_en_check" CHECK ("isfinite"("recordar_en")),
    CONSTRAINT "recordatorios_disponibilidad_telefono_check" CHECK (("telefono" ~ '^\+519[0-9]{8}$'::"text"))
);

COMMENT ON TABLE "crm"."recordatorios_disponibilidad" IS 'F3 lead libre (spec §5.3-§5.5): recordatorio PERSONAL del vendedor para re-verificar un contacto ocupado cuando venza su protección. Anclado al CONTACTO (teléfono normalizado), SIN FK a leads a propósito: no reserva, no prioriza, no es actividad comercial, no toca el timeline ni el reloj de inactividad (spec §10 caso 6). Owner-only por RLS; DELETE permitido como excepción documentada (nota personal efímera + minimización). Los vencidos >7 días caducan solos (pg_cron crm-recordatorios-caducidad). La campana del front re-verifica BAJO DEMANDA al clic: esta tabla jamás guarda veredictos. Como TODA tabla crm.* auditada, su rastro en public.audit_log es legible por admin/superadmin del portal (vía preexistente, misma frase que F1) — el owner-only gobierna la tabla viva, no exime del rastro administrativo.';

COMMENT ON COLUMN "crm"."recordatorios_disponibilidad"."telefono" IS 'Normalizado +519######## por trigger (private.normalizar_telefono) — la misma llave de contacto que verificar/tomar.';

COMMENT ON COLUMN "crm"."recordatorios_disponibilidad"."recordar_en" IS 'Cuándo revisar. Futuro en el momento de escribir, tope 365 días (trigger); finito por CHECK (el veneno infinity de PG17 no entra).';

CREATE TABLE IF NOT EXISTS "crm"."recorrido_control" (
    "id" boolean DEFAULT true NOT NULL,
    "modo" "text" DEFAULT 'observacion'::"text" NOT NULL,
    "cohorte_desde" timestamp with time zone,
    "revision" integer DEFAULT 1 NOT NULL,
    "motivo" "text" DEFAULT 'Instalacion en observacion'::"text" NOT NULL,
    "actualizado_por" "uuid",
    "actualizado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "recorrido_control_actualizado_en_check" CHECK ("isfinite"("actualizado_en")),
    CONSTRAINT "recorrido_control_check" CHECK ((("modo" <> 'exigir'::"text") OR ("cohorte_desde" IS NOT NULL))),
    CONSTRAINT "recorrido_control_cohorte_desde_check" CHECK ("isfinite"("cohorte_desde")),
    CONSTRAINT "recorrido_control_id_check" CHECK ("id"),
    CONSTRAINT "recorrido_control_modo_check" CHECK (("modo" = ANY (ARRAY['apagado'::"text", 'observacion'::"text", 'exigir'::"text"]))),
    CONSTRAINT "recorrido_control_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 8) AND ("length"("btrim"("motivo")) <= 1000))),
    CONSTRAINT "recorrido_control_revision_check" CHECK (("revision" > 0))
);

COMMENT ON TABLE "crm"."recorrido_control" IS 'Estado administrativo de esta instalacion, no un tenant ni una empresa de inversion. Corte inmutable; auditoria before/after existente. Solo puerta gerencial.';

COMMENT ON COLUMN "crm"."recorrido_control"."cohorte_desde" IS 'Inicio inmutable de la primera exigencia global. No exime leads o ciclos anteriores; nombre conservado por compatibilidad con la API publicada.';

CREATE TABLE IF NOT EXISTS "crm"."rentabilidad_hitos" (
    "clave" "text" NOT NULL,
    "valor" "jsonb" NOT NULL,
    "registrado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "rentabilidad_hitos_clave_check" CHECK (("clave" ~ '^[a-z_]{3,60}$'::"text")),
    CONSTRAINT "rentabilidad_hitos_valor_check" CHECK (("jsonb_typeof"("valor") = 'object'::"text"))
);

COMMENT ON TABLE "crm"."rentabilidad_hitos" IS 'Rentabilidad R2. Hitos del sistema de rentabilidad: observacion_activa_desde (desde cuándo toda alta debe tener su observación; se fija DESPUÉS de montar el observador, bajo su candado) y observacion_desactivada_en (lo escribe la reversa). La tabla SOBREVIVE a la reversa de R2 (rastro); solo la escriben migraciones y reversas.';

CREATE TABLE IF NOT EXISTS "crm"."sla_operacion_control" (
    "id" boolean DEFAULT true NOT NULL,
    "modo" "text" DEFAULT 'legado'::"text" NOT NULL,
    "revision" integer DEFAULT 0 NOT NULL,
    "primera_activacion_en" timestamp with time zone,
    "politica_adopcion_id" "uuid",
    "cambiado_por" "uuid",
    "cambiado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "sla_operacion_control_cambiado_en_check" CHECK ("isfinite"("cambiado_en")),
    CONSTRAINT "sla_operacion_control_check" CHECK ((("primera_activacion_en" IS NULL) = ("politica_adopcion_id" IS NULL))),
    CONSTRAINT "sla_operacion_control_check1" CHECK ((("modo" <> 'activo'::"text") OR ("primera_activacion_en" IS NOT NULL))),
    CONSTRAINT "sla_operacion_control_id_check" CHECK ("id"),
    CONSTRAINT "sla_operacion_control_modo_check" CHECK (("modo" = ANY (ARRAY['legado'::"text", 'observacion'::"text", 'activo'::"text"]))),
    CONSTRAINT "sla_operacion_control_primera_activacion_en_check" CHECK ("isfinite"("primera_activacion_en")),
    CONSTRAINT "sla_operacion_control_revision_check" CHECK (("revision" >= 0))
);

COMMENT ON TABLE "crm"."sla_operacion_control" IS 'SLA-R2: control inicial legado. N1 no expone una puerta de activacion.';

CREATE TABLE IF NOT EXISTS "crm"."sla_operacion_recibos" (
    "actor_id" "uuid" NOT NULL,
    "operacion_id" "uuid" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "sujeto_id" "uuid" NOT NULL,
    "comando" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "respuesta" "jsonb",
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "confirmado_en" timestamp with time zone,
    CONSTRAINT "sla_operacion_recibos_check" CHECK ((("respuesta" IS NULL) = ("confirmado_en" IS NULL))),
    CONSTRAINT "sla_operacion_recibos_comando_check" CHECK (("comando" = ANY (ARRAY['registrar_actividad'::"text", 'cerrar_tarea'::"text", 'cerrar_reunion'::"text", 'reprogramar_reunion'::"text", 'reprogramar_tarea'::"text"]))),
    CONSTRAINT "sla_operacion_recibos_payload_check" CHECK (("jsonb_typeof"("payload") = 'object'::"text")),
    CONSTRAINT "sla_operacion_recibos_respuesta_check" CHECK (("jsonb_typeof"("respuesta") = 'object'::"text"))
);

CREATE TABLE IF NOT EXISTS "crm"."sla_politica_etapas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "politica_id" "uuid" NOT NULL,
    "etapa" "text" NOT NULL,
    "maximo_minutos" integer NOT NULL,
    CONSTRAINT "sla_politica_etapas_etapa_check" CHECK (("etapa" = ANY (ARRAY['nuevo'::"text", 'contactado'::"text", 'reunion_agendada'::"text", 'propuesta_enviada'::"text"]))),
    CONSTRAINT "sla_politica_etapas_maximo_minutos_check" CHECK ((("maximo_minutos" >= 1) AND ("maximo_minutos" <= 43200)))
);

CREATE TABLE IF NOT EXISTS "crm"."sla_politica_etapas_operacion" (
    "politica_id" "uuid" NOT NULL,
    "etapa" "text" NOT NULL,
    "seguimiento_minutos" integer NOT NULL,
    "prorroga_minutos" integer NOT NULL,
    "prorroga_max" integer NOT NULL,
    "tope_extra_minutos" integer NOT NULL,
    "pausa_habilitada" boolean NOT NULL,
    "pausa_margen_minutos" integer NOT NULL,
    CONSTRAINT "sla_politica_etapas_operacion_check" CHECK ((("prorroga_minutos" = 0) = ("prorroga_max" = 0))),
    CONSTRAINT "sla_politica_etapas_operacion_check1" CHECK ((("prorroga_max" = 0) OR ("tope_extra_minutos" > 0))),
    CONSTRAINT "sla_politica_etapas_operacion_check2" CHECK ((("etapa" = ANY (ARRAY['contactado'::"text", 'propuesta_enviada'::"text"])) OR ("prorroga_max" = 0))),
    CONSTRAINT "sla_politica_etapas_operacion_check3" CHECK (("pausa_habilitada" OR ("pausa_margen_minutos" = 0))),
    CONSTRAINT "sla_politica_etapas_operacion_pausa_margen_minutos_check" CHECK ((("pausa_margen_minutos" >= 0) AND ("pausa_margen_minutos" <= 10080))),
    CONSTRAINT "sla_politica_etapas_operacion_prorroga_max_check" CHECK ((("prorroga_max" >= 0) AND ("prorroga_max" <= 5))),
    CONSTRAINT "sla_politica_etapas_operacion_prorroga_minutos_check" CHECK ((("prorroga_minutos" = 0) OR (("prorroga_minutos" >= 1441) AND ("prorroga_minutos" <= 43200)))),
    CONSTRAINT "sla_politica_etapas_operacion_seguimiento_minutos_check" CHECK ((("seguimiento_minutos" >= 1) AND ("seguimiento_minutos" <= 43200))),
    CONSTRAINT "sla_politica_etapas_operacion_tope_extra_minutos_check" CHECK ((("tope_extra_minutos" >= 0) AND ("tope_extra_minutos" <= 43200)))
);

COMMENT ON TABLE "crm"."sla_politica_etapas_operacion" IS 'SLA-R2: reglas de una version publicada. N1 no publica ninguna; solo lectura por el nucleo.';

CREATE TABLE IF NOT EXISTS "crm"."solicitudes_desechadas_corridas" (
    "id" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "corte" timestamp with time zone NOT NULL,
    "dias" integer NOT NULL,
    "limite" integer NOT NULL,
    "canceladas_numero_usado" integer NOT NULL,
    "canceladas_sin_movimiento" integer NOT NULL,
    "omitidas" integer NOT NULL,
    "rechazadas" integer NOT NULL,
    "detalle" "jsonb" NOT NULL,
    "duracion_ms" integer NOT NULL,
    CONSTRAINT "solicitudes_desechadas_corridas_canceladas_numero_usado_check" CHECK (("canceladas_numero_usado" >= 0)),
    CONSTRAINT "solicitudes_desechadas_corridas_canceladas_sin_movimiento_check" CHECK (("canceladas_sin_movimiento" >= 0)),
    CONSTRAINT "solicitudes_desechadas_corridas_detalle_check" CHECK (("jsonb_typeof"("detalle") = 'array'::"text")),
    CONSTRAINT "solicitudes_desechadas_corridas_dias_check" CHECK (("dias" >= 1)),
    CONSTRAINT "solicitudes_desechadas_corridas_duracion_ms_check" CHECK (("duracion_ms" >= 0)),
    CONSTRAINT "solicitudes_desechadas_corridas_limite_check" CHECK (("limite" >= 1)),
    CONSTRAINT "solicitudes_desechadas_corridas_omitidas_check" CHECK (("omitidas" >= 0)),
    CONSTRAINT "solicitudes_desechadas_corridas_rechazadas_check" CHECK (("rechazadas" >= 0)),
    CONSTRAINT "solicitudes_desechadas_corridas_tiempos_finitos" CHECK (("isfinite"("creado_en") AND "isfinite"("corte")))
);

COMMENT ON TABLE "crm"."solicitudes_desechadas_corridas" IS 'Rastro de cada corrida de private.solicitudes_desechar_ciclo (bloque 2.15: el CRM cancela solo las solicitudes de inversión que ya no corresponden; D-58, D-59, D-63): cuántas canceló por número de contrato ya usado y por 30 días sin movimiento, cuántas omitió (guardas o fila ocupada) y cuántas rechazó un disparador, con el detalle por solicitud. Append-only; sin grants para la API; sin columna de empresa (CRM de una sola empresa, excepción documentada).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."id" IS 'Identificador de la corrida; viaja en cancelacion_detalle.corrida_id de cada solicitud cancelada.';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."creado_en" IS 'Cuándo terminó la corrida.';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."corte" IS 'Instante de corte con el que se evaluó «sin movimiento» (p_corte).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."dias" IS 'Días sin movimiento exigidos (30, D-63).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."limite" IS 'Presupuesto de cancelaciones por corrida (200), compartido por las dos pasadas; las omitidas y rechazadas no lo consumen.';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."canceladas_numero_usado" IS 'Canceladas por número de contrato ya usado por otro contrato (pasada 1).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."canceladas_sin_movimiento" IS 'Canceladas por 30 días sin confirmarse ni corregirse (pasada 2).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."omitidas" IS 'Candidatas que no se tocaron: una guarda bajo el candado o fila ocupada por otra sesión.';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."rechazadas" IS 'Candidatas cuya cancelación rechazó un disparador de la tabla (quedaron como estaban).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."detalle" IS 'Lista: por solicitud candidata, su id, el motivo evaluado y el resultado (cancelada | omitida: … | rechazada: …).';

COMMENT ON COLUMN "crm"."solicitudes_desechadas_corridas"."duracion_ms" IS 'Duración de la corrida en milisegundos.';

CREATE TABLE IF NOT EXISTS "crm"."solicitudes_tasa" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "politica_id" "uuid" NOT NULL,
    "cliente_id" "uuid",
    "categoria" "text" NOT NULL,
    "contrato_origen_id" "uuid",
    "contrato_origen_numero" "text",
    "producto_condicion_id" "uuid",
    "capital" numeric NOT NULL,
    "moneda" "text" NOT NULL,
    "modalidad" "text" NOT NULL,
    "tipo_interes" "text" NOT NULL,
    "fecha_inicio" "date" NOT NULL,
    "fecha_vencimiento" "date" NOT NULL,
    "huella" "text" NOT NULL,
    "tasa_base" numeric NOT NULL,
    "regla_base" "text" NOT NULL,
    "contratos_previos" integer DEFAULT 0 NOT NULL,
    "prioridad_bandeja" boolean DEFAULT false NOT NULL,
    "tasa_solicitada" numeric NOT NULL,
    "motivo" "text" NOT NULL,
    "estado" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "tasa_maxima_autorizada" numeric,
    "motivo_resolucion" "text",
    "solicitada_por" "uuid" NOT NULL,
    "solicitada_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "vence_en" timestamp with time zone NOT NULL,
    "resuelta_por" "uuid",
    "resuelta_en" timestamp with time zone,
    "respondida_por_analista_en" timestamp with time zone,
    "motivo_analista" "text",
    "consumida_en" timestamp with time zone,
    "contrato_id" "uuid",
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "lead_id" "uuid",
    "huella_preconversion" "text",
    "documento_lead" "text",
    CONSTRAINT "solicitudes_tasa_capital_check" CHECK ((("capital" >= (100)::numeric) AND ("capital" <= (100000000)::numeric))),
    CONSTRAINT "solicitudes_tasa_categoria_check" CHECK (("categoria" = ANY (ARRAY['nuevo'::"text", 'renovacion'::"text", 'upgrade'::"text"]))),
    CONSTRAINT "solicitudes_tasa_contratos_previos_check" CHECK (("contratos_previos" >= 0)),
    CONSTRAINT "solicitudes_tasa_estado_check" CHECK (("estado" = ANY (ARRAY['pendiente'::"text", 'aprobada'::"text", 'aprobada_con_tope'::"text", 'rechazada'::"text", 'aceptada_por_analista'::"text", 'declinada_por_analista'::"text", 'consumida'::"text", 'vencida'::"text"]))),
    CONSTRAINT "solicitudes_tasa_estado_coherente" CHECK (
CASE "estado"
    WHEN 'pendiente'::"text" THEN (("resuelta_por" IS NULL) AND ("tasa_maxima_autorizada" IS NULL) AND ("respondida_por_analista_en" IS NULL) AND ("consumida_en" IS NULL))
    WHEN 'rechazada'::"text" THEN (("resuelta_por" IS NOT NULL) AND ("tasa_maxima_autorizada" IS NULL) AND ("consumida_en" IS NULL))
    WHEN 'aprobada'::"text" THEN (("resuelta_por" IS NOT NULL) AND ("tasa_maxima_autorizada" = "tasa_solicitada") AND ("consumida_en" IS NULL))
    WHEN 'aprobada_con_tope'::"text" THEN (("resuelta_por" IS NOT NULL) AND ("tasa_maxima_autorizada" < "tasa_solicitada") AND ("respondida_por_analista_en" IS NULL) AND ("consumida_en" IS NULL))
    WHEN 'aceptada_por_analista'::"text" THEN (("resuelta_por" IS NOT NULL) AND ("tasa_maxima_autorizada" < "tasa_solicitada") AND ("respondida_por_analista_en" IS NOT NULL) AND ("consumida_en" IS NULL))
    WHEN 'declinada_por_analista'::"text" THEN (("resuelta_por" IS NOT NULL) AND ("tasa_maxima_autorizada" < "tasa_solicitada") AND ("respondida_por_analista_en" IS NOT NULL) AND ("consumida_en" IS NULL))
    WHEN 'consumida'::"text" THEN (("resuelta_por" IS NOT NULL) AND ("tasa_maxima_autorizada" IS NOT NULL) AND ("consumida_en" IS NOT NULL) AND ("contrato_id" IS NOT NULL))
    WHEN 'vencida'::"text" THEN ("consumida_en" IS NULL)
    ELSE false
END),
    CONSTRAINT "solicitudes_tasa_modalidad_check" CHECK (("modalidad" = ANY (ARRAY['mensual'::"text", 'trimestral'::"text", 'semestral'::"text", 'anual'::"text"]))),
    CONSTRAINT "solicitudes_tasa_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "solicitudes_tasa_motivo_analista_check" CHECK ((("motivo_analista" IS NULL) OR (("length"("btrim"("motivo_analista")) >= 1) AND ("length"("btrim"("motivo_analista")) <= 500)))),
    CONSTRAINT "solicitudes_tasa_motivo_check" CHECK ((("length"("btrim"("motivo")) >= 5) AND ("length"("btrim"("motivo")) <= 500))),
    CONSTRAINT "solicitudes_tasa_motivo_resolucion_check" CHECK ((("motivo_resolucion" IS NULL) OR (("length"("btrim"("motivo_resolucion")) >= 1) AND ("length"("btrim"("motivo_resolucion")) <= 500)))),
    CONSTRAINT "solicitudes_tasa_nadie_se_aprueba" CHECK ((("resuelta_por" IS NULL) OR ("resuelta_por" <> "solicitada_por"))),
    CONSTRAINT "solicitudes_tasa_origen_por_categoria" CHECK (((("categoria" = 'nuevo'::"text") AND ("contrato_origen_id" IS NULL)) OR (("categoria" <> 'nuevo'::"text") AND ("contrato_origen_id" IS NOT NULL)))),
    CONSTRAINT "solicitudes_tasa_plazo" CHECK (("fecha_vencimiento" > "fecha_inicio")),
    CONSTRAINT "solicitudes_tasa_regla_base_check" CHECK (("regla_base" = ANY (ARRAY['primera_inversion'::"text", 'heredada_renovacion'::"text", 'heredada_upgrade'::"text"]))),
    CONSTRAINT "solicitudes_tasa_solo_eleva" CHECK (("tasa_solicitada" > "tasa_base")),
    CONSTRAINT "solicitudes_tasa_sujeto" CHECK ((("cliente_id" IS NOT NULL) OR ("lead_id" IS NOT NULL))),
    CONSTRAINT "solicitudes_tasa_tasa_base_check" CHECK ((("tasa_base" > (0)::numeric) AND ("tasa_base" <= (50)::numeric))),
    CONSTRAINT "solicitudes_tasa_tasa_maxima_autorizada_check" CHECK ((("tasa_maxima_autorizada" IS NULL) OR (("tasa_maxima_autorizada" > (0)::numeric) AND ("tasa_maxima_autorizada" <= (50)::numeric) AND ("scale"("tasa_maxima_autorizada") <= 2)))),
    CONSTRAINT "solicitudes_tasa_tasa_solicitada_check" CHECK ((("tasa_solicitada" > (0)::numeric) AND ("tasa_solicitada" <= (50)::numeric) AND ("scale"("tasa_solicitada") <= 2))),
    CONSTRAINT "solicitudes_tasa_tipo_interes_check" CHECK (("tipo_interes" = ANY (ARRAY['simple'::"text", 'compuesto'::"text"]))),
    CONSTRAINT "solicitudes_tasa_tope_en_rango" CHECK ((("tasa_maxima_autorizada" IS NULL) OR (("tasa_maxima_autorizada" > "tasa_base") AND ("tasa_maxima_autorizada" <= "tasa_solicitada")))),
    CONSTRAINT "solicitudes_tasa_vence_despues" CHECK (("vence_en" > "solicitada_en"))
);

COMMENT ON TABLE "crm"."solicitudes_tasa" IS 'Rentabilidad R1. Solicitud de una tasa SUPERIOR a la base (D4) para un contrato en intención, identificado por su HUELLA. El analista pide con motivo; Gerencia —nunca quien pidió (D3)— aprueba, rechaza o aprueba hasta un tope (D6); con tope, el analista acepta o declina. Un solo uso (consumida, R4) y con vencimiento. Solo se escribe por sus puertas crm.*_tasa_fn (trigger con GUC crm.solicitud_tasa_por_puerta).';

COMMENT ON COLUMN "crm"."solicitudes_tasa"."contrato_origen_id" IS 'Renovación/upgrade: contrato del que se hereda la tasa base. Sin FK a public.contratos a propósito (ver contrato_id).';

COMMENT ON COLUMN "crm"."solicitudes_tasa"."huella" IS 'md5 de la intención canónica (cliente, categoría, origen, producto, capital, moneda, modalidad, interés, fechas) — private.huella_solicitud_tasa. Si el contrato cambia, la autorización no aplica.';

COMMENT ON COLUMN "crm"."solicitudes_tasa"."prioridad_bandeja" IS 'D1: primera inversión de un cliente que ya tiene contratos → va primero en la bandeja de Gerencia.';

COMMENT ON COLUMN "crm"."solicitudes_tasa"."tasa_maxima_autorizada" IS 'La tasa AUTORIZADA efectiva: = tasa_solicitada si Gerencia aprobó tal cual; < tasa_solicitada si aprobó hasta un tope (D6). NULL si pendiente o rechazada.';

COMMENT ON COLUMN "crm"."solicitudes_tasa"."contrato_id" IS 'Contrato que consumió la autorización (R4). Sin FK a public.contratos a propósito: la eliminación del contrato por su puerta no se bloquea.';

COMMENT ON COLUMN "crm"."solicitudes_tasa"."lead_id" IS 'Origen comercial permanente; cliente_id se enlaza al convertir y la autorización se consume al contratar.';

CREATE TABLE IF NOT EXISTS "crm"."tarea_sla_contexto" (
    "tarea_id" "uuid" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "ciclo_n" integer NOT NULL,
    "fuente" "text" NOT NULL,
    "registrado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "tarea_sla_contexto_fuente_check" CHECK (("fuente" = ANY (ARRAY['evento'::"text", 'reconstruido'::"text"]))),
    CONSTRAINT "tarea_sla_contexto_registrado_en_check" CHECK ("isfinite"("registrado_en"))
);

COMMENT ON TABLE "crm"."tarea_sla_contexto" IS 'SLA-R2: ciclo causal de tareas. N1 no reconstruye ni captura stock; ausencia no equivale a contexto valido.';

CREATE TABLE IF NOT EXISTS "crm"."tipo_cambio_diario" (
    "fecha_corte" "date" NOT NULL,
    "politica" "text" NOT NULL,
    "tasa" numeric(14,4) NOT NULL,
    "pares" "jsonb" NOT NULL,
    "publicacion_confirmada" "date" NOT NULL,
    "fuente" "text" NOT NULL,
    "huella_respuestas" "text" NOT NULL,
    "consolidado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "tipo_cambio_diario_check" CHECK ((("jsonb_typeof"("pares") = 'array'::"text") AND ((("politica" = 'sbs_punto_medio_7d_v1'::"text") AND ("jsonb_array_length"("pares") = 7)) OR (("politica" = 'sbs_punto_medio_hasta7_legado_v1'::"text") AND (("jsonb_array_length"("pares") >= 1) AND ("jsonb_array_length"("pares") <= 7)))))),
    CONSTRAINT "tipo_cambio_diario_check1" CHECK (("publicacion_confirmada" >= "fecha_corte")),
    CONSTRAINT "tipo_cambio_diario_fuente_check" CHECK (("fuente" = 'BCRP · SBS PD04639PD/PD04640PD'::"text")),
    CONSTRAINT "tipo_cambio_diario_huella_respuestas_check" CHECK (("huella_respuestas" ~ '^[a-f0-9]{64}$'::"text")),
    CONSTRAINT "tipo_cambio_diario_politica_check" CHECK (("politica" = ANY (ARRAY['sbs_punto_medio_7d_v1'::"text", 'sbs_punto_medio_hasta7_legado_v1'::"text"]))),
    CONSTRAINT "tipo_cambio_diario_tasa_check" CHECK ((("tasa" > (0)::numeric) AND ("tasa" < 'Infinity'::numeric)))
);

COMMENT ON TABLE "crm"."tipo_cambio_diario" IS 'Siete pares SBS guardados y promedio numeric consolidado por fecha comercial; sin refresco posterior.';

CREATE TABLE IF NOT EXISTS "crm"."tipo_cambio_trabajos" (
    "fecha_corte" "date" NOT NULL,
    "politica" "text" DEFAULT 'sbs_punto_medio_7d_v1'::"text" NOT NULL,
    "intentos" integer DEFAULT 0 NOT NULL,
    "proximo_intento_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "reserva" "uuid",
    "reservada_hasta" timestamp with time zone,
    "completado_en" timestamp with time zone,
    "ultimo_motivo" "text",
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "tipo_cambio_trabajos_check" CHECK ((("reserva" IS NULL) = ("reservada_hasta" IS NULL))),
    CONSTRAINT "tipo_cambio_trabajos_intentos_check" CHECK (("intentos" >= 0)),
    CONSTRAINT "tipo_cambio_trabajos_politica_check" CHECK (("politica" = ANY (ARRAY['sbs_punto_medio_7d_v1'::"text", 'sbs_punto_medio_hasta7_legado_v1'::"text"]))),
    CONSTRAINT "tipo_cambio_trabajos_ultimo_motivo_check" CHECK (("char_length"("ultimo_motivo") <= 300))
);

CREATE TABLE IF NOT EXISTS "crm"."usuario_eventos" (
    "id" bigint NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "objetivo_id" "uuid",
    "accion" "text" NOT NULL,
    "detalle" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "idempotencia" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "usuario_eventos_accion_valida" CHECK (("accion" = ANY (ARRAY['candidato_creado'::"text", 'perfil_actualizado'::"text", 'rol_asignado'::"text", 'rol_cambiado'::"text", 'jerarquia_actualizada'::"text", 'membresia_activada'::"text", 'membresia_desactivada'::"text", 'recuperacion_solicitada'::"text"]))),
    CONSTRAINT "usuario_eventos_detalle_objeto" CHECK ((("jsonb_typeof"("detalle") = 'object'::"text") AND ("octet_length"(("detalle")::"text") <= 4096)))
);

COMMENT ON TABLE "crm"."usuario_eventos" IS 'Auditoria de usuarios CRM. Append-only y cerrada al Data API; nunca contiene email, documento, password, token ni secreto.';

ALTER TABLE "crm"."usuario_eventos" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "crm"."usuario_eventos_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "crm"."verificaciones_lead" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "verificado_por" "uuid" NOT NULL,
    "telefono_consultado" "text" NOT NULL,
    "dni_consultado" "text",
    "veredicto" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL
);

COMMENT ON TABLE "crm"."verificaciones_lead" IS 'Registro anti-pesca de la verificación por contacto (F1) y de la TOMA directa (F2): cada llamada a crm.verificar_disponibilidad_lead o a crm.tomar_lead_libre deja quién consultó qué identidad y el veredicto (en la toma, también tomado_ok). Lo escriben SOLO esas RPCs (security definer); por policy lo lee gerencia — y, como TODA tabla crm.* auditada, su rastro en public.audit_log es legible por admin/superadmin del portal (vía preexistente; la bandeja del portal filtra tabla IN (perfiles, contratos) y NO lo muestra — verificado en prod 2026-08-16, md5 bandeja_actividad ff1bd19f…). Los prechecks internos del alta atómica llaman al impl directo y no dejan fila.';

CREATE TABLE IF NOT EXISTS "private"."agenda_reparto_cambios" (
    "id" bigint NOT NULL,
    "fecha" "date" NOT NULL,
    "origen" "text" NOT NULL,
    "supervisor_anterior_id" "uuid",
    "supervisor_nuevo_id" "uuid" NOT NULL,
    "cambiado_por" "uuid" NOT NULL,
    "cambiado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "agenda_reparto_cambios_origen_check" CHECK (("origen" = ANY (ARRAY['landing'::"text", 'formulario'::"text"])))
);

ALTER TABLE ONLY "private"."agenda_reparto_cambios" FORCE ROW LEVEL SECURITY;

ALTER TABLE "private"."agenda_reparto_cambios" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."agenda_reparto_cambios_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."agenda_reparto_destinos" (
    "supervisor_id" "uuid" NOT NULL,
    "alias" "text" NOT NULL,
    "orden" smallint NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "agenda_reparto_destinos_alias_check" CHECK ((("char_length"("btrim"("alias")) >= 1) AND ("char_length"("btrim"("alias")) <= 40))),
    CONSTRAINT "agenda_reparto_destinos_orden_check" CHECK ((("orden" >= 1) AND ("orden" <= 9)))
);

ALTER TABLE ONLY "private"."agenda_reparto_destinos" FORCE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS "private"."agenda_reparto_diaria" (
    "fecha" "date" NOT NULL,
    "origen" "text" NOT NULL,
    "supervisor_id" "uuid" NOT NULL,
    "creado_por" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "actualizado_por" "uuid" NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "agenda_reparto_diaria_origen_check" CHECK (("origen" = ANY (ARRAY['landing'::"text", 'formulario'::"text"])))
);

ALTER TABLE ONLY "private"."agenda_reparto_diaria" FORCE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS "private"."analista_vigencia_exenciones" (
    "objeto" "text" NOT NULL,
    "tipo" "text" NOT NULL,
    "huella" "text" NOT NULL,
    "razon" "text" NOT NULL,
    "declarado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "razon_de_verdad" CHECK (("length"("btrim"("razon")) >= 40)),
    CONSTRAINT "tipo_conocido" CHECK (("tipo" = ANY (ARRAY['funcion'::"text", 'vista'::"text", 'policy'::"text"])))
);

COMMENT ON TABLE "private"."analista_vigencia_exenciones" IS 'P-055 F5.a. Sitios donde la pregunta del Portal se usa CRUDA a proposito, por IDENTIDAD exacta y con la HUELLA del cuerpo al declararlos: si el cuerpo cambia, la exencion caduca y el gate se pone rojo.';

CREATE TABLE IF NOT EXISTS "private"."analista_vigencia_tope" (
    "id" boolean DEFAULT true NOT NULL,
    "tope" integer NOT NULL,
    "nucleo_huella" "text",
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tope_no_negativo" CHECK (("tope" >= 0)),
    CONSTRAINT "una_sola_fila" CHECK (("id" IS TRUE))
);

CREATE TABLE IF NOT EXISTS "private"."analitica_lc_sello" (
    "id" boolean DEFAULT true NOT NULL,
    "sello" "text" NOT NULL,
    "sellado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "una_sola_fila" CHECK (("id" IS TRUE))
);

CREATE TABLE IF NOT EXISTS "private"."analitica_leads_citas_exenciones" (
    "objeto" "text" NOT NULL,
    "tipo" "text" NOT NULL,
    "huella" "text" NOT NULL,
    "razon" "text" NOT NULL,
    "declarado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "clase" "text" NOT NULL,
    CONSTRAINT "clase_conocida" CHECK (("clase" = ANY (ARRAY['analitica'::"text", 'mixta'::"text", 'operativo'::"text", 'verificador'::"text"]))),
    CONSTRAINT "razon_de_verdad" CHECK (("length"("btrim"("razon")) >= 40)),
    CONSTRAINT "tipo_conocido" CHECK (("tipo" = ANY (ARRAY['funcion'::"text", 'vista'::"text"])))
);

COMMENT ON TABLE "private"."analitica_leads_citas_exenciones" IS 'Objetos que cuentan leads o citas EN CRUDO a proposito, por identidad exacta y con la huella de su cuerpo: si el cuerpo cambia, la razon caduca y el trinquete salta. Desde el 22/09/2026 cada fila lleva ademas su `clase`, que decide QUIEN CONSUME CUPO bajo el techo; la clase entra en el sello de la lista y solo puede APRETAR (trg_analitica_lc_clase_solo_aprieta).';

COMMENT ON COLUMN "private"."analitica_leads_citas_exenciones"."clase" IS 'Que PREGUNTA responde este contador, y por tanto si puede contradecir al nucleo. `analitica`: mide el PASADO (la cifra del mes, el sello, la produccion) -- cuenta para el techo. `mixta`: publica la cifra oficial del nucleo Y ademas cuenta por su cuenta -- cuenta para el techo. `operativo`: INVENTARIO y RASTRO DE FLUJO -- colas, reparto, validacion de un lote, y tambien el rastro de un periodo (derivaciones del mes, descartados por mes, ingresos al reparto), SIEMPRE que no publique una TASA ni una cifra de CIERRE. Sigue censado, declarado y con huella vigente, pero no consume cupo porque no responde la pregunta de la conversion y por tanto no puede darle otra respuesta. `verificador`: existe para comprobar cifras ajenas y no publica ninguna propia; solo vale para objetos que el censo ya excluye por identidad exacta y huella -- un sujeto del censo NO puede llevarla.';

CREATE TABLE IF NOT EXISTS "private"."analitica_leads_citas_tope" (
    "id" boolean DEFAULT true NOT NULL,
    "tope" integer NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "tope_no_negativo" CHECK (("tope" >= 0)),
    CONSTRAINT "una_sola_fila" CHECK (("id" IS TRUE))
);

CREATE TABLE IF NOT EXISTS "private"."auditoria_alertas" (
    "id" bigint NOT NULL,
    "tabla" "text" NOT NULL,
    "detectada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resuelta_en" timestamp with time zone
);

COMMENT ON TABLE "private"."auditoria_alertas" IS 'Lo que el vigía diario encontró sin rastro. Una alerta se cierra sola en cuanto la tabla recibe su auditor o se declara exenta.';

ALTER TABLE "private"."auditoria_alertas" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."auditoria_alertas_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."auditoria_condicionada" (
    "tabla" "text" NOT NULL,
    "razon" "text" NOT NULL,
    "declarada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "auditoria_condicionada_razon_de_verdad" CHECK (("length"("btrim"("razon")) >= 40))
);

COMMENT ON TABLE "private"."auditoria_condicionada" IS 'Tablas cuyo rastro lleva un WHEN: auditan de verdad, pero se saltan casos a propósito. La regla las acepta SOLO si están aquí con su razón.';

CREATE TABLE IF NOT EXISTS "private"."auditoria_exenciones" (
    "tabla" "text" NOT NULL,
    "razon" "text" NOT NULL,
    "declarada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "auditoria_exenciones_razon_de_verdad" CHECK (("length"("btrim"("razon")) >= 40))
);

COMMENT ON TABLE "private"."auditoria_exenciones" IS 'Tablas de crm/public que pueden vivir SIN rastro en audit_log. Cada fila necesita su razón; el gate del repo compara esta lista con la escrita en supabase/scripts/trinquete-auditoria.sql, así que un cambio silencioso aquí también pone el gate en rojo.';

CREATE TABLE IF NOT EXISTS "private"."auditoria_sello" (
    "unico" boolean DEFAULT true NOT NULL,
    "huella" "text" NOT NULL,
    "sellado" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "auditoria_sello_una_sola_fila" CHECK ("unico")
);

COMMENT ON TABLE "private"."auditoria_sello" IS 'Huella de la lista blanca tal y como la dejó la última migración. Si la lista viva deja de coincidir, el vigía abre alerta sin esperar a que nadie corra el gate.';

CREATE TABLE IF NOT EXISTS "private"."ayuda_consultas" (
    "id" bigint NOT NULL,
    "usuario_id" "uuid" NOT NULL,
    "vista" "text" NOT NULL,
    "consulta_redactada" "text" NOT NULL,
    "longitud" smallint NOT NULL,
    "resultado" "text" NOT NULL,
    "intencion_id" bigint,
    "puntuacion" numeric(5,4),
    "segunda_puntuacion" numeric(5,4),
    "motivo" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "retener_hasta" timestamp with time zone DEFAULT ("clock_timestamp"() + '90 days'::interval) NOT NULL,
    CONSTRAINT "ayuda_consultas_longitud_valida" CHECK ((("longitud" >= 2) AND ("longitud" <= 240))),
    CONSTRAINT "ayuda_consultas_puntuacion_valida" CHECK (((("puntuacion" IS NULL) OR (("puntuacion" >= (0)::numeric) AND ("puntuacion" <= (1)::numeric))) AND (("segunda_puntuacion" IS NULL) OR (("segunda_puntuacion" >= (0)::numeric) AND ("segunda_puntuacion" <= (1)::numeric))))),
    CONSTRAINT "ayuda_consultas_resultado_valido" CHECK (("resultado" = ANY (ARRAY['respuesta'::"text", 'aclaracion'::"text", 'sin_resultado'::"text"])))
);

ALTER TABLE "private"."ayuda_consultas" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."ayuda_consultas_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."ayuda_expresiones" (
    "id" bigint NOT NULL,
    "intencion_id" bigint NOT NULL,
    "texto" "text" NOT NULL,
    "texto_normalizado" "text" GENERATED ALWAYS AS ("private"."normalizar_texto_ayuda"("texto")) STORED,
    "vector_busqueda" "tsvector" GENERATED ALWAYS AS ("to_tsvector"('"spanish"'::"regconfig", "private"."normalizar_texto_ayuda"("texto"))) STORED,
    "peso" numeric(4,3) DEFAULT 1 NOT NULL,
    "tipo" "text" DEFAULT 'coloquial'::"text" NOT NULL,
    CONSTRAINT "ayuda_expresiones_peso_valido" CHECK ((("peso" > (0)::numeric) AND ("peso" <= (1)::numeric))),
    CONSTRAINT "ayuda_expresiones_texto_longitud" CHECK ((("char_length"("texto") >= 2) AND ("char_length"("texto") <= 180))),
    CONSTRAINT "ayuda_expresiones_tipo_valido" CHECK (("tipo" = ANY (ARRAY['canonica'::"text", 'exacta'::"text", 'coloquial'::"text"])))
);

ALTER TABLE "private"."ayuda_expresiones" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."ayuda_expresiones_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."ayuda_intenciones" (
    "id" bigint NOT NULL,
    "clave" "text" NOT NULL,
    "version" integer DEFAULT 1 NOT NULL,
    "pregunta" "text" NOT NULL,
    "contenido" "jsonb" NOT NULL,
    "vistas" "text"[] NOT NULL,
    "grupos_obligatorios" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "terminos_excluidos" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "prioridad" smallint DEFAULT 100 NOT NULL,
    "estado" "text" DEFAULT 'borrador'::"text" NOT NULL,
    "publicado_en" timestamp with time zone,
    "creado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    CONSTRAINT "ayuda_intenciones_clave_formato" CHECK (("clave" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::"text")),
    CONSTRAINT "ayuda_intenciones_contenido_objeto" CHECK (("jsonb_typeof"("contenido") = 'object'::"text")),
    CONSTRAINT "ayuda_intenciones_estado_valido" CHECK (("estado" = ANY (ARRAY['borrador'::"text", 'publicado'::"text", 'retirado'::"text"]))),
    CONSTRAINT "ayuda_intenciones_grupos_array" CHECK (("jsonb_typeof"("grupos_obligatorios") = 'array'::"text")),
    CONSTRAINT "ayuda_intenciones_pregunta_longitud" CHECK ((("char_length"("pregunta") >= 3) AND ("char_length"("pregunta") <= 180))),
    CONSTRAINT "ayuda_intenciones_publicacion_coherente" CHECK (((("estado" = 'publicado'::"text") AND ("publicado_en" IS NOT NULL)) OR ("estado" <> 'publicado'::"text"))),
    CONSTRAINT "ayuda_intenciones_version_positiva" CHECK (("version" > 0)),
    CONSTRAINT "ayuda_intenciones_vistas_validas" CHECK ((("cardinality"("vistas") > 0) AND ("vistas" <@ ARRAY['hoy'::"text", 'alertas'::"text", 'conversiones'::"text", 'ranking-vendedores'::"text", 'reuniones'::"text", 'metas'::"text", 'rendimiento'::"text", 'capital-cierres'::"text", 'pipeline'::"text", 'cartera'::"text", 'agenda'::"text", 'mi-cartera'::"text", 'repartir'::"text", 'equipo'::"text", 'config'::"text", 'config-usuarios'::"text", 'config-productos'::"text", 'config-metas'::"text", 'config-sla'::"text"])))
);

ALTER TABLE "private"."ayuda_intenciones" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."ayuda_intenciones_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."ayuda_reglas_aclaracion" (
    "id" bigint NOT NULL,
    "clave" "text" NOT NULL,
    "todos" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "alguno" "text"[] NOT NULL,
    "ninguno" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "titulo" "text" NOT NULL,
    "detalle" "text" NOT NULL,
    "opciones" "jsonb" NOT NULL,
    "prioridad" smallint DEFAULT 100 NOT NULL,
    "activa" boolean DEFAULT true NOT NULL,
    CONSTRAINT "ayuda_reglas_alguno_no_vacio" CHECK (("cardinality"("alguno") > 0)),
    CONSTRAINT "ayuda_reglas_clave_formato" CHECK (("clave" ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'::"text")),
    CONSTRAINT "ayuda_reglas_opciones_validas" CHECK ((("jsonb_typeof"("opciones") = 'array'::"text") AND (("jsonb_array_length"("opciones") >= 2) AND ("jsonb_array_length"("opciones") <= 3))))
);

ALTER TABLE "private"."ayuda_reglas_aclaracion" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."ayuda_reglas_aclaracion_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."backfill_cuentas_p0xx" (
    "tipo" "text" NOT NULL,
    "fila_id" "uuid" NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "contrato_id" "uuid",
    "marca_actor" "text" DEFAULT 'migracion:p0xx:s1'::"text" NOT NULL,
    "insertada_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revertida_en" timestamp with time zone,
    CONSTRAINT "backfill_cuentas_p0xx_check" CHECK (((("tipo" = 'cuenta'::"text") AND ("contrato_id" IS NULL)) OR (("tipo" = 'vinculo'::"text") AND ("contrato_id" IS NOT NULL)))),
    CONSTRAINT "backfill_cuentas_p0xx_tipo_check" CHECK (("tipo" = ANY (ARRAY['cuenta'::"text", 'vinculo'::"text"])))
);

CREATE TABLE IF NOT EXISTS "private"."celulares_estado" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "asignacion_id" "uuid" NOT NULL,
    "ultimo_latido_en" timestamp with time zone,
    "latido_celular_en" timestamp with time zone,
    "version_macro" "text",
    "eventos_en_cola" integer,
    "minuto_desde" timestamp with time zone,
    "envios_minuto" integer DEFAULT 0 NOT NULL,
    "dia" "date",
    "envios_dia" integer DEFAULT 0 NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "celulares_estado_cola_rango" CHECK ((("eventos_en_cola" IS NULL) OR (("eventos_en_cola" >= 0) AND ("eventos_en_cola" <= 100000)))),
    CONSTRAINT "celulares_estado_envios_dia_validos" CHECK (("envios_dia" >= 0)),
    CONSTRAINT "celulares_estado_envios_minuto_validos" CHECK (("envios_minuto" >= 0)),
    CONSTRAINT "celulares_estado_version_valida" CHECK ((("version_macro" IS NULL) OR ("version_macro" ~ '^[A-Za-z0-9._ -]{1,40}$'::"text")))
);

COMMENT ON TABLE "private"."celulares_estado" IS 'Estado técnico de cada celular asignado: último latido (versión de la macro, eventos en cola) y los contadores del límite de envíos (minuto de reloj y día de Lima, ventanas que nunca retroceden). Una fila por asignación. Desde 20261005143843 no guarda la hora del último envío y la salud no muestra los contadores (N1): cuentan llamadas personales. Tabla técnica de private, sin acceso para la API y sin auditoría. Sin columna de tenant: CRM de una sola empresa.';

COMMENT ON COLUMN "private"."celulares_estado"."id" IS 'Identificador de la fila.';

COMMENT ON COLUMN "private"."celulares_estado"."asignacion_id" IS 'Asignación de celular a la que pertenece (una fila por asignación; no cambia).';

COMMENT ON COLUMN "private"."celulares_estado"."ultimo_latido_en" IS 'Cuándo llegó el último latido (hora del servidor tomada por la puerta tras bloquear este estado). Un latido solo prueba que el celular habla, no que capture bien.';

COMMENT ON COLUMN "private"."celulares_estado"."latido_celular_en" IS 'Hora del celular en el último latido, si la mandó; contrasta con ultimo_latido_en.';

COMMENT ON COLUMN "private"."celulares_estado"."version_macro" IS 'Versión de la macro que declaró el último latido (texto corto del celular, no confiable).';

COMMENT ON COLUMN "private"."celulares_estado"."eventos_en_cola" IS 'Llamadas que el celular dijo tener pendientes de enviar en su último latido (no confiable).';

COMMENT ON COLUMN "private"."celulares_estado"."minuto_desde" IS 'Inicio del minuto de reloj al que corresponde envios_minuto. Nunca retrocede.';

COMMENT ON COLUMN "private"."celulares_estado"."envios_minuto" IS 'Envíos contados en el minuto minuto_desde (válidos, repetidos o inválidos: todo gasta cupo). Solo para el límite; la salud no lo muestra.';

COMMENT ON COLUMN "private"."celulares_estado"."dia" IS 'Día de Lima al que corresponde envios_dia. Nunca retrocede.';

COMMENT ON COLUMN "private"."celulares_estado"."envios_dia" IS 'Envíos contados en el día dia. Solo para el límite; la salud no lo muestra (N1).';

COMMENT ON COLUMN "private"."celulares_estado"."creado_en" IS 'Alta de la fila (primer envío del celular).';

COMMENT ON COLUMN "private"."celulares_estado"."actualizado_en" IS 'Último cambio (lo sella el trigger).';

CREATE TABLE IF NOT EXISTS "private"."conciliacion_cuentas_p0xx" (
    "id" bigint NOT NULL,
    "clase" "text" NOT NULL,
    "cliente_id" "uuid" NOT NULL,
    "moneda" "text" NOT NULL,
    "contrato_id" "uuid",
    "motivo" "text" NOT NULL,
    "observado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "conciliacion_cuentas_p0xx_clase_check" CHECK (("clase" = ANY (ARRAY['perfil'::"text", 'contrato'::"text"]))),
    CONSTRAINT "conciliacion_cuentas_p0xx_moneda_check" CHECK (("moneda" = ANY (ARRAY['PEN'::"text", 'USD'::"text"]))),
    CONSTRAINT "conciliacion_cuentas_p0xx_motivo_check" CHECK (("motivo" = ANY (ARRAY['perfil_invalido'::"text", 'mismo_cci_datos_distintos'::"text", 'varias_activas'::"text", 'sin_cuenta'::"text", 'cuentas_ambiguas'::"text", 'perfil_conflictivo'::"text"])))
);

ALTER TABLE "private"."conciliacion_cuentas_p0xx" ALTER COLUMN "id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "private"."conciliacion_cuentas_p0xx_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE IF NOT EXISTS "private"."contrato_altas_idempotentes" (
    "actor_id" "uuid" NOT NULL,
    "clave" "uuid" NOT NULL,
    "contrato_id" "uuid",
    "huella" "text" NOT NULL,
    "respuesta" "jsonb" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "contrato_altas_idempotentes_huella_md5" CHECK (("huella" ~ '^[0-9a-f]{32}$'::"text")),
    CONSTRAINT "contrato_altas_idempotentes_respuesta_objeto" CHECK (("jsonb_typeof"("respuesta") = 'object'::"text"))
);

ALTER TABLE ONLY "private"."contrato_altas_idempotentes" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "private"."contrato_altas_idempotentes" IS 'Memoria de idempotencia del alta de contrato (crm.crear_contrato_con_cuenta_pdf_v2): por (actor, clave) guarda el contrato creado, la huella de lo pedido y la respuesta. Un reintento con la misma clave y los mismos datos devuelve el mismo contrato en vez de crear otro (incidente del 05/09/2026: dos contratos idénticos por un error falso del front); con otros datos avisa (P0409) sin crear ni devolver nada. Solo la escribe el wrapper DEFINER; sin grants para la API. Al borrar el contrato la fila queda como lápida (contrato_id NULL).';

CREATE TABLE IF NOT EXISTS "private"."contrato_eliminaciones" (
    "contrato_id" "uuid" NOT NULL,
    "token" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "solicitado_por" "uuid" NOT NULL,
    "objetos" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "contrato_eliminaciones_objetos_array" CHECK ((("jsonb_typeof"("objetos") = 'array'::"text") AND ("jsonb_array_length"("objetos") <= 1000)))
);

ALTER TABLE ONLY "private"."contrato_eliminaciones" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "private"."contrato_eliminaciones" IS 'Mutex durable de borrado: la Edge elimina los objetos listados y solo después confirma el hard-delete contractual.';

CREATE TABLE IF NOT EXISTS "private"."contrato_pdf_anexo_emisiones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "pdf_id" "uuid" NOT NULL,
    "revision" integer NOT NULL,
    "template_version_contrato" "text" NOT NULL,
    "template_anexo" "text" NOT NULL,
    "sha256" "text" NOT NULL,
    "bytes" bigint NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    CONSTRAINT "contrato_pdf_anexo_emisiones_hash_bytes_validos" CHECK ((("sha256" ~ '^[a-f0-9]{64}$'::"text") AND (("bytes" >= 1) AND ("bytes" <= 10485760)))),
    CONSTRAINT "contrato_pdf_anexo_emisiones_revision_valida" CHECK (("revision" > 0)),
    CONSTRAINT "contrato_pdf_anexo_emisiones_template_valida" CHECK (("template_anexo" ~ '^anexo-cronograma-v[0-9]{1,3}$'::"text"))
);

ALTER TABLE ONLY "private"."contrato_pdf_anexo_emisiones" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "private"."contrato_pdf_anexo_emisiones" IS 'Bitácora de solo añadir (UPDATE/DELETE/TRUNCATE rechazados también al dueño) de cada anexo de cronograma EMITIDO por la Edge: quién, cuándo, contrato, revisión sellada, plantillas, sha256 y bytes del anexo. Un render fallido no deja asiento. Sin snapshot (datos bancarios) y sin FK (sobrevive a la eliminación auditada y al borrado de perfiles).';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."id" IS 'Identificador del asiento.';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."contrato_id" IS 'Contrato del que se emitió el anexo (sin FK: sobrevive a la eliminación auditada).';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."pdf_id" IS 'Fila de private.contrato_pdfs (sellado) de la que salió el snapshot (sin FK).';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."revision" IS 'Revisión sellada del contrato usada para el anexo.';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."template_version_contrato" IS 'Versión de plantilla del contrato sellado (p. ej. contrato-aep-17-v9).';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."template_anexo" IS 'Versión de plantilla del anexo que la Edge dibujó (anexo-cronograma-vN).';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."sha256" IS 'SHA-256 de los bytes del anexo entregados al navegador.';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."bytes" IS 'Tamaño en bytes del anexo entregado.';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."actor_id" IS 'Quién pidió el anexo (perfil de la sesión). Se conserva tal cual, sin FK.';

COMMENT ON COLUMN "private"."contrato_pdf_anexo_emisiones"."creado_en" IS 'Instante de la emisión.';

CREATE TABLE IF NOT EXISTS "private"."contrato_pdf_jobs" (
    "id" "uuid" NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "estado" "text" DEFAULT 'pendiente'::"text" NOT NULL,
    "storage_bucket" "text" DEFAULT 'contratos-generados'::"text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "nombre_archivo" "text" NOT NULL,
    "template_version" "text" DEFAULT 'contrato-aep-17-v10'::"text" NOT NULL,
    "snapshot" "jsonb" NOT NULL,
    "sha256" "text",
    "bytes" bigint,
    "solicitado_por" "uuid" NOT NULL,
    "intentos" integer DEFAULT 0 NOT NULL,
    "lease_token" "uuid",
    "lease_expira_en" timestamp with time zone,
    "ultimo_error" "text",
    "creado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "subido_en" timestamp with time zone,
    "sellado_en" timestamp with time zone,
    "revision" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "contrato_pdf_jobs_bucket_valido" CHECK (("storage_bucket" = 'contratos-generados'::"text")),
    CONSTRAINT "contrato_pdf_jobs_bytes_pareados" CHECK (((("sha256" IS NULL) AND ("bytes" IS NULL)) OR (("sha256" ~ '^[a-f0-9]{64}$'::"text") AND ("bytes" > 0) AND ("bytes" <= 10485760)))),
    CONSTRAINT "contrato_pdf_jobs_estado_valido" CHECK (("estado" = ANY (ARRAY['pendiente'::"text", 'procesando'::"text", 'subido_verificado'::"text", 'sellado'::"text", 'error_reintentable'::"text", 'integridad_bloqueada'::"text"]))),
    CONSTRAINT "contrato_pdf_jobs_intentos_valido" CHECK (("intentos" >= 0)),
    CONSTRAINT "contrato_pdf_jobs_lease_coherente" CHECK (((("estado" = ANY (ARRAY['procesando'::"text", 'subido_verificado'::"text"])) AND ("lease_token" IS NOT NULL) AND ("lease_expira_en" IS NOT NULL)) OR (("estado" <> ALL (ARRAY['procesando'::"text", 'subido_verificado'::"text"])) AND ("lease_token" IS NULL) AND ("lease_expira_en" IS NULL)))),
    CONSTRAINT "contrato_pdf_jobs_nombre_valido" CHECK ((("nombre_archivo" = "btrim"("nombre_archivo")) AND (("length"("nombre_archivo") >= 5) AND ("length"("nombre_archivo") <= 255)) AND ("nombre_archivo" ~* '\.pdf$'::"text"))),
    CONSTRAINT "contrato_pdf_jobs_revision_valida" CHECK (("revision" > 0)),
    CONSTRAINT "contrato_pdf_jobs_ruta_server_side" CHECK (("storage_path" = (((("contrato_id")::"text" || '/v2/'::"text") || ("id")::"text") || '/contrato.pdf'::"text"))),
    CONSTRAINT "contrato_pdf_jobs_sello_coherente" CHECK (((("estado" = 'sellado'::"text") AND ("sellado_en" IS NOT NULL)) OR (("estado" <> 'sellado'::"text") AND ("sellado_en" IS NULL)))),
    CONSTRAINT "contrato_pdf_jobs_snapshot_objeto" CHECK (("jsonb_typeof"("snapshot") = 'object'::"text")),
    CONSTRAINT "contrato_pdf_jobs_subida_coherente" CHECK (((("estado" = ANY (ARRAY['pendiente'::"text", 'procesando'::"text"])) AND ("sha256" IS NULL) AND ("bytes" IS NULL) AND ("subido_en" IS NULL)) OR (("estado" = ANY (ARRAY['subido_verificado'::"text", 'sellado'::"text"])) AND ("sha256" IS NOT NULL) AND ("bytes" IS NOT NULL) AND ("subido_en" IS NOT NULL)) OR ("estado" = ANY (ARRAY['error_reintentable'::"text", 'integridad_bloqueada'::"text"])))),
    CONSTRAINT "contrato_pdf_jobs_template_valido" CHECK (("template_version" = ANY (ARRAY['contrato-aep-17-v2'::"text", 'contrato-aep-17-v3'::"text", 'contrato-aep-17-v4'::"text", 'contrato-aep-17-v5'::"text", 'contrato-aep-17-v6'::"text", 'contrato-aep-17-v7'::"text", 'contrato-aep-17-v8'::"text", 'contrato-aep-17-v9'::"text", 'contrato-aep-17-v10'::"text"])))
);

ALTER TABLE ONLY "private"."contrato_pdf_jobs" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "private"."contrato_pdf_jobs" IS 'Reserva durable v2; snapshot y ruta server-side inmutables, con lease corto para I/O externo.';

CREATE TABLE IF NOT EXISTS "private"."contrato_pdfs" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "contrato_id" "uuid" NOT NULL,
    "job_id" "uuid",
    "storage_bucket" "text" DEFAULT 'contratos-generados'::"text" NOT NULL,
    "storage_path" "text" NOT NULL,
    "nombre_archivo" "text" NOT NULL,
    "sha256" "text" NOT NULL,
    "bytes" bigint NOT NULL,
    "template_version" "text" NOT NULL,
    "snapshot" "jsonb" NOT NULL,
    "generado_por" "uuid" NOT NULL,
    "generado_en" timestamp with time zone DEFAULT "statement_timestamp"() NOT NULL,
    "revision" integer DEFAULT 1 NOT NULL,
    CONSTRAINT "contrato_pdfs_bucket_valido" CHECK (("storage_bucket" = 'contratos-generados'::"text")),
    CONSTRAINT "contrato_pdfs_hash_bytes_validos" CHECK ((("sha256" ~ '^[a-f0-9]{64}$'::"text") AND ("bytes" > 0) AND ("bytes" <= 10485760))),
    CONSTRAINT "contrato_pdfs_nombre_valido" CHECK ((("nombre_archivo" = "btrim"("nombre_archivo")) AND (("length"("nombre_archivo") >= 5) AND ("length"("nombre_archivo") <= 255)) AND ("nombre_archivo" ~* '\.pdf$'::"text"))),
    CONSTRAINT "contrato_pdfs_revision_valida" CHECK (("revision" > 0)),
    CONSTRAINT "contrato_pdfs_version_ruta_valida" CHECK (((("template_version" = 'contrato-aep-17-v1'::"text") AND ("job_id" IS NULL) AND ("storage_path" = (("contrato_id")::"text" || '/contrato.pdf'::"text"))) OR (("template_version" = ANY (ARRAY['contrato-aep-17-v2'::"text", 'contrato-aep-17-v3'::"text", 'contrato-aep-17-v4'::"text", 'contrato-aep-17-v5'::"text", 'contrato-aep-17-v6'::"text", 'contrato-aep-17-v7'::"text", 'contrato-aep-17-v8'::"text", 'contrato-aep-17-v9'::"text", 'contrato-aep-17-v10'::"text"])) AND ("job_id" IS NOT NULL) AND ("storage_path" = (((("contrato_id")::"text" || '/v2/'::"text") || ("job_id")::"text") || '/contrato.pdf'::"text")))))
);

ALTER TABLE ONLY "private"."contrato_pdfs" FORCE ROW LEVEL SECURITY;

COMMENT ON TABLE "private"."contrato_pdfs" IS 'Ledger inmutable compatible con archivos v1 y jobs server-side v2.';

CREATE TABLE IF NOT EXISTS "private"."f7_piezas_en_observacion" (
    "firma" "text" NOT NULL,
    "huella_md5" "text" NOT NULL,
    "acl_esperada" "text" NOT NULL,
    "llamadores_permitidos" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "patron_censo" "text" NOT NULL,
    "ola" "text" NOT NULL,
    "estado" "text" NOT NULL,
    "cerrada_en" "date" NOT NULL,
    "drop_no_antes_de" "date",
    "ok_miguel" "text" NOT NULL,
    "nota" "text",
    CONSTRAINT "f7_obs_ventana" CHECK ((("estado" <> 'observacion'::"text") OR (("drop_no_antes_de" IS NOT NULL) AND ("drop_no_antes_de" >= ("cerrada_en" + 14))))),
    CONSTRAINT "f7_piezas_en_observacion_estado_check" CHECK (("estado" = ANY (ARRAY['observacion'::"text", 'cerrada_permanente'::"text", 'demolida'::"text", 'liberada'::"text"]))),
    CONSTRAINT "f7_piezas_en_observacion_ok_miguel_check" CHECK (("length"("ok_miguel") >= 20))
);

COMMENT ON TABLE "private"."f7_piezas_en_observacion" IS 'F7: piezas cerradas en observacion. Es la lista que el vigia 06:59 lee, el candado temporal del DROP (drop_no_antes_de) y el registro historico. Salida = estado liberada; jamas DELETE.';

CREATE TABLE IF NOT EXISTS "private"."llamadas_celular_intenciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "evento_origen_id" "text" NOT NULL,
    "analista_id" "uuid" NOT NULL,
    "lead_id" "uuid" NOT NULL,
    "actividad_id" "uuid" NOT NULL,
    "via" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "llamadas_celular_intenciones_origen_valido" CHECK (("evento_origen_id" ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$'::"text")),
    CONSTRAINT "llamadas_celular_intenciones_via_valida" CHECK (("via" = ANY (ARRAY['al_colgar'::"text", 'pestana'::"text"])))
);

COMMENT ON TABLE "private"."llamadas_celular_intenciones" IS 'Intención de enlace (F4-a): la encuesta se guardó con el id de su llamada ANTES de que llegara el aviso del celular. La ingesta la cumple al llegar el aviso (crea el enlace con su vía) y la retira, se cumpla o no. Única por id y por resultado; caduca a los 32 días (la purga diaria) si el aviso nunca llega. Tabla técnica de private, sin acceso para la API y sin auditoría: transitoria, sin número ni datos personales. Sin columna de tenant: CRM de una sola empresa.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."id" IS 'Identificador de la intención.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."evento_origen_id" IS 'Id de la llamada que llegó en la URL de la encuesta: C<n>-<segundos del reloj del celular>. Único.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."analista_id" IS 'Quién registró el resultado: tiene que ser el analista del celular de la llamada para cumplirse. FK con RESTRICT.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."lead_id" IS 'Lead del resultado: la llamada tiene que quedar identificada con este lead para cumplirse. Se va con el lead.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."actividad_id" IS 'Resultado registrado por la encuesta (único). Cambia solo si se deshizo y se registró el corregido. Se va con la actividad.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."via" IS 'Por dónde se abrió la encuesta: al_colgar (la URL de la macro) o pestana (la pestaña «Llamadas del celular»). Pasa al enlace.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."creado_en" IS 'Cuándo se guardó la encuesta. De aquí corren los 32 días.';

COMMENT ON COLUMN "private"."llamadas_celular_intenciones"."actualizado_en" IS 'Último cambio (solo al pasar al resultado corregido; lo sella el trigger).';

CREATE TABLE IF NOT EXISTS "private"."llamadas_celular_recepciones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "evento_origen_id" "text" NOT NULL,
    "asignacion_id" "uuid" NOT NULL,
    "recibido_en" timestamp with time zone NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actualizado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "llamadas_celular_recepciones_origen_valido" CHECK (("evento_origen_id" ~ '^C[1-9][0-9]{0,2}-[0-9]{10}$'::"text"))
);

COMMENT ON TABLE "private"."llamadas_celular_recepciones" IS 'Una fila por cada llamada del celular ACEPTADA (id válido), registrada antes de buscar el lead, también si después se ignora (fallo 1 de la revisión del 02/10). Única por id: el primer envío gana y un reenvío responde lo mismo sin buscar nada. Caduca a los 32 días (la purga diaria), cuando su id ya no puede volver a entrar por la ventana. Tabla técnica de private, sin acceso para la API y sin auditoría (como private.celulares_estado): guarda el id y la asignación, sin número ni hash; aun así dice a qué hora llamaba el analista, por eso caduca. Sin columna de tenant: CRM de una sola empresa.';

COMMENT ON COLUMN "private"."llamadas_celular_recepciones"."id" IS 'Identificador de la recepción.';

COMMENT ON COLUMN "private"."llamadas_celular_recepciones"."evento_origen_id" IS 'Id de la llamada tal como lo genera la macro: C<n>-<segundos del reloj del celular>. Único.';

COMMENT ON COLUMN "private"."llamadas_celular_recepciones"."asignacion_id" IS 'Asignación cuya clave trajo el aviso (crm.celulares_asignaciones).';

COMMENT ON COLUMN "private"."llamadas_celular_recepciones"."recibido_en" IS 'Hora del servidor al aceptarla (la que toma la puerta tras bloquear el estado del celular). De aquí corren los 32 días.';

COMMENT ON COLUMN "private"."llamadas_celular_recepciones"."creado_en" IS 'Alta de la fila.';

COMMENT ON COLUMN "private"."llamadas_celular_recepciones"."actualizado_en" IS 'Igual a creado_en: la fila es inmutable.';

CREATE TABLE IF NOT EXISTS "private"."membresias_purgadas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "perfil_id" "uuid" NOT NULL,
    "rol_crm" "text",
    "activo_al_purgar" boolean,
    "motivo" "text" NOT NULL,
    "purgado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "motivo_de_verdad" CHECK (("length"("btrim"("motivo")) >= 20))
);

COMMENT ON TABLE "private"."membresias_purgadas" IS 'P-055 F5.a. Lapidas de membresias de crm.equipo borradas por la puerta declarada. Si alguien vuelve a aparecer aqui, su baja se hizo purgando y no apagando.';

CREATE TABLE IF NOT EXISTS "private"."pares_autoridad" (
    "rol_portal" "text" NOT NULL,
    "rol_crm" "text",
    "razon" "text" NOT NULL,
    CONSTRAINT "razon_de_verdad" CHECK (("length"("btrim"("razon")) >= 30))
);

COMMENT ON TABLE "private"."pares_autoridad" IS 'P-055 F5.b (D4). Los pares rol-Portal <-> rol-CRM que la casa reconoce. Un par que no este aqui no puede existir: lo vigilan los candados de crm.equipo y public.perfiles (valvula crm.cambiando_par para transiciones ordenadas).';

CREATE TABLE IF NOT EXISTS "private"."respaldo_cierre_agosto_2026" (
    "tabla" "text",
    "fila" "jsonb",
    "guardado_en" timestamp with time zone
);

COMMENT ON TABLE "private"."respaldo_cierre_agosto_2026" IS 'Foto del cierre de agosto 2026 tal como estaba antes de reabrirlo el 17/09/2026 para cargar contratos atrasados. Se restaura con 03-restaurar.sql.';

CREATE TABLE IF NOT EXISTS "private"."respaldo_cierre_septiembre_2026" (
    "tabla" "text",
    "fila" "jsonb",
    "guardado_en" timestamp with time zone
);

COMMENT ON TABLE "private"."respaldo_cierre_septiembre_2026" IS 'Sello, foto, acreditaciones, rastros de registro tardío y cierres en cooperativa de septiembre 2026 tal como estaban antes de reabrirlo el 14/10/2026 para cargar ventas atrasadas, más la huella del mes reabierto. Se restaura con scripts/reexpresion-septiembre-2026/03-restaurar.sql.';

CREATE TABLE IF NOT EXISTS "private"."usuarios_retirados" (
    "perfil_id" "uuid" NOT NULL,
    "nombre_completo" "text" NOT NULL,
    "rol_portal" "text" NOT NULL,
    "rol_crm" "text",
    "retirado_por" "uuid" NOT NULL,
    "retirado_en" timestamp with time zone DEFAULT "clock_timestamp"() NOT NULL,
    "resultado" "text" NOT NULL,
    CONSTRAINT "usuarios_retirados_resultado_check" CHECK (("resultado" = ANY (ARRAY['eliminado'::"text", 'historial_conservado'::"text"])))
);

CREATE TABLE IF NOT EXISTS "private"."vigia_alertas" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "fase" "text" NOT NULL,
    "motivo" "text" NOT NULL,
    "creado_en" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resuelta_en" timestamp with time zone
);

COMMENT ON TABLE "private"."vigia_alertas" IS 'P-055. Alertas de los vigias de trinquete (F5.a vigencia, F6.a analitica). Deny-by-default: la lee quien opere como postgres/service_role.';

ALTER TABLE ONLY "crm"."actividad_ciclo_contexto"
    ADD CONSTRAINT "actividad_ciclo_contexto_pkey" PRIMARY KEY ("actividad_id");

ALTER TABLE ONLY "crm"."actividades_cliente"
    ADD CONSTRAINT "actividades_cliente_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."actividades_cliente"
    ADD CONSTRAINT "actividades_cliente_tarea_id_key" UNIQUE ("tarea_id");

ALTER TABLE ONLY "crm"."actividades"
    ADD CONSTRAINT "actividades_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."agenda_ics"
    ADD CONSTRAINT "agenda_ics_pkey" PRIMARY KEY ("perfil_id");

ALTER TABLE ONLY "crm"."agenda_ics"
    ADD CONSTRAINT "agenda_ics_token_key" UNIQUE ("token");

ALTER TABLE ONLY "crm"."ajustes_mes_cerrado"
    ADD CONSTRAINT "ajustes_mes_cerrado_lead_id_key" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."ajustes_mes_cerrado"
    ADD CONSTRAINT "ajustes_mes_cerrado_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."alertas_reconocimientos"
    ADD CONSTRAINT "alertas_reconocimientos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."alertas_reconocimientos"
    ADD CONSTRAINT "alertas_reconocimientos_secuencia_unica" UNIQUE ("secuencia");

COMMENT ON CONSTRAINT "alertas_reconocimientos_secuencia_unica" ON "crm"."alertas_reconocimientos" IS 'F4.2: «el último asiento manda» se resuelve por secuencia; la identity ya es monotónica y este UNIQUE cierra la vía anómala (restauración, doble carga) que sembraría empates con ganador arbitrario.';

ALTER TABLE ONLY "crm"."backfill_multiempresa_mapa"
    ADD CONSTRAINT "backfill_mapa_fuente_fila_uq" UNIQUE ("fuente", "fila_id");

ALTER TABLE ONLY "crm"."backfill_multiempresa_mapa"
    ADD CONSTRAINT "backfill_multiempresa_mapa_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_base_lead_unico" UNIQUE ("base_id", "lead_id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."base_carga_operaciones"
    ADD CONSTRAINT "base_carga_operaciones_actor_operacion_unica" UNIQUE ("actor", "operacion_id");

ALTER TABLE ONLY "crm"."base_carga_operaciones"
    ADD CONSTRAINT "base_carga_operaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."bases_carga"
    ADD CONSTRAINT "bases_carga_operacion_unica" UNIQUE ("operacion_id");

ALTER TABLE ONLY "crm"."bases_carga"
    ADD CONSTRAINT "bases_carga_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."busquedas_cliente_existente"
    ADD CONSTRAINT "busquedas_cliente_existente_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cambio_cuenta_avisos"
    ADD CONSTRAINT "cambio_cuenta_avisos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cambio_cuenta_avisos"
    ADD CONSTRAINT "cambio_cuenta_avisos_solicitud_uq" UNIQUE ("solicitud_id");

ALTER TABLE ONLY "crm"."capital_cortes_valorados"
    ADD CONSTRAINT "capital_cortes_valorados_periodo_revision_key" UNIQUE ("periodo", "revision");

ALTER TABLE ONLY "crm"."capital_cortes_valorados"
    ADD CONSTRAINT "capital_cortes_valorados_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."capital_mes_sellos"
    ADD CONSTRAINT "capital_mes_sellos_pkey" PRIMARY KEY ("periodo");

ALTER TABLE ONLY "crm"."capital_valoracion_politica"
    ADD CONSTRAINT "capital_valoracion_politica_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."capital_valoraciones"
    ADD CONSTRAINT "capital_valoraciones_fuente_fuente_id_revision_key" UNIQUE ("fuente", "fuente_id", "revision");

ALTER TABLE ONLY "crm"."capital_valoraciones"
    ADD CONSTRAINT "capital_valoraciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cartera_lecturas"
    ADD CONSTRAINT "cartera_lecturas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."celulares_asignaciones"
    ADD CONSTRAINT "celulares_asignaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."celulares_asignaciones"
    ADD CONSTRAINT "celulares_asignaciones_sin_solape" EXCLUDE USING "gist" ("etiqueta" WITH =, "tstzrange"("vigente_desde", COALESCE("vigente_hasta", 'infinity'::timestamp with time zone), '[)'::"text") WITH &&);

ALTER TABLE ONLY "crm"."cierre_mes_vendedor"
    ADD CONSTRAINT "cierre_mes_vendedor_pkey" PRIMARY KEY ("periodo", "vendedor_id");

ALTER TABLE ONLY "crm"."cierres_avance_anulados"
    ADD CONSTRAINT "cierres_avance_anulados_lead_id_key" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."cierres_avance_anulados"
    ADD CONSTRAINT "cierres_avance_anulados_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."configuracion_reparto"
    ADD CONSTRAINT "configuracion_reparto_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."configuracion_reparto"
    ADD CONSTRAINT "configuracion_reparto_singleton_key" UNIQUE ("singleton");

ALTER TABLE ONLY "crm"."contrato_cuenta_pago_asignaciones"
    ADD CONSTRAINT "contrato_cuenta_pago_asignaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."contrato_cuenta_pago_asignaciones"
    ADD CONSTRAINT "contrato_cuenta_pago_asignaciones_solicitud_uq" UNIQUE ("solicitud_id");

ALTER TABLE ONLY "crm"."contrato_cuenta_pago_cambios"
    ADD CONSTRAINT "contrato_cuenta_pago_cambios_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."contrato_cuenta_pago_cambios"
    ADD CONSTRAINT "contrato_cuenta_pago_cambios_solicitud_contrato_uq" UNIQUE ("solicitud_id", "contrato_id");

ALTER TABLE ONLY "crm"."contrato_cuentas_pago"
    ADD CONSTRAINT "contrato_cuentas_pago_contrato_id_key" UNIQUE ("contrato_id");

ALTER TABLE ONLY "crm"."contrato_cuentas_pago"
    ADD CONSTRAINT "contrato_cuentas_pago_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."contratos_eliminados_auditoria"
    ADD CONSTRAINT "contratos_eliminados_auditoria_contrato_id_key" UNIQUE ("contrato_id");

ALTER TABLE ONLY "crm"."contratos_eliminados_auditoria"
    ADD CONSTRAINT "contratos_eliminados_auditoria_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."control_citas_aplicaciones"
    ADD CONSTRAINT "control_citas_aplicaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."control_citas_aplicaciones"
    ADD CONSTRAINT "control_citas_aplicaciones_version_key" UNIQUE ("version");

ALTER TABLE ONLY "crm"."control_citas_versiones"
    ADD CONSTRAINT "control_citas_versiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."control_citas_versiones"
    ADD CONSTRAINT "control_citas_versiones_version_key" UNIQUE ("version");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_episodio_id_key" UNIQUE ("episodio_id");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_fuente_tipo_fuente_id_key" UNIQUE ("fuente_tipo", "fuente_id");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_lead_id_key" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."conversion_pesos"
    ADD CONSTRAINT "conversion_pesos_pkey" PRIMARY KEY ("vigente_desde");

ALTER TABLE ONLY "crm"."conversion_politica"
    ADD CONSTRAINT "conversion_politica_pkey" PRIMARY KEY ("unica");

ALTER TABLE ONLY "crm"."conversion_reservas"
    ADD CONSTRAINT "conversion_reservas_lead_id_key" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."conversion_reservas"
    ADD CONSTRAINT "conversion_reservas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."conversion_ventas_recuperadas"
    ADD CONSTRAINT "conversion_ventas_recuperadas_cierre_avance_anulado_id_key" UNIQUE ("cierre_avance_anulado_id");

ALTER TABLE ONLY "crm"."conversion_ventas_recuperadas"
    ADD CONSTRAINT "conversion_ventas_recuperadas_inversion_eliminada_id_key" UNIQUE ("inversion_eliminada_id");

ALTER TABLE ONLY "crm"."conversion_ventas_recuperadas"
    ADD CONSTRAINT "conversion_ventas_recuperadas_lead_unico" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."conversion_ventas_recuperadas"
    ADD CONSTRAINT "conversion_ventas_recuperadas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."correcciones_categoria_contrato"
    ADD CONSTRAINT "correcciones_categoria_contrato_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."correcciones_correo_acceso"
    ADD CONSTRAINT "correcciones_correo_acceso_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cuentas_bancarias"
    ADD CONSTRAINT "cuentas_bancarias_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cuentas_bancarias_retiros"
    ADD CONSTRAINT "cuentas_bancarias_retiros_cuenta_uq" UNIQUE ("cuenta_id");

ALTER TABLE ONLY "crm"."cuentas_bancarias_retiros"
    ADD CONSTRAINT "cuentas_bancarias_retiros_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."cuentas_bancarias_retiros"
    ADD CONSTRAINT "cuentas_bancarias_retiros_solicitud_uq" UNIQUE ("solicitud_id");

ALTER TABLE ONLY "crm"."cuotas_cuenta_pagada"
    ADD CONSTRAINT "cuotas_cuenta_pagada_cuota_uq" UNIQUE ("cuota_id");

ALTER TABLE ONLY "crm"."cuotas_cuenta_pagada"
    ADD CONSTRAINT "cuotas_cuenta_pagada_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."depositos_reclamados"
    ADD CONSTRAINT "depositos_reclamados_numero_norm_key" UNIQUE ("numero_norm");

ALTER TABLE ONLY "crm"."depositos_reclamados"
    ADD CONSTRAINT "depositos_reclamados_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."dispositivos_push_tasa"
    ADD CONSTRAINT "dispositivos_push_tasa_endpoint_key" UNIQUE ("endpoint");

ALTER TABLE ONLY "crm"."dispositivos_push_tasa"
    ADD CONSTRAINT "dispositivos_push_tasa_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."empresas"
    ADD CONSTRAINT "empresas_clave_key" UNIQUE ("clave");

ALTER TABLE ONLY "crm"."empresas"
    ADD CONSTRAINT "empresas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."enfriamiento_politica"
    ADD CONSTRAINT "enfriamiento_politica_pkey" PRIMARY KEY ("motivo");

ALTER TABLE ONLY "crm"."envios_push_tasa"
    ADD CONSTRAINT "envios_push_tasa_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."envios_push_tasa"
    ADD CONSTRAINT "envios_push_tasa_solicitud_id_dispositivo_id_key" UNIQUE ("solicitud_id", "dispositivo_id");

ALTER TABLE ONLY "crm"."equipo"
    ADD CONSTRAINT "equipo_pkey" PRIMARY KEY ("perfil_id");

ALTER TABLE ONLY "crm"."gestion_diaria_control_avisos"
    ADD CONSTRAINT "gestion_diaria_control_avisos_pkey" PRIMARY KEY ("version");

ALTER TABLE ONLY "crm"."gestion_diaria_entregas"
    ADD CONSTRAINT "gestion_diaria_entregas_perfil_id_alerta_id_entrega_key" UNIQUE ("perfil_id", "alerta_id", "entrega");

ALTER TABLE ONLY "crm"."gestion_diaria_entregas"
    ADD CONSTRAINT "gestion_diaria_entregas_perfil_id_solicitud_id_key" UNIQUE ("perfil_id", "solicitud_id");

ALTER TABLE ONLY "crm"."gestion_diaria_entregas"
    ADD CONSTRAINT "gestion_diaria_entregas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_ajustes_mes_cerrado"
    ADD CONSTRAINT "inversion_ajustes_mes_cerrado_pkey" PRIMARY KEY ("inversion_id");

ALTER TABLE ONLY "crm"."inversion_backfill_lotes"
    ADD CONSTRAINT "inversion_backfill_lotes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_contrato_titular_id_key" UNIQUE ("contrato_titular_id");

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_eventos"
    ADD CONSTRAINT "inversion_eventos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_correcciones"
    ADD CONSTRAINT "inversion_solicitud_correcciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_correcciones"
    ADD CONSTRAINT "inversion_solicitud_correcciones_solicitud_id_revision_key" UNIQUE ("solicitud_id", "revision");

ALTER TABLE ONLY "crm"."inversion_solicitud_origenes"
    ADD CONSTRAINT "inversion_solicitud_origenes_pkey" PRIMARY KEY ("solicitud_id");

ALTER TABLE ONLY "crm"."inversion_solicitud_revisiones"
    ADD CONSTRAINT "inversion_solicitud_revisiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_revisiones"
    ADD CONSTRAINT "inversion_solicitud_revisiones_solicitud_id_revision_key" UNIQUE ("solicitud_id", "revision");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_inversion_id_key" UNIQUE ("inversion_id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversion_titulares"
    ADD CONSTRAINT "inversion_titulares_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversiones_eliminadas"
    ADD CONSTRAINT "inversiones_eliminadas_fuente_tipo_fuente_id_key" UNIQUE ("fuente_tipo", "fuente_id");

ALTER TABLE ONLY "crm"."inversiones_eliminadas"
    ADD CONSTRAINT "inversiones_eliminadas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversiones_eliminadas"
    ADD CONSTRAINT "inversiones_eliminadas_valvula_key" UNIQUE ("valvula");

ALTER TABLE ONLY "crm"."inversiones"
    ADD CONSTRAINT "inversiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionista_datos_contacto"
    ADD CONSTRAINT "inversionista_datos_contacto_pkey" PRIMARY KEY ("inversionista_id");

ALTER TABLE ONLY "crm"."inversionista_fusiones"
    ADD CONSTRAINT "inversionista_fusiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionista_gestiones"
    ADD CONSTRAINT "inversionista_gestiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionista_identificadores"
    ADD CONSTRAINT "inversionista_identificadores_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionista_leads"
    ADD CONSTRAINT "inversionista_leads_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionista_operaciones"
    ADD CONSTRAINT "inversionista_operaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionista_responsables"
    ADD CONSTRAINT "inversionista_responsables_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."inversionistas"
    ADD CONSTRAINT "inversionistas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_asignacion_sla_hitos"
    ADD CONSTRAINT "lead_asignacion_sla_hitos_lead_asignacion_id_key" UNIQUE ("lead_asignacion_id");

ALTER TABLE ONLY "crm"."lead_asignacion_sla_hitos"
    ADD CONSTRAINT "lead_asignacion_sla_hitos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_episodio_unico" UNIQUE ("lead_id", "ciclo_n", "episodio_n");

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_sin_solape" EXCLUDE USING "gist" ("lead_id" WITH =, "tstzrange"("asignado_en", COALESCE("finalizado_en", 'infinity'::timestamp with time zone), '[)'::"text") WITH &&);

ALTER TABLE ONLY "crm"."lead_potencial_eventos"
    ADD CONSTRAINT "lead_potencial_eventos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_potencial"
    ADD CONSTRAINT "lead_potencial_lead_unico" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."lead_potencial"
    ADD CONSTRAINT "lead_potencial_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_sla_ciclos"
    ADD CONSTRAINT "lead_sla_ciclos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_sla_ciclos"
    ADD CONSTRAINT "lead_sla_ciclos_unico" UNIQUE ("lead_id", "ciclo_n");

ALTER TABLE ONLY "crm"."lead_sla_etapa_ajustes"
    ADD CONSTRAINT "lead_sla_etapa_ajustes_etapa_sla_id_origen_actividad_id_key" UNIQUE ("etapa_sla_id", "origen_actividad_id");

ALTER TABLE ONLY "crm"."lead_sla_etapa_ajustes"
    ADD CONSTRAINT "lead_sla_etapa_ajustes_etapa_sla_id_secuencia_key" UNIQUE ("etapa_sla_id", "secuencia");

ALTER TABLE ONLY "crm"."lead_sla_etapa_ajustes"
    ADD CONSTRAINT "lead_sla_etapa_ajustes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."lead_sla_etapas"
    ADD CONSTRAINT "lead_sla_etapas_episodio_uk" UNIQUE ("lead_id", "ciclo_n", "episodio_n");

ALTER TABLE ONLY "crm"."lead_sla_etapas"
    ADD CONSTRAINT "lead_sla_etapas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."leads_eliminados"
    ADD CONSTRAINT "leads_eliminados_lead_id_key" UNIQUE ("lead_id");

ALTER TABLE ONLY "crm"."leads_eliminados"
    ADD CONSTRAINT "leads_eliminados_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."ledger_rentabilidad"
    ADD CONSTRAINT "ledger_rentabilidad_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_actividad_uq" UNIQUE ("actividad_id");

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_evento_uq" UNIQUE ("evento_id");

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_origen_uq" UNIQUE ("evento_origen_id");

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."llamadas_celular_politica"
    ADD CONSTRAINT "llamadas_celular_politica_pkey" PRIMARY KEY ("singleton");

ALTER TABLE ONLY "crm"."meta_periodos"
    ADD CONSTRAINT "meta_periodos_periodo_revision_uk" UNIQUE ("periodo", "revision");

ALTER TABLE ONLY "crm"."meta_periodos"
    ADD CONSTRAINT "meta_periodos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."metas_vendedor_detalle"
    ADD CONSTRAINT "metas_vendedor_detalle_dimension_uk" UNIQUE ("meta_vendedor_id", "categoria", "moneda");

ALTER TABLE ONLY "crm"."metas_vendedor_detalle"
    ADD CONSTRAINT "metas_vendedor_detalle_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."metas_vendedor"
    ADD CONSTRAINT "metas_vendedor_periodo_vendedor_uk" UNIQUE ("meta_periodo_id", "vendedor_id");

ALTER TABLE ONLY "crm"."metas_vendedor"
    ADD CONSTRAINT "metas_vendedor_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."multiempresa_flags"
    ADD CONSTRAINT "multiempresa_flags_pkey" PRIMARY KEY ("nombre");

ALTER TABLE ONLY "crm"."multiempresa_idempotencia"
    ADD CONSTRAINT "multiempresa_idempotencia_pkey" PRIMARY KEY ("clave");

ALTER TABLE ONLY "crm"."objetivos_legacy_archivo"
    ADD CONSTRAINT "objetivos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."objetivos_legacy_archivo"
    ADD CONSTRAINT "objetivos_un_periodo_rol" UNIQUE ("periodo", "rol");

ALTER TABLE ONLY "crm"."objetivos_vendedores_legacy_archivo"
    ADD CONSTRAINT "objetivos_vendedores_periodo_vendedor_uk" UNIQUE ("periodo", "vendedor_id");

ALTER TABLE ONLY "crm"."objetivos_vendedores_legacy_archivo"
    ADD CONSTRAINT "objetivos_vendedores_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_contrato_nuevo_id_key" UNIQUE ("contrato_nuevo_id");

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."origenes_capital_confirmados"
    ADD CONSTRAINT "origenes_capital_confirmados_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."periodos_cerrados"
    ADD CONSTRAINT "periodos_cerrados_pkey" PRIMARY KEY ("periodo");

ALTER TABLE ONLY "crm"."piloto_f8_control"
    ADD CONSTRAINT "piloto_f8_control_pkey" PRIMARY KEY ("singleton");

ALTER TABLE ONLY "crm"."piloto_f8_miembros"
    ADD CONSTRAINT "piloto_f8_miembros_pkey" PRIMARY KEY ("perfil_id");

ALTER TABLE ONLY "crm"."plazos_carga_mes"
    ADD CONSTRAINT "plazos_carga_mes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."plazos_carga_mes"
    ADD CONSTRAINT "plazos_carga_mes_reapertura_key" UNIQUE ("reapertura_id");

ALTER TABLE ONLY "crm"."politica_abandono"
    ADD CONSTRAINT "politica_abandono_pkey" PRIMARY KEY ("singleton");

ALTER TABLE ONLY "crm"."politica_gestion_diaria"
    ADD CONSTRAINT "politica_gestion_diaria_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."politica_gestion_diaria"
    ADD CONSTRAINT "politica_gestion_diaria_version_key" UNIQUE ("version");

ALTER TABLE ONLY "crm"."politica_rentabilidad"
    ADD CONSTRAINT "politica_rentabilidad_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."politica_rentabilidad"
    ADD CONSTRAINT "politica_rentabilidad_version_key" UNIQUE ("version");

ALTER TABLE ONLY "crm"."politica_rentabilidad"
    ADD CONSTRAINT "politica_rentabilidad_vigente_desde_key" UNIQUE ("vigente_desde");

ALTER TABLE ONLY "crm"."postventa_escrituras"
    ADD CONSTRAINT "postventa_escrituras_pkey" PRIMARY KEY ("transaccion", "tarea_id");

ALTER TABLE ONLY "crm"."postventa_operaciones"
    ADD CONSTRAINT "postventa_operaciones_pkey" PRIMARY KEY ("actor_id", "clave");

ALTER TABLE ONLY "crm"."postventa_retiros"
    ADD CONSTRAINT "postventa_retiros_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."producto_condiciones"
    ADD CONSTRAINT "producto_condiciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_numero_uk" UNIQUE ("producto_id", "numero_version");

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."productos_inversion"
    ADD CONSTRAINT "productos_inversion_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."reaperturas_mes"
    ADD CONSTRAINT "reaperturas_mes_id_periodo_key" UNIQUE ("id", "periodo");

ALTER TABLE ONLY "crm"."reaperturas_mes"
    ADD CONSTRAINT "reaperturas_mes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."reaperturas_mes"
    ADD CONSTRAINT "reaperturas_mes_transaccion_key" UNIQUE ("transaccion", "reabierto_en");

ALTER TABLE ONLY "crm"."reasignaciones_analista"
    ADD CONSTRAINT "reasignaciones_analista_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."recordatorios_disponibilidad"
    ADD CONSTRAINT "recordatorios_disponibilidad_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."recordatorios_disponibilidad"
    ADD CONSTRAINT "recordatorios_disponibilidad_unico" UNIQUE ("perfil_id", "telefono");

ALTER TABLE ONLY "crm"."recorrido_control"
    ADD CONSTRAINT "recorrido_control_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."rentabilidad_hitos"
    ADD CONSTRAINT "rentabilidad_hitos_pkey" PRIMARY KEY ("clave");

ALTER TABLE ONLY "crm"."sla_operacion_control"
    ADD CONSTRAINT "sla_operacion_control_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."sla_operacion_recibos"
    ADD CONSTRAINT "sla_operacion_recibos_pkey" PRIMARY KEY ("actor_id", "operacion_id");

ALTER TABLE ONLY "crm"."sla_politica_etapas"
    ADD CONSTRAINT "sla_politica_etapas_dimension_uk" UNIQUE ("politica_id", "etapa");

ALTER TABLE ONLY "crm"."sla_politica_etapas_operacion"
    ADD CONSTRAINT "sla_politica_etapas_operacion_pkey" PRIMARY KEY ("politica_id", "etapa");

ALTER TABLE ONLY "crm"."sla_politica_etapas"
    ADD CONSTRAINT "sla_politica_etapas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."sla_politicas"
    ADD CONSTRAINT "sla_politicas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."sla_politicas"
    ADD CONSTRAINT "sla_politicas_version_key" UNIQUE ("version");

ALTER TABLE ONLY "crm"."sla_politicas"
    ADD CONSTRAINT "sla_politicas_vigente_desde_key" UNIQUE ("vigente_desde");

ALTER TABLE ONLY "crm"."solicitudes_desechadas_corridas"
    ADD CONSTRAINT "solicitudes_desechadas_corridas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."solicitudes_tasa"
    ADD CONSTRAINT "solicitudes_tasa_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."tarea_sla_contexto"
    ADD CONSTRAINT "tarea_sla_contexto_pkey" PRIMARY KEY ("tarea_id");

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."tipo_cambio_diario"
    ADD CONSTRAINT "tipo_cambio_diario_pkey" PRIMARY KEY ("fecha_corte", "politica");

ALTER TABLE ONLY "crm"."tipo_cambio_trabajos"
    ADD CONSTRAINT "tipo_cambio_trabajos_pkey" PRIMARY KEY ("fecha_corte", "politica");

ALTER TABLE ONLY "crm"."usuario_eventos"
    ADD CONSTRAINT "usuario_eventos_idempotencia_unica" UNIQUE ("actor_id", "accion", "idempotencia");

ALTER TABLE ONLY "crm"."usuario_eventos"
    ADD CONSTRAINT "usuario_eventos_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "crm"."verificaciones_lead"
    ADD CONSTRAINT "verificaciones_lead_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."agenda_reparto_cambios"
    ADD CONSTRAINT "agenda_reparto_cambios_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."agenda_reparto_destinos"
    ADD CONSTRAINT "agenda_reparto_destinos_orden_key" UNIQUE ("orden");

ALTER TABLE ONLY "private"."agenda_reparto_destinos"
    ADD CONSTRAINT "agenda_reparto_destinos_pkey" PRIMARY KEY ("supervisor_id");

ALTER TABLE ONLY "private"."agenda_reparto_diaria"
    ADD CONSTRAINT "agenda_reparto_diaria_pkey" PRIMARY KEY ("fecha", "origen");

ALTER TABLE ONLY "private"."analista_vigencia_exenciones"
    ADD CONSTRAINT "analista_vigencia_exenciones_pkey" PRIMARY KEY ("objeto");

ALTER TABLE ONLY "private"."analista_vigencia_tope"
    ADD CONSTRAINT "analista_vigencia_tope_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."analitica_lc_sello"
    ADD CONSTRAINT "analitica_lc_sello_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."analitica_leads_citas_exenciones"
    ADD CONSTRAINT "analitica_leads_citas_exenciones_pkey" PRIMARY KEY ("objeto");

ALTER TABLE ONLY "private"."analitica_leads_citas_tope"
    ADD CONSTRAINT "analitica_leads_citas_tope_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."auditoria_alertas"
    ADD CONSTRAINT "auditoria_alertas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."auditoria_condicionada"
    ADD CONSTRAINT "auditoria_condicionada_pkey" PRIMARY KEY ("tabla");

ALTER TABLE ONLY "private"."auditoria_exenciones"
    ADD CONSTRAINT "auditoria_exenciones_pkey" PRIMARY KEY ("tabla");

ALTER TABLE ONLY "private"."auditoria_sello"
    ADD CONSTRAINT "auditoria_sello_pkey" PRIMARY KEY ("unico");

ALTER TABLE ONLY "private"."ayuda_consultas"
    ADD CONSTRAINT "ayuda_consultas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."ayuda_expresiones"
    ADD CONSTRAINT "ayuda_expresiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."ayuda_expresiones"
    ADD CONSTRAINT "ayuda_expresiones_texto_normalizado_key" UNIQUE ("texto_normalizado");

ALTER TABLE ONLY "private"."ayuda_intenciones"
    ADD CONSTRAINT "ayuda_intenciones_clave_version_key" UNIQUE ("clave", "version");

ALTER TABLE ONLY "private"."ayuda_intenciones"
    ADD CONSTRAINT "ayuda_intenciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."ayuda_reglas_aclaracion"
    ADD CONSTRAINT "ayuda_reglas_aclaracion_clave_key" UNIQUE ("clave");

ALTER TABLE ONLY "private"."ayuda_reglas_aclaracion"
    ADD CONSTRAINT "ayuda_reglas_aclaracion_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."backfill_cuentas_p0xx"
    ADD CONSTRAINT "backfill_cuentas_p0xx_pkey" PRIMARY KEY ("tipo", "fila_id");

ALTER TABLE ONLY "private"."celulares_estado"
    ADD CONSTRAINT "celulares_estado_asignacion_uq" UNIQUE ("asignacion_id");

ALTER TABLE ONLY "private"."celulares_estado"
    ADD CONSTRAINT "celulares_estado_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."conciliacion_cuentas_p0xx"
    ADD CONSTRAINT "conciliacion_cuentas_p0xx_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."contrato_altas_idempotentes"
    ADD CONSTRAINT "contrato_altas_idempotentes_pkey" PRIMARY KEY ("actor_id", "clave");

ALTER TABLE ONLY "private"."contrato_eliminaciones"
    ADD CONSTRAINT "contrato_eliminaciones_pkey" PRIMARY KEY ("contrato_id");

ALTER TABLE ONLY "private"."contrato_eliminaciones"
    ADD CONSTRAINT "contrato_eliminaciones_token_key" UNIQUE ("token");

ALTER TABLE ONLY "private"."contrato_pdf_anexo_emisiones"
    ADD CONSTRAINT "contrato_pdf_anexo_emisiones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."contrato_pdf_jobs"
    ADD CONSTRAINT "contrato_pdf_jobs_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."contrato_pdf_jobs"
    ADD CONSTRAINT "contrato_pdf_jobs_revision_unica" UNIQUE ("contrato_id", "revision");

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_job_unico" UNIQUE ("job_id");

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_revision_unica" UNIQUE ("contrato_id", "revision");

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_ruta_unica" UNIQUE ("storage_bucket", "storage_path");

ALTER TABLE ONLY "private"."f7_piezas_en_observacion"
    ADD CONSTRAINT "f7_piezas_en_observacion_pkey" PRIMARY KEY ("firma");

ALTER TABLE ONLY "private"."llamadas_celular_intenciones"
    ADD CONSTRAINT "llamadas_celular_intenciones_actividad_uq" UNIQUE ("actividad_id");

ALTER TABLE ONLY "private"."llamadas_celular_intenciones"
    ADD CONSTRAINT "llamadas_celular_intenciones_origen_uq" UNIQUE ("evento_origen_id");

ALTER TABLE ONLY "private"."llamadas_celular_intenciones"
    ADD CONSTRAINT "llamadas_celular_intenciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."llamadas_celular_recepciones"
    ADD CONSTRAINT "llamadas_celular_recepciones_origen_uq" UNIQUE ("evento_origen_id");

ALTER TABLE ONLY "private"."llamadas_celular_recepciones"
    ADD CONSTRAINT "llamadas_celular_recepciones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."membresias_purgadas"
    ADD CONSTRAINT "membresias_purgadas_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "private"."pares_autoridad"
    ADD CONSTRAINT "par_unico" UNIQUE NULLS NOT DISTINCT ("rol_portal", "rol_crm");

ALTER TABLE ONLY "private"."usuarios_retirados"
    ADD CONSTRAINT "usuarios_retirados_pkey" PRIMARY KEY ("perfil_id");

ALTER TABLE ONLY "private"."vigia_alertas"
    ADD CONSTRAINT "vigia_alertas_pkey" PRIMARY KEY ("id");

CREATE INDEX "actividad_ciclo_contexto_lead_ciclo_idx" ON "crm"."actividad_ciclo_contexto" USING "btree" ("lead_id", "ciclo_n", "registrado_en");

CREATE INDEX "actividad_ciclo_contexto_oficina_tarea_idx" ON "crm"."actividad_ciclo_contexto" USING "btree" ("oficina_tarea_id");

CREATE INDEX "actividades_autor_fecha_idx" ON "crm"."actividades" USING "btree" ("creado_por", "creado_en" DESC, "id");

COMMENT ON INDEX "crm"."actividades_autor_fecha_idx" IS 'Gestión Diaria: lecturas por analista y por día (registro crudo, marcador, equipo). Orden = el del cursor keyset (creado_en desc, id).';

CREATE INDEX "actividades_cliente_autor_fecha_idx" ON "crm"."actividades_cliente" USING "btree" ("creado_por", "creado_en", "id");

COMMENT ON INDEX "crm"."actividades_cliente_autor_fecha_idx" IS 'Lectura de gestiones heredadas de clientes por autor y fecha.';

CREATE INDEX "actividades_cliente_cliente_fecha_idx" ON "crm"."actividades_cliente" USING "btree" ("cliente_id", "creado_en" DESC);

CREATE INDEX "actividades_cliente_vendedor_fecha_idx" ON "crm"."actividades_cliente" USING "btree" ("vendedor_id", "creado_en" DESC);

CREATE INDEX "actividades_contacto_episodio_idx" ON "crm"."actividades" USING "btree" ("lead_id", "creado_por", "creado_en") WHERE ("tipo" = ANY (ARRAY['llamada_realizada'::"text", 'llamada_no_contestada'::"text", 'whatsapp_enviado'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text"]));

CREATE INDEX "actividades_reasignacion_historial_idx" ON "crm"."actividades" USING "btree" ("creado_en" DESC, "id" DESC) WHERE ("tipo" = 'reasignacion'::"text");

CREATE INDEX "actividades_recientes_idx" ON "crm"."actividades" USING "btree" ("creado_en" DESC, "id");

COMMENT ON INDEX "crm"."actividades_recientes_idx" IS 'Barrido global newest-first de actividades_del_ambito_fn (ventana + limit 10000).';

CREATE UNIQUE INDEX "alertas_corte_aplazamiento_unico_idx" ON "crm"."alertas_reconocimientos" USING "btree" ("perfil_id", "alerta_id") WHERE (("accion" = 'posponer'::"text") AND "starts_with"("alerta_id", 'grupo:corte_'::"text"));

CREATE UNIQUE INDEX "alertas_corte_solicitud_idx" ON "crm"."alertas_reconocimientos" USING "btree" ("perfil_id", "solicitud_corte_id") WHERE ("solicitud_corte_id" IS NOT NULL);

CREATE INDEX "alertas_reconocimientos_caducidad_idx" ON "crm"."alertas_reconocimientos" USING "btree" ("creado_en");

CREATE INDEX "alertas_reconocimientos_ultimo_idx" ON "crm"."alertas_reconocimientos" USING "btree" ("perfil_id", "alerta_id", "secuencia" DESC);

CREATE INDEX "backfill_mapa_clase_idx" ON "crm"."backfill_multiempresa_mapa" USING "btree" ("clase");

CREATE INDEX "backfill_mapa_inv_idx" ON "crm"."backfill_multiempresa_mapa" USING "btree" ("inversionista_id");

CREATE INDEX "base_carga_leads_agregado_por_idx" ON "crm"."base_carga_leads" USING "btree" ("agregado_por");

CREATE INDEX "base_carga_leads_analista_idx" ON "crm"."base_carga_leads" USING "btree" ("analista_id", "base_id");

CREATE INDEX "base_carga_leads_asignado_por_idx" ON "crm"."base_carga_leads" USING "btree" ("asignado_por");

CREATE INDEX "base_carga_leads_lead_idx" ON "crm"."base_carga_leads" USING "btree" ("lead_id");

CREATE UNIQUE INDEX "base_carga_leads_lead_vivo_unico" ON "crm"."base_carga_leads" USING "btree" ("lead_id") WHERE "activo";

CREATE INDEX "base_carga_operaciones_base_idx" ON "crm"."base_carga_operaciones" USING "btree" ("base_id", "creado_en");

CREATE INDEX "bases_carga_creada_por_idx" ON "crm"."bases_carga" USING "btree" ("creada_por");

CREATE UNIQUE INDEX "bases_carga_nombre_vivo_unico" ON "crm"."bases_carga" USING "btree" ("supervisor_id", "lower"("nombre")) WHERE "activo";

CREATE INDEX "bases_carga_supervisor_idx" ON "crm"."bases_carga" USING "btree" ("supervisor_id");

CREATE INDEX "busquedas_cliente_existente_actor_idx" ON "crm"."busquedas_cliente_existente" USING "btree" ("consultado_por", "creado_en" DESC);

CREATE INDEX "busquedas_cliente_existente_lead_idx" ON "crm"."busquedas_cliente_existente" USING "btree" ("lead_id") WHERE ("lead_id" IS NOT NULL);

CREATE INDEX "busquedas_cliente_existente_persona_idx" ON "crm"."busquedas_cliente_existente" USING "btree" ("inversionista_id") WHERE ("inversionista_id" IS NOT NULL);

CREATE INDEX "capital_cortes_meta_periodo" ON "crm"."capital_cortes_valorados" USING "btree" ("meta_periodo_id");

CREATE INDEX "capital_cortes_ultimo" ON "crm"."capital_cortes_valorados" USING "btree" ("periodo", "revision" DESC);

CREATE INDEX "capital_mes_sellos_corte" ON "crm"."capital_mes_sellos" USING "btree" ("corte_id");

CREATE INDEX "capital_valoraciones_anterior" ON "crm"."capital_valoraciones" USING "btree" ("anterior_id");

CREATE INDEX "capital_valoraciones_fuente_actual" ON "crm"."capital_valoraciones" USING "btree" ("fuente", "fuente_id", "revision" DESC);

CREATE INDEX "capital_valoraciones_tipo_cambio" ON "crm"."capital_valoraciones" USING "btree" ("fecha_tc", "politica_tc");

CREATE INDEX "cartera_lecturas_actor_fecha_idx" ON "crm"."cartera_lecturas" USING "btree" ("actor_id", "creado_en" DESC);

CREATE INDEX "cartera_lecturas_persona_fecha_idx" ON "crm"."cartera_lecturas" USING "btree" ("inversionista_id", "creado_en" DESC);

CREATE INDEX "celulares_asignaciones_analista_idx" ON "crm"."celulares_asignaciones" USING "btree" ("analista_id", "vigente_desde" DESC);

CREATE INDEX "celulares_asignaciones_creado_por_idx" ON "crm"."celulares_asignaciones" USING "btree" ("creado_por");

CREATE UNIQUE INDEX "celulares_asignaciones_credencial_uq" ON "crm"."celulares_asignaciones" USING "btree" ("credencial_hash");

CREATE UNIQUE INDEX "celulares_asignaciones_etiqueta_vigente_uq" ON "crm"."celulares_asignaciones" USING "btree" ("etiqueta") WHERE ("vigente_hasta" IS NULL);

CREATE INDEX "cierres_externos_comprobante_idx" ON "crm"."cierres_externos" USING "btree" ("comprobante_objeto_id");

CREATE INDEX "cierres_externos_fecha_imputacion_idx" ON "crm"."cierres_externos" USING "btree" ("fecha_imputacion") WHERE ("fecha_imputacion" IS NOT NULL);

CREATE UNIQUE INDEX "cierres_externos_inicial_por_lead_uidx" ON "crm"."cierres_externos" USING "btree" ("lead_id") WHERE "es_cierre_inicial";

CREATE INDEX "cierres_externos_inversionista_idx" ON "crm"."cierres_externos" USING "btree" ("inversionista_id");

CREATE INDEX "cierres_externos_lead_idx" ON "crm"."cierres_externos" USING "btree" ("lead_id");

CREATE INDEX "contrato_cuenta_pago_cambios_cliente_idx" ON "crm"."contrato_cuenta_pago_cambios" USING "btree" ("cliente_id", "cambiado_en" DESC);

CREATE INDEX "contrato_cuenta_pago_cambios_contrato_idx" ON "crm"."contrato_cuenta_pago_cambios" USING "btree" ("contrato_id", "cambiado_en" DESC);

CREATE INDEX "contrato_cuenta_pago_cambios_respaldo_idx" ON "crm"."contrato_cuenta_pago_cambios" USING "btree" ("respaldo_ruta");

CREATE INDEX "contrato_cuentas_pago_creado_por_idx" ON "crm"."contrato_cuentas_pago" USING "btree" ("creado_por") WHERE ("creado_por" IS NOT NULL);

CREATE INDEX "contrato_cuentas_pago_cuenta_idx" ON "crm"."contrato_cuentas_pago" USING "btree" ("cuenta_bancaria_id");

CREATE INDEX "control_citas_aplicaciones_actor" ON "crm"."control_citas_aplicaciones" USING "btree" ("aplicado_por");

CREATE INDEX "control_citas_aplicaciones_vigencia" ON "crm"."control_citas_aplicaciones" USING "btree" ("mes_inicio" DESC, "version" DESC);

CREATE INDEX "control_citas_versiones_actor" ON "crm"."control_citas_versiones" USING "btree" ("guardado_por");

CREATE INDEX "conversion_acreditaciones_periodo_analista_idx" ON "crm"."conversion_acreditaciones" USING "btree" ("periodo_comercial", "analista_id");

CREATE INDEX "conversion_acreditaciones_persona_idx" ON "crm"."conversion_acreditaciones" USING "btree" ("inversionista_id");

CREATE INDEX "conversion_reservas_inv_idx" ON "crm"."conversion_reservas" USING "btree" ("inversionista_id") WHERE ("inversionista_id" IS NOT NULL);

CREATE INDEX "correcciones_categoria_contrato_busqueda_idx" ON "crm"."correcciones_categoria_contrato" USING "btree" ("contrato_id", "transaccion");

CREATE UNIQUE INDEX "cuentas_bancarias_cci_activa_uidx" ON "crm"."cuentas_bancarias" USING "btree" ("cliente_id", "moneda", "cci") WHERE ("activa" = true);

CREATE INDEX "cuentas_bancarias_cliente_fk_idx" ON "crm"."cuentas_bancarias" USING "btree" ("cliente_id");

CREATE INDEX "cuentas_bancarias_cliente_moneda_idx" ON "crm"."cuentas_bancarias" USING "btree" ("cliente_id", "moneda", "creado_en" DESC) WHERE ("activa" = true);

CREATE INDEX "cuentas_bancarias_creado_por_idx" ON "crm"."cuentas_bancarias" USING "btree" ("creado_por") WHERE ("creado_por" IS NOT NULL);

CREATE INDEX "cuentas_bancarias_desactivada_por_idx" ON "crm"."cuentas_bancarias" USING "btree" ("desactivada_por") WHERE ("desactivada_por" IS NOT NULL);

CREATE INDEX "cuentas_bancarias_retiros_cliente_idx" ON "crm"."cuentas_bancarias_retiros" USING "btree" ("cliente_id", "retirado_en" DESC);

CREATE INDEX "cuotas_cuenta_pagada_contrato_idx" ON "crm"."cuotas_cuenta_pagada" USING "btree" ("contrato_id");

CREATE INDEX "cuotas_cuenta_pagada_cuenta_idx" ON "crm"."cuotas_cuenta_pagada" USING "btree" ("cuenta_bancaria_id");

CREATE INDEX "dispositivos_push_tasa_perfil_idx" ON "crm"."dispositivos_push_tasa" USING "btree" ("perfil_id");

CREATE INDEX "enfriamiento_politica_actualizado_por_idx" ON "crm"."enfriamiento_politica" USING "btree" ("actualizado_por") WHERE ("actualizado_por" IS NOT NULL);

CREATE INDEX "envios_push_tasa_dispositivo_idx" ON "crm"."envios_push_tasa" USING "btree" ("dispositivo_id");

CREATE INDEX "envios_push_tasa_pendientes_idx" ON "crm"."envios_push_tasa" USING "btree" ("disponible_en") WHERE ("estado" = ANY (ARRAY['pendiente'::"text", 'enviando'::"text"]));

CREATE INDEX "gestion_diaria_control_autor_idx" ON "crm"."gestion_diaria_control_avisos" USING "btree" ("creado_por");

CREATE INDEX "idx_actividades_lead" ON "crm"."actividades" USING "btree" ("lead_id", "creado_en" DESC);

CREATE INDEX "idx_ajustes_mes_cerrado_pendiente" ON "crm"."ajustes_mes_cerrado" USING "btree" ("vendedor_id") WHERE ("saldado_en" IS NULL);

CREATE INDEX "idx_cierre_mes_vendedor_vendedor" ON "crm"."cierre_mes_vendedor" USING "btree" ("vendedor_id", "periodo" DESC);

CREATE INDEX "idx_cierres_avance_anulados_en" ON "crm"."cierres_avance_anulados" USING "btree" ("anulado_en");

CREATE INDEX "idx_cierres_avance_anulados_por" ON "crm"."cierres_avance_anulados" USING "btree" ("anulado_por");

CREATE INDEX "idx_cierres_externos_anulado_por" ON "crm"."cierres_externos" USING "btree" ("anulado_por");

CREATE INDEX "idx_cierres_externos_creado_en" ON "crm"."cierres_externos" USING "btree" ("creado_en");

CREATE INDEX "idx_cierres_externos_creado_por" ON "crm"."cierres_externos" USING "btree" ("creado_por");

CREATE INDEX "idx_cierres_externos_vendedor_creado" ON "crm"."cierres_externos" USING "btree" ("vendedor_id", "creado_en" DESC);

CREATE INDEX "idx_conversion_reservas_reservado_por" ON "crm"."conversion_reservas" USING "btree" ("reservado_por");

CREATE INDEX "idx_depositos_reclamados_cierre" ON "crm"."depositos_reclamados" USING "btree" ("cierre_id");

CREATE INDEX "idx_depositos_reclamados_por" ON "crm"."depositos_reclamados" USING "btree" ("reclamado_por");

CREATE INDEX "idx_equipo_creado_por" ON "crm"."equipo" USING "btree" ("creado_por");

CREATE INDEX "idx_equipo_supervisor" ON "crm"."equipo" USING "btree" ("supervisor_id") WHERE ("activo" = true);

CREATE INDEX "idx_leads_base_rellamada" ON "crm"."leads" USING "btree" ("vendedor_id", "proxima_llamada_en") WHERE (("etapa" = 'descartado'::"text") AND ("proxima_llamada_en" IS NOT NULL));

COMMENT ON INDEX "crm"."idx_leads_base_rellamada" IS 'Base para gestión (B1b): agenda propia de la base («Llamar hoy» y contador del menú) por analista. Solo descartados con rellamada.';

CREATE INDEX "idx_leads_clasificacion_auto" ON "crm"."leads" USING "btree" ("clasificacion_auto") WHERE ("clasificacion_auto" IS NOT NULL);

CREATE INDEX "idx_leads_contrato" ON "crm"."leads" USING "btree" ("contrato_id") WHERE ("contrato_id" IS NOT NULL);

CREATE INDEX "idx_leads_convertido_en" ON "crm"."leads" USING "btree" ("convertido_en") WHERE ("etapa" = 'convertido'::"text");

CREATE INDEX "idx_leads_creado_en" ON "crm"."leads" USING "btree" ("creado_en");

COMMENT ON INDEX "crm"."idx_leads_creado_en" IS 'Prefiltro temporal de series_comerciales_fn (BitmapOr con idx_leads_contrato) y de cualquier ventana por fecha de alta.';

CREATE INDEX "idx_leads_creado_por" ON "crm"."leads" USING "btree" ("creado_por");

CREATE INDEX "idx_leads_creado_por_referido" ON "crm"."leads" USING "btree" ("creado_por", "creado_en") WHERE ("origen" = 'referido'::"text");

CREATE INDEX "idx_leads_descartado_por" ON "crm"."leads" USING "btree" ("descartado_por") WHERE ("descartado_por" IS NOT NULL);

CREATE INDEX "idx_leads_descarte" ON "crm"."leads" USING "btree" ("descartado_en" DESC) WHERE ("etapa" = 'descartado'::"text");

CREATE INDEX "idx_leads_etapa" ON "crm"."leads" USING "btree" ("etapa") WHERE ("activo" = true);

CREATE INDEX "idx_leads_parkeo" ON "crm"."leads" USING "btree" ("asignado_supervisor_id") WHERE (("vendedor_id" IS NULL) AND ("activo" = true));

CREATE INDEX "idx_leads_perfil" ON "crm"."leads" USING "btree" ("perfil_id") WHERE ("perfil_id" IS NOT NULL);

CREATE INDEX "idx_leads_tenencia" ON "crm"."leads" USING "btree" ("vendedor_id", "tenencia_desde" DESC) WHERE ("activo" AND ("vendedor_id" IS NOT NULL));

CREATE INDEX "idx_leads_vendedor" ON "crm"."leads" USING "btree" ("vendedor_id") WHERE ("activo" = true);

CREATE INDEX "idx_leads_vendedor_creado_en" ON "crm"."leads" USING "btree" ("vendedor_id", "creado_en") WHERE ("vendedor_id" IS NOT NULL);

COMMENT ON INDEX "crm"."idx_leads_vendedor_creado_en" IS 'Dueno + ventana de alta: sirve el ambito scopeado de metricas_conversiones_equipo_fn. Parcial por vendedor_id not null (deducible del = any(array)); NO parcial por activo.';

CREATE INDEX "inv_fusiones_canonico_idx" ON "crm"."inversionista_fusiones" USING "btree" ("canonico_id");

CREATE INDEX "inv_fusiones_fusionado_idx" ON "crm"."inversionista_fusiones" USING "btree" ("fusionado_id");

CREATE UNIQUE INDEX "inv_fusiones_fusionado_uidx" ON "crm"."inversionista_fusiones" USING "btree" ("fusionado_id");

CREATE INDEX "inv_operaciones_ident_ant_idx" ON "crm"."inversionista_operaciones" USING "btree" ("identificador_anterior_id");

CREATE INDEX "inv_operaciones_ident_nuevo_idx" ON "crm"."inversionista_operaciones" USING "btree" ("identificador_nuevo_id");

CREATE INDEX "inv_operaciones_inv_idx" ON "crm"."inversionista_operaciones" USING "btree" ("inversionista_id");

CREATE INDEX "inv_operaciones_lead_idx" ON "crm"."inversionista_operaciones" USING "btree" ("lead_id");

CREATE INDEX "inv_operaciones_por_idx" ON "crm"."inversionista_operaciones" USING "btree" ("por");

CREATE UNIQUE INDEX "inv_responsables_abierto_uidx" ON "crm"."inversionista_responsables" USING "btree" ("inversionista_id") WHERE ("hasta" IS NULL);

CREATE INDEX "inv_responsables_inv_idx" ON "crm"."inversionista_responsables" USING "btree" ("inversionista_id");

CREATE INDEX "inv_responsables_resp_idx" ON "crm"."inversionista_responsables" USING "btree" ("responsable_id");

CREATE INDEX "inversion_ajustes_creador_idx" ON "crm"."inversion_ajustes_mes_cerrado" USING "btree" ("creado_por");

CREATE INDEX "inversion_ajustes_periodo_idx" ON "crm"."inversion_ajustes_mes_cerrado" USING "btree" ("periodo_origen");

CREATE INDEX "inversion_correcciones_actor_idx" ON "crm"."inversion_solicitud_correcciones" USING "btree" ("corregido_por");

CREATE INDEX "inversion_cotitular_origen_actor_idx" ON "crm"."inversion_cotitular_origenes" USING "btree" ("vinculado_por");

CREATE INDEX "inversion_cotitular_origen_identificador_idx" ON "crm"."inversion_cotitular_origenes" USING "btree" ("identificador_origen_id");

CREATE INDEX "inversion_cotitular_origen_inversion_idx" ON "crm"."inversion_cotitular_origenes" USING "btree" ("inversion_id");

CREATE INDEX "inversion_cotitular_origen_persona_idx" ON "crm"."inversion_cotitular_origenes" USING "btree" ("persona_origen_id");

CREATE INDEX "inversion_eventos_creador_idx" ON "crm"."inversion_eventos" USING "btree" ("creado_por");

CREATE INDEX "inversion_eventos_inversion_idx" ON "crm"."inversion_eventos" USING "btree" ("inversion_id", "creado_en");

CREATE INDEX "inversion_revision_actor_idx" ON "crm"."inversion_solicitud_revisiones" USING "btree" ("revisado_por");

CREATE INDEX "inversion_revision_anterior_idx" ON "crm"."inversion_solicitud_revisiones" USING "btree" ("responsable_anterior_id");

CREATE INDEX "inversion_revision_nuevo_idx" ON "crm"."inversion_solicitud_revisiones" USING "btree" ("responsable_nuevo_id");

CREATE UNIQUE INDEX "inversion_solicitud_conversion_unica" ON "crm"."inversion_solicitudes" USING "btree" ("lead_origen_id") WHERE (("lead_origen_id" IS NOT NULL) AND ("estado" = ANY (ARRAY['preparada'::"text", 'confirmada'::"text"])));

CREATE UNIQUE INDEX "inversion_solicitud_cruzada_pendiente" ON "crm"."inversion_solicitudes" USING "btree" ("inversionista_id", "empresa_id") WHERE (("puerta" = 'cliente_existente'::"text") AND ("estado" = 'preparada'::"text"));

COMMENT ON INDEX "crm"."inversion_solicitud_cruzada_pendiente" IS 'Decisión D6: una sola venta cruzada en preparación por persona y empresa.';

CREATE INDEX "inversion_solicitudes_analista_idx" ON "crm"."inversion_solicitudes" USING "btree" ("analista_cierre_id") WHERE ("analista_cierre_id" IS NOT NULL);

CREATE INDEX "inversion_solicitudes_auth_idx" ON "crm"."inversion_solicitudes" USING "btree" ("auth_claim_id") WHERE ("auth_claim_id" IS NOT NULL);

CREATE INDEX "inversion_solicitudes_busqueda_idx" ON "crm"."inversion_solicitudes" USING "btree" ("busqueda_id") WHERE ("busqueda_id" IS NOT NULL);

CREATE INDEX "inversion_solicitudes_confirmador_idx" ON "crm"."inversion_solicitudes" USING "btree" ("confirmado_por");

CREATE INDEX "inversion_solicitudes_creador_idx" ON "crm"."inversion_solicitudes" USING "btree" ("creado_por");

CREATE INDEX "inversion_solicitudes_empresa_idx" ON "crm"."inversion_solicitudes" USING "btree" ("empresa_id");

CREATE INDEX "inversion_solicitudes_persona_idx" ON "crm"."inversion_solicitudes" USING "btree" ("inversionista_id", "estado");

CREATE INDEX "inversion_solicitudes_responsable_idx" ON "crm"."inversion_solicitudes" USING "btree" ("responsable_esperado_id");

CREATE INDEX "inversion_titulares_inv_idx" ON "crm"."inversion_titulares" USING "btree" ("inversionista_id");

CREATE UNIQUE INDEX "inversion_titulares_par_uidx" ON "crm"."inversion_titulares" USING "btree" ("inversion_id", "inversionista_id");

CREATE UNIQUE INDEX "inversion_titulares_principal_uidx" ON "crm"."inversion_titulares" USING "btree" ("inversion_id") WHERE ("rol" = 'principal'::"text");

CREATE UNIQUE INDEX "inversiones_cierre_uidx" ON "crm"."inversiones" USING "btree" ("cierre_externo_id") WHERE ("cierre_externo_id" IS NOT NULL);

CREATE UNIQUE INDEX "inversiones_contrato_uidx" ON "crm"."inversiones" USING "btree" ("contrato_id") WHERE ("contrato_id" IS NOT NULL);

CREATE INDEX "inversiones_eliminadas_lead_anulada_idx" ON "crm"."inversiones_eliminadas" USING "btree" ("lead_id") WHERE "conversion_anulada";

CREATE INDEX "inversiones_empresa_idx" ON "crm"."inversiones" USING "btree" ("empresa_id");

CREATE INDEX "inversiones_estado_idx" ON "crm"."inversiones" USING "btree" ("estado");

CREATE INDEX "inversiones_inv_idx" ON "crm"."inversiones" USING "btree" ("inversionista_id");

CREATE INDEX "inversionista_gestiones_autor_fecha_idx" ON "crm"."inversionista_gestiones" USING "btree" ("creado_por", "creado_en", "id") WHERE ("tipo" = 'cierre'::"text");

COMMENT ON INDEX "crm"."inversionista_gestiones_autor_fecha_idx" IS 'Lectura de cierres de clientes por autor y fecha.';

CREATE INDEX "inversionista_gestiones_cierre_tarea_idx" ON "crm"."inversionista_gestiones" USING "btree" ("tarea_id") WHERE ("tipo" = 'cierre'::"text");

COMMENT ON INDEX "crm"."inversionista_gestiones_cierre_tarea_idx" IS 'Exclusión del espejo heredado cuando la tarea tiene un cierre F6.';

CREATE INDEX "inversionista_gestiones_persona_fecha" ON "crm"."inversionista_gestiones" USING "btree" ("inversionista_id", "creado_en" DESC, "id");

CREATE INDEX "inversionista_identificadores_inv_idx" ON "crm"."inversionista_identificadores" USING "btree" ("inversionista_id");

CREATE UNIQUE INDEX "inversionista_identificadores_vigente_uidx" ON "crm"."inversionista_identificadores" USING "btree" ("tipo_documento", "documento_normalizado") WHERE ("estado" = 'vigente'::"text");

CREATE UNIQUE INDEX "inversionista_leads_canonico_uidx" ON "crm"."inversionista_leads" USING "btree" ("inversionista_id") WHERE ("rol" = 'canonico'::"text");

CREATE INDEX "inversionista_leads_inv_idx" ON "crm"."inversionista_leads" USING "btree" ("inversionista_id");

CREATE UNIQUE INDEX "inversionista_leads_lead_uidx" ON "crm"."inversionista_leads" USING "btree" ("lead_id");

CREATE INDEX "inversionistas_canonico_idx" ON "crm"."inversionistas" USING "btree" ("inversionista_canonico_id");

CREATE INDEX "inversionistas_estado_idx" ON "crm"."inversionistas" USING "btree" ("estado");

CREATE INDEX "inversionistas_perfil_idx" ON "crm"."inversionistas" USING "btree" ("perfil_id");

COMMENT ON INDEX "crm"."inversionistas_perfil_idx" IS 'Búsqueda de personas por perfil sin la condición del índice único parcial (inversionistas_perfil_uidx). La usa el lateral por contrato de private.cartera_f5_fuentes; antes recorría la tabla entera por cada contrato (medido 29/09/2026).';

CREATE UNIQUE INDEX "inversionistas_perfil_uidx" ON "crm"."inversionistas" USING "btree" ("perfil_id") WHERE (("perfil_id" IS NOT NULL) AND ("estado" <> 'fusionado'::"text"));

CREATE INDEX "inversionistas_responsable_idx" ON "crm"."inversionistas" USING "btree" ("responsable_relacion_id");

CREATE INDEX "lead_asignaciones_analista_destino_idx" ON "crm"."lead_asignaciones" USING "btree" ("analista_destino_id") WHERE ("analista_destino_id" IS NOT NULL);

CREATE INDEX "lead_asignaciones_analista_fecha_idx" ON "crm"."lead_asignaciones" USING "btree" ("analista_id", "asignado_en" DESC);

CREATE INDEX "lead_asignaciones_asignado_por_idx" ON "crm"."lead_asignaciones" USING "btree" ("asignado_por") WHERE ("asignado_por" IS NOT NULL);

CREATE INDEX "lead_asignaciones_cohorte_idx" ON "crm"."lead_asignaciones" USING "btree" ("asignado_en");

CREATE INDEX "lead_asignaciones_convertido_analista_idx" ON "crm"."lead_asignaciones" USING "btree" ("analista_id", COALESCE("resultado_en", "finalizado_en")) WHERE ("resultado" = 'convertido'::"text");

CREATE INDEX "lead_asignaciones_convertido_fecha_idx" ON "crm"."lead_asignaciones" USING "btree" (COALESCE("resultado_en", "finalizado_en")) WHERE ("resultado" = 'convertido'::"text");

CREATE INDEX "lead_asignaciones_finalizado_por_idx" ON "crm"."lead_asignaciones" USING "btree" ("finalizado_por") WHERE ("finalizado_por" IS NOT NULL);

CREATE INDEX "lead_asignaciones_lead_fecha_idx" ON "crm"."lead_asignaciones" USING "btree" ("lead_id", "asignado_en" DESC);

CREATE INDEX "lead_asignaciones_reporte_coordinacion_fecha_idx" ON "crm"."lead_asignaciones" USING "btree" ("asignado_en" DESC) INCLUDE ("analista_id", "supervisor_origen_id", "asignado_por", "origen", "motivo_cierre", "supervisor_destino_id") WHERE ("motivo_apertura" = ANY (ARRAY['asignado'::"text", 'reasignado'::"text"]));

CREATE INDEX "lead_asignaciones_reporte_supervisor_fecha_idx" ON "crm"."lead_asignaciones" USING "btree" ("supervisor_origen_id", "asignado_por", "asignado_en" DESC, "analista_id") WHERE ("motivo_apertura" = ANY (ARRAY['asignado'::"text", 'reasignado'::"text"]));

CREATE INDEX "lead_asignaciones_rescate_descartes_fecha_idx" ON "crm"."lead_asignaciones" USING "btree" ("resultado_en" DESC, "id") WHERE ("resultado" = 'descartado'::"text");

CREATE INDEX "lead_asignaciones_rescate_descartes_idx" ON "crm"."lead_asignaciones" USING "btree" ("analista_id", "resultado_en" DESC) WHERE ("resultado" = 'descartado'::"text");

CREATE INDEX "lead_asignaciones_sla_global_cohorte_idx" ON "crm"."lead_asignaciones" USING "btree" ("sla_global_iniciado_en", "lead_id", "ciclo_n");

CREATE INDEX "lead_asignaciones_sla_politica_idx" ON "crm"."lead_asignaciones" USING "btree" ("sla_politica_asignacion_id", "asignado_en" DESC);

CREATE INDEX "lead_asignaciones_supervisor_destino_idx" ON "crm"."lead_asignaciones" USING "btree" ("supervisor_destino_id") WHERE ("supervisor_destino_id" IS NOT NULL);

CREATE INDEX "lead_asignaciones_supervisor_origen_idx" ON "crm"."lead_asignaciones" USING "btree" ("supervisor_origen_id") WHERE ("supervisor_origen_id" IS NOT NULL);

CREATE INDEX "lead_asignaciones_terminal_analista_idx" ON "crm"."lead_asignaciones" USING "btree" ("analista_id", "finalizado_en" DESC) WHERE ("motivo_cierre" = ANY (ARRAY['convertido'::"text", 'descartado'::"text"]));

CREATE UNIQUE INDEX "lead_asignaciones_un_abierto_por_lead_idx" ON "crm"."lead_asignaciones" USING "btree" ("lead_id") WHERE ("finalizado_en" IS NULL);

CREATE UNIQUE INDEX "lead_asignaciones_una_conversion_por_lead_idx" ON "crm"."lead_asignaciones" USING "btree" ("lead_id") WHERE (("motivo_cierre" = 'convertido'::"text") OR ("resultado" = 'convertido'::"text"));

COMMENT ON INDEX "crm"."lead_asignaciones_una_conversion_por_lead_idx" IS 'Un lead se convierte UNA sola vez en toda su vida. Hasta ahora eso solo lo sostenia CODIGO (private.trg_leads_guard_tenencia y la guardia del ledger), y el codigo se apaga: `disable trigger` es un patron ya usado en esta tabla en 20260807203757, y crm.ledger_writer es un simple GUC. lead_asignaciones_sin_solape NO cubre esto: dos episodios convertidos adyacentes [10,11) y [11,12) no se solapan, y los de duracion cero dan rango vacio. El count(distinct lead_id) de la migracion A tampoco: agrupa POR ANALISTA, asi que dos cierres del mismo lead atribuidos a analistas distintos suman 1+1 en el total de equipo (200 % con divisor 1). NO se pone sobre `resultado` a secas: los descartes repetidos del mismo lead son un flujo vivo.';

CREATE INDEX "lead_potencial_eventos_lead_idx" ON "crm"."lead_potencial_eventos" USING "btree" ("lead_id", "orden" DESC);

CREATE INDEX "lead_potencial_eventos_por_idx" ON "crm"."lead_potencial_eventos" USING "btree" ("por") WHERE ("por" IS NOT NULL);

CREATE INDEX "lead_potencial_marcado_por_idx" ON "crm"."lead_potencial" USING "btree" ("marcado_por");

CREATE INDEX "lead_potencial_nivel_idx" ON "crm"."lead_potencial" USING "btree" ("nivel", "lead_id");

CREATE INDEX "lead_sla_ciclos_lead_fecha_idx" ON "crm"."lead_sla_ciclos" USING "btree" ("lead_id", "iniciado_en" DESC);

CREATE INDEX "lead_sla_ciclos_periodo_idx" ON "crm"."lead_sla_ciclos" USING "btree" ("iniciado_en", "politica_id");

CREATE INDEX "lead_sla_etapa_ajustes_actividad_idx" ON "crm"."lead_sla_etapa_ajustes" USING "btree" ("origen_actividad_id");

CREATE INDEX "lead_sla_etapa_ajustes_autor_idx" ON "crm"."lead_sla_etapa_ajustes" USING "btree" ("creado_por");

CREATE INDEX "lead_sla_etapas_lead_fecha_idx" ON "crm"."lead_sla_etapas" USING "btree" ("lead_id", "iniciado_en" DESC);

CREATE INDEX "lead_sla_etapas_periodo_idx" ON "crm"."lead_sla_etapas" USING "btree" ("iniciado_en", "politica_id", "etapa");

CREATE UNIQUE INDEX "lead_sla_etapas_un_abierto_idx" ON "crm"."lead_sla_etapas" USING "btree" ("lead_id") WHERE ("finalizado_en" IS NULL);

CREATE INDEX "leads_dni_trgm_idx" ON "crm"."leads" USING "gin" ("dni" "extensions"."gin_trgm_ops") WHERE ("dni" IS NOT NULL);

COMMENT ON INDEX "crm"."leads_dni_trgm_idx" IS 'Busqueda ilike %digitos% por DNI en la cartera paginada. Parcial: dni es nullable y el predicado se deduce del propio ilike.';

CREATE UNIQUE INDEX "leads_inversionista_uidx" ON "crm"."leads" USING "btree" ("inversionista_id") WHERE ("inversionista_id" IS NOT NULL);

CREATE INDEX "leads_nombre_trgm_idx" ON "crm"."leads" USING "gin" ("nombre_completo" "extensions"."gin_trgm_ops");

COMMENT ON INDEX "crm"."leads_nombre_trgm_idx" IS 'Busqueda ilike %texto% por nombre en la cartera paginada.';

CREATE INDEX "leads_orden_cartera_idx" ON "crm"."leads" USING "btree" ("actualizado_en" DESC, "id");

COMMENT ON INDEX "crm"."leads_orden_cartera_idx" IS 'Orden de las lecturas de cartera (actualizado_en desc, id). No parcial a proposito: la consulta del ambito no envia activo=true explicito.';

CREATE INDEX "leads_telefono_trgm_idx" ON "crm"."leads" USING "gin" ("telefono" "extensions"."gin_trgm_ops");

COMMENT ON INDEX "crm"."leads_telefono_trgm_idx" IS 'Busqueda ilike %digitos% por telefono en la cartera paginada.';

CREATE INDEX "leads_vendedor_orden_idx" ON "crm"."leads" USING "btree" ("vendedor_id", "actualizado_en" DESC) WHERE ("vendedor_id" IS NOT NULL);

COMMENT ON INDEX "crm"."leads_vendedor_orden_idx" IS 'Cartera de un vendedor ya ordenada: evita el sort cuando la RLS recorta por vendedor_id antes de ordenar.';

CREATE INDEX "ledger_rentabilidad_cliente_idx" ON "crm"."ledger_rentabilidad" USING "btree" ("cliente_id");

CREATE INDEX "ledger_rentabilidad_contrato_idx" ON "crm"."ledger_rentabilidad" USING "btree" ("contrato_id", "registrado_en" DESC);

CREATE INDEX "ledger_rentabilidad_registrado_idx" ON "crm"."ledger_rentabilidad" USING "btree" ("registrado_en" DESC);

CREATE INDEX "ledger_rentabilidad_secuencia_idx" ON "crm"."ledger_rentabilidad" USING "btree" ("contrato_id", "secuencia" DESC);

CREATE UNIQUE INDEX "ledger_rentabilidad_una_legacy_por_contrato" ON "crm"."ledger_rentabilidad" USING "btree" ("contrato_id") WHERE ("origen" = 'backfill_legacy'::"text");

CREATE INDEX "llamadas_celular_enlaces_actualizado_idx" ON "crm"."llamadas_celular_enlaces" USING "btree" ("actualizado_en", "evento_id");

CREATE INDEX "llamadas_celular_enlaces_enlazado_por_idx" ON "crm"."llamadas_celular_enlaces" USING "btree" ("enlazado_por");

CREATE INDEX "llamadas_celular_enlaces_lead_idx" ON "crm"."llamadas_celular_enlaces" USING "btree" ("lead_id");

CREATE INDEX "llamadas_celular_eventos_analista_atencion_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("analista_id", "atencion", "recibido_en" DESC);

CREATE INDEX "llamadas_celular_eventos_asignacion_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("asignacion_id");

CREATE INDEX "llamadas_celular_eventos_asociado_por_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("asociado_por");

CREATE INDEX "llamadas_celular_eventos_descartado_en_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("descartado_en", "id") WHERE ("atencion" = 'descartado_con_motivo'::"text");

CREATE INDEX "llamadas_celular_eventos_descartado_por_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("descartado_por");

CREATE INDEX "llamadas_celular_eventos_lead_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("lead_id", "recibido_en" DESC);

CREATE INDEX "llamadas_celular_eventos_numero_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("numero_canonico") WHERE ("numero_canonico" IS NOT NULL);

CREATE INDEX "llamadas_celular_eventos_recibido_idx" ON "crm"."llamadas_celular_eventos" USING "btree" ("recibido_en");

CREATE INDEX "llamadas_celular_politica_actualizado_por_idx" ON "crm"."llamadas_celular_politica" USING "btree" ("actualizado_por");

CREATE INDEX "meta_periodos_publicada_por_idx" ON "crm"."meta_periodos" USING "btree" ("publicada_por");

CREATE INDEX "meta_periodos_revision_anterior_idx" ON "crm"."meta_periodos" USING "btree" ("revision_anterior_id") WHERE ("revision_anterior_id" IS NOT NULL);

CREATE INDEX "meta_periodos_vigente_idx" ON "crm"."meta_periodos" USING "btree" ("periodo", "revision" DESC);

CREATE INDEX "metas_vendedor_detalle_meta_idx" ON "crm"."metas_vendedor_detalle" USING "btree" ("meta_vendedor_id");

CREATE INDEX "metas_vendedor_supervisor_idx" ON "crm"."metas_vendedor" USING "btree" ("supervisor_id", "meta_periodo_id");

CREATE INDEX "metas_vendedor_vendedor_idx" ON "crm"."metas_vendedor" USING "btree" ("vendedor_id", "meta_periodo_id");

CREATE INDEX "objetivos_actualizado_por_idx" ON "crm"."objetivos_legacy_archivo" USING "btree" ("actualizado_por") WHERE ("actualizado_por" IS NOT NULL);

CREATE INDEX "operaciones_cartera_cliente_periodo_idx" ON "crm"."operaciones_cartera" USING "btree" ("cliente_id", "periodo", "fecha_operacion", "creado_en", "id");

CREATE UNIQUE INDEX "operaciones_cartera_origen_renovado_uidx" ON "crm"."operaciones_cartera" USING "btree" ("contrato_origen_id") WHERE ("contrato_origen_id" IS NOT NULL);

CREATE INDEX "operaciones_cartera_periodo_vendedor_idx" ON "crm"."operaciones_cartera" USING "btree" ("periodo", "vendedor_id");

CREATE UNIQUE INDEX "origenes_capital_contrato_activo" ON "crm"."origenes_capital_confirmados" USING "btree" ("contrato_id") WHERE "activo";

CREATE UNIQUE INDEX "origenes_capital_externo_activo" ON "crm"."origenes_capital_confirmados" USING "btree" ("cierre_externo_id") WHERE "activo";

CREATE INDEX "plazos_carga_mes_decidido_por_idx" ON "crm"."plazos_carga_mes" USING "btree" ("decidido_por");

CREATE INDEX "plazos_carga_mes_periodo_idx" ON "crm"."plazos_carga_mes" USING "btree" ("periodo", "decidido_en" DESC, "id" DESC);

CREATE INDEX "politica_gestion_diaria_vigencia_idx" ON "crm"."politica_gestion_diaria" USING "btree" ("vigente_desde" DESC, "version" DESC);

CREATE UNIQUE INDEX "postventa_retiro_activo" ON "crm"."postventa_retiros" USING "btree" ("fuente_id") WHERE ("estado" = ANY (ARRAY['solicitada'::"text", 'en_revision'::"text"]));

CREATE INDEX "postventa_retiros_persona" ON "crm"."postventa_retiros" USING "btree" ("inversionista_id", "creado_en" DESC, "id");

CREATE UNIQUE INDEX "producto_condiciones_combinacion_activa_uk" ON "crm"."producto_condiciones" USING "btree" ("version_id", "categoria", "moneda", "plazo_meses", "modalidad", "tipo_interes", "capital_minimo", "capital_maximo", "tasa_referencia", "tasa_minima", "tasa_maxima") WHERE ("activa" AND (NOT "es_legacy"));

CREATE INDEX "producto_condiciones_creado_por_idx" ON "crm"."producto_condiciones" USING "btree" ("creado_por") WHERE ("creado_por" IS NOT NULL);

CREATE INDEX "producto_condiciones_legacy_contrato_idx" ON "crm"."producto_condiciones" USING "btree" ("legacy_contrato_id", "creado_en" DESC) WHERE "es_legacy";

CREATE UNIQUE INDEX "producto_condiciones_orden_activo_uk" ON "crm"."producto_condiciones" USING "btree" ("version_id", "orden") WHERE "activa";

CREATE INDEX "producto_condiciones_retirada_por_idx" ON "crm"."producto_condiciones" USING "btree" ("retirada_por") WHERE ("retirada_por" IS NOT NULL);

CREATE INDEX "producto_condiciones_selector_idx" ON "crm"."producto_condiciones" USING "btree" ("categoria", "moneda", "plazo_meses", "modalidad", "tipo_interes") WHERE ("activa" AND (NOT "es_legacy"));

CREATE INDEX "producto_condiciones_version_activas_idx" ON "crm"."producto_condiciones" USING "btree" ("version_id", "orden") WHERE "activa";

CREATE INDEX "producto_versiones_actualizado_por_idx" ON "crm"."producto_versiones" USING "btree" ("actualizado_por") WHERE ("actualizado_por" IS NOT NULL);

CREATE INDEX "producto_versiones_creado_por_idx" ON "crm"."producto_versiones" USING "btree" ("creado_por") WHERE ("creado_por" IS NOT NULL);

CREATE INDEX "producto_versiones_producto_estado_idx" ON "crm"."producto_versiones" USING "btree" ("producto_id", "estado", "numero_version" DESC);

CREATE INDEX "producto_versiones_publicada_por_idx" ON "crm"."producto_versiones" USING "btree" ("publicada_por") WHERE ("publicada_por" IS NOT NULL);

CREATE INDEX "producto_versiones_retirada_por_idx" ON "crm"."producto_versiones" USING "btree" ("retirada_por") WHERE ("retirada_por" IS NOT NULL);

CREATE UNIQUE INDEX "producto_versiones_un_borrador_uk" ON "crm"."producto_versiones" USING "btree" ("producto_id") WHERE ("estado" = 'borrador'::"text");

CREATE UNIQUE INDEX "producto_versiones_una_publicada_uk" ON "crm"."producto_versiones" USING "btree" ("producto_id") WHERE ("estado" = 'publicada'::"text");

CREATE INDEX "productos_inversion_actualizado_por_idx" ON "crm"."productos_inversion" USING "btree" ("actualizado_por") WHERE ("actualizado_por" IS NOT NULL);

CREATE INDEX "productos_inversion_archivado_por_idx" ON "crm"."productos_inversion" USING "btree" ("archivado_por") WHERE ("archivado_por" IS NOT NULL);

CREATE UNIQUE INDEX "productos_inversion_codigo_uk" ON "crm"."productos_inversion" USING "btree" ("lower"("codigo"));

CREATE INDEX "productos_inversion_creado_por_idx" ON "crm"."productos_inversion" USING "btree" ("creado_por") WHERE ("creado_por" IS NOT NULL);

CREATE INDEX "productos_inversion_estado_idx" ON "crm"."productos_inversion" USING "btree" ("estado", "codigo");

CREATE INDEX "reaperturas_mes_decidido_por_idx" ON "crm"."reaperturas_mes" USING "btree" ("decidido_por");

CREATE INDEX "reaperturas_mes_periodo_idx" ON "crm"."reaperturas_mes" USING "btree" ("periodo", "reabierto_en" DESC, "id" DESC);

CREATE INDEX "reasignaciones_analista_contrato_idx" ON "crm"."reasignaciones_analista" USING "btree" ("contrato_id", "reasignado_en" DESC);

CREATE INDEX "recordatorios_disponibilidad_campana_idx" ON "crm"."recordatorios_disponibilidad" USING "btree" ("perfil_id", "recordar_en");

CREATE INDEX "sla_operacion_recibos_lead_idx" ON "crm"."sla_operacion_recibos" USING "btree" ("lead_id");

CREATE INDEX "sla_politica_etapas_politica_idx" ON "crm"."sla_politica_etapas" USING "btree" ("politica_id");

CREATE INDEX "sla_politicas_publicada_por_idx" ON "crm"."sla_politicas" USING "btree" ("publicada_por") WHERE ("publicada_por" IS NOT NULL);

CREATE INDEX "sla_politicas_version_anterior_idx" ON "crm"."sla_politicas" USING "btree" ("version_anterior_id") WHERE ("version_anterior_id" IS NOT NULL);

CREATE INDEX "sla_politicas_vigencia_idx" ON "crm"."sla_politicas" USING "btree" ("vigente_desde" DESC);

CREATE INDEX "solicitudes_tasa_cliente_idx" ON "crm"."solicitudes_tasa" USING "btree" ("cliente_id");

CREATE INDEX "solicitudes_tasa_estado_idx" ON "crm"."solicitudes_tasa" USING "btree" ("estado", "prioridad_bandeja" DESC, "solicitada_en");

CREATE INDEX "solicitudes_tasa_lead_idx" ON "crm"."solicitudes_tasa" USING "btree" ("lead_id", "solicitada_en" DESC) WHERE ("lead_id" IS NOT NULL);

CREATE INDEX "solicitudes_tasa_resuelta_por_en_idx" ON "crm"."solicitudes_tasa" USING "btree" ("resuelta_por", "resuelta_en" DESC, "id" DESC) WHERE (("resuelta_por" IS NOT NULL) AND ("resuelta_en" IS NOT NULL));

CREATE INDEX "solicitudes_tasa_solicitante_idx" ON "crm"."solicitudes_tasa" USING "btree" ("solicitada_por", "solicitada_en" DESC);

CREATE UNIQUE INDEX "solicitudes_tasa_una_viva_por_huella" ON "crm"."solicitudes_tasa" USING "btree" ("huella") WHERE ("estado" = ANY (ARRAY['pendiente'::"text", 'aprobada'::"text", 'aprobada_con_tope'::"text", 'aceptada_por_analista'::"text"]));

CREATE INDEX "tarea_sla_contexto_ciclo_idx" ON "crm"."tarea_sla_contexto" USING "btree" ("lead_id", "ciclo_n");

CREATE INDEX "tareas_bandeja_idx" ON "crm"."tareas" USING "btree" ("asignado_supervisor_id") WHERE (("vendedor_id" IS NULL) AND ("estado" = 'pendiente'::"text"));

CREATE INDEX "tareas_cola_idx" ON "crm"."tareas" USING "btree" ("vendedor_id", "estado", "vence_en");

CREATE INDEX "tareas_creado_por_idx" ON "crm"."tareas" USING "btree" ("creado_por");

CREATE INDEX "tareas_lead_pendiente_idx" ON "crm"."tareas" USING "btree" ("lead_id") WHERE ("estado" = 'pendiente'::"text");

CREATE INDEX "tareas_pendientes_keyset_idx" ON "crm"."tareas" USING "btree" ("vence_en", "id") WHERE (("estado" = 'pendiente'::"text") AND "activo");

COMMENT ON INDEX "crm"."tareas_pendientes_keyset_idx" IS 'Orden del cursor (vence_en, id) de las tareas pendientes vivas para crm.tareas_pendientes_fn. Rendimiento, no seguridad.';

CREATE INDEX "tareas_perfil_idx" ON "crm"."tareas" USING "btree" ("perfil_id") WHERE ("perfil_id" IS NOT NULL);

CREATE INDEX "tareas_persona_pendiente" ON "crm"."tareas" USING "btree" ("inversionista_id", "vence_en", "id") WHERE (("inversionista_id" IS NOT NULL) AND "activo" AND ("estado" = 'pendiente'::"text"));

CREATE INDEX "tareas_reagendada_de_idx" ON "crm"."tareas" USING "btree" ("reagendada_de") WHERE ("reagendada_de" IS NOT NULL);

CREATE INDEX "tareas_resultado_actividad_idx" ON "crm"."tareas" USING "btree" ("resultado_actividad_id") WHERE ("resultado_actividad_id" IS NOT NULL);

CREATE INDEX "tareas_reuniones_periodo_idx" ON "crm"."tareas" USING "btree" ("vence_en", "vendedor_id") WHERE ("tipo" = 'reunion'::"text");

CREATE INDEX "tareas_reversion_gestion_idx" ON "crm"."tareas" USING "btree" ("lead_id", "creado_por", "creado_en") WHERE ("lead_id" IS NOT NULL);

CREATE INDEX "tipo_cambio_trabajos_pendientes" ON "crm"."tipo_cambio_trabajos" USING "btree" ("proximo_intento_en") WHERE ("completado_en" IS NULL);

CREATE UNIQUE INDEX "uq_leads_dni_vivo" ON "crm"."leads" USING "btree" ("dni") WHERE (("dni" IS NOT NULL) AND ("activo" = true) AND ("etapa" <> ALL (ARRAY['convertido'::"text", 'descartado'::"text"])));

CREATE UNIQUE INDEX "uq_leads_telefono_vivo" ON "crm"."leads" USING "btree" ("telefono") WHERE (("activo" = true) AND ("etapa" <> ALL (ARRAY['convertido'::"text", 'descartado'::"text"])));

CREATE INDEX "usuario_eventos_objetivo_fecha_idx" ON "crm"."usuario_eventos" USING "btree" ("objetivo_id", "creado_en" DESC);

CREATE UNIQUE INDEX "ux_cierres_externos_transaccion" ON "crm"."cierres_externos" USING "btree" ("upper"("btrim"("numero_transaccion")));

CREATE INDEX "verificaciones_lead_autor_idx" ON "crm"."verificaciones_lead" USING "btree" ("verificado_por", "creado_en" DESC);

CREATE INDEX "agenda_reparto_cambios_fecha_idx" ON "private"."agenda_reparto_cambios" USING "btree" ("fecha" DESC, "cambiado_en" DESC);

CREATE UNIQUE INDEX "auditoria_alertas_abierta_unica" ON "private"."auditoria_alertas" USING "btree" ("tabla") WHERE ("resuelta_en" IS NULL);

CREATE INDEX "ayuda_consultas_intencion_idx" ON "private"."ayuda_consultas" USING "btree" ("intencion_id");

CREATE INDEX "ayuda_consultas_retencion_idx" ON "private"."ayuda_consultas" USING "btree" ("retener_hasta");

CREATE INDEX "ayuda_consultas_usuario_fecha_idx" ON "private"."ayuda_consultas" USING "btree" ("usuario_id", "creado_en" DESC);

CREATE INDEX "ayuda_expresiones_intencion_idx" ON "private"."ayuda_expresiones" USING "btree" ("intencion_id");

CREATE INDEX "ayuda_expresiones_trgm_idx" ON "private"."ayuda_expresiones" USING "gin" ("texto_normalizado" "extensions"."gin_trgm_ops");

CREATE INDEX "ayuda_expresiones_vector_idx" ON "private"."ayuda_expresiones" USING "gin" ("vector_busqueda");

CREATE INDEX "ayuda_intenciones_inicio_idx" ON "private"."ayuda_intenciones" USING "btree" ("estado", "prioridad", "clave") INCLUDE ("pregunta", "vistas");

CREATE UNIQUE INDEX "ayuda_intenciones_una_publicada_idx" ON "private"."ayuda_intenciones" USING "btree" ("clave") WHERE ("estado" = 'publicado'::"text");

CREATE INDEX "ayuda_intenciones_vistas_idx" ON "private"."ayuda_intenciones" USING "gin" ("vistas");

CREATE INDEX "contrato_altas_idempotentes_contrato_idx" ON "private"."contrato_altas_idempotentes" USING "btree" ("contrato_id");

CREATE INDEX "contrato_eliminaciones_solicitado_por_idx" ON "private"."contrato_eliminaciones" USING "btree" ("solicitado_por");

CREATE INDEX "contrato_pdf_anexo_emisiones_contrato_idx" ON "private"."contrato_pdf_anexo_emisiones" USING "btree" ("contrato_id", "creado_en" DESC);

CREATE INDEX "contrato_pdf_jobs_estado_idx" ON "private"."contrato_pdf_jobs" USING "btree" ("estado", "actualizado_en");

CREATE INDEX "contrato_pdf_jobs_solicitado_por_idx" ON "private"."contrato_pdf_jobs" USING "btree" ("solicitado_por");

CREATE INDEX "contrato_pdfs_generado_por_idx" ON "private"."contrato_pdfs" USING "btree" ("generado_por");

CREATE INDEX "llamadas_celular_intenciones_analista_idx" ON "private"."llamadas_celular_intenciones" USING "btree" ("analista_id");

CREATE INDEX "llamadas_celular_intenciones_creado_idx" ON "private"."llamadas_celular_intenciones" USING "btree" ("creado_en");

CREATE INDEX "llamadas_celular_intenciones_lead_idx" ON "private"."llamadas_celular_intenciones" USING "btree" ("lead_id");

CREATE INDEX "llamadas_celular_recepciones_asignacion_idx" ON "private"."llamadas_celular_recepciones" USING "btree" ("asignacion_id");

CREATE INDEX "llamadas_celular_recepciones_recibido_idx" ON "private"."llamadas_celular_recepciones" USING "btree" ("recibido_en");

CREATE OR REPLACE TRIGGER "audit_actividad_ciclo_contexto" AFTER INSERT OR DELETE OR UPDATE ON "crm"."actividad_ciclo_contexto" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "audit_configuracion_reparto" AFTER INSERT OR DELETE OR UPDATE ON "crm"."configuracion_reparto" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "audit_recorrido_control" AFTER INSERT OR DELETE OR UPDATE ON "crm"."recorrido_control" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "audit_sla_operacion_recibos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."sla_operacion_recibos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "base_carga_operaciones_inmutable" BEFORE DELETE OR UPDATE ON "crm"."base_carga_operaciones" FOR EACH ROW EXECUTE FUNCTION "private"."bases_carga_operacion_inmutable"();

COMMENT ON TRIGGER "base_carga_operaciones_inmutable" ON "crm"."base_carga_operaciones" IS 'Los recibos de las bases cargadas no se cambian ni se borran (P0409).';

CREATE OR REPLACE TRIGGER "base_carga_operaciones_no_truncate" BEFORE TRUNCATE ON "crm"."base_carga_operaciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."bases_carga_operacion_inmutable"();

COMMENT ON TRIGGER "base_carga_operaciones_no_truncate" ON "crm"."base_carga_operaciones" IS 'Los recibos de las bases cargadas no se vacían con TRUNCATE (P0409).';

CREATE OR REPLACE TRIGGER "busqueda_cliente_inmutable" BEFORE DELETE OR UPDATE ON "crm"."busquedas_cliente_existente" FOR EACH ROW EXECUTE FUNCTION "private"."busqueda_cliente_inmutable"();

CREATE OR REPLACE TRIGGER "busqueda_cliente_no_truncate" BEFORE TRUNCATE ON "crm"."busquedas_cliente_existente" FOR EACH STATEMENT EXECUTE FUNCTION "private"."busqueda_cliente_inmutable"();

CREATE OR REPLACE TRIGGER "control_citas_aplicacion_inmutable" BEFORE DELETE OR UPDATE ON "crm"."control_citas_aplicaciones" FOR EACH ROW EXECUTE FUNCTION "private"."control_citas_version_inmutable"();

CREATE OR REPLACE TRIGGER "control_citas_aplicacion_truncado_denegado" BEFORE TRUNCATE ON "crm"."control_citas_aplicaciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."control_citas_version_inmutable"();

CREATE OR REPLACE TRIGGER "control_citas_truncado_denegado" BEFORE TRUNCATE ON "crm"."control_citas_versiones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."control_citas_version_inmutable"();

CREATE OR REPLACE TRIGGER "control_citas_version_inmutable" BEFORE DELETE OR UPDATE ON "crm"."control_citas_versiones" FOR EACH ROW EXECUTE FUNCTION "private"."control_citas_version_inmutable"();

CREATE OR REPLACE TRIGGER "conversion_reserva_legacy_cerrada" BEFORE INSERT ON "crm"."conversion_reservas" FOR EACH ROW EXECUTE FUNCTION "private"."conversion_reserva_legacy_cerrada"();

CREATE OR REPLACE TRIGGER "correccion_categoria_auditoria" AFTER INSERT ON "crm"."correcciones_categoria_contrato" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "correccion_categoria_inmutable" BEFORE DELETE OR UPDATE ON "crm"."correcciones_categoria_contrato" FOR EACH ROW EXECUTE FUNCTION "private"."trg_correccion_categoria_inmutable"();

CREATE OR REPLACE TRIGGER "inversion_correo_a_ficha" AFTER INSERT OR UPDATE OF "datos" ON "crm"."inversion_solicitudes" FOR EACH ROW EXECUTE FUNCTION "private"."inversion_correo_a_ficha"();

CREATE OR REPLACE TRIGGER "inversion_correo_desde_ficha" AFTER UPDATE OF "correo" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."inversion_correo_desde_ficha"();

CREATE OR REPLACE TRIGGER "inversion_solicitud_atribucion_inmutable" BEFORE UPDATE ON "crm"."inversion_solicitudes" FOR EACH ROW EXECUTE FUNCTION "private"."inversion_atribucion_inmutable"();

CREATE OR REPLACE TRIGGER "inversion_solicitud_origen_inmutable" BEFORE UPDATE ON "crm"."inversion_solicitudes" FOR EACH ROW EXECUTE FUNCTION "private"."inversion_origen_inmutable"();

CREATE OR REPLACE TRIGGER "inversion_solicitud_venta_cruzada_llave" BEFORE INSERT ON "crm"."inversion_solicitudes" FOR EACH ROW WHEN (("new"."puerta" = 'cliente_existente'::"text")) EXECUTE FUNCTION "private"."inversion_venta_cruzada_llave"();

CREATE OR REPLACE TRIGGER "lead_potencial_evento_inmutable" BEFORE DELETE OR UPDATE ON "crm"."lead_potencial_eventos" FOR EACH ROW EXECUTE FUNCTION "private"."potencial_evento_inmutable"();

CREATE OR REPLACE TRIGGER "lead_potencial_evento_no_truncate" BEFORE TRUNCATE ON "crm"."lead_potencial_eventos" FOR EACH STATEMENT EXECUTE FUNCTION "private"."potencial_evento_inmutable"();

CREATE OR REPLACE TRIGGER "recorrido_contexto_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."actividad_ciclo_contexto" FOR EACH ROW EXECUTE FUNCTION "private"."recorrido_contexto_guard"();

CREATE OR REPLACE TRIGGER "recorrido_contexto_no_truncate" BEFORE TRUNCATE ON "crm"."actividad_ciclo_contexto" FOR EACH STATEMENT EXECUTE FUNCTION "private"."recorrido_contexto_guard"();

CREATE OR REPLACE TRIGGER "recorrido_control_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."recorrido_control" FOR EACH ROW EXECUTE FUNCTION "private"."recorrido_control_guard"();

CREATE OR REPLACE TRIGGER "recorrido_control_no_truncate" BEFORE TRUNCATE ON "crm"."recorrido_control" FOR EACH STATEMENT EXECUTE FUNCTION "private"."recorrido_control_guard"();

CREATE OR REPLACE TRIGGER "sla_recibo_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."sla_operacion_recibos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_sla_recibo_guard"();

CREATE OR REPLACE TRIGGER "sla_recibo_truncate_guard" BEFORE TRUNCATE ON "crm"."sla_operacion_recibos" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_sla_recibo_guard"();

CREATE OR REPLACE TRIGGER "trg_00_actividades_base_gestion_solo_nucleo" BEFORE INSERT OR UPDATE OF "metadata" ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."trg_actividades_base_gestion_solo_nucleo"();

CREATE OR REPLACE TRIGGER "trg_00_actividades_no_contactar_solo_puerta" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."trg_actividades_no_contactar_solo_puerta"();

COMMENT ON TRIGGER "trg_00_actividades_no_contactar_solo_puerta" ON "crm"."actividades" IS 'Base para gestión (B6c): la nota del veto (evento no_contactar, sin distinguir mayúsculas ni espacios) solo la escriben sus puertas (válvula crm.op_privilegiada) o sesiones sin usuario, y no se cambia ni se borra; desde la API → 42501. Ver private.trg_actividades_no_contactar_solo_puerta.';

CREATE OR REPLACE TRIGGER "trg_00_actividades_resultado_solo_nucleo" BEFORE INSERT OR UPDATE OF "metadata" ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."trg_actividades_resultado_solo_nucleo"();

CREATE OR REPLACE TRIGGER "trg_00_recorrido_invalidacion" BEFORE DELETE OR UPDATE ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."recorrido_serializar_invalidacion"();

CREATE OR REPLACE TRIGGER "trg_01_gestion_lead_serializada" BEFORE INSERT ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."trg_gestion_lead_serializada"();

CREATE OR REPLACE TRIGGER "trg_02_recorrido_contexto" AFTER INSERT ON "crm"."actividades" FOR EACH ROW WHEN (("new"."tipo" = ANY (ARRAY['llamada_realizada'::"text", 'llamada_no_contestada'::"text", 'whatsapp_enviado'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text"]))) EXECUTE FUNCTION "private"."recorrido_capturar_actividad"();

CREATE OR REPLACE TRIGGER "trg_02_recorrido_lock" BEFORE INSERT ON "crm"."actividades" FOR EACH ROW WHEN (("new"."tipo" = ANY (ARRAY['llamada_realizada'::"text", 'llamada_no_contestada'::"text", 'whatsapp_enviado'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text"]))) EXECUTE FUNCTION "private"."recorrido_bloquear_insert"();

CREATE OR REPLACE TRIGGER "trg_actividades_cliente_01_veto_persona" BEFORE INSERT ON "crm"."actividades_cliente" FOR EACH ROW EXECUTE FUNCTION "private"."trg_actividades_cliente_veto_persona"();

CREATE OR REPLACE TRIGGER "trg_ajustes_mes_cerrado_00_solo_saldar" BEFORE DELETE OR UPDATE ON "crm"."ajustes_mes_cerrado" FOR EACH ROW EXECUTE FUNCTION "private"."trg_ajustes_mes_cerrado_solo_saldar"();

CREATE OR REPLACE TRIGGER "trg_alertas_reconocimientos_00_sellar" BEFORE INSERT ON "crm"."alertas_reconocimientos" FOR EACH ROW EXECUTE FUNCTION "crm"."alertas_reconocimientos_sellar"();

CREATE OR REPLACE TRIGGER "trg_alertas_reconocimientos_01_inmutables" BEFORE DELETE OR UPDATE ON "crm"."alertas_reconocimientos" FOR EACH ROW EXECUTE FUNCTION "crm"."alertas_reconocimientos_inmutables"();

CREATE OR REPLACE TRIGGER "trg_audit" AFTER INSERT ON "crm"."gestion_diaria_control_avisos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit" AFTER INSERT ON "crm"."gestion_diaria_entregas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_actividades" AFTER INSERT ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_actividades_cambio_baja" AFTER DELETE OR UPDATE ON "crm"."actividades" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_actividades_cliente" AFTER INSERT OR DELETE OR UPDATE ON "crm"."actividades_cliente" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_agenda_ics" AFTER INSERT OR DELETE OR UPDATE ON "crm"."agenda_ics" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('token');

CREATE OR REPLACE TRIGGER "trg_audit_ajustes_mes_cerrado" AFTER INSERT OR DELETE OR UPDATE ON "crm"."ajustes_mes_cerrado" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_alertas_reconocimientos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."alertas_reconocimientos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_backfill_mapa" AFTER INSERT OR DELETE OR UPDATE ON "crm"."backfill_multiempresa_mapa" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_base_carga_leads" AFTER INSERT OR DELETE OR UPDATE ON "crm"."base_carga_leads" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_base_carga_operaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."base_carga_operaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_bases_carga" AFTER INSERT OR DELETE OR UPDATE ON "crm"."bases_carga" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_busquedas_cliente_existente" AFTER INSERT OR DELETE OR UPDATE ON "crm"."busquedas_cliente_existente" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('valor_consultado');

CREATE OR REPLACE TRIGGER "trg_audit_cambio_cuenta_avisos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cambio_cuenta_avisos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_capital_cortes" AFTER INSERT ON "crm"."capital_cortes_valorados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_capital_sellos" AFTER INSERT ON "crm"."capital_mes_sellos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_capital_valoracion_politica" AFTER INSERT OR UPDATE ON "crm"."capital_valoracion_politica" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_capital_valoraciones" AFTER INSERT ON "crm"."capital_valoraciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_cartera_lecturas" AFTER INSERT ON "crm"."cartera_lecturas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_celulares_asignaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."celulares_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('credencial_hash');

CREATE OR REPLACE TRIGGER "trg_audit_cierre_mes_vendedor" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cierre_mes_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_cierres_avance_anulados" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cierres_avance_anulados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_cierres_externos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cierres_externos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('documento');

CREATE OR REPLACE TRIGGER "trg_audit_contrato_cuenta_pago_asignaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."contrato_cuenta_pago_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_contrato_cuenta_pago_cambios" AFTER INSERT OR DELETE OR UPDATE ON "crm"."contrato_cuenta_pago_cambios" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_contrato_cuentas_pago" AFTER INSERT OR DELETE OR UPDATE ON "crm"."contrato_cuentas_pago" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_contratos_eliminados" AFTER INSERT ON "crm"."contratos_eliminados_auditoria" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('snapshot', 'archivos');

CREATE OR REPLACE TRIGGER "trg_audit_control_citas_aplicaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."control_citas_aplicaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_control_citas_versiones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."control_citas_versiones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_conversion_acreditaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."conversion_acreditaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_conversion_pesos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."conversion_pesos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_conversion_politica" AFTER INSERT OR DELETE OR UPDATE ON "crm"."conversion_politica" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_conversion_reservas" AFTER INSERT OR DELETE OR UPDATE ON "crm"."conversion_reservas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_conversion_ventas_recuperadas" AFTER INSERT ON "crm"."conversion_ventas_recuperadas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_correcciones_correo_acceso" AFTER INSERT OR DELETE OR UPDATE ON "crm"."correcciones_correo_acceso" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_cotitular_origen" AFTER INSERT ON "crm"."inversion_cotitular_origenes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('fuente_snapshot', 'identificador_snapshot', 'hash_fuente');

CREATE OR REPLACE TRIGGER "trg_audit_cuentas_bancarias" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cuentas_bancarias" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_cuentas_bancarias_retiros" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cuentas_bancarias_retiros" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_cuotas_cuenta_pagada" AFTER INSERT OR DELETE OR UPDATE ON "crm"."cuotas_cuenta_pagada" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_depositos_reclamados" AFTER INSERT OR DELETE OR UPDATE ON "crm"."depositos_reclamados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_dispositivos_push_tasa" AFTER INSERT OR DELETE OR UPDATE ON "crm"."dispositivos_push_tasa" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('endpoint', 'p256dh', 'auth', 'sesion_id');

CREATE OR REPLACE TRIGGER "trg_audit_empresas" AFTER INSERT OR DELETE OR UPDATE ON "crm"."empresas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_enfriamiento_politica" AFTER INSERT OR DELETE OR UPDATE ON "crm"."enfriamiento_politica" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_envios_push_tasa" AFTER INSERT OR DELETE OR UPDATE ON "crm"."envios_push_tasa" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('reserva');

CREATE OR REPLACE TRIGGER "trg_audit_equipo" AFTER INSERT OR DELETE OR UPDATE ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversion_ajustes" AFTER INSERT ON "crm"."inversion_ajustes_mes_cerrado" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversion_backfill_lotes" AFTER INSERT OR UPDATE ON "crm"."inversion_backfill_lotes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('mapa', 'resultado');

CREATE OR REPLACE TRIGGER "trg_audit_inversion_correccion" AFTER INSERT ON "crm"."inversion_solicitud_correcciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('hash_peticion', 'hash_anterior', 'hash_nuevo', 'datos_anteriores', 'datos_nuevos', 'motivo');

CREATE OR REPLACE TRIGGER "trg_audit_inversion_eventos" AFTER INSERT ON "crm"."inversion_eventos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('motivo');

CREATE OR REPLACE TRIGGER "trg_audit_inversion_revision" AFTER INSERT ON "crm"."inversion_solicitud_revisiones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('motivo');

CREATE OR REPLACE TRIGGER "trg_audit_inversion_solicitud_origenes" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversion_solicitud_origenes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversion_solicitudes" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversion_solicitudes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('datos', 'auth_contexto', 'motivo_atribucion');

CREATE OR REPLACE TRIGGER "trg_audit_inversion_titulares" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversion_titulares" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversiones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversiones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversiones_eliminadas" AFTER INSERT ON "crm"."inversiones_eliminadas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('snapshot', 'archivos', 'valvula', 'anulacion');

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_datos_contacto" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_datos_contacto" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_fusiones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_fusiones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_gestiones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_gestiones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_identificadores" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_identificadores" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('documento_normalizado', 'documento_original');

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_leads" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_leads" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_operaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_operaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversionista_responsables" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionista_responsables" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_inversionistas" AFTER INSERT OR DELETE OR UPDATE ON "crm"."inversionistas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_asignacion_sla_hitos" AFTER INSERT OR UPDATE ON "crm"."lead_asignacion_sla_hitos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_asignacion_sla_hitos_completa" AFTER DELETE ON "crm"."lead_asignacion_sla_hitos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_asignaciones" AFTER INSERT OR UPDATE ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_asignaciones_completa" AFTER DELETE ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_potencial" AFTER INSERT OR DELETE OR UPDATE ON "crm"."lead_potencial" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_potencial_eventos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."lead_potencial_eventos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_sla_ciclos" AFTER INSERT OR UPDATE ON "crm"."lead_sla_ciclos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_sla_ciclos_completa" AFTER DELETE ON "crm"."lead_sla_ciclos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_sla_etapa_ajustes" AFTER INSERT OR DELETE OR UPDATE ON "crm"."lead_sla_etapa_ajustes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_sla_etapas" AFTER INSERT OR UPDATE ON "crm"."lead_sla_etapas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_lead_sla_etapas_completa" AFTER DELETE ON "crm"."lead_sla_etapas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_leads" AFTER INSERT OR DELETE OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('dni', 'fecha_nacimiento', 'genero');

CREATE OR REPLACE TRIGGER "trg_audit_leads_eliminados" AFTER INSERT OR DELETE OR UPDATE ON "crm"."leads_eliminados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('copia');

CREATE OR REPLACE TRIGGER "trg_audit_ledger_rentabilidad" AFTER INSERT OR DELETE OR UPDATE ON "crm"."ledger_rentabilidad" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_llamadas_celular_enlaces" AFTER INSERT OR DELETE OR UPDATE ON "crm"."llamadas_celular_enlaces" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_llamadas_celular_eventos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."llamadas_celular_eventos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_sin_secretos"('numero_canonico');

CREATE OR REPLACE TRIGGER "trg_audit_llamadas_celular_politica" AFTER INSERT OR DELETE OR UPDATE ON "crm"."llamadas_celular_politica" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_meta_periodos" AFTER INSERT ON "crm"."meta_periodos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_meta_periodos_completa" AFTER DELETE OR UPDATE ON "crm"."meta_periodos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_metas_vendedor" AFTER INSERT ON "crm"."metas_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_metas_vendedor_completa" AFTER DELETE OR UPDATE ON "crm"."metas_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_metas_vendedor_detalle" AFTER INSERT ON "crm"."metas_vendedor_detalle" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_metas_vendedor_detalle_completa" AFTER DELETE OR UPDATE ON "crm"."metas_vendedor_detalle" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_multiempresa_flags" AFTER INSERT OR DELETE OR UPDATE ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_multiempresa_idempotencia" AFTER INSERT OR DELETE OR UPDATE ON "crm"."multiempresa_idempotencia" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_objetivos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."objetivos_legacy_archivo" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_objetivos_vendedores" AFTER INSERT OR DELETE OR UPDATE ON "crm"."objetivos_vendedores_legacy_archivo" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_operaciones_cartera" AFTER INSERT OR DELETE OR UPDATE ON "crm"."operaciones_cartera" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_origenes_capital_confirmados" AFTER INSERT OR DELETE OR UPDATE ON "crm"."origenes_capital_confirmados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_periodos_cerrados" AFTER INSERT OR DELETE OR UPDATE ON "crm"."periodos_cerrados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_piloto_f8_control" AFTER INSERT OR DELETE OR UPDATE ON "crm"."piloto_f8_control" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_piloto_f8_miembros" AFTER INSERT OR DELETE OR UPDATE ON "crm"."piloto_f8_miembros" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_plazos_carga_mes" AFTER INSERT OR DELETE OR UPDATE ON "crm"."plazos_carga_mes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_politica_abandono" AFTER INSERT OR DELETE OR UPDATE ON "crm"."politica_abandono" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_politica_gestion_diaria" AFTER INSERT ON "crm"."politica_gestion_diaria" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_politica_rentabilidad" AFTER INSERT OR DELETE OR UPDATE ON "crm"."politica_rentabilidad" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_postventa_escrituras" AFTER INSERT OR DELETE OR UPDATE ON "crm"."postventa_escrituras" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_postventa_operaciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."postventa_operaciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_postventa_retiros" AFTER INSERT OR DELETE OR UPDATE ON "crm"."postventa_retiros" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_producto_condiciones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."producto_condiciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_producto_versiones" AFTER INSERT OR DELETE OR UPDATE ON "crm"."producto_versiones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_productos_inversion" AFTER INSERT OR DELETE OR UPDATE ON "crm"."productos_inversion" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_reaperturas_mes" AFTER INSERT OR DELETE OR UPDATE ON "crm"."reaperturas_mes" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_reasignaciones_analista" AFTER INSERT OR DELETE OR UPDATE ON "crm"."reasignaciones_analista" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_recordatorios_disponibilidad" AFTER INSERT OR DELETE OR UPDATE ON "crm"."recordatorios_disponibilidad" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_rentabilidad_hitos" AFTER INSERT OR DELETE OR UPDATE ON "crm"."rentabilidad_hitos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_sla_operacion_control" AFTER INSERT OR DELETE OR UPDATE ON "crm"."sla_operacion_control" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_sla_politica_etapas" AFTER INSERT ON "crm"."sla_politica_etapas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_sla_politica_etapas_completa" AFTER DELETE OR UPDATE ON "crm"."sla_politica_etapas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_sla_politica_etapas_operacion" AFTER INSERT OR DELETE OR UPDATE ON "crm"."sla_politica_etapas_operacion" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_sla_politicas" AFTER INSERT ON "crm"."sla_politicas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_sla_politicas_completa" AFTER DELETE OR UPDATE ON "crm"."sla_politicas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_solicitudes_desechadas_corridas" AFTER INSERT OR DELETE OR UPDATE ON "crm"."solicitudes_desechadas_corridas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_solicitudes_tasa" AFTER INSERT OR DELETE OR UPDATE ON "crm"."solicitudes_tasa" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_tarea_sla_contexto" AFTER INSERT OR DELETE OR UPDATE ON "crm"."tarea_sla_contexto" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_tareas" AFTER INSERT OR DELETE OR UPDATE ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_tipo_cambio_diario" AFTER INSERT ON "crm"."tipo_cambio_diario" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_tipo_cambio_trabajos" AFTER INSERT OR UPDATE ON "crm"."tipo_cambio_trabajos" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_verificaciones_lead" AFTER INSERT OR DELETE OR UPDATE ON "crm"."verificaciones_lead" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_backfill_mapa_touch" BEFORE UPDATE ON "crm"."backfill_multiempresa_mapa" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_base_carga_leads_touch" BEFORE UPDATE ON "crm"."base_carga_leads" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_bases_carga_touch" BEFORE UPDATE ON "crm"."bases_carga" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_cambio_cuenta_avisos_00_no_borrar" BEFORE DELETE ON "crm"."cambio_cuenta_avisos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_registro_cuenta_pago_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_capital_cortes_inmutables" BEFORE DELETE OR UPDATE ON "crm"."capital_cortes_valorados" FOR EACH ROW EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_capital_cortes_sin_truncate" BEFORE TRUNCATE ON "crm"."capital_cortes_valorados" FOR EACH STATEMENT EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_capital_fijar_sello" AFTER INSERT ON "crm"."periodos_cerrados" FOR EACH ROW EXECUTE FUNCTION "private"."capital_fijar_sello_trg"();

CREATE OR REPLACE TRIGGER "trg_capital_meta_pen" BEFORE INSERT OR UPDATE ON "crm"."metas_vendedor_detalle" FOR EACH ROW EXECUTE FUNCTION "private"."capital_meta_pen_trg"();

CREATE OR REPLACE TRIGGER "trg_capital_sellos_inmutables" BEFORE DELETE OR UPDATE ON "crm"."capital_mes_sellos" FOR EACH ROW EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_capital_sellos_sin_truncate" BEFORE TRUNCATE ON "crm"."capital_mes_sellos" FOR EACH STATEMENT EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_capital_valoraciones_inmutables" BEFORE DELETE OR UPDATE ON "crm"."capital_valoraciones" FOR EACH ROW EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_capital_valoraciones_sin_truncate" BEFORE TRUNCATE ON "crm"."capital_valoraciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_celulares_asignaciones_00_candado" BEFORE DELETE OR UPDATE ON "crm"."celulares_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_celulares_asignaciones_candado"();

CREATE OR REPLACE TRIGGER "trg_celulares_asignaciones_00_sin_vaciar" BEFORE TRUNCATE ON "crm"."celulares_asignaciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_llamadas_celular_sin_vaciar"();

CREATE OR REPLACE TRIGGER "trg_cierre_mes_vendedor_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."cierre_mes_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."trg_cierre_mes_append_only"();

CREATE OR REPLACE TRIGGER "trg_cierre_mes_vendedor_10_ranking_origen" BEFORE INSERT ON "crm"."cierre_mes_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."ranking_origen_sellado_trg"();

CREATE OR REPLACE TRIGGER "trg_cierre_mes_vendedor_11_ranking_cartera" BEFORE INSERT ON "crm"."cierre_mes_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."ranking_cartera_sellado_trg"();

CREATE OR REPLACE TRIGGER "trg_cierres_avance_anulados_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."cierres_avance_anulados" FOR EACH ROW EXECUTE FUNCTION "private"."trg_cierres_avance_anulados_append_only"();

CREATE OR REPLACE TRIGGER "trg_cierres_externos_00_inmutables" BEFORE DELETE OR UPDATE ON "crm"."cierres_externos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_cierres_externos_inmutables"();

CREATE OR REPLACE TRIGGER "trg_cierres_f4_inmutables" BEFORE UPDATE ON "crm"."cierres_externos" FOR EACH ROW EXECUTE FUNCTION "private"."f4_fuente_inmutable"();

CREATE OR REPLACE TRIGGER "trg_cierres_f4_sincronizar" AFTER UPDATE OF "monto", "moneda", "cooperativa", "numero_transaccion", "referencia_externa", "vence_en", "nota", "anulado_en" ON "crm"."cierres_externos" FOR EACH ROW EXECUTE FUNCTION "private"."f4_sincronizar_cierre"();

CREATE OR REPLACE TRIGGER "trg_config_inmutable" BEFORE DELETE OR UPDATE ON "crm"."politica_gestion_diaria" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_00_inmutable" BEFORE UPDATE ON "crm"."contrato_cuentas_pago" FOR EACH ROW EXECUTE FUNCTION "private"."trg_contrato_cuenta_pago_inmutable"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_asignaciones_00_inmutable" BEFORE UPDATE ON "crm"."contrato_cuenta_pago_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_contrato_cuenta_pago_asignaciones_inmutable"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_asignaciones_00_no_borrar" BEFORE DELETE ON "crm"."contrato_cuenta_pago_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_registro_cuenta_pago_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_asignaciones_00_sin_vaciar" BEFORE TRUNCATE ON "crm"."contrato_cuenta_pago_asignaciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_contrato_cuenta_pago_asignaciones_inmutable"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_cambios_00_inmutable" BEFORE UPDATE ON "crm"."contrato_cuenta_pago_cambios" FOR EACH ROW EXECUTE FUNCTION "private"."trg_contrato_cuenta_pago_cambios_inmutable"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_cambios_00_no_borrar" BEFORE DELETE ON "crm"."contrato_cuenta_pago_cambios" FOR EACH ROW EXECUTE FUNCTION "private"."trg_registro_cuenta_pago_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_contrato_cuenta_pago_coherente" BEFORE INSERT OR UPDATE ON "crm"."contrato_cuentas_pago" FOR EACH ROW EXECUTE FUNCTION "private"."trg_contrato_cuenta_pago_coherente"();

CREATE OR REPLACE TRIGGER "trg_contratos_eliminados_inmutables" BEFORE DELETE OR UPDATE ON "crm"."contratos_eliminados_auditoria" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_auditoria_contrato_eliminado"();

CREATE OR REPLACE TRIGGER "trg_contratos_eliminados_no_truncate" BEFORE TRUNCATE ON "crm"."contratos_eliminados_auditoria" FOR EACH STATEMENT EXECUTE FUNCTION "private"."proteger_auditoria_contrato_eliminado"();

CREATE OR REPLACE TRIGGER "trg_conversion_acreditacion_cooperativa" AFTER INSERT OR UPDATE OF "fecha_comercial", "lead_id", "es_cierre_inicial" ON "crm"."cierres_externos" FOR EACH ROW WHEN ("new"."es_cierre_inicial") EXECUTE FUNCTION "private"."conversion_acreditacion_evento_trg"();

CREATE OR REPLACE TRIGGER "trg_conversion_acreditacion_episodio" AFTER INSERT OR UPDATE OF "resultado", "resultado_en", "finalizado_en" ON "crm"."lead_asignaciones" FOR EACH ROW WHEN (("new"."resultado" = 'convertido'::"text")) EXECUTE FUNCTION "private"."conversion_acreditacion_evento_trg"();

CREATE OR REPLACE TRIGGER "trg_conversion_acreditacion_solicitud" AFTER INSERT OR UPDATE OF "estado", "inversion_id" ON "crm"."inversion_solicitudes" FOR EACH ROW WHEN ((("new"."estado" = 'confirmada'::"text") AND ("new"."lead_origen_id" IS NOT NULL))) EXECUTE FUNCTION "private"."conversion_acreditacion_evento_trg"();

CREATE OR REPLACE TRIGGER "trg_conversion_bloquear_retiro" BEFORE INSERT ON "crm"."contratos_eliminados_auditoria" FOR EACH ROW EXECUTE FUNCTION "private"."conversion_bloquear_retiro_trg"();

CREATE OR REPLACE TRIGGER "trg_conversion_fijar_sello" AFTER INSERT ON "crm"."periodos_cerrados" FOR EACH ROW EXECUTE FUNCTION "private"."conversion_fijar_sello_trg"();

CREATE OR REPLACE TRIGGER "trg_conversion_ventas_recuperadas_00_validar" BEFORE INSERT ON "crm"."conversion_ventas_recuperadas" FOR EACH ROW EXECUTE FUNCTION "private"."validar_venta_recuperada"();

CREATE OR REPLACE TRIGGER "trg_conversion_ventas_recuperadas_inmutables" BEFORE DELETE OR UPDATE ON "crm"."conversion_ventas_recuperadas" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_venta_recuperada"();

CREATE OR REPLACE TRIGGER "trg_conversion_ventas_recuperadas_no_truncate" BEFORE TRUNCATE ON "crm"."conversion_ventas_recuperadas" FOR EACH STATEMENT EXECUTE FUNCTION "private"."proteger_venta_recuperada"();

CREATE OR REPLACE TRIGGER "trg_cotitular_origen_inmutable" BEFORE DELETE OR UPDATE ON "crm"."inversion_cotitular_origenes" FOR EACH ROW EXECUTE FUNCTION "private"."f4_proteger_origen_cotitular"();

CREATE OR REPLACE TRIGGER "trg_cuentas_bancarias_retiros_00_inmutable" BEFORE DELETE OR UPDATE ON "crm"."cuentas_bancarias_retiros" FOR EACH ROW EXECUTE FUNCTION "private"."trg_retiro_cuenta_inmutable"();

CREATE OR REPLACE TRIGGER "trg_cuentas_bancarias_retiros_00_sin_vaciar" BEFORE TRUNCATE ON "crm"."cuentas_bancarias_retiros" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_retiro_cuenta_inmutable"();

CREATE OR REPLACE TRIGGER "trg_cuentas_bancarias_version_inmutable" BEFORE UPDATE ON "crm"."cuentas_bancarias" FOR EACH ROW EXECUTE FUNCTION "private"."trg_cuentas_bancarias_version_inmutable"();

CREATE OR REPLACE TRIGGER "trg_cuotas_cuenta_pagada_00_no_borrar" BEFORE DELETE ON "crm"."cuotas_cuenta_pagada" FOR EACH ROW EXECUTE FUNCTION "private"."trg_registro_cuenta_pago_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_cuotas_cuenta_pagada_00_solo_resello" BEFORE UPDATE ON "crm"."cuotas_cuenta_pagada" FOR EACH ROW EXECUTE FUNCTION "private"."trg_cuotas_cuenta_pagada_solo_resello"();

CREATE OR REPLACE TRIGGER "trg_depositos_reclamados_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."depositos_reclamados" FOR EACH ROW EXECUTE FUNCTION "private"."trg_depositos_reclamados_append_only"();

CREATE OR REPLACE TRIGGER "trg_empresas_touch" BEFORE UPDATE ON "crm"."empresas" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_encolar_push_tasa" AFTER INSERT ON "crm"."solicitudes_tasa" FOR EACH ROW EXECUTE FUNCTION "private"."encolar_push_tasa"();

CREATE OR REPLACE TRIGGER "trg_equipo_evento_jerarquia_insert" AFTER INSERT ON "crm"."equipo" FOR EACH ROW WHEN (("new"."supervisor_id" IS NOT NULL)) EXECUTE FUNCTION "private"."trg_equipo_evento_jerarquia"();

COMMENT ON TRIGGER "trg_equipo_evento_jerarquia_insert" ON "crm"."equipo" IS 'Historia inicial solo con supervisor no NULL; AFTER INSERT por fila, evento en la misma transacción.';

CREATE OR REPLACE TRIGGER "trg_equipo_evento_jerarquia_update" AFTER UPDATE ON "crm"."equipo" FOR EACH ROW WHEN (("old"."supervisor_id" IS DISTINCT FROM "new"."supervisor_id")) EXECUTE FUNCTION "private"."trg_equipo_evento_jerarquia"();

COMMENT ON TRIGGER "trg_equipo_evento_jerarquia_update" ON "crm"."equipo" IS 'Historia de toda vía solo cuando cambia supervisor_id (incluye SET NULL por FK); AFTER UPDATE por fila, evento en la misma transacción.';

CREATE OR REPLACE TRIGGER "trg_equipo_no_borrar" BEFORE DELETE ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."trg_equipo_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_equipo_par_autoridad" BEFORE INSERT OR UPDATE OF "rol_crm", "perfil_id" ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."trg_equipo_par_autoridad"();

CREATE OR REPLACE TRIGGER "trg_equipo_rotar_agenda_ics_offboarding" AFTER UPDATE OF "activo" ON "crm"."equipo" FOR EACH ROW WHEN ((("old"."activo" IS TRUE) AND ("new"."activo" IS NOT TRUE))) EXECUTE FUNCTION "private"."trg_rotar_agenda_ics_offboarding"();

CREATE OR REPLACE TRIGGER "trg_equipo_touch" BEFORE UPDATE ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_equipo_validar_usuarios_jerarquia" AFTER INSERT OR UPDATE OF "rol_crm", "supervisor_id", "activo" ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."trg_validar_equipo_usuario_crm"();

CREATE OR REPLACE TRIGGER "trg_inmutable" BEFORE DELETE OR UPDATE ON "crm"."gestion_diaria_control_avisos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_inmutable" BEFORE DELETE OR UPDATE ON "crm"."gestion_diaria_entregas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_inversion_ajustes_inmutables" BEFORE DELETE OR UPDATE ON "crm"."inversion_ajustes_mes_cerrado" FOR EACH ROW EXECUTE FUNCTION "private"."f4_fuente_inmutable"();

CREATE OR REPLACE TRIGGER "trg_inversion_backfill_inmutable" BEFORE DELETE OR UPDATE ON "crm"."inversion_backfill_lotes" FOR EACH ROW EXECUTE FUNCTION "private"."f4_proteger_lote_historico"();

CREATE OR REPLACE TRIGGER "trg_inversion_correcciones_inmutables" BEFORE DELETE OR UPDATE ON "crm"."inversion_solicitud_correcciones" FOR EACH ROW EXECUTE FUNCTION "private"."f4_fuente_inmutable"();

CREATE OR REPLACE TRIGGER "trg_inversion_eventos_inmutables" BEFORE DELETE OR UPDATE ON "crm"."inversion_eventos" FOR EACH ROW EXECUTE FUNCTION "private"."f4_fuente_inmutable"();

CREATE OR REPLACE TRIGGER "trg_inversion_revisiones_inmutables" BEFORE DELETE OR UPDATE ON "crm"."inversion_solicitud_revisiones" FOR EACH ROW EXECUTE FUNCTION "private"."f4_fuente_inmutable"();

CREATE OR REPLACE TRIGGER "trg_inversion_titular_coherente" BEFORE INSERT OR UPDATE ON "crm"."inversion_titulares" FOR EACH ROW EXECUTE FUNCTION "private"."inversion_titular_coherente"();

CREATE OR REPLACE TRIGGER "trg_inversiones_eliminadas_inmutables" BEFORE DELETE OR UPDATE ON "crm"."inversiones_eliminadas" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_inversion_eliminada"();

CREATE OR REPLACE TRIGGER "trg_inversiones_eliminadas_no_truncate" BEFORE TRUNCATE ON "crm"."inversiones_eliminadas" FOR EACH STATEMENT EXECUTE FUNCTION "private"."proteger_inversion_eliminada"();

CREATE OR REPLACE TRIGGER "trg_inversiones_empresa_coherente" BEFORE INSERT OR UPDATE ON "crm"."inversiones" FOR EACH ROW EXECUTE FUNCTION "private"."inversiones_empresa_coherente"();

CREATE OR REPLACE TRIGGER "trg_inversiones_touch" BEFORE UPDATE ON "crm"."inversiones" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_inversionista_fusiones_append_only" BEFORE DELETE OR UPDATE ON "crm"."inversionista_fusiones" FOR EACH ROW EXECUTE FUNCTION "private"."inversionista_fusiones_append_only"();

CREATE OR REPLACE TRIGGER "trg_inversionista_operaciones_append_only" BEFORE DELETE OR UPDATE ON "crm"."inversionista_operaciones" FOR EACH ROW EXECUTE FUNCTION "private"."inversionista_operaciones_append_only"();

CREATE OR REPLACE TRIGGER "trg_inversionistas_fusion_destino" BEFORE INSERT OR UPDATE ON "crm"."inversionistas" FOR EACH ROW EXECUTE FUNCTION "private"."inversionista_fusion_destino_activo"();

CREATE OR REPLACE TRIGGER "trg_inversionistas_postventa" AFTER UPDATE OF "no_contactar", "responsable_relacion_id", "inversionista_canonico_id" ON "crm"."inversionistas" FOR EACH ROW EXECUTE FUNCTION "private"."postventa_cambio_persona"();

CREATE OR REPLACE TRIGGER "trg_inversionistas_touch" BEFORE UPDATE ON "crm"."inversionistas" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_lead_asignacion_sla_hitos_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."lead_asignacion_sla_hitos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_asignacion_sla_hitos_guard"();

CREATE OR REPLACE TRIGGER "trg_lead_asignaciones_00_fill_sla_global" BEFORE INSERT OR UPDATE ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_asignaciones_completar_sla_global"();

CREATE OR REPLACE TRIGGER "trg_lead_asignaciones_00_inmutables" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_asignaciones_inmutables"();

CREATE OR REPLACE TRIGGER "trg_lead_asignaciones_00_sla_global_inmutable" BEFORE UPDATE ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_asignaciones_sla_global_inmutable"();

CREATE OR REPLACE TRIGGER "trg_lead_asignaciones_01_sla_versionado" BEFORE INSERT OR UPDATE ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_asignaciones_sla_versionado"();

CREATE OR REPLACE TRIGGER "trg_lead_asignaciones_02_crear_sla_hitos" AFTER INSERT ON "crm"."lead_asignaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_asignaciones_crear_sla_hitos"();

CREATE OR REPLACE TRIGGER "trg_lead_potencial_touch" BEFORE UPDATE ON "crm"."lead_potencial" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_lead_sla_ciclos_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."lead_sla_ciclos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_sla_ciclos_guard"();

CREATE OR REPLACE TRIGGER "trg_lead_sla_etapas_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."lead_sla_etapas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_lead_sla_etapas_guard"();

CREATE OR REPLACE TRIGGER "trg_leads_000_base_cargada_solo_puerta" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_base_cargada_solo_puerta"();

COMMENT ON TRIGGER "trg_leads_000_base_cargada_solo_puerta" ON "crm"."leads" IS 'Bases cargadas (B7): origen y motivo base_cargada solo con la válvula crm.op_bases_carga (entrar y, mientras siga descartado, salir del motivo); un capital que existe no se vacía. Ver private.trg_leads_base_cargada_solo_puerta.';

CREATE OR REPLACE TRIGGER "trg_leads_000_hereda_veto" BEFORE INSERT ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_hereda_veto_persona"();

CREATE OR REPLACE TRIGGER "trg_leads_000_no_contactar_puerta" BEFORE UPDATE OF "no_contactar" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_no_contactar_solo_puerta"();

CREATE OR REPLACE TRIGGER "trg_leads_00_devolucion_equipo_solo_rpc" BEFORE UPDATE OF "vendedor_id", "asignado_supervisor_id" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_devolucion_equipo_solo_rpc"();

CREATE OR REPLACE TRIGGER "trg_leads_00_disponibilidad_insert" BEFORE INSERT ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_disponibilidad_atomica"();

CREATE OR REPLACE TRIGGER "trg_leads_00_disponibilidad_update" BEFORE UPDATE OF "telefono", "dni", "no_contactar", "etapa", "activo", "motivo_descarte", "telefono_alternativo", "telefono_alternativo_crudo" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_disponibilidad_atomica"();

CREATE OR REPLACE TRIGGER "trg_leads_00_guard_tenencia" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_guard_tenencia"();

CREATE OR REPLACE TRIGGER "trg_leads_00_seguimiento_activo" BEFORE UPDATE ON "crm"."leads" FOR EACH ROW WHEN ((("old"."etapa" = 'descartado'::"text") AND ("new"."vendedor_id" IS DISTINCT FROM "old"."vendedor_id"))) EXECUTE FUNCTION "private"."trg_leads_guard_seguimiento_activo"();

COMMENT ON TRIGGER "trg_leads_00_seguimiento_activo" ON "crm"."leads" IS 'B6 (03/10/2026): un lead descartado en gestión de su analista no cambia de responsable (rescate, ficha, tomar lead libre). Ver private.trg_leads_guard_seguimiento_activo.';

CREATE OR REPLACE TRIGGER "trg_leads_01_sla_global" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_sla_global"();

CREATE OR REPLACE TRIGGER "trg_leads_02_sla_versionado" AFTER INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_sla_versionado"();

CREATE OR REPLACE TRIGGER "trg_leads_asignaciones" AFTER INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_asignaciones"();

CREATE OR REPLACE TRIGGER "trg_leads_before_insert" BEFORE INSERT ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."leads_before_insert"();

CREATE OR REPLACE TRIGGER "trg_leads_before_update" BEFORE UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."leads_before_update"();

CREATE OR REPLACE TRIGGER "trg_leads_bloquear_reasignacion" BEFORE UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_bloquear_reasignacion"();

CREATE OR REPLACE TRIGGER "trg_leads_cambio_etapa" BEFORE UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_cambio_etapa"();

CREATE OR REPLACE TRIGGER "trg_leads_campania_controlada" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_campania_lead"();

CREATE OR REPLACE TRIGGER "trg_leads_conversion_con_inversion" BEFORE UPDATE OF "etapa" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."conversion_lead_con_inversion"();

CREATE OR REPLACE TRIGGER "trg_leads_eliminados_inmutables" BEFORE DELETE OR UPDATE ON "crm"."leads_eliminados" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_lead_eliminado"();

CREATE OR REPLACE TRIGGER "trg_leads_eliminados_no_truncate" BEFORE TRUNCATE ON "crm"."leads_eliminados" FOR EACH STATEMENT EXECUTE FUNCTION "private"."proteger_lead_eliminado"();

CREATE OR REPLACE TRIGGER "trg_leads_normalizar_tel" BEFORE INSERT OR UPDATE OF "telefono" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_normalizar_telefono"();

CREATE OR REPLACE TRIGGER "trg_leads_protege_inversionista_id" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."leads_protege_inversionista_id"();

CREATE OR REPLACE TRIGGER "trg_leads_reasignacion" BEFORE UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_reasignacion"();

CREATE OR REPLACE TRIGGER "trg_leads_zz_enlaza_identidad" BEFORE INSERT OR UPDATE OF "dni" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_zz_enlaza_identidad"();

CREATE OR REPLACE TRIGGER "trg_leads_zz_puente_identidad" AFTER INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_zz_puente_identidad"();

CREATE OR REPLACE TRIGGER "trg_leads_zz_reapertura_solo_rpc" BEFORE UPDATE OF "etapa", "activo" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_zz_reapertura_solo_rpc"();

COMMENT ON TRIGGER "trg_leads_zz_reapertura_solo_rpc" ON "crm"."leads" IS 'F2.b [D-13]: con resolver_en_puertas encendida, descartado -> vivo (o activo false -> true) solo bajo crm.reapertura_identidad=on (tomar/rescatar/deshacer) o válvula. Apagada: inerte.';

CREATE OR REPLACE TRIGGER "trg_leads_zz_sello_base_gestion" BEFORE INSERT OR UPDATE OF "reactivado_en", "enfriado_hasta", "proxima_llamada_en" ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_zz_sello_base_gestion"();

CREATE OR REPLACE TRIGGER "trg_leads_zz_sello_descarte" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_zz_sello_descarte"();

CREATE OR REPLACE TRIGGER "trg_leads_zz_sello_descarte_base_cargada" BEFORE INSERT ON "crm"."leads" FOR EACH ROW WHEN (("new"."origen" = 'base_cargada'::"text")) EXECUTE FUNCTION "private"."trg_leads_sello_descarte_base_cargada"();

COMMENT ON TRIGGER "trg_leads_zz_sello_descarte_base_cargada" ON "crm"."leads" IS 'Bases cargadas (B8): el contacto que nace dormido recibe descartado_en (momento de la carga) y descartado_por (el actor). Corre después de trg_leads_zz_sello_descarte (orden por nombre). Ver private.trg_leads_sello_descarte_base_cargada.';

CREATE OR REPLACE TRIGGER "trg_leads_zz_sync_tareas" AFTER UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_sync_tareas"();

CREATE OR REPLACE TRIGGER "trg_leads_zzz_tenencia_desde" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."trg_leads_tenencia_desde"();

CREATE OR REPLACE TRIGGER "trg_leads_zzzz_recorrido_insert" BEFORE INSERT ON "crm"."leads" FOR EACH ROW WHEN (("new"."etapa" = 'convertido'::"text")) EXECUTE FUNCTION "private"."recorrido_insert_convertido_guard"();

CREATE OR REPLACE TRIGGER "trg_ledger_rentabilidad_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."ledger_rentabilidad" FOR EACH ROW EXECUTE FUNCTION "private"."trg_ledger_rentabilidad_append_only"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_enlaces_00_candado" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."llamadas_celular_enlaces" FOR EACH ROW EXECUTE FUNCTION "private"."trg_llamadas_celular_enlaces_candado"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_enlaces_00_sin_vaciar" BEFORE TRUNCATE ON "crm"."llamadas_celular_enlaces" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_llamadas_celular_sin_vaciar"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_eventos_00_candado" BEFORE DELETE OR UPDATE ON "crm"."llamadas_celular_eventos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_llamadas_celular_eventos_candado"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_eventos_00_sin_vaciar" BEFORE TRUNCATE ON "crm"."llamadas_celular_eventos" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_llamadas_celular_sin_vaciar"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_politica_00_candado" BEFORE DELETE OR UPDATE ON "crm"."llamadas_celular_politica" FOR EACH ROW EXECUTE FUNCTION "private"."trg_llamadas_celular_politica_candado"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_politica_00_sin_vaciar" BEFORE TRUNCATE ON "crm"."llamadas_celular_politica" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_llamadas_celular_sin_vaciar"();

CREATE OR REPLACE TRIGGER "trg_meta_periodos_00_no_bajo_sellado" BEFORE INSERT OR UPDATE OF "periodo" ON "crm"."meta_periodos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_metas_no_bajo_mes_sellado"();

CREATE OR REPLACE TRIGGER "trg_meta_periodos_inmutables" BEFORE DELETE OR UPDATE ON "crm"."meta_periodos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_metas_vendedor_detalle_inmutables" BEFORE DELETE OR UPDATE ON "crm"."metas_vendedor_detalle" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_metas_vendedor_inmutables" BEFORE DELETE OR UPDATE ON "crm"."metas_vendedor" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_multiempresa_flags_00_serializa_puertas" BEFORE UPDATE OF "activo" ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."trg_multiempresa_flags_serializa_puertas"();

COMMENT ON TRIGGER "trg_multiempresa_flags_00_serializa_puertas" ON "crm"."multiempresa_flags" IS 'F2.b [D-5]: el cambio de una bandera toma el advisory exclusivo crm_flag_<nombre>; las puertas que leen resolver_en_puertas bajo el compartido terminan con la bandera que leyeron.';

CREATE OR REPLACE TRIGGER "trg_multiempresa_flags_01_bloquear_piloto_f8" BEFORE INSERT OR UPDATE ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."trg_multiempresa_flags_bloquear_piloto_f8"();

CREATE OR REPLACE TRIGGER "trg_multiempresa_flags_touch" BEFORE UPDATE ON "crm"."multiempresa_flags" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_objetivos_legacy_archivo_inmutable" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."objetivos_legacy_archivo" FOR EACH ROW EXECUTE FUNCTION "private"."trg_archivo_metas_legacy_inmutable"();

CREATE OR REPLACE TRIGGER "trg_objetivos_touch" BEFORE UPDATE ON "crm"."objetivos_legacy_archivo" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_objetivos_vendedores_actualizado" BEFORE UPDATE ON "crm"."objetivos_vendedores_legacy_archivo" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_objetivos_vendedores_legacy_archivo_inmutable" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."objetivos_vendedores_legacy_archivo" FOR EACH ROW EXECUTE FUNCTION "private"."trg_archivo_metas_legacy_inmutable"();

CREATE OR REPLACE TRIGGER "trg_operaciones_cartera_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."operaciones_cartera" FOR EACH ROW EXECUTE FUNCTION "private"."trg_operaciones_cartera_append_only"();

CREATE OR REPLACE TRIGGER "trg_operaciones_cartera_10_fija_categoria" AFTER INSERT OR UPDATE OF "tipo", "contrato_nuevo_id" ON "crm"."operaciones_cartera" FOR EACH ROW EXECUTE FUNCTION "private"."trg_operacion_cartera_fija_categoria"();

COMMENT ON TRIGGER "trg_operaciones_cartera_10_fija_categoria" ON "crm"."operaciones_cartera" IS 'La operación decide: sincroniza la categoría del contrato nuevo con la operación (20261009120000).';

CREATE OR REPLACE TRIGGER "trg_origen_capital_confirmado_guardar" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."origenes_capital_confirmados" FOR EACH ROW EXECUTE FUNCTION "private"."origen_capital_confirmado_guardar"();

CREATE OR REPLACE TRIGGER "trg_periodos_cerrados_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."periodos_cerrados" FOR EACH ROW EXECUTE FUNCTION "private"."trg_cierre_mes_append_only"();

CREATE OR REPLACE TRIGGER "trg_piloto_f8_control_00_validar" BEFORE DELETE OR UPDATE ON "crm"."piloto_f8_control" FOR EACH ROW EXECUTE FUNCTION "private"."trg_piloto_f8_control_validar"();

CREATE OR REPLACE TRIGGER "trg_piloto_f8_miembros_00_controlar" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."piloto_f8_miembros" FOR EACH ROW EXECUTE FUNCTION "private"."trg_piloto_f8_miembros_controlar"();

CREATE OR REPLACE TRIGGER "trg_plazos_carga_mes_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."plazos_carga_mes" FOR EACH ROW EXECUTE FUNCTION "private"."trg_plazo_carga_append_only"();

CREATE OR REPLACE TRIGGER "trg_plazos_carga_mes_no_truncate" BEFORE TRUNCATE ON "crm"."plazos_carga_mes" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_plazo_carga_append_only"();

CREATE OR REPLACE TRIGGER "trg_politica_abandono_00_autoria" BEFORE UPDATE ON "crm"."politica_abandono" FOR EACH ROW EXECUTE FUNCTION "crm"."politica_abandono_sellar_autoria"();

CREATE OR REPLACE TRIGGER "trg_politica_rentabilidad_inmutable" BEFORE DELETE OR UPDATE ON "crm"."politica_rentabilidad" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_producto_condiciones_inmutables" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."producto_condiciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_producto_condiciones_inmutables"();

CREATE OR REPLACE TRIGGER "trg_producto_versiones_inmutables" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."producto_versiones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_producto_versiones_inmutables"();

CREATE OR REPLACE TRIGGER "trg_productos_inversion_inmutables" BEFORE DELETE OR UPDATE ON "crm"."productos_inversion" FOR EACH ROW EXECUTE FUNCTION "private"."trg_productos_inversion_inmutables"();

CREATE OR REPLACE TRIGGER "trg_reaperturas_mes_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."reaperturas_mes" FOR EACH ROW EXECUTE FUNCTION "private"."trg_plazo_carga_append_only"();

CREATE OR REPLACE TRIGGER "trg_reaperturas_mes_00_llave" BEFORE INSERT ON "crm"."reaperturas_mes" FOR EACH ROW EXECUTE FUNCTION "private"."trg_reaperturas_mes_llave"();

CREATE OR REPLACE TRIGGER "trg_reaperturas_mes_no_truncate" BEFORE TRUNCATE ON "crm"."reaperturas_mes" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_plazo_carga_append_only"();

CREATE OR REPLACE TRIGGER "trg_reasignaciones_00_append_only" BEFORE DELETE OR UPDATE ON "crm"."reasignaciones_analista" FOR EACH ROW EXECUTE FUNCTION "private"."trg_reasignaciones_append_only"();

CREATE OR REPLACE TRIGGER "trg_recordatorios_disponibilidad_00_sellar" BEFORE INSERT OR UPDATE ON "crm"."recordatorios_disponibilidad" FOR EACH ROW EXECUTE FUNCTION "crm"."recordatorios_disponibilidad_sellar"();

CREATE OR REPLACE TRIGGER "trg_rentabilidad_hitos_solo_migraciones" BEFORE DELETE ON "crm"."rentabilidad_hitos" FOR EACH ROW EXECUTE FUNCTION "private"."trg_ledger_rentabilidad_append_only"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."lead_sla_etapa_ajustes" FOR EACH ROW EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."sla_operacion_control" FOR EACH ROW EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."sla_politica_etapas_operacion" FOR EACH ROW EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_guard" BEFORE INSERT OR DELETE OR UPDATE ON "crm"."tarea_sla_contexto" FOR EACH ROW EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_no_truncate" BEFORE TRUNCATE ON "crm"."lead_sla_etapa_ajustes" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_no_truncate" BEFORE TRUNCATE ON "crm"."sla_operacion_control" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_no_truncate" BEFORE TRUNCATE ON "crm"."sla_politica_etapas_operacion" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_nucleo_no_truncate" BEFORE TRUNCATE ON "crm"."tarea_sla_contexto" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_sla_nucleo_entrada_guard"();

CREATE OR REPLACE TRIGGER "trg_sla_politica_etapas_inmutables" BEFORE DELETE OR UPDATE ON "crm"."sla_politica_etapas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_sla_politicas_inmutables" BEFORE DELETE OR UPDATE ON "crm"."sla_politicas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_config_versionada_inmutable"();

CREATE OR REPLACE TRIGGER "trg_solicitudes_recorrido" BEFORE INSERT OR UPDATE ON "crm"."inversion_solicitudes" FOR EACH ROW EXECUTE FUNCTION "private"."recorrido_solicitud_guard"();

CREATE OR REPLACE TRIGGER "trg_solicitudes_tasa_00_solo_por_puerta" BEFORE DELETE OR UPDATE ON "crm"."solicitudes_tasa" FOR EACH ROW EXECUTE FUNCTION "private"."trg_solicitudes_tasa_solo_por_puerta"();

CREATE OR REPLACE TRIGGER "trg_solicitudes_zz_postventa" BEFORE UPDATE OF "datos", "estado", "inversionista_id", "empresa_id" ON "crm"."inversion_solicitudes" FOR EACH ROW EXECUTE FUNCTION "private"."postventa_reinversion_guard"();

CREATE OR REPLACE TRIGGER "trg_tareas_000_postventa" BEFORE INSERT OR UPDATE ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."postventa_tarea_guard"();

CREATE OR REPLACE TRIGGER "trg_tareas_00_0_veto_persona" BEFORE INSERT ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_tareas_veto_persona_perfil"();

CREATE OR REPLACE TRIGGER "trg_tareas_00_before_insert" BEFORE INSERT ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_tareas_before_insert"();

CREATE OR REPLACE TRIGGER "trg_tareas_00_before_update" BEFORE UPDATE ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_tareas_before_update"();

CREATE OR REPLACE TRIGGER "trg_tareas_00_recorrido_invalidacion" BEFORE DELETE OR UPDATE ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."recorrido_serializar_invalidacion"();

CREATE OR REPLACE TRIGGER "trg_tareas_01_destino_efectivo_insert" BEFORE INSERT ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_tareas_destino_efectivo"();

CREATE OR REPLACE TRIGGER "trg_tareas_01_destino_efectivo_update" BEFORE UPDATE OF "vendedor_id", "asignado_supervisor_id", "activo", "estado" ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_tareas_destino_efectivo"();

CREATE OR REPLACE TRIGGER "trg_tareas_02_gestion_lead_serializada" BEFORE INSERT ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."trg_gestion_lead_serializada"();

CREATE OR REPLACE TRIGGER "trg_tareas_03_sla_contexto" AFTER INSERT ON "crm"."tareas" FOR EACH ROW WHEN (("new"."lead_id" IS NOT NULL)) EXECUTE FUNCTION "private"."trg_sla_tarea_contexto"();

CREATE OR REPLACE TRIGGER "trg_tareas_touch" BEFORE UPDATE ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."set_actualizado_en_crm"();

CREATE OR REPLACE TRIGGER "trg_tipo_cambio_diario_inmutable" BEFORE DELETE OR UPDATE ON "crm"."tipo_cambio_diario" FOR EACH ROW EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_tipo_cambio_diario_sin_truncate" BEFORE TRUNCATE ON "crm"."tipo_cambio_diario" FOR EACH STATEMENT EXECUTE FUNCTION "private"."capital_tc_inmutable"();

CREATE OR REPLACE TRIGGER "trg_validar_politica_gestion_diaria" BEFORE INSERT ON "crm"."politica_gestion_diaria" FOR EACH ROW EXECUTE FUNCTION "private"."trg_politica_gestion_diaria_insertar"();

CREATE OR REPLACE TRIGGER "trg_zy_actividades_sla_versionado" AFTER INSERT ON "crm"."actividades" FOR EACH ROW WHEN (("new"."tipo" = ANY (ARRAY['llamada_realizada'::"text", 'llamada_no_contestada'::"text", 'whatsapp_enviado'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text"]))) EXECUTE FUNCTION "private"."trg_actividades_sla_versionado"();

CREATE OR REPLACE TRIGGER "trg_zz_actividades_avance_etapa" AFTER INSERT ON "crm"."actividades" FOR EACH ROW WHEN (("new"."tipo" = ANY (ARRAY['llamada_realizada'::"text", 'whatsapp_recibido'::"text", 'reunion_realizada'::"text"]))) EXECUTE FUNCTION "private"."trg_actividades_avance_etapa"();

CREATE OR REPLACE TRIGGER "trg_zz_actividades_enfriamiento_base" AFTER INSERT ON "crm"."actividades" FOR EACH ROW WHEN ((("new"."metadata" ->> 'evento'::"text") = 'intento_base'::"text")) EXECUTE FUNCTION "private"."trg_actividades_enfriamiento_base"();

CREATE OR REPLACE TRIGGER "trg_zz_conversion_acreditacion_lead" AFTER UPDATE OF "contrato_id", "perfil_id", "origen" ON "crm"."leads" FOR EACH ROW WHEN ((("new"."etapa" = 'convertido'::"text") AND (("new"."contrato_id" IS DISTINCT FROM "old"."contrato_id") OR ("new"."perfil_id" IS DISTINCT FROM "old"."perfil_id") OR ("new"."origen" IS DISTINCT FROM "old"."origen")))) EXECUTE FUNCTION "private"."conversion_acreditacion_evento_trg"();

CREATE OR REPLACE TRIGGER "trg_zz_tareas_avance_etapa" AFTER INSERT ON "crm"."tareas" FOR EACH ROW WHEN ((("new"."tipo" = 'reunion'::"text") AND ("new"."lead_id" IS NOT NULL) AND ("new"."reagendada_de" IS NULL) AND ("new"."estado" = 'pendiente'::"text") AND ("new"."activo" = true))) EXECUTE FUNCTION "private"."trg_tareas_avance_etapa"();

CREATE OR REPLACE TRIGGER "trg_zzzz_usuario_retirado" BEFORE INSERT OR UPDATE ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."no_asignar_usuario_retirado"();

CREATE OR REPLACE TRIGGER "trg_zzzz_usuario_retirado" BEFORE INSERT OR UPDATE ON "crm"."inversionista_responsables" FOR EACH ROW EXECUTE FUNCTION "private"."no_asignar_usuario_retirado"();

CREATE OR REPLACE TRIGGER "trg_zzzz_usuario_retirado" BEFORE INSERT OR UPDATE ON "crm"."inversionistas" FOR EACH ROW EXECUTE FUNCTION "private"."no_asignar_usuario_retirado"();

CREATE OR REPLACE TRIGGER "trg_zzzz_usuario_retirado" BEFORE INSERT OR UPDATE ON "crm"."leads" FOR EACH ROW EXECUTE FUNCTION "private"."no_asignar_usuario_retirado"();

CREATE OR REPLACE TRIGGER "trg_zzzz_usuario_retirado" BEFORE INSERT OR UPDATE ON "crm"."tareas" FOR EACH ROW EXECUTE FUNCTION "private"."no_asignar_usuario_retirado"();

CREATE OR REPLACE TRIGGER "usuario_retirado_equipo" BEFORE DELETE OR UPDATE ON "crm"."equipo" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_usuario_retirado"();

CREATE OR REPLACE TRIGGER "zz_capital_valorar_cierre" AFTER INSERT OR UPDATE OF "monto", "moneda", "fecha_comercial", "fecha_imputacion" ON "crm"."cierres_externos" FOR EACH ROW EXECUTE FUNCTION "private"."capital_valorar_cierre_trg"();

CREATE OR REPLACE TRIGGER "ayuda_intenciones_proteger_publicada" BEFORE DELETE OR UPDATE ON "private"."ayuda_intenciones" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_version_publicada_ayuda"();

CREATE OR REPLACE TRIGGER "contrato_pdf_anexo_emisiones_sin_vaciar" BEFORE TRUNCATE ON "private"."contrato_pdf_anexo_emisiones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."bloquear_mutacion_anexo_emision"();

CREATE OR REPLACE TRIGGER "contrato_pdf_anexo_emisiones_solo_insert" BEFORE DELETE OR UPDATE ON "private"."contrato_pdf_anexo_emisiones" FOR EACH ROW EXECUTE FUNCTION "private"."bloquear_mutacion_anexo_emision"();

CREATE OR REPLACE TRIGGER "contrato_pdf_jobs_transiciones_validas" BEFORE DELETE OR UPDATE ON "private"."contrato_pdf_jobs" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_job_contrato_pdf"();

CREATE OR REPLACE TRIGGER "contrato_pdfs_solo_insert" BEFORE DELETE OR UPDATE ON "private"."contrato_pdfs" FOR EACH ROW EXECUTE FUNCTION "private"."bloquear_mutacion_contrato_pdf"();

CREATE OR REPLACE TRIGGER "trg_analista_vigencia_tope_no_truncar" BEFORE TRUNCATE ON "private"."analista_vigencia_tope" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_analista_vigencia_tope_no_truncar"();

CREATE OR REPLACE TRIGGER "trg_analista_vigencia_tope_solo_baja" BEFORE DELETE OR UPDATE ON "private"."analista_vigencia_tope" FOR EACH ROW EXECUTE FUNCTION "private"."trg_analista_vigencia_tope_solo_baja"();

CREATE OR REPLACE TRIGGER "trg_analitica_lc_clase_solo_aprieta" BEFORE UPDATE OF "clase" ON "private"."analitica_leads_citas_exenciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_analitica_lc_clase_solo_aprieta"();

CREATE OR REPLACE TRIGGER "trg_analitica_lc_exenciones_no_borrar" BEFORE DELETE OR TRUNCATE ON "private"."analitica_leads_citas_exenciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_analitica_lc_exenciones_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_analitica_lc_tope_no_truncar" BEFORE TRUNCATE ON "private"."analitica_leads_citas_tope" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_analitica_lc_tope_no_truncar"();

CREATE OR REPLACE TRIGGER "trg_analitica_lc_tope_solo_baja" BEFORE DELETE OR UPDATE ON "private"."analitica_leads_citas_tope" FOR EACH ROW EXECUTE FUNCTION "private"."trg_analitica_lc_tope_solo_baja"();

CREATE OR REPLACE TRIGGER "trg_audit_auditoria_condicionada" AFTER INSERT OR DELETE OR UPDATE ON "private"."auditoria_condicionada" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_audit_auditoria_exenciones" AFTER INSERT OR DELETE OR UPDATE ON "private"."auditoria_exenciones" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "trg_celulares_estado_00_candado" BEFORE DELETE OR UPDATE ON "private"."celulares_estado" FOR EACH ROW EXECUTE FUNCTION "private"."trg_celulares_estado_candado"();

CREATE OR REPLACE TRIGGER "trg_contrato_eliminaciones_00_operacion" BEFORE INSERT ON "private"."contrato_eliminaciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_preparar_eliminacion_operacion_cartera"();

CREATE OR REPLACE TRIGGER "trg_f7_obs_00_solo_crece" BEFORE UPDATE ON "private"."f7_piezas_en_observacion" FOR EACH ROW EXECUTE FUNCTION "private"."trg_f7_obs_solo_crece"();

CREATE OR REPLACE TRIGGER "trg_f7_obs_01_no_borrar" BEFORE DELETE ON "private"."f7_piezas_en_observacion" FOR EACH ROW EXECUTE FUNCTION "private"."trg_f7_obs_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_f7_obs_02_no_truncar" BEFORE TRUNCATE ON "private"."f7_piezas_en_observacion" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_f7_obs_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_intenciones_00_candado" BEFORE DELETE OR UPDATE ON "private"."llamadas_celular_intenciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_llamadas_celular_intenciones_candado"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_intenciones_00_sin_vaciar" BEFORE TRUNCATE ON "private"."llamadas_celular_intenciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_llamadas_celular_sin_vaciar"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_recepciones_00_candado" BEFORE DELETE OR UPDATE ON "private"."llamadas_celular_recepciones" FOR EACH ROW EXECUTE FUNCTION "private"."trg_llamadas_celular_recepciones_candado"();

CREATE OR REPLACE TRIGGER "trg_llamadas_celular_recepciones_00_sin_vaciar" BEFORE TRUNCATE ON "private"."llamadas_celular_recepciones" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_llamadas_celular_sin_vaciar"();

CREATE OR REPLACE TRIGGER "trg_pares_autoridad_no_borrar" BEFORE DELETE ON "private"."pares_autoridad" FOR EACH ROW EXECUTE FUNCTION "private"."trg_pares_autoridad_no_borrar"();

CREATE OR REPLACE TRIGGER "trg_pares_autoridad_no_truncar" BEFORE TRUNCATE ON "private"."pares_autoridad" FOR EACH STATEMENT EXECUTE FUNCTION "private"."trg_pares_autoridad_no_borrar"();

CREATE OR REPLACE TRIGGER "usuarios_retirados_audit" AFTER INSERT ON "private"."usuarios_retirados" FOR EACH ROW EXECUTE FUNCTION "private"."log_audit_crm"();

CREATE OR REPLACE TRIGGER "usuarios_retirados_inmutables" BEFORE DELETE OR UPDATE ON "private"."usuarios_retirados" FOR EACH ROW EXECUTE FUNCTION "private"."proteger_usuario_retirado"();

ALTER TABLE ONLY "crm"."actividad_ciclo_contexto"
    ADD CONSTRAINT "actividad_ciclo_contexto_actividad_id_fkey" FOREIGN KEY ("actividad_id") REFERENCES "crm"."actividades"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."actividad_ciclo_contexto"
    ADD CONSTRAINT "actividad_ciclo_contexto_lead_id_ciclo_n_fkey" FOREIGN KEY ("lead_id", "ciclo_n") REFERENCES "crm"."lead_sla_ciclos"("lead_id", "ciclo_n");

ALTER TABLE ONLY "crm"."actividad_ciclo_contexto"
    ADD CONSTRAINT "actividad_ciclo_contexto_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."actividad_ciclo_contexto"
    ADD CONSTRAINT "actividad_ciclo_contexto_oficina_tarea_id_fkey" FOREIGN KEY ("oficina_tarea_id") REFERENCES "crm"."tareas"("id");

ALTER TABLE ONLY "crm"."actividades_cliente"
    ADD CONSTRAINT "actividades_cliente_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."perfiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."actividades_cliente"
    ADD CONSTRAINT "actividades_cliente_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."actividades_cliente"
    ADD CONSTRAINT "actividades_cliente_tarea_id_fkey" FOREIGN KEY ("tarea_id") REFERENCES "crm"."tareas"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."actividades_cliente"
    ADD CONSTRAINT "actividades_cliente_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."actividades"
    ADD CONSTRAINT "actividades_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."actividades"
    ADD CONSTRAINT "actividades_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."agenda_ics"
    ADD CONSTRAINT "agenda_ics_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."ajustes_mes_cerrado"
    ADD CONSTRAINT "ajustes_mes_cerrado_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."ajustes_mes_cerrado"
    ADD CONSTRAINT "ajustes_mes_cerrado_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."ajustes_mes_cerrado"
    ADD CONSTRAINT "ajustes_mes_cerrado_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."alertas_reconocimientos"
    ADD CONSTRAINT "alertas_reconocimientos_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."backfill_multiempresa_mapa"
    ADD CONSTRAINT "backfill_multiempresa_mapa_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."backfill_multiempresa_mapa"
    ADD CONSTRAINT "backfill_multiempresa_mapa_revisor_fkey" FOREIGN KEY ("revisor") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_agregado_por_fkey" FOREIGN KEY ("agregado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_analista_id_fkey" FOREIGN KEY ("analista_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_asignado_por_fkey" FOREIGN KEY ("asignado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_base_id_fkey" FOREIGN KEY ("base_id") REFERENCES "crm"."bases_carga"("id");

ALTER TABLE ONLY "crm"."base_carga_leads"
    ADD CONSTRAINT "base_carga_leads_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."base_carga_operaciones"
    ADD CONSTRAINT "base_carga_operaciones_actor_fkey" FOREIGN KEY ("actor") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."base_carga_operaciones"
    ADD CONSTRAINT "base_carga_operaciones_base_id_fkey" FOREIGN KEY ("base_id") REFERENCES "crm"."bases_carga"("id");

ALTER TABLE ONLY "crm"."bases_carga"
    ADD CONSTRAINT "bases_carga_creada_por_fkey" FOREIGN KEY ("creada_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."bases_carga"
    ADD CONSTRAINT "bases_carga_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."busquedas_cliente_existente"
    ADD CONSTRAINT "busquedas_cliente_existente_consultado_por_fkey" FOREIGN KEY ("consultado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."busquedas_cliente_existente"
    ADD CONSTRAINT "busquedas_cliente_existente_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."busquedas_cliente_existente"
    ADD CONSTRAINT "busquedas_cliente_existente_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."capital_cortes_valorados"
    ADD CONSTRAINT "capital_cortes_valorados_meta_periodo_id_fkey" FOREIGN KEY ("meta_periodo_id") REFERENCES "crm"."meta_periodos"("id");

ALTER TABLE ONLY "crm"."capital_mes_sellos"
    ADD CONSTRAINT "capital_mes_sellos_corte_id_fkey" FOREIGN KEY ("corte_id") REFERENCES "crm"."capital_cortes_valorados"("id");

ALTER TABLE ONLY "crm"."capital_mes_sellos"
    ADD CONSTRAINT "capital_mes_sellos_periodo_fkey" FOREIGN KEY ("periodo") REFERENCES "crm"."periodos_cerrados"("periodo");

ALTER TABLE ONLY "crm"."capital_valoraciones"
    ADD CONSTRAINT "capital_valoraciones_anterior_id_fkey" FOREIGN KEY ("anterior_id") REFERENCES "crm"."capital_valoraciones"("id");

ALTER TABLE ONLY "crm"."capital_valoraciones"
    ADD CONSTRAINT "capital_valoraciones_fecha_tc_politica_tc_fkey" FOREIGN KEY ("fecha_tc", "politica_tc") REFERENCES "crm"."tipo_cambio_diario"("fecha_corte", "politica");

ALTER TABLE ONLY "crm"."cartera_lecturas"
    ADD CONSTRAINT "cartera_lecturas_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."cartera_lecturas"
    ADD CONSTRAINT "cartera_lecturas_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."celulares_asignaciones"
    ADD CONSTRAINT "celulares_asignaciones_analista_id_fkey" FOREIGN KEY ("analista_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."celulares_asignaciones"
    ADD CONSTRAINT "celulares_asignaciones_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierre_mes_vendedor"
    ADD CONSTRAINT "cierre_mes_vendedor_periodo_fkey" FOREIGN KEY ("periodo") REFERENCES "crm"."periodos_cerrados"("periodo") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierre_mes_vendedor"
    ADD CONSTRAINT "cierre_mes_vendedor_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierre_mes_vendedor"
    ADD CONSTRAINT "cierre_mes_vendedor_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_avance_anulados"
    ADD CONSTRAINT "cierres_avance_anulados_acreditado_a_fkey" FOREIGN KEY ("acreditado_a") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_avance_anulados"
    ADD CONSTRAINT "cierres_avance_anulados_anulado_por_fkey" FOREIGN KEY ("anulado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_avance_anulados"
    ADD CONSTRAINT "cierres_avance_anulados_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_anulado_por_fkey" FOREIGN KEY ("anulado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_comprobante_objeto_id_fkey" FOREIGN KEY ("comprobante_objeto_id") REFERENCES "storage"."objects"("id");

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cierres_externos"
    ADD CONSTRAINT "cierres_externos_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."configuracion_reparto"
    ADD CONSTRAINT "configuracion_reparto_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."contrato_cuentas_pago"
    ADD CONSTRAINT "contrato_cuentas_pago_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."contrato_cuentas_pago"
    ADD CONSTRAINT "contrato_cuentas_pago_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."contrato_cuentas_pago"
    ADD CONSTRAINT "contrato_cuentas_pago_cuenta_bancaria_id_fkey" FOREIGN KEY ("cuenta_bancaria_id") REFERENCES "crm"."cuentas_bancarias"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."control_citas_aplicaciones"
    ADD CONSTRAINT "control_citas_aplicaciones_aplicado_por_fkey" FOREIGN KEY ("aplicado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."control_citas_aplicaciones"
    ADD CONSTRAINT "control_citas_aplicaciones_version_fkey" FOREIGN KEY ("version") REFERENCES "crm"."control_citas_versiones"("version");

ALTER TABLE ONLY "crm"."control_citas_versiones"
    ADD CONSTRAINT "control_citas_versiones_guardado_por_fkey" FOREIGN KEY ("guardado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_episodio_id_fkey" FOREIGN KEY ("episodio_id") REFERENCES "crm"."lead_asignaciones"("id");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."conversion_acreditaciones"
    ADD CONSTRAINT "conversion_acreditaciones_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."conversion_reservas"
    ADD CONSTRAINT "conversion_reservas_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."conversion_reservas"
    ADD CONSTRAINT "conversion_reservas_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."conversion_reservas"
    ADD CONSTRAINT "conversion_reservas_reservado_por_fkey" FOREIGN KEY ("reservado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."conversion_ventas_recuperadas"
    ADD CONSTRAINT "conversion_ventas_recuperadas_cierre_avance_anulado_id_fkey" FOREIGN KEY ("cierre_avance_anulado_id") REFERENCES "crm"."cierres_avance_anulados"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."conversion_ventas_recuperadas"
    ADD CONSTRAINT "conversion_ventas_recuperadas_inversion_eliminada_id_fkey" FOREIGN KEY ("inversion_eliminada_id") REFERENCES "crm"."inversiones_eliminadas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."cuentas_bancarias"
    ADD CONSTRAINT "cuentas_bancarias_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."perfiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."cuentas_bancarias"
    ADD CONSTRAINT "cuentas_bancarias_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."cuentas_bancarias"
    ADD CONSTRAINT "cuentas_bancarias_desactivada_por_fkey" FOREIGN KEY ("desactivada_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."depositos_reclamados"
    ADD CONSTRAINT "depositos_reclamados_cierre_id_fkey" FOREIGN KEY ("cierre_id") REFERENCES "crm"."cierres_externos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."depositos_reclamados"
    ADD CONSTRAINT "depositos_reclamados_reclamado_por_fkey" FOREIGN KEY ("reclamado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."dispositivos_push_tasa"
    ADD CONSTRAINT "dispositivos_push_tasa_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "crm"."equipo"("perfil_id");

ALTER TABLE ONLY "crm"."empresas"
    ADD CONSTRAINT "empresas_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."enfriamiento_politica"
    ADD CONSTRAINT "enfriamiento_politica_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."envios_push_tasa"
    ADD CONSTRAINT "envios_push_tasa_dispositivo_id_fkey" FOREIGN KEY ("dispositivo_id") REFERENCES "crm"."dispositivos_push_tasa"("id");

ALTER TABLE ONLY "crm"."envios_push_tasa"
    ADD CONSTRAINT "envios_push_tasa_solicitud_id_fkey" FOREIGN KEY ("solicitud_id") REFERENCES "crm"."solicitudes_tasa"("id");

ALTER TABLE ONLY "crm"."equipo"
    ADD CONSTRAINT "equipo_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."equipo"
    ADD CONSTRAINT "equipo_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."equipo"
    ADD CONSTRAINT "equipo_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."gestion_diaria_control_avisos"
    ADD CONSTRAINT "gestion_diaria_control_avisos_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."gestion_diaria_entregas"
    ADD CONSTRAINT "gestion_diaria_entregas_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_ajustes_mes_cerrado"
    ADD CONSTRAINT "inversion_ajustes_mes_cerrado_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_ajustes_mes_cerrado"
    ADD CONSTRAINT "inversion_ajustes_mes_cerrado_inversion_id_fkey" FOREIGN KEY ("inversion_id") REFERENCES "crm"."inversiones"("id");

ALTER TABLE ONLY "crm"."inversion_ajustes_mes_cerrado"
    ADD CONSTRAINT "inversion_ajustes_mes_cerrado_periodo_origen_fkey" FOREIGN KEY ("periodo_origen") REFERENCES "crm"."periodos_cerrados"("periodo");

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_contrato_titular_id_fkey" FOREIGN KEY ("contrato_titular_id") REFERENCES "public"."contrato_titulares"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_identificador_origen_id_fkey" FOREIGN KEY ("identificador_origen_id") REFERENCES "crm"."inversionista_identificadores"("id");

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_inversion_id_fkey" FOREIGN KEY ("inversion_id") REFERENCES "crm"."inversiones"("id");

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_persona_origen_id_fkey" FOREIGN KEY ("persona_origen_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversion_cotitular_origenes"
    ADD CONSTRAINT "inversion_cotitular_origenes_vinculado_por_fkey" FOREIGN KEY ("vinculado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_eventos"
    ADD CONSTRAINT "inversion_eventos_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_eventos"
    ADD CONSTRAINT "inversion_eventos_inversion_id_fkey" FOREIGN KEY ("inversion_id") REFERENCES "crm"."inversiones"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_correcciones"
    ADD CONSTRAINT "inversion_solicitud_correcciones_corregido_por_fkey" FOREIGN KEY ("corregido_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_correcciones"
    ADD CONSTRAINT "inversion_solicitud_correcciones_solicitud_id_fkey" FOREIGN KEY ("solicitud_id") REFERENCES "crm"."inversion_solicitudes"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_origenes"
    ADD CONSTRAINT "inversion_solicitud_origenes_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_origenes"
    ADD CONSTRAINT "inversion_solicitud_origenes_fuente_id_fkey" FOREIGN KEY ("fuente_id") REFERENCES "crm"."cierres_externos"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_origenes"
    ADD CONSTRAINT "inversion_solicitud_origenes_solicitud_id_fkey" FOREIGN KEY ("solicitud_id") REFERENCES "crm"."inversion_solicitudes"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_revisiones"
    ADD CONSTRAINT "inversion_solicitud_revisiones_responsable_anterior_id_fkey" FOREIGN KEY ("responsable_anterior_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_revisiones"
    ADD CONSTRAINT "inversion_solicitud_revisiones_responsable_nuevo_id_fkey" FOREIGN KEY ("responsable_nuevo_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_revisiones"
    ADD CONSTRAINT "inversion_solicitud_revisiones_revisado_por_fkey" FOREIGN KEY ("revisado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitud_revisiones"
    ADD CONSTRAINT "inversion_solicitud_revisiones_solicitud_id_fkey" FOREIGN KEY ("solicitud_id") REFERENCES "crm"."inversion_solicitudes"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_analista_cierre_id_fkey" FOREIGN KEY ("analista_cierre_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_busqueda_id_fkey" FOREIGN KEY ("busqueda_id") REFERENCES "crm"."busquedas_cliente_existente"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_confirmado_por_fkey" FOREIGN KEY ("confirmado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "crm"."empresas"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_inversion_id_fkey" FOREIGN KEY ("inversion_id") REFERENCES "crm"."inversiones"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_lead_origen_id_fkey" FOREIGN KEY ("lead_origen_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."inversion_solicitudes"
    ADD CONSTRAINT "inversion_solicitudes_responsable_esperado_id_fkey" FOREIGN KEY ("responsable_esperado_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_titulares"
    ADD CONSTRAINT "inversion_titulares_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversion_titulares"
    ADD CONSTRAINT "inversion_titulares_inversion_id_fkey" FOREIGN KEY ("inversion_id") REFERENCES "crm"."inversiones"("id");

ALTER TABLE ONLY "crm"."inversion_titulares"
    ADD CONSTRAINT "inversion_titulares_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversiones"
    ADD CONSTRAINT "inversiones_cierre_externo_id_fkey" FOREIGN KEY ("cierre_externo_id") REFERENCES "crm"."cierres_externos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."inversiones"
    ADD CONSTRAINT "inversiones_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."inversiones"
    ADD CONSTRAINT "inversiones_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversiones_eliminadas"
    ADD CONSTRAINT "inversiones_eliminadas_contrato_auditoria_id_fkey" FOREIGN KEY ("contrato_auditoria_id") REFERENCES "crm"."contratos_eliminados_auditoria"("id");

ALTER TABLE ONLY "crm"."inversiones"
    ADD CONSTRAINT "inversiones_empresa_id_fkey" FOREIGN KEY ("empresa_id") REFERENCES "crm"."empresas"("id");

ALTER TABLE ONLY "crm"."inversiones"
    ADD CONSTRAINT "inversiones_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_datos_contacto"
    ADD CONSTRAINT "inversionista_datos_contacto_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_datos_contacto"
    ADD CONSTRAINT "inversionista_datos_contacto_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_fusiones"
    ADD CONSTRAINT "inversionista_fusiones_canonico_id_fkey" FOREIGN KEY ("canonico_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_fusiones"
    ADD CONSTRAINT "inversionista_fusiones_fusionado_id_fkey" FOREIGN KEY ("fusionado_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_fusiones"
    ADD CONSTRAINT "inversionista_fusiones_por_fkey" FOREIGN KEY ("por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_gestiones"
    ADD CONSTRAINT "inversionista_gestiones_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_gestiones"
    ADD CONSTRAINT "inversionista_gestiones_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_gestiones"
    ADD CONSTRAINT "inversionista_gestiones_tarea_id_fkey" FOREIGN KEY ("tarea_id") REFERENCES "crm"."tareas"("id");

ALTER TABLE ONLY "crm"."inversionista_identificadores"
    ADD CONSTRAINT "inversionista_identificadores_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_identificadores"
    ADD CONSTRAINT "inversionista_identificadores_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_leads"
    ADD CONSTRAINT "inversionista_leads_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_leads"
    ADD CONSTRAINT "inversionista_leads_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_leads"
    ADD CONSTRAINT "inversionista_leads_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."inversionista_operaciones"
    ADD CONSTRAINT "inversionista_operaciones_identificador_anterior_id_fkey" FOREIGN KEY ("identificador_anterior_id") REFERENCES "crm"."inversionista_identificadores"("id");

ALTER TABLE ONLY "crm"."inversionista_operaciones"
    ADD CONSTRAINT "inversionista_operaciones_identificador_nuevo_id_fkey" FOREIGN KEY ("identificador_nuevo_id") REFERENCES "crm"."inversionista_identificadores"("id");

ALTER TABLE ONLY "crm"."inversionista_operaciones"
    ADD CONSTRAINT "inversionista_operaciones_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_operaciones"
    ADD CONSTRAINT "inversionista_operaciones_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."inversionista_operaciones"
    ADD CONSTRAINT "inversionista_operaciones_por_fkey" FOREIGN KEY ("por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_responsables"
    ADD CONSTRAINT "inversionista_responsables_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionista_responsables"
    ADD CONSTRAINT "inversionista_responsables_por_fkey" FOREIGN KEY ("por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionista_responsables"
    ADD CONSTRAINT "inversionista_responsables_responsable_id_fkey" FOREIGN KEY ("responsable_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionistas"
    ADD CONSTRAINT "inversionistas_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionistas"
    ADD CONSTRAINT "inversionistas_inversionista_canonico_id_fkey" FOREIGN KEY ("inversionista_canonico_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."inversionistas"
    ADD CONSTRAINT "inversionistas_no_contactar_por_fkey" FOREIGN KEY ("no_contactar_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionistas"
    ADD CONSTRAINT "inversionistas_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."inversionistas"
    ADD CONSTRAINT "inversionistas_responsable_relacion_id_fkey" FOREIGN KEY ("responsable_relacion_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."lead_asignacion_sla_hitos"
    ADD CONSTRAINT "lead_asignacion_sla_hitos_lead_asignacion_id_fkey" FOREIGN KEY ("lead_asignacion_id") REFERENCES "crm"."lead_asignaciones"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_analista_destino_id_fkey" FOREIGN KEY ("analista_destino_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_analista_id_fkey" FOREIGN KEY ("analista_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_asignado_por_fkey" FOREIGN KEY ("asignado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_finalizado_por_fkey" FOREIGN KEY ("finalizado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_sla_politica_asignacion_id_fkey" FOREIGN KEY ("sla_politica_asignacion_id") REFERENCES "crm"."sla_politicas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_supervisor_destino_id_fkey" FOREIGN KEY ("supervisor_destino_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_asignaciones"
    ADD CONSTRAINT "lead_asignaciones_supervisor_origen_id_fkey" FOREIGN KEY ("supervisor_origen_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_potencial_eventos"
    ADD CONSTRAINT "lead_potencial_eventos_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."lead_potencial_eventos"
    ADD CONSTRAINT "lead_potencial_eventos_por_fkey" FOREIGN KEY ("por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."lead_potencial"
    ADD CONSTRAINT "lead_potencial_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id");

ALTER TABLE ONLY "crm"."lead_potencial"
    ADD CONSTRAINT "lead_potencial_marcado_por_fkey" FOREIGN KEY ("marcado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."lead_sla_ciclos"
    ADD CONSTRAINT "lead_sla_ciclos_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_ciclos"
    ADD CONSTRAINT "lead_sla_ciclos_politica_id_fkey" FOREIGN KEY ("politica_id") REFERENCES "crm"."sla_politicas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_etapa_ajustes"
    ADD CONSTRAINT "lead_sla_etapa_ajustes_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_etapa_ajustes"
    ADD CONSTRAINT "lead_sla_etapa_ajustes_etapa_sla_id_fkey" FOREIGN KEY ("etapa_sla_id") REFERENCES "crm"."lead_sla_etapas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_etapa_ajustes"
    ADD CONSTRAINT "lead_sla_etapa_ajustes_origen_actividad_id_fkey" FOREIGN KEY ("origen_actividad_id") REFERENCES "crm"."actividades"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_etapas"
    ADD CONSTRAINT "lead_sla_etapas_ciclo_fk" FOREIGN KEY ("lead_id", "ciclo_n") REFERENCES "crm"."lead_sla_ciclos"("lead_id", "ciclo_n") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_etapas"
    ADD CONSTRAINT "lead_sla_etapas_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."lead_sla_etapas"
    ADD CONSTRAINT "lead_sla_etapas_politica_id_fkey" FOREIGN KEY ("politica_id") REFERENCES "crm"."sla_politicas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_asignado_supervisor_id_fkey" FOREIGN KEY ("asignado_supervisor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_descartado_por_fkey" FOREIGN KEY ("descartado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."leads"
    ADD CONSTRAINT "leads_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."ledger_rentabilidad"
    ADD CONSTRAINT "ledger_rentabilidad_politica_id_fkey" FOREIGN KEY ("politica_id") REFERENCES "crm"."politica_rentabilidad"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."ledger_rentabilidad"
    ADD CONSTRAINT "ledger_rentabilidad_solicitud_id_fkey" FOREIGN KEY ("solicitud_id") REFERENCES "crm"."solicitudes_tasa"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_actividad_id_fkey" FOREIGN KEY ("actividad_id") REFERENCES "crm"."actividades"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_enlazado_por_fkey" FOREIGN KEY ("enlazado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_evento_id_fkey" FOREIGN KEY ("evento_id") REFERENCES "crm"."llamadas_celular_eventos"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."llamadas_celular_enlaces"
    ADD CONSTRAINT "llamadas_celular_enlaces_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_analista_id_fkey" FOREIGN KEY ("analista_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_asignacion_id_fkey" FOREIGN KEY ("asignacion_id") REFERENCES "crm"."celulares_asignaciones"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_asociado_por_fkey" FOREIGN KEY ("asociado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_descartado_por_fkey" FOREIGN KEY ("descartado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."llamadas_celular_eventos"
    ADD CONSTRAINT "llamadas_celular_eventos_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."llamadas_celular_politica"
    ADD CONSTRAINT "llamadas_celular_politica_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."meta_periodos"
    ADD CONSTRAINT "meta_periodos_publicada_por_fkey" FOREIGN KEY ("publicada_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."meta_periodos"
    ADD CONSTRAINT "meta_periodos_revision_anterior_id_fkey" FOREIGN KEY ("revision_anterior_id") REFERENCES "crm"."meta_periodos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."metas_vendedor_detalle"
    ADD CONSTRAINT "metas_vendedor_detalle_meta_vendedor_id_fkey" FOREIGN KEY ("meta_vendedor_id") REFERENCES "crm"."metas_vendedor"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."metas_vendedor"
    ADD CONSTRAINT "metas_vendedor_meta_periodo_id_fkey" FOREIGN KEY ("meta_periodo_id") REFERENCES "crm"."meta_periodos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."metas_vendedor"
    ADD CONSTRAINT "metas_vendedor_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."metas_vendedor"
    ADD CONSTRAINT "metas_vendedor_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."multiempresa_flags"
    ADD CONSTRAINT "multiempresa_flags_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."multiempresa_idempotencia"
    ADD CONSTRAINT "multiempresa_idempotencia_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."objetivos_legacy_archivo"
    ADD CONSTRAINT "objetivos_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."objetivos_vendedores_legacy_archivo"
    ADD CONSTRAINT "objetivos_vendedores_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "auth"."users"("id");

ALTER TABLE ONLY "crm"."objetivos_vendedores_legacy_archivo"
    ADD CONSTRAINT "objetivos_vendedores_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "crm"."equipo"("perfil_id");

ALTER TABLE ONLY "crm"."objetivos_vendedores_legacy_archivo"
    ADD CONSTRAINT "objetivos_vendedores_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "crm"."equipo"("perfil_id");

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_contrato_nuevo_id_fkey" FOREIGN KEY ("contrato_nuevo_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_contrato_origen_id_fkey" FOREIGN KEY ("contrato_origen_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."operaciones_cartera"
    ADD CONSTRAINT "operaciones_cartera_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."periodos_cerrados"
    ADD CONSTRAINT "periodos_cerrados_cerrado_por_fkey" FOREIGN KEY ("cerrado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."piloto_f8_control"
    ADD CONSTRAINT "piloto_f8_control_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."piloto_f8_miembros"
    ADD CONSTRAINT "piloto_f8_miembros_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."piloto_f8_miembros"
    ADD CONSTRAINT "piloto_f8_miembros_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."plazos_carga_mes"
    ADD CONSTRAINT "plazos_carga_mes_decidido_por_fkey" FOREIGN KEY ("decidido_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."plazos_carga_mes"
    ADD CONSTRAINT "plazos_carga_mes_reapertura_fkey" FOREIGN KEY ("reapertura_id", "periodo") REFERENCES "crm"."reaperturas_mes"("id", "periodo") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."politica_abandono"
    ADD CONSTRAINT "politica_abandono_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."politica_gestion_diaria"
    ADD CONSTRAINT "politica_gestion_diaria_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."politica_gestion_diaria"
    ADD CONSTRAINT "politica_gestion_diaria_version_anterior_id_fkey" FOREIGN KEY ("version_anterior_id") REFERENCES "crm"."politica_gestion_diaria"("id");

ALTER TABLE ONLY "crm"."politica_rentabilidad"
    ADD CONSTRAINT "politica_rentabilidad_publicada_por_fkey" FOREIGN KEY ("publicada_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."politica_rentabilidad"
    ADD CONSTRAINT "politica_rentabilidad_version_anterior_id_fkey" FOREIGN KEY ("version_anterior_id") REFERENCES "crm"."politica_rentabilidad"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."postventa_operaciones"
    ADD CONSTRAINT "postventa_operaciones_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."postventa_operaciones"
    ADD CONSTRAINT "postventa_operaciones_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."postventa_retiros"
    ADD CONSTRAINT "postventa_retiros_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."postventa_retiros"
    ADD CONSTRAINT "postventa_retiros_fuente_id_fkey" FOREIGN KEY ("fuente_id") REFERENCES "crm"."cierres_externos"("id");

ALTER TABLE ONLY "crm"."postventa_retiros"
    ADD CONSTRAINT "postventa_retiros_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."postventa_retiros"
    ADD CONSTRAINT "postventa_retiros_revisado_por_fkey" FOREIGN KEY ("revisado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."producto_condiciones"
    ADD CONSTRAINT "producto_condiciones_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."producto_condiciones"
    ADD CONSTRAINT "producto_condiciones_retirada_por_fkey" FOREIGN KEY ("retirada_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."producto_condiciones"
    ADD CONSTRAINT "producto_condiciones_version_id_fkey" FOREIGN KEY ("version_id") REFERENCES "crm"."producto_versiones"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_producto_id_fkey" FOREIGN KEY ("producto_id") REFERENCES "crm"."productos_inversion"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_publicada_por_fkey" FOREIGN KEY ("publicada_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."producto_versiones"
    ADD CONSTRAINT "producto_versiones_retirada_por_fkey" FOREIGN KEY ("retirada_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."productos_inversion"
    ADD CONSTRAINT "productos_inversion_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."productos_inversion"
    ADD CONSTRAINT "productos_inversion_archivado_por_fkey" FOREIGN KEY ("archivado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."productos_inversion"
    ADD CONSTRAINT "productos_inversion_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."reaperturas_mes"
    ADD CONSTRAINT "reaperturas_mes_decidido_por_fkey" FOREIGN KEY ("decidido_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."reasignaciones_analista"
    ADD CONSTRAINT "reasignaciones_analista_analista_a_fkey" FOREIGN KEY ("analista_a") REFERENCES "crm"."equipo"("perfil_id");

ALTER TABLE ONLY "crm"."reasignaciones_analista"
    ADD CONSTRAINT "reasignaciones_analista_analista_de_fkey" FOREIGN KEY ("analista_de") REFERENCES "crm"."equipo"("perfil_id");

ALTER TABLE ONLY "crm"."reasignaciones_analista"
    ADD CONSTRAINT "reasignaciones_analista_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."reasignaciones_analista"
    ADD CONSTRAINT "reasignaciones_analista_reasignado_por_fkey" FOREIGN KEY ("reasignado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."recordatorios_disponibilidad"
    ADD CONSTRAINT "recordatorios_disponibilidad_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."recorrido_control"
    ADD CONSTRAINT "recorrido_control_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "crm"."sla_operacion_control"
    ADD CONSTRAINT "sla_operacion_control_cambiado_por_fkey" FOREIGN KEY ("cambiado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."sla_operacion_control"
    ADD CONSTRAINT "sla_operacion_control_politica_adopcion_id_fkey" FOREIGN KEY ("politica_adopcion_id") REFERENCES "crm"."sla_politicas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."sla_operacion_recibos"
    ADD CONSTRAINT "sla_operacion_recibos_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."perfiles"("id") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY "crm"."sla_operacion_recibos"
    ADD CONSTRAINT "sla_operacion_recibos_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE ONLY "crm"."sla_politica_etapas_operacion"
    ADD CONSTRAINT "sla_politica_etapas_operacion_politica_id_etapa_fkey" FOREIGN KEY ("politica_id", "etapa") REFERENCES "crm"."sla_politica_etapas"("politica_id", "etapa") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."sla_politica_etapas"
    ADD CONSTRAINT "sla_politica_etapas_politica_id_fkey" FOREIGN KEY ("politica_id") REFERENCES "crm"."sla_politicas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."sla_politicas"
    ADD CONSTRAINT "sla_politicas_publicada_por_fkey" FOREIGN KEY ("publicada_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."sla_politicas"
    ADD CONSTRAINT "sla_politicas_version_anterior_id_fkey" FOREIGN KEY ("version_anterior_id") REFERENCES "crm"."sla_politicas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."solicitudes_tasa"
    ADD CONSTRAINT "solicitudes_tasa_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."solicitudes_tasa"
    ADD CONSTRAINT "solicitudes_tasa_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."solicitudes_tasa"
    ADD CONSTRAINT "solicitudes_tasa_politica_id_fkey" FOREIGN KEY ("politica_id") REFERENCES "crm"."politica_rentabilidad"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."solicitudes_tasa"
    ADD CONSTRAINT "solicitudes_tasa_resuelta_por_fkey" FOREIGN KEY ("resuelta_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."solicitudes_tasa"
    ADD CONSTRAINT "solicitudes_tasa_solicitada_por_fkey" FOREIGN KEY ("solicitada_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."tarea_sla_contexto"
    ADD CONSTRAINT "tarea_sla_contexto_lead_id_ciclo_n_fkey" FOREIGN KEY ("lead_id", "ciclo_n") REFERENCES "crm"."lead_sla_ciclos"("lead_id", "ciclo_n") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."tarea_sla_contexto"
    ADD CONSTRAINT "tarea_sla_contexto_tarea_id_fkey" FOREIGN KEY ("tarea_id") REFERENCES "crm"."tareas"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_asignado_supervisor_id_fkey" FOREIGN KEY ("asignado_supervisor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_inversionista_id_fkey" FOREIGN KEY ("inversionista_id") REFERENCES "crm"."inversionistas"("id");

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_perfil_id_fkey" FOREIGN KEY ("perfil_id") REFERENCES "public"."perfiles"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_reagendada_de_fkey" FOREIGN KEY ("reagendada_de") REFERENCES "crm"."tareas"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_resultado_actividad_id_fkey" FOREIGN KEY ("resultado_actividad_id") REFERENCES "crm"."actividades"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."tareas"
    ADD CONSTRAINT "tareas_vendedor_id_fkey" FOREIGN KEY ("vendedor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE SET NULL;

ALTER TABLE ONLY "crm"."verificaciones_lead"
    ADD CONSTRAINT "verificaciones_lead_verificado_por_fkey" FOREIGN KEY ("verificado_por") REFERENCES "public"."perfiles"("id");

ALTER TABLE ONLY "private"."agenda_reparto_cambios"
    ADD CONSTRAINT "agenda_reparto_cambios_cambiado_por_fkey" FOREIGN KEY ("cambiado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."agenda_reparto_cambios"
    ADD CONSTRAINT "agenda_reparto_cambios_supervisor_anterior_id_fkey" FOREIGN KEY ("supervisor_anterior_id") REFERENCES "private"."agenda_reparto_destinos"("supervisor_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."agenda_reparto_cambios"
    ADD CONSTRAINT "agenda_reparto_cambios_supervisor_nuevo_id_fkey" FOREIGN KEY ("supervisor_nuevo_id") REFERENCES "private"."agenda_reparto_destinos"("supervisor_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."agenda_reparto_destinos"
    ADD CONSTRAINT "agenda_reparto_destinos_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."agenda_reparto_diaria"
    ADD CONSTRAINT "agenda_reparto_diaria_actualizado_por_fkey" FOREIGN KEY ("actualizado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."agenda_reparto_diaria"
    ADD CONSTRAINT "agenda_reparto_diaria_creado_por_fkey" FOREIGN KEY ("creado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."agenda_reparto_diaria"
    ADD CONSTRAINT "agenda_reparto_diaria_supervisor_id_fkey" FOREIGN KEY ("supervisor_id") REFERENCES "private"."agenda_reparto_destinos"("supervisor_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."ayuda_consultas"
    ADD CONSTRAINT "ayuda_consultas_intencion_id_fkey" FOREIGN KEY ("intencion_id") REFERENCES "private"."ayuda_intenciones"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "private"."ayuda_expresiones"
    ADD CONSTRAINT "ayuda_expresiones_intencion_id_fkey" FOREIGN KEY ("intencion_id") REFERENCES "private"."ayuda_intenciones"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "private"."celulares_estado"
    ADD CONSTRAINT "celulares_estado_asignacion_id_fkey" FOREIGN KEY ("asignacion_id") REFERENCES "crm"."celulares_asignaciones"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_altas_idempotentes"
    ADD CONSTRAINT "contrato_altas_idempotentes_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE SET NULL;

ALTER TABLE ONLY "private"."contrato_eliminaciones"
    ADD CONSTRAINT "contrato_eliminaciones_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_eliminaciones"
    ADD CONSTRAINT "contrato_eliminaciones_solicitado_por_fkey" FOREIGN KEY ("solicitado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_pdf_jobs"
    ADD CONSTRAINT "contrato_pdf_jobs_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_pdf_jobs"
    ADD CONSTRAINT "contrato_pdf_jobs_solicitado_por_fkey" FOREIGN KEY ("solicitado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_contrato_id_fkey" FOREIGN KEY ("contrato_id") REFERENCES "public"."contratos"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_generado_por_fkey" FOREIGN KEY ("generado_por") REFERENCES "public"."perfiles"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."contrato_pdfs"
    ADD CONSTRAINT "contrato_pdfs_job_fk" FOREIGN KEY ("job_id") REFERENCES "private"."contrato_pdf_jobs"("id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."llamadas_celular_intenciones"
    ADD CONSTRAINT "llamadas_celular_intenciones_actividad_id_fkey" FOREIGN KEY ("actividad_id") REFERENCES "crm"."actividades"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "private"."llamadas_celular_intenciones"
    ADD CONSTRAINT "llamadas_celular_intenciones_analista_id_fkey" FOREIGN KEY ("analista_id") REFERENCES "crm"."equipo"("perfil_id") ON DELETE RESTRICT;

ALTER TABLE ONLY "private"."llamadas_celular_intenciones"
    ADD CONSTRAINT "llamadas_celular_intenciones_lead_id_fkey" FOREIGN KEY ("lead_id") REFERENCES "crm"."leads"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "private"."llamadas_celular_recepciones"
    ADD CONSTRAINT "llamadas_celular_recepciones_asignacion_id_fkey" FOREIGN KEY ("asignacion_id") REFERENCES "crm"."celulares_asignaciones"("id") ON DELETE RESTRICT;

ALTER TABLE "crm"."actividad_ciclo_contexto" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."actividades" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."actividades_cliente" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "actividades_cliente_select" ON "crm"."actividades_cliente" FOR SELECT TO "authenticated" USING (( SELECT "private"."puede_consultar_cliente_ficha"("actividades_cliente"."cliente_id") AS "puede_consultar_cliente_ficha"));

COMMENT ON POLICY "actividades_cliente_select" ON "crm"."actividades_cliente" IS 'El historial de la Ficha 360 sigue la asignación actual del cliente.';

CREATE POLICY "actividades_insert" ON "crm"."actividades" FOR INSERT TO "authenticated" WITH CHECK ((("creado_por" = ( SELECT "auth"."uid"() AS "uid")) AND ("tipo" <> ALL (ARRAY['cambio_etapa'::"text", 'reasignacion'::"text", 'conversion'::"text"])) AND (EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE (("l"."id" = "actividades"."lead_id") AND ("l"."activo" = true) AND (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text") OR ("l"."vendedor_id" = ( SELECT "auth"."uid"() AS "uid")) OR (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'supervisor'::"text") AND (("l"."vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("l"."vendedor_id" IS NULL) AND ("l"."asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")))))))))));

CREATE POLICY "actividades_select" ON "crm"."actividades" FOR SELECT TO "authenticated" USING (((EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE (("l"."id" = "actividades"."lead_id") AND ("l"."activo" = true) AND (("l"."vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("l"."vendedor_id" IS NULL) AND ("l"."asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."es_lector_global"() AS "es_lector_global"))))) OR (( SELECT "private"."es_coordinacion_consulta"() AS "es_coordinacion_consulta") AND (EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE (("l"."id" = "actividades"."lead_id") AND ("l"."activo" IS TRUE)))))));

ALTER TABLE "crm"."agenda_ics" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "agenda_ics_insert" ON "crm"."agenda_ics" FOR INSERT TO "authenticated" WITH CHECK (("perfil_id" = ( SELECT "auth"."uid"() AS "uid")));

CREATE POLICY "agenda_ics_select" ON "crm"."agenda_ics" FOR SELECT TO "authenticated" USING (("perfil_id" = ( SELECT "auth"."uid"() AS "uid")));

CREATE POLICY "agenda_ics_update" ON "crm"."agenda_ics" FOR UPDATE TO "authenticated" USING (("perfil_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("perfil_id" = ( SELECT "auth"."uid"() AS "uid")));

ALTER TABLE "crm"."ajustes_mes_cerrado" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."alertas_reconocimientos" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "alertas_reconocimientos_insert" ON "crm"."alertas_reconocimientos" FOR INSERT TO "authenticated" WITH CHECK ((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'supervisor'::"text")));

CREATE POLICY "alertas_reconocimientos_select" ON "crm"."alertas_reconocimientos" FOR SELECT TO "authenticated" USING (((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'supervisor'::"text")) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text")));

CREATE POLICY "backfill_mapa_select_gerencia" ON "crm"."backfill_multiempresa_mapa" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."backfill_multiempresa_mapa" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."base_carga_leads" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "base_carga_leads_select" ON "crm"."base_carga_leads" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "crm"."bases_carga" "b"
  WHERE ("b"."id" = "base_carga_leads"."base_id"))));

COMMENT ON POLICY "base_carga_leads_select" ON "crm"."base_carga_leads" IS 'Segundo candado (no hay grants): ve las filas quien ve la base (exists sobre crm.bases_carga, cuya RLS decide).';

ALTER TABLE "crm"."base_carga_operaciones" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "base_carga_operaciones_select" ON "crm"."base_carga_operaciones" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "crm"."bases_carga" "b"
  WHERE ("b"."id" = "base_carga_operaciones"."base_id"))));

COMMENT ON POLICY "base_carga_operaciones_select" ON "crm"."base_carga_operaciones" IS 'Segundo candado (no hay grants): ve los recibos quien ve la base (exists sobre crm.bases_carga, cuya RLS decide).';

ALTER TABLE "crm"."bases_carga" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bases_carga_select" ON "crm"."bases_carga" FOR SELECT TO "authenticated" USING (((( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = ANY (ARRAY['supervisor'::"text", 'gerencia'::"text"])) AND ("supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))));

COMMENT ON POLICY "bases_carga_select" ON "crm"."bases_carga" IS 'Segundo candado (no hay grants): Supervisión ve las bases cuyo supervisor dueño está en su subárbol (las suyas y las de su equipo); Gerencia ve todas; el analista y cualquier otro rol, nada (lee su base por la puerta DEFINER de B10).';

ALTER TABLE "crm"."busquedas_cliente_existente" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cambio_cuenta_avisos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."capital_cortes_valorados" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."capital_mes_sellos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."capital_valoracion_politica" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."capital_valoraciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cartera_lecturas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."celulares_asignaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cierre_mes_vendedor" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cierres_avance_anulados" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cierres_externos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."configuracion_reparto" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."contrato_cuenta_pago_asignaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."contrato_cuenta_pago_cambios" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."contrato_cuentas_pago" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."contratos_eliminados_auditoria" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."control_citas_aplicaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."control_citas_versiones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."conversion_acreditaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."conversion_pesos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."conversion_politica" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."conversion_reservas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."conversion_ventas_recuperadas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."correcciones_categoria_contrato" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."correcciones_correo_acceso" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "correcciones_correo_acceso_lectura" ON "crm"."correcciones_correo_acceso" FOR SELECT TO "authenticated" USING ("public"."es_admin"());

CREATE POLICY "crm_actor_activo_gate" ON "crm"."actividades" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

CREATE POLICY "crm_actor_activo_gate" ON "crm"."agenda_ics" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

CREATE POLICY "crm_actor_activo_gate" ON "crm"."enfriamiento_politica" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

CREATE POLICY "crm_actor_activo_gate" ON "crm"."equipo" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

CREATE POLICY "crm_actor_activo_gate" ON "crm"."lead_asignaciones" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

CREATE POLICY "crm_actor_activo_gate" ON "crm"."leads" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

CREATE POLICY "crm_actor_activo_gate" ON "crm"."tareas" AS RESTRICTIVE TO "authenticated" USING (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm")) WITH CHECK (( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm"));

ALTER TABLE "crm"."cuentas_bancarias" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cuentas_bancarias_retiros" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."cuotas_cuenta_pagada" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."depositos_reclamados" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."dispositivos_push_tasa" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."empresas" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "empresas_select_gerencia" ON "crm"."empresas" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

CREATE POLICY "enfriamiento_insert" ON "crm"."enfriamiento_politica" FOR INSERT TO "authenticated" WITH CHECK (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text"));

ALTER TABLE "crm"."enfriamiento_politica" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "enfriamiento_select" ON "crm"."enfriamiento_politica" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "enfriamiento_update" ON "crm"."enfriamiento_politica" FOR UPDATE TO "authenticated" USING (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text")) WITH CHECK (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text"));

ALTER TABLE "crm"."envios_push_tasa" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."equipo" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "equipo_select" ON "crm"."equipo" FOR SELECT TO "authenticated" USING (((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND ("activo" = true)) OR ("perfil_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR ( SELECT "private"."es_lector_global"() AS "es_lector_global")));

ALTER TABLE "crm"."gestion_diaria_control_avisos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."gestion_diaria_entregas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_ajustes_mes_cerrado" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_backfill_lotes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_cotitular_origenes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_eventos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_solicitud_correcciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_solicitud_origenes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_solicitud_revisiones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_solicitudes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversion_titulares" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversion_titulares_select_gerencia" ON "crm"."inversion_titulares" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversiones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversiones_eliminadas" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversiones_select_gerencia" ON "crm"."inversiones" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversionista_datos_contacto" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversionista_fusiones" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversionista_fusiones_select_gerencia" ON "crm"."inversionista_fusiones" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversionista_gestiones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."inversionista_identificadores" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversionista_identificadores_select_gerencia" ON "crm"."inversionista_identificadores" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversionista_leads" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversionista_leads_select_gerencia" ON "crm"."inversionista_leads" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversionista_operaciones" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversionista_operaciones_select_gerencia" ON "crm"."inversionista_operaciones" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversionista_responsables" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversionista_responsables_select_gerencia" ON "crm"."inversionista_responsables" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."inversionistas" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inversionistas_select_gerencia" ON "crm"."inversionistas" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."lead_asignacion_sla_hitos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."lead_asignaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."lead_potencial" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."lead_potencial_eventos" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "lead_potencial_eventos_select" ON "crm"."lead_potencial_eventos" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE ("l"."id" = "lead_potencial_eventos"."lead_id"))));

COMMENT ON POLICY "lead_potencial_eventos_select" ON "crm"."lead_potencial_eventos" IS 'Segundo candado: si algún día se concede SELECT, ve el historial solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

CREATE POLICY "lead_potencial_select" ON "crm"."lead_potencial" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE ("l"."id" = "lead_potencial"."lead_id"))));

COMMENT ON POLICY "lead_potencial_select" ON "crm"."lead_potencial" IS 'Segundo candado: si algún día se concede SELECT, ve la marca solo quien ve el lead (el exists corre con la RLS de crm.leads del que consulta).';

ALTER TABLE "crm"."lead_sla_ciclos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."lead_sla_etapa_ajustes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."lead_sla_etapas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."leads" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."leads_eliminados" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "leads_select" ON "crm"."leads" FOR SELECT TO "authenticated" USING (((("activo" = true) AND (("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."es_lector_global"() AS "es_lector_global"))) OR (("activo" IS TRUE) AND ( SELECT "private"."es_coordinacion_consulta"() AS "es_coordinacion_consulta"))));

CREATE POLICY "leads_update" ON "crm"."leads" FOR UPDATE TO "authenticated" USING ((("activo" = true) AND (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text") OR ("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")))))) WITH CHECK (((("vendedor_id" IS NULL) OR ("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) AND (("asignado_supervisor_id" IS NULL) OR ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) AND (("activo" = true) OR ("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = ANY (ARRAY['supervisor'::"text", 'gerencia'::"text"])))));

CREATE POLICY "lectura_interna" ON "crm"."gestion_diaria_control_avisos" FOR SELECT TO "crm_gestion_diaria_lector" USING (("private"."puede_acceder_crm"() AND ("private"."rol_crm"("auth"."uid"()) = 'supervisor'::"text")));

CREATE POLICY "lectura_interna" ON "crm"."gestion_diaria_entregas" FOR SELECT TO "crm_gestion_diaria_lector" USING ((("perfil_id" = "auth"."uid"()) AND "private"."puede_acceder_crm"() AND ("private"."rol_crm"("auth"."uid"()) = 'supervisor'::"text")));

ALTER TABLE "crm"."ledger_rentabilidad" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ledger_rentabilidad_select" ON "crm"."ledger_rentabilidad" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."puede_consultar_cliente_ficha"("ledger_rentabilidad"."cliente_id") AS "puede_consultar_cliente_ficha")));

ALTER TABLE "crm"."llamadas_celular_enlaces" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."llamadas_celular_eventos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."llamadas_celular_politica" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."meta_periodos" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meta_periodos_select" ON "crm"."meta_periodos" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL)));

ALTER TABLE "crm"."metas_vendedor" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."metas_vendedor_detalle" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "metas_vendedor_detalle_select" ON "crm"."metas_vendedor_detalle" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (EXISTS ( SELECT 1
   FROM "crm"."metas_vendedor" "mv"
  WHERE (("mv"."id" = "metas_vendedor_detalle"."meta_vendedor_id") AND ("mv"."vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")))))));

CREATE POLICY "metas_vendedor_select" ON "crm"."metas_vendedor" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR ("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))));

ALTER TABLE "crm"."multiempresa_flags" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "multiempresa_flags_select_gerencia" ON "crm"."multiempresa_flags" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."multiempresa_idempotencia" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "multiempresa_idempotencia_select_gerencia" ON "crm"."multiempresa_idempotencia" FOR SELECT TO "authenticated" USING ("private"."es_gerencia_crm_activa"());

ALTER TABLE "crm"."objetivos_legacy_archivo" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."objetivos_vendedores_legacy_archivo" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."operaciones_cartera" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "operaciones_cartera_select" ON "crm"."operaciones_cartera" FOR SELECT TO "authenticated" USING (( SELECT "private"."puede_consultar_cliente_ficha"("operaciones_cartera"."cliente_id") AS "puede_consultar_cliente_ficha"));

COMMENT ON POLICY "operaciones_cartera_select" ON "crm"."operaciones_cartera" IS 'Renovaciones y aumentos siguen la asignación actual del cliente; la atribución histórica no concede lectura.';

ALTER TABLE "crm"."origenes_capital_confirmados" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."periodos_cerrados" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."piloto_f8_control" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."piloto_f8_miembros" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."plazos_carga_mes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."politica_abandono" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "politica_abandono_select" ON "crm"."politica_abandono" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL)));

CREATE POLICY "politica_abandono_update" ON "crm"."politica_abandono" FOR UPDATE TO "authenticated" USING (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text")) WITH CHECK (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text"));

ALTER TABLE "crm"."politica_gestion_diaria" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "politica_gestion_diaria_select" ON "crm"."politica_gestion_diaria" FOR SELECT TO "authenticated" USING ((( SELECT "private"."puede_acceder_crm"() AS "puede_acceder_crm") AND (( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL))));

ALTER TABLE "crm"."politica_rentabilidad" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "politica_rentabilidad_select" ON "crm"."politica_rentabilidad" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL)));

ALTER TABLE "crm"."postventa_escrituras" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."postventa_operaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."postventa_retiros" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."producto_condiciones" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "producto_condiciones_select" ON "crm"."producto_condiciones" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ((( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL) AND "activa" AND (NOT "es_legacy") AND (EXISTS ( SELECT 1
   FROM ("crm"."producto_versiones" "v"
     JOIN "crm"."productos_inversion" "p" ON (("p"."id" = "v"."producto_id")))
  WHERE (("v"."id" = "producto_condiciones"."version_id") AND ("v"."estado" = ANY (ARRAY['publicada'::"text", 'retirada'::"text"])) AND (NOT "p"."es_legacy")))))));

ALTER TABLE "crm"."producto_versiones" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "producto_versiones_select" ON "crm"."producto_versiones" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ((( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL) AND ("estado" = ANY (ARRAY['publicada'::"text", 'retirada'::"text"])) AND (EXISTS ( SELECT 1
   FROM "crm"."productos_inversion" "p"
  WHERE (("p"."id" = "producto_versiones"."producto_id") AND (NOT "p"."es_legacy")))))));

ALTER TABLE "crm"."productos_inversion" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "productos_inversion_select" ON "crm"."productos_inversion" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ((( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL) AND (NOT "es_legacy") AND ( SELECT "private"."producto_inversion_tiene_version_visible"("productos_inversion"."id") AS "producto_inversion_tiene_version_visible"))));

ALTER TABLE "crm"."reaperturas_mes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."reasignaciones_analista" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "reasignaciones_lee_autoridad" ON "crm"."reasignaciones_analista" FOR SELECT TO "authenticated" USING (((( SELECT "public"."es_gestor_cartera"() AS "es_gestor_cartera") OR COALESCE(("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text"), false)) AND (NOT ( SELECT "private"."membresia_crm_revocada"() AS "membresia_crm_revocada"))));

ALTER TABLE "crm"."recordatorios_disponibilidad" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "recordatorios_disponibilidad_delete" ON "crm"."recordatorios_disponibilidad" FOR DELETE TO "authenticated" USING ((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'vendedor'::"text")));

CREATE POLICY "recordatorios_disponibilidad_insert" ON "crm"."recordatorios_disponibilidad" FOR INSERT TO "authenticated" WITH CHECK ((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'vendedor'::"text")));

CREATE POLICY "recordatorios_disponibilidad_select" ON "crm"."recordatorios_disponibilidad" FOR SELECT TO "authenticated" USING ((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'vendedor'::"text")));

CREATE POLICY "recordatorios_disponibilidad_update" ON "crm"."recordatorios_disponibilidad" FOR UPDATE TO "authenticated" USING ((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'vendedor'::"text"))) WITH CHECK ((("perfil_id" = ( SELECT "auth"."uid"() AS "uid")) AND (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'vendedor'::"text")));

ALTER TABLE "crm"."recorrido_control" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."rentabilidad_hitos" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rentabilidad_hitos_select" ON "crm"."rentabilidad_hitos" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL)));

ALTER TABLE "crm"."sla_operacion_control" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."sla_operacion_recibos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."sla_politica_etapas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."sla_politica_etapas_operacion" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sla_politica_etapas_select" ON "crm"."sla_politica_etapas" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL)));

ALTER TABLE "crm"."sla_politicas" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sla_politicas_select" ON "crm"."sla_politicas" FOR SELECT TO "authenticated" USING ((( SELECT "private"."es_lector_global"() AS "es_lector_global") OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") IS NOT NULL)));

ALTER TABLE "crm"."solicitudes_desechadas_corridas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."solicitudes_tasa" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "solicitudes_tasa_select" ON "crm"."solicitudes_tasa" FOR SELECT TO "authenticated" USING (((("solicitada_por" = ( SELECT "auth"."uid"() AS "uid")) OR "private"."es_lector_global"() OR ("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text") OR ("solicitada_por" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) AND (("lead_id" IS NULL) OR ("solicitada_por" = ( SELECT "auth"."uid"() AS "uid")) OR "private"."puede_ver_tasa_lead"("lead_id"))));

ALTER TABLE "crm"."tarea_sla_contexto" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."tareas" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tareas_destino_efectivo_insert" ON "crm"."tareas" AS RESTRICTIVE FOR INSERT TO "authenticated" WITH CHECK (((NOT (("activo" IS TRUE) AND ("estado" = 'pendiente'::"text"))) OR ((("vendedor_id" IS NOT NULL) OR ("asignado_supervisor_id" IS NOT NULL)) AND (("vendedor_id" IS NULL) OR ("private"."rol_crm"("vendedor_id") = ANY (ARRAY['vendedor'::"text", 'supervisor'::"text"]))) AND (("asignado_supervisor_id" IS NULL) OR ("private"."rol_crm"("asignado_supervisor_id") = 'supervisor'::"text")))));

CREATE POLICY "tareas_destino_efectivo_update" ON "crm"."tareas" AS RESTRICTIVE FOR UPDATE TO "authenticated" USING (true) WITH CHECK (((NOT (("activo" IS TRUE) AND ("estado" = 'pendiente'::"text"))) OR ((("vendedor_id" IS NOT NULL) OR ("asignado_supervisor_id" IS NOT NULL)) AND (("vendedor_id" IS NULL) OR ("private"."rol_crm"("vendedor_id") = ANY (ARRAY['vendedor'::"text", 'supervisor'::"text"]))) AND (("asignado_supervisor_id" IS NULL) OR ("private"."rol_crm"("asignado_supervisor_id") = 'supervisor'::"text")))));

CREATE POLICY "tareas_insert" ON "crm"."tareas" FOR INSERT TO "authenticated" WITH CHECK ((("activo" = true) AND ("creado_por" = ( SELECT "auth"."uid"() AS "uid")) AND "private"."puede_asignar_destino_tarea"("vendedor_id", "asignado_supervisor_id") AND (("lead_id" IS NULL) OR (EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE ("l"."id" = "tareas"."lead_id")))) AND (("perfil_id" IS NULL) OR "private"."puede_gestionar_tarea_cliente"("perfil_id", "vendedor_id"))));

CREATE POLICY "tareas_postventa_insert" ON "crm"."tareas" AS RESTRICTIVE FOR INSERT TO "authenticated" WITH CHECK (("inversionista_id" IS NULL));

CREATE POLICY "tareas_postventa_lectura" ON "crm"."tareas" AS RESTRICTIVE FOR SELECT TO "authenticated" USING ((("inversionista_id" IS NULL) OR "private"."postventa_visible"("inversionista_id")));

CREATE POLICY "tareas_postventa_update" ON "crm"."tareas" AS RESTRICTIVE FOR UPDATE TO "authenticated" USING (("inversionista_id" IS NULL)) WITH CHECK (("inversionista_id" IS NULL));

CREATE POLICY "tareas_select" ON "crm"."tareas" FOR SELECT TO "authenticated" USING (((("activo" = true) AND (("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles"))) OR (( SELECT "private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) AS "rol_crm") = 'gerencia'::"text") OR ( SELECT "private"."es_lector_global"() AS "es_lector_global"))) OR (("activo" IS TRUE) AND ( SELECT "private"."es_coordinacion_consulta"() AS "es_coordinacion_consulta") AND (EXISTS ( SELECT 1
   FROM "crm"."leads" "l"
  WHERE (("l"."id" = "tareas"."lead_id") AND ("l"."activo" IS TRUE)))))));

CREATE POLICY "tareas_update" ON "crm"."tareas" FOR UPDATE TO "authenticated" USING ((("activo" = true) AND (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text") OR ("vendedor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")) OR (("vendedor_id" IS NULL) AND ("asignado_supervisor_id" IN ( SELECT "private"."vendedor_ids_visibles"(( SELECT "auth"."uid"() AS "uid")) AS "vendedor_ids_visibles")))))) WITH CHECK (("activo" = true));

ALTER TABLE "crm"."tipo_cambio_diario" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."tipo_cambio_trabajos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."usuario_eventos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "crm"."verificaciones_lead" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "verificaciones_lead_select" ON "crm"."verificaciones_lead" FOR SELECT TO "authenticated" USING (("private"."rol_crm"(( SELECT "auth"."uid"() AS "uid")) = 'gerencia'::"text"));

ALTER TABLE "private"."agenda_reparto_cambios" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."agenda_reparto_destinos" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."agenda_reparto_diaria" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."analista_vigencia_exenciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."analista_vigencia_tope" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."analitica_lc_sello" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."analitica_leads_citas_exenciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."analitica_leads_citas_tope" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."auditoria_alertas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."auditoria_condicionada" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."auditoria_exenciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."auditoria_sello" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."ayuda_consultas" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."ayuda_expresiones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."ayuda_intenciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."ayuda_reglas_aclaracion" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."backfill_cuentas_p0xx" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."celulares_estado" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."conciliacion_cuentas_p0xx" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."contrato_altas_idempotentes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."contrato_eliminaciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."contrato_pdf_anexo_emisiones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."contrato_pdf_jobs" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."contrato_pdfs" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."f7_piezas_en_observacion" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."llamadas_celular_intenciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."llamadas_celular_recepciones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."membresias_purgadas" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "p0xx_solo_interno" ON "private"."backfill_cuentas_p0xx" AS RESTRICTIVE USING (false) WITH CHECK (false);

CREATE POLICY "p0xx_solo_interno" ON "private"."conciliacion_cuentas_p0xx" AS RESTRICTIVE USING (false) WITH CHECK (false);

ALTER TABLE "private"."pares_autoridad" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."respaldo_cierre_septiembre_2026" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."usuarios_retirados" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "private"."vigia_alertas" ENABLE ROW LEVEL SECURITY;

GRANT USAGE ON SCHEMA "crm" TO "authenticated";

GRANT USAGE ON SCHEMA "crm" TO "service_role";

GRANT USAGE ON SCHEMA "crm" TO "crm_metricas_bridge";

GRANT USAGE ON SCHEMA "crm" TO "crm_gestion_diaria_lector";

GRANT USAGE ON SCHEMA "private" TO "authenticated";

GRANT USAGE ON SCHEMA "private" TO "service_role";

GRANT USAGE ON SCHEMA "private" TO "crm_metricas_bridge";

GRANT USAGE ON SCHEMA "private" TO "crm_gestion_diaria_lector";

GRANT SELECT ON TABLE "crm"."meta_periodos" TO "authenticated";

GRANT SELECT ON TABLE "crm"."meta_periodos" TO "service_role";

GRANT SELECT ON TABLE "crm"."sla_politicas" TO "authenticated";

GRANT SELECT ON TABLE "crm"."sla_politicas" TO "service_role";

GRANT SELECT,INSERT ON TABLE "crm"."tareas" TO "authenticated";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."tareas" TO "service_role";

GRANT UPDATE("vence_en") ON TABLE "crm"."tareas" TO "authenticated";

GRANT UPDATE("confirmada_en") ON TABLE "crm"."tareas" TO "authenticated";

GRANT SELECT("inversionista_id") ON TABLE "crm"."tareas" TO "authenticated";

GRANT SELECT("postventa_revision") ON TABLE "crm"."tareas" TO "authenticated";

GRANT SELECT("id") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("version") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("version_anterior_id") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("vigente_desde") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("cortes_activos") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("corte_1_hora") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("corte_1_minimo") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("corte_2_hora") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("corte_2_incremento_pct") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("corte_2_piso") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("corte_2_techo") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("sabado_minimo") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("bien_min_pct") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("atencion_min_pct") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("minimo_llamadas_utiles") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT("tasa_baja_diferencia_pp") ON TABLE "crm"."politica_gestion_diaria" TO "authenticated";

GRANT SELECT ON TABLE "crm"."politica_rentabilidad" TO "authenticated";

GRANT SELECT ON TABLE "crm"."politica_rentabilidad" TO "service_role";

GRANT SELECT,INSERT ON TABLE "crm"."alertas_reconocimientos" TO "authenticated";

GRANT SELECT,INSERT ON TABLE "crm"."actividades" TO "authenticated";

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "crm"."actividades" TO "service_role";

GRANT SELECT ON TABLE "crm"."actividades_cliente" TO "authenticated";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."agenda_ics" TO "authenticated";

GRANT SELECT ON TABLE "crm"."agenda_ics" TO "service_role";

GRANT SELECT ON TABLE "crm"."alertas_reconocimientos_vigentes" TO "authenticated";

GRANT SELECT ON TABLE "crm"."clientes_basicos" TO "authenticated";

GRANT SELECT ON TABLE "crm"."clientes_basicos" TO "service_role";

GRANT SELECT,INSERT ON TABLE "crm"."contrato_cuentas_pago" TO "service_role";

GRANT SELECT ON TABLE "crm"."contratos_cartera" TO "authenticated";

GRANT SELECT ON TABLE "crm"."contratos_cartera" TO "service_role";

GRANT SELECT ON TABLE "crm"."correcciones_correo_acceso" TO "authenticated";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."cuentas_bancarias" TO "service_role";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."enfriamiento_politica" TO "authenticated";

GRANT SELECT ON TABLE "crm"."equipo" TO "authenticated";

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "crm"."equipo" TO "service_role";

GRANT SELECT ON TABLE "crm"."gestion_diaria_control_avisos" TO "crm_gestion_diaria_lector";

GRANT SELECT ON TABLE "crm"."gestion_diaria_entregas" TO "crm_gestion_diaria_lector";

GRANT SELECT ON TABLE "crm"."lead_asignacion_sla_hitos" TO "service_role";

GRANT SELECT ON TABLE "crm"."lead_sla_ciclos" TO "service_role";

GRANT SELECT ON TABLE "crm"."lead_sla_etapas" TO "service_role";

GRANT SELECT ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "crm"."leads" TO "service_role";

GRANT UPDATE("id") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("nombre_completo") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("telefono") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("correo") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("dni") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("distrito") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("origen") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("etapa") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("motivo_descarte") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("monto_estimado") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("moneda") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("categoria_interes") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("vendedor_id") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("asignado_supervisor_id") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("perfil_id") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("contrato_id") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("convertido_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("nota") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("activo") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("creado_por"),UPDATE("creado_por") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("creado_por") ON TABLE "crm"."leads" TO "service_role";

GRANT UPDATE("creado_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("actualizado_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("ciclo_actual") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("genero"),UPDATE("genero") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("genero"),INSERT("genero"),UPDATE("genero") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("fecha_nacimiento"),UPDATE("fecha_nacimiento") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("fecha_nacimiento"),INSERT("fecha_nacimiento"),UPDATE("fecha_nacimiento") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("no_contactar"),UPDATE("no_contactar") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("no_contactar"),INSERT("no_contactar"),UPDATE("no_contactar") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("consentimiento_en"),UPDATE("consentimiento_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("consentimiento_en"),INSERT("consentimiento_en"),UPDATE("consentimiento_en") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("consentimiento_fuente"),UPDATE("consentimiento_fuente") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("consentimiento_fuente"),INSERT("consentimiento_fuente"),UPDATE("consentimiento_fuente") ON TABLE "crm"."leads" TO "service_role";

GRANT UPDATE("sla_global_iniciado_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("sla_global_aproximado") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("clasificacion_auto"),UPDATE("clasificacion_auto") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("clasificacion_auto"),INSERT("clasificacion_auto"),UPDATE("clasificacion_auto") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("descartado_en"),UPDATE("descartado_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("descartado_en"),INSERT("descartado_en"),UPDATE("descartado_en") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("descartado_por"),UPDATE("descartado_por") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("descartado_por"),INSERT("descartado_por"),UPDATE("descartado_por") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("tenencia_desde"),UPDATE("tenencia_desde") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("tenencia_desde") ON TABLE "crm"."leads" TO "service_role";

GRANT UPDATE("telefono_alternativo") ON TABLE "crm"."leads" TO "authenticated";

GRANT UPDATE("telefono_alternativo_crudo") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("alta_manual"),UPDATE("alta_manual") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("alta_manual") ON TABLE "crm"."leads" TO "service_role";

GRANT UPDATE("inversionista_id") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("reactivado_en"),UPDATE("reactivado_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("reactivado_en") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("enfriado_hasta"),UPDATE("enfriado_hasta") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("enfriado_hasta") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("proxima_llamada_en"),UPDATE("proxima_llamada_en") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT("proxima_llamada_en") ON TABLE "crm"."leads" TO "service_role";

GRANT SELECT("campania_origen") ON TABLE "crm"."leads" TO "authenticated";

GRANT SELECT ON TABLE "crm"."ledger_rentabilidad" TO "authenticated";

GRANT SELECT ON TABLE "crm"."ledger_rentabilidad" TO "service_role";

GRANT SELECT ON TABLE "crm"."metas_vendedor" TO "authenticated";

GRANT SELECT ON TABLE "crm"."metas_vendedor" TO "service_role";

GRANT SELECT ON TABLE "crm"."metas_vendedor_detalle" TO "authenticated";

GRANT SELECT ON TABLE "crm"."metas_vendedor_detalle" TO "service_role";

GRANT SELECT ON TABLE "crm"."objetivos_legacy_archivo" TO "service_role";

GRANT SELECT ON TABLE "crm"."objetivos_vendedores_legacy_archivo" TO "service_role";

GRANT SELECT ON TABLE "crm"."operaciones_cartera" TO "authenticated";

GRANT SELECT,UPDATE ON TABLE "crm"."politica_abandono" TO "authenticated";

GRANT SELECT ON TABLE "crm"."producto_condiciones" TO "authenticated";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."producto_condiciones" TO "service_role";

GRANT SELECT ON TABLE "crm"."producto_versiones" TO "authenticated";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."producto_versiones" TO "service_role";

GRANT SELECT ON TABLE "crm"."productos_inversion" TO "authenticated";

GRANT SELECT,INSERT,UPDATE ON TABLE "crm"."productos_inversion" TO "service_role";

GRANT SELECT ON TABLE "crm"."reasignaciones_analista" TO "authenticated";

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE "crm"."recordatorios_disponibilidad" TO "authenticated";

GRANT SELECT ON TABLE "crm"."rentabilidad_hitos" TO "authenticated";

GRANT SELECT ON TABLE "crm"."rentabilidad_hitos" TO "service_role";

GRANT SELECT ON TABLE "crm"."sla_politica_etapas" TO "authenticated";

GRANT SELECT ON TABLE "crm"."sla_politica_etapas" TO "service_role";

GRANT SELECT ON TABLE "crm"."solicitudes_tasa" TO "authenticated";

GRANT SELECT ON TABLE "crm"."solicitudes_tasa" TO "service_role";

GRANT SELECT ON TABLE "crm"."verificaciones_lead" TO "authenticated";
