**VERDICT: CHANGES_REQUESTED**

**SUMMARY**

Hay defectos concretos en la lectura de comprobantes después de la reversa o de reemplazos sucesivos, y una discrepancia entre la identidad que autoriza la subida y la que valida la confirmación. Además, varias muertes de mutantes no demuestran la protección que sugieren sus nombres.

No encuentro en el SQL aportado un camino que confirme media operación financiera: las excepciones se propagan y revierten la copia, el borrado y el alta. La concurrencia completa y el capital mensual quedan sin verificar por falta de cuerpos relevantes.

Verificación propia: **NOT RUN** — revisión estática de la transcripción. Los PASS del banco son evidencia aportada.

**FINDINGS**

**[P1] La reversa conserva inversiones cuyos comprobantes deja de permitir leer**

Archivo: `supabase/scripts/reemplazar-inversion-cooperativa/reversa.sql`, restauración de `private.f4_comprobante_visible`; migración, §2 y §3b.

Escenario:

1. A se reemplaza por B con un comprobante nuevo en `persona/reemplazo-A/nuevo.pdf`.
2. B conserva ese objeto en `comprobante_objeto_id`. El reemplazo no crea una solicitud con esa ruta.
3. Se aplica la reversa, que conserva B pero restaura una función de visibilidad que exige encontrar la ruta en `crm.inversion_solicitudes`.

La función devuelve `false` para el comprobante de B, incluso a Gerencia. La política SELECT restrictiva impide que otra política permisiva lo habilite. Revertir primero el frontend no resuelve esta pérdida de acceso.

**Acción:** conservar compatibilidad de lectura para comprobantes ya adoptados al retirar las puertas de escritura, o rechazar esta reversa cuando existan esos datos. Recuperar exactamente la huella anterior no acredita una reversa funcional después de usar la característica.

**[P2] Una segunda sustitución puede dejar ilegible el comprobante de la copia auditada**

Archivo: migración, `private.f4_comprobante_visible` y `private.registrar_inversion_reemplazada_cooperativa`.

Escenario:

1. A→B incorpora el comprobante P mediante una ruta de reemplazo.
2. B→C incorpora otro comprobante Q.
3. P queda referenciado en `inversiones_eliminadas.archivos`, pero ninguna fila de `cierres_externos` lo referencia y ninguna solicitud contiene su ruta.

Ambas ramas de visibilidad devuelven `false` para P. Los bytes siguen existiendo, pero las políticas suministradas impiden leer el documento que respalda la copia de B.

V1 prueba una cadena reutilizando el comprobante; V3 prueba un comprobante nuevo sin reemplazarlo después. Ninguno alcanza este caso.

**Acción:** definir acceso autorizado a comprobantes históricos. Si existe otra puerta que entrega estos archivos mediante acceso privilegiado, aportar esa evidencia y probarla; no aparece en lo transcrito.

**[P2] Subida y confirmación discrepan para personas fusionadas**

Archivo: migración, §3b, `private.f4_comprobante_reemplazo_autorizado`; §2, validación de `v_ruta`.

La subida exige:

```sql
private.inversionista_canonica(ce.inversionista_id) = v_persona
```

La confirmación exige un prefijo construido con:

```sql
v_ce.inversionista_id::text
```

Si un cierre conserva `inversionista_id=A` y la persona canónica de A es B:

- `B/reemplazo-<cierre>/x.pdf` pasa la autorización de subida y falla al confirmar.
- `A/reemplazo-<cierre>/x.pdf` no pasa la autorización de subida.

El esquema aportado no prohíbe ese estado; varios ayudantes resuelven expresamente identidades canónicas. Falta demostrar que toda fusión reescribe siempre los cierres.

**Acción:** usar una identidad coherente en ambos pasos y añadir una prueba con un cierre que conserve el ID fusionado.

**[P2] Hay mutantes muertos por otra barrera, y uno no elimina toda la validación anunciada**

Archivos: `test-reemplazar-cooperativa.sql`, R1; lista de `MUTANTES`.

Tres casos concretos:

