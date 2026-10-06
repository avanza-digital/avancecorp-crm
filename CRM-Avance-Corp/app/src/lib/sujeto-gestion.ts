import * as v from 'valibot'
const Uuid = v.pipe(v.string(), v.uuid())
export const camposIdentidadCliente = {
  sujeto_tipo: v.picklist(['perfil', 'inversionista']), sujeto_id: v.nullable(Uuid), sujeto_nombre: v.pipe(v.string(), v.minLength(1)),
  inversionista_id: v.nullable(Uuid), perfil_id: v.nullable(Uuid), identidad_visible: v.boolean(),
}
export const IdentidadClienteSchema = v.pipe(v.object(camposIdentidadCliente), v.check(i => i.identidad_visible
  ? i.sujeto_tipo === 'inversionista' ? i.sujeto_id !== null && i.inversionista_id === i.sujeto_id && i.perfil_id === null
    : i.sujeto_id !== null && i.perfil_id === i.sujeto_id
  : i.sujeto_id === null && i.inversionista_id === null && i.perfil_id === null))
export function identidadClienteValida(valor: unknown): boolean { return v.safeParse(IdentidadClienteSchema, valor).success }
