# Verificación y toma de lead libre

**Plan aprobado por Miguel el 2026-08-16** sobre la especificación
`CRM-Avance-Corp/docs/especificacion-funcional-verificacion-y-toma-lead-libre.md`.
Revisado por un panel de 6 lentes + 3 refutadores (que rompieron 4 afirmaciones del plan
original y un agujero que ya existe hoy: tomar un descartado-vencido crearía un DUPLICADO).
El documento `docs/propuesta-implementacion-anti-duplicado-alta-manual.md` queda **subsumido**
aquí (su umbral hardcodeado de 15 días se descarta: contradecía el modelo).

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
