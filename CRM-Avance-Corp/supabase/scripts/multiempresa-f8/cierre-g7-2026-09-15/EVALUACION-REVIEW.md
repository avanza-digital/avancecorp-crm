# Evaluación PRIMARY del review

Claude entregó **CHANGES_REQUESTED**, confianza MEDIUM. El dictamen original se
conserva en [REVISION-CLAUDE.md](REVISION-CLAUDE.md); no es una aprobación G7.
El primer intento no arrancó dentro del sandbox (exit 1, sin dictamen). El mismo
pedido se ejecutó con el wrapper autorizado fuera del sandbox y terminó exit 0.
No se hizo otra consulta para obtener un dictamen favorable.

| Hallazgo | Decisión y evidencia |
|---|---|
| Matriz del destino general y olas F9 | Aceptado. Nuevos [21 contextos SQL generales](PRUEBAS-LOCALES.md) PASS, incluidos Coordinación, perfiles/equipo inactivos y Directorio sin equipo. Hay 92 comparaciones Auth/API previas en modo general; nada de ello representa login de las 24 cuentas productivas. [APERTURA.md](APERTURA.md) conserva G7 y las olas. |
| Supuesta ventana obligatoria de F8 OFF a global ON | Matizado: nueva prueba local pasa transición en una sola transacción, visibilidad entre conexiones, aborto por error/contención y reversa; dieciséis superficies conservadas. Falta preparar el SQL productivo con guardias actuales y aprobación, no se ejecutó una transición real. |
| Paridad con fuentes compartidas | Aceptado. Se rotula coherencia interna de lectores; ninguna comparación acredita documentos físicos o contabilidad externa. La conformidad financiera permanece pendiente. |
| Falta de desglose | Ampliado en [complemento.sql](complemento.sql): seis filas de desglose, cero diferencias y tres renovaciones completas cuya suma coincide. Nueve renovaciones históricas carecen de desglose y se conservan explícitas. Los 89 upgrades no son renovaciones: sus campos renovado/adicional son NULL conforme al flujo existente; no se inventa ese puente ni se compara NULL como cero. El caso reasignado coincide en stock/atribución/autor, sin ejecutar una reasignación. |
| Autoría frente a atribución | Corregido con `capital_episodios.registrado_por` y `inversion_solicitudes.creado_por/confirmado_por`: diez Avance por autores no nominales y una Qorilazo por un actor piloto, también atribuida a él. |
| Ancla temporal | El complemento fija el inicio documentado `2026-09-14T18:23:51.712435Z` y muestra el control vivo por separado. La consulta inicial es evidencia de una ventana concreta, no un acumulador reutilizable después de reiniciar el piloto. |
| Procedencia de la lectura administrativa | Documentada abajo. No se atribuye acceso humano a Gerencia ni una sesión Auth. Se conservaron los recibos fuera de la BD, con huellas de las personas consultadas. |
| Orden de la huella mensual | Refutado el posible orden incompleto: PK productiva `(periodo,vendedor_id)`. El agregado filtra un período y ordena por vendedor. Dos capturas conservan las 16 filas y sus huellas. Esto acredita estabilidad entre cortes, no una nueva prueba de escritura contra un mes sellado. |
| Dependencias/versiones y ficha anterior tras error | Ampliado contexto de funciones en complemento y guardias; no se afirma un inventario transitorio completo. Se añadió `ficha:=null` al comenzar cada persona. Ninguno de los 19 casos originales falló; no hubo huella reutilizada. Las páginas son de 25 inversiones y los dos enteros son números de página. La muestra solo ejercita página 1; paginación superior no se atribuye a este ensayo. |
| Anulaciones y secuencia histórica | [casos.json](casos.json) completa Avance, también cero. Avance → Avance incluye renovaciones/upgrades y solo se describe como transición de fuentes; no equivale a una nueva inversión adicional de F8. |
| Sin responsable no probado | Resuelto después del pedido inicial: dos fichas reales, lectura permitida a Gerencia y nueva inversión bloqueada. [casos.json](casos.json). |
| Personas nuevas, casos raros y firmas | Se mantiene G7 abierto. Posteriormente Miguel aprobó expresamente el ajuste de evidencia («sii claro hazlo»). Los [casos complementarios](CASOS-COMPLEMENTARIOS.md) pasan 15 grupos HTTP, 3 financieros y 46 contextos; las firmas siguen pendientes. |

## Procedencia administrativa

Operador: **Codex PRIMARY**, a pedido de Miguel. Conexión: conector administrativo
Supabase de PortalAvanceCorp; rol inicial `postgres`. Propósito: verificar
coherencia de lectores y aislamiento de capacidades antes de preparar la apertura.
No participaron ni iniciaron sesión las personas nominales del CRM.

Los scripts de capacidades/fichas usaron claims locales y `SET LOCAL ROLE
authenticated` para comprobar la autorización de las RPC. Toda la transacción
terminó con ROLLBACK, incluidas las filas de auditoría que escribe la lectura de
fichas. No se registró ese ensayo como actividad humana de Carlos/Gerencia.
La evidencia duradera son los scripts y recibos versionados: corte del 15/09,
19 huellas en [fichas.json](fichas.json), 24 cuentas en [roles.json](roles.json) y
dos casos adicionales sin responsable. Esas huellas son seudónimos, no una
anonimización irreversible. No se versionan DNI, nombres, contactos o UUID reales.

La consulta adicional del desglose no modifica dinero. No se ejecutaron retiros,
anulaciones, confirmaciones, reasignaciones, altas Auth ni banderas productivas.
