VERDICT:
CHANGES_REQUESTED

SUMMARY:
La refactorización mantiene intactos los puntos que el PRIMARY pidió proteger:
- consultas;
- condiciones de habilitación;
- escritores de PostventaPersona;
- gating de `capacidades.postventa`;
- totales leídos del RPC.

El render prop evita que la ficha se desmonte cuando falla la consulta F6, y eso mejora frente al early-return anterior. Hay hallazgos accionables de severidad media:
- Se pierde la distinción entre capital activo y capital registrado.
- Quedan ocultos avisos y acciones operativas dentro del detalle plegado.
- El botón de detalle tiene un nombre accesible que no coincide con su texto visible.
- Los componentes "extraídos sin cambios" sí alteran visualmente ClienteFicha.

No encuentro P0 ni P1.

FINDINGS:

[P2] Se pierde la semántica "Capital activo" frente a "Capital registrado" en los totales
File: `CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx`
Lines: 198-203 (continuidad), 234 (sustituye a `<ResumenEmpresas>`)
Problem: El diff elimina `<ResumenEmpresas totales={ficha.totales} />` de "Inversiones y contratos". Ese componente mostraba "Capital activo" o "Capital registrado", además de la cantidad por empresa y moneda (líneas 23-33). Ahora solo queda la continuidad, que usa `money(t.capital_activo ?? t.capital_registrado, t.moneda)` sin ninguna etiqueta que indique cuál de los dos valores se muestra.
Evidence: En una ficha solo Avance la etiqueta es `'Capital vigente'` (línea 198). Si `capital_activo` es `null`, algo que el schema admite (`inversionistas.ts:28`), se muestra `capital_registrado` bajo el rótulo "vigente". En el test nuevo, `qorilazo` tiene `capital_activo: null` y `capital_registrado: 90000`, y la UI pinta "Qorilazo · S/ 90,000" sin decir que es un registrado. También se pierde `t.cantidad` por empresa y moneda.
Impact: Es información financiera ambigua. Gerencia o un analista pueden leer capital registrado (que incluye inversiones vencidas o anuladas comercialmente) como capital vigente. Esto afecta el requisito de "mantener fuentes/cálculos", porque la fuente se conserva pero su significado se degrada.
Recommendation: Hay dos opciones:
- Conservar un sufijo breve por línea, por ejemplo "activo" o "registrado", según el campo que se use.
- Mantener `ResumenEmpresas`, o una versión compacta, dentro de la sección de inversiones.

Añadir una aserción al test "conserva los totales del núcleo…" que distinga los dos casos.

[P2] Acciones y avisos operativos quedan ocultos tras "Ver inversión"
File: `CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx`
Lines: 78-106
Problem: Dentro del `<div hidden={!abierta}>` quedan tres elementos que antes estaban siempre visibles:
- el botón "Recuperar PDF pendiente" (línea 100);
- el aviso "Anulación comercial. El capital registrado se conserva." (línea 92);
- el estado del documento (línea 97).
Evidence: Antes estos elementos formaban parte del `<article>` visible. El propio test tuvo que añadir clics en "Ver detalle de QORILAZO SINTÉTICO" antes de "Documento del ensayo" (diff de `cartera-inversionistas.test.tsx`, hunk @@ -129).
Impact: Un PDF con `reintentable: true` puede quedarse sin recuperar porque nada en la tarjeta compacta indica que está pendiente. En F4 esto implica un contrato sin documento sellado. El badge de estado sí muestra la anulación, pero la aclaración sobre el capital queda oculta.
Recommendation: Mover "Recuperar PDF pendiente" a `acciones`, o añadir a `badges` un badge como "PDF pendiente" cuando `i.pdf?.reintentable`. Los documentos pueden seguir bajo demanda.

[P2] El nombre accesible no contiene el texto visible (WCAG 2.5.3, label in name)
File: `CRM-Avance-Corp/app/src/components/app/inversionista-ficha.tsx`
Lines: 108-111
Problem: El texto visible es "Ver inversión" u "Ocultar detalle", pero `aria-label` lo sustituye por "Ver detalle de {numero}".
Evidence:
```tsx
aria-label={`${abierta ? 'Ocultar' : 'Ver'} detalle de ${i.numero || 'la inversión'}`}
...{abierta ? 'Ocultar detalle' : 'Ver inversión'}
```
Cuando `numero` es `null`, todas las tarjetas se llaman "Ver detalle de la inversión", con nombres duplicados.
Impact:
- Quien usa control por voz y dice "Ver inversión" no encuentra el botón.
- Con varias inversiones sin número, un lector de pantalla no puede distinguir los botones.
Recommendation: Hacer que el texto visible forme parte del nombre, por ejemplo "Ver inversión" con `aria-describedby` apuntando a la referencia. Otra opción es un nombre como `Ver inversión ${numero}`. Como fallback sin número conviene usar un dato distintivo como empresa, moneda o fecha. Hay que actualizar los selectores de los tests.

[P3] Los componentes compartidos modifican visualmente ClienteFicha, que se describía como "conservando lógica original"
File: `CRM-Avance-Corp/app/src/components/app/ficha-comercial.tsx`
Lines: hunk @@ -3,10 +3,48 (`FichaComercialInversion`, `FichaComercialHistorial`)
Problem: La tarjeta extraída no reproduce exactamente el marcado anterior de ClienteFicha:
- El título pasa de `truncate` a `[overflow-wrap:anywhere]`.
- El contenedor pasa de `flex items-start` a `flex flex-wrap` con `basis-40`, así que en anchos estrechos el capital puede bajar de línea.
- El detalle del historial también recibe `[overflow-wrap:anywhere]`.
Evidence: Diff de `cliente-ficha.tsx` (clases eliminadas) comparado con `ficha-comercial.tsx` (clases nuevas). El E2E visual compara solo el ancho del diálogo (línea 49), no la composición interna.
Impact: Probablemente es una mejora, pero es un cambio visual no declarado en la ficha que el usuario pidió recuperar tal cual.
Recommendation: Declararlo en la entrega o comparar las capturas `ficha-anterior.png` de antes y después con nombres de producto largos.

