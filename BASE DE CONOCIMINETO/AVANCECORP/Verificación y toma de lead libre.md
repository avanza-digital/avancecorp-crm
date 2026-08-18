# Verificación y toma de lead libre

**Plan aprobado por Miguel el 2026-08-16** sobre la especificación
`CRM-Avance-Corp/docs/especificacion-funcional-verificacion-y-toma-lead-libre.md`.
Revisado por un panel de 6 lentes + 3 refutadores (que rompieron 4 afirmaciones del plan
original y un agujero que ya existe hoy: tomar un descartado-vencido crearía un DUPLICADO).
El documento `docs/propuesta-implementacion-anti-duplicado-alta-manual.md` queda **subsumido**
aquí (su umbral hardcodeado de 15 días se descarta: contradecía el modelo).

## Estado de ejecución (2026-08-17)

- ✅ **F1 «Verificar» EN PRODUCCIÓN COMPLETA** — front (28.º release
  `crm-20260817T151109Z-42f02cbdc1ca` + 29.º `crm-20260817T160102Z-cbc95900091f`,
  la honestidad del precheck que pidió Miguel) y servidor (migración
  `20260816221500`, aplicada y registrada, índice 100).
- ✅ **F2 «Tomar» COMPLETA EN PRODUCCIÓN — servidor Y front.**
  Servidor (17/08, migración `20260817164745`): RPC `crm.tomar_lead_libre`
  por contacto + split libre/`reutilizable` + válvula `crm.toma_directa`.
  Doble auditoría (auditor-rls y Codex), oráculo 16✓ con carreras dblink,
  6 mutantes, gate del branch 304✓, registro al byte, advisors 123/0. Ciclo
  en `supabase/migrations/MIGRACIONES.md` (adendas 17/08 a 17/08-e).
  Front (18/08, **30.º release** `crm-20260818T044028Z-2bbedf6314f3`, commit
  `ed15fa6`, vivo AL BYTE): contrato estricto de `reutilizable` + tarjeta
  «Seguimiento anterior disponible» (sin quién descartó, §8) + capacidad
  `tomarLeadDirecto` (solo vendedor) + api `tomarLeadLibre` sin fail-open +
  botón con los tres desenlaces DICHOS (ganar resincroniza antes de abrir la
  ficha; perder recibe el veredicto fresco §5.7; error reintenable). Doble
  auditoría del front: revisor-a11y (4 aplicadas — contraste 7,1:1, el
  desenlace «libre» ya no es mudo, rescate de foco, aria-describedby) y
  Codex 3/6 reales corregidas (formulario congelado con la toma en vuelo;
  Cancelar muere mientras la RPC viaja — el servidor puede COMPROMETER la
  toma; resincronización fallida se dice sin ficha vacía). 7 mutantes (6
  muertos, 1 enmascarado por estructura, documentado). Gate 1.988/1.988.
  Registro del deploy en [[Deploy a Hostinger]].
- ✅ **F3 «Recordar» COMPLETA en producción, servidor y front (18/08).**
  Servidor (madrugada): `crm.recordatorios_disponibilidad` (UNIQUE
  perfil+teléfono, sellado con auth.uid, futuro ≤365d, RLS dueño-only solo
  vendedor con la excepción DELETE documentada), caducidad `>7 días vencido`
  con cron 17:06 UTC, y el CHECK `isfinite` en `crm.actividades` — la deuda
  de finitud SALDADA. Registro 103, advisors 129/0, ciclo en MIGRACIONES.md
  (adendas 18/08). Front (**31.º release**
  `crm-20260818T153614Z-1a8a51fb3c03`, commit `1a8a51f`, vivo AL BYTE):
  mini-form «¿Quieres que te lo recuerde?» sobre ocupados sin puerta, campana
  «Revisar contacto» solo-vencidos con Verificar (el circuito F1/F2 entero) y
  Quitar. Doble dictamen aplicado: a11y A1/M1–M4/N1–N3 y Codex R2–R6, 9/9
  mutantes muertos, gate 2.023/2.023. Registro en [[Deploy a Hostinger]].
- ✅ **F3.1 (18/08 tarde): la auditoría doble del F3 aplicada entera** — 7
  lentes propios + Codex refutador sobre el commit `1a8a51f`; 6 medios + 4
  huecos de test + menores corregidos (campana con error visible y Reintentar
  real; fecha vaciada avisa; estado del recordatorio ANCLADO al teléfono —
  ni blur sin editar ni el DNI lo borran; candado por contacto a nivel de
  módulo; foco decidido por la REALIDAD del dato con fallback al encabezado;
  dni explícito en el upsert — sin DNI = limpiar; sugerida acotada al máximo;
  min/max con reloj vivo; la campana ya no pide el dni). 14/14 mutantes,
  gate 2.053/2.053. La caza destapó 2 trampas de jsdom (blur y body.focus
  son no-op) y un bug real (focus sobre disabled — rescate vía efecto).
