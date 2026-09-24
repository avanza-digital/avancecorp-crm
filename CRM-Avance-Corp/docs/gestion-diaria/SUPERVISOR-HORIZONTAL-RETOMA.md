# Gestión Diaria — punto de retoma del supervisor horizontal

**Guardado el 23/09/2026 por petición de Miguel: «guarda todo y seguimos en unas horas».**
El trabajo queda detenido hasta que el usuario lo retome. H4 tiene el plan
aprobado y sigue sin implementar; no avanzar sus casillas por esta aprobación.

## Estado y ubicación

- H1–H3 cerradas: 12 etapas y 36 de 72 tareas. H4–H6 pendientes.
- H2: commit `e6cc6c5b`. H3: commit `fa23ab5e`.
- Rama: `codex/gestion-diaria-supervisor-horizontal`.
- Copia de trabajo: `/private/tmp/avancecorp-release.hvdub4/repo`.
- Base Main verificada al iniciar: `cf87e8087bf61ea5c58669d924e801526a04c779`.
- El taller principal contiene trabajo ajeno; continuar en la copia aislada.
- Respaldo local de los commits posteriores a esa base:
  `/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-2026-09-23.bundle`.
  Este bundle incremental requiere que el repositorio de destino tenga la base indicada.
- Sin push, publicación ni instalación de la migración H3 en producción.

## Objetivo aprobado para H4

Integrar los cortes de llamadas y los avisos operativos en la vista horizontal
del supervisor, manteniendo un resumen compacto y acceso al detalle cuando lo
necesite. Cada aviso debe mostrar su estado real, permitir las acciones de
seguimiento existentes y abrir el registro del analista correcto. Conservar
permisos, horarios y restricciones actuales, evitar notificaciones duplicadas
y verificar los recorridos con pruebas locales. Actualizar Figma, el plan y
la memoria del proyecto con la evidencia de cierre.

## Secuencia de retoma

1. Leer este punto de retoma, el [plan canónico](GESTION-DIARIA.md) y la
   [evidencia H3](SUPERVISOR-HORIZONTAL-H3-EVIDENCIA-2026-09-23.md). Comprobar
   rama y estado de la copia; no sobrescribir cambios de otras sesiones.
2. **H4.1:** compactar el estado real de los cortes en una franja, con cifras
   y personas bajo demanda; distinguir programado, evaluado, desactivado,
   no laborable y error según política y día Lima.
3. **H4.2:** conservar «Lo estoy atendiendo» y «Posponer 1 hora»; mostrar
   espera, confirmación y fallo, sin reiniciar estados ni provocar reavisos.
4. **H4.3:** aviso → analista correcto → Registro → Llamadas; reutilizar
   campana/popup, acceso por lista y protección contra duplicados.
5. **H4.4:** integrar otros avisos y su navegación; ficha superpuesta conserva
   contexto, otra vista cierra selección local; comprobar sincronización y permisos.

H4 reutiliza las consultas y acciones existentes; no prevé una migración nueva.
Las cuatro etapas y doce tareas permanecen pendientes hasta tener evidencia.
Su cierre llevaría el avance a 48/72; H5 conserva la verificación integral y
H6 la entrega, publicación y aceptación operativa.

## Evidencia conservada y límites

H3: `npm run check` PASS, 4.244 pruebas; E2E completo en Docker local 241 PASS,
0 fallos y 26 omitidas; dirigido final 14/14 y capturas 4/4. Claude PASS con
confianza MEDIUM. SQL/RLS y HTTP real: 1.008 tareas, 11 páginas, paridad,
revocación, reversa/replay y tipos verificados. Capturas y logs en el acta H3.

Banco SQL local H3: `gestion_diaria_h3_20260923`, contenedor
`supabase_db_avancecorp-f5-bank`, puerto 58322. El banco F4 original permanece
intacto; el banco y contenedor HTTP temporales propios ya se retiraron.
La migración H3 está versionada: no editarla en H4.

Gate de realidad, matriz general remota/advisors hosted y lectores humanos
NVDA/VoiceOver: NOT RUN, con motivos en el acta. No atribuirles PASS.
Los E2E siguen ejecutándose únicamente en Docker local.

## Figma y memoria

- [Mismo tablero, H4](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-35).
- [Mapa de nodos y avance](FIGMA-PLAN.json): 36/72 completas; H4 pendiente.
- Vault: `Gestion Diaria - supervisor horizontal aprobado (2026-09-23).md`.
- Las 76 casillas históricas F0–F6 se conservan. La jornada real de F4 y su
  seguimiento son independientes del rediseño; tasa baja sigue OFF.

Frase para retomar: **«Retomemos Gestión Diaria desde H4.1; el plan de H4 está aprobado».**
