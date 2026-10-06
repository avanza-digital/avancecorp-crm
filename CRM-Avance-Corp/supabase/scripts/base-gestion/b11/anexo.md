
## Qué cambió desde tu r1 (BLOCK) — respuesta del PRIMARY, punto por punto
- **[P1] El freno no excluía escritores → ACEPTADO.** Migración y reversa toman ahora, ANTES de su primera lectura,
  `lock table crm.lead_asignaciones, crm.conversion_acreditaciones in share row exclusive mode nowait` (transcrito arriba,
  en «Preflight» y en «Reversa»). Va suelto y no dentro de un DO porque un DO toma la instantánea antes de ejecutar su
  cuerpo. NOWAIT y no espera: la migración nunca espera con un candado tomado, así que no puede interbloquearse con un
  escritor que toque las dos tablas en otro orden ni dejar colgado a un usuario; si hay contienda, se niega y se repite.
  Esas dos tablas son las únicas que mira el freno; el origen de un lead no cambia tras el alta (trigger, P0409). Ensayo de
  dos sesiones en «Resultados medidos».
- **[P2] Pestaña con el bundle anterior + servidor nuevo + primer cierre de base → ACEPTADO como riesgo operativo, no se
  arregla en el servidor.** Un bundle ya cargado no se puede cambiar desde la base. Mitigación: (a) la pantalla nueva se
  publica antes; (b) el CRM consulta `version.json` cada 60 s y avisa «hay versión nueva»
  (`app/src/lib/version-publicada.ts`, componente `VersionPublicadaAviso` montado en `main.tsx`); (c) la migración se
  aplica después de dar tiempo a recargar (propuesta a Miguel: al día siguiente). Residual: quien ignore el aviso y abra el
  Divisor de coordinación tras el primer cierre de base verá esa tarjeta en error hasta recargar; no se altera ningún dato.
  Hoy hay 0 contactos de base en producción (medido el 05/10).
- **Riesgo «sellar un mes con cierres de base»: DECLARADO, fuera de B11.** `crm.cerrar_periodo` no se ensayó con un cierre
  de base: no hay meses sellados y el ciclo de cierre está en pausa por decisión de Miguel. El numerador sellado sale de
  private.conversion_cierres (que con B11 ya da 1 al cierre de base); la foto no guarda la base aparte y el Divisor de
  coordinación de ese mes mostrará «—» en Base (NULL, sin inventar un 0). Guardar la base en la foto es otro paso.
- **Heurística de llamadores por texto:** se queda como defensa adicional; no es la única (un llamador roto fallaría en su
  primera ejecución y el gate lo vería). La forma `private."conversion_divisor_empresa"(…)` no existe en el repo.
- También desde r1: auditor-rls r2 PASS; la reversa dice que conserva la fila del historial; fila del ledger escrita.

## Revisión interna previa (auditor-rls, 06/10): r1 CHANGES_REQUESTED sin P0/P1 → r2 PASS
- La reversa se niega si otra función nombra al ayudante, si hay un llamador nuevo del divisor de empresa, o si el censo
  analítico no está vigente y sellado; comprueba el candado de migraciones y prosecdef.
- Gate de RLS: bloque propio de B11 (catálogo + contrato) y la paridad del desglose suma `cierres.base_cargada ?? 0`.
