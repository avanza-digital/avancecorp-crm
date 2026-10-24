VERDICT:
CHANGES_REQUESTED

SUMMARY:
La candidata cumple el objetivo central con evidencia sólida: el publicador fija `corte=v_hasta`, construye base/producción/facturación/metas/personas solo con operaciones que tienen `valoracion_id`, la huella sigue incluyendo corte, meta y las cinco proyecciones, y la puerta v2 reutiliza la autorización de v1 antes de calcular pendientes filtrados por `vendedor_id`. Las 22 aserciones SQL y las 12 HTTP cubren los casos pedidos (parcial PEN con USD pendiente, equipo ajeno 403, sello rechazado, sello inmutable, idempotencia). No encuentro defectos de permisos ni fugas de datos ajenos. Sí hay dos huecos que deben cerrarse antes de aplicar: el cambio de semántica de `corte` (ya no implica cobertura completa) no está probado contra el cierre cuando el corte llega a fin de mes con un pendiente vivo, y no se adjuntó el diff del publicador respecto a la versión con hash `629ec2…`, así que la afirmación "conserva identidad y huella" solo está respaldada indirectamente por TEST 4. Además hay una duplicación de contrato en la rama sellada de v2 que conviene corregir ahora, cuando es barato.

FINDINGS:

[P2] El cierre no está probado con corte = fin de mes y pendiente vivo
File:
CRM-Avance-Corp/supabase/scripts/capital-pendientes/prueba.sql
Lines:
132-153 (savepoint sello_pendiente) y 244-263 (savepoint sello_completo)
Problem:
Con la candidata, `corte` ya no significa "todo lo anterior está valorado". En `sello_pendiente` solo se parchea `now()` de `crm.cerrar_periodo`, no `statement_timestamp()` de `private.publicar_corte_capital`, así que el corte del último revisión es 2026-10-23 y no 2026-10-31. El escenario donde el mes ya terminó, el corte es 10-31 y sigue habiendo un USD sin TC no se ejercita. Ese es precisamente el estado en que la nueva semántica podría confundir a una puerta de cierre que antes podía inferir cobertura por fecha.
Evidence:
Migración línea 36 (`v_corte:=v_hasta`) frente a comentario línea 3 y texto del request ("sello mensual permanece estricto"). El cuerpo de `crm.cerrar_periodo` no está adjunto; el mensaje capturado "Cierre pendiente: reconciliar % valoraciones de capital" sugiere que la puerta cuenta valoraciones pendientes directamente, pero es inferencia, no evidencia. Marcado como hipótesis.
Impact:
Si alguna comprobación del cierre usa `corte = último día del mes` como señal de completitud, un mes con pendiente podría sellarse con el nuevo publicador. Riesgo financiero directo (sello inmutable con capital faltante).
Recommendation:
Añadir un savepoint que parchee ambas funciones a 2026-11-12 (como `sello_completo`) pero sin consolidar el TC del USD, y asertar que `cerrar_periodo` falla con `PT409` y que no se crea fila en `capital_mes_sellos`. Adjuntar el fragmento de `cerrar_periodo` donde se evalúa la cobertura de capital.

[P2] Falta el diff del publicador frente a la versión protegida por hash
File:
CRM-Avance-Corp/supabase/migrations/20261024030000_crm_capital_pendientes_sin_bloquear.sql
Lines:
9-14 y 16-80
Problem:
El preflight compara `md5(prosrc)` con `629ec2c60834ab1dc72abcbef8542486`, pero la evidencia solo contiene el cuerpo nuevo completo. No puedo verificar qué líneas cambiaron realmente respecto a la versión en producción (cálculo de `v_corte`, filtro `where a.valoracion_id is not null`, join interno de facturas, campos de identidad, orden de agregación). Sin ese diff, "mantiene identidad, huella e historia inmutable" se sostiene solo en TEST 4 (misma huella en el mismo día) y en la precondición del banco.
Evidence:
Request del PRIMARY: "Preflight bloquea si publicador esperado cambió"; no hay hunk del `create or replace` frente al cuerpo anterior.
Impact:
Una diferencia no intencional en el orden de agregación, en `to_jsonb(h)` o en las columnas de `facturas` cambiaría la huella de todos los meses abiertos en la primera ejecución y generaría una revisión espuria, o peor, alteraría `identidad_persona`.
Recommendation:
Adjuntar `diff` entre `pg_get_functiondef` de producción y el cuerpo nuevo. Si el único cambio son las líneas 35-36 y el filtro de la línea 44, dejarlo explícito en el comentario de cabecera de la migración.