- 📌 **Decisiones selladas de F3.1 (Miguel, 18/08):** (1) la campana suena a
  las 09:00 del día aunque la liberación real sea por la tarde — ACEPTADO: el
  botón «Verificar» siempre da el veredicto real; (2) el toast de éxito
  muestra el teléfono completo unos segundos en la pantalla del propio
  dueño — ACEPTADO (dato del dueño de la sesión).
- 🔴 **Deuda F4 (decisión pospuesta por Miguel):** al caducar un recordatorio,
  `private.caducar_recordatorios_disponibilidad()` copia teléfono+DNI a
  `public.audit_log` (lado portal, sin retención). Decidir en F4: auditar sin
  PII (migración corta) o documentar la retención.
- ⏳ Pruebas visuales de Miguel (F1+F2+F3 juntas; ⚠️ `crm.leads` está VACÍA
  en prod — sembrar o esperar lead real; local: `npm run dev` en app/).
- ⏳ F4 «Alerta» → F5 «Perilla». Deuda viva para F4+: valorar quitar
  `descartado_por` de los payloads de verificación si ninguna fase lo pintará.

## El modelo («C+ · híbrida con toma directa»)

1. **La inactividad NO libera sola** — dispara alerta al supervisor «reencola o confirma».
2. **Cuando el lead está libre** (en bolsa, o enfriamiento vencido) **el vendedor que
   verifica lo toma directo**: gana el primero; el árbitro es el protocolo de candados
   (NO el índice del ledger — ver «lo que estaba mal»).
3. **La puerta de toma vive SOLO tras la verificación por contacto** (teléfono/DNI): no hay
   vitrina de la bolsa; el reparto del coordinador queda intacto.
4. **Perilla**: alerta X días ignorada y sin conversación real → a la bolsa sola, con
   arranque suave (no retroactivo el día del encendido).

## Decisiones de Miguel (2026-08-16, registradas)

| Decisión | Elección |
|---|---|
| Destino del reencolado del supervisor | **Bolsa del coordinador** (vía auditada nueva: hoy el guard reserva la cola global a gerencia) |
| Capacidad en la toma directa | **Libre, con aviso** al superar el objetivo (hoy nadie impone tope, ni el reparto) |
| Qué protege al dueño | **VARIANTE DURA: solo conversaciones reales** (los intentos NO renuevan; el desglose «intentos vs conversaciones» se muestra al supervisor) — y en coherencia, **«confirmar seguimiento» tampoco detiene la perilla**: solo hablar con el cliente la detiene |
| Descartados con 0 días (pide_credito, datos_invalidos) | **Carencia de 24 h solo para TOMAR** (protege el «Deshacer descarte 24h» del coordinador; el alta manual no cambia) |
| Umbrales iniciales (defaults míos, editables por gerencia) | **Y = 7 días** de abandono (unifica el 5 del servidor y el 7 del cliente) · **X = 7 días** de perilla |

⚠️ **Todo reloj de abandono arranca en `greatest(última conversación real, tenencia_desde)`**
— la regla de Miguel «la espera se mide ante su dueño actual». Sin esto, la perilla le
quitaría en horas un lead a quien lo acaba de recibir (bloqueante cazado por el refutador).
Con la variante dura, «conversación real» = TIPOS_CONVERSACION (≠ TIPOS_CONTACTO — la regla
del [[RETOMAR-27]] ya lo separa).

## Lo que estaba mal en el plan original (evidencia verificada)

- **«El candado del ledger arbitra la carrera» — FALSO**: ante un segundo UPDATE de
  vendedor, el trigger cierra el episodio del ganador como `transferido` y abre otro SIN
  error (`20260717212639:670-765`) — el segundo tomador robaría el lead en silencio. El
  árbitro es: advisory locks por contacto + SELECT FOR UPDATE + **UPDATE con CAS** +
  re-verificación dentro (patrón ya pagado en `repartir_lead` y la creación atómica).
- **El ledger veta asientos directos** (`ledger_writer` + `pg_trigger_depth`,
  `20260717212639:530-533`): se mueve el lead y la cascada asienta.
- **El supervisor NO puede reencolar a cola global**: `trg_leads_guard_tenencia` lo
  reserva a gerencia (`20260803164348:537-550`); hace falta flag de sesión (patrón
  `crm.cancela_sistema`, `20260809024942:163-167`) re-auditado.
