# Llamadas desde el celular — F4.2.4 aceptada y macros de C1 exportadas (2026-10-12)

Sesión de Jhosep del lunes 12/10/2026. Sigue a [[Llamadas desde el celular - auditoria de fases y pruebas S1-S3 (2026-10-09)]].
Evidencia: `CRM-Avance-Corp/docs/gestion-diaria/piloto-telefonia/REGISTRO.md` §5k. Tablero: cambios 213–231.

## Qué quedó hecho

- **El #251 ya estaba en producción**: el agente de Miguel lo aprobó, fusionó (`7b0d0716`) y publicó el 10/10 por la
  noche; el #253 devolvió a `main` el historial del release. Trae el botón **«Unir a un resultado guardado»** (F4.2.4).
- **F4.2.4 aceptada en C1** (un caso, contra producción): llamada sin resultado → «No contestó» guardado desde la PC
  sin el id de la llamada → en «Celular» → «Pendientes» → «Unir a un resultado guardado» → un solo candidato →
  «Llamada está unida». Comprobado en la base en solo lectura: vía `manual`, un enlace, ninguna pendiente.
  **48/102 tareas, subfase F4.2 cerrada.**
- **Investigación de los límites de la unión a mano** cerrada: I-1 a I-3 por el agente de Miguel en banco (el nuevo
  dueño **sí** puede unir a mano, dentro del ámbito; el reloj adelantado >10 min la rechaza; el supervisor no tiene la
  pestaña aunque la puerta lo permita) e **I-5** por nuestra sesión en un banco desechable con las doce migraciones (en
  un lead descartado el panel puede ofrecer un resultado que ya es de la llamada de otra persona; la base rechaza con
  23505; sin daño). Todo en `SOPORTE.md` §2 y §2.2 (corregido: antes decía que el nuevo dueño no podía unir).
- **Macros de C1 exportadas** por el camino A de `ACTIVAR-C2.md`: tres archivos `.macro` (uno por macro, JSON con las
  variables globales **y su valor** → vaciar `numero_saliente` y `clave_celular` antes es obligatorio), revisados con un
  script que solo cuenta y nunca muestra valores: limpios. C1 volvió a funcionar con su **misma** clave (no hizo falta
  rotar). C2 y C3: ~10 min cada uno importando.
- **MacroDroid de C1 renovado** (10:22 Lima). Próximo: **15/10**. Pro corporativo hasta S/ 57 autorizado por Miguel;
  Jhosep sigue con la versión gratis.

## Decisiones de Miguel (#251, 6128409126)

- **OK explícito a la sección 9 de `F4E-CONTRATO.md`**: se puede preparar la migración de F4-e (plan corto con OK de
  Jhosep primero; revisiones y checks del contrato antes de aplicar o publicar).
- **Aviso de tratamiento resuelto**: Legal lo aprobó y tramitó; no se incorpora al sistema. C2 y C3 sin frenos.

## Hallazgos (vistos una vez, sin pérdida de datos)

- **H-BLANCO**: la app del celular quedó en blanco al abrir el enlace de la llamada. Hipótesis de Jhosep respaldada
  por el código (no reproducida): la app llevaba abierta desde antes de la publicación del 11/10. El receptor del
  enlace está fuera de la protección por pantalla y la app no tiene protección general; el aviso de versión nueva calla
  el error de carga. Propuesta para Miguel: protección general que ofrezca «actualizar». Para analistas: cerrar la app
  del todo y abrirla; la llamada queda en «Pendientes».
- **H-GUARDANDO**: la PC se quedó en «Guardando…» con el resultado ya guardado una sola vez; la protección de
  «Guardados por confirmar» funcionó. Causa no determinada.

## Propuestas nuevas (`PROPUESTAS-DE-AJUSTE.md`)

- **#19 Llamadas largas**: la hora de la llamada es la de colgar y la unión a mano acepta resultados desde 10 min
  antes; un resultado guardado en la PC a mitad de una llamada larga se rechaza. Contar el margen desde el inicio
  (`t_saliente` o `duracion_seg`); toca macro y núcleo.
- **#20 Activar celulares sin trabajo manual** (después del piloto): MacroDroid con archivos, app propia (Tasker App
  Factory → APK) o servicio de call tracking (p. ej. Salestrail por webhook). Nada probado; terminar el piloto con
  MacroDroid.

## Lección de trabajo

Al guiar pruebas físicas, decir en cada paso el aparato (**En la PC** / **En C1**), no pedir datos de pasos ya hechos
(consultar la base en solo lectura) y dar en bloque los pasos simples: a Jhosep el proceso se le hizo largo.

Relacionadas: [[Llamadas desde el celular - decisiones de Miguel y plan v2 (2026-10-03)]],
[[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]].
