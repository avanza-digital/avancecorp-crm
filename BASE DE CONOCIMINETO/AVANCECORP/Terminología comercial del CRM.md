# Terminología comercial del CRM

## Regla canónica

La denominación visible y de negocio para quien gestiona la cartera es **Analista**. La interfaz, los textos de ayuda, los datos demo, los reportes y las pruebas de aceptación deben usar «Analista», nunca «Vendedor».

## Compatibilidad técnica

Los contratos heredados no se renombran mientras formen parte de interfaces técnicas estables. Esto incluye:

- el valor `rol_crm = 'vendedor'`, columnas como `vendedor_id` y arreglos como
  `vendedor_ids_visibles`;
- nombres de archivos, funciones, tipos, símbolos, rutas y claves de fixtures
  como `vend*`;
- campos heredados `asesor_*` y sentinelas técnicos como `'asesor'` y
  `'sin_asesor'`;
- frases legítimas dirigidas al cliente, como «tu asesor», cuando nombran su
  relación de atención y no el rol comercial interno del sistema.

La distinción evita dos clases de divergencia: el lenguaje comercial debe ser uniforme, y los contratos técnicos deben conservar compatibilidad hacia atrás.

## Alcance

Esta regla aplica a toda nueva funcionalidad y, al modificar una pantalla o flujo existente, a su texto visible y sus expectativas de prueba asociadas. En prosa, «analista» es un sustantivo común; «Analista» se reserva para la etiqueta exacta del rol o el inicio de una oración. No obliga a reescribir el historial de migraciones, capturas históricas, citas ni contratos internos: una nota posterior registra el cambio sin alterar la evidencia original.

Relacionadas: [[Rol Analista]], [[Fusión asesor-analista]], [[Auditoría backend Gestión de cartera 2026-08-28]].