[P3] Remontaje completo si cambia `capacidades.postventa` durante la apertura
File: `inversionista-ficha.tsx`
Lines: 278-279
Problem: `contenido()` se renderiza como hijo de `<PostventaPersona>` o directamente en la raíz, según `ficha.capacidades.postventa`. Al cambiar el valor tras un refetch cambia la forma del árbol, y React remonta todo el subárbol.
Impact: Se pierden varios estados:
- `abierta` de cada tarjeta;
- el estado interno de `CuentasAvance`, con nuevas lecturas de bancos (el test asegura `api.bancos` ×2 sin relecturas);
- el foco.

Es un caso poco frecuente, por ejemplo al activar o desactivar el flag F6 con la ficha abierta.
Recommendation: Renderizar siempre un envoltorio estable, ya sea un `PostventaPersona` con prop `activa` o un componente intermedio. Otra opción es documentarlo como aceptado.

[P3] El badge "Demostración" pierde su color de advertencia
File: `inversionista-ficha.tsx`
Lines: 73
Evidence: Antes era `color="amber"`. Ahora es `var(--chart-4)`, el mismo color que el badge de categoría de la línea 71.
Impact: Una inversión demo deja de destacar frente a las reales.
Recommendation: Mantener `amber`.

[P3] Contenido extraño en el slot de cabecera de sección
File: `postventa-persona.tsx`
Lines: 49-55
Problem: `acciones` se pasa al `accion` de la cabecera de "Información del cliente" (línea 248 de la ficha). Incluye el párrafo "Gerencia debe asignar un responsable…" y un contenedor flex que puede quedar vacío, por ejemplo con un analista y `no_contactar=true`.
Impact: Un texto de ayuda largo queda comprimido junto al título a 390px. Además, la ayuda describe una restricción del botón "Agendar gestión", que ahora está en el pie y lejos de este texto.
Recommendation: Situar la ayuda junto a "Agendar" en el pie, o dentro del cuerpo de "Seguimiento".

TEST GAPS:
- Falta una prueba unitaria de PostventaPersona en modo error tras un éxito previo. Debería comprobar que la ficha sigue montada, que desaparecen agendar, acciones y retiros, que aparece `PanelError`, y que al reintentar vuelven los controles. El E2E "rechazo F6 aislado" no se detalla lo suficiente para confirmar que cubre el refetch fallido con datos previos.
- El test de Directorio (`f6-postventa.spec.ts`) ya no verifica la ausencia del bloque completo. Debería afirmar también que no aparecen "Cambiar responsable", "Marcar No contactar" ni "Solicitudes de retiro".
- No hay caso para `yo.demo`: ficha visible sin controles y sin diálogo.
- No hay caso para el clic en "Registrar solicitud de retiro" con `habilitada=false`. Hoy ese botón queda inerte y el diálogo se abriría después si la consulta pasara a habilitada. Es paridad con el comportamiento previo, pero no está cubierto.
- No hay aserción para `capital_activo: null` en una ficha solo Avance (ligado al P2 de totales).
- No hay caso para un PDF `reintentable` en la tarjeta compacta.
- La igualdad exacta `toBe(medidaAnterior?.width)` sobre valores float puede ser frágil; conviene tolerancia ±1px.

REGRESSION RISKS:
- Paridad verificada en el diff:
  - la condición `habilitada` equivale a la del early-return anterior;
  - el `disabled` de agendar, asignar, veto y retiros es idéntico;
  - los escritores (`AsignarResponsable`, `TramitePostventa`, `ClienteGestion`) no cambian.
- El `Dialog` queda gateado por `habilitada`. Si un refetch F6 falla con el diálogo abierto, este se cierra y se reabre al recuperarse, igual que antes. Queda la hipótesis, sin evidencia del `Dialog`, de que al cerrarse desmonte a los hijos y se pierda el borrador en curso. Es preexistente.

SECURITY RISKS:
- No hay cambios de autorización. El detalle con `hidden` sigue en el DOM, pero son datos que ya se mostraban. Documentos y cuentas siguen detrás de sus callbacks y lecturas revalidadas.

RECOMMENDED NEXT ACTIONS:
1. Restaurar la distinción activo/registrado (y la cantidad) en los totales, y añadir la aserción correspondiente.
2. Sacar "Recuperar PDF pendiente", o un indicador de PDF pendiente, a la tarjeta compacta.
3. Alinear el nombre accesible del botón de detalle con su texto visible y evitar nombres duplicados.
4. Añadir la prueba unitaria del modo error de PostventaPersona y reforzar el test de Directorio.
5. Declarar los cambios visuales en ClienteFicha y mostrar la comparación al usuario antes de publicar, como ya está previsto. El gate de realidad sigue NOT RUN y debe reportarse así.

CONFIDENCE:
MEDIUM. El diff y las fuentes son suficientes para estos hallazgos. No dispongo de `Dialog`, `FichaComercialSeccion`, `cliente-ficha.tsx` completo ni los fixtures, así que la afirmación sobre el desmontaje de hijos del diálogo es una hipótesis.
