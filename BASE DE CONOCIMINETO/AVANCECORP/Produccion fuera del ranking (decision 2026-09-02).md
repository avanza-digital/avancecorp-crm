# Producción fuera del ranking

Decisión comercial del 2026-09-02, complementaria a [[Rankings por mes calendario (decision 2026-09-02)]] y [[Ranking de capital total unificado (TC BCRP)]].

## Regla cerrada

- Solo los analistas comerciales pueden recibir puesto en los rankings individuales.
- Una inversión atribuida a un supervisor, Gerencia, coordinación, Directorio o una persona fuera de la estructura no se reasigna artificialmente a un analista.
- Esa producción sí forma parte del resultado total de la empresa, porque el capital y las operaciones existen.
- La misma producción no crea una fila rankeable, no aumenta el contador de analistas y no modifica posiciones, metas ni porcentajes individuales.
- Gerencia la ve nominada y desglosada bajo **«Producción fuera del ranking»**, con responsable, motivo, capital PEN/USD, contratos, cierres y operaciones de cartera.
- Supervisores y analistas no reciben ese bloque global.

## Implementación

No se crearon funciones, RPC ni tablas paralelas. La regla se incorporó a los núcleos mensuales existentes mediante la migración `20260902202247_crm_ranking_foto_mensual_coherente`.

En meses abiertos, Gerencia recibe el detalle calculado desde los mismos núcleos canónicos de conversión, producción y cartera. Al cerrar el mes, el detalle queda congelado dentro de `crm.periodos_cerrados.cobertura.fuera_ranking`; así el histórico no cambia cuando una persona cambia de rol o sale del equipo.

Un analista que produjo sin meta mensual conserva su producción con objetivos cero y, al cierre, permanece en la foto del equipo bajo el supervisor correspondiente. Esto es distinto de una inversión cuyo responsable no era analista.

## Orden de publicación

El frontend compatible debe publicarse antes que la migración porque `cumplimiento_metas_fn` añadirá la clave `fuera_ranking` a una respuesta validada de forma estricta. Ver [[Deploy a Hostinger]].

## Evidencia y despliegue

- Migración aplicada desde cero sobre un calco limpio del esquema productivo.
- Seis núcleos revisados con `plpgsql_check`: cero hallazgos.
- Oráculo SQL específico: analista sin meta preservado, supervisor nunca rankeado, detalle abierto/cerrado y aislamiento por rol; todo verde.
- Frontend: 2.635 pruebas unitarias, build y controles de bundle/duplicación aprobados.
- Navegador: 113 pruebas aprobadas, 26 omitidas por suites desactivadas y cero fallidas.

El frontend se publicó primero desde `main` con el release
`crm-20260902T223231Z-9b5cc36935ec`; después se aplicó y registró
`20260902202247_crm_ranking_foto_mensual_coherente` en Supabase.

La verificación real de agosto descubrió una última incoherencia únicamente en
el contador del mes abierto: existían 16 filas con puesto, pero
`total.analistas` decía 18 al sumar dos supervisores externos. Se corrigió en el
mismo núcleo existente mediante
`20260902224847_crm_conversion_total_analistas_solo_ranking`, sin cambiar las
medidas. Resultado productivo final:

- agosto: 16 analistas / 16 responsables, divisor 823, numerador 55,9 y 6,79 %;
- septiembre: 17 / 17, divisor 182, numerador 9 y 4,95 %;
- fuera del ranking en agosto: tres identidades, ninguna con puesto; S/ 65 000,
  USD 12 640 y tres operaciones conservadas en el total empresa;
- censo analítico: 30/30, huella y permisos del núcleo intactos salvo el cambio
  funcional autorizado.

Estado final: **implementado, publicado y auditado en producción**. Ver
[[Deploy a Hostinger]] y [[Rankings por mes calendario (decision 2026-09-02)]].

## Corrección del contrato frontend — 2026-09-03

La migración `20260902224847_crm_conversion_total_analistas_solo_ranking`
dejó `total.analistas` con la semántica correcta (solo responsables con puesto),
pero `ConversionMensualSchema` todavía exigía
`responsables.length + cobertura.fuera_de_roster.analistas`. En septiembre la
respuesta viva fue 17 responsables, 1 identidad externa y
`total.analistas = 17`; la RPC respondió HTTP 200, pero el cliente rechazó el
payload completo con `CONVERSION_MENSUAL_CONTRACT`.

El contrato del frontend quedó alineado: el contador se contrasta solo contra
`responsables.length`, mientras divisor, cierres y numerador continúan
reconciliándose con `fuera_de_roster`. La regresión prueba además que volver a
sumar identidades externas al contador se rechaza. Gate del frontend: 2.635
pruebas, cobertura, build, bundle y duplicación aprobados.

### Incidente y republicación segura

El primer release, `crm-20260903T162104Z-213e6fab1cf4`, se construyó desde un
worktree limpio sin copiar `app/.env`, archivo local ignorado por Git. Vite
generó un bundle sin `VITE_SUPABASE_URL` ni `VITE_SUPABASE_ANON_KEY`; el
frontend falló cerrado, mostró «El acceso con cuenta aún no está disponible
aquí» y deshabilitó `Entrar`. Se restauró inmediatamente el release previo
`crm-20260902T223231Z-9b5cc36935ec`, recuperando las sesiones mientras se
preparaba el artefacto correcto. La base de datos no se modificó durante el
incidente.

El commit `f767a5f` añadió un gate obligatorio a `release:crm`: exige el host
productivo exacto, rechaza llaves privilegiadas y comprueba que URL y llave
pública quedaron incorporadas al JavaScript emitido. Cuatro pruebas cubren
configuración válida, variables ausentes, llave secreta y bundle sin config.

La republicación correcta es
`crm-20260903T164522Z-f767a5f976f5`, SHA-256
`a915d21d7add63426f2203467884d7e38645331dc9c9c420959428cb37e2cb03`.
`version.json` sirve `build-20260903T164521412Z`; `index.html`,
`assets/index-BY99-vH0.js` y `assets/crm-api-BoAOJFi_.js` coinciden byte a byte
con el artefacto. Supabase Auth respondió HTTP 200 con la configuración
pública del bundle, el build defectuoso dejó de servirse y el ZIP público
respondió 404.
