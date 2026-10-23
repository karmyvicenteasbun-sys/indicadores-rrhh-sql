-- =====================================================================
-- 02. Rotación voluntaria móvil de 12 meses, por área y total (SQL Server)
-- Pregunta: ¿la rotación está subiendo o bajando, y en qué áreas?
-- Técnicas: funciones de ventana con marco ROWS BETWEEN 11 PRECEDING y
--           UNION ALL para el total de la empresa. La cláusula WINDOW solo
--           existe desde SQL Server 2022, así que la ventana se repite.
-- AVG() de un entero devuelve un entero en SQL Server: por eso 1.0 * dotacion.
-- =====================================================================
WITH dotacion AS (
    SELECT p.periodo, v.area, COUNT(*) AS dotacion
    FROM dbo.planilla_mensual AS p
    JOIN dbo.v_colaboradores  AS v ON v.id_colaborador = p.id_colaborador
    GROUP BY p.periodo, v.area
),
renuncias AS (
    SELECT CONVERT(CHAR(7), fecha_egreso, 126) AS periodo, area, COUNT(*) AS renuncias
    FROM dbo.v_colaboradores
    WHERE tipo_egreso = N'Renuncia voluntaria'
    GROUP BY CONVERT(CHAR(7), fecha_egreso, 126), area
),
por_area AS (
    SELECT d.periodo, d.area, d.dotacion, COALESCE(r.renuncias, 0) AS renuncias
    FROM dotacion AS d
    LEFT JOIN renuncias AS r ON r.periodo = d.periodo AND r.area = d.area
),
base AS (
    SELECT periodo, area, dotacion, renuncias FROM por_area
    UNION ALL
    SELECT periodo, N'Toda la empresa', SUM(dotacion), SUM(renuncias) FROM por_area GROUP BY periodo
),
movil AS (
    SELECT periodo, area,
           SUM(renuncias)       OVER (PARTITION BY area ORDER BY periodo ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS renuncias_12m,
           AVG(1.0 * dotacion)  OVER (PARTITION BY area ORDER BY periodo ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS dotacion_promedio_12m,
           COUNT(*)             OVER (PARTITION BY area ORDER BY periodo ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS meses
    FROM base
)
SELECT periodo,
       area,
       renuncias_12m,
       ROUND(dotacion_promedio_12m, 1)                        AS dotacion_promedio_12m,
       ROUND(1.0 * renuncias_12m / dotacion_promedio_12m, 4)  AS rotacion_voluntaria_12m
FROM movil
WHERE meses = 12
ORDER BY CASE WHEN area = N'Toda la empresa' THEN 0 ELSE 1 END, area, periodo;
