# Llamadas desde el celular — revisión antes de publicar (2026-10-02)

**Estado: NO PUBLICAR TODAVÍA.** F2 + F3 (PR #169 de Jhosep) se revisaron a fondo el 02/10 con Miguel:
`auditor-rls`, Codex LEVEL 3 (**BLOCK**) y un banco Supabase propio con el esquema de producción al byte.
Nada se aplicó en producción.

## Decisiones de Miguel (02/10)
- Aprueba las propuestas **#13 clientes, #14 entrantes y #15 métricas aparte**. La #14 implica comprar
  **MacroDroid Pro**.
- Ratifica las 7 decisiones provisionales de F2 y las 5 de F3. Queda por confirmarle: la regla extra de la
  decisión 4, los criterios de Claude de `MIGRACIONES.md` y la #12.

## Lo que bloquea (3 reproducidos en el banco)
1. **El reenvío delata si un número es de un lead** (rompe la #12): mismo id con otro contenido da 409 solo
   si la llamada se guardó.
2. **Gerencia ve y descarta llamadas de leads borrados**; el dueño no las ve.
3. **La perilla de entrantes guarda una entrante perdida como «pide resultado»**: la lógica de la #14 no
   existe todavía.
4. Las ambiguas revelan que un número es de varios leads de todo el CRM.
5. Hasta F4 nada enlaza la encuesta con la llamada: todo queda «pide resultado» para siempre (decisión de
   Miguel pendiente).

## Lecciones
- **Un banco de solo esquema no trae las tablas de control** (`crm.sla_operacion_control`): el gate da
  rojos que no son del CRM y deja sin probar justo la zona donde F2 se engancha. Ver
  [[Gestion Diaria F4 - cierre en copia aislada y banco Docker propio (2026-09-22)]].
- **Un test escrito sobre el comportamiento actual puede consagrar el fallo**: el bloque nuevo del gate
  exigía el 409 que la auditoría marcó como fuga.
- La clave de un celular no debe asignarse desde una sesión de Claude: la respuesta queda en la
  conversación.

## Dónde seguir
`CRM-Avance-Corp/docs/plans/llamadas-celular/REVISION-2026-10-02.md` y `HANDOFF-2026-10-03-REVISION.md`
(rama `feat/llamadas-f2`). Relacionadas: [[Llamadas desde el celular - pruebas de MacroDroid en C1 (2026-10-02)]],
[[Llamadas desde el celular - clientes como objetivo pendiente (2026-10-01)]].
