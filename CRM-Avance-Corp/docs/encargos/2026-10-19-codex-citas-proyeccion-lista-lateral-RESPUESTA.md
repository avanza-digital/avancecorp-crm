**VERDICT: NEEDS CHANGES**

**SUMMARY:** No encuentro divergencias de datos: ambas vistas recorren `detalle.lista` y usan las mismas expresiones y componentes. La lista tiene nombre accesible y la agrupación `dt`/`dd` es correcta. El diff conserva la tabla de escritorio.

**FINDINGS**

- **P2 — El botón de la persona no garantiza 44 px de ancho.** [proyeccion.css:143](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/app/src/components/citas/proyeccion.css:143) establece `min-width: 0`; la [regla móvil:216](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/app/src/components/citas/proyeccion.css:216) solo añade `min-height: 44px`. Con las reglas suministradas, una persona llamada «Li» con lead tiene un botón de ancho intrínseco que puede quedar por debajo de 44 px. Garantizar también el ancho mínimo. Es una conclusión estática; no tengo medición en navegador.

- **P3 — La prueba de paridad no demuestra el orden de las citas.** En [proyeccion-hoja.test.tsx:731](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/app/src/components/citas/proyeccion-hoja.test.tsx:731), ambos arrays de nombres pasan por `.sort()`. Si las tarjetas se renderizaran en orden inverso, esa aserción seguiría pasando. El código actual conserva el orden, pero la prueba no protege ese contrato. Comparar la secuencia esperada sin ordenarla.

**TEST GAPS**

- El [E2E añadido:284](/Users/usuario/Desktop/DESARROLLO/DESARROLLO/AVANCECORP-desktop/CRM-Avance-Corp/app/e2e/citas-proyeccion.spec.ts:284) comprueba tarjetas, tipografía y anchura a 390 px; no demuestra ausencia de desbordes a 320 px con nombres sin espacios, dólares largos y fecha/hora. Tampoco mide las dimensiones táctiles.
- La prueba de apertura de ficha verifica el callback y la desaparición del diálogo. No verifica foco inicial, retorno al disparador/respaldo ni foco dentro de la ficha real. Falta la implementación de `Sheet` para evaluarlo estáticamente.
- El mutante reportado demuestra que las pruebas detectan sustituir las tarjetas por la tabla. No acredita orden, tamaños táctiles ni gestión del foco.

**NEXT ACTIONS:** Garantizar el ancho táctil, quitar `.sort()` de la comprobación de orden y completar las comprobaciones de navegador anteriores.

**CONFIDENCE:** Media. Revisión limitada al material adjunto; sin acceso al repositorio ni navegador. **NOT RUN por mí:** Vitest, oxlint, tsc, check completo y E2E Docker. Los resultados comunicados no constituyen verificación independiente.