- **«Sin la carpeta de la persona».** R1 entrega una ruta ajena para la que no creó un objeto. Al quitar la validación del prefijo, el núcleo sigue rechazando por objeto inexistente: `P0409` en lugar del `22023` esperado. El mutante muere por cambiar el error, sin demostrar que se rechazaría un objeto ajeno existente y válido.
- **«Puerta y núcleo: sin exigir rol».** Queda una tercera barrera en `registrar_inversion_reemplazada_cooperativa`: rechaza `p_rol is null` o fuera de los roles permitidos con `22023`. El vendedor puede seguir siendo rechazado, aunque hayan desaparecido las dos comprobaciones mutadas.
- **«Sin validar el objeto».** La transformación deja esta condición:

  ```sql
  (false and (objeto_inexistente or tamaño_inválido))
  or mime_inválido
  ```

  La validación MIME sigue activa. Para un objeto inexistente, el MIME vacío también provoca rechazo. Su muerte no demuestra cobertura independiente de existencia, tamaño y MIME.

**Acción:** conservar las pruebas del contrato de errores, pero distinguirlas de pruebas de seguridad. Crear el objeto ajeno válido y separar los mutantes por defensa. Los nombres «sin copia … (null)» y «sin registrar al actor» también exageran lo que mutan: cambian el UUID de destino y el rol, respectivamente.

**RISKS**

- **Bucket y pertenencia.** Con las políticas aportadas, un vendedor o lector global sin otro rol habilitante no obtiene permiso por la rama nueva. Un admin del portal sí puede subir para cualquier persona cuyo cierre inicial vigente corresponda al prefijo: su autorización es global, no depende de ser responsable de esa persona. Eso coincide con el alcance descrito.

  UPDATE y DELETE siguen bloqueados para `authenticated` por las políticas restrictivas. Ampliar INSERT no permite sobrescribir el objeto existente mediante UPDATE.

  La confirmación, sin embargo, **no exige** que la ruta sea `persona/reemplazo-<p_fuente>/archivo`, ni comprueba quién subió el objeto: admite cualquier ruta válida bajo el ID de esa persona. No demuestra una evasión entre personas, pero tampoco acredita procedencia del archivo respecto de ese reemplazo o actor. No debe describirse como una revalidación completa de la autorización de subida.

- **Atomicidad y solicitud original.** Un fallo de la válvula o del alta posterior no deja una copia confirmada sin completar la operación: no hay un COMMIT intermedio ni un manejador que absorba esos errores. La subida previa del archivo sí es independiente y puede dejar un objeto huérfano.

  La batería no crea una solicitud de alta asociada a las inversiones reemplazadas. Por tanto, no prueba su cancelación ni su posterior rechazo al reconfirmar. El fragmento de confirmación tampoco muestra la comprobación de estado. Los índices únicos sí impiden dos cierres iniciales simultáneos del mismo lead y reutilizar el mismo número de operación mientras la nueva inversión exista.

- **El orden global anunciado no coincide con «Eliminar inversión».** `crm.eliminar_inversion_fn` entra directamente en `eliminar_inversion_contexto`, sin tomar antes el candado global. No puede darse por demostrado que ambas puertas comparten ese orden.

  Además, el contexto toma el mes original y el lead **esperando**. Para una acreditación activa puede bloquearse en `leads FOR UPDATE` antes de alcanzar el `NOWAIT` de `conversion_coordinar_retiro_fuente`. Ese NOWAIT no protege la espera anterior; los try-lock posteriores tampoco.

  Si «Corregir» toma inversión→cierre, existe el ciclo clásico frente al cierre→inversión del reemplazo. Si otra puerta toma lead→fuente, también debe examinarse el orden inverso del contexto. Son escenarios pendientes de confirmar con sus cuerpos, no deadlocks demostrados aquí. El manejador del reemplazo limita sus efectos mediante rollback y `PT409`.

- **Los cotitulares se leen antes de bloquearlos.** `v_titulares` se calcula antes de entrar en la función que bloquea esas filas. Un escritor que modifique o elimine un titular existente sin bloquear primero la inversión podría intercalarse: la copia registraría el estado nuevo y la inversión reconstruida heredaría el viejo. El candado del padre no basta para impedir cualquier modificación de hijos existentes. Falta comprobar el protocolo de sus escritores.

