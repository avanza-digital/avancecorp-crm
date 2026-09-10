# F6 — evidencia del 10/09/2026

**Actualización: publicada e instalada OFF el 10/09/2026.**
La matriz siguiente conserva la evidencia local inicial. Para los resultados
vigentes —43 pruebas remotas, 3.182 frontend, matriz general FAIL sin regresiones
y observación Auth— consultar [el acta productiva](PUBLICACION-2026-09-10.md).
No interpretar los NOT RUN iniciales de servidor/publicación como estado actual.

## Evidencia local inicial, anterior a la publicación
No se declara terminado el plan F1–F9 ni se enciende el circuito económico.

| Control | Resultado | Evidencia |
|---|---|---|
| Servidor F6 real, banco sintético | PASS, 41 pruebas | Cinco archivos `*.test.mjs`: agenda, permisos, veto, retiro, reinversión, integridad y carreras |
| Regresión F5 sobre el banco con F6 | PASS, 46 pruebas | `../f5/verificar-banco.mjs`, nueve grupos |
| Reconstrucción del archivo exacto | PASS | `replay-local.mjs`, copia descartable del banco |
| Conservación de funciones y permisos | PASS local | 564 funciones previas; solo seis cuerpos extendidos, ACL y propietarios conservados |
| Instalación y reversa sin cambios de datos previos | PASS local | Huellas de once tablas de negocio, identidad y Auth; tareas anteriores comparadas sin las dos columnas nuevas |
| Banderas y contexto interno | PASS | Banderas previas conservadas, F6 nace OFF, historial/contexto nuevos vacíos |
| D-19 | PASS, cero referencias sin candado | Consulta sobre funciones del banco tras replay |
| Compatibilidad de las seis bases productivas | PASS, lectura del 10/09 | `base-productiva-2026-09-10.json`; no se escribió producción |
| Tipos | PASS, 18 nodos | Introspección local + `integrar-tipos.mjs --verificar` |
| Gate frontend integral | PASS | `npm run check`: lint, typecheck, 3.180 pruebas en 225 archivos, cobertura, configuración, build, bundle y duplicación |
| Navegación completa | PASS, 159; 26 omitidas | Playwright completo; las omisiones existentes no cuentan como aprobadas |
| Recorridos nuevos F6 | PASS, 7 | `app/e2e/f6-postventa.spec.ts`, escritorio/móvil/roles y recuperación |
| Preflights backend | PASS | `check:scripts`, `seed:preflight`, `test:rls:preflight`, `test:edge-preflight` |
| Matriz RLS general completa con F6 | NOT RUN | Se ejecutaron matrices pertinentes F6/F5. La línea base general anterior tiene 65 fallos abiertos; no se declara PASS global |
| Branch remoto/advisors F6 | NOT RUN | Pendiente del carril de instalación autorizado; no confundir con el branch F5 ya cerrado |
| Instalación/activación F6 productiva | NOT RUN | F6 permanece local, sin SQL o encendido productivos |
| Aceptación humana F6 / G6–G8 | Pendiente | No se hereda la aprobación manual de F5; faltan F7, piloto y ciclo mensual |

El lint conserva cuatro advertencias previas de accesibilidad en coverflow;
ninguna nueva. Los primeros ensayos detectaron errores reales de integración:
filtro de Agenda que excluía la persona, baja con barrido de tareas heredadas,
lectura ICS sin JWT, restricciones NULL y bloqueo de una lectura GET. Se
corrigieron y los gates citados se ejecutaron después. Dos fixtures antiguos
no conocían el endpoint F6 apagado; se actualizaron sin relajar sus aserciones.

## Propiedades comprobadas

- JWT/ámbito vigente, baja y cambios de responsable, Gerencia/cola y exclusión de
  Directorio, Cliente, anónimo y service_role de las escrituras F6.
- DML neutral bloqueado incluso desde funciones antiguas con una GUC falsificada;
  ningún rol API puede crear el contexto interno que autoriza la escritura.
- Una clave y contenido por operación, revisión de tarea/retiro, close+next atómico,
  cambio de cuenta rechazado, respuesta perdida recuperada sin duplicación.
- Cruces modo/persona/tarea/fuente terminan en conflicto reintentable; no dejan
  tareas, solicitudes ni recibos parciales. Cierre/veto/reasignación coherentes.
- Fusión mantiene sujeto histórico y resuelve la persona canónica; las tareas y
  el calendario siguen al responsable actual. Veto incluye equivalencias antiguas.
- Retiro administrativo deja idénticas cinco fuentes financieras. Reinversión
  conserva origen/empresa/persona y delega en F4; un depósito repetido se rechaza.
- F6 ausente o apagada conserva el comportamiento anterior; apagarla mantiene
  accesible únicamente el estado mínimo del recibo propio para recuperar un envío.

Los logs completos y el dump sintético se guardan fuera del repositorio en el
respaldo de CARTERA. El manifiesto y las capturas seleccionadas son evidencia
sin credenciales. Véase [README](README.md) para repetir los controles.
