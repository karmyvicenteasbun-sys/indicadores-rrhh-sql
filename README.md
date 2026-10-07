# ¿Cuánto cuesta el ausentismo y qué dicen los indicadores de RRHH?

**Indicadores de RRHH en SQL.** Una base SQLite normalizada con colaboradores, planilla mensual y cada ausencia con su fecha, más 9 consultas que responden preguntas de gestión: dotación, rotación, ausentismo, su costo en bolivianos y alertas de sobrecarga. Las consultas usan CTE, funciones de ventana, agregación condicional y la técnica de huecos e islas.

![El ausentismo cuesta Bs 919 mil al año; la mitad es cubrir los puestos](img/01_costo_ausentismo.png)

> **Datos ficticios.** Corresponden a una embotelladora mediana de unos 500 colaboradores, entre octubre de 2023 y septiembre de 2026. Son los mismos datos de los proyectos [Costo de la rotación](https://github.com/karmyvicenteasbun-sys/costo-rotacion-people-analytics) y [Dashboard de costos de personal](https://github.com/karmyvicenteasbun-sys/dashboard-costos-personal-powerbi), más el detalle de las 8.549 ausencias. No describen a ninguna empresa real.

## Resultados (último año: oct-2025 a sep-2026)

| Pregunta | Respuesta |
|---|---|
| ¿Cuánto cuesta el ausentismo? | **Bs 918.776 al año.** La mitad son días pagados sin trabajar y la otra mitad, **horas extra al doble para cubrir los puestos**. Producción y Logística suman el **74%** del costo. |
| ¿Hay un patrón? | Los **lunes** concentran el **30%** de las faltas injustificadas y los viernes el 21%; si fueran parejas, cada día tendría el 17%. El turno rotativo falta 22% más que el diurno (1,9% contra 1,5%). |
| ¿Está concentrado en pocas personas? | El 20% de las personas con mayor factor de Bradford (ausencias cortas y repetidas) acumula el **41%** de los días de ausencia. |
| ¿Avisa algo? | Sí. En los **3 meses antes de renunciar**, la gente falta **2,1 veces más** (3,3% contra 1,6%) y más de la mitad de esas ausencias son faltas injustificadas. |
| ¿Y la rotación? | La rotación voluntaria de la empresa es **16,6%**, pero **Logística pierde el 31%** de su gente por año y viene subiendo desde febrero. El 49% de las renuncias ocurre antes del primer año. |
| ¿Qué hacer primero? | **Usar el ausentismo como alerta temprana**: una conversación de retorno después de cada falta injustificada (sobre todo los lunes) y seguimiento cuando alguien falta más de lo habitual. Además, revisar a las **35 personas** que hicieron más de 40 horas extra al mes durante 3 meses seguidos o más, casi todas en Logística y Producción. |

## Las consultas

| Archivo | Pregunta | Técnicas |
|---|---|---|
| `01_dotacion_y_movimientos.sql` | ¿Cuántas personas hay cada mes y cuántas entran y salen? | CTE, agregación condicional, `LAG()` |
| `02_rotacion_movil_12_meses.sql` | ¿La rotación sube o baja, y en qué áreas? | Ventanas con marco `ROWS BETWEEN 11 PRECEDING`, cláusula `WINDOW` |
| `03_rotacion_por_antiguedad.sql` | ¿En qué momento se va la gente? | Tramos con `VALUES`, `JOIN` por rangos, tasa por meses-persona |
| `04_ausentismo_por_area.sql` | ¿Qué áreas y turnos faltan más? | `SUM(CASE ...)`, `UNION ALL` para el total |
| `05_faltas_por_dia_de_semana.sql` | ¿Las faltas se concentran en algún día? | `strftime('%w')`, `SUM() OVER ()` |
| `06_factor_bradford.sql` | ¿Dónde se concentran los días de ausencia? | `NTILE()`, `LEFT JOIN` para incluir a quien no faltó |
| `07_costo_ausentismo.sql` | ¿Cuánto cuesta el ausentismo? | Parámetros en una tabla, `CROSS JOIN`, pivote con `MAX(CASE ...)` |
| `08_alerta_horas_extra.sql` | ¿Quién tiene sobrecarga de horas extra varios meses seguidos? | Huecos e islas con `ROW_NUMBER()` |
| `09_ausencias_antes_de_renunciar.sql` | ¿Las ausencias avisan una renuncia? | Aritmética de meses, clasificación con `CASE` |

Los resultados completos están en `resultados/`, un CSV por consulta.

### Un ejemplo: rachas de sobrecarga con huecos e islas

Si a un número de mes correlativo se le resta `ROW_NUMBER()`, los meses consecutivos de una persona dan el mismo valor y forman una misma racha:

```sql
WITH meses_altos AS (
    SELECT id_colaborador, periodo, horas_extra,
           CAST(substr(periodo, 1, 4) AS INTEGER) * 12
         + CAST(substr(periodo, 6, 2) AS INTEGER) AS mes_correlativo
    FROM planilla_mensual
    WHERE horas_extra > 40 AND periodo >= '2025-10'
),
islas AS (
    SELECT *, mes_correlativo
              - ROW_NUMBER() OVER (PARTITION BY id_colaborador ORDER BY mes_correlativo) AS isla
    FROM meses_altos
)
SELECT id_colaborador, MIN(periodo) AS desde, MAX(periodo) AS hasta, COUNT(*) AS meses_seguidos
FROM islas
GROUP BY id_colaborador, isla
HAVING COUNT(*) >= 3;
```

| id_colaborador | área | cargo | desde | hasta | meses seguidos | horas extra promedio |
|---|---|---|---|---|---:|---:|
| C0085 | Logística y Distribución | Ayudante de reparto | 2025-10 | 2026-09 | 12 | 58,0 |
| C0686 | Logística y Distribución | Auxiliar de almacén | 2025-10 | 2026-05 | 8 | 55,1 |
| C0403 | Producción | Auxiliar de producción | 2025-10 | 2026-04 | 7 | 57,6 |

### Costo del ausentismo por área

| Área | Días de ausencia | Días pagados sin trabajar (Bs) | Cobertura con horas extra (Bs) | Total (Bs) |
|---|---:|---:|---:|---:|
| Producción | 1.269 | 178.081 | 252.411 | 430.491 |
| Logística y Distribución | 694 | 98.147 | 147.451 | 245.599 |
| Ventas | 364 | 53.579 | 31.531 | 85.111 |
| Administración y Finanzas | 242 | 57.204 | 9.105 | 66.309 |
| Mantenimiento | 241 | 45.924 | 9.110 | 55.034 |
| Calidad | 173 | 26.666 | 9.566 | 36.232 |

Supuestos, guardados en la tabla `parametros` y editables:
- Los días de enfermedad y los permisos se pagan completos, con la carga patronal: aportes de 16,71% y provisiones de aguinaldo e indemnización.
- Las faltas injustificadas se descuentan del sueldo.
- En Producción y Logística se cubre con horas extra al doble el 70% de los días de ausencia de los operativos; en las demás áreas, el 30%.

| | |
|---|---|
| ![Los lunes concentran el 30% de las faltas injustificadas](img/02_faltas_por_dia.png) | ![Antes de renunciar, la gente falta 2,1 veces más](img/04_ausencias_antes_de_renunciar.png) |

![Logística pierde el 31% de su gente por año](img/03_rotacion_movil.png)

## El modelo de datos

```mermaid
erDiagram
    areas ||--o{ cargos : "id_area"
    niveles ||--o{ cargos : "id_nivel"
    cargos ||--o{ colaboradores : "id_cargo"
    colaboradores ||--o{ planilla_mensual : "id_colaborador"
    colaboradores ||--o{ ausencias : "id_colaborador"
    areas {
        int id_area PK
        text nombre
    }
    niveles {
        int id_nivel PK
        text nombre
    }
    cargos {
        int id_cargo PK
        text nombre
        int id_area FK
        int id_nivel FK
    }
    colaboradores {
        text id_colaborador PK
        int id_cargo FK
        text turno
        text fecha_ingreso
        text fecha_egreso "NULL si está activo"
        text tipo_egreso
    }
    planilla_mensual {
        text periodo PK
        text id_colaborador PK
        int dias_trabajados "días en planilla"
        int dias_ausencia
        real horas_extra
        real costo_total_bs
    }
    ausencias {
        text id_ausencia PK
        text id_colaborador FK
        text fecha_inicio
        int dias
        text tipo
    }
    parametros {
        text clave PK
        real valor
    }
```

El esquema (`sql/00_esquema.sql`) tiene claves foráneas, restricciones `CHECK` e índices, más la vista `v_colaboradores`, que junta a cada persona con su cargo, área y nivel. Al crear la base, `crear_base.py` controla que los días de ausencia del detalle coincidan con los de la planilla en cada mes.

## Estructura

```
├── sql/00_esquema.sql          tablas, restricciones, índices y vista
├── consultas/                  las 9 consultas, comentadas
├── crear_base.py               crea rrhh.db a partir de los CSV y controla la integridad
├── ejecutar_consultas.py       corre las consultas, guarda los resultados y arma los gráficos
├── generar_datos.py            genera colaboradores y planilla (semilla fija)
├── generar_ausencias.py        reparte los días de ausencia de la planilla en episodios con fecha
├── graficos.py                 estilo de los gráficos
├── requirements.txt
├── datos/                      colaboradores.csv, planilla_mensual.csv, ausencias.csv
├── resultados/                 un CSV por consulta
└── img/                        gráficos
```

## Cómo correrlo

```bash
pip install -r requirements.txt
python ejecutar_consultas.py     # crea rrhh.db si no existe y corre las 9 consultas
```

Las consultas también se pueden abrir y ejecutar en DB Browser for SQLite o DBeaver, sobre `rrhh.db`. Necesitan SQLite 3.28 o superior, que ya viene con Python 3.8 en adelante.

## Límites

- El costo es una estimación con supuestos simples. En la práctica, la seguridad social cubre parte de las bajas médicas largas, y eso hay que descontarlo con datos reales.
- El factor de Bradford sirve para ordenar las conversaciones, no para sancionar: detrás de muchas ausencias cortas puede haber una enfermedad o un problema familiar.
- Las consultas usan funciones de fecha de SQLite. Para PostgreSQL o SQL Server hay que cambiar `strftime` y `julianday` por sus equivalentes.

**Herramientas:** SQL (SQLite) · Python · pandas · matplotlib

---

### English summary

This is an HR analytics project in SQL on a fictional bottling company with about 500 employees and synthetic data from October 2023 to September 2026.
- The SQLite database is normalized, with constraints, indexes and a view. Nine commented queries cover headcount, rolling 12-month turnover, tenure-based turnover rates, absenteeism, the Bradford factor, the cost of absence and overtime-overload streaks.
- The queries use CTEs, window functions and gaps-and-islands.

Key findings: absence costs about Bs 0.92 million a year, and half of that is overtime to cover the missing person. Unjustified absences cluster on Mondays. People are absent 2.1 times more often in the three months before they resign.

---

Vicente Asbun · [LinkedIn](https://www.linkedin.com/in/vicente-antonio-asbun-karmy-30aa19164/)
