"""
Genera los datos ficticios de una embotelladora mediana (unos 500 colaboradores)
entre octubre de 2023 y septiembre de 2026, con montos en bolivianos (Bs).

Salidas (carpeta datos/):
  - colaboradores.csv     una fila por colaborador (activo o egresado)
  - planilla_mensual.csv  una fila por colaborador y mes trabajado

Todo es inventado: no hay datos de ninguna empresa real. La planilla sigue la
lógica de una planilla boliviana, simplificada para el ejemplo (ver SUPUESTOS).

Uso:
    python generar_datos.py
"""

from pathlib import Path

import numpy as np
import pandas as pd

SEMILLA = 2026
INICIO = pd.Period("2023-10", freq="M")
FIN = pd.Period("2026-09", freq="M")
DOTACION_INICIAL = 500
DOTACION_FINAL = 520

# --- Supuestos de planilla (simplificados) ---------------------------------
APORTES_PATRONALES = 0.1671      # seguro de salud 10% + riesgo profesional 1,71% + aporte solidario 3% + vivienda 2%
PROVISION_AGUINALDO = 1 / 12     # un sueldo por año
PROVISION_INDEMNIZACION = 1 / 12 # un sueldo por año de servicio
RECARGO_HORAS_EXTRA = 2.0        # la hora extra se paga al doble
HORAS_MES = 240                  # 30 días x 8 horas
SALARIO_MINIMO = 2750            # base del bono de antigüedad (supuesto fijo)
INCREMENTO_ANUAL = 0.04          # incremento salarial de cada mayo (supuesto)
# Bono de antigüedad: % sobre 3 salarios mínimos según años de servicio
ESCALA_ANTIGUEDAD = [(25, 0.50), (20, 0.42), (15, 0.34), (11, 0.26), (8, 0.18), (5, 0.11), (2, 0.05)]

# --- Estructura de la empresa ----------------------------------------------
# peso: participación en la dotación | base: tasa mensual base de renuncia
# rotativo: % de operativos en turno rotativo | horas_extra: promedio mensual
AREAS = {
    "Producción":                dict(peso=0.40, base=0.0125, rotativo=0.65, horas_extra=22),
    "Logística y Distribución":  dict(peso=0.24, base=0.0175, rotativo=0.20, horas_extra=26),
    "Ventas":                    dict(peso=0.14, base=0.0240, rotativo=0.00, horas_extra=8),
    "Mantenimiento":             dict(peso=0.08, base=0.0085, rotativo=0.50, horas_extra=18),
    "Calidad":                   dict(peso=0.06, base=0.0075, rotativo=0.40, horas_extra=12),
    "Administración y Finanzas": dict(peso=0.08, base=0.0060, rotativo=0.00, horas_extra=4),
}

NIVELES = {
    "Operativo":              dict(salario_medio=3600, factor_renuncia=1.00, edad=(27, 6)),
    "Técnico y supervisión":  dict(salario_medio=6500, factor_renuncia=0.80, edad=(32, 6)),
    "Profesional y jefatura": dict(salario_medio=12500, factor_renuncia=0.65, edad=(36, 6)),
}

MEZCLA_NIVELES = {  # Operativo, Técnico y supervisión, Profesional y jefatura
    "Producción":                [0.82, 0.13, 0.05],
    "Logística y Distribución":  [0.85, 0.11, 0.04],
    "Ventas":                    [0.82, 0.12, 0.06],
    "Mantenimiento":             [0.35, 0.55, 0.10],
    "Calidad":                   [0.45, 0.45, 0.10],
    "Administración y Finanzas": [0.40, 0.40, 0.20],
}

CARGOS = {
    "Producción": {
        "Operativo": ["Operario de línea", "Operador de llenadora", "Auxiliar de producción"],
        "Técnico y supervisión": ["Supervisor de turno"],
        "Profesional y jefatura": ["Jefe de producción", "Ingeniero de procesos"],
    },
    "Logística y Distribución": {
        "Operativo": ["Chofer repartidor", "Ayudante de reparto", "Auxiliar de almacén"],
        "Técnico y supervisión": ["Supervisor de distribución", "Encargado de almacén"],
        "Profesional y jefatura": ["Jefe de logística"],
    },
    "Ventas": {
        "Operativo": ["Preventista", "Mercaderista"],
        "Técnico y supervisión": ["Supervisor de ventas"],
        "Profesional y jefatura": ["Jefe comercial", "Analista comercial"],
    },
    "Mantenimiento": {
        "Operativo": ["Ayudante de mantenimiento"],
        "Técnico y supervisión": ["Técnico mecánico", "Técnico eléctrico"],
        "Profesional y jefatura": ["Jefe de mantenimiento"],
    },
    "Calidad": {
        "Operativo": ["Inspector de calidad"],
        "Técnico y supervisión": ["Analista de laboratorio"],
        "Profesional y jefatura": ["Jefe de calidad"],
    },
    "Administración y Finanzas": {
        "Operativo": ["Auxiliar administrativo", "Cajero"],
        "Técnico y supervisión": ["Asistente contable", "Asistente de RRHH"],
        "Profesional y jefatura": ["Contador general", "Jefe de RRHH", "Analista financiero"],
    },
}

