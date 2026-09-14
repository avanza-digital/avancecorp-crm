---
tags: [moc, inicio]
actualizado: 2026-09-14
---

# 🏠 Inicio — Portal Avance Corp

- [[Citas Gerencia - avance integrado sin deploy 2026-09-13]] — módulo real y Superadmin preparados en local/banco; 3.512 pruebas y 48 comprobaciones HTTP PASS. Tres decisiones comerciales y diagnóstico del gate general pendientes; Miguel pidió no desplegar.
- [[Citas Gerencia - reglas confirmadas y propuesta revisada 2026-09-13]] — cuentan manuales y sus citas, cada asistencia cuenta como entrevista y el ticket es mensual por analista; historial de la propuesta aprobada.
- [[Citas Gerencia - meta incorrecta detectada y correccion local 2026-09-13]] — reclamo de Miguel: meta anterior publicada; corrección local y métricas aún pendientes.

Bóveda de conocimiento del **Portal Digital de Inversiones de Avance Corp S.A.C.** (dominio `miavance.com`). Es la **memoria de negocio y decisiones** del proyecto. Léela al inicio de cada sesión.

Estado F8 vigente: [[F8 - ensayo completo antes de instalar (2026-09-14)]].
Ensayo remoto y Auth terminados; sigue instalación OFF autorizada.

Antecedentes: [[F8 - pausa segura de instalacion (2026-09-14)]],
[[F8 - instalacion autorizada en curso (2026-09-14)]],
[[F8 - instalacion apagada preparada (2026-09-13)]],
[[F8 - exclusion demo preparada (2026-09-13)]],
[[F8 - enlaces reales aplicados (2026-09-13)]],
[[F8 - enlaces historicos preparados (2026-09-13)]],
[[F8 - revision de identidades pendientes (2026-09-13)]] y
[[F8 - piloto economico preparado localmente (2026-09-13)]].
F7 publicada e instalada OFF; G6 cerrado el 13/09 para el corte conciliado.
F8 tiene control probado en banco y rama. Los diez movimientos reales ya están
enlazados en producción, con veinte comprobaciones posteriores aprobadas.
Los cuatro huecos demo tienen corrección probada localmente; paquete y
procedimiento de instalación preparados. Miguel aprobó los dos SQL y después
pidió pausar. Trabajo guardado; rama exclusiva eliminada para cerrar su costo.
La reconstrucción revisada queda pendiente. No volver a pedir esa aprobación.
La lectura de las 23:08 Lima confirmó cero huecos reales y compatibilidad de las
14 definiciones previas examinadas. F8 no está instalada ni activa.
F6 conserva su publicación apagada: [[F6 - cierre y ajustes publicados (2026-09-11)]].
Plan principal: [[Plan por fases - cliente multiempresa e inversiones del grupo (2026-09-01)]].

## 🧠 Cómo funciona la memoria de este proyecto

Hay **tres capas**, complementarias:

1. **Este vault de Obsidian** — conocimiento curado, decisiones y features (notas enlazadas).
2. **Grafo de código (CODEgraph)** — estructura del código, vía el MCP `codegraph` (`mcp__codegraph__*`). Consúltalo (p. ej. `codegraph_symbol_search`, `codegraph_get_ai_context`) en vez de grepear.
3. **Documentos canónicos** (la *fuente de verdad* técnica):
   - **`public_html/CLAUDE.md`** → memoria técnica detallada del portal. **GANA sobre todo lo demás** si hay diferencia.
   - **`PORTAL_AVANCE_CORP_IMPLEMENTACION.md`** → guía de implementación.
   - **`CRM-Avance-Corp/PLAN-CRM-AVANCE-CORP.md`** → plan maestro vigente del CRM;
     su sección inicial «Estado maestro vigente» concentra avance, ruta crítica y
     definición de «CRM listo».
   - *(`MEMORIA DE PROYECTOS.md` se eliminó el 2026-06-01 por estar desactualizado — era copia vieja del CLAUDE.md.)*

## 🗺️ Mapa de notas

- [[Arquitectura del portal]] — stack, base de datos, edge functions, seguridad (resumen).

