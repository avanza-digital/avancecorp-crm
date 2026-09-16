# Apertura general Multiempresa autorizada

Miguel pidió «OK ACTIVALO PRO FAVOR» después de comprobar que el acceso seguía
limitado a Carlos, Jorge, Vladimir y Linda. Autoriza la apertura operativa a los
18 analistas y sus supervisores/Gerencia. La aprobación de apertura no se
presenta como firma contable ni como cierre del ciclo mensual G8.

Estado: **ACTIVADO Y VERIFICADO, 15/09 a las 21:08 Lima**.
[Acta productiva y pruebas posteriores](ACTA-PRODUCCION.md).
La pausa anterior quedó sin activación; Miguel reanudó con «seguimos».
Transición atómica completada F8 OFF,
F4/F5/F6 ON; F3 permanece ON y F7 OFF. Solo cambia configuración, preservando
roles y fuentes canónicas. Los filtros mensuales y la distribución de Cartera
quedan en su pendiente independiente.

Alcance confirmado: 18 analistas, 3 supervisores, 2 Gerencia; Coordinación
conserva su exclusión. No hay Directorio vigente en el corte de apertura.
Los cuatro miembros nominales se conservan como historial, con piloto OFF.
`actualizado_por` identifica al responsable operativo declarado Carlos; el
motivo identifica autorización de Miguel y ejecución administrativa Codex.
No representa inicio de sesión ni firma de Carlos.

## Artefactos y evidencia

- [ACTIVAR.sql](ACTIVAR.sql): artefacto exacto de configuración, con vigencia
  limitada en [config.json](config.json), abortos atómicos y recibo posterior
  al COMMIT. Solo administración `postgres` sin claims de otro usuario.
- [REVERTIR.sql](REVERTIR.sql): desactiva las nuevas capacidades y conserva
  inversiones, identidades e historia. Un solo uso. No restaura el piloto;
  otra apertura exige captura/artefacto nuevos.
- [POSTFLIGHT.sql](POSTFLIGHT.sql): comprueba capacidades en las 24 cuentas
  por SQL con rol authenticated y ROLLBACK. No es login Auth ni prueba UI.
- [verificar-lecturas.sql](verificar-lecturas.sql): tres roles fuera del piloto,
  lista/ficha, importes exactos del núcleo y rechazo de ficha ajena. ROLLBACK
  deshace también las auditorías de lectura de esta comprobación.
- [ensayo.json](ensayo.json): **17 escenarios PASS** en copia sintética propia
  `f9_apertura_20260915`, con SHA256 de los artefactos usados. Ventana local de
  candados 67,198 ms; no es medición de producción. Dos inversiones F4 nuevas
  sobreviven a REVERTIR sin cambiar las 19 superficies de datos verificadas.
- [EVALUACION-REVIEW.md](EVALUACION-REVIEW.md): respuesta con evidencia al
  CHANGES_REQUESTED original; revisión final evaluada y observaciones verificadas.
- [conciliacion-previa.json](conciliacion-previa.json): 16/09 01:57:37 UTC,
  614 fuentes/468 personas y cero diferencias entre Cartera, Capital y F7.
- [frontend-publicado.json](frontend-publicado.json): cuatro recursos HTTP 200,
  huellas y presencia de las funciones de Cartera/Postventa publicadas.

## Ejecución y soporte

Procedimiento ejecutado. No repetir ACTIVAR: el estado ya cambió y sus guardas
rechazan una segunda ejecución. Para una futura intervención recapturar primero.

1. Verificar el [preflight](capturar-preflight.sql) en el proyecto
   `dctqcbznekcyxhjujuci`, comparar equipo/roles, control, miembros, lectores,
   funciones y triggers con config. No refrescar una diferencia a ciegas.
2. Conservar revisión/evidencia y respaldar el commit en `avancecorp/main`.
3. Ejecutar ACTIVAR sin modificar su texto. Una guarda, timeout o pérdida de
   respuesta requiere leer primero el estado real: no repetir a ciegas.
4. Exigir recibo posterior al COMMIT, lectura independiente de banderas/control,
   POSTFLIGHT, lecturas por rol y conciliación. Si una capacidad o un permiso
   falla, usar REVERTIR y registrar el resultado; preservar las inversiones.
5. Si queda encendido, actualizar el acta y la memoria. Para ver la nueva
   Cartera basta actualizar el CRM; la consulta de disponibilidad también se
   refresca al entrar, recuperar foco y cada 15 segundos.

No se cierra G8: continúa observación del ciclo operativo mensual. F7 permanece
apagada; la apertura no fabrica conformidad financiera ni calculadora de
comisiones. No hubo banco remoto nuevo de pago.
