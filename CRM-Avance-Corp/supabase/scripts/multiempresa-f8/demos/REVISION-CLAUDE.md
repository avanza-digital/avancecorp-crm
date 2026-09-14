# Revisión independiente — F8 demos

Codex PRIMARY; Claude Code SECONDARY_REVIEWER, mediante `scripts/claude-review`
sin herramientas ni MCP. LEVEL 3, dos consultas acotadas. Se adjuntó evidencia
saneada, consultas CodeGraph y definiciones/tests; Claude no escribió archivos.

Ambos dictámenes fueron **CHANGES_REQUESTED**, con confianza MEDIUM. El PRIMARY
evaluó los hallazgos, incorporó las correcciones pertinentes y ejecutó los gates
finales: **31 pruebas SQL PASS**. No se pidió una tercera opinión para obtener
un PASS. La versión final acotada a demos y el arreglo del reinicio del banco
quedaron verificados por el PRIMARY después de la segunda consulta.

Evidencia: [primera revisión](revision-1.txt), [segunda revisión](revision-2.txt),
[salida SQL final](pruebas-sql.txt),
[lectura productiva sin PII](preflight-produccion-2026-09-13.json).

## Decisiones y resolución

| Hallazgo | Decisión y evidencia |
|---|---|
| P2: faltaría bloquear los escritores de banderas globales | Rechazado tras adjuntar `private.trg_multiempresa_flags_bloquear_piloto_f8`, migración `20260913215240`, líneas 228–261: toma el mismo candado `crm_piloto_f8_control` en los encendidos, incluidos INSERT. La segunda revisión confirmó esa lectura. Añadir locks de filas después podría invertir el orden. Cinco carreras del control PASS. |
| P2: barrido de consumidores incompleto | Corregido: todos los esquemas no sistémicos, referencias cualificadas/no cualificadas, comillas/espacios y excepciones por OID. `pg_depend` cubre vistas/materializadas, policies y funciones SQL con cuerpo analizado. Nuevos consumidores en public y vistas provocan rollback en ambos sentidos. SQL montado dinámicamente sigue requiriendo revisión manual. |
| P2: la reversa no explica el ledger | Corregido en cabecera y README: no altera el historial; compensación y reinstalación publicadas requieren nuevas migraciones en rama. No se presupone que `db push` repita una versión. |
| P3: falta comprobar las huellas que necesita la reversa | Corregido: postflight de las ocho definiciones, incluida la huella final de personas `f32a1baf67372df496388508a724e6bb`. Reversa exacta aplicada, comprobada y seguida de reinstalación en banco. |
| P3: NULL y capital podrían discrepar | La columna productiva `public.contratos.es_demo` es NOT NULL y cierres produce un booleano no nulo. El mutante solo comprueba que NULL no evade cobertura. No se altera la semántica financiera existente. |
| P1 de segunda ronda: el reinicio del banco no permitió terminar una sesión de otro rol | Corregido: se retiró `pg_terminate_backend`; el banco comprueba cero conexiones cliente y rehúsa interrumpir sesiones. La ejecución completa posterior terminó con 31 PASS, incluidas las 11 del piloto y cinco carreras. |
| P2 de segunda ronda: `con_historia` abarca también historia real | Aceptada la acotación a demos: sus ramas ahora se alimentan exclusivamente del CTE demo del lector bruto. Se prueban todos los extremos, incluso contradictorios y leads históricos. Un mutante demuestra que un filtro futuro que omita fuentes reales no hace desaparecer el perfil. La lectura productiva además demuestra cero contratos/cierres fuera del lector actual. |
| P3: faltan pruebas diferenciales/permisos | El cierre demo era aceptado por `postventa_fuente` antes del ajuste y se rechaza después. Documento demo de persona mixta devuelve NULL para Gerencia y vendedor responsable. Directorio, cliente sin fuentes, perfiles solo demo y aislamiento entre vendedores PASS. Vencimientos ya excluía demos: ese caso se conserva como prueba de regresión. |
| P3: probar rechazos de instalación/reversa y rollback de deriva | PASS con F8 o cada bandera F4–F7 encendida, función alterada, consumidor public y vista. Se comprueba restauración de la última función y del primer lector ya procesado antes del fallo, además de la huella de datos. |

La hipótesis sobre ACL de `postventa_fuente` quedó descartada: tanto esta función
como el lector bruto ya estaban cerrados a roles API; sus llamadores autorizados
son definers. El helper nuevo conserva esa frontera.

La segunda consulta mencionó como información una posible renombrada de
banderas administrativas activas. El ajuste no cambia nombres ni permisos de
esas filas; no abre esa capacidad. No se declara una auditoría general de todas
las mutaciones administrativas del control F8.

## Alcance de la entrega

La consulta productiva verificó diez huellas/propietarios existentes y el estado
F3 ON, F4–F7 OFF, cero huecos reales y cuatro demo. Dos definiciones posteriores
al control F8 solo existen en el banco: deben revalidarse tras instalar ese
prerrequisito. Cada candidato mantiene la convención transaccional del paquete
F8 previo; el historial remoto/merge sigue sujeto a su gate de instalación.

Los preflights de scripts/Edge/seed/RLS pasaron. Seed/RLS offline no abren
conexión. La matriz SQL focalizada ejecutó las funciones con roles reales de
PostgreSQL; no se simula haber probado Auth/Data API remota.

**NOT RUN:** rama/replay/advisors/Auth Data API remoto de esta corrección, build
frontend y regeneración de tipos (sin cambios de contrato expuesto o cliente).
El SQL es una candidata revisable: producción no está instalada ni activada y
G7 conserva sus casos reales y conformidades pendientes.
