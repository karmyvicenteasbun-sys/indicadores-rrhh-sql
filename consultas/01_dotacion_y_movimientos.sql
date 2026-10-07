-- =====================================================================
-- 01. Dotación y movimientos por mes
-- Pregunta: ¿cuántas personas hay cada mes y cuántas entran y salen?
-- Técnicas: CTE, agregación condicional, LEFT JOIN y LAG().
-- Dotación = personas en planilla en el mes (incluye a quien entró o salió ese mes).
-- =====================================================================
WITH dotacion AS (
    SELECT periodo, COUNT(*) AS dotacion
    FROM planilla_mensual
    GROUP BY periodo
),
ingresos AS (
    SELECT strftime('%Y-%m', fecha_ingreso) AS periodo, COUNT(*) AS ingresos
    FROM colaboradores
    GROUP BY 1
),
egresos AS (
    SELECT strftime('%Y-%m', fecha_egreso) AS periodo,
           COUNT(*)                                AS egresos,
           SUM(tipo_egreso = 'Renuncia voluntaria') AS renuncias,
           SUM(tipo_egreso = 'Desvinculación')      AS desvinculaciones
    FROM colaboradores
    WHERE fecha_egreso IS NOT NULL
    GROUP BY 1
)
SELECT d.periodo,
       d.dotacion,
       d.dotacion - LAG(d.dotacion) OVER (ORDER BY d.periodo) AS variacion,
       COALESCE(i.ingresos, 0)          AS ingresos,
       COALESCE(e.egresos, 0)           AS egresos,
       COALESCE(e.renuncias, 0)         AS renuncias,
       COALESCE(e.desvinculaciones, 0)  AS desvinculaciones
FROM dotacion AS d
LEFT JOIN ingresos AS i ON i.periodo = d.periodo
LEFT JOIN egresos  AS e ON e.periodo = d.periodo
ORDER BY d.periodo;
