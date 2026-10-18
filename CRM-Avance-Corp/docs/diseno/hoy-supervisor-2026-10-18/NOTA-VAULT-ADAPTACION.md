---
tags: [crm, supervisor, hoy, comercial, ux]
fecha: 2026-10-18
estado: implementado-local-sin-publicar
---

# Hoy supervisor - direccion de jornada integrada localmente (2026-10-18)

Miguel eligió la dirección 2 y pidió adaptarla al CRM. La ruta Hoy del supervisor
ahora usa «Dirección de la jornada»: resultado mensual arriba, **Llamadas de hoy**,
**Citas de hoy**, acompañar el cierre, tabla por analista y pendientes. Se retiraron
los accesos «Cómo leer las cifras» y «Si faltan datos». Después pidió continuar
solo en local, sin navegador; se dejó la validación en código y pruebas locales.
Al cerrar, Miguel aclaró: **«no necesitas docker solo estamos viendo diseño»**.
Esta iteración es de diseño local; no continuar E2E ni tratarlo como condición
para entregar esta propuesta. Los intentos de pruebas previos quedan como historial.

Capital, metas, operaciones y conversión vienen de las fuentes oficiales del mes.
La actividad diaria viene de la foto completa de Gestión Diaria. No promediar
tasas por analista: contacto es contestadas/útiles agregadas. Citas se agrupan por
fecha prevista y estado explícito, no por creación ni restando otros estados.
El potencial de oportunidades se presenta por moneda y corresponde a toda la
cartera abierta asignada; se distingue del capital confirmado.

La tabla mensual conserva la atribución oficial, incluidos cambios de equipo.
Capital/metas y conversión pueden tener poblaciones distintas: la falta de fila
de conversión de una persona no invalida las filas confirmadas de los demás.
La cobertura del núcleo decide si pueden mostrarse. Ausente no equivale a cero;
meta cargando, meta caída y meta inexistente tienen mensajes distintos.

Los componentes viejos se mantienen como referencia, pero la ruta usa la nueva
portada. Se omitieron consultas de ranking/agenda semanal no utilizadas. Se
reutilizan detalle por analista, tasas autorizadas y módulos de destino existentes.
No hay cambios SQL, permisos ni dependencias.

Evidencia: `CRM-Avance-Corp/docs/diseno/hoy-supervisor-2026-10-18/ADAPTACION-CRM.md`.
Lint, typecheck, build y bundle PASS. Suite unitaria 6 766 pruebas PASS; después
de corregir la revisión, 118 pruebas relevantes PASS. Claude hizo una revisión
solo lectura: CHANGES_REQUESTED/MEDIUM, hallazgos evaluados y corregidos por
PRIMARY; resolución en el mismo directorio. No hubo segundo dictamen.

E2E Docker **no acreditado**: timeouts de arranque, un fallo documentado en la
corrida dirigida y proceso terminado con código 143 sin resumen final. Gate de
realidad **NOT RUN**, falta `SUPABASE_URL`. Pendiente validar E2E en entorno estable
y conciliar fuentes productivas en una futura preparación para publicar, fuera
del alcance de esta revisión de diseño. Implementación solo local;
sin publicación ni cambios a registros del CRM.

[[Hoy supervisor - dos propuestas de indicadores comerciales (2026-10-18)]] ·
[[Hoy del supervisor - puesto de mando en una pantalla, plan (2026-09-27)]] ·
[[Gestion Diaria - supervisor horizontal aprobado (2026-09-23)]] ·
[[Citas - validacion de cifras del supervisor Jorge (2026-09-28)]] · [[Inicio]]
