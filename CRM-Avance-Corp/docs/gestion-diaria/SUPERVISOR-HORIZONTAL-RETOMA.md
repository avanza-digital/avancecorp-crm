# Gestión Diaria — punto de retoma del supervisor horizontal

**H4 cerrada y guardada el 23/09/2026. Siguiente etapa: H5.1.**
La pausa anterior terminó al iniciar el objetivo H4. No se ha iniciado H5.

## Estado y ubicación

- H1–H4 cerradas: 16 etapas y 48 de 72 tareas. H5–H6 pendientes.
- H2: `e6cc6c5b`. H3: `fa23ab5e`. Producto H4:
  `186e00f160f2e52ecfa89427a32d3227f30a0e1f`.
- Rama: `codex/gestion-diaria-supervisor-horizontal`.
- Copia de trabajo: `/private/tmp/avancecorp-release.hvdub4/repo`.
- Base Main: `cf87e8087bf61ea5c58669d924e801526a04c779`.
- El taller principal contiene trabajo ajeno; continuar en la copia aislada.
- Respaldo local incremental de producto, plan y evidencia:
  `/Users/usuario/.local/share/avancecorp-checkpoints/supervisor-horizontal-h4-2026-09-23.bundle`.
  Requiere la base indicada. Su JSON compañero identifica el commit final y
  la huella del bundle. Se conserva también el respaldo previo de H1–H3.
- Sin push, publicación ni instalación de la migración H3 en producción.

## Objetivo H4 cumplido

Integrar los cortes de llamadas y los avisos operativos en la vista horizontal
del supervisor para identificar qué requiere atención y actuar con menos
scroll. Estado real, «Lo estoy atendiendo», «Posponer 1 hora» y registro del
analista correcto; permisos/reglas conservados y avisos sin duplicados.

Franja de 44 px a 1512 × 805; detalle bajo demanda. Lista, campana y popup
comparten personas y seguimiento. Reintento conserva UUID; datos se separan
por actor/día. Ficha conserva contexto y otro destino limpia selección.
La fuente diaria refresca cortes/libro sin descargar todo el store.
H4 no añadió migraciones, RPC, políticas RLS ni dependencias.

## Evidencia y límites

- [Acta H4](SUPERVISOR-HORIZONTAL-H4-EVIDENCIA-2026-09-23.md),
  [JSON y huellas](SUPERVISOR-HORIZONTAL-H4-EVIDENCIA-2026-09-23.json),
  [revisión y resolución](SUPERVISOR-HORIZONTAL-H4-REVISION-2026-09-23.md).
- Gate final equivalente a `npm run check`: **4.272 pruebas / 287 archivos PASS**,
  cobertura con `--maxWorkers=2` después de un ERANGE del entorno al arrancar
  un worker. Lint, tipos, build y demás pasos PASS.
- E2E completo Docker local: **247 PASS / 0 fallos / 26 omitidas**, cero retries.
  Dirigido final: **14/14 PASS**. Primera corrida completa: 245/1/26, fallo
  intermitente de postventa; archivo repetido y suite final PASS sin modificarlo.
- Claude: **CHANGES_REQUESTED / MEDIUM**, una consulta; cuatro P2 y tres P3
  resueltos por Codex con pruebas. No se atribuye un PASS del reviewer.
- `gate:realidad`: NOT RUN, falta SUPABASE_URL. Lectores humanos, Safari,
  validación operativa/productiva y advisors hosted: NOT RUN en H4.

H3 conserva su banco local `gestion_diaria_h3_20260923`, contenedor
`supabase_db_avancecorp-f5-bank`, puerto 58322. El banco F4 original permanece
intacto. La migración H3 está versionada; no editarla al continuar.
Las pruebas de navegador H4 usan respuestas sintéticas, no actividad real.

## Secuencia para continuar

1. Leer este punto, el [plan canónico](GESTION-DIARIA.md), las actas H3/H4 y las
   reglas del proyecto. Comprobar rama, cambios locales y estado de Main.
2. **H5.1:** reunir la verificación de estados, filtros, orden, selección,
   pestañas, páginas y cambio de actor/día/permisos.
3. **H5.2:** completar recorridos de usuario en Docker local, sin E2E en GitHub.
4. **H5.3:** revisar densidad, nombres largos, 390 px, zoom/reflow y accesibilidad.
5. **H5.4:** cerrar calidad/rendimiento, informe y riesgos según el plan.
6. H6 conserva PR, integración con `avancecorp/main`, versión reproducible,
   publicación y aceptación. No publicar ni instalar SQL solo por esta nota.

## Figma y memoria

- [Mismo tablero: H4 completa](https://www.figma.com/board/9Pg7jMDRg3UVbb4XfeM80L?node-id=18-35).
- [Mapa del plan](FIGMA-PLAN.json): **48 completas / 24 pendientes**.
- 76 casillas históricas F0–F6 conservadas; capturas e inspección PASS.
- Vault: `Gestion Diaria - supervisor horizontal aprobado (2026-09-23).md`.
- F4 real mantiene sus pendientes del 24/09 y sábado 26/09; tasa baja OFF.
  El rediseño no cierra esa jornada ni activa TypeSafe/Jev.

Frase para retomar: **«Retomemos Gestión Diaria desde H5.1; H4 está cerrada en 186e00f1».**
