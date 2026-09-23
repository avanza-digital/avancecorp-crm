# Cuando se publique el front, esto entra en tres comandos

**Estado al 23/09/2026.** Tres migraciones están escritas, ensayadas contra
producción y **con pestillo**. Ninguna puede entrar antes de que el front esté
vivo: el bundle actual valida esos bloques con `v.strictObject` y una clave
desconocida tumba la pantalla entera.

## 1. Comprobar que el front ya está vivo (los tres pasos, en orden)

```bash
curl -s https://crm.miavance.com/version.json          # -> buildId
ls -t CRM-Avance-Corp/releases/*.manifest.json | head  # el de ese buildId -> commit
git merge-base --is-ancestor c2c9274b <ese commit> && echo "LISTO" || echo "TODAVÍA NO"
```

`c2c9274b` es el commit que vuelve `v.optional` las cuatro claves del contrato
en los cuatro módulos del front. **Si sale «TODAVÍA NO», parar aquí.**

## 2. Aplicar, en este orden

| # | Migración | Qué hace |
|---|---|---|
| 1 | `20260922233545_crm_puerta5_declara_su_fuente.sql` | la #5 declara |
| 2 | `20260923002033_crm_puerta5_delega_en_la_mensual.sql` | la #5 delega (su preflight exige la anterior por md5) |
| 3 | `20260923012825_crm_puertas7y8_declaran_con_pestillo.sql` | la #8 declara, y la #7 lo hereda |

Las tres piden el pestillo. Se aplican así:

```bash
cd CRM-Avance-Corp
cat > /tmp/aplicar.sql <<'SQL'
begin;
set local crm.ola1_front_publicado = 'si';
SQL
# y luego, por cada migración, pegar su cuerpo sin su propio `begin;`
```

O más simple, una por una, añadiendo el `set local` al principio del fichero que
se pasa a `supabase db query --linked --file`. **Nunca editar la migración
commiteada**: se copia a un temporal y se le antepone el `set local`.

Después de cada una:
`supabase migration repair --status applied <versión> --linked`.

## 3. Comprobar

```bash
supabase db query --linked --file supabase/scripts/conversion/ensayo-cierre-unificacion.sql
```

Sella agosto de verdad, anula un cierre suyo y compara las cinco puertas, todo
con `rollback`. Tiene que decir que los cinco caminos restan lo mismo.

## 4. Y entonces sí: el rótulo en las dos pantallas que faltan

Ranking y Gestión de equipo leen la puerta #7. Hasta que la #7 declare no hay
nada que rotular allí. Cuando declare, usar `rotuloDeLaCifra` de
`app/src/lib/conversion-rotulo.ts`, igual que en el héroe de Resumen.

---

🔴 **Y lo que no depende de esto:** rotar el token de Hostinger. Se pegó en
claro dos veces.
