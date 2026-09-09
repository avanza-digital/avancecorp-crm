# G5 — evidencia de aceptación sintética

Fecha local: 08/09/2026. Candidata funcional implementada, con F4/F5 productivas
apagadas. No se usaron personas, depósitos ni cuentas reales como fixtures.

| Gate | Resultado |
|---|---|
| Lecturas HTTP/RLS, filtros, totales, historia sin links, matriz de roles, búsqueda ajena, baja y traslado | PASS: 12 pruebas |
| Qorilazo → Prodelco / repetición / Avance, acceso real local, depósito único, revisión y recuperación, proxy documental | PASS: 7 pruebas |
| Fusión real por preview/hash, perfil/tasa/origen conservados en aumento; origen ajeno rechazado | PASS: 1 prueba |
| No contactar, documento no verificado, perfil inactivo, baja neutral, sin responsable, paginación, cobertura y multirrol | PASS: 8 pruebas |
| Avance → Qorilazo, mes sellado, fecha comercial/imputación distinta y anulación sin retirar capital | PASS: 1 prueba |
| PDF PEN/USD pendiente → fallo transitorio → recuperación del mismo job/snapshot/contrato, descarga idéntica por F5 | PASS: 3 pruebas |
| Frontera documental: sesión, origen, UUID, ruta, tamaño/streaming, integridad y credencial de servicio | PASS: 4 pruebas |
| Edición concurrente del lead y auditoría sin amplificar cada refetch | PASS: 2 pruebas |
| `npm run check:all` tras integrar Citas de Main (`2135fa4`) | PASS: lint, TypeScript, 3.127 tests en 221 archivos, cobertura, configuración de release, build, bundle y duplicación; 147 Playwright PASS y 26 skip ya declarados |
| Siete recorridos F5, incluido tres empresas y PEN/USD | PASS integrados en el gate completo; además los siete pasan con configuración CI y un worker |
| `check:scripts`, seed/RLS preflight con variables locales, `test:edge-preflight`, Deno check documental | PASS |
| Introspección postgres-meta v0.99.0 de los seis nodos F5 | PASS: coincide exactamente, conservando los tipos ajenos presentes en Main |
| Replay de SQL exacto en copia nueva y reversa sin pérdida | PASS: funciones publicadas, Auth, identidades, fuentes, dinero y banderas intactos |
| Supabase db lint local CRM/private | PASS sin errores; avisos preexistentes fuera de F5. El banco incorpora pg_cron sin jobs; no se activan tareas productivas |
| Revisión Claude y evaluación del PRIMARY | Ejecutada; hallazgos corregidos o contrastados con el contrato/catálogo. [Evaluación](REVISION.md) |
| Revisión visual | Capturas reales de navegador de escritorio, móvil 390 px, roles y revisión/confirmación; 8 páginas de PDF PEN y USD verificadas sin cambios a plantilla/fonts/assets |
| Revisión personal de Miguel | Propuesta visual bien recibida; solicitó conservar la coherencia con el CRM. Ajustes realizados y verificados en [ACABADO-VISUAL.md](ACABADO-VISUAL.md) |
| Lector de pantalla manual | NOT RUN: se verificaron nombres accesibles, teclado, foco, diálogos y estados anunciados automáticamente; no se afirma una sesión manual de VoiceOver |
| Advisors / gate de datos / carga en producción y despliegue F5 | NOT RUN: fase de desarrollo sintético, sin instalación ni encendido productivo. Ejecutar con el destino y artefacto aprobados |

Las ocho suites de banco suman **38 pruebas** y se ejecutan secuencialmente.

Tras la revisión visual de Miguel se ajustaron componentes, espacios y lectura
en móvil. El gate completo volvió a pasar con 3.127 pruebas unitarias y 147 E2E;
se inspeccionaron 13 capturas adicionales entre 320 y 1.440 px. Este ajuste no
cambia el backend cuya evidencia se conserva arriba. Detalle y capturas:
[ACABADO-VISUAL.md](ACABADO-VISUAL.md).

El primer CI remoto (`257af26`, ejecución `34302179500`) aprobó calidad y los
siete recorridos F5; fallaron ocho casos antiguos de Seguimiento exclusivamente
al escribir capturas en `/private/tmp`, que no existe en el runner Linux.
Se sustituyen por `test.info().outputPath`, aislado por prueba/reintento, y CI
conserva también `test-results/`. Se mantiene el fallo original en el respaldo;
la comprobación remota posterior se registra en el manifiesto privado de cierre.
La suite corregida de Seguimiento (14 casos) y el gate completo posterior pasan
en local; el último código integrado verificado es `45c7201`.

La UI incluye recuperación tras respuesta perdida, recarga, corrección pendiente,
borrador corrupto, revocación con ficha abierta, retorno de foco y filtros,
descarga cancelada y banca estable al refrescar. Una inversión no se anuncia
como confirmada por haber preparado la solicitud o cargado el comprobante.

El ensayo PDF usa handler y renderer publicados sin cambios, ejecutados en Node
con adaptadores HTTP hacia Auth/PostgREST/Storage reales del banco; no se etiqueta
ese arnés como una ejecución del entrypoint Deno. El nuevo entrypoint documental
pasa `deno check`; el runtime desplegado se comprueba al publicarlo.

Fuentes y resultados del censo productivo siguen en [CONTRATO.md](CONTRATO.md).
Sus huecos se resuelven con lotes F4 revisados antes del encendido, no mediante
un backfill global ni mostrando una suma parcial. No se implementaron comisiones.
