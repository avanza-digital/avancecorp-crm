# F8 — propuesta de enlaces históricos

**Aplicada y verificada en producción el 13/09/2026**, tras la aprobación de Miguel.
Acta y resultado: [APLICACION-2026-09-13.md](APLICACION-2026-09-13.md).
Miguel confirmó que
las dos cuentas del caso multirrol corresponden a la misma persona. El lote
privado permitió crear siete identidades y enlazar diez movimientos reales:
nueve contratos Avance de seis perfiles cliente y un cierre Qorilazo de un
lead convertido. El diagnóstico previo está en
[REVISION-IDENTIDADES-2026-09-13.md](../REVISION-IDENTIDADES-2026-09-13.md).

## Efecto concreto

- Crea siete identidades, siete identificadores DNI y siete asignaciones del
  responsable original activo. Conserva los perfiles, sus roles y las cuentas
  Auth. La cuenta analista del caso multirrol no recibe un enlace económico.
- Avance se resuelve por el perfil cliente. Qorilazo enlaza cierre y lead; el
  trigger F3 vigente crea su puente canónico. Registra ocho mapas de fuente
  (seis perfiles, un cierre y su lead). El caso multirrol conserva clase E,
  ahora resuelta con confianza alta y motivo explícito; no se disfraza de
  coincidencia automática.
- El trigger de responsable deja una gestión por persona. La fuente de cada
  documento y el motivo contienen el identificador del lote y la huella de la
  evidencia. La ejecución administrativa usa su actor SQL real: no suplanta
  un JWT humano ni atribuye a un usuario una escritura hecha por `postgres`.
- Conserva contratos, titulares, importes, monedas, estados, fechas, perfiles
  y capital. No crea inversiones F4, movimientos de dinero ni comisiones.
  Las fuentes históricas admiten `inversion_id` vacío y se leen por sus enlaces
  originales. No hay cambios permanentes de esquema ni de banderas.

La aceptación documental sigue la procedencia histórica F2, explícita en la
propuesta: seis INSERT auditados de perfil y uno de cierre conservan el DNI
original vigente. La consulta privada del 13/09 a las 20:21 Lima comprobó sus
autores registrados, responsables activos y ausencia de otros titulares.
Los seis perfiles fueron capturados sin actor JWT en el audit; el cierre sí
tiene actor analista. No se infiere el endpoint usado ni una consulta a un
registro externo. La conformidad financiera G6 no sustituye esta evidencia.

## Guardas y reversa

[completar.sql.in](completar.sql.in) exige F3 ON, F4–F7 OFF, F8 ausente/OFF,
ejecución administrativa sin claim humano y `READ COMMITTED`. Comprueba las
preimágenes económicas y documentales, auditoría original, responsable,
colisiones entre tipos, mapas y enlaces. Un cambio o una reaplicación aborta
el lote completo. Rechaza también huecos reales nuevos fuera de los diez.

Los bloqueos de tabla cubren escritores ajenos al advisory del resolutor y las
referencias FK a identidades. Hay timeout de bloqueo de tres segundos y de
sentencia de treinta segundos: ejecutar en un momento de poca actividad.
Si se aborta por una venta o documento nuevos, volver a revisar la fotografía;
no quitar guardas ni reintentar sustituyendo datos automáticamente.

Con 598 fuentes sintéticas, ensayo/aplicación/reversa tardaron 0,48/0,48/0,47 s
en local. No es un plazo garantizado en producción: el stock y la concurrencia
pueden diferir. Los tres segundos limitan la espera para adquirir un candado;
los candados adquiridos se mantienen hasta terminar toda la transacción.

Antes y después compara ocho superficies protegidas, incluyendo todo el capital
derivado. La reversa solo procede si las personas mantienen el estado exacto
esperado y no recibieron nuevas inversiones, cotitulares, tareas u otras
referencias. Restaura los enlaces operativos previos y conserva identidades
bloqueadas, documentos/puente históricos y auditoría. **No borra la historia ni
deja listo un reintento idéntico:** una operación posterior a la reversa exige
otra revisión. La reversa es una acción independiente; no se ejecuta por defecto.

Después de revertir, el índice documental parcial permite al resolutor F3 crear
una identidad vigente para ese DNI: no queda reservado para siempre. En cambio,
el puente histórico del lead Qorilazo sigue reservado; reenlazarlo requiere una
reconciliación administrativa explícita del puente y del lead. Las escrituras
normales no lo reparan y activar la válvula por sí sola tampoco reconstruye el
puente. Ambos efectos se probaron con ROLLBACK y deben considerarse antes de
autorizar una reversa. El censo global conservador también exige revisar una
reversa nueva si aparece cualquier hueco real ajeno al lote.

## Generación y prueba

[generar.py](generar.py) solo produce archivos privados, sin conexión ni ejecución
SQL. Rechaza un lote distinto de siete personas / diez fuentes / un multirrol.
Desde esta carpeta:

```bash
python3 generar.py '/ruta/privada/revision-privada-verificada.json' \
  '/ruta/privada/procedencia-documental.json' \
  '/ruta/privada/confirmacion-multirrol.json' '/ruta/privada/nueva-propuesta'
PYTHONDONTWRITEBYTECODE=1 python3 probar.py
```

Genera `lote-privado.json`, `ensayo-transaccional.sql` (ROLLBACK),
`aplicar-propuesta.sql` (COMMIT), `reversa-propuesta.sql` e `integridad.json`.
La carpeta es `700`, sus archivos `600`. Contienen datos personales: no subirlos
a Git ni adjuntarlos al reviewer. El lote preparado está en el escritorio,
`Revision F8 - identidades 2026-09-13/Propuesta de enlaces/`.

[probar.py](probar.py) solo utiliza el contenedor local fijo
`supabase_db_avancecorp-f5-bank`. Clona la base **sintética** F7
`multiempresa_f7_20260911` a `multiempresa_f8_identidades_20260913`; antes de
reemplazarla exige su comentario de propiedad y cero conexiones. No acepta
URLs/destinos externos. Conserva triggers y restricciones durante la operación.
El fixture reproduce el estado anterior a F3 y un audit documental histórico
anterior al enmascaramiento; no modifica datos reales ni debilita el SQL.

Verificación: [VERIFICACION.md](VERIFICACION.md). Revisión independiente:
[REVISION-CLAUDE.md](REVISION-CLAUDE.md).

## Estado productivo y siguiente paso

Miguel aprobó el `aplicar-propuesta.sql` exacto. Se comprobaron su hash, censo y
funciones; se aplicó una vez y se verificó el COMMIT con veinte comprobaciones
en lecturas nuevas. El comprobante permanece privado. No volver a aplicar el lote.

**Los diez huecos reales están corregidos; F8 no está instalada/activa.** La
lectura posterior encontró cero huecos reales y cuatro demo. El tratamiento de las
pruebas en gate/listados/ficha/conteos sigue pendiente; este lote no permite
encender F5 ni F8. El equipo, instalación compatible y evidencia real G7 siguen
en el [plan F8](../README.md).
