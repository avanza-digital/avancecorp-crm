---
tags: [crm, rendimiento, refactor, servidor]
fecha: 2026-09-29
---

# CRM — perfil de carga: lectura vs escritura (2026-09-29)

**Conclusión:** el CRM es un sistema **de lectura**. Se escribe poco (≈3.200 filas al día) y se lee
muchísimo (paneles, métricas, colas, fichas). Base para priorizar el refactor módulo por módulo
(ver [[Mapa de capas del servidor CRM]]).

## Cómo se midió
Solo lectura en producción (`supabase db query --linked`) sobre `pg_stat_user_tables` y
`pg_stat_statements`. Ventana: desde el último arranque de Postgres, **25/09 20:50 UTC → 29/09
21:45 UTC (~97 h, incluye fin de semana)**. Los contadores se reinician con cada arranque: la
cifra válida es la de hoy, no esta.

## Cifras (esquema `crm`, ~97 h)
- Filas escritas: 8.694 insert + 4.277 update + 8 delete = **12.979**.
- Filas leídas: **13.143 millones** → ~1.000.000 : 1. Sin la anomalía de abajo, ~50.000 : 1.
- Peticiones a la API (PostgREST, un `set_config` por petición, incluye portal): ~203.000.
- RPC del CRM declaradas `STABLE` (solo leen): 169.914 llamadas. Declaradas `VOLATILE`: 19.316,
  pero la mayoría también son lecturas (`postventa_agenda_fn`, `cartera_inversionistas_*_fn`,
  `*_ficha_fn`). Escrituras reales visibles: `registrar_llamada_v4` 598, `importar_lead_fn` 455,
  `repartir_lead` 202, `solicitud_inversion_fn` 203, `cerrar_tarea_v2` 118.
- Tablas más escritas: `actividades`, `sla_operacion_recibos`, `leads`, `cartera_lecturas`, `tareas`.

## Puntos calientes (candidatos de refactor)
1. 🔴 **`crm.inversionistas`**: 22,6 M lecturas completas de la tabla (~551 filas cada una) =
   12.462 M filas, **el 95 % de todo lo que lee el CRM**.
   **Causa medida (29/09, bloques `DO` de solo lectura que terminan en `raise`):**
   `private.cartera_f5_fuentes()` hace un `cross join lateral` por contrato con
   `where i.perfil_id = c.cliente_id`. El único índice de `perfil_id` es **parcial**
   (`inversionistas_perfil_uidx … where perfil_id is not null and estado <> 'fusionado'`) y esa
   consulta no repite la condición, así que no lo puede usar → **679 recorridos completos por llamada**
   (uno por contrato; 679 contratos), ~90 ms. La alcanzan 11 puertas (postventa_agenda/estado/ficha,
   cartera_inversionistas_estado, inversionista_ficha/gestion/cuentas, contexto_conversion_inversion,
   solicitud_inversion, acceso_inversion, preparar_persona_lead_inversion): 14.252 llamadas en la ventana,
   ~2 llamadas a fuentes por puerta ≈ los 22,6 M. En vivo: 26.509 recorridos en 77 s (~39 llamadas).
   Descartadas con medición: `inversionista_canonica` (1 índice, 0 recorridos) y
   `leads_vetados_persona` (2 recorridos para los 2.582 leads).
   **✅ ARREGLADO EN PROD 29/09 ~17:25 Lima** (migración `20260929220021_crm_indice_inversionistas_perfil`,
   lanzada por Miguel con `!`): índice normal `crm.inversionistas (perfil_id)`, sin tocar ninguna función.
   Verificado: `cartera_f5_fuentes` seq 679 → **0**, 91 → 49 ms, 719 filas idénticas; en vivo
   **545 → 0,8 recorridos/s**. Advisors: 242 avisos, ninguno del índice. Codex CHANGES_REQUESTED (P2
   registrador con relectura, P3 comentarios) aplicado. Sirve también a otras 18 funciones con el mismo
   patrón (`citas_gerencia_consulta`, `citas_testigo_mes`…). Reversa: `drop index crm.inversionistas_perfil_idx`.
   Segundo foco, aparte: `private.postventa_tarea_json` compara `inversionista_canonica(i.id)` contra
   toda la tabla por cada tarea (1 recorrido + ~1.061 índices por tarea); ahí un índice no sirve, hay que reescribirla.
2. `solicitudes_tasa_fn`: 88.328 llamadas (~15 por minuto): huele a sondeo repetido.
3. Las más caras en tiempo: `avisos_sla_resumen_v2_fn` (2.922 s, 0,32 s cada una) y
   `cumplimiento_metas_fn` (1.861 s).
4. `equipo` (2,97 M) y `cierres_externos` (1,46 M) también se recorren enteras; son pequeñas.
5. Funciones que solo leen marcadas `VOLATILE`: PostgREST las trata como escritura. Revisar una por
   una antes de cambiarlas: `cartera_lecturas` recibe inserts (1.213), puede ser un registro de
   lecturas hecho a propósito.
