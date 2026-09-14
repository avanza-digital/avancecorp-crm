# Verificación del completado F8 — 13/09/2026

**PASS, banco sintético local:** 34 comprobaciones con 598 fuentes, SQL generado
desde la plantilla real, restricciones y triggers activos:

1. rechaza una preimagen financiera caducada.
2. rechaza otra cuenta con el documento.
3. exige confirmación multirrol.
4. exige la auditoría original del documento.
5. rechaza conformidad ausente.
6. rechaza versión ausente.
7. rechaza versión nula.
8. rechaza conformidad nula.
9. rechaza multirrol ausente.
10. rechaza multirrol nulo.
11. rechaza documento duplicado en el lote.
12. rechaza origen duplicado en el lote.
13. exige partición exacta de fuentes.
14. rechaza intercambiar la marca multirrol entre personas.
15. operación ausente nunca convierte aplicación en reversa.
16. generador conserva texto literal con comillas y marcadores de plantilla.
17. rechaza documento original enmascarado.
18. exige F4 apagada.
19. rechaza suplantar un actor humano.
20. ensayo con ROLLBACK conserva identidades y hechos.
21. aplica siete identidades, resuelve diez fuentes y conserva cuatro demos.
22. triggers dejan siete gestiones de responsable sin tareas ni actor suplantado.
23. reaplicación rechazada sin duplicar.
24. cuenta analista sin enlace económico ni cambio de rol.
25. RLS Portal sin ampliación; núcleo F5 limita las siete personas al responsable.
26. reversa bloqueada ante una nueva relación de cotitularidad.
27. reversa bloqueada si cambió la revisión histórica.
28. reversa bloqueada si hubo otra gestión.
29. reversa conserva historia y restaura cobertura previa sin mover dinero.
30. reversa restaura exactamente la revisión F2 multirrol.
31. índice parcial permite resolver el DNI después de la reversa (ensayo revertido).
32. tras reversa el puente histórico exige reconciliación explícita para reenlazar.
33. dos sesiones; colisión PASAPORTE concurrente aborta el lote DNI entero.
34. base sintética original conservada.

Las pruebas de permisos cubren RLS Portal con `authenticated` y claims sintéticos
y el núcleo de autorización F5: cero personas del lote para el analista y siete
para el responsable original. No son llamadas HTTP ni un encendido F5; ese gate
sigue bloqueado por las fuentes demo.

Los casos financieros comparan perfiles, contratos, cierres sin su enlace,
inversiones, capital derivado y Auth. La plantilla compara además titulares,
leads sin enlace/timestamp y titulares relacionales en la misma transacción.

**PASS, compatibilidad observada:** 33 funciones utilizadas directamente o por
triggers de tablas mutadas tienen la misma huella en producción y en el banco
de origen. Lectura administrativa, sin cambios; no certifica todo el esquema
ni las dependencias transitivas. Revalidar antes de la ejecución productiva.

**PASS, censo vigente:** lectura `REPEATABLE READ READ ONLY` del 13/09 a las
21:16:09 Lima, terminada con ROLLBACK. Conserva diez huecos reales y cuatro demo;
al reconstruir el lote desde esa lectura coincide exactamente con el lote
privado congelado. No se actualizaron preimágenes silenciosamente.

**PASS, verificaciones locales:** parseo AST de ambos Python;
`npm run check:scripts`; `npm run test:edge-preflight`.
`seed:preflight` y `test:rls:preflight` pasaron con variables ficticias explícitas
y destino loopback: no abrieron conexiones. Su primer intento falló por falta
de `SUPABASE_URL`; no se cargaron secretos ni se confundió preflight con RLS real.

**NOT RUN:** SQL productivo (incluido el ensayo con ROLLBACK), matriz RLS HTTP
completa, prueba visual F5, alta económica completa durante F8 y activación.
La propuesta requiere aprobación del SQL exacto. Los cuatro casos demo y F8
OFF impiden afirmar cobertura operativa completa. Build frontend no aplica:
no se modificaron producto web, dependencias ni tipos de esquema.

La revisión de Claude y las decisiones del PRIMARY quedan por separado en
[REVISION-CLAUDE.md](REVISION-CLAUDE.md). Un dictamen no sustituye estas pruebas.

Medición con 598 fuentes sintéticas: ensayo 0,480 s; aplicación 0,483 s; reversa
0,469 s. Incluye el proceso psql local. El timeout de bloqueo de tres segundos
limita la espera, no la duración de los candados: se conservan hasta terminar
la transacción. La medición no garantiza una duración productiva; el resto del
stock/historia y la concurrencia pueden diferir.
