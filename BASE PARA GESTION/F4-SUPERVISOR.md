# F4 · Vista del supervisor — plan y contrato (03/10 noche)

## Decisiones de Miguel (03/10)
1. **Vetados:** en la lista de la base con interruptor «Ver no contactar», SOLO supervisor y gerencia (opción a).
2. **Ubicación:** pestañas en «Base para gestión»: «Descartes del mes» (el Centro de rescate actual, INTACTO) y
   «Gestión de la base» (nuevo). Al entrar abre «Descartes del mes».
3. **Todo número se abre:** «Intentos de hoy» y «Reactivaciones del mes» del panel por analista se abren (lectura de
   detalle nueva en la misma migración).
4. **Vetados completos:** marca + cuándo + motivo + quién; también los que están en descanso. Analista que los pida → 42501.
5. **Ficha del supervisor:** consulta + «Quitar No contactar» (D5). No registra intentos ni reactiva; repartir sigue en
   «Descartes del mes».
6. Gerencia (~1069 filas): una carga, filtros en el navegador, páginas de 50 (por defecto).

## Contrato servidor ↔ pantalla (migración B6b; nombre: B5 ya es la del mes y B7+ es «Bases cargadas»)
- `crm.obtener_base_gestion(p_vendedor_id uuid default null, p_incluir_vetados boolean default false)` — drop + create
  sobre el texto vivo de B5 (`20261003162400`). Salida: las columnas de hoy + al final `no_contactar boolean`,
  `no_contactar_en timestamptz`, `no_contactar_motivo text`, `no_contactar_por text` (de la última actividad del lead con
  `evento='no_contactar'`, `accion='marcar'`; NULL si la marca vino de otro lead de la persona). `p_incluir_vetados=true`
  con rol que no sea supervisor/gerencia → 42501. `null` = `false`. Vetados al final; nunca en «Llamar hoy»
  (`rellamada_hoy=false` si `no_contactar`). Con `true` también se listan los vetados en descanso.
- `crm.base_gestion_resumen_detalle(p_vendedor_id uuid, p_cifra text)` — `p_cifra in ('intentos_hoy','reactivaciones_mes')`;
  salida `(lead_id uuid, nombre_completo text, en timestamptz, detalle text, autor text, sigue_en_base boolean)`, mismo
  ámbito y rol que `base_gestion_resumen` (analista → 42501; supervisor fuera de su ámbito → P0002), mismas definiciones
  que las cifras del resumen (intentos de hoy en Lima atribuidos al dueño actual; `reactivacion_base` del mes en Lima).
  Orden: más reciente primero.
- Ambas: `security definer`, `search_path ''`, sin `count(`/`sum(1)` (censo analítico), `revoke … from public, anon,
  authenticated, service_role` + `grant execute … to authenticated`, `COMMENT ON`, `notify pgrst`. Pre/postflight con md5 y
  ACL; reversa en `supabase/scripts/base-gestion/reversa-b6b.sql`; registrador en `supabase/scripts/base-gestion/registrar/`.
- Ciclo: banco Docker → `auditor-rls` → Codex LEVEL 3 → rama con datos → gate `test-rls.mjs` → advisors → Miguel aplica con
  `!` + registrador → ledger → tipos.

## Pantalla (rama `crm/base-gestion-f4` sobre el vivo `82cac826`)
1. Datos: `baseGestionResumen`, `baseGestionResumenDetalle`, `levantarNoContactar`, `incluirVetados` + campos opcionales
   `no_contactar*`; si el servidor responde **PGRST202** (B6b aún no aplicada) se reintenta sin el parámetro y el
   interruptor/las cifras no se abren (molde de `recibido_en`).
2. `HojaBase` extraída de `screens/rescate/analista.tsx` (columna «Gestiona» opcional); dimensión de filtro `analista`.
3. `screens/rescate/supervision.tsx` con pestañas; `RescateDescartados` sin tocar.
4. «Gestión de la base»: panel por analista (En base · Para llamar hoy · Intentos de hoy · Reactivaciones del mes, todo se
   abre), hoja con «Gestiona», filtro Analista, páginas de 50, interruptor «Ver no contactar» (bloque al final).
5. Ficha según el rol: consulta + «Quitar No contactar» (motivo ≥ 5; avisa que se levanta para la persona y todos sus
   leads).
6. `revisor-a11y`, `npm run check`, E2E Docker, Codex LEVEL 2 de F3–F4.

## Revisiones de B6b (03–04/10)
- **Codex r1: BLOCK** (1 P2): la foto de `$foto$` y el `$postflight$` no comparten instantánea bajo READ COMMITTED; un
  intento o una reactivación concurrente revierte una migración correcta (falla cerrada, sin fuga). Arreglo:
  `REPEATABLE READ` al empezar + caso concurrente reproducido en el banco.
- **auditor-rls: CHANGES_REQUESTED** (sin P0/P1): P2a marca desfasada entre leads de la misma persona (marcar/levantar
  escriben la actividad solo en un lead) → ancla con `inversionistas.no_contactar_en`; P2b la nota del veto es
  falsificable por `actividades_insert`; P3 motivo de postventa, casos del gate (miembro desactivado, bandeja, retirado
  en reactivaciones), comentario.
- **Decisión de Miguel (04/10) sobre P2b:** B6b sale con el riesgo escrito y **justo después una migración pequeña
  (B6c) reserva `metadata.evento='no_contactar'` para las puertas oficiales** (mover el `set_config(..,'off')` de
  `levantar_no_contactar` detrás de su insert), con su propio ciclo.