- **Un trigger no dispara por tiempo**: la perilla es **pg_cron** (patrón del cierre de
  mes `20260815102000:884-898`), corre con `auth.uid()` NULL → pasa el guard limpio.
- **«Libre» no distingue al reutilizable**: el descartado-vencido cae al `libre` genérico
  y el alta haría INSERT nuevo (`20260804165440:566-610`; los índices de dedup solo cubren
  vivos) → duplicado violando §5.6. Se parte en `libre` / `reutilizable`.

## Las 5 fases (orden nuevo: Tomar antes que Recordar)

1. **Verificar** — tarjeta honesta (quién lo atiende, última conversación; fecha SOLO
   donde hay regla real: enfriamiento). Nace `crm.politica_abandono` (Y+X, gerencia) y
   `crm.verificaciones_lead` (log anti-pesca, SELECT solo gerencia; la RPC pasa a
   volatile). **Front PRIMERO** (contrato estricto `v.strictObject` — la lección del
   15-ago), con claves nuevas `v.optional` y la variante `reutilizable` tolerante desde ya.
   UI: cero pantallas nuevas — tarjeta en el precheck del alta + atajo en el vacío del
   buscador del topbar, tras `funcionesLeadsVisibles`.
2. **Tomar** — RPC `tomar_lead_libre(p_telefono, p_dni)` POR CONTACTO (jamás lead_id:
   mata TOCTOU y no filtra UUIDs). Protocolo gemelo del alta con **mismo ORDEN de
   candados que los caminos vivos** (fila↔advisory: invertirlo = abrazo mortal con
   «Deshacer descarte», cazado por el refutador). Bolsa: CAS `vendedor IS NULL AND
   supervisor IS NULL AND activo`; reutilizable: CAS `etapa='descartado' AND activo` con
   etapa→'nuevo' y vendedor en el MISMO update (el guard sube ciclo solo; tenencia
   renace sola). 0 filas → veredicto fresco presentado como `tomado_por_otro`.
   Convertido sin perfil de portal NO es reabrible → alta nueva. Traza §9: actividad con
   metadata `{propietario_anterior, ultima_conversacion, quedo_libre_en,
   motivo:'liberacion_por_inactividad'}`. Banco SQL a DOS sesiones + mutantes (quitar CAS
   o advisory → deben morir). `activo=false` NUNCA es reutilizable (cae a libre → crear).
3. **Recordar** — tabla `crm.recordatorios_disponibilidad` anclada AL CONTACTO tecleado
   (teléfono normalizado + DNI), **SIN FK a leads** (no ser el 8.º candado de la
   limpieza). RLS owner-only con DELETE propio (excepción documentada a la convención:
   la spec exige eliminar). NO es `crm.tareas` (candado lead-visible + contaminaría
   agenda). Campana: tipo de alerta nuevo derivado en cliente; re-verificación BAJO
   DEMANDA al clic (nunca N llamadas al abrir). Los vencidos no atendidos **caducan
   solos** (minimización de datos). Módulo con nombre distinto de `lib/recordatorio.ts`
   (ese es el anti no-show).
4. **Alerta de abandono** — tabla `crm.abandono_alertas` (FK ON DELETE CASCADE SIN
   guard) + **el detector diario nace AQUÍ** (pg_cron; era el hueco: nadie escribía
   `detectado_en`, el reloj de la perilla). Reloj: conversaciones reales + Y, ante el
   dueño actual. Reencolar = CAS «solo si el dueño sigue siendo el de la alerta» (el
   UPDATE de reasignar hoy no tiene CAS y pisaría una toma en vuelo). La fecha estimada
   de los TOMADOS aparece en la tarjeta recién en esta fase (antes sería una promesa sin
   motor — «dos relojes», cazado por el refutador).
5. **La perilla** — barrido en el job: CAS `dueño = el de la alerta AND sin conversación
   posterior a detectado_en AND detectado_en + X < now()` → 0 filas = pierde limpio.
   La cascada existente cancela citas y retrocede etapa; autoría firmada como sistema
   (sin el flag, el timeline diría que el CREADOR del lead lo devolvió). Verificar el
   deploy contando el job en `cron.job`.

Cada fase: branch de Supabase → gate RLS → advisors → auditor-rls + Codex → releases con
front/servidor en el orden que manda la dirección del cambio.

Relacionadas: [[Limpieza controlada del dataset CRM]] · [[Deploy a Hostinger]] ·
[[Carga de leads desde hoja de Google]]
