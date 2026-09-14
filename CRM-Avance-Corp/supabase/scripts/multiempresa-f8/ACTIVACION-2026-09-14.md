# Activación nominal F8 — 14/09/2026

**ACTIVO y verificado; G7 abierto.** Aprobación explícita del solicitante tras
presentar el SQL exacto y la vigencia. Referencia `F8-20260914-01`.

- SQL SHA256: `43880847b0a40a2deb0ad14d2ed9847f759652a4b8fdd10c86dfcdacaa6467bb`.
- Preparación integrada: `c6e39859f28f52575402e8986bba73a4e85aa8fd`.
- Ejecución única: 14/09/2026 13:23:51.712435 Lima.
- Vence el acceso: 21/09/2026 13:23:51.712435 Lima; cierre anticipado disponible.
- Control ON, revisión 1; cuatro participantes: Gerencia, supervisor y dos
  analistas. Roles y supervisores exactos conservados.

[Recibo saneado con las comprobaciones](activacion/evidencia-encendido-2026-09-14/recibo.json).
Selección, SQL nominal, aprobación y reversa en el registro privado
`/private/tmp/avancecorp-f8-participantes-20260914/`.

## Verificación productiva

PASS: estado inicial y final, cuentas vigentes, composición y ventana exactas,
responsable/referencia, cinco registros de auditoría con UID de sesión NULL,
RLS y ACL de las tablas de control cerrados a anon/authenticated. F3 permanece
ON; F4/F5/F6/F7 globales OFF. La capacidad del informe F7 para Gerencia sigue
OFF, comprobada por SQL; no se habilitó ese informe. Los cuatro participantes reciben capacidades F5,
escritura y F6; un supervisor ajeno permanece excluido. El supervisor piloto
ve a su analista y no al de otro equipo.

PASS: las ocho huellas observadas antes y después (contratos, cierres,
inversiones, personas, titulares, periodos, Auth y equipo) coinciden. El corte
inicial tiene 602 fuentes reales, cero brechas: Avance 579, Qorilazo 17,
Prodelco 6. Son fuentes/inversiones, no un conteo de personas distintas.
Las ventas posteriores se medirán contra su propio corte.

Las capacidades se probaron con rol SQL `authenticated` y UID local en
transacciones terminadas con ROLLBACK. NOT RUN: login/Auth/HTTP real de los
participantes y nuevas escrituras económicas de prueba. No se ejecutó reversa
productiva, pues apagaría el piloto recién autorizado. La reversa conserva sus
pruebas sintéticas aprobadas.

El primer intento con `BEGIN READ ONLY` falló porque `private.postventa_modo()`
usa SELECT FOR SHARE. Se corrigió la invocación de verificación para permitir
ese bloqueo y hacer ROLLBACK; los cinco actores pasaron. No es una modificación
del producto ni un fallo de la activación.

## Continuación

El solicitante inicia un registro real desde el analista del supervisor piloto.
Se seguirá desde el núcleo de registro hasta cartera, inversión, seguimiento y
reportes. Requisito reafirmado: cifras y datos proceden de núcleos canónicos;
no agregar funciones de lectura o cálculo desconectadas de ellos.

[Guía del primer recorrido](PRIMER-RECORRIDO-G7.md).

[ACTA-G7.md](ACTA-G7.md) conserva los casos, conciliaciones y conformidades
pendientes. Un registro exitoso no reemplaza la matriz completa de roles,
empresas y casos. Comisiones externas. F9 todavía pendiente.
