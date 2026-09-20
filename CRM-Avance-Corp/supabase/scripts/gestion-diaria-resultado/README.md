# Gestión Diaria · Fase 2 — resultado tipificado de llamada

Estado: **ensayada en el banco local el 20/09/2026, pendiente de instalar en
producción DESPUÉS de la Fase 1 (`20260919211958`)**. Acta en
`../../migrations/MIGRACIONES.md`, entrada `20260920005000`. Plan completo en
`../../../docs/gestion-diaria/GESTION-DIARIA.md`.

## Qué entrega

- `crm.registrar_llamada_v3(p_operacion_id, p_lead_id, p_resultado, p_submotivo, p_detalle, p_siguiente, p_tarea_id, p_descartar, p_no_insista)`:
  registra la llamada con uno de siete resultados y sus efectos en una transacción
  (tarea siguiente, descarte con submotivo, «No insistir»). Idempotente por
  `p_operacion_id` (recibo del mundo SLA). Sobre `{ok, version:2, operacion_id,
  comando:'registrar_llamada', lead_id, actividad_id, siguiente_id, descartado,
  no_insista, resultado, intento_n, deshecho, etapa, replay}`.
- `crm.deshacer_resultado_llamada(p_actividad_id)`: deshace los EFECTOS (≤ 24 h,
  solo el autor): cancela la tarea creada y revierte el descarte si sigue vigente
  (compone sobre `crm.reabrir_lead_fn`: es una REAPERTURA, ciclo nuevo).
- CHECK de forma + trigger anti-falsificación sobre `crm.actividades.metadata`.
- `private.actividades_de_lead_core` con `metadata` por lista blanca.
- Gate paraguas `private.assert_gestion_diaria()` = F1 (`_registro`) + F2 (`_resultado`), 14 mutantes.

## Ensayo local

```bash
node supabase/scripts/gestion-diaria-resultado/ensayar.mjs [--historial <ruta 20260919185718>] [--fase1 <ruta 20260919211958>]
```

Crea la copia `gestion_diaria_f2_20260919` desde `conversion_inversion_base_20260919`
(como `supabase_admin`), instala si faltan el historial por lead y la Fase 1,
SELLA los md5 propios del gate en dos pasadas (placeholders `MD5_*_PENDIENTE_*`),
corre el gate, los mutantes (F2 y F1), el oráculo por actor
(`test-gestion-diaria-resultado.sql`: crea sus leads por `crm.crear_lead_si_disponible`
y termina en rollback), comprueba el censo intacto, registra una llamada REAL
(commit), ensaya `reversa.sql` y reinstala con esa metadata conservada. Escribe
`verificacion.json` y genera `../registrar-20260920005000.sql`.

## Publicación y reversa

1. Miguel instala F1 (`20260919211958`) y su registrador, si aún no están.
2. `!npx supabase db query --linked --file supabase/migrations/20260920005000_crm_gestion_diaria_resultado_llamada.sql`,
   luego `supabase/scripts/registrar-20260920005000.sql`, y anota el acta.
3. Front publicado después (RPC nueva: SQL primero).
4. Reversa: retirar el front y ejecutar `reversa.sql` (retira los objetos nuevos,
   devuelve el gate de F1 a su nombre y el núcleo del historial a su cuerpo del
   19/09; la metadata escrita se conserva y la reinstalación la admite).
