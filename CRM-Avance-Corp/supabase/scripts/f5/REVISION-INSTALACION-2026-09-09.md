# Evaluación de la revisión de instalación F5

Codex PRIMARY consultó una vez a Claude como SECONDARY_REVIEWER mediante el
wrapper aislado. Dictamen: **CHANGES_REQUESTED**; se conserva el
[informe íntegro](evidencias/instalacion-2026-09-09/revision-claude.txt).
No equivale a un PASS. El PRIMARY decidió sobre cada hallazgo con código y pruebas.

| Hallazgo | Evaluación y evidencia del PRIMARY |
| --- | --- |
| P1: reversa sin aserción de funciones F5 | La reversa real solo bloquea y apaga la bandera; no recrea ni elimina funciones. Se reforzó el replay comparando después las nueve funciones F5 completas, ACL y dueño; conserva la capacidad corregida y D-19=0. PASS. |
| P1: cambio simultáneo de producción/Tasa | Se añadió base versionada y `preflight-merge.mjs`: compara esquema, historial completo, permisos, código/entrada/JWT de todas las Edge, Main remoto y banderas, con captura de máximo 60 segundos. Cinco pruebas pasan. El cambio real 265→266 de Tasa fue rechazado antes de renovar la base. |
| P2: primer caso de candado no distingue la lectura de F3 | Ahora F5 está encendida en ese subcaso y se exige el motivo exacto de apagado de F3. La revocación de membresía durante la espera mantiene además una prueba de comportamiento del snapshot. PASS. |
| P2: el gate general no exige volatilidad/límite de espera de F5 | Se añadió comprobación condicional de existencia, VOLATILE, dueño, SECURITY DEFINER, search_path, lock_timeout y helper. Se ejecutó la función D-19 exacta del script general contra el banco: siete checks PASS. No se declara repetido el resto del gate. |
| P2: clave opaca desconocida como Bearer | Bearer se envía solo para una estructura JWT de tres segmentos; otras claves quedan únicamente en apikey. Auth y ambas RPC conservan el JWT del usuario. Casos JWT/opaco/otro formato PASS y descarga desplegada PASS. |
| P2: errores de Storage sin diagnóstico | Se registra únicamente estado HTTP y bucket. Prueba confirma que no aparecen ruta, nombre, cabeceras ni claves. Se conserva la respuesta pública genérica. |
| P2: falta prueba del segundo descriptor divergente | Añadida: dos respuestas autorizadas pero con ruta distinta devuelven 409 y descartan los bytes. PASS. |
| P2: exigir SHA/bytes para todo documento | Rechazado por contrato vigente: documentos históricos y comprobantes pueden carecer de SHA persistido. Exigirlo bloquearía descargas válidas. El PDF sellado sí valida su SHA; los demás mantienen SHA de transporte y doble permiso. Ya documentado en README/CONTRATO y probado con Storage real. |
| P2: volver idempotente el SQL ya aplicado | No se modifica una migración versionada/aplicada. El guard exige el cuerpo original; ante respuesta perdida se inspeccionan historial, SQL exacto y cuerpo, sin repetir a ciegas. El manifiesto registra MD5 anterior y corregido calculados desde ambos archivos. |
| P2: referencia remota de Git posiblemente antigua | El constructor consulta `git ls-remote avancecorp refs/heads/main` antes y después del build, además de refs locales y fuentes limpias. |
| P3: otras banderas como autorización | La capacidad es informativa. La confirmación económica sigue revalidando por F4 bajo sus candados; F5 no sustituye esa autoridad. No se activa escritura. |
| P3: posibles nombres de bandera duplicados | Hipótesis descartada: `multiempresa_flags.nombre` es clave primaria. No se cambia SQL por un estado imposible bajo el esquema vigente. |
| P3: UUID por coacción | Corregido: cada valor debe ser string antes del regex. Arrays y números se rechazan como 400 antes de Auth/Storage. |
| P3: carpeta de paquete | Se exige directorio real, sin symlink, y permisos 0700. No contiene claves de servicio. |
| P3: orden JSON de descriptor | Se conserva comparación completa: la RPC devuelve JSONB, cuyo contrato ordenado no cambió. Un cambio de tipo exigiría revisar ese contrato; no se introduce una comparación parcial que ignore campos nuevos. |
| P3: 55P03/0A000 con F5 OFF | El límite de espera es deliberado y READ COMMITTED es el contrato publicado de F3. Se conserva el error ante contención; no se simula un estado exitoso que el servidor no pudo verificar. El censo productivo no tiene llamadores SQL de la capacidad, y el consumidor utiliza POST de PostgREST. |

Durante el trabajo se publicó Tasa (`20260909165815`). Se ejecutó
`rebase_branch` antes de renovar la base del gate: padre 266 migraciones y
banco 268 (las dos adicionales son F5). Se cotejaron las 1.353
funciones/restricciones del padre, con solo los tres CHECK asociativos previamente
explicados, y las 17 Edge existentes/50 archivos, byte a byte. La función de
conversión nueva quedó conservada. Las 15 comprobaciones remotas F5 volvieron
a pasar después del rebase.

La comparación previa reduce la ventana de concurrencia, pero no es un bloqueo
global entre publicaciones: la API de merge no ofrece compare-and-swap conjunto
de SQL y Edge. Debe ejecutarse inmediatamente antes de integrar y repetirse la
verificación de fuentes después; cualquier cambio observado exige detener y
reintegrar. No se interpreta la fecha de captura como una reserva del servidor.

Verificación final del PRIMARY: 46 pruebas locales F5, cinco del gate premerge,
15 comprobaciones remotas y siete checks D-19 del script general PASS; replay
con reversa reforzada, sintaxis/preflights y tipos PASS. Los 65 fallos previos
del gate general siguen declarados. No se cambió el SQL correctivo ni su SHA.
La revisión y estas pruebas respaldan preparar la instalación apagada; no
constituyen autorización del segundo SQL ni aprobación del piloto económico.