**Features y decisiones:**
- [[F8 - pausa segura de instalacion (2026-09-14)]] — pausa solicitada, producción sin F8, rama propia eliminada, revisión recibida y punto exacto de retoma guardado.
- [[F8 - instalacion autorizada en curso (2026-09-14)]] — dos SQL aprobados; rama propia creada, reconstrucción y verificación en curso; F8 productiva sin instalar ni activar.
- [[F8 - instalacion apagada preparada (2026-09-13)]] — SQL exacto y procedimiento para rama con paridad de esquema/historial/Edge; precondiciones actuales verificadas; instalación pendiente.
- [[F8 - exclusion demo preparada (2026-09-13)]] — 31 pruebas locales; SQL y reversa listos para revisión, sin aplicar ni activar producción.
- [[F8 - enlaces reales aplicados (2026-09-13)]] — SQL aprobado y aplicado; siete personas / diez movimientos, cero huecos reales y cuatro demo pendientes. F8 sigue OFF.
- [[F8 - enlaces historicos preparados (2026-09-13)]] — historial del ensayo de siete personas / diez movimientos; aplicación productiva completada después.
- [[F8 - revision de identidades pendientes (2026-09-13)]] — diagnóstico cerrado: ocho movimientos reales para completado, dos del caso multirrol y cuatro pruebas. Informe privado en el escritorio; correcciones pendientes.
- [[F8 - piloto economico preparado localmente (2026-09-13)]] — control nominal F8 probado en banco sintético; producción intacta y piloto todavía OFF. Faltan enlaces, equipo, rama e inicio autorizado.

