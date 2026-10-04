// Las puertas de «Bases cargadas» que usa la pantalla, en un solo objeto: la sesión real llama al servidor
// (`bases-cargadas-api`); la demo, a su espejo en memoria (`lib/bases-cargadas-demo`). La pantalla no distingue.
import {
  armarBaseCrm,
  cargarBaseLote,
  contactosDeBase,
  crearBase,
  recogerDeBase,
  repartirBase,
  seguimientoBase,
  seguimientoBaseDetalle,
  seguimientoBases,
} from './bases-cargadas-api'

export interface FuenteBases {
  seguimientoBases: typeof seguimientoBases
  seguimientoBase: typeof seguimientoBase
  seguimientoBaseDetalle: typeof seguimientoBaseDetalle
  contactosDeBase: typeof contactosDeBase
  crearBase: typeof crearBase
  cargarBaseLote: typeof cargarBaseLote
  armarBaseCrm: typeof armarBaseCrm
  repartirBase: typeof repartirBase
  recogerDeBase: typeof recogerDeBase
}

export const FUENTE_REAL: FuenteBases = {
  seguimientoBases, seguimientoBase, seguimientoBaseDetalle, contactosDeBase, crearBase, cargarBaseLote, armarBaseCrm, repartirBase, recogerDeBase,
}