- **Trigger anterior a la llamada explícita.** `conversion_sincronizar_lead` puede escoger otra fuente: tras desaparecer la anterior, una solicitud confirmada o un contrato enlazado tienen prioridad sobre el nuevo cierre. La llamada explícita y el invariante aportan defensas, pero falta el cuerpo de `conversion_acreditar_fuente` para determinar si este recorrido falla, introduce efectos adicionales o se reconcilia correctamente.

- **Idempotencia.** El orden de claves no produce huellas distintas: `p_cierre` es `jsonb`, cuya representación normaliza ese orden. Sí pueden diferir cadenas que después se recortan o fechas textualmente distintas.

  No veo duplicación por reintentar el mismo pedido tras perder la respuesta. Hay otro límite: después de A→B→C, reintentar A devuelve B y consulta sus datos en una fila ya eliminada; `cooperativa` y `fecha_comercial` resultan nulas. Conserva el destino histórico, pero no devuelve necesariamente un destino vigente ni la respuesta original completa.

- **Conversión e imputación.** Poner `fecha_imputacion = fecha nueva` es coherente con el camino admitido: el reemplazo rechaza meses sellados; la imputación a hoy del alta corresponde precisamente al caso sellado.

  Cambiar `creado_en` tiene un efecto reconocido sobre el plazo de acreditación. No se aportan todos sus consumidores ni los de `creado_por`, por lo que no puede descartarse otro efecto sobre informes o cartera. La huella de una función no permite revisar su comportamiento.

  Para capital, se conserva monto/moneda y cambian potencialmente empresa, fecha de imputación y vencimiento. Eso no acredita que las valoraciones antiguas se retiren correctamente ni que los agregados se reconstruyan sin duplicaciones. Falta `materializar_capital_valoraciones_para` y la lógica de retirada y consulta del capital.

**TEST GAPS**

1. **RLS real de Storage:** INSERT, SELECT, UPDATE, DELETE y upsert como `authenticated`, con las políticas efectivas. Incluir al admin sin CRM después de confirmar: la función actual de visibilidad lo excluye por su condición exterior de rol.
2. **Alta real con solicitud:** reemplazar una inversión confirmada por su puerta, comprobar cancelación y reconfirmar la solicitud antigua.
3. **Restricciones diferidas y commit:** los reemplazos exitosos se deshacen antes del commit. Forzar `SET CONSTRAINTS ALL IMMEDIATE` antes de cada rollback de prueba y ensayar un ciclo confirmado con reintento desde otra sesión.
4. **Concurrencia entre dos sesiones:** reemplazo frente a eliminar, corregir, alta, cierre mensual y acreditación, con pausas controladas en los candados relevantes.
5. **La red explícita de acreditación:** fixture con acreditación existente y sin asignación elegible para `conversion_sincronizar_lead`. Quitar la llamada explícita debería hacer fallar ese caso. Añadir otra fuente viva de mayor prioridad.
6. **Defensas sin evidencia específica:** lead por revisar, membresía revocada, fuente sin acreditación y traslado desde un mes cuyo plazo venció hacia otro abierto. La comprobación nueva de plazo mira el mes de destino.
7. **Capital e historia:** comprobar filas y agregados antes/después, incluidos USD, comprobantes sucesivos y reversa después de un reemplazo efectivo.

**NEXT ACTIONS**

1. Resolver la lectura de comprobantes conservados, tanto durante la operación normal como después de la reversa.
2. Unificar la identidad usada para subir y adoptar el comprobante.
3. Corregir los fixtures y separar las defensas de los mutantes señalados.
4. Completar la evidencia de acreditación, corrección, cierre mensual, confirmación y capital; ejecutar las pruebas de concurrencia y commit.

**CONFIDENCE: MEDIUM**

Alta en los hallazgos estáticos de visibilidad, identidad y mutantes. Limitada para concurrencia completa, replay de solicitudes y capital mensual por el código y las ejecuciones que faltan.