- [[Citas Gerencia - preparacion verificada 2026-09-13]] — publicación existente comprobada: tres migraciones y 72 archivos HTTP coincidentes con `d3ce2c1`; deuda de pruebas generales y nuevas metas/proyección pendientes.
- [[Citas Gerencia - publicacion pausada 2026-09-12]] — preparación detenida por Miguel; candidatas ensayadas en rama propia, validaciones incompletas, sin commit ni publicación.
- [[Citas Gerencia - conexiones corregidas en local 2026-09-12]] — caché y lector canónico preparados y probados; SQL sin instalar, nuevas metas/proyección y gate global pendientes.
- [[Leads recibidos por dia para analistas 2026-09-12]] — rango y conteo diario de entradas operativas a la cartera; rama preview verificada, pendiente de publicación.
- [[Citas Gerencia - avance y proyeccion mensual por analista 2026-09-11]] — flujo cita/entrevista/cliente aclarado; propuesta visual del cierre con tasas y ticket, bases pendientes.
- [[Citas Gerencia - control de Superadmin en borrador 2026-09-11]] — panel local para metas y reglas; guardado compartido pendiente de SQL autorizado y nuevas métricas aún sin activar.
- [[Alertas de respuestas de tasa para analistas - 2026-09-11]] — avisos en la PC, sonido y lectura de respuestas propias mientras el CRM está abierto.
- [[Notificaciones de solicitudes de tasa - implementacion local 2026-09-10]] — SQL y coste autorizados; PWA verificada localmente, banco remoto exclusivo en pruebas antes de publicar.
- [[G6 - conciliacion real preparada (2026-09-11)]] — 218 inversiones reales conciliadas y conformidad humana/financiera recibida para el corte del 11/09. G6 cerrado; los diez enlaces pendientes se completaron después en F8.
- [[F7 - publicada y apagada (2026-09-11)]] — informe Empresas publicado y SQL instalado OFF; pruebas específicas PASS, cero regresiones sobre los 57 fallos de la matriz general, banco cerrado; G6 cerrado el 13/09/2026.
- [[F7 - informe multiempresa en sombra preparado (2026-09-11)]] — historial de construcción, decisiones, revisiones y autorizaciones previas a la publicación.
- [[F6 - cierre y ajustes publicados (2026-09-11)]] — últimos ajustes publicados y verificados, revisión manual cerrada con VoiceOver omitido; F4/F5/F6 apagadas y F7 siguiente.
- [[F6 - publicada y apagada (2026-09-10)]] — historial de instalación y 43 pruebas remotas PASS; observaciones RLS/Auth. La publicación de los últimos ajustes quedó resuelta el 11/09; F7–F9 siguen pendientes.
- [[F6 - conflicto HTTP y ensayo remoto (2026-09-10)]] — corrección PT409, pruebas y límites.
- [[F6 - implementación de postventa (2026-09-10)]] — decisiones e implementación inicial.
- [[F5 - instalada y apagada (2026-09-10)]] — SQL autorizado instalado y verificado; banco temporal eliminado, datos conservados.
- [[Citas Gerencia - cierre de sesion y punto de retoma 2026-09-09]] — publicado, avance guardado y respaldo privado; pendientes de revisión visual y mantenimiento del banco general.
- [[Solicitud de tasa en el lead - publicada 2026-09-09]] — aprobación antes de convertir publicada; banco temporal cerrado y verificaciones registradas.
- [[RETOMAR-64 - CARTERA F4 terminada y avance guardado (2026-09-08)]] — punto de retoma vigente, commits y respaldo privado; sigue F5.
- [[F4 cerrada - comisiones fuera del sistema (2026-09-08)]] — F4 técnica terminada; comisiones externas excluidas del sistema. Sigue F5.
- [[F4 multiempresa - reconstruccion, finanzas y lectura vigente (2026-09-08)]] — candidata técnica probada y guardada; G4 cerrado según la decisión de comisiones externas.
- [[UX1 y UX2 Gerencia - componentes y revision visual 2026-09-06]] — catálogo reutilizable y nueva revisión de Resumen/Conversiones; pendiente de revisión visual y validación humana de F0.
- [[Organizacion local y Figma - UI UX Gerencia 2026-09-06]] — carpeta `UX-UI-GERENCIA`, índice de Figma, estado de F0 y preparación de UX1.
- [[Rol Analista]]
- [[Rol Directorio]]
- [[Fusión asesor-analista]]
- [[Clave temporal = DNI]]
- [[Notificaciones de pagos]]
- [[Importador de clientes]]
- [[Gestión comercial de clientes - renovaciones y upgrades]]
- [[Nucleo de conversion - diagnostico de llegadas y asignaciones 2026-09-04]]
- [[Plan de correccion de metricas de Gerencia - requerimiento vigente]] — cinco puntos acordados, restricciones y punto de reanudación.
- [[Inventario de indicadores de Gerencia - Contrato de lectura]] — significado, fuente, período y límites de cada indicador; entregable documental del punto 1.
- [[Correccion de pantallas de Gerencia - punto 2 - 2026-09-04]] — correcciones implementadas, verificadas y publicadas; alcance y límites.
- [[Correccion de Cartera - punto 3 - conciliacion y SQL pendiente 2026-09-04]] — punto 3 completado: SQL aplicado y frontend publicado. Cifras conciliadas, pruebas y reversión.
- [[Main unico - sincronizacion y publicacion 2026-09-04]]
- [[Publicacion frontend metricas Gerencia 2026-09-04]] — todo guardado; frontend publicado desde `50f33a5`, archivos y acceso de Gerencia verificados. Los puntos 4–5 siguen pendientes.
- [[Datos faltantes de Gerencia - punto 4 - decision pendiente 2026-09-05]] — justificación histórica de las cuatro necesidades; alcance aprobado e implementación local completada después.
- [[Plan por fases - cuatro datos de Gerencia - aprobado 2026-09-05]] — N1–N4 implementados y auditados localmente; falta confirmar/aplicar SQL, versionar, sincronizar y publicar.
- [[Contrato tecnico de ampliaciones N1-N4 de Gerencia - 2026-09-05]] — contrato, huellas, migración, rollback y evidencia final. Título comercial acordado: «Resultados de los leads del mes».
- [[Auditoria final de Gerencia - punto 5 - avance 2026-09-05]] — ampliaciones y animación verificadas localmente con núcleos intactos; faltan las puertas productivas y el commit final.
- [[Cierre productivo de metricas de Gerencia - ejecucion 2026-09-05]] — ejecución autorizada de los seis pasos; preflight actual comprobado, SQL exacto pendiente de confirmación y publicación todavía no realizada.
- [[Identidad unificada de inversionistas - plan pendiente]]
- [[Handoff plan maestro multiempresa aprobado para firma F0 (2026-09-01)]]
- [[Incidente y restauracion Ficha 360 2026-08-31]]
- [[Nombres en mayúscula]]
- [[Interés compuesto]]
- [[Realtime de novedades]]
- [[Bug de fechas UTC]]
- [[Reporte diario de derivaciones para Coordinación]]
- [[Auditorías del portal]]
- [[Citas Gerencia - auditoria de conexion a nucleos 2026-09-11]] — auditoría de backend/frontend: lector fuera del núcleo, caché pendiente y nuevas metas/proyección aún sin conexión; 97 pruebas y TypeScript pasados, gate del servidor fallido.

**Herramientas independientes:**
- [[SubLínea — subtítulos locales para X]]

## 👤 Reglas de trabajo con Miguel

- Miguel **no es desarrollador** (analista comercial). Explicar en **lenguaje natural**, sin jerga.
- **Versiones de desarrollo:** usar siempre la **última versión estable** disponible del lenguaje, framework y dependencias aplicables. Antes de implementar, verificar las versiones y la documentación vigente con Context7. Si una actualización rompe compatibilidad con el proyecto, explicar el impacto y acordar la migración antes de aplicarla.
- **Cambios de base de datos:** mostrar el **SQL primero** y esperar confirmación.
- Lo **visual** decláralo explícito para que Miguel lo pruebe; las **capturas** son el input principal de debugging.
- **Deploy manual** a Hostinger (copiar a la carpeta espejo) + subir `?v=N` del módulo editado.
- Máximo 3 intentos automáticos; si sigue fallando, escalar con explicación clara.

- [[Notificaciones de tasa - publicadas 2026-09-11]] — Avisos de tasas activos en la PWA; falta permiso y prueba del teléfono.