[P2] La rama sellada de v2 construye `cobertura` a mano y duplica el contrato
File:
CRM-Avance-Corp/supabase/migrations/20261024030000_crm_capital_pendientes_sin_bloquear.sql
Lines:
99-102
Problem:
Para meses sellados, v2 arma el objeto `cobertura` literal (`estado`, `corte`, `generado_en`, `pendientes`, `por_incorporar`, `ventas_pendientes`) en lugar de delegar en `private.capital_estado_corte`, que es la única fuente de ese shape para `cumplimiento_metas_v2_fn` y `facturacion_diaria_v2_fn`. El frontend lo valida con `v.optional(CoberturaCapitalSchema)` dentro de un `strictObject`.
Evidence:
Comparar líneas 100-102 de la migración con `capital_estado_corte` líneas 58-73 del archivo existente. La prueba SQL de mes sellado (líneas 255-258) solo comprueba `estado`, `ventas_pendientes` y `total_pen`, no la igualdad estructural.
Impact:
Cualquier campo que se añada a `capital_estado_corte` en el futuro quedará ausente en la rama sellada y hará fallar el `strictObject`/`optional` del cliente solo en meses cerrados, que son los menos probados.
Recommendation:
En la rama sellada llamar a `private.capital_estado_corte(p_periodo, v_corte.id, '[]'::jsonb)` y sobrescribir solo `estado` a `'completo'` si hace falta, o extraer un constructor común. Añadir una aserción que compare las claves de ambas ramas.

[P3] El acoplamiento `por_incorporar ⊇ pendientes` queda implícito en la UI
File:
CRM-Avance-Corp/app/src/components/common/cobertura-capital.tsx
Lines:
Hunk de `valoradasPorIncorporar = Math.max(0, cobertura.por_incorporar.cantidad - pendientes)`
Problem:
El componente resta `pendientes` a `por_incorporar` asumiendo que todo pendiente también cuenta como por incorporar. Hoy es cierto por la definición en `capital_estado_corte` (líneas 51-55: `valoracion_id is null or not exists(...)`), pero el servidor no publica esa invariante y el componente no tiene test unitario del caso mixto.
Evidence:
`capital_estado_corte` líneas 51-55 y 63-64; ningún test adjunto renderiza `por_incorporar.cantidad > pendientes.cantidad`.
Impact:
Si el servidor dejara de incluir los pendientes en `por_incorporar`, la UI mostraría "N operaciones ya valoradas se incorporarán" con N inflado.
Recommendation:
Que `capital_estado_corte` exponga la cantidad de valoradas por incorporar como campo propio, o al menos añadir un test unitario del componente con `por_incorporar=3, pendientes=1` y con una pendiente PEN por `fecha_comercial_sin_acreditar`.

[P3] Un analista sin meta y solo con ventas pendientes recibe 42501 en el detalle
File:
/private/tmp/avancecorp-capital-review-existente.sql (v1, líneas 12-15) y migración línea 95
Problem:
v2 hereda de v1 el rechazo "Analista fuera del ámbito autorizado" cuando el vendedor no aparece en `personas`. `personas` se construye desde `operaciones` (solo valoradas) y `metas_vendedor`; un analista sin meta cuyo único contrato espera TC no está en ninguna de las dos. Su propio detalle devuelve 42501 y el cliente no hace fallback.
Evidence:
Migración líneas 59-66; `prueba.sql` savepoint `sin_meta` líneas 199-203 solo consulta `cumplimiento_metas_v2_fn`, no `capital_operaciones_valoradas_v2_fn` para `id(7)`.
Impact:
Bajo: hoy el ranking no muestra botón de detalle para alguien fuera de `personas`. Pero el código de error es semánticamente incorrecto (no es un problema de permisos) y puede confundir soporte.
Recommendation:
Añadir una aserción en `sin_meta` que documente el comportamiento actual para `id(7)` (esperado 42501 o un payload vacío) y decidir explícitamente cuál se quiere.