# Estacionalidad de las horas extra: el verano y fin de año son temporada alta de bebidas
ESTACIONALIDAD = {1: 1.30, 2: 1.25, 3: 1.05, 4: 0.95, 5: 0.90, 6: 0.80,
                  7: 0.80, 8: 0.85, 9: 0.95, 10: 1.05, 11: 1.15, 12: 1.35}


def factor_antiguedad(meses):
    """Riesgo relativo de renuncia según los meses de antigüedad."""
    if meses < 3:
        return 2.0
    if meses < 6:
        return 2.4
    if meses < 12:
        return 1.7
    if meses < 24:
        return 1.0
    if meses < 60:
        return 0.6
    return 0.4


def indice_salarial(periodo):
    """Índice acumulado de incrementos de mayo desde octubre de 2023."""
    incrementos = sum(1 for anio in range(2024, periodo.year + 1)
                      if pd.Period(f"{anio}-05", freq="M") <= periodo)
    return (1 + INCREMENTO_ANUAL) ** incrementos


def porcentaje_bono_antiguedad(anios):
    for minimo, porcentaje in ESCALA_ANTIGUEDAD:
        if anios >= minimo:
            return porcentaje
    return 0.0


class Empresa:
    def __init__(self, semilla=SEMILLA):
        self.rng = np.random.default_rng(semilla)
        self.colaboradores = []

    # --- altas ---------------------------------------------------------------
    def nuevo_colaborador(self, area, nivel, fecha_ingreso, es_reemplazo=True):
        rng = self.rng
        conf_area = AREAS[area]
        edad_media, edad_desvio = NIVELES[nivel]["edad"]
        operativo_o_tecnico = nivel != "Profesional y jefatura"
        turno = "Diurno"
        if nivel == "Operativo" and rng.random() < conf_area["rotativo"]:
            turno = "Rotativo"
        elif nivel == "Técnico y supervisión" and rng.random() < conf_area["rotativo"] * 0.5:
            turno = "Rotativo"
        propension_he = 0.0
        if operativo_o_tecnico:
            factor_nivel = 1.0 if nivel == "Operativo" else 0.7
            propension_he = conf_area["horas_extra"] * factor_nivel * rng.lognormal(0, 0.35)
        colaborador = dict(
            area=area,
            nivel=nivel,
            cargo=str(rng.choice(CARGOS[area][nivel])),
            turno=turno,
            fecha_ingreso=fecha_ingreso,
            edad_ingreso=int(np.clip(round(rng.normal(edad_media, edad_desvio)), 18, 60)),
            distancia_km=round(float(np.clip(rng.lognormal(np.log(8), 0.55), 1, 35)), 1),
            # posición en la banda salarial (1 = punto medio); los ingresos recientes entran algo más bajo
            compa_ratio=round(float(np.clip(rng.normal(0.97 if es_reemplazo else 1.0, 0.08), 0.80, 1.22)), 2),
            evaluacion_desempeno=int(np.clip(round(rng.normal(3.3, 0.8)), 1, 5)),
            propension_he=propension_he,
            desapego=float(rng.normal(0, 1)),  # variable latente: no se exporta
            fecha_egreso=None,
            tipo_egreso=None,
        )
        colaborador["tasa_ausencia"] = 0.45 * np.exp(0.35 * colaborador["desapego"]) * (1.2 if turno == "Rotativo" else 1.0)
        self.colaboradores.append(colaborador)
        return colaborador

    def poblacion_inicial(self):
        rng = self.rng
        areas = list(AREAS)
        pesos = [AREAS[a]["peso"] for a in areas]
        inicio = INICIO.to_timestamp()
        for _ in range(DOTACION_INICIAL):
            area = str(rng.choice(areas, p=pesos))
            nivel = str(rng.choice(list(NIVELES), p=MEZCLA_NIVELES[area]))
            tramo = rng.random()
            if tramo < 0.22:
                meses = rng.uniform(0, 12)
            elif tramo < 0.52:
                meses = rng.uniform(12, 36)
            else:
                meses = rng.uniform(36, 180)
            fecha_ingreso = inicio - pd.Timedelta(days=int(meses * 30.4) + 1)
            self.nuevo_colaborador(area, nivel, fecha_ingreso, es_reemplazo=False)

    # --- simulación mensual ---------------------------------------------------
    def probabilidades_mes(self, colaborador, periodo):
        meses = (periodo - pd.Period(colaborador["fecha_ingreso"], freq="M")).n
        edad = colaborador["edad_ingreso"] + meses / 12
        area = AREAS[colaborador["area"]]
        p_renuncia = (
            area["base"]
            * NIVELES[colaborador["nivel"]]["factor_renuncia"]
            * factor_antiguedad(meses)
            * np.exp(0.025 * (colaborador["propension_he"] - 15))
            * (1.30 if colaborador["turno"] == "Rotativo" else 1.0)
            * np.exp(-4.0 * (colaborador["compa_ratio"] - 1))
            * np.exp(0.02 * (colaborador["distancia_km"] - 9))
            * np.exp(-0.02 * (edad - 30))
            * np.exp(0.35 * colaborador["desapego"])
        )
        p_desvinculacion = (
            0.0030
            * (2.5 if colaborador["evaluacion_desempeno"] <= 2 else 1.0)
            * (2.0 if meses < 3 else 1.0)
        )
        return min(p_renuncia, 0.30), p_desvinculacion

    def simular(self):
        rng = self.rng
        self.poblacion_inicial()
        areas = list(AREAS)
        pesos = [AREAS[a]["peso"] for a in areas]
        periodos = pd.period_range(INICIO, FIN, freq="M")
        n_meses = len(periodos)
        vacantes = []  # (area, nivel) a cubrir el mes siguiente

        for i, periodo in enumerate(periodos):
            # 1) ingresan los reemplazos y el crecimiento del mes
            activos = [c for c in self.colaboradores if c["fecha_egreso"] is None]
            objetivo = DOTACION_INICIAL + (DOTACION_FINAL - DOTACION_INICIAL) * i / (n_meses - 1)
            faltan = int(round(objetivo)) - len(activos)
            if i > 0:
                altas = list(vacantes[:max(faltan, 0)])
                while len(altas) < faltan:
                    area = str(rng.choice(areas, p=pesos))
                    altas.append((area, str(rng.choice(list(NIVELES), p=MEZCLA_NIVELES[area]))))
                for area, nivel in altas:
                    dia = int(rng.integers(1, 29))
                    fecha = periodo.to_timestamp() + pd.Timedelta(days=dia - 1)
                    self.nuevo_colaborador(area, nivel, fecha)
            vacantes = []

            # 2) egresos del mes (los que ingresaron este mes no se evalúan)
            for c in self.colaboradores:
                if c["fecha_egreso"] is not None or pd.Period(c["fecha_ingreso"], freq="M") >= periodo:
                    continue
                p_renuncia, p_desvinculacion = self.probabilidades_mes(c, periodo)
                sorteo = rng.random()
                if sorteo < p_renuncia:
                    tipo = "Renuncia voluntaria"
                elif sorteo < p_renuncia + p_desvinculacion:
                    tipo = "Desvinculación"
                else:
                    continue
                dia = int(rng.integers(1, 31))
                dia = min(dia, periodo.days_in_month)
                c["fecha_egreso"] = periodo.to_timestamp() + pd.Timedelta(days=dia - 1)
                c["tipo_egreso"] = tipo
                vacantes.append((c["area"], c["nivel"]))
        return self

    # --- salidas --------------------------------------------------------------
    def tabla_colaboradores(self):
        inicio = INICIO.to_timestamp()
        filas = [c for c in self.colaboradores if c["fecha_egreso"] is None or c["fecha_egreso"] >= inicio]
        filas.sort(key=lambda c: c["fecha_ingreso"])
        for n, c in enumerate(filas, start=1):
            c["id_colaborador"] = f"C{n:04d}"
        df = pd.DataFrame(filas)
        ultimo = FIN
        df["haber_basico_actual_bs"] = [
            round(NIVELES[c["nivel"]]["salario_medio"] * c["compa_ratio"]
                  * indice_salarial(pd.Period(c["fecha_egreso"], freq="M") if c["fecha_egreso"] is not None else ultimo), 0)
            for c in filas
        ]
        df["fecha_ingreso"] = pd.to_datetime(df["fecha_ingreso"]).dt.date
        df["fecha_egreso"] = pd.to_datetime(df["fecha_egreso"]).dt.date
        columnas = ["id_colaborador", "area", "cargo", "nivel", "turno", "fecha_ingreso", "fecha_egreso",
                    "tipo_egreso", "edad_ingreso", "distancia_km", "compa_ratio", "evaluacion_desempeno",
                    "haber_basico_actual_bs"]
        self._filas = filas
        return df[columnas]

    def tabla_planilla(self):
        rng = self.rng
        registros = []
        for c in self._filas:
            ingreso = pd.Timestamp(c["fecha_ingreso"])
            egreso = pd.Timestamp(c["fecha_egreso"]) if c["fecha_egreso"] is not None else None
            p_ingreso = pd.Period(ingreso, freq="M")
            p_egreso = pd.Period(egreso, freq="M") if egreso is not None else None
            desde = max(INICIO, p_ingreso)
            hasta = min(FIN, p_egreso) if p_egreso is not None else FIN
            for periodo in pd.period_range(desde, hasta, freq="M"):
                dias = 30
                if periodo == p_ingreso:
                    dias = 30 - min(ingreso.day, 30) + 1
                if p_egreso is not None and periodo == p_egreso:
                    dias = min(egreso.day, 30)
                proporcion = dias / 30
                haber = round(NIVELES[c["nivel"]]["salario_medio"] * c["compa_ratio"] * indice_salarial(periodo), 0)
                # ausencias: suben en los 3 meses previos a una renuncia
                antes_de_renunciar = (
                    c["tipo_egreso"] == "Renuncia voluntaria" and p_egreso is not None
                    and 0 <= (p_egreso - periodo).n <= 2
                )
                tasa = c["tasa_ausencia"] * (1.8 if antes_de_renunciar else 1.0)
                dias_ausencia = int(min(rng.poisson(tasa * proporcion), dias))
                horas_extra = 0.0
                if c["propension_he"] > 0:
                    horas_extra = c["propension_he"] * ESTACIONALIDAD[periodo.month] * rng.lognormal(0, 0.25) * proporcion
                    horas_extra = float(np.clip(round(horas_extra * 2) / 2, 0, 70))
                anios = (periodo.to_timestamp() - ingreso).days // 365
                basico_pagado = haber * proporcion
                bono_antiguedad = porcentaje_bono_antiguedad(anios) * 3 * SALARIO_MINIMO * proporcion
                monto_he = horas_extra * haber / HORAS_MES * RECARGO_HORAS_EXTRA
                total_ganado = basico_pagado + bono_antiguedad + monto_he
                aportes = total_ganado * APORTES_PATRONALES
                aguinaldo = total_ganado * PROVISION_AGUINALDO
                indemnizacion = total_ganado * PROVISION_INDEMNIZACION
                registros.append(dict(
                    periodo=str(periodo),
                    fecha_periodo=periodo.to_timestamp().date(),
                    id_colaborador=c["id_colaborador"],
                    dias_trabajados=dias,
                    dias_ausencia=dias_ausencia,
                    horas_extra=horas_extra,
                    haber_basico_bs=haber,
                    basico_pagado_bs=round(basico_pagado, 2),
                    bono_antiguedad_bs=round(bono_antiguedad, 2),
                    monto_horas_extra_bs=round(monto_he, 2),
                    total_ganado_bs=round(total_ganado, 2),
                    aportes_patronales_bs=round(aportes, 2),
                    provision_aguinaldo_bs=round(aguinaldo, 2),
                    provision_indemnizacion_bs=round(indemnizacion, 2),
                    costo_total_bs=round(total_ganado + aportes + aguinaldo + indemnizacion, 2),
                ))
        return pd.DataFrame(registros)


def main():
    carpeta = Path(__file__).resolve().parent / "datos"
    carpeta.mkdir(exist_ok=True)
    empresa = Empresa().simular()
    colaboradores = empresa.tabla_colaboradores()
    planilla = empresa.tabla_planilla()
    colaboradores.to_csv(carpeta / "colaboradores.csv", index=False, encoding="utf-8")
    planilla.to_csv(carpeta / "planilla_mensual.csv", index=False, encoding="utf-8")
    print(f"colaboradores.csv: {len(colaboradores):,} filas")
    print(f"planilla_mensual.csv: {len(planilla):,} filas")


if __name__ == "__main__":
    main()
