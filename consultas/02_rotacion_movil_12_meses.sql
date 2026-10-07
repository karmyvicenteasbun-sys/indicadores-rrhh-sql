-- =====================================================================
-- 02. Rotación voluntaria móvil de 12 meses, por área y total
-- Pregunta: ¿la rotación está subiendo o bajando, y en qué áreas?
-- Técnicas: funciones de ventana con marco ROWS BETWEEN 11 PRECEDING,
--           cláusula WINDOW y UNION ALL para el total de la empresa.
-- Rotación de 12 meses = renuncias de los últimos 12 meses / dotación promedio
-- de esos 12 meses. Solo se muestran las ventanas completas.
-- =====================================================================
WITH dotacion AS (
    SELECT p.periodo, v.area, COUNT(*) AS dotacion
    FROM planilla_mensual AS p
    JOIN v_colaboradores  AS v ON v.id_colaborador = p.id_colaborador
    GROUP BY p.periodo, v.area
),
renuncias AS (
    SELECT strftime('%Y-%m', fecha_egreso) AS periodo, area, COUNT(*) AS renuncias
    FROM v_colaboradores
    WHERE tipo_egreso = 'Renuncia voluntaria'
    GROUP BY 1, 2
),
por_area AS (
    SELECT d.periodo, d.area, d.dotacion, COALESCE(r.renuncias, 0) AS renuncias
    FROM dotacion AS d
    LEFT JOIN renuncias AS r ON r.periodo = d.periodo AND r.area = d.area
),
base AS (
    SELECT periodo, area, dotacion, renuncias FROM por_area
    UNION ALL
    SELECT periodo, 'Toda la empresa', SUM(dotacion), SUM(renuncias) FROM por_area GROUP BY periodo
),
movil AS (
    SELECT periodo, area,
           SUM(renuncias) OVER ventana AS renuncias_12m,
           AVG(dotacion)  OVER ventana AS dotacion_promedio_12m,
           COUNT(*)       OVER ventana AS meses
    FROM base
    WINDOW ventana AS (PARTITION BY area ORDER BY periodo ROWS BETWEEN 11 PRECEDING AND CURRENT ROW)
)
SELECT periodo,
       area,
       renuncias_12m,
       ROUND(dotacion_promedio_12m, 1)                         AS dotacion_promedio_12m,
       ROUND(1.0 * renuncias_12m / dotacion_promedio_12m, 4)   AS rotacion_voluntaria_12m
FROM movil
WHERE meses = 12
ORDER BY area = 'Toda la empresa' DESC, area, periodo;