[P3] Una revisión nueva por día mientras exista un pendiente
File:
CRM-Avance-Corp/supabase/migrations/20261024030000_crm_capital_pendientes_sin_bloquear.sql
Lines:
31, 36, 73-74
Problem:
`v_corte` entra en la huella y avanza cada día del mes en curso. Con la versión anterior el corte se congelaba antes del pendiente, por lo que la huella no cambiaba; ahora cada corrida diaria en un mes con USD atascado inserta una revisión aunque base/producción/facturación sean idénticas.
Evidence:
TEST 4 (líneas 126-129 y 234-237) solo repite dentro del mismo día.
Impact:
Crecimiento de `capital_cortes_valorados` y cambio diario de `corte_id` que el frontend "conserva" por diseño. No es incorrecto según el requisito "Corte=v_hasta", pero es un cambio de ritmo de publicación que conviene dejar documentado.
Recommendation:
Documentarlo en el comentario de la migración o añadir una prueba que parchee `statement_timestamp()` a día siguiente y aserte el comportamiento esperado (revisión nueva con misma producción).

TEST GAPS:
- Cierre con corte igual a fin de mes y pendiente vivo (ver P2 primero).
- Igualdad estructural de `cobertura` entre la rama sellada y `capital_estado_corte`.
- Prueba SQL de v2 con `p_corte_id` de una revisión anterior tras llegar el TC: `por_incorporar.cantidad=1`, `pendientes.cantidad=0`.
- Componente `CoberturaCapitalAviso` con pendientes mixtos (PEN sin fecha comercial acreditada y USD sin TC) y con `por_incorporar > pendientes`.
- Repetición del gate completo y del caso E2E 8/8 siguen pendientes según el propio PRIMARY; deben reportarse con salida real antes de DONE.

ARCHITECTURE RISKS:
- `corte` cambia de significado ("completo hasta") a ("valorado hasta") sin renombrar el campo; cualquier consumidor que lo use como señal de cobertura queda silenciosamente desactualizado. Vale una búsqueda de usos de `corte` en funciones SQL que decidan cierre o sello.
- Duplicación del shape de `cobertura` en v2 (P2 tercero).

SECURITY RISKS:
- Ninguno nuevo confirmado. v2 es `security definer` con `search_path=''`, owner postgres, ejecutable solo por `authenticated`, autoriza vía v1 antes de tocar `produccion_operaciones`, y filtra por `vendedor_id`. Las pruebas de equipo ajeno (SQL líneas 167-181 y HTTP) lo respaldan.
- `revoke ... from service_role` sobre v2 es coherente con v1; verificar que ningún job server-side use ese rol para el detalle.

REGRESSION RISKS:
- Primera ejecución del publicador en producción: todos los meses abiertos con pendiente generarán una revisión nueva con corte avanzado. Esperado, pero conviene anunciarlo.
- Textos cambiados ("Aún no se ha publicado un corte", "primera publicación de capital valorado") rompen cualquier test o selector no incluido en el diff que buscara las frases antiguas.
- Fallback a v1 por `PGRST202` solo protege el despliegue del frontend antes de la migración; tras `notify pgrst` no debería activarse. Si se activa en producción, es señal de que la migración no aplicó.

RECOMMENDED NEXT ACTIONS:
1. Añadir y ejecutar el caso de cierre con ambas funciones parcheadas a 2026-11-12 y el USD sin TC; adjuntar el fragmento de `cerrar_periodo` que evalúa cobertura de capital.
2. Adjuntar el diff real del cuerpo de `publicar_corte_capital` frente a la versión con hash `629ec2…` y confirmar que solo cambian el cálculo de `v_corte` y el filtro de valoración.
3. Unificar la construcción de `cobertura` en la rama sellada de v2 con `capital_estado_corte` y asertar igualdad de claves.
4. Cerrar los pendientes declarados: salida del gate completo repetido y del E2E 8/8 corregido.

CONFIDENCE:
MEDIUM. Los hallazgos de corrección parcial, huella y RLS se apoyan en el código y las pruebas adjuntas. La confianza baja en el cierre y en la ausencia de regresiones del publicador porque faltan `cerrar_periodo`, `capital_valoraciones_actuales`, `produccion_operaciones` y el diff del cuerpo anterior.
