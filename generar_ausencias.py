"""
Genera datos/ausencias.csv: el detalle de cada ausencia (fecha, días y tipo).

Parte de la planilla mensual (datos/planilla_mensual.csv, que trae los días de
ausencia de cada persona en cada mes) y reparte esos días en episodios con fecha.
Los totales por persona y mes coinciden exactamente con la planilla.

Supuestos (ficticios):
  - Tres tipos de ausencia: enfermedad con baja médica (1 a 3 días seguidos),
    permiso con goce de haber (1 día) y falta injustificada (1 día).
  - Las faltas injustificadas caen más en lunes y viernes.
  - En los 3 meses previos a una renuncia suben las faltas injustificadas.
  - Se trabaja de lunes a sábado.

Uso:
    python generar_ausencias.py
"""

from pathlib import Path

import numpy as np
import pandas as pd

SEMILLA = 2026
TIPOS = ["Enfermedad con baja médica", "Permiso con goce de haber", "Falta injustificada"]
MEZCLA_NORMAL = [0.42, 0.22, 0.36]
MEZCLA_ANTES_DE_RENUNCIAR = [0.30, 0.15, 0.55]
DURACION_ENFERMEDAD = {1: 0.45, 2: 0.35, 3: 0.20}
# Peso de cada día para las faltas injustificadas (lunes = 0 ... sábado = 5)
PESO_DIA_FALTA = np.array([0.28, 0.14, 0.12, 0.13, 0.21, 0.12])


def dias_habiles(desde, hasta):
    dias = pd.date_range(desde, hasta, freq="D")
    return dias[dias.dayofweek < 6]


def repartir_mes(rng, dias_ausencia, habiles, mezcla):
    """Reparte los días de ausencia del mes en episodios sin superponerlos."""
    libres = list(habiles)
    episodios = []
    restantes = dias_ausencia
    while restantes > 0 and libres:
        tipo = TIPOS[rng.choice(3, p=mezcla)]
        largo = 1
        if tipo == TIPOS[0]:
            largo = int(rng.choice(list(DURACION_ENFERMEDAD), p=list(DURACION_ENFERMEDAD.values())))
        largo = min(largo, restantes)
        if tipo == TIPOS[2]:
            pesos = PESO_DIA_FALTA[[d.dayofweek for d in libres]]
            inicio = libres[rng.choice(len(libres), p=pesos / pesos.sum())]
        else:
            inicio = libres[rng.integers(len(libres))]
        # Días seguidos libres desde el inicio (si no alcanzan, el episodio se acorta)
        posicion = libres.index(inicio)
        tramo = [inicio]
        while len(tramo) < largo and posicion + len(tramo) < len(libres):
            siguiente = libres[posicion + len(tramo)]
            if (siguiente - tramo[-1]).days > 2:  # no saltar más que el domingo
                break
            tramo.append(siguiente)
        for dia in tramo:
            libres.remove(dia)
        episodios.append((tramo[0], tramo[-1], len(tramo), tipo))
        restantes -= len(tramo)
    return episodios


def main():
    carpeta = Path(__file__).resolve().parent / "datos"
    rng = np.random.default_rng(SEMILLA)
    colaboradores = pd.read_csv(carpeta / "colaboradores.csv", parse_dates=["fecha_ingreso", "fecha_egreso"])
    planilla = pd.read_csv(carpeta / "planilla_mensual.csv", parse_dates=["fecha_periodo"])
    planilla = planilla[planilla["dias_ausencia"] > 0].merge(
        colaboradores[["id_colaborador", "fecha_ingreso", "fecha_egreso", "tipo_egreso"]], on="id_colaborador")

    filas = []
    for fila in planilla.itertuples(index=False):
        inicio_mes = fila.fecha_periodo
        fin_mes = inicio_mes + pd.offsets.MonthEnd(0)
        desde = max(inicio_mes, fila.fecha_ingreso)
        hasta = min(fin_mes, fila.fecha_egreso) if pd.notna(fila.fecha_egreso) else fin_mes
        antes_de_renunciar = (fila.tipo_egreso == "Renuncia voluntaria"
                              and 0 <= (fila.fecha_egreso.to_period("M") - inicio_mes.to_period("M")).n <= 2)
        mezcla = MEZCLA_ANTES_DE_RENUNCIAR if antes_de_renunciar else MEZCLA_NORMAL
        habiles = dias_habiles(desde, hasta)
        episodios = repartir_mes(rng, int(fila.dias_ausencia), habiles, mezcla)
        if sum(e[2] for e in episodios) != fila.dias_ausencia:
            raise ValueError(f"No cuadran los días de {fila.id_colaborador} en {fila.periodo}")
        filas += [(fila.id_colaborador, *e) for e in episodios]

    ausencias = pd.DataFrame(filas, columns=["id_colaborador", "fecha_inicio", "fecha_fin", "dias", "tipo"])
    ausencias = ausencias.sort_values(["fecha_inicio", "id_colaborador"], kind="stable").reset_index(drop=True)
    ausencias.insert(0, "id_ausencia", [f"A{i:05d}" for i in range(1, len(ausencias) + 1)])
    for columna in ["fecha_inicio", "fecha_fin"]:
        ausencias[columna] = ausencias[columna].dt.date
    ausencias.to_csv(carpeta / "ausencias.csv", index=False, encoding="utf-8")
    print(f"ausencias.csv: {len(ausencias):,} episodios, {ausencias['dias'].sum():,} días")


if __name__ == "__main__":
    main()
