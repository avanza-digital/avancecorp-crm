# Observación previa a la retirada de Seguimiento

**Estado: iniciada, siete días todavía pendientes.** F5 quedó publicada y
verificada el **24/09/2026 a las 21:57:11 Lima** (`2026-09-25T02:57:11Z`).
[Acta y evidencia](f5-publicacion-2026-09-24/ACTA.md). La primera fecha posible
de retirada es **01/10/2026, 21:57:11 Lima**, si se acredita estabilidad y no
quedan incidencias relevantes abiertas. T0 no equivale a un día cumplido.

El inicio requiere anotar el commit y manifiesto del frontend servido, la
migración F5 instalada por merge de la rama ensayada y una comprobación viva
del tablero y sus cifras. El plazo mínimo son siete días reales desde ese
inicio, con los recorridos F3–F5 estables y sin incidencias relevantes abiertas.
La conformidad manual anterior de Miguel permanece cerrada; no se pide otra
sesión manual para iniciar esta observación técnica.

| Dato de inicio | Evidencia |
| --- | --- |
| Fecha/hora Lima de publicación verificada F5 | 24/09/2026, 21:57:11 |
| Commit y manifiesto del frontend | `b402a7f1b5c9789c1d592baa428f0bde8e1e9752`; `crm-20260925T023617Z-b402a7f1b5c9.manifest.json` |
| Migración y huella SQL productivas | `20260924201358`; `5f904c2b9b492b72fdb1ff1815aac2376d881939d6a8eaed938d1404380bf6b2` |
| Archivos servidos y recorrido autorizado | PASS: 78/78 HTML/JS/CSS, portada y recorrido de gerencia hasta ficha y regreso |
| Conciliación productiva con fuentes originales | PASS: hoy/ayer y hábitos de 7/14/30 días; agregados en el acta |

Durante la observación, registrar fecha/hora, versión servida, resultado de
consulta de un día y de hábitos, navegación a equipo/analista/registro y las
incidencias que aparezcan. Mantener los controles operativos de cortes en sus
horarios reales. Usar consultas de lectura; no crear datos reales ni reconocer
o aplazar avisos sólo para probar.

La [sonda de conciliación](../../supabase/scripts/gestion-diaria-f5/sonda-conciliacion.sql)
contrasta recuentos globales y tasas con actividades/tareas originales y el
cuadre de equipos en una sola sentencia. Informa sólo agregados. La fecha
consultada puede cambiar; los pendientes siempre corresponden al instante
actual. Esta sonda no sustituye las pruebas específicas de hábitos y permisos.

| Día de observación | Fecha/hora y versión | Evidencia e incidencias | Estado |
| --- | --- | --- | --- |
| T0 | 24/09 21:57:11 Lima; `b402a7f1` | SQL, cifras, hábitos, archivos y recorrido PASS; sin incidencia detectada en este control | PASS, inicio |
| 1 | 25/09 21:57:11 Lima, primer día completo | Pendiente de observación | NOT RUN |
| 2 | 26/09 21:57:11 Lima | Pendiente; corte único de sábado a las 11:30 por comprobar | NOT RUN |
| 3 | 27/09 21:57:11 Lima | Pendiente de observación | NOT RUN |
| 4 | 28/09 21:57:11 Lima | Pendiente de observación | NOT RUN |
| 5 | 29/09 21:57:11 Lima | Pendiente de observación | NOT RUN |
| 6 | 30/09 21:57:11 Lima | Pendiente de observación | NOT RUN |
| 7 | 01/10 21:57:11 Lima | Pendiente de observación y decisión de retirada | NOT RUN |

Las horas anteriores son hitos temporales, no tareas programadas. No existe
vigilancia automática garantizada; cada control debe tener una ejecución y
evidencia reales. Miguel conserva cerrada su conformidad y reportará incidencias.

Una incidencia relevante impide cerrar por el mero paso del calendario:
corregir, verificar y acreditar el período estable antes de retirar Seguimiento.
La equivalencia de cola, permisos, acciones y enlaces debe probarse también,
según [PREPARACION-F6-2026-09-24.md](PREPARACION-F6-2026-09-24.md).
