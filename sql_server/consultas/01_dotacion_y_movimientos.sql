-- =====================================================================
-- 01. Dotación y movimientos por mes (versión SQL Server)
-- Pregunta: ¿cuántas personas hay cada mes y cuántas entran y salen?
-- Técnicas: CTE, agregación condicional con CASE, LEFT JOIN y LAG().
-- CONVERT(CHAR(7), fecha, 126) devuelve el mes como 'AAAA-MM'.
-- =====================================================================
WITH dotacion AS (
    SELECT periodo, COUNT(*) AS dotacion
    FROM dbo.planilla_mensual
    GROUP BY periodo
),
ingresos AS (
    SELECT CONVERT(CHAR(7), fecha_ingreso, 126) AS periodo, COUNT(*) AS ingresos
    FROM dbo.colaboradores
    GROUP BY CONVERT(CHAR(7), fecha_ingreso, 126)
),
egresos AS (
    SELECT CONVERT(CHAR(7), fecha_egreso, 126) AS periodo,
           COUNT(*)                                                         AS egresos,
           SUM(CASE WHEN tipo_egreso = N'Renuncia voluntaria' THEN 1 ELSE 0 END) AS renuncias,
           SUM(CASE WHEN tipo_egreso = N'Desvinculación' THEN 1 ELSE 0 END)      AS desvinculaciones
    FROM dbo.colaboradores
    WHERE fecha_egreso IS NOT NULL
    GROUP BY CONVERT(CHAR(7), fecha_egreso, 126)
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
