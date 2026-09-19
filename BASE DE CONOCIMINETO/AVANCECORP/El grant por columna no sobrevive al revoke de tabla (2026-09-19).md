# El grant por columna no sobrevive al revoke de tabla (2026-09-19)

Trampa del servidor, medida en el banco (PostgreSQL 17) el 19/09/2026 al ensayar
`20260919211105` (grant por columna de `alta_manual` y `creado_por` en `crm.leads`).

## El hecho

Un `revoke select on crm.leads from authenticated` de **tabla** arrastra las ACL
**por columna** del mismo privilegio: `tenencia_desde` pasa de
`{authenticated=r, service_role=r}` a `{service_role=r}`, y `genero` pierde su
`r` pero conserva su `w`. Es la semántica documentada de PostgreSQL: «al revocar
privilegios sobre una tabla, se revocan también los privilegios de columna
correspondientes».

## Qué significa para la casa

- Las notas de `20260723120000` y `20260725012707` prometen que el grant por
  columna es «la única red si alguien revoca el grant de tabla». **No lo es.**
- Lo que sí vale: convención y registro. Si algún día se pasa a privilegios por
  columna (revoke de tabla + grant columna a columna), las columnas con grant
  explícito son la lista a reponer, y PostgREST no las pierde por un olvido.
- Al revés sí funciona como uno espera: con la tabla concedida, revocar una
  columna suelta no cierra nada (la tabla la sigue cubriendo).

## Cómo probarlo sin escribir nada

```sql
begin;
revoke select on crm.leads from authenticated;
select attname, attacl from pg_attribute
 where attrelid='crm.leads'::regclass and attname in ('tenencia_desde','genero');
rollback;
```

Relacionado con [[Procedencia del lead - sistema o manual (2026-09-19)]] y con
[[Revocar a anon no basta]] (misma familia: lo que crees que cierra, no cierra).
