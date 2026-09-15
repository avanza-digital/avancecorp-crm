# Controles técnicos G7 en copia local

**PASS — 15/09/2026. G7 permanece ABIERTO.** No hubo cambios productivos, nuevas
cuentas reales ni banco remoto de pago. Los casos son sintéticos y no firman la
aceptación económica o financiera del piloto.

## Banco y versiones

Contenedor `supabase_db_avancecorp-f5-bank`, copia propia `g7_cierre_20260915`.
Se clonó `ficha_rapida_20260915`, sin modificar esa base fuente. En la copia se
aplicó la optimización publicada `20260915170237_crm_ficha_lectura_individual.sql`
y se sincronizaron desde el catálogo productivo las dos envolturas vigentes
`crm.confirmar_inversion_revisada_fn(uuid,integer)` y
`crm.corregir_solicitud_inversion_fn(uuid,uuid,integer,jsonb,text)`.

Las **65 definiciones seleccionadas** de inversión/COOPAC/piloto/permisos
coinciden con [versiones-nucleo.json](versiones-nucleo.json). La selección y
comparación exacta se conservan en el ejecutor; no es paridad de todo el catálogo,
esquema, ACL ni servicios Auth/Storage. No se modificó ninguna función productiva.

## Resultados

| Prueba | Resultado y alcance |
|---|---|
| Diez reintentos | Cinco confirmaciones repetidas Qorilazo y cinco Prodelco; misma inversión, respuesta y hechos, salvo `reintento:true` |
| Cinco carreras económicas | Confirmación duplicada, depósito entre personas/empresas, clave con importes distintos, confirmación contra corrección y conversión inicial repetida |
| Simultaneidad observada | Dos sesiones SQL esperando un candado antes de liberarlo en cada carrera; no se deduce concurrencia solo de lanzar promesas |
| Permisos generales | 21 contextos: quince cuentas sintéticas de base y seis variantes agregadas dentro de ROLLBACK |
| Aislamiento | Cuatro fichas ajenas denegadas; Directorio con/sin equipo conserva lectura Avance y sin escritura |
| Denegaciones | Coordinación, perfil inactivo, membresía inactiva y Directorio inactivo no adquieren acceso; la lista también rechaza con `42501` |
| Transición | F8 OFF y F4/F5/F6 ON se ven íntegros tras COMMIT; F3 ON/F7 OFF |
| Fallo/contención | Error deliberado después del cambio y candado ocupado abortan sin estado parcial |
| Reversa | Retorno al piloto vigente sin ampliar fechas y apagado de capacidades nuevas conservan dieciséis superficies |

Recibos: [operaciones](ensayo-local.json), [roles](roles-general-local.json) y
[transición/reversa](transicion-local.json). Las dieciséis huellas incluyen
contratos, cronogramas, descriptores PDF, inversiones, depósitos, eventos,
personas, gestiones, tareas, leads, períodos/fotos y cuentas Auth. La tabla de
fotos mensuales local está vacía: esta conservación **no prueba una nueva
operación contra un mes sellado con filas**.

El primer intento de crear contextos de rol omitió el supervisor de un vendedor;
el trigger lo rechazó y la transacción se revirtió. El fixture final asigna un
supervisor activo y mantiene FK/triggers/RLS. La primera ejecución del guion de
transición no obtuvo acceso al socket Docker del sandbox; con el permiso local
correspondiente el ensayo terminó correctamente. Ninguno es un defecto productivo.

## Ejecución y límites

Desde la raíz, contra la copia ya preparada y con Docker disponible:

```sh
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/ensayo-local.mjs
docker exec -i supabase_db_avancecorp-f5-bank psql -X -qAt -U postgres -d g7_cierre_20260915 -v ON_ERROR_STOP=1 -f - < CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/roles-general-local.sql
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/transicion-local.mjs
node CRM-Avance-Corp/supabase/scripts/multiempresa-f8/cierre-g7-2026-09-15/verificar-evidencia.mjs
```

El SQL de roles imprime el recibo; se conserva como `roles-general-local.json`
solo si `psql` termina con código 0. El verificador comprueba los tres recibos y
sus huellas. Una ejecución interrumpida de los guiones Node invalida el PASS
anterior al escribir RUNNING; no se acepta como prueba terminada.

Los ejecutores financieros usan rol SQL `authenticated` y claims sintéticos.
Los comprobantes solo tienen metadatos Storage ficticios: no se subieron bytes.
**NOT RUN nuevo:** login Auth/HTTP, navegador productivo, fallo del servicio Auth,
los seis recorridos completos y todos los casos especiales. No se extrapola la
matriz de 21 contextos a sesiones reales de las 24 cuentas productivas.

La copia queda disponible para inspección con piloto y miembros apagados y las
banderas previas restauradas. Conserva los hechos ficticios creados por el ensayo.
El guion de transición está cerrado al banco local: **no es el SQL exacto de
producción**, que requerirá guardias del equipo/código y la aprobación prevista
en [APERTURA.md](APERTURA.md).
